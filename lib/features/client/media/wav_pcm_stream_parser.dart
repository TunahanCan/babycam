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

class WavPcmStreamParser {
  WavPcmStreamParser({
    this.defaultSampleRate = 16000,
    this.defaultChannels = 1,
    this.defaultBitsPerSample = 16,
  })  : _sampleRate = defaultSampleRate,
        _channels = defaultChannels,
        _bitsPerSample = defaultBitsPerSample;

  final int defaultSampleRate;
  final int defaultChannels;
  final int defaultBitsPerSample;

  final _header = BytesBuilder(copy: false);
  bool _configured = false;
  int _sampleRate;
  int _channels;
  int _bitsPerSample;
  Uint8List _pendingBytes = Uint8List(0);

  ParsedPcmAudio add(Uint8List chunk) {
    if (!_configured) {
      _header.add(chunk);
      final headerBytes = _header.toBytes();
      final dataStart = _tryParseHeader(headerBytes);
      if (dataStart == null) {
        return _empty;
      }
      _configured = true;
      final payload = headerBytes.sublist(dataStart);
      return _parsed(_align(payload));
    }
    return _parsed(_align(chunk));
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

  int? _tryParseHeader(Uint8List bytes) {
    if (bytes.length < 12) return null;
    if (!_asciiAt(bytes, 0, 'RIFF') || !_asciiAt(bytes, 8, 'WAVE')) {
      return 0;
    }

    var offset = 12;
    while (offset + 8 <= bytes.length) {
      final chunkId = String.fromCharCodes(bytes.sublist(offset, offset + 4));
      final chunkSize = _uint32le(bytes, offset + 4);
      final chunkDataOffset = offset + 8;
      final nextOffset =
          chunkDataOffset + chunkSize + (chunkSize.isOdd ? 1 : 0);
      if (chunkDataOffset + chunkSize > bytes.length) return null;

      if (chunkId == 'fmt ') {
        if (chunkSize >= 16) {
          final audioFormat = _uint16le(bytes, chunkDataOffset);
          final channels = _uint16le(bytes, chunkDataOffset + 2);
          final sampleRate = _uint32le(bytes, chunkDataOffset + 4);
          final bitsPerSample = _uint16le(bytes, chunkDataOffset + 14);
          if (audioFormat == 1 && bitsPerSample == 16 && channels > 0) {
            _channels = channels;
            _sampleRate = sampleRate;
            _bitsPerSample = bitsPerSample;
          }
        }
      } else if (chunkId == 'data') {
        return chunkDataOffset;
      }
      offset = nextOffset;
    }
    return null;
  }

  Uint8List _align(Uint8List bytes) {
    if (bytes.isEmpty) return bytes;
    final frameSize = (_channels * _bitsPerSample ~/ 8).clamp(2, 16).toInt();
    final builder = BytesBuilder(copy: false);
    final pending = _pendingBytes;
    if (pending.isNotEmpty) {
      builder.add(pending);
      _pendingBytes = Uint8List(0);
    }
    builder.add(bytes);
    final all = builder.toBytes();
    final alignedLength = all.length - (all.length % frameSize);
    if (alignedLength == all.length) return all;
    if (alignedLength < all.length) {
      _pendingBytes = Uint8List.sublistView(all, alignedLength);
    }
    return Uint8List.sublistView(all, 0, alignedLength);
  }

  static bool _asciiAt(Uint8List bytes, int offset, String value) {
    if (offset + value.length > bytes.length) return false;
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
