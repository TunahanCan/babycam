import 'package:flutter/material.dart';

import '../../../app/app_role.dart';
import '../../../l10n/app_strings.dart';
import 'mimicam_design_tokens.dart';

class MimiCamRolePresentation {
  const MimiCamRolePresentation._({
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
      AppRole.client => MimiCamDesignTokens.mint,
      AppRole.server => dark
          ? MimiCamDesignTokens.serverCyan
          : MimiCamDesignTokens.serverCyanDeep,
    };
  }

  static MimiCamRolePresentation of(
    AppRole role,
    AppStrings strings,
  ) {
    return switch (role) {
      AppRole.client => MimiCamRolePresentation._(
          role: role,
          badgeTitle: strings.ui('clientRoleTitle'),
          badgeSubtitle: strings.ui('parentRoleSubtitle'),
          choiceTitle: strings.ui('parentDeviceTitle'),
          choiceDescription: strings.ui('parentDeviceDescription'),
          choiceIcon: Icons.monitor_heart,
          choiceBackgroundColor: MimiCamDesignTokens.mintSoft,
          choiceIconColor: const Color(0xFFB9F1E9),
        ),
      AppRole.server => MimiCamRolePresentation._(
          role: role,
          badgeTitle: strings.ui('serverRoleTitle'),
          badgeSubtitle: strings.ui('babyRoomRoleSubtitle'),
          choiceTitle: strings.ui('babyRoomDeviceTitle'),
          choiceDescription: strings.ui('babyRoomDeviceDescription'),
          choiceIcon: Icons.child_care,
          choiceBackgroundColor: MimiCamDesignTokens.serverIce,
          choiceIconColor: MimiCamDesignTokens.serverCyan,
        ),
    };
  }
}
