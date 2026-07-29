import 'package:flutter/material.dart';

import '../../../app/app_role.dart';
import '../../../core/theme/miucam_colors.dart';
import '../../../l10n/app_strings.dart';
import 'miucam_design_tokens.dart';
import 'miucam_role_presentation.dart';

class MiuCamCard extends StatelessWidget {
  const MiuCamCard({super.key, required this.child, this.dark = false});

  final Widget child;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Container(
        width: double.infinity,
        padding: MiuCamDesignTokens.cardPadding,
        decoration: MiuCamDesignTokens.cardDecoration(dark: dark),
        child: child,
      ),
    );
  }
}

class MiuCamTopBar extends StatelessWidget {
  const MiuCamTopBar({
    super.key,
    required this.onResetRole,
    this.dark = false,
  });

  final VoidCallback onResetRole;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final color =
        dark ? MiuCamDesignTokens.serverText : MiuCamDesignTokens.navy;
    final chipColor = dark
        ? MiuCamDesignTokens.serverSurfaceRaised.withValues(alpha: .88)
        : Colors.white;
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
                'MiuCam',
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

class MiuCamRoleSwitch extends StatelessWidget {
  const MiuCamRoleSwitch({
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
    final clientRole = MiuCamRolePresentation.of(AppRole.client, strings);
    final serverRole = MiuCamRolePresentation.of(AppRole.server, strings);
    final borderColor = dark
        ? MiuCamDesignTokens.serverOutline.withValues(alpha: .72)
        : const Color(0xFFD7E1E8);
    final backgroundColor =
        dark ? MiuCamDesignTokens.serverPanel : Colors.white;
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
              title: clientRole.badgeTitle,
              subtitle: clientRole.badgeSubtitle,
              activeColor: clientRole.accentColor(dark: dark),
              dark: dark,
              enabled: enabled,
              onTap: onRoleSelected,
            ),
          ),
          Container(
            width: 2,
            height: 44,
            color: MiuCamDesignTokens.pink,
          ),
          Expanded(
            child: _RoleSwitchSide(
              role: AppRole.server,
              activeRole: activeRole,
              title: serverRole.badgeTitle,
              subtitle: serverRole.badgeSubtitle,
              activeColor: serverRole.accentColor(dark: dark),
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

class MiuCamRoleBadge extends StatelessWidget {
  const MiuCamRoleBadge({
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
    final role = MiuCamRolePresentation.of(activeRole, strings);
    final accent = role.accentColor(dark: dark);
    final textColor =
        dark ? MiuCamDesignTokens.serverText : MiuCamDesignTokens.navy;
    final mutedColor =
        dark ? MiuCamDesignTokens.serverTextMuted : MiuCamDesignTokens.slate;
    final backgroundColor = dark
        ? MiuCamDesignTokens.serverPanel.withValues(alpha: .94)
        : Colors.white.withValues(alpha: .92);
    final borderColor = dark
        ? MiuCamDesignTokens.serverOutline.withValues(alpha: .72)
        : const Color(0xFFDDE7EE);

    return RepaintBoundary(
      child: Tooltip(
        message:
            strings.uiFormat('roleBadgeTooltip', {'title': role.badgeTitle}),
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
                boxShadow: [
                  BoxShadow(
                    color: dark
                        ? const Color(0x1424493D)
                        : const Color(0x16111827),
                    blurRadius: dark ? 14 : 12,
                    offset: const Offset(0, 5),
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
                        role.badgeTitle,
                        style: TextStyle(
                          color: textColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          letterSpacing: .7,
                        ),
                      ),
                      Text(
                        role.badgeSubtitle,
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
                    Icons.swap_horiz_rounded,
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
    required this.activeColor,
    required this.dark,
    required this.enabled,
    required this.onTap,
  });

  final AppRole role;
  final AppRole activeRole;
  final String title;
  final String subtitle;
  final Color activeColor;
  final bool dark;
  final bool enabled;
  final ValueChanged<AppRole> onTap;

  @override
  Widget build(BuildContext context) {
    final active = role == activeRole;
    final textColor =
        dark ? MiuCamDesignTokens.serverText : MiuCamDesignTokens.navy;
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
                color: dark
                    ? MiuCamDesignTokens.serverTextMuted
                    : MiuCamDesignTokens.slate,
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

class MiuCamBottomNavItem {
  const MiuCamBottomNavItem({required this.icon, required this.label});

  final IconData icon;
  final String label;
}

class MiuCamBottomNav extends StatelessWidget {
  const MiuCamBottomNav({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onTap,
    required this.activeColor,
    this.dark = false,
  });

  final List<MiuCamBottomNavItem> items;
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
              ? MiuCamDesignTokens.serverPanel.withValues(alpha: .98)
              : Colors.white.withValues(alpha: .96),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(
            color: dark
                ? MiuCamDesignTokens.serverOutline.withValues(alpha: .78)
                : const Color(0xFFEEDFD8),
          ),
          boxShadow: [
            BoxShadow(
              color: dark ? const Color(0x1824493D) : const Color(0x1F111827),
              blurRadius: dark ? 16 : 16,
              offset: const Offset(0, 6),
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

  final MiuCamBottomNavItem item;
  final bool selected;
  final Color activeColor;
  final bool dark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final baseColor =
        dark ? MiuCamDesignTokens.serverTextMuted : MiuCamDesignTokens.slate;
    final selectedTextColor =
        dark ? MiuCamDesignTokens.serverText : MiuCamDesignTokens.navy;
    final scaledLabelSize = MediaQuery.textScalerOf(context).scale(12);
    final buttonHeight =
        58.0 + (scaledLabelSize - 12).clamp(0.0, 8.0).toDouble();
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        height: buttonHeight,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color:
              selected ? activeColor.withValues(alpha: dark ? .22 : .25) : null,
          borderRadius: BorderRadius.circular(24),
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

class MiuCamGradientShell extends StatelessWidget {
  const MiuCamGradientShell({
    super.key,
    required this.child,
    required this.variant,
  });

  final Widget child;
  final MiuCamShellVariant variant;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(gradient: variant.gradient),
      child: child,
    );
  }
}

enum MiuCamShellVariant {
  client,
  server;

  Gradient get gradient {
    return switch (this) {
      MiuCamShellVariant.client => const RadialGradient(
          center: Alignment(.55, -.75),
          radius: .85,
          colors: [
            MiuCamDesignTokens.mintSoft,
            MiuCamDesignTokens.lightClientBg,
            Color(0xFFFFFBF8),
          ],
        ),
      MiuCamShellVariant.server => const RadialGradient(
          center: Alignment(.62, -.9),
          radius: 1.22,
          colors: [
            Color(0xFFD9F1E8),
            MiuCamDesignTokens.serverNavy,
            MiuCamColors.serverBackground,
          ],
          stops: [0, .42, 1],
        ),
    };
  }
}
