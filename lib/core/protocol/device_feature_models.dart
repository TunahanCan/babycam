import 'pairing_payload.dart';
import 'pairing_session.dart';

class BatterySnapshot {
  const BatterySnapshot({
    required this.levelPercent,
    required this.state,
    required this.isLow,
    required this.isCritical,
    required this.updatedAtMs,
  });

  factory BatterySnapshot.unknown({int? updatedAtMs}) => BatterySnapshot(
        levelPercent: null,
        state: 'unknown',
        isLow: false,
        isCritical: false,
        updatedAtMs: updatedAtMs ?? DateTime.now().millisecondsSinceEpoch,
      );

  factory BatterySnapshot.fromLevel({
    required int levelPercent,
    required String state,
    required int updatedAtMs,
  }) {
    final clamped = levelPercent.clamp(0, 100).toInt();
    final normalizedState = state.trim().isEmpty ? 'unknown' : state.trim();
    final charging = normalizedState == 'charging' || normalizedState == 'full';
    return BatterySnapshot(
      levelPercent: clamped,
      state: normalizedState,
      isLow: !charging && clamped <= 20,
      isCritical: !charging && clamped <= 10,
      updatedAtMs: updatedAtMs,
    );
  }

  final int? levelPercent;
  final String state;
  final bool isLow;
  final bool isCritical;
  final int updatedAtMs;

  Map<String, Object?> toJson() => {
        'levelPercent': levelPercent,
        'state': state,
        'isLow': isLow,
        'isCritical': isCritical,
        'updatedAtMs': updatedAtMs,
      };

  static BatterySnapshot? fromJson(Object? value) {
    final json = _objectMap(value);
    if (json == null) return null;
    final level = _intOrNull(json['levelPercent']);
    final state = json['state']?.toString() ?? 'unknown';
    final updatedAtMs = _intOrNull(json['updatedAtMs']);
    if (updatedAtMs == null) return null;
    return BatterySnapshot(
      levelPercent: level,
      state: state,
      isLow: json['isLow'] == true,
      isCritical: json['isCritical'] == true,
      updatedAtMs: updatedAtMs,
    );
  }
}

class ComfortAudioState {
  const ComfortAudioState({
    required this.playing,
    required this.trackId,
    required this.trackTitle,
    required this.volume,
    required this.loop,
    required this.playlistTrackIds,
    required this.updatedAtMs,
    this.lastError,
  });

  factory ComfortAudioState.initial({int? updatedAtMs}) => ComfortAudioState(
        playing: false,
        trackId: null,
        trackTitle: null,
        volume: 0.5,
        loop: true,
        playlistTrackIds: const ['white_noise', 'soft_lullaby'],
        updatedAtMs: updatedAtMs ?? DateTime.now().millisecondsSinceEpoch,
      );

  final bool playing;
  final String? trackId;
  final String? trackTitle;
  final double volume;
  final bool loop;
  final List<String> playlistTrackIds;
  final int updatedAtMs;
  final String? lastError;

  ComfortAudioState copyWith({
    bool? playing,
    String? trackId,
    String? trackTitle,
    double? volume,
    bool? loop,
    List<String>? playlistTrackIds,
    int? updatedAtMs,
    String? lastError,
    bool clearError = false,
    bool clearTrack = false,
  }) =>
      ComfortAudioState(
        playing: playing ?? this.playing,
        trackId: clearTrack ? null : trackId ?? this.trackId,
        trackTitle: clearTrack ? null : trackTitle ?? this.trackTitle,
        volume: (volume ?? this.volume).clamp(0, 1).toDouble(),
        loop: loop ?? this.loop,
        playlistTrackIds: playlistTrackIds ?? this.playlistTrackIds,
        updatedAtMs: updatedAtMs ?? this.updatedAtMs,
        lastError: clearError ? null : lastError ?? this.lastError,
      );

  Map<String, Object?> toJson() => {
        'playing': playing,
        'trackId': trackId,
        'trackTitle': trackTitle,
        'volume': volume,
        'loop': loop,
        'playlistTrackIds': playlistTrackIds,
        'updatedAtMs': updatedAtMs,
        if (lastError != null) 'lastError': lastError,
      };

  static ComfortAudioState? fromJson(Object? value) {
    final json = _objectMap(value);
    if (json == null) return null;
    final updatedAtMs = _intOrNull(json['updatedAtMs']);
    final volume = _doubleOrNull(json['volume']);
    if (updatedAtMs == null || volume == null) return null;
    return ComfortAudioState(
      playing: json['playing'] == true,
      trackId: _stringOrNull(json['trackId']),
      trackTitle: _stringOrNull(json['trackTitle']),
      volume: volume.clamp(0, 1).toDouble(),
      loop: json['loop'] != false,
      playlistTrackIds: _stringList(json['playlistTrackIds']),
      updatedAtMs: updatedAtMs,
      lastError: _stringOrNull(json['lastError']),
    );
  }
}

