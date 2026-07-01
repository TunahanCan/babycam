import 'dart:typed_data';

import '../../core/protocol/device_feature_models.dart';
import '../../core/security/secure_random_token_generator.dart';

class ComfortAudioTrack {
  const ComfortAudioTrack({
    required this.id,
    required this.title,
    required this.assetPath,
    required this.kind,
  });

  final String id;
  final String title;
  final String assetPath;
  final String kind;

  Map<String, Object?> toJson() => {
        'id': id,
        'title': title,
        'assetPath': assetPath,
        'kind': kind,
      };
}

class ComfortAudioService {
  ComfortAudioService({DateTime Function()? now})
      : _now = now ?? DateTime.now,
        _state = ComfortAudioState.initial(
          updatedAtMs: (now ?? DateTime.now)().millisecondsSinceEpoch,
        );

  static const builtInTracks = [
    ComfortAudioTrack(
      id: 'white_noise',
      title: 'White noise',
      assetPath: 'assets/comfort/white_noise.wav',
      kind: 'white_noise',
    ),
    ComfortAudioTrack(
      id: 'pink_noise',
      title: 'Pink noise',
      assetPath: 'assets/comfort/pink_noise.wav',
      kind: 'white_noise',
    ),
    ComfortAudioTrack(
      id: 'rain',
      title: 'Rain',
      assetPath: 'assets/comfort/rain.wav',
      kind: 'ambient',
    ),
    ComfortAudioTrack(
      id: 'soft_lullaby',
      title: 'Soft lullaby',
      assetPath: 'assets/comfort/soft_lullaby.wav',
      kind: 'lullaby',
    ),
  ];

  final DateTime Function() _now;
  ComfortAudioState _state;

  ComfortAudioState get state => _state;

  List<Map<String, Object?>> get trackCatalog =>
      [for (final track in builtInTracks) track.toJson()];

  ComfortAudioState applyCommand(Map<Object?, Object?>? command) {
    final action = command?['action']?.toString().trim();
    final nowMs = _now().millisecondsSinceEpoch;
    switch (action) {
      case 'play':
        final track = _trackFor(command?['trackId']?.toString()) ??
            _trackFor(_state.trackId) ??
            _trackFor(_state.playlistTrackIds.isEmpty
                ? null
                : _state.playlistTrackIds.first);
        if (track == null) {
          _state = _state.copyWith(
            playing: false,
            updatedAtMs: nowMs,
            lastError: 'NO_TRACK_AVAILABLE',
          );
          return _state;
        }
        _state = _state.copyWith(
          playing: true,
          trackId: track.id,
          trackTitle: track.title,
          volume: _double(command?['volume']) ?? _state.volume,
          loop: _bool(command?['loop']) ?? _state.loop,
          updatedAtMs: nowMs,
          clearError: true,
        );
        return _state;
      case 'pause':
        _state = _state.copyWith(
          playing: false,
          updatedAtMs: nowMs,
          clearError: true,
        );
        return _state;
      case 'stop':
        _state = _state.copyWith(
          playing: false,
          updatedAtMs: nowMs,
          clearTrack: true,
          clearError: true,
        );
        return _state;
      case 'setVolume':
        _state = _state.copyWith(
          volume: _double(command?['volume']) ?? _state.volume,
          updatedAtMs: nowMs,
          clearError: true,
        );
        return _state;
      case 'setPlaylist':
        final playlist = _playlist(command?['playlistTrackIds']);
        _state = _state.copyWith(
          playlistTrackIds:
              playlist.isEmpty ? _state.playlistTrackIds : playlist,
          updatedAtMs: nowMs,
          clearError: true,
        );
        return _state;
      default:
        _state = _state.copyWith(
          updatedAtMs: nowMs,
          lastError: 'UNKNOWN_COMFORT_COMMAND',
        );
        return _state;
    }
  }

  ComfortAudioTrack? _trackFor(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final track in builtInTracks) {
      if (track.id == id) return track;
    }
    return null;
  }

  List<String> _playlist(Object? value) {
    if (value is! Iterable) return const [];
    final known = <String>[];
    for (final item in value) {
      final track = _trackFor(item.toString());
      if (track != null) known.add(track.id);
    }
    return known;
  }
}

class NightLightController {
  NightLightController({DateTime Function()? now})
      : _now = now ?? DateTime.now,
        _state = NightLightState.initial(
          updatedAtMs: (now ?? DateTime.now)().millisecondsSinceEpoch,
        );

  final DateTime Function() _now;
  NightLightState _state;

  NightLightState get state => _state;

