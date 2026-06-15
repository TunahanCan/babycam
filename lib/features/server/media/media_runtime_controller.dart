class MediaRuntimeController {
  MediaRuntimeController({Future<void> Function()? onStart, Future<void> Function()? onStop}) : _onStart = onStart, _onStop = onStop;
  final Future<void> Function()? _onStart;
  final Future<void> Function()? _onStop;
  bool _isActive = false;
  bool get isActive => _isActive;

  Future<void> start() async {
    if (_isActive) return;
    await _onStart?.call();
    _isActive = true;
  }

  Future<void> stop() async {
    if (!_isActive) return;
    await _onStop?.call();
    _isActive = false;
  }
}
