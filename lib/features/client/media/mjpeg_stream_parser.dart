import 'dart:convert';
import 'dart:typed_data';

class MjpegStreamParser {
  static final _headerEnd = Uint8List.fromList([13, 10, 13, 10]);
  static final _contentLengthPattern = RegExp(
    r'^content-length:([^\r\n]*)\r?$',
    caseSensitive: false,
    multiLine: true,
  );
  static final _unsignedIntegerPattern = RegExp(r'^\d+$');
  static final _sequencePattern = RegExp(
    r'^x-miucam-sequence:[ \t]*(\d+)[ \t]*\r?$',
    caseSensitive: false,
    multiLine: true,
  );
  static final _capturedAtPattern = RegExp(
    r'^x-miucam-captured-at-ms:[ \t]*(\d+)[ \t]*\r?$',
    caseSensitive: false,
    multiLine: true,
  );
  static final _sentAtPattern = RegExp(
    r'^x-miucam-sent-at-ms:[ \t]*(\d+)[ \t]*\r?$',
    caseSensitive: false,
    multiLine: true,
  );
  static final _capturedMonoPattern = RegExp(
    r'^x-miucam-captured-mono-us:[ \t]*(\d+)[ \t]*\r?$',
    caseSensitive: false,
    multiLine: true,
  );
  static final _encodeDurationPattern = RegExp(
    r'^x-miucam-encode-duration-us:[ \t]*(\d+)[ \t]*\r?$',
    caseSensitive: false,
    multiLine: true,
  );
  static final _traceIdPattern = RegExp(
    r'^x-miucam-trace-id:[ \t]*([^\r\n]+)\r?$',
    caseSensitive: false,
    multiLine: true,
  );
  static const _maxHeaderBytes = 16 * 1024;
  static const _maxFrameBytes = 2 * 1024 * 1024;

  final _headerBytes = <int>[];
  _MjpegParserState _state = _MjpegParserState.header;
  Uint8List? _frameBuffer;
  int _frameOffset = 0;
  int _discardBodyBytes = 0;
  bool _trailingCarriageReturn = false;
  int? _frameSequence;
  int? _frameCapturedAtMs;
  int? _frameSentAtMs;
  int? _frameCapturedAtMonoUs;
  int? _frameEncodeDurationUs;
  String? _frameTraceId;

  int _bytesReceived = 0;
  int _framesParsed = 0;
  int _keepAliveParts = 0;
  int _invalidParts = 0;
  int _oversizedHeaders = 0;
  int _oversizedFrames = 0;
  int _bodyBytesCopied = 0;
  int _peakHeaderBytes = 0;
  int _peakFrameBytes = 0;

  int get bufferedBytes =>
      _headerBytes.length + _frameOffset + (_trailingCarriageReturn ? 1 : 0);

  MjpegParserMetrics get metrics => MjpegParserMetrics(
        bytesReceived: _bytesReceived,
        framesParsed: _framesParsed,
        keepAliveParts: _keepAliveParts,
        invalidParts: _invalidParts,
        oversizedHeaders: _oversizedHeaders,
        oversizedFrames: _oversizedFrames,
        bodyBytesCopied: _bodyBytesCopied,
        peakHeaderBytes: _peakHeaderBytes,
        peakFrameBytes: _peakFrameBytes,
        bufferedBytes: bufferedBytes,
      );

  List<Uint8List> add(Uint8List chunk) =>
      addFrames(chunk).map((frame) => frame.jpeg).toList(growable: false);

