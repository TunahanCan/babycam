import 'package:flutter/material.dart';

import '../../app/app_role.dart';
import '../../l10n/app_strings.dart';

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
                dark: true,
                icon: Icons.child_care,
                title: strings.ui('babyRoomDeviceTitle'),
                description: strings.ui('babyRoomDeviceDescription'),
                chip: strings.ui('recommended'),
                onPressed: () => onRoleSelected(AppRole.server),
              ),
              const SizedBox(height: 14),
              _RoleChoiceCard(
                icon: Icons.monitor_heart,
                title: strings.ui('parentDeviceTitle'),
                description: strings.ui('parentDeviceDescription'),
                chip: strings.ui('viewer'),
                onPressed: () => onRoleSelected(AppRole.client),
              ),
              const SizedBox(height: 18),
              _InfoStrip(
                title: strings.ui('setupPermissionsTitle'),
                text: strings.ui('setupPermissionsText'),
              ),
              const SizedBox(height: 10),
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
    this.dark = false,
    required this.icon,
    required this.title,
    required this.description,
    required this.chip,
    required this.onPressed,
  });

  final bool dark;
  final IconData icon;
  final String title;
  final String description;
  final String chip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final titleColor = dark ? Colors.white : _navy;
    final bodyColor = dark ? Colors.white70 : _slate;
    final iconColor = dark ? _pink : _mint;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: _cardDecoration(dark: dark),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: iconColor,
                    child: Icon(icon, color: _navy, size: 25),
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
                          style: TextStyle(
                            color: titleColor,
                            fontSize: 20,
                            height: 1.12,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 7),
                        Text(
                          description,
                          style: TextStyle(
                              color: bodyColor, fontSize: 14.5, height: 1.28),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  _Chip(text: chip, color: dark ? _pinkSoft : _mintSoft),
                ],
              ),
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerRight,
                child: Icon(
                  Icons.arrow_forward_rounded,
                  color: dark ? Colors.white : _navy,
                  size: 22,
                ),
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
      decoration: _cardDecoration(),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CircleAvatar(
            radius: 20,
            backgroundColor: _mintSoft,
            child: Icon(Icons.lock_outline_rounded, color: _navy),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: _navy,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(text,
                    style: const TextStyle(
                        color: _slate, fontSize: 14, height: 1.25)),
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
          colors: [_mintSoft, Color(0xFFFDF7F4), Color(0xFFF9F7FC)],
        ),
      ),
      child: child,
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: ShapeDecoration(color: color, shape: const StadiumBorder()),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
            color: _navy, fontWeight: FontWeight.w800, fontSize: 12),
      ),
    );
  }
}

BoxDecoration _cardDecoration({bool dark = false}) {
  return BoxDecoration(
    color: dark ? _navy : Colors.white,
    borderRadius: BorderRadius.circular(22),
    border: Border.all(color: const Color(0xFFE2E8F0)),
    boxShadow: const [
      BoxShadow(color: Color(0x18111827), blurRadius: 18, offset: Offset(0, 8)),
    ],
  );
}

const _navy = Color(0xFF101B31);
const _slate = Color(0xFF6E7686);
const _pink = Color(0xFFFF708B);
const _pinkSoft = Color(0xFFFFDCE6);
const _mint = Color(0xFF87D8CC);
const _mintSoft = Color(0xFFD9F7F1);

const _titleStyle = TextStyle(
  color: _navy,
  fontSize: 30,
  height: 1.08,
  fontWeight: FontWeight.w900,
);
const _subtitleStyle = TextStyle(color: _slate, fontSize: 15.5, height: 1.25);
