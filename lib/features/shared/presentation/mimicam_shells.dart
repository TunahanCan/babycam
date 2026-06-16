import 'package:flutter/material.dart';

import 'mimicam_design_tokens.dart';

class MimiCamCard extends StatelessWidget {
  const MimiCamCard({super.key, required this.child, this.dark = false});

  final Widget child;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: MimiCamDesignTokens.cardPadding,
      decoration: MimiCamDesignTokens.cardDecoration(dark: dark),
      child: child,
    );
  }
}

class MimiCamTopBar extends StatelessWidget {
  const MimiCamTopBar({
    super.key,
    required this.onResetRole,
    this.dark = false,
  });

  final VoidCallback onResetRole;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final color = dark ? Colors.white : MimiCamDesignTokens.navy;
    final chipColor = dark ? Colors.white.withValues(alpha: .12) : Colors.white;
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: ShapeDecoration(
            color: chipColor,
            shape: const StadiumBorder(),
          ),
          child: Row(
            children: [
              Icon(Icons.nightlight_round_rounded, color: color, size: 18),
              const SizedBox(width: 8),
              Text(
                'MimiCam',
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w900,
                  fontSize: 17,
                ),
              ),
            ],
          ),
        ),
        const Spacer(),
        TextButton.icon(
          onPressed: onResetRole,
          icon: Icon(Icons.swap_horiz_rounded, color: color),
          label: Text('Rol değiştir', style: TextStyle(color: color)),
        ),
      ],
    );
  }
}

class MimiCamGradientShell extends StatelessWidget {
  const MimiCamGradientShell({
    super.key,
    required this.child,
    required this.variant,
  });

  final Widget child;
  final MimiCamShellVariant variant;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(gradient: variant.gradient),
      child: child,
    );
  }
}

enum MimiCamShellVariant {
  client,
  server;

  Gradient get gradient {
    return switch (this) {
      MimiCamShellVariant.client => const RadialGradient(
          center: Alignment(.55, -.75),
          radius: .85,
          colors: [
            MimiCamDesignTokens.mintSoft,
            Color(0xFFFDF7F4),
            Color(0xFFF9F7FC),
          ],
        ),
      MimiCamShellVariant.server => const RadialGradient(
          center: Alignment(.7, -.85),
          radius: .9,
          colors: [
            Color(0xFF24465A),
            MimiCamDesignTokens.navy,
            Color(0xFF07111F),
          ],
        ),
    };
  }
}
