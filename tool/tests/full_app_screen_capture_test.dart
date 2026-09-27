// Host-only screen review: no APK installation, device storage or real camera.
// flutter test tool/tests/full_app_screen_capture_test.dart \
//   --dart-define=MIUCAM_SCREENSHOT_FONT_DIR=/path/to/Roboto-and-MaterialIcons
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miucam/l10n/app_strings.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../screen_report_device_app.dart';

const _scenes = [
  ('01_role', 'role', 0),
  ('02_parent_unpaired', 'client_unpaired', 0),
  ('03_find_room', 'client_unpaired', 1),
  ('04_notifications', 'client_unpaired', 2),
  ('05_parent_settings', 'client_unpaired', 3),
  ('06_parent_paired', 'client_paired', 0),
  ('07_qr_permission_denied', 'qr_scanner', 0),
  ('08_watch_live', 'watch', 0),
  ('09_watch_history', 'watch', 1),
  ('10_watch_settings', 'watch', 2),
  ('11_room_controls', 'watch_controls', 0),
  ('12_watch_connection_error', 'watch_error', 0),
  ('13_server_preview_off', 'server', 0),
  ('14_server_preview_on', 'server_preview_on', 0),
  ('15_server_qr_ip', 'server', 1),
  ('16_server_services', 'server', 2),
  ('17_server_settings', 'server', 3),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const fontRoot = String.fromEnvironment('MIUCAM_SCREENSHOT_FONT_DIR');
  final previousHttpOverrides = HttpOverrides.current;
  setUpAll(() async {
    expect(fontRoot, isNotEmpty,
        reason: 'Real fonts are required for a useful visual review.');
    // Only the scene's generated loopback media is fetched. A widget test's
    // default HTTP-400 override would turn a live screen into a false error.
    HttpOverrides.global = null;
    for (final font in [
      ('MaterialIcons', 'MaterialIcons-Regular.otf'),
      ('Roboto', 'Roboto-Regular.ttf'),
      ('ReviewText', 'Roboto-Regular.ttf'),
      ('ReviewEmoji', 'NotoColorEmoji.ttf'),
    ]) {
      final loader = FontLoader(font.$1)
        ..addFont(File('$fontRoot/${font.$2}')
            .readAsBytes()
            .then(ByteData.sublistView));
      await loader.load();
    }
    await Directory('build/app_acceptance/screens').create(recursive: true);
  });
  tearDownAll(() => HttpOverrides.global = previousHttpOverrides);

  for (final spec in _scenes) {
    testWidgets('capture actual ${spec.$1} screen', (tester) async {
      // A font/layout change may make a previously scrollable scene fit. Do
      // not leave an obsolete bottom capture in the next review's gallery.
      await tester.runAsync(() async {
        for (final suffix in ['', '_bottom']) {
          final file =
              File('build/app_acceptance/screens/${spec.$1}$suffix.png');
          if (await file.exists()) await file.delete();
        }
      });
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      // ignore: invalid_use_of_visible_for_testing_member
      SharedPreferences.setMockInitialValues({});
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        const MethodChannel('miucam/pcm_audio'),
        (call) async => call.method == 'status'
            ? <String, Object?>{'queuedBytes': 0}
            : true,
      );
      addTearDown(() => messenger.setMockMethodCallHandler(
          const MethodChannel('miucam/pcm_audio'), null));
      final scene = await tester.runAsync(() => buildScreenReportScene(
            spec.$2,
            tab: spec.$3,
            themeTransform: _withRealFonts,
          ));
      expect(scene, isNotNull);
      final key = GlobalKey();
      try {
        await tester.pumpWidget(MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: _withRealFonts(ThemeData()),
          locale: const Locale('tr'),
          supportedLocales: AppStrings.supportedLocales,
          localizationsDelegates: const [
            AppStrings.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: RepaintBoundary(key: key, child: scene!.child),
        ));
        await _waitForScene(tester, scene);
        await _capture(tester, key, spec.$1);
        final scrollable = find.byType(Scrollable).first;
        if (scrollable.evaluate().isNotEmpty) {
          final position = tester.state<ScrollableState>(scrollable).position;
          if (position.maxScrollExtent > 1) {
            position.jumpTo(position.maxScrollExtent);
            await tester.pump(const Duration(milliseconds: 200));
            await _capture(tester, key, '${spec.$1}_bottom');
          }
        }
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        var completed = false;
        Object? failure;
        final closing = scene!.dispose().then((_) => completed = true,
            onError: (Object error, StackTrace stack) {
          failure = error;
          completed = true;
        });
        for (var frame = 0; frame < 100 && !completed; frame++) {
          await tester.pump(const Duration(milliseconds: 50));
          await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 10)));
        }
        expect(completed, isTrue, reason: 'Scene media must close.');
        await closing;
        if (failure != null) throw failure!;
      }
    });
  }
}

