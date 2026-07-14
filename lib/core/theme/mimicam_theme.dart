import 'package:flutter/material.dart';

import 'mimicam_colors.dart';

class MimiCamTheme {
  static ThemeData serverTheme() {
    const scheme = ColorScheme.light(
      primary: MimiCamColors.serverPrimary,
      onPrimary: Colors.white,
      primaryContainer: MimiCamColors.serverSurfaceRaised,
      onPrimaryContainer: MimiCamColors.serverText,
      secondary: MimiCamColors.serverInfo,
      onSecondary: Colors.white,
      secondaryContainer: MimiCamColors.serverSurfaceRaised,
      onSecondaryContainer: MimiCamColors.serverText,
      tertiary: MimiCamColors.serverLavender,
      onTertiary: Colors.white,
      error: MimiCamColors.serverError,
      onError: Colors.white,
      surface: MimiCamColors.serverSurface,
      onSurface: MimiCamColors.serverText,
      outline: MimiCamColors.serverOutline,
      outlineVariant: MimiCamColors.serverBackgroundTop,
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: MimiCamColors.serverLightSurface,
      onInverseSurface: MimiCamColors.serverLightInk,
      inversePrimary: MimiCamColors.serverPrimaryPressed,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: scheme,
      scaffoldBackgroundColor: MimiCamColors.serverBackground,
      canvasColor: MimiCamColors.serverBackground,
      cardTheme: CardThemeData(
        elevation: 0,
        color: MimiCamColors.serverSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.white,
        modalBackgroundColor: Colors.white,
        showDragHandle: true,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: MimiCamColors.serverSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: MimiCamColors.serverText,
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
        inactiveTrackColor: MimiCamColors.serverOutline,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: MimiCamColors.serverSurfaceRaised,
        selectedColor: MimiCamColors.serverSurfaceRaised,
        side: const BorderSide(color: MimiCamColors.serverOutline),
        labelStyle: const TextStyle(color: MimiCamColors.serverTextMuted),
        secondaryLabelStyle: const TextStyle(color: MimiCamColors.serverText),
        checkmarkColor: MimiCamColors.serverPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }

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
