import 'package:flutter/material.dart';

import '../../../app/app_role.dart';
import '../../../l10n/app_strings.dart';
import '../../shared/presentation/miucam_design_tokens.dart';
import '../../shared/presentation/miucam_shells.dart';
import '../server_runtime.dart';

enum ServerHomeDestination {
  stream(Icons.videocam_rounded, 'navStream', 'server-stream'),
  pairing(Icons.qr_code_2_rounded, 'navQrIp', 'server-qr-ip'),
  services(
    Icons.settings_input_component_rounded,
    'navService',
    'server-services',
  ),
  settings(Icons.tune_rounded, 'navSettings', 'server-settings');

  const ServerHomeDestination(this.icon, this.labelKey, this.viewKey);

  final IconData icon;
  final String labelKey;
  final String viewKey;

  static ServerHomeDestination fromIndex(int index) {
    return values[index.clamp(0, values.length - 1).toInt()];
  }

  MiuCamBottomNavItem navigationItem(AppStrings strings) {
    return MiuCamBottomNavItem(icon: icon, label: strings.ui(labelKey));
  }
}

class ServerTabFrame extends StatelessWidget {
  const ServerTabFrame({
    super.key,
    required this.activeRole,
    required this.onRoleSelected,
    required this.switchingRole,
    required this.children,
  });

  final AppRole activeRole;
  final ValueChanged<AppRole> onRoleSelected;
  final bool switchingRole;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: MiuCamDesignTokens.screenPadding.copyWith(top: 6, bottom: 18),
      children: [
        Align(
          alignment: Alignment.topRight,
          child: MiuCamRoleBadge(
            activeRole: activeRole,
            onRoleSelected: onRoleSelected,
            enabled: !switchingRole,
            dark: true,
          ),
        ),
        const SizedBox(height: 12),
        ...children,
      ],
    );
  }
}

class ServerSectionHeader extends StatelessWidget {
  const ServerSectionHeader({
    super.key,
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: MiuCamDesignTokens.serverText,
            fontSize: 22,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: const TextStyle(
            color: MiuCamDesignTokens.serverTextMuted,
            fontSize: 14.5,
            height: 1.25,
          ),
        ),
      ],
    );
  }
}

class ServerKeyValue extends StatelessWidget {
  const ServerKeyValue(this.label, this.value, {super.key});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 15,
              color: MiuCamDesignTokens.serverTextMuted,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 15,
              color: MiuCamDesignTokens.serverText,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    );
  }
}

int connectedParentCount(ServerRuntimeState state) {
  final connectedCount = state.activeClients > state.activeEventClients
      ? state.activeClients
      : state.activeEventClients;
  if (connectedCount == 0 && state.phase == ServerRuntimePhase.clientPaired) {
    return 1;
  }
  return connectedCount;
}
