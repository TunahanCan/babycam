import 'dart:convert';
import 'dart:typed_data';

class MjpegStreamParser {
  static final _headerEnd = Uint8List.fromList([13, 10, 13, 10]);
  static final _contentLengthPattern = RegExp(
    r'content-length:\s*(\d+)',
    caseSensitive: false,
  );
  static const _maxHeaderBytes = 16 * 1024;
  static const _maxFrameBytes = 2 * 1024 * 1024;

  Uint8List _buffer = Uint8List(0);

  List<Uint8List> add(Uint8List chunk) {
    if (chunk.isEmpty) return const [];
    _buffer = _append(_buffer, chunk);
    final frames = <Uint8List>[];

    while (_buffer.isNotEmpty) {
      final headerEnd = _indexOf(_buffer, _headerEnd);
      if (headerEnd < 0) {
        _trimOversizedHeader();
        break;
      }

      final header = latin1.decode(
        Uint8List.sublistView(_buffer, 0, headerEnd),
        allowInvalid: true,
      );
      final contentLength = _contentLength(header);
      final frameStart = headerEnd + _headerEnd.length;
      if (contentLength == null ||
          contentLength <= 0 ||
          contentLength > _maxFrameBytes) {
        _buffer = Uint8List.sublistView(_buffer, frameStart);
        continue;
      }

      final frameEnd = frameStart + contentLength;
      if (_buffer.length < frameEnd) break;

      frames.add(_buffer.sublist(frameStart, frameEnd));
      var consumed = frameEnd;
      if (_buffer.length >= consumed + 2 &&
          _buffer[consumed] == 13 &&
          _buffer[consumed + 1] == 10) {
        consumed += 2;
      }
      _buffer = Uint8List.sublistView(_buffer, consumed);
    }

    return frames;
  }

  int? _contentLength(String header) {
    final match = _contentLengthPattern.firstMatch(header);
    if (match == null) return null;
    return int.tryParse(match.group(1) ?? '');
  }

  void _trimOversizedHeader() {
    if (_buffer.length <= _maxHeaderBytes) return;
    _buffer = Uint8List.sublistView(
      _buffer,
      _buffer.length - _headerEnd.length + 1,
    );
  }

  static Uint8List _append(Uint8List first, Uint8List second) {
    if (first.isEmpty) return second;
    final combined = Uint8List(first.length + second.length);
    combined.setRange(0, first.length, first);
    combined.setRange(first.length, combined.length, second);
    return combined;
  }

  static int _indexOf(Uint8List bytes, Uint8List pattern) {
    if (pattern.isEmpty || bytes.length < pattern.length) return -1;
    for (var i = 0; i <= bytes.length - pattern.length; i++) {
      var matched = true;
      for (var j = 0; j < pattern.length; j++) {
        if (bytes[i + j] != pattern[j]) {
          matched = false;
          break;
        }
      }
      if (matched) return i;
    }
    return -1;
  }
}
