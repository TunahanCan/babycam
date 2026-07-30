import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';
import 'package:miucam/app/app_role.dart';
import 'package:miucam/core/media/adaptive_media_profile.dart';
import 'package:miucam/core/protocol/alert_event_dto.dart';
import 'package:miucam/core/protocol/device_feature_models.dart';
import 'package:miucam/core/protocol/miucam_protocol.dart';
import 'package:miucam/core/protocol/pairing_payload.dart';
import 'package:miucam/core/protocol/pairing_session.dart';
import 'package:miucam/core/theme/miucam_theme.dart';
import 'package:miucam/features/client/client_home_screen.dart';
import 'package:miucam/features/client/client_runtime.dart';
import 'package:miucam/features/client/controls/client_room_controls.dart';
import 'package:miucam/features/client/media/active_stream_session.dart';
import 'package:miucam/features/client/media/watch_screen.dart';
import 'package:miucam/features/role_selection/role_selection_screen.dart';
import 'package:miucam/features/server/media/media_runtime_controller.dart';
import 'package:miucam/features/server/media/server_media_source.dart';
import 'package:miucam/features/server/server_home_screen.dart';
import 'package:miucam/features/server/server_runtime.dart';
import 'package:miucam/l10n/app_strings.dart';
import 'package:miucam/services/configuration_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _scene = String.fromEnvironment('REPORT_SCENE', defaultValue: 'role');
const _localeCode = String.fromEnvironment('REPORT_LOCALE', defaultValue: 'tr');
const _localeCountry =
    String.fromEnvironment('REPORT_LOCALE_COUNTRY', defaultValue: '');
const _reportTab = int.fromEnvironment('REPORT_TAB', defaultValue: 0);
const _reportSequence =
    bool.fromEnvironment('REPORT_SEQUENCE', defaultValue: false);

Locale _reportLocale() => _localeCountry.isEmpty
    ? const Locale(_localeCode)
    : Locale.fromSubtags(
        languageCode: _localeCode,
        countryCode: _localeCountry,
      );

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (_reportSequence) {
    runApp(const _ReportApp(child: _ReportSequence()));
    return;
  }
  final scene = await _buildScene(_scene, tab: _reportTab);
  runApp(
    _ReportApp(
      child: _ReportSceneHost(
        scene: scene,
        onReady: () {},
      ),
    ),
  );
}

