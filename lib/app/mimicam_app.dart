import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../core/theme/mimicam_theme.dart';
import '../l10n/app_strings.dart';
import 'app_bootstrap.dart';

class MimiCamApp extends StatefulWidget {
  const MimiCamApp({super.key});

  @override
  State<MimiCamApp> createState() => _MimiCamAppState();
}

class _MimiCamAppState extends State<MimiCamApp> {
  Locale? _locale;

  void _setLocale(Locale? locale) {
    if (_locale == locale) return;
    setState(() => _locale = locale);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MimiCam',
      theme: MimiCamTheme.neutralTheme(),
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