  List<MjpegStreamFrame> addFrames(Uint8List chunk) {
    if (chunk.isEmpty) return const [];
    _bytesReceived += chunk.length;
    final frames = <MjpegStreamFrame>[];
    var offset = 0;
    while (offset < chunk.length) {
      switch (_state) {
        case _MjpegParserState.header:
          _consumeHeaderByte(chunk[offset++]);
        case _MjpegParserState.body:
          final frame = _frameBuffer!;
          final remaining = frame.length - _frameOffset;
          final available = chunk.length - offset;
          final copied = remaining < available ? remaining : available;
          frame.setRange(
            _frameOffset,
            _frameOffset + copied,
            chunk,
            offset,
          );
          _frameOffset += copied;
          _bodyBytesCopied += copied;
          offset += copied;
          if (_frameOffset == frame.length) {
            frames.add(MjpegStreamFrame(
              jpeg: frame,
              sequence: _frameSequence,
              capturedAtMs: _frameCapturedAtMs,
              sentAtMs: _frameSentAtMs,
              capturedAtMonoUs: _frameCapturedAtMonoUs,
              encodeDurationUs: _frameEncodeDurationUs,
              traceId: _frameTraceId,
            ));
            _framesParsed++;
            _clearFrame();
            _beginTrailingCrlf();
          }
        case _MjpegParserState.discardBody:
          final available = chunk.length - offset;
          final discarded =
              _discardBodyBytes < available ? _discardBodyBytes : available;
          _discardBodyBytes -= discarded;
          offset += discarded;
          if (_discardBodyBytes == 0) _beginTrailingCrlf();
        case _MjpegParserState.trailingCrlf:
          if (!_trailingCarriageReturn) {
            if (chunk[offset] == 13) {
              _trailingCarriageReturn = true;
              offset++;
            } else {
              _state = _MjpegParserState.header;
            }
            continue;
          }
          if (chunk[offset] == 10) {
            offset++;
          } else {
            _appendHeaderByte(13);
          }
          _trailingCarriageReturn = false;
          _state = _MjpegParserState.header;
      }
    }
    return frames;
  }

  void reset() {
    _headerBytes.clear();
    _state = _MjpegParserState.header;
    _clearFrame();
    _discardBodyBytes = 0;
    _trailingCarriageReturn = false;
    _bytesReceived = 0;
    _framesParsed = 0;
    _keepAliveParts = 0;
    _invalidParts = 0;
    _oversizedHeaders = 0;
    _oversizedFrames = 0;
    _bodyBytesCopied = 0;
    _peakHeaderBytes = 0;
    _peakFrameBytes = 0;
  }

  void _consumeHeaderByte(int byte) {
    _appendHeaderByte(byte);
    if (!_endsWithHeaderTerminator()) {
      if (_headerBytes.length > _maxHeaderBytes) {
        _oversizedHeaders++;
        final suffix = _headerBytes.sublist(
          _headerBytes.length - _headerEnd.length + 1,
        );
        _headerBytes
          ..clear()
          ..addAll(suffix);
      }
      return;
    }

    final headerLength = _headerBytes.length - _headerEnd.length;
    final header = latin1.decode(
      Uint8List.fromList(_headerBytes.sublist(0, headerLength)),
      allowInvalid: true,
    );
    _headerBytes.clear();
    final contentLength = _contentLength(header);
    if (contentLength == null || contentLength < 0) {
      _invalidParts++;
      return;
    }
    if (contentLength == 0) {
      _keepAliveParts++;
      _beginTrailingCrlf();
      return;
    }
    if (contentLength > _maxFrameBytes) {
      _oversizedFrames++;
      _discardBodyBytes = contentLength;
      _state = _MjpegParserState.discardBody;
      return;
    }

    _frameBuffer = Uint8List(contentLength);
    _frameOffset = 0;
    _frameSequence = _headerInt(header, _sequencePattern);
    _frameCapturedAtMs = _headerInt(header, _capturedAtPattern);
    _frameSentAtMs = _headerInt(header, _sentAtPattern);
    _frameCapturedAtMonoUs = _headerInt(header, _capturedMonoPattern);
    _frameEncodeDurationUs = _headerInt(header, _encodeDurationPattern);
    _frameTraceId = _headerText(header, _traceIdPattern);
    if (contentLength > _peakFrameBytes) _peakFrameBytes = contentLength;
    _state = _MjpegParserState.body;
  }

  void _appendHeaderByte(int byte) {
    _headerBytes.add(byte);
    if (_headerBytes.length > _peakHeaderBytes) {
      _peakHeaderBytes = _headerBytes.length;
    }
  }

  bool _endsWithHeaderTerminator() {
    if (_headerBytes.length < _headerEnd.length) return false;
    final start = _headerBytes.length - _headerEnd.length;
    for (var index = 0; index < _headerEnd.length; index++) {
      if (_headerBytes[start + index] != _headerEnd[index]) return false;
    }
    return true;
  }

