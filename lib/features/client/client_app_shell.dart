import 'package:flutter/material.dart';

import '../../core/theme/mimicam_theme.dart';
import 'client_home_screen.dart';
import 'client_runtime.dart';

class ClientAppShell extends StatelessWidget {
  const ClientAppShell(
      {super.key, required this.runtime, required this.onResetRole});
  final ClientRuntime runtime;
  final VoidCallback onResetRole;
  @override
  Widget build(BuildContext context) => Theme(
      data: MimiCamTheme.clientTheme(),
      child: ClientHomeScreen(runtime: runtime, onResetRole: onResetRole));
}
