import 'package:flutter/material.dart';

class MimiCamDesignTokens {
  const MimiCamDesignTokens._();

  static const navy = Color(0xFF071120);
  static const slate = Color(0xFF657083);
  static const pink = Color(0xFFFF315A);
  static const mint = Color(0xFF6EDCCE);
  static const mintSoft = Color(0xFFDDF8F4);
  static const amber = Color(0xFFF5C451);
  static const lightClientBg = Color(0xFFF6FBFA);
  static const softRed = Color(0xFFFF5D6C);

  static const screenPadding = EdgeInsets.fromLTRB(20, 12, 20, 22);
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
      color: dark ? navy : Colors.white,
      borderRadius: BorderRadius.circular(dark ? 22 : 18),
      border: Border.all(color: const Color(0xFFE2E8F0)),
      boxShadow: const [
        BoxShadow(
          color: Color(0x18111827),
          blurRadius: 18,
          offset: Offset(0, 8),
        ),
      ],
    );
  }
}