  void _beginTrailingCrlf() {
    _state = _MjpegParserState.trailingCrlf;
    _trailingCarriageReturn = false;
  }

  void _clearFrame() {
    _frameBuffer = null;
    _frameOffset = 0;
    _frameSequence = null;
    _frameCapturedAtMs = null;
    _frameSentAtMs = null;
    _frameCapturedAtMonoUs = null;
    _frameEncodeDurationUs = null;
    _frameTraceId = null;
  }

  int? _contentLength(String header) {
    final matches = _contentLengthPattern.allMatches(header).iterator;
    if (!matches.moveNext()) return null;
    final value = matches.current.group(1)?.trim() ?? '';
    // Ambiguous lengths and numeric prefixes of malformed values would move
    // the body boundary and turn subsequent valid frames into JPEG garbage.
    if (matches.moveNext() || !_unsignedIntegerPattern.hasMatch(value)) {
      return null;
    }
    return int.tryParse(value);
  }

  int? _headerInt(String header, RegExp pattern) {
    final match = pattern.firstMatch(header);
    if (match == null) return null;
    return int.tryParse(match.group(1) ?? '');
  }

  String? _headerText(String header, RegExp pattern) {
    final value = pattern.firstMatch(header)?.group(1)?.trim();
    return value == null || value.isEmpty ? null : value;
  }
}

enum _MjpegParserState { header, body, discardBody, trailingCrlf }

class MjpegParserMetrics {
  const MjpegParserMetrics({
    required this.bytesReceived,
    required this.framesParsed,
    required this.keepAliveParts,
    required this.invalidParts,
    required this.oversizedHeaders,
    required this.oversizedFrames,
    required this.bodyBytesCopied,
    required this.peakHeaderBytes,
    required this.peakFrameBytes,
    required this.bufferedBytes,
  });

  final int bytesReceived;
  final int framesParsed;
  final int keepAliveParts;
  final int invalidParts;
  final int oversizedHeaders;
  final int oversizedFrames;
  final int bodyBytesCopied;
  final int peakHeaderBytes;
  final int peakFrameBytes;
  final int bufferedBytes;

  Map<String, Object?> toJson() => {
        'bytesReceived': bytesReceived,
        'framesParsed': framesParsed,
        'keepAliveParts': keepAliveParts,
        'invalidParts': invalidParts,
        'oversizedHeaders': oversizedHeaders,
        'oversizedFrames': oversizedFrames,
        'bodyBytesCopied': bodyBytesCopied,
        'peakHeaderBytes': peakHeaderBytes,
        'peakFrameBytes': peakFrameBytes,
        'bufferedBytes': bufferedBytes,
      };
}

class MjpegStreamFrame {
  const MjpegStreamFrame({
    required this.jpeg,
    this.sequence,
    this.capturedAtMs,
    this.sentAtMs,
    this.capturedAtMonoUs,
    this.encodeDurationUs,
    this.traceId,
  });

  final Uint8List jpeg;
  final int? sequence;
  final int? capturedAtMs;
  final int? sentAtMs;
  final int? capturedAtMonoUs;
  final int? encodeDurationUs;
  final String? traceId;
}

/// Relative one-way delay needs no synchronized clocks: the minimum observed
/// transit time becomes the path baseline and only queue growth is reported.
class VideoTransitEstimator {
  int? _baseTransitMs;
  int? _lastTransitMs;
  double _jitterMs = 0;

  double get jitterMs => _jitterMs;
  int get queueDelayMs {
    final base = _baseTransitMs;
    final transit = _lastTransitMs;
    if (base == null || transit == null) return 0;
    return (transit - base).clamp(0, 60000);
  }

  void observe({required int sentAtMs, required int arrivedAtMs}) {
    final transit = arrivedAtMs - sentAtMs;
    final base = _baseTransitMs;
    if (base == null || transit < base) _baseTransitMs = transit;
    final previous = _lastTransitMs;
    if (previous != null) {
      final variation = (transit - previous).abs();
      _jitterMs += (variation - _jitterMs) / 16;
    }
    _lastTransitMs = transit;
  }

  void reset() {
    _baseTransitMs = null;
    _lastTransitMs = null;
    _jitterMs = 0;
  }
}
