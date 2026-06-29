import 'dart:typed_data';

extension ByteChunkView on List<int> {
  Uint8List asUint8ListView() {
    final chunk = this;
    return chunk is Uint8List ? chunk : Uint8List.fromList(chunk);
  }
}
