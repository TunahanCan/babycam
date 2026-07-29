import 'dart:isolate';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:miucam/services/motion_analyzer.dart';
import 'package:miucam/services/server/camera_jpeg_worker.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('BGRA stride luma ve JPEG renk kanallarinda dogru okunur', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    // ignore: deprecated_member_use
    final frame = CameraImage.fromPlatformData({
      'format': 1111970369,
      'width': 2,
      'height': 2,
      'planes': [
        {
          'bytes': Uint8List.fromList([
            0,
            0,
            255,
            255,
            0,
            0,
            255,
            255,
            0,
            0,
            255,
            255,
            0,
            0,
            255,
            255,
          ]),
          'bytesPerPixel': 4,
          'bytesPerRow': 8,
        },
      ],
    });

    final luma = const LumaDownsampler(sampleStep: 1).downsample(frame);
    final decoded = img.decodeJpg(CameraImageJpegEncoder.encode(frame));

    expect(luma, everyElement(closeTo(76.245, 0.01)));
    expect(decoded, isNotNull);
    final pixel = decoded!.getPixel(0, 0);
    expect(pixel.r, greaterThan(pixel.g));
    expect(pixel.r, greaterThan(pixel.b));
  });

  test('iOS iki-plane NV12 frame JPEG olarak encode edilir', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    // ignore: deprecated_member_use
    final frame = CameraImage.fromPlatformData({
      'format': 875704438,
      'width': 2,
      'height': 2,
      'planes': [
        {
          'bytes': Uint8List.fromList([76, 76, 76, 76]),
          'bytesPerPixel': 1,
          'bytesPerRow': 2,
        },
        {
          'bytes': Uint8List.fromList([85, 255]),
          'bytesPerPixel': 2,
          'bytesPerRow': 2,
        },
      ],
    });

    final decoded = img.decodeJpg(CameraImageJpegEncoder.encode(frame));

    expect(decoded, isNotNull);
    final pixel = decoded!.getPixel(0, 0);
    expect(pixel.r, greaterThan(180));
    expect(pixel.r, greaterThan(pixel.g));
    expect(pixel.r, greaterThan(pixel.b));
  });

  test('CameraImage JPEG worker isolateina aktarilabilir', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    // ignore: deprecated_member_use
    final frame = CameraImage.fromPlatformData({
      'format': 875704438,
      'width': 2,
      'height': 2,
      'planes': [
        {
          'bytes': Uint8List.fromList([90, 90, 90, 90]),
          'bytesPerPixel': 1,
          'bytesPerRow': 2,
        },
        {
          'bytes': Uint8List.fromList([128, 128]),
          'bytesPerPixel': 2,
          'bytesPerRow': 2,
        },
      ],
    });

    final jpeg = await Isolate.run(() => CameraImageJpegEncoder.encode(frame));

    expect(jpeg, isNotEmpty);
    expect(img.decodeJpg(jpeg), isNotNull);
  });

  test('JPEG encoder hedef profili en-boy oranini koruyarak uygular', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    // ignore: deprecated_member_use
    final frame = CameraImage.fromPlatformData({
      'format': 1111970369,
      'width': 8,
      'height': 4,
      'planes': [
        {
          'bytes': Uint8List.fromList(
            List<int>.generate(8 * 4 * 4, (index) => index % 4 == 3 ? 255 : 96),
          ),
          'bytesPerPixel': 4,
          'bytesPerRow': 8 * 4,
        },
      ],
    });

    final downscaled = img.decodeJpg(
      CameraImageJpegEncoder.encode(
        frame,
        targetWidth: 4,
        targetHeight: 4,
      ),
    );
    final notUpscaled = img.decodeJpg(
      CameraImageJpegEncoder.encode(
        frame,
        targetWidth: 16,
        targetHeight: 16,
      ),
    );

    expect((downscaled!.width, downscaled.height), (4, 2));
    expect((notUpscaled!.width, notUpscaled.height), (8, 4));
  });

  test('persistent JPEG worker owned snapshot kullanip bir kez spawn olur',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final worker = CameraJpegWorker();
    addTearDown(worker.dispose);
    // ignore: deprecated_member_use
    final frame = CameraImage.fromPlatformData({
      'format': 875704438,
      'width': 2,
      'height': 2,
      'planes': [
        {
          'bytes': Uint8List.fromList([60, 60, 60, 60]),
          'bytesPerPixel': 1,
          'bytesPerRow': 2,
        },
        {
          'bytes': Uint8List.fromList([128, 128]),
          'bytesPerPixel': 2,
          'bytesPerRow': 2,
        },
      ],
    });

    final firstSnapshot = TransferableCameraFrame.capture(frame);
    frame.planes.first.bytes.fillRange(0, 4, 200);
    final firstJpeg = await worker.encode(firstSnapshot, quality: 70);
    final secondJpeg = await worker.encode(
      TransferableCameraFrame.capture(frame),
      quality: 70,
    );

    final firstPixel = img.decodeJpg(firstJpeg)!.getPixel(0, 0);
    final secondPixel = img.decodeJpg(secondJpeg)!.getPixel(0, 0);
    expect(firstPixel.r, lessThan(secondPixel.r));
    expect(worker.debugSpawnCount, 1);
  });
}
