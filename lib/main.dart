import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app/app_bootstrap.dart';
import 'l10n/app_strings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BabyCamApp());
}

class BabyCamApp extends StatelessWidget {
  const BabyCamApp({super.key});
  @override Widget build(BuildContext context) => MaterialApp(
    title: 'BabyCam',
    supportedLocales: AppStrings.supportedLocales,
    localizationsDelegates: const [AppStrings.delegate, GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
    home: const AppBootstrap(),
  );
}