  Future<NightLightState> applyCommand(
    Map<Object?, Object?>? command, {
    Future<bool> Function(bool enabled)? torchSetter,
  }) async {
    final action = command?['action']?.toString().trim();
    final nowMs = _now().millisecondsSinceEpoch;
    if (action == 'off') {
      await _setTorchBestEffort(torchSetter, false);
      _state = _state.copyWith(
        enabled: false,
        mode: 'off',
        updatedAtMs: nowMs,
        clearError: true,
      );
      return _state;
    }

    final enable = switch (action) {
      'on' => true,
      'toggle' => !_state.enabled,
      'set' => _bool(command?['enabled']) ?? _state.enabled,
      _ => null,
    };
    if (enable == null) {
      _state = _state.copyWith(
        updatedAtMs: nowMs,
        lastError: 'UNKNOWN_NIGHT_LIGHT_COMMAND',
      );
      return _state;
    }
    if (!enable) {
      await _setTorchBestEffort(torchSetter, false);
      _state = _state.copyWith(
        enabled: false,
        mode: 'off',
        brightness: _double(command?['brightness']) ?? _state.brightness,
        updatedAtMs: nowMs,
        clearError: true,
      );
      return _state;
    }

    final requestedMode = command?['mode']?.toString().trim().isEmpty == false
        ? command!['mode'].toString().trim()
        : _state.mode == 'off'
            ? 'torch'
            : _state.mode;
    final brightness = _double(command?['brightness']) ?? _state.brightness;
    var mode = requestedMode == 'screenGlow' ? 'screenGlow' : 'torch';
    String? error;
    if (mode == 'torch') {
      final torchOk = await _setTorchBestEffort(torchSetter, true);
      if (!torchOk) {
        mode = 'screenGlow';
        error = 'TORCH_UNAVAILABLE_SCREEN_GLOW_FALLBACK';
      }
    }
    _state = _state.copyWith(
      enabled: true,
      mode: mode,
      brightness: brightness,
      updatedAtMs: nowMs,
      lastError: error,
      clearError: error == null,
    );
    return _state;
  }

  Future<bool> _setTorchBestEffort(
    Future<bool> Function(bool enabled)? setter,
    bool enabled,
  ) async {
    if (setter == null) return false;
    try {
      return await setter(enabled);
    } catch (_) {
      return false;
    }
  }
}

class TalkSessionBusyException implements Exception {
  const TalkSessionBusyException(this.activeSession);

  final TalkSession activeSession;
}

class TalkSessionRegistry {
  TalkSessionRegistry({
    DateTime Function()? now,
    SecureRandomTokenGenerator? tokenGenerator,
    this.sessionTtl = const Duration(seconds: 45),
  })  : _now = now ?? DateTime.now,
        _tokenGenerator = tokenGenerator ?? SecureRandomTokenGenerator();

  final DateTime Function() _now;
  final SecureRandomTokenGenerator _tokenGenerator;
  final Duration sessionTtl;
  TalkSession? _active;

  TalkSession? get activeSession {
    _pruneExpired();
    return _active;
  }

  TalkSession start({required String clientId}) {
    _pruneExpired();
    final active = _active;
    if (active != null && active.clientId != clientId) {
      throw TalkSessionBusyException(active);
    }
    final nowMs = _now().millisecondsSinceEpoch;
    final session = TalkSession(
      clientId: clientId,
      token: _tokenGenerator.generateHex(byteCount: 32),
      startedAtMs: nowMs,
      expiresAtMs: nowMs + sessionTtl.inMilliseconds,
      audioBytesReceived: 0,
      videoBytesReceived: 0,
    );
    _active = session;
    return session;
  }

  bool stop({required String clientId, String? token}) {
    _pruneExpired();
    final active = _active;
    if (active == null || active.clientId != clientId) return false;
    if (token != null && token.isNotEmpty && active.token != token) {
      return false;
    }
    _active = null;
    return true;
  }

  TalkSession? recordAudio(String token, Uint8List bytes) {
    _pruneExpired();
    final active = _active;
    if (active == null || active.token != token) return null;
    final nowMs = _now().millisecondsSinceEpoch;
    final next = active.copyWith(
      audioBytesReceived: active.audioBytesReceived + bytes.length,
      lastAudioAtMs: nowMs,
    );
    _active = next;
    return next;
  }

  TalkSession? recordVideo(String token, Uint8List bytes) {
    _pruneExpired();
    final active = _active;
    if (active == null || active.token != token) return null;
    final nowMs = _now().millisecondsSinceEpoch;
    final next = active.copyWith(
      videoBytesReceived: active.videoBytesReceived + bytes.length,
      lastVideoAtMs: nowMs,
    );
    _active = next;
    return next;
  }

  bool isTokenActive(String token) {
    _pruneExpired();
    return _active?.token == token;
  }

  void _pruneExpired() {
    final active = _active;
    if (active == null) return;
    if (active.isExpired(_now().millisecondsSinceEpoch)) _active = null;
  }
}

bool? _bool(Object? value) {
  if (value is bool) return value;
  final text = value?.toString().trim().toLowerCase();
  if (text == 'true') return true;
  if (text == 'false') return false;
  return null;
}

double? _double(Object? value) {
  if (value is num) return value.toDouble().clamp(0, 1).toDouble();
  final parsed = double.tryParse(value?.toString() ?? '');
  return parsed?.clamp(0, 1).toDouble();
}
