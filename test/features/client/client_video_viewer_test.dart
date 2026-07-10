import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mimicam/features/client/media/client_video_viewer.dart';

void main() {
  testWidgets('frame yokken loading, hata varken kapalı kamera ikonu gösterir',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: SizedBox(
        width: 120,
        height: 90,
        child: ClientVideoViewer(frame: null),
      ),
    ));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byIcon(Icons.videocam_off_rounded), findsNothing);

    await tester.pumpWidget(MaterialApp(
      home: SizedBox(
        width: 120,
        height: 90,
        child: ClientVideoViewer(
          frame: null,
          error: StateError('stream failed'),
        ),
      ),
    ));

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byIcon(Icons.videocam_off_rounded), findsOneWidget);
  });

  test('decode sirasinda ara kareleri biriktirmeyip en yeniyi tutar', () async {
    final requested = <Uint8List>[];
    final decodes = <Completer<int>>[];
    final presented = <int>[];
    final discarded = <int>[];
    final errors = <Object>[];
    final queue = LatestVideoFramePresentationQueue<int>(
      decode: (frame) {
        requested.add(frame);
        final completer = Completer<int>();
        decodes.add(completer);
        return completer.future;
      },
      onPresented: presented.add,
      onDiscarded: discarded.add,
      onError: (error, _) => errors.add(error),
    );
    final first = Uint8List.fromList([1]);
    final middle = Uint8List.fromList([2]);
    final latest = Uint8List.fromList([3]);

    queue
      ..offer(first)
      ..offer(middle)
      ..offer(latest);

    expect(requested, [same(first)]);
    expect(queue.decodeInFlight, isTrue);
    expect(queue.coalescedFrameCount, 1);

    decodes.first.complete(1);
    await Future<void>.delayed(Duration.zero);

    expect(presented, [1]);
    expect(requested, [same(first), same(latest)]);
    expect(requested, isNot(contains(same(middle))));

    decodes.last.complete(3);
    await Future<void>.delayed(Duration.zero);

    expect(presented, [1, 3]);
    expect(discarded, isEmpty);
    expect(errors, isEmpty);
    expect(queue.decodeInFlight, isFalse);
    queue.dispose();
  });

  testWidgets(
      'decoded kareleri global ImageCache disinda tutup eskisini kapatir',
      (tester) async {
    final cache = PaintingBinding.instance.imageCache;
    cache
      ..clear()
      ..clearLiveImages();
    addTearDown(() {
      cache
        ..clear()
        ..clearLiveImages();
    });

    await tester.pumpWidget(MaterialApp(
      home: SizedBox(
        width: 120,
        height: 90,
        child: ClientVideoViewer(frame: _jpeg(240, 20, 20)),
      ),
    ));
    await _waitFor(tester, () => find.byType(RawImage).evaluate().isNotEmpty);

    final first = tester.widget<RawImage>(find.byType(RawImage)).image!;
    expect(cache.currentSize, 0);

    await tester.pumpWidget(MaterialApp(
      home: SizedBox(
        width: 120,
        height: 90,
        child: ClientVideoViewer(frame: _jpeg(20, 20, 240)),
      ),
    ));
    await _waitFor(
      tester,
      () => !identical(
        tester.widget<RawImage>(find.byType(RawImage)).image,
        first,
      ),
    );

    final latest = tester.widget<RawImage>(find.byType(RawImage)).image!;
    expect(identical(latest, first), isFalse);
    expect(first.debugDisposed, isTrue);
    expect(latest.debugDisposed, isFalse);
    expect(cache.currentSize, 0);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(latest.debugDisposed, isTrue);
  });
}

Uint8List _jpeg(int red, int green, int blue) {
  final image = img.Image(width: 2, height: 2);
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      image.setPixelRgba(x, y, red, green, blue, 255);
    }
  }
  return Uint8List.fromList(img.encodeJpg(image, quality: 90));
}

Future<void> _waitFor(
  WidgetTester tester,
  bool Function() predicate,
) async {
  for (var attempt = 0; attempt < 50; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
    if (predicate()) return;
  }
  fail('Timed out waiting for asynchronous video decode.');
}
