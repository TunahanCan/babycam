import 'package:flutter/material.dart';

import 'babycam_design_tokens.dart';

class BabyCamCard extends StatelessWidget {
  const BabyCamCard({super.key, required this.child, this.dark = false});

  final Widget child;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: BabyCamDesignTokens.cardPadding,
      decoration: BabyCamDesignTokens.cardDecoration(dark: dark),
      child: child,
    );
  }
}

class BabyCamTopBar extends StatelessWidget {
  const BabyCamTopBar({
    super.key,
    required this.onResetRole,
    this.dark = false,
  });

  final VoidCallback onResetRole;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final color = dark ? Colors.white : BabyCamDesignTokens.navy;
    return Row(
      children: [
        Text(
          '09:41',
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w900,
            fontSize: 18,
          ),
        ),
        const Spacer(),
        TextButton(onPressed: onResetRole, child: const Text('Rol')),
        Icon(Icons.signal_cellular_alt_rounded, color: color),
        const SizedBox(width: 12),
        Icon(Icons.battery_5_bar_rounded, color: color),
      ],
    );
  }
}

class BabyCamGradientShell extends StatelessWidget {
  const BabyCamGradientShell({
    super.key,
    required this.child,
    required this.variant,
  });

  final Widget child;
  final BabyCamShellVariant variant;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(gradient: variant.gradient),
      child: child,
    );
  }
}

enum BabyCamShellVariant {
  client,
  server;

  Gradient get gradient {
    return switch (this) {
      BabyCamShellVariant.client => const RadialGradient(
          center: Alignment(.55, -.75),
          radius: .85,
          colors: [
            BabyCamDesignTokens.mintSoft,
            Color(0xFFFDF7F4),
            Color(0xFFF9F7FC),
          ],
        ),
      BabyCamShellVariant.server => const RadialGradient(
          center: Alignment(.7, -.85),
          radius: .9,
          colors: [
            Color(0xFF24465A),
            BabyCamDesignTokens.navy,
            Color(0xFF07111F),
          ],
        ),
    };
  }
}
