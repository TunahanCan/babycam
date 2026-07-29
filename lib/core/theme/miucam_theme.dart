import 'package:flutter/material.dart';

import 'miucam_colors.dart';

class MiuCamTheme {
  static ThemeData serverTheme() {
    const scheme = ColorScheme.light(
      primary: MiuCamColors.serverPrimary,
      onPrimary: Colors.white,
      primaryContainer: MiuCamColors.serverSurfaceRaised,
      onPrimaryContainer: MiuCamColors.serverText,
      secondary: MiuCamColors.serverInfo,
      onSecondary: Colors.white,
      secondaryContainer: MiuCamColors.serverSurfaceRaised,
      onSecondaryContainer: MiuCamColors.serverText,
      tertiary: MiuCamColors.serverLavender,
      onTertiary: Colors.white,
      error: MiuCamColors.serverError,
      onError: Colors.white,
      surface: MiuCamColors.serverSurface,
      onSurface: MiuCamColors.serverText,
      outline: MiuCamColors.serverOutline,
      outlineVariant: MiuCamColors.serverBackgroundTop,
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: MiuCamColors.serverLightSurface,
      onInverseSurface: MiuCamColors.serverLightInk,
      inversePrimary: MiuCamColors.serverPrimaryPressed,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: scheme,
      scaffoldBackgroundColor: MiuCamColors.serverBackground,
      canvasColor: MiuCamColors.serverBackground,
      cardTheme: CardThemeData(
        elevation: 0,
        color: MiuCamColors.serverSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.white,
        modalBackgroundColor: Colors.white,
        showDragHandle: true,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: MiuCamColors.serverSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: MiuCamColors.serverText,
        contentTextStyle: TextStyle(color: Colors.white),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      sliderTheme: const SliderThemeData(
        inactiveTrackColor: MiuCamColors.serverOutline,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: MiuCamColors.serverSurfaceRaised,
        selectedColor: MiuCamColors.serverSurfaceRaised,
        side: const BorderSide(color: MiuCamColors.serverOutline),
        labelStyle: const TextStyle(color: MiuCamColors.serverTextMuted),
        secondaryLabelStyle: const TextStyle(color: MiuCamColors.serverText),
        checkmarkColor: MiuCamColors.serverPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }

  static ThemeData clientTheme() => _theme(MiuCamColors.brandBlue,
      MiuCamColors.brandBlueSoft, MiuCamColors.brandBlueDark);
  static ThemeData neutralTheme() => _theme(MiuCamColors.brandBlue,
      MiuCamColors.background, MiuCamColors.brandPinkDark);

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
                borderRadius: BorderRadius.circular(18))),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size(48, 48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            textStyle: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(48, 48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            textStyle: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: primary, width: 2),
          ),
        ),
      );
}
