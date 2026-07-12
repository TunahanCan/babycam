import 'package:flutter/material.dart';

import '../../app/app_role.dart';
import '../../l10n/app_strings.dart';
import '../shared/presentation/mimicam_design_tokens.dart';
import '../shared/presentation/mimicam_role_presentation.dart';

class RoleSelectionScreen extends StatelessWidget {
  const RoleSelectionScreen({super.key, required this.onRoleSelected});

  final ValueChanged<AppRole> onRoleSelected;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final serverRole = MimiCamRolePresentation.of(AppRole.server, strings);
    final clientRole = MimiCamRolePresentation.of(AppRole.client, strings);
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
                  const SizedBox(height: 12),
                  const _MascotHero(),
                  const SizedBox(height: 18),
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
                  const SizedBox(height: 22),
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
        label: 'MimiCam',
        image: true,
        child: Image.asset(
          'assets/branding/mimicam_wordmark.png',
          width: 164,
          height: 44,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
        ),
      ),
    );
  }
}

class _MascotHero extends StatelessWidget {
  const _MascotHero();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 174,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFE3DF), Color(0xFFFFF4E9), Color(0xFFDDF8F0)],
        ),
        borderRadius: BorderRadius.circular(36),
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A8C6F68),
            blurRadius: 28,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          const Positioned(
            left: 28,
            top: 30,
            child: _SoftBubble(
              icon: Icons.favorite_rounded,
              color: Color(0xFFFF8D96),
              size: 42,
            ),
          ),
          const Positioned(
            right: 30,
            top: 24,
            child: _SoftBubble(
              icon: Icons.wifi_rounded,
              color: Color(0xFF45BFA6),
              size: 48,
            ),
          ),
          const Positioned(
            right: 76,
            bottom: 24,
            child: Icon(
              Icons.star_rounded,
              color: Color(0xFFFFBE68),
              size: 28,
            ),
          ),
          Positioned(
            bottom: -24,
            child: Semantics(
              label: 'MimiCam',
              image: true,
              child: Image.asset(
                'assets/branding/mimicam_bear_mascot.png',
                width: 192,
                height: 192,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SoftBubble extends StatelessWidget {
  const _SoftBubble({
    required this.icon,
    required this.color,
    required this.size,
  });

  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .72),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: color, size: size * .48),
    );
  }
}

class _RoleChoiceCard extends StatelessWidget {
  const _RoleChoiceCard({
    required this.role,
    required this.onPressed,
  });

  final MimiCamRolePresentation role;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final roomDevice = role.role == AppRole.server;
    final background =
        roomDevice ? const Color(0xFFFFEFEC) : const Color(0xFFE5F8F2);
    final accent =
        roomDevice ? const Color(0xFFFF7F88) : const Color(0xFF39B99E);
    return Semantics(
      button: true,
      label: role.choiceTitle,
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
                      Text(
                        role.choiceTitle,
                        style: const TextStyle(
                          color: MimiCamDesignTokens.nightPlum,
                          fontSize: 19,
                          height: 1.1,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        role.choiceDescription,
                        style: const TextStyle(
                          color: MimiCamDesignTokens.slate,
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
        color: Colors.white.withValues(alpha: .78),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE9DED6)),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 21,
            backgroundColor: Color(0xFFFFE9B9),
            child: Icon(
              Icons.wifi_rounded,
              color: Color(0xFF9A6921),
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
                    color: MimiCamDesignTokens.nightPlum,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  text,
                  style: const TextStyle(
                    color: MimiCamDesignTokens.slate,
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
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFFBF8), Color(0xFFF7FBFA), Color(0xFFFFF8F4)],
        ),
      ),
      child: Stack(
        children: [
          const Positioned(
            left: -90,
            top: -110,
            child: _BackgroundGlow(color: Color(0xFFFFD8D3), size: 250),
          ),
          const Positioned(
            right: -110,
            top: 110,
            child: _BackgroundGlow(color: Color(0xFFCFF4E9), size: 280),
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
  color: MimiCamDesignTokens.nightPlum,
  fontSize: 29,
  height: 1.08,
  fontWeight: FontWeight.w900,
  letterSpacing: -.5,
);

const _subtitleStyle = TextStyle(
  color: MimiCamDesignTokens.slate,
  fontSize: 15,
  height: 1.3,
);
