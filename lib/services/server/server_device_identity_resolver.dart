import 'dart:async';

typedef ServerDeviceIdProvider = FutureOr<String> Function();

/// Resolves the discovery identity once and shares the same in-flight result
/// across HTTP status, pairing and advertisement consumers.
class ServerDeviceIdentityResolver {
  ServerDeviceIdentityResolver(this._provider);

  final ServerDeviceIdProvider _provider;

  String? _resolved;
  Future<String>? _resolution;

  Future<String> resolve() {
    final resolved = _resolved;
    if (resolved != null) return Future<String>.value(resolved);

    return _resolution ??= Future<String>.sync(_provider).then((value) {
      final normalized = value.trim();
      if (normalized.isEmpty) {
        throw StateError('Server discovery device ID must not be empty.');
      }
      _resolved = normalized;
      return normalized;
    }).whenComplete(() => _resolution = null);
  }
}
