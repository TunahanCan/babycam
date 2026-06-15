import 'package:flutter/material.dart';

import '../../core/theme/babycam_theme.dart';
import 'server_home_screen.dart';
import 'server_runtime.dart';

class ServerAppShell extends StatelessWidget {
  const ServerAppShell({super.key, required this.runtime, required this.onResetRole});
  final ServerRuntime runtime;
  final VoidCallback onResetRole;
  @override Widget build(BuildContext context) => MaterialApp(theme: BabyCamTheme.serverTheme(), home: ServerHomeScreen(runtime: runtime, onResetRole: onResetRole));
}
