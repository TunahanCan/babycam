import 'dart:typed_data';

/// Reassembles arbitrary HTTP/TCP chunks into aligned PCM16 frames.
///
/// Transport chunk boundaries are unrelated to sample boundaries, so an odd
/// trailing byte is retained and prepended to the next chunk instead of being
/// discarded. Full frames are emitted eagerly and an aligned tail can be
/// flushed when the request ends.
class Pcm16FrameAssembler {
  Pcm16FrameAssembler({required this.frameBytes})
      : assert(frameBytes > 0 && frameBytes.isEven);

  final int frameBytes;
  final _pending = <int>[];

  int get pendingBytes => _pending.length;
  bool get hasPartialSample => _pending.length.isOdd;

  List<Uint8List> add(List<int> bytes) {
    if (bytes.isEmpty) return const [];
    _pending.addAll(bytes);
    return _drainFullFrames();
  }

  Uint8List? flushAlignedTail() {
    final alignedLength = _pending.length - (_pending.length % 2);
    if (alignedLength == 0) return null;
    final result = Uint8List.fromList(_pending.take(alignedLength).toList());
    _pending.removeRange(0, alignedLength);
    return result;
  }

  void clear() => _pending.clear();

  List<Uint8List> _drainFullFrames() {
    if (_pending.length < frameBytes) return const [];
    final frames = <Uint8List>[];
    while (_pending.length >= frameBytes) {
      frames.add(Uint8List.fromList(_pending.take(frameBytes).toList()));
      _pending.removeRange(0, frameBytes);
    }
    return frames;
  }
}