ThemeData _withRealFonts(ThemeData theme) {
  TextStyle textStyle(TextStyle? style) =>
      (style ?? const TextStyle()).copyWith(
        fontFamily: 'ReviewText',
        fontFamilyFallback: const ['ReviewEmoji'],
      );
  ButtonStyle buttonStyle(ButtonStyle? style) =>
      (style ?? const ButtonStyle()).copyWith(
        textStyle: WidgetStateProperty.resolveWith((states) => textStyle(
            style?.textStyle?.resolve(states) ?? theme.textTheme.labelLarge)),
      );
  return theme.copyWith(
    textTheme: theme.textTheme.apply(
        fontFamily: 'ReviewText', fontFamilyFallback: const ['ReviewEmoji']),
    primaryTextTheme: theme.primaryTextTheme.apply(
        fontFamily: 'ReviewText', fontFamilyFallback: const ['ReviewEmoji']),
    filledButtonTheme: FilledButtonThemeData(
        style: buttonStyle(theme.filledButtonTheme.style)),
    outlinedButtonTheme: OutlinedButtonThemeData(
        style: buttonStyle(theme.outlinedButtonTheme.style)),
    textButtonTheme:
        TextButtonThemeData(style: buttonStyle(theme.textButtonTheme.style)),
    elevatedButtonTheme: ElevatedButtonThemeData(
        style: buttonStyle(theme.elevatedButtonTheme.style)),
  );
}

Future<void> _waitForScene(
    WidgetTester tester, ReportSceneFixture scene) async {
  final matcher = scene.readyWidget;
  for (var frame = 0; frame < 100; frame++) {
    await tester.pump(const Duration(milliseconds: 50));
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    if (frame >= 5 &&
        (matcher == null ||
            find.byWidgetPredicate(matcher).evaluate().isNotEmpty)) {
      expect(tester.takeException(), isNull);
      return;
    }
  }
  fail('The actual media frame did not arrive; do not capture a placeholder.');
}

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  // A widget-local ButtonStyle can replace the theme's entire TextStyle. On a
  // phone its unspecified family resolves to Roboto; flutter_tester uses Ahem.
  // Bind that host-only default before layout, preserving explicit icon fonts,
  // all text, styles and semantics. No product widget is replaced for capture.
  // The first layout can rebuild a responsive button row after scrolling.
  for (var pass = 0; pass < 2; pass++) {
    _bindDefaultFont(key.currentContext!.findRenderObject()!);
    await tester.pump();
  }
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('build/app_acceptance/screens/$name.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

void _bindDefaultFont(RenderObject object) {
  if (object is RenderParagraph) {
    object.text = _withDefaultFont(object.text, null);
  }
  object.visitChildren(_bindDefaultFont);
}

InlineSpan _withDefaultFont(InlineSpan span, String? inheritedFamily) {
  if (span is! TextSpan) return span;
  final style = span.style ?? const TextStyle();
  final requestedFamily = style.fontFamily ?? inheritedFamily;
  final family = requestedFamily == null || requestedFamily == 'Ahem'
      ? 'ReviewText'
      : requestedFamily;
  return TextSpan(
    text: span.text,
    style: style.copyWith(
      fontFamily: family,
      fontFamilyFallback: style.fontFamilyFallback ?? const ['ReviewEmoji'],
    ),
    children:
        span.children?.map((child) => _withDefaultFont(child, family)).toList(),
    recognizer: span.recognizer,
    mouseCursor: span.mouseCursor,
    onEnter: span.onEnter,
    onExit: span.onExit,
    semanticsLabel: span.semanticsLabel,
    semanticsIdentifier: span.semanticsIdentifier,
    locale: span.locale,
    spellOut: span.spellOut,
  );
}
