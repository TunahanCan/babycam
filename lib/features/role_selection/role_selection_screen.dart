import 'package:flutter/material.dart';

import '../../app/app_role.dart';
import '../../l10n/app_strings.dart';
import '../shared/presentation/mimicam_design_tokens.dart';

class RoleSelectionScreen extends StatelessWidget {
  const RoleSelectionScreen({super.key, required this.onRoleSelected});

  final ValueChanged<AppRole> onRoleSelected;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Scaffold(
      body: _LightShell(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 22),
            children: [
              Text(strings.ui('roleSelectionTitle'), style: _titleStyle),
              const SizedBox(height: 8),
              Text(
                strings.ui('roleSelectionSubtitle'),
                style: _subtitleStyle,
              ),
              const SizedBox(height: 20),
              _RoleChoiceCard(
                icon: Icons.child_care,
                title: strings.ui('babyRoomDeviceTitle'),
                description: strings.ui('babyRoomDeviceDescription'),
                backgroundColor: MimiCamDesignTokens.blushSoft,
                iconColor: const Color(0xFFFFC6D4),
                onPressed: () => onRoleSelected(AppRole.server),
              ),
              const SizedBox(height: 14),
              _RoleChoiceCard(
                icon: Icons.monitor_heart,
                title: strings.ui('parentDeviceTitle'),
                description: strings.ui('parentDeviceDescription'),
                backgroundColor: MimiCamDesignTokens.mintSoft,
                iconColor: const Color(0xFFB9F1E9),
                onPressed: () => onRoleSelected(AppRole.client),
              ),
              const SizedBox(height: 132),
              _InfoStrip(
                title: strings.ui('securityNoteTitle'),
                text: strings.ui('securityNoteText'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoleChoiceCard extends StatelessWidget {
  const _RoleChoiceCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.backgroundColor,
    required this.iconColor,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final String description;
  final Color backgroundColor;
  final Color iconColor;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: _cardDecoration(color: backgroundColor),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 34,
                    backgroundColor: iconColor,
                    child: Icon(
                      icon,
                      color: MimiCamDesignTokens.nightPlum,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: MimiCamDesignTokens.nightPlum,
                            fontSize: 20,
                            height: 1.12,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 7),
                        Text(
                          description,
                          style: const TextStyle(
                            color: MimiCamDesignTokens.slate,
                            fontSize: 14.5,
                            height: 1.28,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: MimiCamDesignTokens.nightPlum,
                    size: 28,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoStrip extends StatelessWidget {
  const _InfoStrip({required this.title, required this.text});

  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(color: MimiCamDesignTokens.amberSoft),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CircleAvatar(
            radius: 20,
            backgroundColor: Colors.white,
            child: Icon(
              Icons.shield_outlined,
              color: MimiCamDesignTokens.nightPlum,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: MimiCamDesignTokens.nightPlum,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(text,
                    style: const TextStyle(
                        color: MimiCamDesignTokens.slate,
                        fontSize: 14,
                        height: 1.25)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LightShell extends StatelessWidget {
  const _LightShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(.55, -.78),
          radius: .8,
          colors: [
            MimiCamDesignTokens.mintSoft,
            MimiCamDesignTokens.cream,
            Color(0xFFFFFBF8),
          ],
        ),
      ),
      child: child,
    );
  }
}

BoxDecoration _cardDecoration({Color? color}) {
  return BoxDecoration(
    color: color ?? Colors.white,
    borderRadius: BorderRadius.circular(22),
    border: Border.all(color: const Color(0xFFEEDFD8)),
    boxShadow: const [
      BoxShadow(color: Color(0x14111827), blurRadius: 12, offset: Offset(0, 6)),
    ],
  );
}

const _titleStyle = TextStyle(
  color: MimiCamDesignTokens.nightPlum,
  fontSize: 30,
  height: 1.08,
  fontWeight: FontWeight.w900,
);
const _subtitleStyle = TextStyle(
  color: MimiCamDesignTokens.slate,
  fontSize: 15.5,
  height: 1.25,
);
