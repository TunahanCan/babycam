import 'package:flutter/material.dart';

import '../../app/app_role.dart';
import '../../l10n/app_strings.dart';
import '../shared/presentation/miucam_design_tokens.dart';
import '../shared/presentation/miucam_role_presentation.dart';

class RoleSelectionScreen extends StatelessWidget {
  const RoleSelectionScreen({super.key, required this.onRoleSelected});

  final ValueChanged<AppRole> onRoleSelected;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final serverRole = MiuCamRolePresentation.of(AppRole.server, strings);
    final clientRole = MiuCamRolePresentation.of(AppRole.client, strings);
    return Scaffold(
      body: _WelcomeShell(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
                children: [
                  const _BrandHeader(),
                  const SizedBox(height: 14),
                  Text(
                    strings.ui('roleSelectionTitle'),
                    textAlign: TextAlign.center,
                    style: _titleStyle,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    strings.ui('roleSelectionSubtitle'),
                    textAlign: TextAlign.center,
                    style: _subtitleStyle,
                  ),
                  const SizedBox(height: 18),
                  _DeviceFlow(
                    roomRole: serverRole,
                    parentRole: clientRole,
                  ),
                  const SizedBox(height: 18),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final cards = [
                        _RoleChoiceCard(
                          role: serverRole,
                          onPressed: () => onRoleSelected(AppRole.server),
                        ),
                        _RoleChoiceCard(
                          role: clientRole,
                          onPressed: () => onRoleSelected(AppRole.client),
                        ),
                      ];
                      if (constraints.maxWidth >= 620) {
                        return IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(child: cards.first),
                              const SizedBox(width: 14),
                              Expanded(child: cards.last),
                            ],
                          ),
                        );
                      }
                      return Column(
                        children: [
                          cards.first,
                          const SizedBox(height: 12),
                          cards.last,
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 14),
                  _InfoStrip(
                    title: strings.ui('securityNoteTitle'),
                    text: strings.ui('securityNoteText'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BrandHeader extends StatelessWidget {
  const _BrandHeader();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Semantics(
        label: 'MiuCam',
        image: true,
        child: Image.asset(
          'assets/branding/miucam_wordmark_v2.png',
          key: const ValueKey('role-wordmark'),
          width: 210,
          height: 64,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
        ),
      ),
    );
  }
}

class _DeviceFlow extends StatelessWidget {
  const _DeviceFlow({required this.roomRole, required this.parentRole});

  final MiuCamRolePresentation roomRole;
  final MiuCamRolePresentation parentRole;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .66),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFD8D5F2)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x146257C8),
            blurRadius: 18,
            offset: Offset(0, 7),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: _DeviceFlowNode(
              icon: roomRole.choiceIcon,
              color: MiuCamDesignTokens.mint,
            ),
          ),
          Expanded(
            child: Row(
              children: [
                const Expanded(child: Divider(color: Color(0xFFC9C4E9))),
                Container(
                  width: 34,
                  height: 34,
                  decoration: const BoxDecoration(
                    color: Color(0xFFE4E0FF),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.wifi_rounded,
                    color: MiuCamDesignTokens.pink,
                    size: 19,
                  ),
                ),
                const Expanded(child: Divider(color: Color(0xFFC9C4E9))),
              ],
            ),
          ),
          Expanded(
            child: _DeviceFlowNode(
              icon: parentRole.choiceIcon,
              color: MiuCamDesignTokens.pink,
            ),
          ),
        ],
      ),
    );
  }
}

class _DeviceFlowNode extends StatelessWidget {
  const _DeviceFlowNode({
    required this.icon,
    required this.color,
  });

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: color.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(15),
        ),
        child: Icon(icon, color: color, size: 23),
      ),
    );
  }
}

class _RoleChoiceCard extends StatelessWidget {
  const _RoleChoiceCard({
    required this.role,
    required this.onPressed,
  });

  final MiuCamRolePresentation role;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final roomDevice = role.role == AppRole.server;
    final background =
        roomDevice ? const Color(0xFFECF7F4) : const Color(0xFFEDEAFF);
    final accent =
        roomDevice ? MiuCamDesignTokens.serverCyan : MiuCamDesignTokens.pink;
    return Semantics(
      button: true,
      label: '${role.choiceTitle}. ${role.choiceDescription}',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(26),
          child: Ink(
            padding: const EdgeInsets.fromLTRB(18, 16, 16, 17),
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: accent.withValues(alpha: .28)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x10162033),
                  blurRadius: 18,
                  offset: Offset(0, 7),
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .78),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Icon(role.choiceIcon, color: accent, size: 29),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: .74),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          role.badgeSubtitle,
                          style: TextStyle(
                            color: accent,
                            fontSize: 10.5,
                            letterSpacing: .35,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        role.choiceTitle,
                        style: const TextStyle(
                          color: MiuCamDesignTokens.nightPlum,
                          fontSize: 19,
                          height: 1.1,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        role.choiceDescription,
                        style: const TextStyle(
                          color: MiuCamDesignTokens.slate,
                          fontSize: 13.5,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 34,
                  height: 34,
                  decoration:
                      BoxDecoration(color: accent, shape: BoxShape.circle),
                  child: const Icon(
                    Icons.arrow_forward_rounded,
                    color: Colors.white,
                    size: 19,
                  ),
                ),
              ],
            ),
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
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF1EFFF).withValues(alpha: .9),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFD9D4F7)),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 21,
            backgroundColor: Color(0xFFE0DCFF),
            child: Icon(
              Icons.wifi_rounded,
              color: MiuCamDesignTokens.pink,
              size: 23,
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
                    color: MiuCamDesignTokens.nightPlum,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  text,
                  style: const TextStyle(
                    color: MiuCamDesignTokens.slate,
                    fontSize: 13,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WelcomeShell extends StatelessWidget {
  const _WelcomeShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF7F5FF), Color(0xFFEEF0FF), Color(0xFFF8F9FF)],
        ),
      ),
      child: Stack(
        children: [
          const Positioned(
            left: -90,
            top: -110,
            child: _BackgroundGlow(color: Color(0xFFBFB7FF), size: 250),
          ),
          const Positioned(
            right: -110,
            top: 110,
            child: _BackgroundGlow(color: Color(0xFFCDEEE6), size: 280),
          ),
          const Positioned(
            left: -120,
            bottom: -150,
            child: _BackgroundGlow(color: Color(0xFFDAD4FF), size: 300),
          ),
          Positioned.fill(child: child),
        ],
      ),
    );
  }
}

class _BackgroundGlow extends StatelessWidget {
  const _BackgroundGlow({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: .42),
        shape: BoxShape.circle,
      ),
    );
  }
}

const _titleStyle = TextStyle(
  color: MiuCamDesignTokens.nightPlum,
  fontSize: 29,
  height: 1.08,
  fontWeight: FontWeight.w900,
  letterSpacing: -.5,
);

const _subtitleStyle = TextStyle(
  color: MiuCamDesignTokens.slate,
  fontSize: 15,
  height: 1.3,
);