Future<_BuiltReportScene> _buildScene(
  String scene, {
  required int tab,
}) async {
  switch (scene) {
    case 'client_unpaired':
      final runtime = ClientRuntime(pair: (_) async => _session());
      return _BuiltReportScene(
        child: _ThemedScene(
          theme: MiuCamTheme.clientTheme(),
          child: ClientHomeScreen(
            runtime: runtime,
            activeRole: AppRole.client,
            onRoleSelected: (_) {},
            initialTab: tab,
          ),
        ),
        dispose: runtime.dispose,
      );
    case 'client_paired':
      final runtime = ClientRuntime(
        pair: (_) async => _session(),
        startStream: (_, {bool audioEnabled = false}) async =>
            ActiveStreamSession(
          streamToken: 'stream',
          audioEnabled: audioEnabled,
        ),
        stopStream: (_) async {},
      );
      await runtime.pairWithServer(_payload());
      return _BuiltReportScene(
        child: _ThemedScene(
          theme: MiuCamTheme.clientTheme(),
          child: ClientHomeScreen(
            runtime: runtime,
            activeRole: AppRole.client,
            onRoleSelected: (_) {},
            initialTab: tab,
          ),
        ),
        dispose: runtime.dispose,
      );
    case 'watch':
    case 'watch_controls':
    case 'watch_error':
      final fixture = scene == 'watch_error'
          ? null
          : await _ReportMediaFixtureServer.start(
              await _loadReportFrame(),
            );
      final controls = scene == 'watch_controls' ? _ReportRoomControls() : null;
      final session = fixture == null
          ? _session()
          : _session(
              payload: _payload(
                host: fixture.host,
                port: fixture.port,
              ),
            );
      final runtime = ClientRuntime(
        pair: (_) async => session,
        startStream: (_, {bool audioEnabled = false}) async {
          if (scene == 'watch_error') {
            throw StateError('report-stream-unavailable');
          }
          return ActiveStreamSession(
            streamToken: 'stream',
            audioEnabled: audioEnabled,
          );
        },
        stopStream: (_) async {},
        startAlerts: (_) async => true,
        stopAlerts: () async {},
        alertConnectionStates: Stream<bool>.value(true),
        roomControls: controls,
      );
      await runtime.pairWithServer(session.payload);
      await _seedWatchAlerts(runtime);
      await runtime.startAlertListening();
      return _BuiltReportScene(
        child: _ThemedScene(
          theme: MiuCamTheme.clientTheme(),
          child: WatchScreen(runtime: runtime, initialTab: tab),
        ),
        readyWidget: fixture == null || tab != 0
            ? null
            : (widget) => widget is RawImage && widget.image != null,
        dispose: () async {
          await runtime.dispose();
          await fixture?.dispose();
        },
      );
    case 'qr_scanner':
      return _BuiltReportScene(child: const _QrScannerReportScene());
    case 'server':
    case 'server_preview_on':
      final preferences = await SharedPreferences.getInstance();
      final config = ConfigurationService(preferences);
      await config.resetToDefaults();
      final preview = scene == 'server_preview_on'
          ? _ReportPreviewSource(await _loadReportFrame())
          : null;
      final runtime = ServerRuntime(
        mediaRuntime: MediaRuntimeController(),
        onStartPairing: () async => _qrPayload,
        previewSource: preview == null ? null : () => preview,
        mediaProfile: () => MediaQualityProfile.forDeviceTier(
          DeviceCapabilityTier.balanced,
        ).adaptForClientLoad(2),
      );
      if (scene == 'server_preview_on') {
        await runtime.startLocalPreview();
      } else {
        await runtime.startStreamSession(
          'anne-telefonu',
          const StreamSessionOptions(video: true, audio: true),
        );
      }
      return _BuiltReportScene(
        child: _ThemedScene(
          theme: MiuCamTheme.serverTheme(),
          child: ServerHomeScreen(
            runtime: runtime,
            config: config,
            activeRole: AppRole.server,
            onRoleSelected: (_) {},
            initialTab: tab,
          ),
        ),
        readyWidget: preview == null
            ? null
            : (widget) {
                if (widget is! Image) return false;
                final provider = widget.image;
                return provider is MemoryImage &&
                    identical(provider.bytes, preview.frame);
              },
        dispose: () async {
          await runtime.dispose();
          await preview?.dispose();
        },
      );
    case 'role':
    default:
      return _BuiltReportScene(
        child: _ThemedScene(
          theme: MiuCamTheme.neutralTheme(),
          child: RoleSelectionScreen(onRoleSelected: (_) {}),
        ),
      );
  }
}

Future<Uint8List> _loadReportFrame() async {
  final data = await rootBundle.load(
    'assets/branding/miucam_launcher_icon.png',
  );
  return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}

class _BuiltReportScene {
  _BuiltReportScene({
    required this.child,
    this.readyWidget,
    Future<void> Function()? dispose,
  }) : _onDispose = dispose;

  final Widget child;
  final bool Function(Widget widget)? readyWidget;
  final Future<void> Function()? _onDispose;
  Future<void>? _disposeFuture;

  Future<void> dispose() =>
      _disposeFuture ??= _onDispose?.call() ?? Future<void>.value();
}

const _reportScenes = <_ReportSceneSpec>[
  _ReportSceneSpec('role', 0),
  _ReportSceneSpec('client_unpaired', 0),
  _ReportSceneSpec('client_unpaired', 1),
  _ReportSceneSpec('client_unpaired', 2),
  _ReportSceneSpec('client_unpaired', 3),
  _ReportSceneSpec('client_paired', 0),
  _ReportSceneSpec('qr_scanner', 0),
  _ReportSceneSpec('watch', 0),
  _ReportSceneSpec('watch', 1),
  _ReportSceneSpec('watch', 2),
  _ReportSceneSpec('watch_controls', 0),
  _ReportSceneSpec('watch_error', 0),
  _ReportSceneSpec('server', 0),
  _ReportSceneSpec('server_preview_on', 0),
  _ReportSceneSpec('server', 1),
  _ReportSceneSpec('server', 2),
  _ReportSceneSpec('server', 3),
];

