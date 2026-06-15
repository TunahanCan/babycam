import 'package:flutter/material.dart';

import 'babycam_colors.dart';

class BabyCamTheme {
  static ThemeData serverTheme() => _theme(BabyCamColors.brandPink, BabyCamColors.brandPinkSoft, BabyCamColors.brandPinkDark);
  static ThemeData clientTheme() => _theme(BabyCamColors.brandBlue, BabyCamColors.brandBlueSoft, BabyCamColors.brandBlueDark);
  static ThemeData neutralTheme() => _theme(BabyCamColors.brandBlue, BabyCamColors.background, BabyCamColors.brandPinkDark);

  static ThemeData _theme(Color primary, Color surface, Color secondary) => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: primary, primary: primary, secondary: secondary, surface: surface),
        scaffoldBackgroundColor: surface,
        cardTheme: CardThemeData(elevation: 0, color: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24))),
      );
}
