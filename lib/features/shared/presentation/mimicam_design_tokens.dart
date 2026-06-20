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
      color: dark ? plumSurface : Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(
        color: dark
            ? Colors.white.withValues(alpha: .12)
            : const Color(0xFFEEDFD8),
      ),
      boxShadow: const [
        BoxShadow(
          color: Color(0x14111827),
          blurRadius: 14,
          offset: Offset(0, 7),
        ),
      ],
    );
  }
}
