import 'package:flutter/material.dart';

class BabyCamDesignTokens {
  const BabyCamDesignTokens._();

  static const navy = Color(0xFF101B31);
  static const slate = Color(0xFF6E7686);
  static const pink = Color(0xFFFF708B);
  static const mint = Color(0xFF87D8CC);
  static const mintSoft = Color(0xFFD9F7F1);
  static const amber = Color(0xFFFFD37B);

  static const screenPadding = EdgeInsets.fromLTRB(26, 18, 26, 28);
  static const cardPadding = EdgeInsets.all(28);

  static const title = TextStyle(
    color: navy,
    fontSize: 42,
    height: 1.05,
    fontWeight: FontWeight.w900,
  );

  static const darkTitle = TextStyle(
    color: Colors.white,
    fontSize: 44,
    height: 1.05,
    fontWeight: FontWeight.w900,
  );

  static const subtitle = TextStyle(
    color: slate,
    fontSize: 21,
    height: 1.18,
  );

  static const darkSubtitle = TextStyle(
    color: Colors.white70,
    fontSize: 21,
    height: 1.18,
  );

  static const cardTitle = TextStyle(
    color: navy,
    fontSize: 23,
    fontWeight: FontWeight.w900,
  );

  static BoxDecoration cardDecoration({bool dark = false}) {
    return BoxDecoration(
      color: dark ? navy : Colors.white,
      borderRadius: BorderRadius.circular(34),
      border: Border.all(color: const Color(0xFFE2E8F0)),
      boxShadow: const [
        BoxShadow(
          color: Color(0x24111827),
          blurRadius: 28,
          offset: Offset(0, 16),
        ),
      ],
    );
  }
}
