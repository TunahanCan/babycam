import 'package:flutter/material.dart';

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
        home: const HomePage(),
      );
}