class _ReportSceneSpec {
  const _ReportSceneSpec(this.scene, this.tab);

  final String scene;
  final int tab;
}

class _ReportSequence extends StatefulWidget {
  const _ReportSequence();

  @override
  State<_ReportSequence> createState() => _ReportSequenceState();
}

class _ReportSequenceState extends State<_ReportSequence> {
  var _index = 0;
  var _horizontalDrag = 0.0;
  var _transitioning = true;
  var _generation = 0;
  int? _reportedReadyIndex;
  _BuiltReportScene? _activeScene;

  @override
  void initState() {
    super.initState();
    unawaited(_replaceScene(_index));
  }

  void _move(int delta) {
    if (_transitioning) return;
    final next = (_index + delta).clamp(0, _reportScenes.length - 1);
    if (next == _index) return;
    unawaited(_replaceScene(next));
  }

  Future<void> _replaceScene(int next) async {
    final generation = ++_generation;
    final previous = _activeScene;
    setState(() {
      _transitioning = true;
      _activeScene = null;
    });
    await WidgetsBinding.instance.endOfFrame;
    await previous?.dispose();

    final spec = _reportScenes[next];
    final loaded = await _buildScene(spec.scene, tab: spec.tab);
    if (!mounted || generation != _generation) {
      await loaded.dispose();
      return;
    }
    setState(() {
      _index = next;
      _activeScene = loaded;
      _transitioning = false;
      _reportedReadyIndex = null;
    });
  }

  void _reportReady(_BuiltReportScene scene, int index) {
    if (!identical(_activeScene, scene) ||
        _transitioning ||
        _reportedReadyIndex == index) {
      return;
    }
    _reportedReadyIndex = index;
    final spec = _reportScenes[index];
    debugPrint(
      'MIUCAM_REPORT_READY index=$index '
      'scene=${spec.scene} tab=${spec.tab}',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _horizontalDrag = 0,
      onPointerMove: (event) => _horizontalDrag += event.delta.dx,
      onPointerUp: (_) {
        if (_horizontalDrag.abs() < 90) return;
        _move(_horizontalDrag < 0 ? 1 : -1);
      },
      child: _activeScene == null
          ? const Scaffold(
              backgroundColor: Color(0xFFF7F5FC),
              body: Center(child: CircularProgressIndicator()),
            )
          : _ReportSceneHost(
              key: ValueKey(_index),
              scene: _activeScene!,
              onReady: () => _reportReady(_activeScene!, _index),
            ),
    );
  }
}

class _ReportSceneHost extends StatefulWidget {
  const _ReportSceneHost({
    super.key,
    required this.scene,
    required this.onReady,
  });

  final _BuiltReportScene scene;
  final VoidCallback onReady;

  @override
  State<_ReportSceneHost> createState() => _ReportSceneHostState();
}

class _ReportSceneHostState extends State<_ReportSceneHost> {
  @override
  void initState() {
    super.initState();
    unawaited(_waitUntilReady());
  }

  @override
  void dispose() {
    unawaited(widget.scene.dispose());
    super.dispose();
  }

  Future<void> _waitUntilReady() async {
    await WidgetsBinding.instance.endOfFrame;
    final matcher = widget.scene.readyWidget;
    while (mounted && matcher != null && !_containsWidget(context, matcher)) {
      await Future<void>.delayed(const Duration(milliseconds: 16));
      if (!mounted) return;
      await WidgetsBinding.instance.endOfFrame;
    }
    if (!mounted) return;
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) widget.onReady();
  }

  bool _containsWidget(
    BuildContext root,
    bool Function(Widget widget) matcher,
  ) {
    var found = matcher((root as Element).widget);
    void visit(Element element) {
      if (found) return;
      if (matcher(element.widget)) {
        found = true;
        return;
      }
      element.visitChildElements(visit);
    }

    root.visitChildElements(visit);
    return found;
  }

  @override
  Widget build(BuildContext context) => widget.scene.child;
}

class _ReportMediaFixtureServer {
  _ReportMediaFixtureServer._(this._server, this._frame) {
    _server.listen(_handleRequest);
  }

  final HttpServer _server;
  final Uint8List _frame;
  bool _disposed = false;

