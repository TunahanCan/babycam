import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:miucam/features/client/media/mjpeg_stream_parser.dart';

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

  test('zero-length keepalive parcasini frame saymadan atlar', () {
    final parser = MjpegStreamParser();
    final bytes = utf8.encode(
          '--frame\r\nContent-Length: 0\r\n\r\n\r\n',
        ) +
        _frame([4, 5, 6]);

    final frames = parser.add(Uint8List.fromList(bytes));

    expect(frames, hasLength(1));
    expect(frames.single, [4, 5, 6]);
  });

  test('sequence ve send timestamp multipart metadata olarak parse edilir', () {
    final parser = MjpegStreamParser();
    final bytes = utf8.encode(
          '--frame\r\nContent-Type: image/jpeg\r\n'
          'Content-Length: 3\r\n'
          'X-MiuCam-Sequence: 42\r\n'
          'X-MiuCam-Captured-At-Ms: 900\r\n'
          'X-MiuCam-Sent-At-Ms: 1000\r\n\r\n',
        ) +
        [7, 8, 9] +
        utf8.encode('\r\n');

    final frame = parser.addFrames(Uint8List.fromList(bytes)).single;

    expect(frame.jpeg, [7, 8, 9]);
    expect(frame.sequence, 42);
    expect(frame.capturedAtMs, 900);
    expect(frame.sentAtMs, 1000);
  });

  test('relative transit estimator saat offsetini cikarip queue delay olcer',
      () {
    final estimator = VideoTransitEstimator()
      ..observe(sentAtMs: 1000, arrivedAtMs: 6000)
      ..observe(sentAtMs: 1100, arrivedAtMs: 6130);

    expect(estimator.queueDelayMs, 30);
    expect(estimator.jitterMs, closeTo(1.875, 0.001));
  });

  test(
      'buyuk frame parcalari tek body kopyasi ve bounded header ile parse edilir',
      () {
    final parser = MjpegStreamParser();
    final jpeg = List<int>.generate(128 * 1024, (index) => index & 0xff);
    final stream = Uint8List.fromList(_frame(jpeg));
    final frames = <Uint8List>[];

    for (var offset = 0; offset < stream.length; offset += 257) {
      final end = (offset + 257).clamp(0, stream.length);
      frames.addAll(parser.add(Uint8List.sublistView(stream, offset, end)));
    }

    expect(frames, hasLength(1));
    expect(frames.single, jpeg);
    expect(parser.metrics.framesParsed, 1);
    expect(parser.metrics.bodyBytesCopied, jpeg.length);
    expect(parser.metrics.peakFrameBytes, jpeg.length);
    expect(parser.metrics.peakHeaderBytes, lessThan(1024));
    expect(parser.metrics.bufferedBytes, 0);
  });
}

List<int> _frame(List<int> jpeg) =>
    utf8.encode(
      '--frame\r\nContent-Type: image/jpeg\r\n'
      'Content-Length: ${jpeg.length}\r\n\r\n',
    ) +
    jpeg +
    utf8.encode('\r\n');