class NightLightState {
  const NightLightState({
    required this.enabled,
    required this.mode,
    required this.brightness,
    required this.updatedAtMs,
    this.lastError,
  });

  factory NightLightState.initial({int? updatedAtMs}) => NightLightState(
        enabled: false,
        mode: 'off',
        brightness: 0.25,
        updatedAtMs: updatedAtMs ?? DateTime.now().millisecondsSinceEpoch,
      );

  final bool enabled;
  final String mode;
  final double brightness;
  final int updatedAtMs;
  final String? lastError;

  NightLightState copyWith({
    bool? enabled,
    String? mode,
    double? brightness,
    int? updatedAtMs,
    String? lastError,
    bool clearError = false,
  }) =>
      NightLightState(
        enabled: enabled ?? this.enabled,
        mode: mode ?? this.mode,
        brightness: (brightness ?? this.brightness).clamp(0, 1).toDouble(),
        updatedAtMs: updatedAtMs ?? this.updatedAtMs,
        lastError: clearError ? null : lastError ?? this.lastError,
      );

  Map<String, Object?> toJson() => {
        'enabled': enabled,
        'mode': mode,
        'brightness': brightness,
        'updatedAtMs': updatedAtMs,
        if (lastError != null) 'lastError': lastError,
      };

  static NightLightState? fromJson(Object? value) {
    final json = _objectMap(value);
    if (json == null) return null;
    final updatedAtMs = _intOrNull(json['updatedAtMs']);
    final brightness = _doubleOrNull(json['brightness']);
    if (updatedAtMs == null || brightness == null) return null;
    return NightLightState(
      enabled: json['enabled'] == true,
      mode: json['mode']?.toString() ?? 'off',
      brightness: brightness.clamp(0, 1).toDouble(),
      updatedAtMs: updatedAtMs,
      lastError: _stringOrNull(json['lastError']),
    );
  }
}

class TalkSession {
  const TalkSession({
    required this.clientId,
    required this.token,
    required this.startedAtMs,
    required this.expiresAtMs,
    required this.audioBytesReceived,
    required this.videoBytesReceived,
    this.lastAudioAtMs,
    this.lastVideoAtMs,
  });

  final String clientId;
  final String token;
  final int startedAtMs;
  final int expiresAtMs;
  final int audioBytesReceived;
  final int videoBytesReceived;
  final int? lastAudioAtMs;
  final int? lastVideoAtMs;

  bool isExpired(int nowMs) => expiresAtMs <= nowMs;

  TalkSession copyWith({
    int? audioBytesReceived,
    int? videoBytesReceived,
    int? lastAudioAtMs,
    int? lastVideoAtMs,
  }) =>
      TalkSession(
        clientId: clientId,
        token: token,
        startedAtMs: startedAtMs,
        expiresAtMs: expiresAtMs,
        audioBytesReceived: audioBytesReceived ?? this.audioBytesReceived,
        videoBytesReceived: videoBytesReceived ?? this.videoBytesReceived,
        lastAudioAtMs: lastAudioAtMs ?? this.lastAudioAtMs,
        lastVideoAtMs: lastVideoAtMs ?? this.lastVideoAtMs,
      );

  Map<String, Object?> toJson({bool includeToken = false}) => {
        'clientId': clientId,
        if (includeToken) 'talkToken': token,
        'startedAtMs': startedAtMs,
        'expiresAtMs': expiresAtMs,
        'audioBytesReceived': audioBytesReceived,
        'videoBytesReceived': videoBytesReceived,
        'lastAudioAtMs': lastAudioAtMs,
        'lastVideoAtMs': lastVideoAtMs,
      };
}

class BleConnectionDescriptor {
  const BleConnectionDescriptor({
    required this.serviceUuid,
    required this.deviceName,
    required this.host,
    required this.port,
    required this.transport,
    required this.capabilities,
    required this.expiresAtMs,
    this.pairingNonce,
    this.instructions,
  });

  final String serviceUuid;
  final String deviceName;
  final String host;
  final int port;
  final String transport;
  final String? pairingNonce;
  final Map<String, Object?> capabilities;
  final int expiresAtMs;
  final String? instructions;

  Map<String, Object?> toJson() => {
        'serviceUuid': serviceUuid,
        'deviceName': deviceName,
        'host': host,
        'port': port,
        'transport': transport,
        'pairingNonce': pairingNonce,
        'capabilities': capabilities,
        'expiresAtMs': expiresAtMs,
        if (instructions != null) 'instructions': instructions,
      };

