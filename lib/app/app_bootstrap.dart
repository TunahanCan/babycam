import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/theme/mimicam_theme.dart';
import '../features/client/client_app_shell.dart';
import '../features/client/client_composition_root.dart';
import '../features/client/client_runtime.dart';
import '../features/client/pairing/pairing_session_store.dart';
import '../features/role_selection/role_selection_screen.dart';
import '../features/server/server_app_shell.dart';
import '../features/server/server_composition_root.dart';
import '../features/server/server_runtime.dart';
import '../l10n/app_strings.dart';
import '../services/configuration_service.dart';
import 'app_role.dart';
import 'role_permission_coordinator.dart';
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
  bool _switchingRole = false;
  int _roleSwitchGeneration = 0;
  final _permissionCoordinator = const RolePermissionCoordinator();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final roles = SharedPreferencesRoleRepository(prefs);
    final role = await RoleResolver(roles).resolve();
    if (!mounted) return;
    setState(() {
      _prefs = prefs;
      _roles = roles;
      _role = role;
      _loaded = true;
    });
  }

  Future<void> _select(AppRole role) async {
    await _permissionCoordinator.requestFor(role);
    if (!mounted) return;
    await _switchRole(role);
  }

  Future<void> _requestRoleChange(AppRole role) async {
    if (_role == role || _switchingRole) return;
    if (_role == AppRole.server && role == AppRole.client) {
      final confirmed = await _confirmLeavingServer();
      if (confirmed != true) return;
    }
    await _permissionCoordinator.requestFor(role);
    if (!mounted) return;
    await _switchRole(role);
  }

  Future<bool?> _confirmLeavingServer() {
    final strings = AppStrings.of(context);
    return showModalBottomSheet<bool>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  strings.ui('confirmLeaveServerTitle'),
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 10),
                Text(
                  strings.ui('confirmLeaveServerBody'),
                  style: const TextStyle(fontSize: 16, height: 1.3),
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: Text(strings.ui('cancel')),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        child: Text(strings.ui('switchToClient')),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _switchRole(AppRole? role) async {
    if (_switchingRole) return;

    final generation = ++_roleSwitchGeneration;
    final runtime = _runtime;
    setState(() {
      _switchingRole = true;
      _role = null;
      _runtime = null;
    });

    await _disposeRuntime(runtime);
    if (_prefs != null) await PairingSessionStore(_prefs!).clear();
    if (role == null) {
      await _roles!.clearRole();
    } else {
      await _roles!.saveRole(role);
    }

    if (!mounted || generation != _roleSwitchGeneration) return;
    setState(() {
      _role = role;
      _switchingRole = false;
    });
  }

  Future<void> _disposeRuntime(Object? runtime) async {
    if (runtime is ServerRuntime) await runtime.dispose();
    if (runtime is ClientRuntime) await runtime.dispose();
  }

  @override
  void dispose() {
    _roleSwitchGeneration++;
    final runtime = _runtime;
    _runtime = null;
    unawaited(_disposeRuntime(runtime));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    if (!_loaded) {
      return _BootstrapProgress(message: strings.ui('bootstrapPreparing'));
    }
    if (_switchingRole) {
      return _BootstrapProgress(message: strings.ui('roleSwitching'));
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
          activeRole: AppRole.server,
          switchingRole: _switchingRole,
          onRoleSelected: (role) => unawaited(_requestRoleChange(role)),
        ),
      AppRole.client => ClientAppShell(
          runtime: (_runtime ??= ClientCompositionRoot.create(
            preferences: prefs,
            strings: AppStrings.of(context),
          )) as ClientRuntime,
          activeRole: AppRole.client,
          switchingRole: _switchingRole,
          onRoleSelected: (role) => unawaited(_requestRoleChange(role)),
        ),
      null => Theme(
          data: MimiCamTheme.neutralTheme(),
          child: RoleSelectionScreen(onRoleSelected: _select),
        ),
    };
  }
}

class _BootstrapProgress extends StatelessWidget {
  const _BootstrapProgress({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: MimiCamTheme.neutralTheme(),
      child: Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(message),
            ],
          ),
        ),
      ),
    );
  }
}
