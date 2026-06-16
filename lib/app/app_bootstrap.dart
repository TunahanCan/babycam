import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/theme/mimicam_theme.dart';
import '../features/client/client_app_shell.dart';
import '../features/client/client_composition_root.dart';
import '../features/client/client_runtime.dart';
import '../features/role_selection/role_selection_screen.dart';
import '../features/server/server_app_shell.dart';
import '../features/server/server_composition_root.dart';
import '../features/server/server_runtime.dart';
import '../l10n/app_strings.dart';
import '../services/configuration_service.dart';
import 'app_role.dart';
import 'role_repository.dart';
import 'role_resolver.dart';

class AppBootstrap extends StatefulWidget {
  const AppBootstrap({super.key});

  @override
  State<AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<AppBootstrap> {
  SharedPreferences? _prefs;
  RoleRepository? _roles;
  AppRole? _role;
  Object? _runtime;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final roles = SharedPreferencesRoleRepository(prefs);
    final role = await RoleResolver(roles).resolve();
    setState(() {
      _prefs = prefs;
      _roles = roles;
      _role = role;
      _loaded = true;
    });
  }

  Future<void> _select(AppRole role) async {
    await _roles!.saveRole(role);
    await _disposeRuntime();
    setState(() {
      _role = role;
      _runtime = null;
    });
  }

  Future<void> _reset() async {
    await _roles!.clearRole();
    await _disposeRuntime();
    setState(() {
      _role = null;
      _runtime = null;
    });
  }

  Future<void> _disposeRuntime() async {
    final runtime = _runtime;
    if (runtime is ServerRuntime) await runtime.dispose();
    if (runtime is ClientRuntime) await runtime.dispose();
  }

  @override
  void dispose() {
    _disposeRuntime();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return Theme(
        data: MimiCamTheme.neutralTheme(),
        child: const Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }
    final prefs = _prefs!;
    final config = ConfigurationService(prefs);
    return switch (_role) {
      AppRole.server => ServerAppShell(
          runtime: (_runtime ??= ServerCompositionRoot.create(
            config: config,
            strings: AppStrings.of(context),
          )) as ServerRuntime,
          config: config,
          onResetRole: _reset,
        ),
      AppRole.client => ClientAppShell(
          runtime: (_runtime ??=
                  ClientCompositionRoot.create(preferences: prefs))
              as ClientRuntime,
          onResetRole: _reset,
        ),
      null => Theme(
          data: MimiCamTheme.neutralTheme(),
          child: RoleSelectionScreen(onRoleSelected: _select),
        ),
    };
  }
}
