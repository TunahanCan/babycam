import 'package:flutter/material.dart';

import '../../../core/theme/mimicam_colors.dart';

class MimiCamDesignTokens {
  const MimiCamDesignTokens._();

  static const cream = Color(0xFFF8FAFC);
  static const blushSoft = Color(0xFFF2F0FF);
  static const nightPlum = Color(0xFF162033);
  static const plumSurface = Color(0xFF27354A);
  static const navy = nightPlum;
  static const slate = Color(0xFF687083);
  static const pink = Color(0xFF6257C8);
  static const mint = Color(0xFF39A88B);
  static const mintSoft = Color(0xFFE1F5EF);
  static const serverInk = MimiCamColors.serverBackground;
  static const serverNavy = MimiCamColors.serverBackgroundTop;
  static const serverPanel = MimiCamColors.serverSurface;
  static const serverSurfaceRaised = MimiCamColors.serverSurfaceRaised;
  static const serverOutline = MimiCamColors.serverOutline;
  static const serverText = MimiCamColors.serverText;
  static const serverTextMuted = MimiCamColors.serverTextMuted;
  static const serverCyan = MimiCamColors.serverPrimary;
  static const serverCyanDeep = MimiCamColors.serverPrimaryPressed;
  static const serverBlue = MimiCamColors.serverInfo;
  static const serverViolet = MimiCamColors.serverLavender;
  static const serverSuccess = MimiCamColors.serverSuccess;
  static const serverWarning = MimiCamColors.serverWarning;
  static const serverError = MimiCamColors.serverError;
  static const serverDisabled = MimiCamColors.serverDisabled;
  static const serverIce = MimiCamColors.serverLightSurface;
  static const serverLightInk = MimiCamColors.serverLightInk;
  static const serverCyanOnLight = MimiCamColors.serverPrimaryOnLight;
  static const serverBlueOnLight = MimiCamColors.serverInfoOnLight;
  static const serverVioletOnLight = MimiCamColors.serverLavenderOnLight;
  static const amber = Color(0xFFD69B2D);
  static const amberSoft = Color(0xFFFFF5DE);
  static const lavenderSoft = Color(0xFFEEF0FF);
  static const lightClientBg = cream;
  static const softRed = pink;

  static const screenPadding = EdgeInsets.fromLTRB(20, 14, 20, 24);
  static const cardPadding = EdgeInsets.all(18);

  static const title = TextStyle(
    color: navy,
    fontSize: 31,
    height: 1.08,
    fontWeight: FontWeight.w900,
  );

  static const darkTitle = TextStyle(
    color: Colors.white,
    fontSize: 32,
    height: 1.08,
    fontWeight: FontWeight.w900,
  );

  static const subtitle = TextStyle(
    color: slate,
    fontSize: 16,
    height: 1.26,
  );

  static const darkSubtitle = TextStyle(
    color: Colors.white70,
    fontSize: 16,
    height: 1.26,
  );

  static const cardTitle = TextStyle(
    color: navy,
    fontSize: 18,
    fontWeight: FontWeight.w900,
  );

  static BoxDecoration cardDecoration({bool dark = false}) {
    return BoxDecoration(
      color: dark ? serverPanel.withValues(alpha: .96) : Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(
        color: dark
            ? serverOutline.withValues(alpha: .66)
            : const Color(0xFFE2E8F0),
      ),
      boxShadow: [
        BoxShadow(
          color: dark
              ? Colors.black.withValues(alpha: .24)
              : const Color(0x12111827),
          blurRadius: dark ? 18 : 16,
          offset: const Offset(0, 7),
        ),
      ],
    );
  }
}
