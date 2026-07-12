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
import '../services/client_preferences_service.dart';
import 'app_role.dart';
import 'app_runtime.dart';
import 'install_integrity_guard.dart';
import 'role_permission_coordinator.dart';
import 'role_repository.dart';
import 'role_resolver.dart';
import 'role_switch_transaction.dart';

class AppBootstrap extends StatefulWidget {
  const AppBootstrap({
    super.key,
    this.onLocaleChanged,
    this.preferencesLoader,
  });

  final ValueChanged<Locale?>? onLocaleChanged;
  final Future<SharedPreferences> Function()? preferencesLoader;

  @override
  State<AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<AppBootstrap> {
  SharedPreferences? _prefs;
  RoleRepository? _roles;
  AppRole? _role;
  AppRuntime? _runtime;
  bool _loaded = false;
  bool _loading = true;
  Object? _loadError;
  bool _switchingRole = false;
  int _roleSwitchGeneration = 0;
  final _permissionCoordinator = const RolePermissionCoordinator();
  final _roleSwitchTransaction = const RoleSwitchTransaction();

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    if (!_loading && mounted) {
      setState(() {
        _loading = true;
        _loadError = null;
      });
    }
    try {
      final prefs = await (widget.preferencesLoader?.call() ??
          SharedPreferences.getInstance());
      await const InstallIntegrityGuard().prepare(prefs);
      final roles = SharedPreferencesRoleRepository(prefs);
      final role = await RoleResolver(roles).resolve();
      if (!mounted) return;
      widget.onLocaleChanged?.call(ClientPreferencesService(prefs).locale);
      setState(() {
        _prefs = prefs;
        _roles = roles;
        _role = role;
        _loaded = true;
        _loading = false;
        _loadError = null;
      });
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'MimiCam bootstrap',
          context: ErrorDescription('while loading application state'),
        ),
      );
      if (!mounted) return;
      setState(() {
        _loaded = false;
        _loading = false;
        _loadError = error;
      });
    }
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
    final previousRole = _role;
    setState(() {
      _switchingRole = true;
      _role = null;
      _runtime = null;
    });

    Object? switchError;
    StackTrace? switchStackTrace;
    try {
      await _roleSwitchTransaction.execute(
        runtime: runtime,
        previousRole: previousRole,
        nextRole: role,
        roles: _roles!,
        clearPairingSession: () async {
          final prefs = _prefs;
          if (prefs != null) await PairingSessionStore(prefs).clear();
        },
      );
    } catch (error, stackTrace) {
      switchError = error;
      switchStackTrace = stackTrace;
    }

    if (!mounted || generation != _roleSwitchGeneration) return;
    setState(() {
      _role = switchError == null ? role : previousRole;
      _switchingRole = false;
    });
    if (switchError != null) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: switchError,
          stack: switchStackTrace,
          library: 'MimiCam bootstrap',
          context: ErrorDescription('while switching application roles'),
        ),
      );
    }
  }

  @override
  void dispose() {
    _roleSwitchGeneration++;
    final runtime = _runtime;
    _runtime = null;
    unawaited(runtime?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    if (_loadError != null) {
      return _BootstrapError(onRetry: () => unawaited(_load()));
    }
    if (_loading || !_loaded) {
      return _BootstrapProgress(message: strings.ui('bootstrapPreparing'));
    }
    if (_switchingRole) {
      return _BootstrapProgress(message: strings.ui('roleSwitching'));
    }
    final prefs = _prefs!;
    final config = ConfigurationService(prefs);
    final clientPreferences = ClientPreferencesService(prefs);
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
          onRestartServer: () => unawaited(_switchRole(AppRole.server)),
        ),
      AppRole.client => ClientAppShell(
          runtime: (_runtime ??= ClientCompositionRoot.create(
            preferences: prefs,
            strings: AppStrings.of(context),
          )) as ClientRuntime,
          activeRole: AppRole.client,
          switchingRole: _switchingRole,
          preferences: clientPreferences,
          selectedLocale: clientPreferences.locale,
          onLocaleChanged: widget.onLocaleChanged,
          onRoleSelected: (role) => unawaited(_requestRoleChange(role)),
        ),
      null => Theme(
          data: MimiCamTheme.neutralTheme(),
          child: RoleSelectionScreen(onRoleSelected: _select),
        ),
    };
  }
}

class _BootstrapError extends StatelessWidget {
  const _BootstrapError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Theme(
      data: MimiCamTheme.neutralTheme(),
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.sync_problem_rounded, size: 54),
                  const SizedBox(height: 18),
                  Text(
                    strings.ui('bootstrapFailedTitle'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 23,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    strings.ui('bootstrapFailedText'),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 22),
                  FilledButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh_rounded),
                    label: Text(strings.ui('tryAgain')),
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
