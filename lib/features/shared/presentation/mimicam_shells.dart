import 'package:flutter/material.dart';

import '../../../app/app_role.dart';
import '../../../l10n/app_strings.dart';
import 'mimicam_design_tokens.dart';

class MimiCamCard extends StatelessWidget {
  const MimiCamCard({super.key, required this.child, this.dark = false});

  final Widget child;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Container(
        width: double.infinity,
        padding: MimiCamDesignTokens.cardPadding,
        decoration: MimiCamDesignTokens.cardDecoration(dark: dark),
        child: child,
      ),
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
    final strings = AppStrings.of(context);
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
          label: Text(strings.ui('changeRole'), style: TextStyle(color: color)),
        ),
      ],
    );
  }
}

class MimiCamRoleSwitch extends StatelessWidget {
  const MimiCamRoleSwitch({
    super.key,
    required this.activeRole,
    required this.onRoleSelected,
    this.dark = false,
    this.enabled = true,
  });

  final AppRole activeRole;
  final ValueChanged<AppRole> onRoleSelected;
  final bool dark;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final borderColor =
        dark ? Colors.white.withValues(alpha: .24) : const Color(0xFFD7E1E8);
    final backgroundColor =
        dark ? Colors.white.withValues(alpha: .08) : Colors.white;
    return Container(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          Expanded(
            child: _RoleSwitchSide(
              role: AppRole.client,
              activeRole: activeRole,
              title: strings.ui('clientRoleTitle'),
              subtitle: strings.ui('parentRoleSubtitle'),
              dark: dark,
              enabled: enabled,
              onTap: onRoleSelected,
            ),
          ),
          Container(
            width: 2,
            height: 44,
            color: MimiCamDesignTokens.pink,
          ),
          Expanded(
            child: _RoleSwitchSide(
              role: AppRole.server,
              activeRole: activeRole,
              title: strings.ui('serverRoleTitle'),
              subtitle: strings.ui('babyRoomRoleSubtitle'),
              dark: dark,
              enabled: enabled,
              onTap: onRoleSelected,
            ),
          ),
        ],
      ),
    );
  }
}

class MimiCamRoleBadge extends StatelessWidget {
  const MimiCamRoleBadge({
    super.key,
    required this.activeRole,
    required this.onRoleSelected,
    this.dark = false,
    this.enabled = true,
  });

  final AppRole activeRole;
  final ValueChanged<AppRole> onRoleSelected;
  final bool dark;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final isClient = activeRole == AppRole.client;
    final nextRole = isClient ? AppRole.server : AppRole.client;
    final accent =
        isClient ? MimiCamDesignTokens.mint : MimiCamDesignTokens.pink;
    final title = isClient
        ? strings.ui('clientRoleTitle')
        : strings.ui('serverRoleTitle');
    final subtitle = isClient
        ? strings.ui('parentRoleSubtitle')
        : strings.ui('babyRoomRoleSubtitle');
    final textColor = dark ? Colors.white : MimiCamDesignTokens.navy;
    final mutedColor = dark ? Colors.white70 : MimiCamDesignTokens.slate;
    final backgroundColor = dark
        ? Colors.white.withValues(alpha: .08)
        : Colors.white.withValues(alpha: .92);
    final borderColor =
        dark ? Colors.white.withValues(alpha: .18) : const Color(0xFFDDE7EE);

    return RepaintBoundary(
      child: Tooltip(
        message: strings.uiFormat('roleBadgeTooltip', {'title': title}),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: enabled ? () => onRoleSelected(nextRole) : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: backgroundColor,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: borderColor),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x16111827),
                    blurRadius: 12,
                    offset: Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.lock_rounded, color: accent, size: 15),
                  const SizedBox(width: 8),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: textColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          letterSpacing: .7,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: mutedColor,
                          fontSize: 8,
                          fontWeight: FontWeight.w800,
                          letterSpacing: .4,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.more_horiz_rounded,
                    color: mutedColor,
                    size: 16,
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

class _RoleSwitchSide extends StatelessWidget {
  const _RoleSwitchSide({
    required this.role,
    required this.activeRole,
    required this.title,
    required this.subtitle,
    required this.dark,
    required this.enabled,
    required this.onTap,
  });

  final AppRole role;
  final AppRole activeRole;
  final String title;
  final String subtitle;
  final bool dark;
  final bool enabled;
  final ValueChanged<AppRole> onTap;

  @override
  Widget build(BuildContext context) {
    final active = role == activeRole;
    final activeColor = role == AppRole.client
        ? MimiCamDesignTokens.mint
        : MimiCamDesignTokens.pink;
    final textColor = dark ? Colors.white : MimiCamDesignTokens.navy;
    return InkWell(
      onTap: enabled && !active ? () => onTap(role) : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color:
              active ? activeColor.withValues(alpha: .18) : Colors.transparent,
          border: Border(
            bottom: BorderSide(
              width: 4,
              color: active ? activeColor : Colors.transparent,
            ),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: textColor,
                fontSize: 12,
                fontWeight: FontWeight.w900,
                letterSpacing: .8,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: dark ? Colors.white70 : MimiCamDesignTokens.slate,
                fontSize: 9,
                fontWeight: active ? FontWeight.w900 : FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MimiCamBottomNavItem {
  const MimiCamBottomNavItem({required this.icon, required this.label});

  final IconData icon;
  final String label;
}

class MimiCamBottomNav extends StatelessWidget {
  const MimiCamBottomNav({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onTap,
    required this.activeColor,
    this.dark = false,
  });

  final List<MimiCamBottomNavItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;
  final Color activeColor;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: dark
              ? const Color(0xFF101B2B).withValues(alpha: .94)
              : Colors.white.withValues(alpha: .96),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: dark ? Colors.white12 : const Color(0xFFE0E8EE),
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x26111827),
              blurRadius: 22,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          children: [
            for (var index = 0; index < items.length; index++)
              Expanded(
                child: _BottomNavButton(
                  item: items[index],
                  selected: index == currentIndex,
                  activeColor: activeColor,
                  dark: dark,
                  onTap: () => onTap(index),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _BottomNavButton extends StatelessWidget {
  const _BottomNavButton({
    required this.item,
    required this.selected,
    required this.activeColor,
    required this.dark,
    required this.onTap,
  });

  final MimiCamBottomNavItem item;
  final bool selected;
  final Color activeColor;
  final bool dark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final baseColor = dark ? Colors.white70 : MimiCamDesignTokens.slate;
    final selectedTextColor = dark ? Colors.white : MimiCamDesignTokens.navy;
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        height: 62,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color:
              selected ? activeColor.withValues(alpha: dark ? .22 : .25) : null,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(item.icon,
                color: selected ? activeColor : baseColor, size: 22),
            const SizedBox(height: 4),
            Text(
              item.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: selected ? selectedTextColor : baseColor,
                fontSize: 12,
                fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
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
            MimiCamDesignTokens.lightClientBg,
            Color(0xFFFFFFFF),
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
