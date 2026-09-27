import 'dart:typed_data';

/// Reassembles arbitrary HTTP/TCP chunks into aligned PCM16 frames.
///
/// Transport chunk boundaries are unrelated to sample boundaries, so an odd
/// trailing byte is retained and prepended to the next chunk instead of being
/// discarded. Full frames are emitted eagerly and an aligned tail can be
/// flushed when the request ends.
class Pcm16FrameAssembler {
  Pcm16FrameAssembler({required this.frameBytes})
      : _pending = Uint8List(_validateFrameBytes(frameBytes));

  final int frameBytes;
  final Uint8List _pending;
  int _pendingLength = 0;

  int get pendingBytes => _pendingLength;
  bool get hasPartialSample => _pendingLength.isOdd;

  List<Uint8List> add(List<int> bytes) {
    if (bytes.isEmpty) return const [];
    final frames = <Uint8List>[];
    var offset = 0;
    if (_pendingLength > 0) {
      final missing = frameBytes - _pendingLength;
      final available = bytes.length < missing ? bytes.length : missing;
      _pending.setRange(_pendingLength, _pendingLength + available, bytes);
      _pendingLength += available;
      offset = available;
      if (_pendingLength < frameBytes) return frames;
      frames.add(Uint8List.fromList(_pending));
      _pendingLength = 0;
    }

    // Copy each complete frame once. Removing prefixes from a growing list
    // shifts every remaining byte repeatedly for large HTTP chunks.
    while (bytes.length - offset >= frameBytes) {
      frames.add(Uint8List(frameBytes)..setRange(0, frameBytes, bytes, offset));
      offset += frameBytes;
    }
    _pendingLength = bytes.length - offset;
    if (_pendingLength > 0) {
      _pending.setRange(0, _pendingLength, bytes, offset);
    }
    return frames;
  }

  Uint8List? flushAlignedTail() {
    final alignedLength = _pendingLength - (_pendingLength % 2);
    if (alignedLength == 0) return null;
    final result = Uint8List(alignedLength)
      ..setRange(0, alignedLength, _pending);
    _pendingLength -= alignedLength;
    if (_pendingLength > 0) _pending[0] = _pending[alignedLength];
    return result;
  }

  void clear() => _pendingLength = 0;

  static int _validateFrameBytes(int value) {
    if (value <= 0 || value.isOdd) {
      throw ArgumentError.value(
          value, 'frameBytes', 'must be positive and even');
    }
    return value;
  }
}
