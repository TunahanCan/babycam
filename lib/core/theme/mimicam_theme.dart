import 'package:flutter/material.dart';

import 'mimicam_colors.dart';

class MimiCamTheme {
  static ThemeData serverTheme() => _theme(MimiCamColors.brandPink,
      MimiCamColors.brandPinkSoft, MimiCamColors.brandPinkDark);
  static ThemeData clientTheme() => _theme(MimiCamColors.brandBlue,
      MimiCamColors.brandBlueSoft, MimiCamColors.brandBlueDark);
  static ThemeData neutralTheme() => _theme(MimiCamColors.brandBlue,
      MimiCamColors.background, MimiCamColors.brandPinkDark);

  static ThemeData _theme(Color primary, Color surface, Color secondary) =>
      ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
            seedColor: primary,
            primary: primary,
            secondary: secondary,
            surface: surface),
        scaffoldBackgroundColor: surface,
        cardTheme: CardThemeData(
            elevation: 0,
            color: Colors.white,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24))),
      );
}
