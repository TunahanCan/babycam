import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:miucam/core/theme/miucam_colors.dart';
import 'package:miucam/core/theme/miucam_theme.dart';
import 'package:miucam/features/shared/presentation/miucam_design_tokens.dart';
import 'package:miucam/features/server/presentation/server_home_components.dart';

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
    final theme = MiuCamTheme.serverTheme();

    expect(theme.brightness, Brightness.light);
    expect(theme.scaffoldBackgroundColor, MiuCamColors.serverBackground);
    expect(
      theme.scaffoldBackgroundColor.computeLuminance(),
      greaterThan(.85),
    );
    expect(theme.colorScheme.primary, MiuCamColors.serverPrimary);
    expect(theme.colorScheme.surface, MiuCamColors.serverSurface);
    expect(theme.colorScheme.primary, isNot(MiuCamColors.brandPink));
  });

  test('server metin ve semantik durum renkleri panel üzerinde AA taşır', () {
    const surface = MiuCamDesignTokens.serverPanel;
    const colors = {
      'primary text': MiuCamDesignTokens.serverText,
      'muted text': MiuCamDesignTokens.serverTextMuted,
      'primary action': MiuCamDesignTokens.serverCyan,
      'information': MiuCamDesignTokens.serverBlue,
      'secondary': MiuCamDesignTokens.serverViolet,
      'success': MiuCamDesignTokens.serverSuccess,
      'warning': MiuCamDesignTokens.serverWarning,
      'error': MiuCamDesignTokens.serverError,
      'disabled': MiuCamDesignTokens.serverDisabled,
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
      MiuCamDesignTokens.serverCyan,
      MiuCamDesignTokens.serverBlue,
      MiuCamDesignTokens.serverViolet,
      MiuCamDesignTokens.serverSuccess,
      MiuCamDesignTokens.serverWarning,
      MiuCamDesignTokens.serverError,
      MiuCamDesignTokens.serverDisabled,
    ];

    for (final color in colors) {
      expect(
        _contrastRatio(MiuCamDesignTokens.serverOnAccent, color),
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
