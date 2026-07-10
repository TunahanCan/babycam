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
    final isBgra = image.format.group == ImageFormatGroup.bgra8888 ||
        (image.planes.length == 1 && (yPlane.bytesPerPixel ?? 1) >= 4);
    final pixelStride = isBgra ? (yPlane.bytesPerPixel ?? 4) : 1;
    final values = <double>[];
    var row = 0;
    while (row < image.height) {
      var col = 0;
      final rowStart = row * rowStride;
      while (col < image.width) {
        final offset = rowStart + col * pixelStride;
        if (isBgra && offset + 2 < bytes.length) {
          final b = bytes[offset];
          final g = bytes[offset + 1];
          final r = bytes[offset + 2];
          values.add(0.114 * b + 0.587 * g + 0.299 * r);
        } else if (offset < bytes.length) {
          values.add(bytes[offset].toDouble());
        }
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
  static Uint8List encode(
    CameraImage image, {
    int quality = 70,
    ImageFormatGroup? formatGroup,
    int? targetWidth,
    int? targetHeight,
  }) {
    final safeQuality = quality.clamp(35, 85);
    final effectiveFormatGroup = formatGroup ?? image.format.group;
    final outputSize = _outputSize(
      image,
      targetWidth: targetWidth,
      targetHeight: targetHeight,
    );
    if (effectiveFormatGroup == ImageFormatGroup.bgra8888 ||
        (image.planes.length == 1 &&
            (image.planes.first.bytesPerPixel ?? 1) >= 4)) {
      return _encodeBgra8888(
        image,
        quality: safeQuality,
        outputWidth: outputSize.width,
        outputHeight: outputSize.height,
      );
    }
    if (effectiveFormatGroup == ImageFormatGroup.yuv420) {
      if (image.planes.length >= 3) {
        return _encodePlanarYuv420(
          image,
          quality: safeQuality,
          outputWidth: outputSize.width,
          outputHeight: outputSize.height,
        );
      }
      if (image.planes.length == 2) {
        return _encodeBiPlanarYuv420(
          image,
          quality: safeQuality,
          outputWidth: outputSize.width,
          outputHeight: outputSize.height,
        );
      }
    }
    if (image.planes.length >= 3) {
      return _encodePlanarYuv420(
        image,
        quality: safeQuality,
        outputWidth: outputSize.width,
        outputHeight: outputSize.height,
      );
    }
    return _encodeLuma(
      image,
      quality: safeQuality,
      outputWidth: outputSize.width,
      outputHeight: outputSize.height,
    );
  }

  static Uint8List _encodePlanarYuv420(
    CameraImage frame, {
    required int quality,
    required int outputWidth,
    required int outputHeight,
  }) {
    final out = img.Image(width: outputWidth, height: outputHeight);
    final yPlane = frame.planes[0];
    final uPlane = frame.planes[1];
    final vPlane = frame.planes[2];
    final uPixelStride = uPlane.bytesPerPixel ?? 1;
    final vPixelStride = vPlane.bytesPerPixel ?? uPixelStride;

    for (var y = 0; y < outputHeight; y++) {
      final sourceY = y * frame.height ~/ outputHeight;
      for (var x = 0; x < outputWidth; x++) {
        final sourceX = x * frame.width ~/ outputWidth;
        final yIndex = sourceY * yPlane.bytesPerRow + sourceX;
        final uIndex =
            (sourceY ~/ 2) * uPlane.bytesPerRow + (sourceX ~/ 2) * uPixelStride;
        final vIndex =
            (sourceY ~/ 2) * vPlane.bytesPerRow + (sourceX ~/ 2) * vPixelStride;
        final yy = yIndex < yPlane.bytes.length ? yPlane.bytes[yIndex] : 0;
        final uu =
            uIndex < uPlane.bytes.length ? uPlane.bytes[uIndex] - 128 : 0;
        final vv =
            vIndex < vPlane.bytes.length ? vPlane.bytes[vIndex] - 128 : 0;
        _setYuvPixel(out, x, y, yy, uu, vv);
      }
    }
    return img.encodeJpg(
      out,
      quality: quality,
      chroma: img.JpegChroma.yuv420,
    );
  }

  /// iOS exposes kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange as a
  /// full-resolution Y plane plus one interleaved CbCr (NV12) plane.
  static Uint8List _encodeBiPlanarYuv420(
    CameraImage frame, {
    required int quality,
    required int outputWidth,
    required int outputHeight,
  }) {
    final out = img.Image(width: outputWidth, height: outputHeight);
    final yPlane = frame.planes[0];
    final uvPlane = frame.planes[1];
    final uvPixelStride = uvPlane.bytesPerPixel ?? 2;
    for (var y = 0; y < outputHeight; y++) {
      final sourceY = y * frame.height ~/ outputHeight;
      for (var x = 0; x < outputWidth; x++) {
        final sourceX = x * frame.width ~/ outputWidth;
        final yIndex = sourceY * yPlane.bytesPerRow + sourceX;
        final uvIndex = (sourceY ~/ 2) * uvPlane.bytesPerRow +
            (sourceX ~/ 2) * uvPixelStride;
        final yy = yIndex < yPlane.bytes.length ? yPlane.bytes[yIndex] : 0;
        final uu =
            uvIndex < uvPlane.bytes.length ? uvPlane.bytes[uvIndex] - 128 : 0;
        final vv = uvIndex + 1 < uvPlane.bytes.length
            ? uvPlane.bytes[uvIndex + 1] - 128
            : 0;
        _setYuvPixel(out, x, y, yy, uu, vv);
      }
    }
    return img.encodeJpg(
      out,
      quality: quality,
      chroma: img.JpegChroma.yuv420,
    );
  }

  static Uint8List _encodeBgra8888(
    CameraImage frame, {
    required int quality,
    required int outputWidth,
    required int outputHeight,
  }) {
    final out = img.Image(width: outputWidth, height: outputHeight);
    final plane = frame.planes.first;
    final pixelStride = plane.bytesPerPixel ?? 4;
    for (var y = 0; y < outputHeight; y++) {
      final sourceY = y * frame.height ~/ outputHeight;
      for (var x = 0; x < outputWidth; x++) {
        final sourceX = x * frame.width ~/ outputWidth;
        final index = sourceY * plane.bytesPerRow + sourceX * pixelStride;
        if (index + 2 >= plane.bytes.length) continue;
        out.setPixelRgb(
          x,
          y,
          plane.bytes[index + 2],
          plane.bytes[index + 1],
          plane.bytes[index],
        );
      }
    }
    return img.encodeJpg(
      out,
      quality: quality,
      chroma: img.JpegChroma.yuv420,
    );
  }

  static void _setYuvPixel(
    img.Image out,
    int x,
    int y,
    int luma,
    int u,
    int v,
  ) {
    final r = (luma + 1.402 * v).round().clamp(0, 255);
    final g = (luma - 0.344136 * u - 0.714136 * v).round().clamp(0, 255);
    final b = (luma + 1.772 * u).round().clamp(0, 255);
    out.setPixelRgb(x, y, r, g, b);
  }

  static Uint8List _encodeLuma(
    CameraImage frame, {
    required int quality,
    required int outputWidth,
    required int outputHeight,
  }) {
    final out = img.Image(width: outputWidth, height: outputHeight);
    final yPlane = frame.planes.first;
    for (var y = 0; y < outputHeight; y++) {
      final sourceY = y * frame.height ~/ outputHeight;
      for (var x = 0; x < outputWidth; x++) {
        final sourceX = x * frame.width ~/ outputWidth;
        final index = sourceY * yPlane.bytesPerRow + sourceX;
        final luma = index < yPlane.bytes.length ? yPlane.bytes[index] : 0;
        out.setPixelRgb(x, y, luma, luma, luma);
      }
    }
    return img.encodeJpg(
      out,
      quality: quality,
      chroma: img.JpegChroma.yuv420,
    );
  }

  static ({int width, int height}) _outputSize(
    CameraImage frame, {
    required int? targetWidth,
    required int? targetHeight,
  }) {
    final sourceWidth = max(1, frame.width);
    final sourceHeight = max(1, frame.height);
    if (targetWidth == null ||
        targetHeight == null ||
        targetWidth <= 0 ||
        targetHeight <= 0) {
      return (width: sourceWidth, height: sourceHeight);
    }
    final scale = min(
      1.0,
      min(targetWidth / sourceWidth, targetHeight / sourceHeight),
    );
    return (
      width: max(1, (sourceWidth * scale).round()),
      height: max(1, (sourceHeight * scale).round()),
    );
  }
}
