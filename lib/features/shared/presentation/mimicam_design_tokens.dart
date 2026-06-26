import 'package:flutter/material.dart';

class MimiCamDesignTokens {
  const MimiCamDesignTokens._();

  static const cream = Color(0xFFFFF8F3);
  static const blushSoft = Color(0xFFFFE3EA);
  static const nightPlum = Color(0xFF2B223B);
  static const plumSurface = Color(0xFF3A2D4D);
  static const navy = nightPlum;
  static const slate = Color(0xFF687083);
  static const pink = Color(0xFFFF5C7C);
  static const mint = Color(0xFF6EDCCE);
  static const mintSoft = Color(0xFFDDF8F4);
  static const serverInk = Color(0xFF0B2634);
  static const serverNavy = Color(0xFF276F82);
  static const serverPanel = Color(0xFF1B5265);
  static const serverCyan = Color(0xFF9BEFE4);
  static const serverCyanDeep = Color(0xFF59D0C6);
  static const serverBlue = Color(0xFF82CDE8);
  static const serverViolet = Color(0xFFB7EAD6);
  static const serverIce = Color(0xFFF4FFFC);
  static const amber = Color(0xFFF5C451);
  static const amberSoft = Color(0xFFFFF0D8);
  static const lavenderSoft = Color(0xFFF2EEFA);
  static const lightClientBg = cream;
  static const softRed = pink;

  static const screenPadding = EdgeInsets.fromLTRB(22, 14, 22, 24);
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
      color: dark ? serverPanel.withValues(alpha: .90) : Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(
        color:
            dark ? serverCyan.withValues(alpha: .34) : const Color(0xFFEEDFD8),
      ),
      boxShadow: [
        BoxShadow(
          color: dark
              ? serverBlue.withValues(alpha: .30)
              : const Color(0x14111827),
          blurRadius: dark ? 26 : 14,
          offset: const Offset(0, 7),
        ),
      ],
    );
  }
}
