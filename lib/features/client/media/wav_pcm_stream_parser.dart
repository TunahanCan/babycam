import 'dart:typed_data';

class ParsedPcmAudio {
  const ParsedPcmAudio({
    required this.sampleRate,
    required this.channels,
    required this.pcm16le,
    required this.isConfigured,
  });

  final int sampleRate;
  final int channels;
  final Uint8List pcm16le;
  final bool isConfigured;
}

/// Incrementally parses a streaming PCM WAV header with bounded memory.
///
/// A non-RIFF stream is treated as raw PCM using the configured defaults. A
/// RIFF/WAVE stream must advertise a supported PCM16 format before its data
/// chunk. The fixed header buffer prevents malformed input from growing an
/// unbounded [BytesBuilder] while a network connection stays open.
class WavPcmStreamParser {
  WavPcmStreamParser({
    this.defaultSampleRate = 16000,
    this.defaultChannels = 1,
    this.defaultBitsPerSample = 16,
    this.maxHeaderBytes = 64 * 1024,
    this.minSampleRate = 8000,
    this.maxSampleRate = 48000,
  })  : assert(maxHeaderBytes >= 12),
        _sampleRate = defaultSampleRate,
        _channels = defaultChannels,
        _bitsPerSample = defaultBitsPerSample,
        _header = Uint8List(maxHeaderBytes);

  final int defaultSampleRate;
  final int defaultChannels;
  final int defaultBitsPerSample;
  final int maxHeaderBytes;
  final int minSampleRate;
  final int maxSampleRate;

  Uint8List? _header;
  int _headerLength = 0;
  int _peakHeaderBytes = 0;
  bool _configured = false;
  int _sampleRate;
  int _channels;
  int _bitsPerSample;
  Uint8List _pendingBytes = Uint8List(0);

  int get peakHeaderBytes => _peakHeaderBytes;

  ParsedPcmAudio add(Uint8List chunk) {
    if (_configured) return _parsed(_align(chunk));
    if (chunk.isEmpty) return _empty;

    final header = _header!;
    final writable = maxHeaderBytes - _headerLength;
    final copied = chunk.length < writable ? chunk.length : writable;
    if (copied > 0) {
      header.setRange(_headerLength, _headerLength + copied, chunk);
      _headerLength += copied;
      if (_headerLength > _peakHeaderBytes) _peakHeaderBytes = _headerLength;
    }

    final dataStart = _tryParseHeader(header, _headerLength);
    if (dataStart == null) {
      if (copied < chunk.length || _headerLength >= maxHeaderBytes) {
        throw FormatException(
          'WAV header exceeds the $maxHeaderBytes byte limit.',
        );
      }
      return _empty;
    }

    _configured = true;
    final payload = _copyPayload(
      header,
      dataStart: dataStart,
      bufferedEnd: _headerLength,
      remainder: copied < chunk.length
          ? Uint8List.sublistView(chunk, copied)
          : Uint8List(0),
    );
    _header = null;
    return _parsed(_align(payload));
  }

  ParsedPcmAudio get _empty => ParsedPcmAudio(
        sampleRate: _sampleRate,
        channels: _channels,
        pcm16le: Uint8List(0),
        isConfigured: _configured,
      );

  ParsedPcmAudio _parsed(Uint8List pcm) => ParsedPcmAudio(
        sampleRate: _sampleRate,
        channels: _channels,
        pcm16le: pcm,
        isConfigured: _configured,
      );

