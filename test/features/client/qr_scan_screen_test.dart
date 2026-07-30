import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miucam/core/media/camera_permission_gateway.dart';
import 'package:miucam/features/client/pairing/qr_scan_screen.dart';
import 'package:miucam/l10n/app_strings.dart';

void main() {
  testWidgets('kamera izni reddedilince manuel QR girişi açık kalır',
      (tester) async {
    final gateway = _FakeQRCameraPermissionGateway(
      statusResult: CameraPermissionStatus.denied,
      requestResult: CameraPermissionStatus.denied,
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
      statusResult: CameraPermissionStatus.permanentlyDenied,
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
      statusResult: CameraPermissionStatus.granted,
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

  testWidgets(
      'manuel QR girişi boşken gönderilemez ve erişilebilir etiketi var',
      (tester) async {
    final gateway = _FakeQRCameraPermissionGateway(
      statusResult: CameraPermissionStatus.denied,
      requestResult: CameraPermissionStatus.denied,
    );

    await tester.pumpWidget(_App(gateway: gateway));
    await tester.pump();
    await tester.pump();

    final submitFinder = find.byKey(const ValueKey('qr-manual-submit'));
    expect(tester.widget<FilledButton>(submitFinder).onPressed, isNull);
    expect(find.byTooltip('Bağlan'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '  miucam://pair?x=1  ');
    await tester.pump();

    expect(tester.widget<FilledButton>(submitFinder).onPressed, isNotNull);
    expect(
      tester.getSemantics(find.byIcon(Icons.arrow_forward_rounded)).label,
      contains('Bağlan'),
    );
  });

  testWidgets('geçersiz manuel QR tarayıcı ekranını kapatmaz', (tester) async {
    final gateway = _FakeQRCameraPermissionGateway(
      statusResult: CameraPermissionStatus.denied,
      requestResult: CameraPermissionStatus.denied,
    );

    await tester.pumpWidget(_App(gateway: gateway));
    await tester.pump();
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'https://example.com');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('qr-manual-submit')));
    await tester.pump();

    expect(find.byType(QRScanScreen), findsOneWidget);
    expect(
      find.text('Geçersiz veya süresi dolmuş MiuCam QR kodu.'),
      findsOneWidget,
    );

    await tester.pump(const Duration(seconds: 1));
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('qr-manual-submit')),
          )
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('dar yatay ekranda ve büyük metinde içerik taşmaz',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(667, 320));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final gateway = _FakeQRCameraPermissionGateway(
      statusResult: CameraPermissionStatus.denied,
      requestResult: CameraPermissionStatus.denied,
    );

    await tester.pumpWidget(
      _App(
        gateway: gateway,
        textScaler: const TextScaler.linear(2),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('QR kod metni'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'dar yatay ekranda klavye açıkken manuel giriş kaydırılabilir kalır',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(667, 320));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    addTearDown(tester.view.resetViewInsets);
    final gateway = _FakeQRCameraPermissionGateway(
      statusResult: CameraPermissionStatus.denied,
      requestResult: CameraPermissionStatus.denied,
    );

    await tester.pumpWidget(
      _App(
        gateway: gateway,
        textScaler: const TextScaler.linear(2),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.showKeyboard(find.byType(TextField));
    tester.view.viewInsets = const FakeViewPadding(bottom: 200);
    await tester.pump();

    expect(
      find.byKey(const ValueKey('qr-keyboard-scroll')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('qr-manual-entry-panel')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    await tester.enterText(find.byType(TextField), 'miucam://pair?x=1');
    await tester.ensureVisible(
      find.byKey(const ValueKey('qr-manual-submit')),
    );
    await tester.pump();

    expect(find.byType(TextField).hitTestable(), findsOneWidget);
    expect(
      find.byKey(const ValueKey('qr-manual-submit')).hitTestable(),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('qr-manual-submit')),
          )
          .onPressed,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
  });
}

class _App extends StatelessWidget {
  const _App({
    required this.gateway,
    this.cameraAvailabilityGateway,
    this.textScaler,
  });

  final CameraPermissionGateway gateway;
  final QRCameraAvailabilityGateway? cameraAvailabilityGateway;
  final TextScaler? textScaler;

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
      builder: textScaler == null
          ? null
          : (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(textScaler: textScaler),
                child: child!,
              ),
      home: QRScanScreen(
        permissionGateway: gateway,
        cameraAvailabilityGateway: cameraAvailabilityGateway ??
            _FakeQRCameraAvailabilityGateway(available: true),
      ),
    );
  }
}

class _FakeQRCameraPermissionGateway implements CameraPermissionGateway {
  _FakeQRCameraPermissionGateway({
    required this.statusResult,
    this.requestResult,
  });

  CameraPermissionStatus statusResult;
  final CameraPermissionStatus? requestResult;
  int statusCalls = 0;
  int requestCalls = 0;
  int openSettingsCalls = 0;

  @override
  Future<CameraPermissionStatus> status() async {
    statusCalls++;
    return statusResult;
  }

  @override
  Future<CameraPermissionStatus> request() async {
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
