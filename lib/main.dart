import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'l10n/app_strings.dart';

import 'ui/home_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BabyCamApp());
}

class BabyCamApp extends StatelessWidget {
  const BabyCamApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'BabyCam',
        theme: ThemeData(colorSchemeSeed: Colors.pink, useMaterial3: true),
        supportedLocales: AppStrings.supportedLocales,
        localizationsDelegates: const [
          AppStrings.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const HomePage(),
      );
}
