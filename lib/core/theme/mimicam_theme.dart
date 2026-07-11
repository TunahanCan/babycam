import 'package:flutter/material.dart';

import 'mimicam_colors.dart';

class MimiCamTheme {
  static ThemeData serverTheme() {
    const scheme = ColorScheme.dark(
      primary: MimiCamColors.serverPrimary,
      onPrimary: MimiCamColors.serverBackground,
      primaryContainer: MimiCamColors.serverSurfaceRaised,
      onPrimaryContainer: MimiCamColors.serverText,
      secondary: MimiCamColors.serverInfo,
      onSecondary: MimiCamColors.serverBackground,
      secondaryContainer: MimiCamColors.serverSurfaceRaised,
      onSecondaryContainer: MimiCamColors.serverText,
      tertiary: MimiCamColors.serverLavender,
      onTertiary: MimiCamColors.serverBackground,
      error: MimiCamColors.serverError,
      onError: MimiCamColors.serverBackground,
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
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: MimiCamColors.serverBackground,
      canvasColor: MimiCamColors.serverBackground,
      cardTheme: CardThemeData(
        elevation: 0,
        color: MimiCamColors.serverSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: MimiCamColors.serverSurface,
        modalBackgroundColor: MimiCamColors.serverSurface,
        showDragHandle: true,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: MimiCamColors.serverSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: MimiCamColors.serverSurfaceRaised,
        contentTextStyle: TextStyle(color: MimiCamColors.serverText),
      ),
      sliderTheme: const SliderThemeData(
        inactiveTrackColor: MimiCamColors.serverOutline,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: MimiCamColors.serverSurfaceRaised,
        selectedColor: MimiCamColors.serverPrimary.withValues(alpha: .18),
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
                borderRadius: BorderRadius.circular(24))),
      );
}
