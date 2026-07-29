import 'package:flutter/material.dart';

import '../../../app/app_role.dart';
import '../../../l10n/app_strings.dart';
import 'miucam_design_tokens.dart';

class MiuCamRolePresentation {
  const MiuCamRolePresentation._({
    required this.role,
    required this.badgeTitle,
    required this.badgeSubtitle,
    required this.choiceTitle,
    required this.choiceDescription,
    required this.choiceIcon,
    required this.choiceBackgroundColor,
    required this.choiceIconColor,
  });

  final AppRole role;
  final String badgeTitle;
  final String badgeSubtitle;
  final String choiceTitle;
  final String choiceDescription;
  final IconData choiceIcon;
  final Color choiceBackgroundColor;
  final Color choiceIconColor;

  Color accentColor({required bool dark}) {
    return switch (role) {
      AppRole.client => MiuCamDesignTokens.mint,
      AppRole.server => dark
          ? MiuCamDesignTokens.serverCyan
          : MiuCamDesignTokens.serverCyanDeep,
    };
  }

  static MiuCamRolePresentation of(
    AppRole role,
    AppStrings strings,
  ) {
    return switch (role) {
      AppRole.client => MiuCamRolePresentation._(
          role: role,
          badgeTitle: strings.ui('clientRoleTitle'),
          badgeSubtitle: strings.ui('parentRoleSubtitle'),
          choiceTitle: strings.ui('parentDeviceTitle'),
          choiceDescription: strings.ui('parentDeviceDescription'),
          choiceIcon: Icons.monitor_heart,
          choiceBackgroundColor: MiuCamDesignTokens.mintSoft,
          choiceIconColor: const Color(0xFFB9F1E9),
        ),
      AppRole.server => MiuCamRolePresentation._(
          role: role,
          badgeTitle: strings.ui('serverRoleTitle'),
          badgeSubtitle: strings.ui('babyRoomRoleSubtitle'),
          choiceTitle: strings.ui('babyRoomDeviceTitle'),
          choiceDescription: strings.ui('babyRoomDeviceDescription'),
          choiceIcon: Icons.child_care,
          choiceBackgroundColor: MiuCamDesignTokens.serverIce,
          choiceIconColor: MiuCamDesignTokens.serverCyanOnLight,
        ),
    };
  }
}
