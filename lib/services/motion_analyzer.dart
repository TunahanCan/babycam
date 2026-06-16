import 'dart:math';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;

class MotionAnalysisResult {
  const MotionAnalysisResult({required this.score, required this.jpeg});
  final double score;
  final Uint8List jpeg;
}

class MotionAnalyzer {
  MotionAnalyzer({this.sampleStep = 4});

  final int sampleStep;
  final _scoreCalculator = MotionScoreCalculator();
  List<double>? _background;

  MotionAnalysisResult analyze(CameraImage image) {
    final sampled = LumaDownsampler(sampleStep: sampleStep).downsample(image);
    final background = _background;
    var score = 0.0;

    if (background == null || background.length != sampled.length) {
      _background = List<double>.of(sampled, growable: false);
      _scoreCalculator.reset();
    } else {
      var diffSum = 0.0;
      for (var i = 0; i < sampled.length; i++) {
        final current = sampled[i];
        final previous = background[i];
        diffSum += (current - previous).abs();
        background[i] = previous * 0.96 + current * 0.04;
      }
      final rawScore = (diffSum / (sampled.length * 255.0)).clamp(0.0, 1.0);
      score = _scoreCalculator.calculate(rawScore);
    }

    return MotionAnalysisResult(
        score: score, jpeg: CameraImageJpegEncoder.encode(image));
  }
}

class LumaDownsampler {
  const LumaDownsampler({required this.sampleStep});
  final int sampleStep;

  List<double> downsample(CameraImage image) {
    final yPlane = image.planes.first;
    final bytes = yPlane.bytes;
    final rowStride = yPlane.bytesPerRow;
    final values = <double>[];
    var row = 0;
    while (row < image.height) {
      var col = 0;
      final rowStart = row * rowStride;
      while (col < image.width) {
        final offset = rowStart + col;
        if (offset < bytes.length) values.add(bytes[offset].toDouble());
        col += sampleStep;
      }
      row += sampleStep;
    }
    return values;
  }
}

class MotionScoreCalculator {
  double _motionNoiseEstimate = 0.02;
  double _smoothedMotion = 0.0;

  void reset() {
    _motionNoiseEstimate = 0.02;
    _smoothedMotion = 0.0;
  }

  double calculate(double rawScore) {
    _motionNoiseEstimate = rawScore < _motionNoiseEstimate
        ? _motionNoiseEstimate * 0.9 + rawScore * 0.1
        : _motionNoiseEstimate * 0.995 + rawScore * 0.005;
    final adjusted = max(0.0, rawScore - _motionNoiseEstimate);
    final dynamicRange = max(1e-3, 1.0 - _motionNoiseEstimate);
    final normalized = (adjusted / dynamicRange).clamp(0.0, 1.0);
    _smoothedMotion = _smoothedMotion * 0.65 + normalized * 0.35;
    return _smoothedMotion;
  }
}

class CameraImageJpegEncoder {
  static Uint8List encode(CameraImage image, {int quality = 70}) {
    final safeQuality = quality.clamp(35, 85);
    if (image.planes.length >= 3) {
      return _encodeYuv420(image, quality: safeQuality);
    }
    return _encodeLuma(image, quality: safeQuality);
  }

  static Uint8List _encodeYuv420(CameraImage frame, {required int quality}) {
    final out = img.Image(width: frame.width, height: frame.height);
    final yPlane = frame.planes[0];
    final uPlane = frame.planes[1];
    final vPlane = frame.planes[2];
    final uvPixelStride = uPlane.bytesPerPixel ?? 1;

    for (var y = 0; y < frame.height; y++) {
      for (var x = 0; x < frame.width; x++) {
        final yIndex = y * yPlane.bytesPerRow + x;
        final uvIndex =
            (y ~/ 2) * uPlane.bytesPerRow + (x ~/ 2) * uvPixelStride;
        final yy = yIndex < yPlane.bytes.length ? yPlane.bytes[yIndex] : 0;
        final uu =
            uvIndex < uPlane.bytes.length ? uPlane.bytes[uvIndex] - 128 : 0;
        final vv =
            uvIndex < vPlane.bytes.length ? vPlane.bytes[uvIndex] - 128 : 0;
        final r = (yy + 1.402 * vv).round().clamp(0, 255);
        final g = (yy - 0.344136 * uu - 0.714136 * vv).round().clamp(0, 255);
        final b = (yy + 1.772 * uu).round().clamp(0, 255);
        out.setPixelRgb(x, y, r, g, b);
      }
    }
    return Uint8List.fromList(img.encodeJpg(out, quality: quality));
  }

  static Uint8List _encodeLuma(CameraImage frame, {required int quality}) {
    final out = img.Image(width: frame.width, height: frame.height);
    final yPlane = frame.planes.first;
    for (var y = 0; y < frame.height; y++) {
      for (var x = 0; x < frame.width; x++) {
        final index = y * yPlane.bytesPerRow + x;
        final luma = index < yPlane.bytes.length ? yPlane.bytes[index] : 0;
        out.setPixelRgb(x, y, luma, luma, luma);
      }
    }
    return Uint8List.fromList(img.encodeJpg(out, quality: quality));
  }
}
