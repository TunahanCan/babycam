/// Normalized rectangular region of interest using 0.0-1.0 coordinates.
class NormalizedRect {
  /// Creates a normalized rectangle. Negative sizes are rejected by assertion.
  const NormalizedRect({
    required double left,
    required double top,
    required double width,
    required double height,
  })  : assert(width >= 0, 'width must be non-negative'),
        assert(height >= 0, 'height must be non-negative'),
        left = left < 0 ? 0 : (left > 1 ? 1 : left),
        top = top < 0 ? 0 : (top > 1 ? 1 : top),
        width = width < 0 ? 0 : (width > 1 ? 1 : width),
        height = height < 0 ? 0 : (height > 1 ? 1 : height);

  final double left;
  final double top;
  final double width;
  final double height;

  double get right => (left + width).clamp(0.0, 1.0).toDouble();
  double get bottom => (top + height).clamp(0.0, 1.0).toDouble();

  /// Returns true when [x] and [y] are inside this normalized rectangle.
  bool containsNormalized(double x, double y) =>
      x >= left && x < right && y >= top && y < bottom;

  /// Serializes the ROI to JSON-safe values.
  Map<String, Object?> toJson() => {
        'left': left,
        'top': top,
        'width': width,
        'height': height,
      };
}
