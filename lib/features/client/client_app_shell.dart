import 'package:flutter/material.dart';

import '../../app/app_role.dart';
import '../../core/theme/mimicam_theme.dart';
import '../../services/client_preferences_service.dart';
import 'client_home_screen.dart';
import 'client_runtime.dart';

class ClientAppShell extends StatelessWidget {
  const ClientAppShell({
    super.key,
    required this.runtime,
    required this.activeRole,
    required this.onRoleSelected,
    this.preferences,
    this.selectedLocale,
    this.onLocaleChanged,
    this.switchingRole = false,
  });

  final ClientRuntime runtime;
  final AppRole activeRole;
  final ValueChanged<AppRole> onRoleSelected;
  final ClientPreferencesService? preferences;
  final Locale? selectedLocale;
  final ValueChanged<Locale?>? onLocaleChanged;
  final bool switchingRole;

  @override
  Widget build(BuildContext context) => Theme(
      data: MimiCamTheme.clientTheme(),
      child: ClientHomeScreen(
        runtime: runtime,
        activeRole: activeRole,
        onRoleSelected: onRoleSelected,
        switchingRole: switchingRole,
        preferences: preferences,
        selectedLocale: selectedLocale,
        onLocaleChanged: onLocaleChanged,
      ));
}