  String get host => InternetAddress.loopbackIPv4.address;
  int get port => _server.port;

  static Future<_ReportMediaFixtureServer> start(Uint8List frame) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    return _ReportMediaFixtureServer._(server, frame);
  }

  void _handleRequest(HttpRequest request) {
    switch (request.uri.path) {
      case '/video':
        unawaited(_serveVideo(request.response));
        return;
      case '/audio':
        unawaited(_serveAudio(request.response));
        return;
      default:
        request.response.statusCode = HttpStatus.notFound;
        unawaited(request.response.close());
        return;
    }
  }

  Future<void> _serveVideo(HttpResponse response) async {
    response.headers
      ..set(
        HttpHeaders.contentTypeHeader,
        'multipart/x-mixed-replace; boundary=frame',
      )
      ..chunkedTransferEncoding = true;
    var sequence = 0;
    try {
      while (!_disposed) {
        sequence++;
        final now = DateTime.now().millisecondsSinceEpoch;
        response.add(utf8.encode(
          '--frame\r\n'
          'Content-Type: image/png\r\n'
          'Content-Length: ${_frame.length}\r\n'
          'X-MiuCam-Sequence: $sequence\r\n'
          'X-MiuCam-Sent-At-Ms: $now\r\n\r\n',
        ));
        response.add(_frame);
        response.add(const [13, 10]);
        await response.flush();
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
    } catch (_) {
      // A scene transition force-closes fixture clients by design.
    } finally {
      try {
        await response.close();
      } catch (_) {}
    }
  }

  Future<void> _serveAudio(HttpResponse response) async {
    response.headers
      ..contentType = ContentType('audio', 'wav')
      ..chunkedTransferEncoding = true;
    final silence = Uint8List(640);
    try {
      while (!_disposed) {
        response.add(silence);
        await response.flush();
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    } catch (_) {
      // A scene transition force-closes fixture clients by design.
    } finally {
      try {
        await response.close();
      } catch (_) {}
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _server.close(force: true);
  }
}

class _ReportPreviewSource implements ServerJpegPreviewSource {
  _ReportPreviewSource(this.frame);

  final Uint8List frame;
  final _frames = StreamController<Uint8List>.broadcast();

  @override
  Uint8List get latestPreviewFrame => frame;

  @override
  Stream<Uint8List> get previewFrames => _frames.stream;

  Future<void> dispose() => _frames.close();
}

Future<void> _seedWatchAlerts(ClientRuntime runtime) async {
  final now = DateTime.now().millisecondsSinceEpoch;
  await runtime.recordAlert(AlertEventDto(
    id: 'report-motion',
    type: 'motionDetected',
    severity: 'info',
    messageKey: 'parentMotionAlert',
    message: 'Motion detected',
    score: .43,
    timestampMs: now - const Duration(minutes: 4).inMilliseconds,
    sourceDeviceId: 'server-lg-g6',
    metadata: const {
      'scorePercent': 43,
      'activeAreaPercent': 12,
      'meanDiff': 18.4,
    },
  ));
  await runtime.recordAlert(AlertEventDto(
    id: 'report-cry',
    type: 'cryDetected',
    severity: 'warning',
    messageKey: 'parentCryAlert',
    message: 'Cry-like sound detected',
    score: .82,
    timestampMs: now - const Duration(minutes: 1).inMilliseconds,
    sourceDeviceId: 'server-lg-g6',
    metadata: const {
      'confidencePercent': 82,
      'ambientDeltaDb': 13.6,
      'cryBandPercent': 71,
      'isCalibrated': true,
    },
  ));
}

class _ReportApp extends StatelessWidget {
  const _ReportApp({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: _reportLocale(),
      supportedLocales: AppStrings.supportedLocales,
      localizationsDelegates: const [
        AppStrings.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: child,
    );
  }
}

class _ThemedScene extends StatelessWidget {
  const _ThemedScene({required this.theme, required this.child});

  final ThemeData theme;
  final Widget child;

  @override
  Widget build(BuildContext context) => Theme(data: theme, child: child);
}

PairingPayload _payload({
  String host = '192.168.1.42',
  int port = 8080,
}) =>
    PairingPayload(
      schemaVersion: MiuCamProtocolV2.schemaVersion,
      host: host,
      port: port,
      deviceId: 'server-lg-g6',
      deviceName: AppStrings(_reportLocale()).ui('babyRoomName'),
      pairingNonce: 'nonce-report',
      expiresAtMs: DateTime.now()
          .add(const Duration(minutes: 10))
          .millisecondsSinceEpoch,
      transport: 'http_ws',
      capabilities: {
        'transport': 'http_ws',
        'video': 'mjpeg',
        'audio': 'pcm16le',
        'events': 'websocket',
        'maxClients': 5,
        'mediaProfile': MediaQualityProfile.forDeviceTier(
          DeviceCapabilityTier.balanced,
        ).toJson(),
      },
    );

PairingSession _session({PairingPayload? payload}) => PairingSession(
      payload: payload ?? _payload(),
      sessionToken: 'report-session-token',
      clientId: 'anne-telefonu',
      trustedClientTokenExpiresAtMs:
          DateTime.now().add(const Duration(days: 7)).millisecondsSinceEpoch,
      pairedAtMs: DateTime.now().millisecondsSinceEpoch,
    );

class _ReportRoomControls extends ClientRoomControls {
  _ReportRoomControls() {
    scheduleMicrotask(() => _emit());
  }

  final _changes = StreamController<ClientRoomControlSnapshot>.broadcast();
  var _snapshot = ClientRoomControlSnapshot(
    comfort: ComfortAudioState.initial().copyWith(
      playing: true,
      trackId: 'shushing',
      trackTitle: 'Soft shushing',
      volume: .58,
    ),
  );

  @override
  ClientRoomControlSnapshot get currentState => _snapshot;

  @override
  Stream<ClientRoomControlSnapshot> get states => _changes.stream;

  @override
  Future<ComfortAudioState?> refreshComfort(PairingSession session) async {
    _emit();
    return _snapshot.comfort;
  }

  @override
  Future<ComfortAudioState?> setComfort(
    PairingSession session, {
    required String action,
    String? trackId,
    double? volume,
    bool? loop,
  }) async {
    final current = _snapshot.comfort ?? ComfortAudioState.initial();
    final playing = switch (action) {
      'play' => true,
      'pause' || 'stop' => false,
      _ => current.playing,
    };
    final comfort = current.copyWith(
      playing: playing,
      trackId: trackId,
      volume: volume,
      loop: loop,
    );
    _snapshot = ClientRoomControlSnapshot(
      comfort: comfort,
      talking: _snapshot.talking,
    );
    _emit();
    return comfort;
  }

  @override
  Future<void> startTalking(PairingSession session) async {
    _snapshot = ClientRoomControlSnapshot(
      comfort: _snapshot.comfort,
      talking: true,
    );
    _emit();
  }

  @override
  Future<void> stopTalking() async {
    _snapshot = ClientRoomControlSnapshot(
      comfort: _snapshot.comfort,
      talking: false,
    );
    _emit();
  }

  void _emit() {
    if (!_changes.isClosed) _changes.add(_snapshot);
  }

  @override
  Future<void> dispose() async {
    await _changes.close();
    await super.dispose();
  }
}

const _qrPayload =
    'miucam://pair?payload=eyJob3N0IjoiMTkyLjE2OC4xLjQyIiwicG9ydCI6ODA4MCwiZGV2aWNlTmFtZSI6IkJlYmVrIE9kYXNpIiwidHJhbnNwb3J0IjoiaHR0cF93cyJ9';

class _QrScannerReportScene extends StatelessWidget {
  const _QrScannerReportScene();

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFF07111F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF07111F),
        foregroundColor: Colors.white,
        title: Text(strings.ui('scanQr')),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Container(color: const Color(0xFF10233B)),
                  Center(
                    child: Container(
                      width: 250,
                      height: 250,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.white, width: 3),
                        borderRadius: BorderRadius.circular(26),
                      ),
                    ),
                  ),
                  const Align(
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.qr_code_scanner_rounded,
                      color: Colors.white54,
                      size: 96,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
              color: Colors.white,
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      enabled: false,
                      decoration: InputDecoration(
                        labelText: strings.ui('qrCodeText'),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const SizedBox(
                    height: 56,
                    child: FilledButton(
                      onPressed: null,
                      child: Icon(Icons.check_rounded),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