  int? _tryParseHeader(Uint8List bytes, int length) {
    if (length < 12) return null;
    if (!_asciiAt(bytes, length, 0, 'RIFF')) return 0;
    if (!_asciiAt(bytes, length, 8, 'WAVE')) {
      throw const FormatException('Invalid RIFF/WAVE header.');
    }

    var offset = 12;
    var foundSupportedFormat = false;
    while (offset + 8 <= length) {
      final chunkSize = _uint32le(bytes, offset + 4);
      final chunkDataOffset = offset + 8;
      if (_asciiAt(bytes, length, offset, 'data')) {
        if (!foundSupportedFormat) {
          throw const FormatException(
            'WAV data chunk appeared before a supported PCM format.',
          );
        }
        return chunkDataOffset;
      }

      final paddedSize = chunkSize + (chunkSize.isOdd ? 1 : 0);
      final nextOffset = chunkDataOffset + paddedSize;
      if (nextOffset > length) return null;

      if (_asciiAt(bytes, length, offset, 'fmt ')) {
        if (chunkSize < 16) {
          throw const FormatException('WAV fmt chunk is too short.');
        }
        final audioFormat = _uint16le(bytes, chunkDataOffset);
        final channels = _uint16le(bytes, chunkDataOffset + 2);
        final sampleRate = _uint32le(bytes, chunkDataOffset + 4);
        final byteRate = _uint32le(bytes, chunkDataOffset + 8);
        final blockAlign = _uint16le(bytes, chunkDataOffset + 12);
        final bitsPerSample = _uint16le(bytes, chunkDataOffset + 14);
        final expectedBlockAlign = channels * bitsPerSample ~/ 8;
        final expectedByteRate = sampleRate * expectedBlockAlign;
        final supported = audioFormat == 1 &&
            bitsPerSample == 16 &&
            channels >= 1 &&
            channels <= 2 &&
            sampleRate >= minSampleRate &&
            sampleRate <= maxSampleRate &&
            blockAlign == expectedBlockAlign &&
            byteRate == expectedByteRate;
        if (!supported) {
          throw FormatException(
            'Unsupported WAV format: format=$audioFormat, channels=$channels, '
            'sampleRate=$sampleRate, bits=$bitsPerSample.',
          );
        }
        _channels = channels;
        _sampleRate = sampleRate;
        _bitsPerSample = bitsPerSample;
        foundSupportedFormat = true;
      }
      offset = nextOffset;
    }
    return null;
  }

  static Uint8List _copyPayload(
    Uint8List header, {
    required int dataStart,
    required int bufferedEnd,
    required Uint8List remainder,
  }) {
    final bufferedPayloadLength = bufferedEnd - dataStart;
    final result = Uint8List(bufferedPayloadLength + remainder.length);
    if (bufferedPayloadLength > 0) {
      result.setRange(0, bufferedPayloadLength, header, dataStart);
    }
    if (remainder.isNotEmpty) {
      result.setRange(bufferedPayloadLength, result.length, remainder);
    }
    return result;
  }

  Uint8List _align(Uint8List bytes) {
    if (bytes.isEmpty) return bytes;
    final frameSize = (_channels * _bitsPerSample ~/ 8).clamp(2, 16).toInt();
    final pending = _pendingBytes;
    if (pending.isEmpty) {
      final alignedLength = bytes.length - (bytes.length % frameSize);
      if (alignedLength == bytes.length) return bytes;
      _pendingBytes = Uint8List.sublistView(bytes, alignedLength);
      return Uint8List.sublistView(bytes, 0, alignedLength);
    }

    final all = Uint8List(pending.length + bytes.length)
      ..setRange(0, pending.length, pending)
      ..setRange(pending.length, pending.length + bytes.length, bytes);
    _pendingBytes = Uint8List(0);
    final alignedLength = all.length - (all.length % frameSize);
    if (alignedLength < all.length) {
      _pendingBytes = Uint8List.sublistView(all, alignedLength);
    }
    return Uint8List.sublistView(all, 0, alignedLength);
  }

  static bool _asciiAt(
    Uint8List bytes,
    int length,
    int offset,
    String value,
  ) {
    if (offset + value.length > length) return false;
    for (var i = 0; i < value.length; i++) {
      if (bytes[offset + i] != value.codeUnitAt(i)) return false;
    }
    return true;
  }

  static int _uint16le(Uint8List bytes, int offset) =>
      ByteData.sublistView(bytes, offset, offset + 2).getUint16(
        0,
        Endian.little,
      );

  static int _uint32le(Uint8List bytes, int offset) =>
      ByteData.sublistView(bytes, offset, offset + 4).getUint32(
        0,
        Endian.little,
      );
}
