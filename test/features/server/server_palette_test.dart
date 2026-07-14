import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimicam/core/theme/mimicam_colors.dart';
import 'package:mimicam/core/theme/mimicam_theme.dart';
import 'package:mimicam/features/shared/presentation/mimicam_design_tokens.dart';
import 'package:mimicam/features/server/presentation/server_home_components.dart';

void main() {
  test('server destinasyonları tip güvenli ve dış indekslere dayanıklıdır', () {
    expect(
      ServerHomeDestination.fromIndex(-1),
      ServerHomeDestination.stream,
    );
    expect(
      ServerHomeDestination.fromIndex(99),
      ServerHomeDestination.settings,
    );
    expect(
      ServerHomeDestination.values
          .map((destination) => destination.viewKey)
          .toSet(),
      hasLength(ServerHomeDestination.values.length),
    );
  });

  test('server theme ferah açık paleti kullanır ve client seedine düşmez', () {
    final theme = MimiCamTheme.serverTheme();

    expect(theme.brightness, Brightness.light);
    expect(theme.scaffoldBackgroundColor, MimiCamColors.serverBackground);
    expect(
      theme.scaffoldBackgroundColor.computeLuminance(),
      greaterThan(.85),
    );
    expect(theme.colorScheme.primary, MimiCamColors.serverPrimary);
    expect(theme.colorScheme.surface, MimiCamColors.serverSurface);
    expect(theme.colorScheme.primary, isNot(MimiCamColors.brandPink));
  });

  test('server metin ve semantik durum renkleri panel üzerinde AA taşır', () {
    const surface = MimiCamDesignTokens.serverPanel;
    const colors = {
      'primary text': MimiCamDesignTokens.serverText,
      'muted text': MimiCamDesignTokens.serverTextMuted,
      'primary action': MimiCamDesignTokens.serverCyan,
      'information': MimiCamDesignTokens.serverBlue,
      'secondary': MimiCamDesignTokens.serverViolet,
      'success': MimiCamDesignTokens.serverSuccess,
      'warning': MimiCamDesignTokens.serverWarning,
      'error': MimiCamDesignTokens.serverError,
      'disabled': MimiCamDesignTokens.serverDisabled,
    };

    for (final entry in colors.entries) {
      expect(
        _contrastRatio(entry.value, surface),
        greaterThanOrEqualTo(4.5),
        reason: '${entry.key} panel üzerinde yetersiz kontrastta',
      );
    }
  });

  test('server durum renkleri üzerindeki ikonlar AA kontrastı taşır', () {
    const colors = [
      MimiCamDesignTokens.serverCyan,
      MimiCamDesignTokens.serverBlue,
      MimiCamDesignTokens.serverViolet,
      MimiCamDesignTokens.serverSuccess,
      MimiCamDesignTokens.serverWarning,
      MimiCamDesignTokens.serverError,
      MimiCamDesignTokens.serverDisabled,
    ];

    for (final color in colors) {
      expect(
        _contrastRatio(MimiCamDesignTokens.serverOnAccent, color),
        greaterThanOrEqualTo(4.5),
      );
    }
  });
}

double _contrastRatio(Color first, Color second) {
  final firstLuminance = first.computeLuminance();
  final secondLuminance = second.computeLuminance();
  final lighter = math.max(firstLuminance, secondLuminance);
  final darker = math.min(firstLuminance, secondLuminance);
  return (lighter + .05) / (darker + .05);
}
