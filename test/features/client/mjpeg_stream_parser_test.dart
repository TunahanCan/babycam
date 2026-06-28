import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mimicam/features/client/media/mjpeg_stream_parser.dart';

void main() {
  test('parcali MJPEG header ve frame verisini birlestirir', () {
    final parser = MjpegStreamParser();
    final stream = _frame([1, 2, 3, 4]) + _frame([5, 6]);

    final first = parser.add(Uint8List.fromList(stream.take(17).toList()));
    final second = parser.add(Uint8List.fromList(stream.skip(17).toList()));

    expect(first, isEmpty);
    expect(second, hasLength(2));
    expect(second[0], [1, 2, 3, 4]);
    expect(second[1], [5, 6]);
  });

  test('gecersiz content-length frame yerine siradaki headera toparlanir', () {
    final parser = MjpegStreamParser();
    final bytes = utf8.encode(
          '--frame\r\nContent-Type: image/jpeg\r\n\r\nignored',
        ) +
        _frame([9, 8, 7]);

    final frames = parser.add(Uint8List.fromList(bytes));

    expect(frames, hasLength(1));
    expect(frames.single, [9, 8, 7]);
  });
}

List<int> _frame(List<int> jpeg) =>
    utf8.encode(
      '--frame\r\nContent-Type: image/jpeg\r\n'
      'Content-Length: ${jpeg.length}\r\n\r\n',
    ) +
    jpeg +
    utf8.encode('\r\n');
