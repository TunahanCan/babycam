import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimicam/features/client/pairing/qr_scan_screen.dart';
import 'package:mimicam/l10n/app_strings.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  testWidgets('kamera izni reddedilince manuel QR girişi açık kalır',
      (tester) async {
    final gateway = _FakeQRCameraPermissionGateway(
      statusResult: PermissionStatus.denied,
      requestResult: PermissionStatus.denied,
    );

    await tester.pumpWidget(_App(gateway: gateway));
    await tester.pump();
    await tester.pump();

    expect(gateway.statusCalls, 1);
    expect(gateway.requestCalls, 1);
    expect(
      find.text(
        'QR taramak için kamera izni gerekli. QR kod metnini alttan yapıştırabilirsin.',
      ),
      findsOneWidget,
    );
    expect(find.text('Ayarları aç'), findsOneWidget);
    expect(find.text('Tekrar dene'), findsOneWidget);
    expect(find.text('QR kod metni'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('ayarlar butonu permission gateway üzerinden açılır',
      (tester) async {
    final gateway = _FakeQRCameraPermissionGateway(
      statusResult: PermissionStatus.permanentlyDenied,
    );

    await tester.pumpWidget(_App(gateway: gateway));
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('Ayarları aç'));
    await tester.pump();

    expect(gateway.openSettingsCalls, 1);
  });

  testWidgets('kamera yoksa native scanner açmadan manuel giriş gösterir',
      (tester) async {
    final gateway = _FakeQRCameraPermissionGateway(
      statusResult: PermissionStatus.granted,
    );
    final availability = _FakeQRCameraAvailabilityGateway(available: false);

    await tester.pumpWidget(_App(
      gateway: gateway,
      cameraAvailabilityGateway: availability,
    ));
    await tester.pump();
    await tester.pump();

    expect(availability.calls, 1);
    expect(find.text('Kamera bulunamadı.'), findsOneWidget);
    expect(find.text('QR kod metni'), findsOneWidget);
  });
}

class _App extends StatelessWidget {
  const _App({
    required this.gateway,
    this.cameraAvailabilityGateway,
  });

  final QRCameraPermissionGateway gateway;
  final QRCameraAvailabilityGateway? cameraAvailabilityGateway;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      locale: const Locale('tr'),
      supportedLocales: AppStrings.supportedLocales,
      localizationsDelegates: const [
        AppStrings.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: QRScanScreen(
        permissionGateway: gateway,
        cameraAvailabilityGateway: cameraAvailabilityGateway ??
            _FakeQRCameraAvailabilityGateway(available: true),
      ),
    );
  }
}

class _FakeQRCameraPermissionGateway implements QRCameraPermissionGateway {
  _FakeQRCameraPermissionGateway({
    required this.statusResult,
    this.requestResult,
  });

  PermissionStatus statusResult;
  final PermissionStatus? requestResult;
  int statusCalls = 0;
  int requestCalls = 0;
  int openSettingsCalls = 0;

  @override
  Future<PermissionStatus> status() async {
    statusCalls++;
    return statusResult;
  }

  @override
  Future<PermissionStatus> request() async {
    requestCalls++;
    statusResult = requestResult ?? statusResult;
    return statusResult;
  }

  @override
  Future<bool> openSettings() async {
    openSettingsCalls++;
    return true;
  }
}

class _FakeQRCameraAvailabilityGateway implements QRCameraAvailabilityGateway {
  _FakeQRCameraAvailabilityGateway({required this.available});

  final bool available;
  int calls = 0;

  @override
  Future<bool> hasCamera() async {
    calls++;
    return available;
  }
}
