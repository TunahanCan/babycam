import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mimicam/core/theme/mimicam_colors.dart';
import 'package:mimicam/core/theme/mimicam_theme.dart';
import 'package:mimicam/features/shared/presentation/mimicam_design_tokens.dart';

void main() {
  test('server theme gece paletini kullanır ve pembe client seedine düşmez',
      () {
    final theme = MimiCamTheme.serverTheme();

    expect(theme.brightness, Brightness.dark);
    expect(theme.scaffoldBackgroundColor, MimiCamColors.serverBackground);
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
}

double _contrastRatio(Color first, Color second) {
  final firstLuminance = first.computeLuminance();
  final secondLuminance = second.computeLuminance();
  final lighter = math.max(firstLuminance, secondLuminance);
  final darker = math.min(firstLuminance, secondLuminance);
  return (lighter + .05) / (darker + .05);
}
