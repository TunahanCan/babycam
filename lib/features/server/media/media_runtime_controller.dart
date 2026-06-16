class MediaRuntimeController {
  MediaRuntimeController({
    Future<void> Function()? onStart,
    Future<void> Function()? onStop,
  })  : _onStart = onStart,
        _onStop = onStop;

  final Future<void> Function()? _onStart;
  final Future<void> Function()? _onStop;
  bool _isActive = false;
  Future<void>? _starting;

  bool get isActive => _isActive;

  Future<void> start() async {
    if (_isActive) return;
    final existingStart = _starting;
    if (existingStart != null) return existingStart;

    final start = _onStart?.call() ?? Future<void>.value();
    _starting = start;
    try {
      await start;
      _isActive = true;
    } finally {
      _starting = null;
    }
  }

  Future<void> stop() async {
    final start = _starting;
    if (start != null) {
      try {
        await start;
      } catch (_) {
        return;
      }
    }
    if (!_isActive) return;
    try {
      await _onStop?.call();
    } finally {
      _isActive = false;
    }
  }
}
