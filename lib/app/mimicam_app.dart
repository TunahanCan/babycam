import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../core/theme/mimicam_theme.dart';
import '../l10n/app_strings.dart';
import 'app_bootstrap.dart';

class MimiCamApp extends StatelessWidget {
  const MimiCamApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MimiCam',
      theme: MimiCamTheme.neutralTheme(),
      supportedLocales: AppStrings.supportedLocales,
      localizationsDelegates: const [
        AppStrings.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const AppBootstrap(),
    );
  }
}
