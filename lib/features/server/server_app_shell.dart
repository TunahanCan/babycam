import 'package:flutter/material.dart';

import '../../app/app_role.dart';
import '../../core/theme/mimicam_theme.dart';
import '../../services/configuration_service.dart';
import 'server_home_screen.dart';
import 'server_runtime.dart';

class ServerAppShell extends StatelessWidget {
  const ServerAppShell({
    super.key,
    required this.runtime,
    required this.config,
    required this.activeRole,
    required this.onRoleSelected,
    this.switchingRole = false,
  });

  final ServerRuntime runtime;
  final ConfigurationService config;
  final AppRole activeRole;
  final ValueChanged<AppRole> onRoleSelected;
  final bool switchingRole;

  @override
  Widget build(BuildContext context) => Theme(
      data: MimiCamTheme.serverTheme(),
      child: ServerHomeScreen(
        runtime: runtime,
        config: config,
        activeRole: activeRole,
        onRoleSelected: onRoleSelected,
        switchingRole: switchingRole,
      ));
}
