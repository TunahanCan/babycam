import 'dart:convert';
import 'dart:ui' show FrameTiming;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:miucam/app/app_role.dart';
import 'package:miucam/features/server/media/media_runtime_controller.dart';
import 'package:miucam/features/server/server_home_screen.dart';
import 'package:miucam/features/server/server_runtime.dart';
import 'package:miucam/l10n/app_strings.dart';
import 'package:miucam/services/configuration_service.dart';

final _frameP95BudgetMs = double.parse(
  const String.fromEnvironment(
    'MIUCAM_FRAME_P95_BUDGET_MS',
    defaultValue: '35',
  ),
);
const _minimumFrameSamples = 30;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'server settings slider and scroll stay inside frame-time p95 budget',
    (tester) async {
      expect(
        kProfileMode,
        isTrue,
        reason: 'Frame-time benchmark must run with flutter drive --profile.',
      );
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final runtime = ServerRuntime(
        mediaRuntime: MediaRuntimeController(),
        onStartPairing: () async => 'miucam://pair?payload=benchmark',
      );
      addTearDown(runtime.dispose);

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('tr'),
          supportedLocales: AppStrings.supportedLocales,
          localizationsDelegates: const [
            AppStrings.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: ServerHomeScreen(
            runtime: runtime,
            config: ConfigurationService(preferences),
            activeRole: AppRole.server,
            onRoleSelected: (_) {},
            initialTab: 3,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.timedDrag(
        find.byKey(const ValueKey('server-settings')),
        const Offset(0, -320),
        const Duration(milliseconds: 450),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('İleri ayarlar'));
      await tester.pumpAndSettle();
      expect(find.byType(Slider), findsNWidgets(5));

      final firstSlider = find.byType(Slider).first;
      await tester.scrollUntilVisible(
        firstSlider,
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await _warmUpSlider(tester, firstSlider);
      final slider = await _measureFrames(
        tester,
        () async {
          for (var iteration = 0; iteration < 4; iteration++) {
            final direction = iteration.isEven ? 1.0 : -1.0;
            await tester.timedDrag(
              firstSlider,
              Offset(105 * direction, 0),
              const Duration(milliseconds: 650),
            );
          }
          await tester.pumpAndSettle();
        },
      );

      final scrollable = find.byType(Scrollable).first;
      await _warmUpScroll(tester, scrollable);
      final scroll = await _measureFrames(
        tester,
        () async {
          for (var iteration = 0; iteration < 3; iteration++) {
            await tester.timedDrag(
              scrollable,
              const Offset(0, -420),
              const Duration(milliseconds: 700),
            );
            await tester.timedDrag(
              scrollable,
              const Offset(0, 420),
              const Duration(milliseconds: 700),
            );
          }
          await tester.pumpAndSettle();
        },
      );

      final view = tester.view;
      final report = <String, Object>{
        'schemaVersion': 1,
        'benchmark': 'server_settings_slider_scroll',
        'mode': 'profile',
        'frameP95BudgetMs': _frameP95BudgetMs,
        'minimumFrameSamples': _minimumFrameSamples,
        'viewport': {
          'physicalWidth': view.physicalSize.width,
          'physicalHeight': view.physicalSize.height,
          'devicePixelRatio': view.devicePixelRatio,
        },
        'scenarios': {
          'slider': slider.toJson(),
          'scroll': scroll.toJson(),
        },
      };
      binding.reportData = report;
      debugPrint(
        'MIUCAM_FRAME_BENCHMARK ${jsonEncode(report)}',
        wrapWidth: 1024,
      );

      for (final entry in {'slider': slider, 'scroll': scroll}.entries) {
        expect(
          entry.value.sampleCount,
          greaterThanOrEqualTo(_minimumFrameSamples),
          reason: '${entry.key} did not produce enough measured frames.',
        );
        expect(
          entry.value.totalP95Ms,
          lessThanOrEqualTo(_frameP95BudgetMs),
          reason: '${entry.key} frame-time p95 exceeded the device budget.',
        );
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

Future<void> _warmUpSlider(WidgetTester tester, Finder slider) async {
  await tester.timedDrag(
    slider,
    const Offset(60, 0),
    const Duration(milliseconds: 350),
  );
  await tester.timedDrag(
    slider,
    const Offset(-60, 0),
    const Duration(milliseconds: 350),
  );
  await tester.pumpAndSettle();
}

Future<void> _warmUpScroll(WidgetTester tester, Finder scrollable) async {
  await tester.timedDrag(
    scrollable,
    const Offset(0, -240),
    const Duration(milliseconds: 350),
  );
  await tester.timedDrag(
    scrollable,
    const Offset(0, 240),
    const Duration(milliseconds: 350),
  );
  await tester.pumpAndSettle();
}

Future<_FrameTimingSummary> _measureFrames(
  WidgetTester tester,
  Future<void> Function() interaction,
) async {
  final timings = <FrameTiming>[];
  void record(List<FrameTiming> batch) => timings.addAll(batch);

  WidgetsBinding.instance.addTimingsCallback(record);
  try {
    await interaction();
    // Frame timings are reported asynchronously in batches by the engine.
    await Future<void>.delayed(const Duration(milliseconds: 250));
  } finally {
    WidgetsBinding.instance.removeTimingsCallback(record);
  }
  return _FrameTimingSummary.from(timings);
}

class _FrameTimingSummary {
  const _FrameTimingSummary({
    required this.sampleCount,
    required this.buildP50Ms,
    required this.buildP95Ms,
    required this.rasterP50Ms,
    required this.rasterP95Ms,
    required this.totalP50Ms,
    required this.totalP95Ms,
    required this.totalMaxMs,
    required this.framesOver16Ms,
    required this.framesOver32Ms,
  });

  factory _FrameTimingSummary.from(List<FrameTiming> timings) {
    final build = timings
        .map((timing) => timing.buildDuration.inMicroseconds / 1000)
        .toList(growable: false);
    final raster = timings
        .map((timing) => timing.rasterDuration.inMicroseconds / 1000)
        .toList(growable: false);
    final total = timings
        .map((timing) => timing.totalSpan.inMicroseconds / 1000)
        .toList(growable: false);
    return _FrameTimingSummary(
      sampleCount: timings.length,
      buildP50Ms: _percentile(build, .50),
      buildP95Ms: _percentile(build, .95),
      rasterP50Ms: _percentile(raster, .50),
      rasterP95Ms: _percentile(raster, .95),
      totalP50Ms: _percentile(total, .50),
      totalP95Ms: _percentile(total, .95),
      totalMaxMs: total.isEmpty
          ? 0
          : total.reduce((current, next) => current > next ? current : next),
      framesOver16Ms: total.where((value) => value > 16.67).length,
      framesOver32Ms: total.where((value) => value > 32).length,
    );
  }

  final int sampleCount;
  final double buildP50Ms;
  final double buildP95Ms;
  final double rasterP50Ms;
  final double rasterP95Ms;
  final double totalP50Ms;
  final double totalP95Ms;
  final double totalMaxMs;
  final int framesOver16Ms;
  final int framesOver32Ms;

  Map<String, Object> toJson() => {
        'sampleCount': sampleCount,
        'buildP50Ms': buildP50Ms,
        'buildP95Ms': buildP95Ms,
        'rasterP50Ms': rasterP50Ms,
        'rasterP95Ms': rasterP95Ms,
        'totalP50Ms': totalP50Ms,
        'totalP95Ms': totalP95Ms,
        'totalMaxMs': totalMaxMs,
        'framesOver16Ms': framesOver16Ms,
        'framesOver32Ms': framesOver32Ms,
        'framesOver16Ratio':
            sampleCount == 0 ? 0 : framesOver16Ms / sampleCount,
        'framesOver32Ratio':
            sampleCount == 0 ? 0 : framesOver32Ms / sampleCount,
      };
}

double _percentile(List<double> values, double percentile) {
  if (values.isEmpty) return 0;
  final sorted = [...values]..sort();
  final rank = (percentile * sorted.length).ceil().clamp(1, sorted.length);
  return sorted[rank - 1];
}
