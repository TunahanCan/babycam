import 'package:flutter/material.dart';

import '../../../core/theme/miucam_colors.dart';

class MiuCamDesignTokens {
  const MiuCamDesignTokens._();

  static const cream = Color(0xFFF8FAFC);
  static const blushSoft = Color(0xFFF2F0FF);
  static const nightPlum = Color(0xFF162033);
  static const plumSurface = Color(0xFF27354A);
  static const navy = nightPlum;
  static const slate = Color(0xFF687083);
  static const pink = Color(0xFF6257C8);
  static const mint = Color(0xFF39A88B);
  static const mintSoft = Color(0xFFE1F5EF);
  static const serverInk = MiuCamColors.serverBackground;
  static const serverNavy = MiuCamColors.serverBackgroundTop;
  static const serverPanel = MiuCamColors.serverSurface;
  static const serverSurfaceRaised = MiuCamColors.serverSurfaceRaised;
  static const serverOutline = MiuCamColors.serverOutline;
  static const serverText = MiuCamColors.serverText;
  static const serverTextMuted = MiuCamColors.serverTextMuted;
  static const serverOnAccent = Colors.white;
  static const serverCyan = MiuCamColors.serverPrimary;
  static const serverCyanDeep = MiuCamColors.serverPrimaryPressed;
  static const serverBlue = MiuCamColors.serverInfo;
  static const serverViolet = MiuCamColors.serverLavender;
  static const serverSuccess = MiuCamColors.serverSuccess;
  static const serverWarning = MiuCamColors.serverWarning;
  static const serverError = MiuCamColors.serverError;
  static const serverDisabled = MiuCamColors.serverDisabled;
  static const serverIce = MiuCamColors.serverLightSurface;
  static const serverLightInk = MiuCamColors.serverLightInk;
  static const serverCyanOnLight = MiuCamColors.serverPrimaryOnLight;
  static const serverBlueOnLight = MiuCamColors.serverInfoOnLight;
  static const serverVioletOnLight = MiuCamColors.serverLavenderOnLight;
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
      color: dark ? serverPanel : Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(
        color: dark
            ? serverOutline.withValues(alpha: .66)
            : const Color(0xFFE2E8F0),
      ),
      boxShadow: [
        BoxShadow(
          color: dark ? const Color(0x1424493D) : const Color(0x12111827),
          blurRadius: dark ? 20 : 16,
          offset: const Offset(0, 8),
        ),
      ],
    );
  }
}
