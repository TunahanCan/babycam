import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../core/theme/miucam_theme.dart';
import '../l10n/app_strings.dart';
import 'app_bootstrap.dart';

class MiuCamApp extends StatefulWidget {
  const MiuCamApp({super.key});

  @override
  State<MiuCamApp> createState() => _MiuCamAppState();
}

class _MiuCamAppState extends State<MiuCamApp> {
  Locale? _locale;

  void _setLocale(Locale? locale) {
    if (_locale == locale) return;
    setState(() => _locale = locale);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MiuCam',
      theme: MiuCamTheme.neutralTheme(),
      locale: _locale,
      supportedLocales: AppStrings.supportedLocales,
      localizationsDelegates: const [
        AppStrings.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: AppBootstrap(onLocaleChanged: _setLocale),
    );
  }
}
