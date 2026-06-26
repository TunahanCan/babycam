import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:mimicam/app/app_role.dart';
import 'package:mimicam/core/media/adaptive_media_profile.dart';
import 'package:mimicam/core/protocol/pairing_payload.dart';
import 'package:mimicam/core/protocol/pairing_session.dart';
import 'package:mimicam/core/theme/mimicam_theme.dart';
import 'package:mimicam/features/client/client_home_screen.dart';
import 'package:mimicam/features/client/client_runtime.dart';
import 'package:mimicam/features/client/media/watch_screen.dart';
import 'package:mimicam/features/role_selection/role_selection_screen.dart';
import 'package:mimicam/features/server/media/media_runtime_controller.dart';
import 'package:mimicam/features/server/server_home_screen.dart';
import 'package:mimicam/features/server/server_runtime.dart';
import 'package:mimicam/l10n/app_strings.dart';
import 'package:mimicam/services/configuration_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _scene = String.fromEnvironment('REPORT_SCENE', defaultValue: 'role');
const _localeCode = String.fromEnvironment('REPORT_LOCALE', defaultValue: 'tr');
const _localeCountry =
    String.fromEnvironment('REPORT_LOCALE_COUNTRY', defaultValue: '');

Locale _reportLocale() => _localeCountry.isEmpty
    ? const Locale(_localeCode)
    : Locale.fromSubtags(
        languageCode: _localeCode,
        countryCode: _localeCountry,
      );

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final child = await _buildScene(_scene);
  runApp(_ReportApp(child: child));
}

Future<Widget> _buildScene(String scene) async {
  switch (scene) {
    case 'client_unpaired':
      return _ThemedScene(
        theme: MimiCamTheme.clientTheme(),
        child: ClientHomeScreen(
          runtime: ClientRuntime(pair: (_) async => _session()),
          activeRole: AppRole.client,
          onRoleSelected: (_) {},
        ),
      );
    case 'client_paired':
      final runtime = ClientRuntime(
        pair: (_) async => _session(),
        startStream: (_) async {},
        stopStream: (_) async {},
      );
      await runtime.pairWithServer(_payload());
      return _ThemedScene(
        theme: MimiCamTheme.clientTheme(),
        child: ClientHomeScreen(
          runtime: runtime,
          activeRole: AppRole.client,
          onRoleSelected: (_) {},
        ),
      );
    case 'watch':
      final runtime = ClientRuntime(
        pair: (_) async => _session(),
        startStream: (_) async {},
        stopStream: (_) async {},
      );
      await runtime.pairWithServer(_payload());
      return _ThemedScene(
        theme: MimiCamTheme.clientTheme(),
        child: WatchScreen(runtime: runtime),
      );
    case 'qr_scanner':
      return const _QrScannerReportScene();
    case 'server':
      final preferences = await SharedPreferences.getInstance();
      final runtime = ServerRuntime(
        mediaRuntime: MediaRuntimeController(),
        onStartPairing: () async => _qrPayload,
        mediaProfile: () => MediaQualityProfile.forDeviceTier(
          DeviceCapabilityTier.balanced,
        ).adaptForClientLoad(2),
      );
      await runtime.startStreamSession(
        'anne-telefonu',
        const StreamSessionOptions(video: true, audio: true),
      );
      return _ThemedScene(
        theme: MimiCamTheme.serverTheme(),
        child: ServerHomeScreen(
          runtime: runtime,
          config: ConfigurationService(preferences),
          activeRole: AppRole.server,
          onRoleSelected: (_) {},
        ),
      );
    case 'role':
    default:
      return _ThemedScene(
        theme: MimiCamTheme.neutralTheme(),
        child: RoleSelectionScreen(onRoleSelected: (_) {}),
      );
  }
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

PairingPayload _payload() => PairingPayload(
      schemaVersion: 1,
      host: '192.168.1.42',
      port: 8080,
      deviceId: 'server-lg-g6',
      deviceName: 'Bebek Odası',
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

PairingSession _session() => PairingSession(
      payload: _payload(),
      sessionToken: 'report-session-token',
      clientId: 'anne-telefonu',
      trustedClientTokenExpiresAtMs:
          DateTime.now().add(const Duration(days: 7)).millisecondsSinceEpoch,
      pairedAtMs: DateTime.now().millisecondsSinceEpoch,
    );

const _qrPayload =
    'mimicam://pair?payload=eyJob3N0IjoiMTkyLjE2OC4xLjQyIiwicG9ydCI6ODA4MCwiZGV2aWNlTmFtZSI6IkJlYmVrIE9kYXNpIiwidHJhbnNwb3J0IjoiaHR0cF93cyJ9';

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