  static BleConnectionDescriptor? fromJson(Object? value) {
    final json = _objectMap(value);
    if (json == null) return null;
    final port = _intOrNull(json['port']);
    final expiresAtMs = _intOrNull(json['expiresAtMs']);
    final capabilities = _objectMap(json['capabilities']);
    if (port == null || expiresAtMs == null || capabilities == null) {
      return null;
    }
    return BleConnectionDescriptor(
      serviceUuid: json['serviceUuid']?.toString() ?? '',
      deviceName: json['deviceName']?.toString() ?? '',
      host: json['host']?.toString() ?? '',
      port: port,
      transport: json['transport']?.toString() ?? 'http_ws',
      pairingNonce: _stringOrNull(json['pairingNonce']),
      capabilities: capabilities,
      expiresAtMs: expiresAtMs,
      instructions: _stringOrNull(json['instructions']),
    );
  }
}

class ChildProfile {
  const ChildProfile({
    required this.id,
    required this.displayName,
    required this.payload,
    required this.clientId,
    required this.trustedClientTokenExpiresAtMs,
    required this.pairedAtMs,
    this.selected = false,
    this.lastSeenAtMs,
  });

  factory ChildProfile.fromSession(
    PairingSession session, {
    bool selected = false,
    int? lastSeenAtMs,
  }) =>
      ChildProfile(
        id: idForSession(session),
        displayName: session.payload.deviceName,
        payload: session.payload,
        clientId: session.clientId,
        trustedClientTokenExpiresAtMs: session.trustedClientTokenExpiresAtMs,
        pairedAtMs: session.pairedAtMs,
        selected: selected,
        lastSeenAtMs: lastSeenAtMs,
      );

  final String id;
  final String displayName;
  final PairingPayload payload;
  final String clientId;
  final int trustedClientTokenExpiresAtMs;
  final int pairedAtMs;
  final bool selected;
  final int? lastSeenAtMs;

  static String idForSession(PairingSession session) {
    final serverDeviceId = session.payload.deviceId.trim();
    if (serverDeviceId.isNotEmpty) return serverDeviceId;
    return '${session.payload.host}:${session.payload.port}';
  }

  ChildProfile copyWith({
    String? displayName,
    PairingPayload? payload,
    String? clientId,
    int? trustedClientTokenExpiresAtMs,
    int? pairedAtMs,
    bool? selected,
    int? lastSeenAtMs,
  }) =>
      ChildProfile(
        id: id,
        displayName: displayName ?? this.displayName,
        payload: payload ?? this.payload,
        clientId: clientId ?? this.clientId,
        trustedClientTokenExpiresAtMs:
            trustedClientTokenExpiresAtMs ?? this.trustedClientTokenExpiresAtMs,
        pairedAtMs: pairedAtMs ?? this.pairedAtMs,
        selected: selected ?? this.selected,
        lastSeenAtMs: lastSeenAtMs ?? this.lastSeenAtMs,
      );

  PairingSession toSession({required String sessionToken}) => PairingSession(
        payload: payload,
        sessionToken: sessionToken,
        clientId: clientId,
        trustedClientTokenExpiresAtMs: trustedClientTokenExpiresAtMs,
        pairedAtMs: pairedAtMs,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'displayName': displayName,
        'payload': payload.toJson(),
        'clientId': clientId,
        'trustedClientTokenExpiresAtMs': trustedClientTokenExpiresAtMs,
        'pairedAtMs': pairedAtMs,
        'selected': selected,
        if (lastSeenAtMs != null) 'lastSeenAtMs': lastSeenAtMs,
      };

  static ChildProfile? fromJson(Object? value) {
    final json = _objectMap(value);
    if (json == null) return null;
    final payload = PairingPayload.fromJson(
      Map<String, Object?>.from(_objectMap(json['payload']) ?? const {}),
    );
    if (payload == null) return null;
    final id = json['id']?.toString();
    final clientId = json['clientId']?.toString();
    final expiresAt = _intOrNull(json['trustedClientTokenExpiresAtMs']);
    final pairedAt = _intOrNull(json['pairedAtMs']);
    if (id == null ||
        id.isEmpty ||
        clientId == null ||
        clientId.isEmpty ||
        expiresAt == null ||
        pairedAt == null) {
      return null;
    }
    return ChildProfile(
      id: id,
      displayName: json['displayName']?.toString() ?? payload.deviceName,
      payload: payload,
      clientId: clientId,
      trustedClientTokenExpiresAtMs: expiresAt,
      pairedAtMs: pairedAt,
      selected: json['selected'] == true,
      lastSeenAtMs: _intOrNull(json['lastSeenAtMs']),
    );
  }
}

Map<String, Object?>? _objectMap(Object? value) {
  if (value is! Map) return null;
  return Map<String, Object?>.from(value);
}

int? _intOrNull(Object? value) {
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse(value?.toString() ?? '');
}

double? _doubleOrNull(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '');
}

String? _stringOrNull(Object? value) {
  final text = value?.toString();
  if (text == null || text.isEmpty) return null;
  return text;
}

List<String> _stringList(Object? value) {
  if (value is! Iterable) return const [];
  return value.map((item) => item.toString()).toList(growable: false);
}
