import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../app/app_role.dart';
import '../../l10n/app_strings.dart';
import '../../services/configuration_service.dart';
import '../shared/presentation/miucam_design_tokens.dart';
import '../shared/presentation/miucam_shells.dart';
import 'presentation/server_home_components.dart';
import 'presentation/server_pairing_section.dart';
import 'presentation/server_preview_section.dart';
import 'presentation/server_services_section.dart';
import 'presentation/server_settings_section.dart';
import 'presentation/server_status_section.dart';
import 'server_runtime.dart';

/// Coordinates server destinations and runtime side effects. Each destination
/// owns its local UI state so high-frequency updates stay below this boundary.
class ServerHomeScreen extends StatefulWidget {
  const ServerHomeScreen({
    super.key,
    required this.runtime,
    required this.config,
    required this.activeRole,
    required this.onRoleSelected,
    this.switchingRole = false,
    this.initialTab = 0,
    this.onRestartServer,
    this.openSettings,
  });

  final ServerRuntime runtime;
  final ConfigurationService config;
  final AppRole activeRole;
  final ValueChanged<AppRole> onRoleSelected;
  final bool switchingRole;
  final int initialTab;
  final VoidCallback? onRestartServer;
  final Future<bool> Function()? openSettings;

  @override
  State<ServerHomeScreen> createState() => _ServerHomeScreenState();
}

class _ServerHomeScreenState extends State<ServerHomeScreen> {
  bool _fullscreenPreview = false;
  bool _localPreviewWanted = false;
  bool _previewActionBusy = false;
  bool? _previewActionTargetEnabled;
  BoxFit _previewFit = BoxFit.cover;
  late ServerHomeDestination _destination;

  @override
  void initState() {
    super.initState();
    _destination = ServerHomeDestination.fromIndex(widget.initialTab);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_destination == ServerHomeDestination.stream ||
          _destination == ServerHomeDestination.pairing) {
        unawaited(widget.runtime.startPairingMode());
      }
    });
  }

  @override
  void dispose() {
    if (_fullscreenPreview) {
      unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    }
    unawaited(widget.runtime.stopLocalPreview().catchError((_) {}));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_fullscreenPreview) return _buildFullscreenPreview();

    final strings = AppStrings.of(context);
    return Scaffold(
      body: MiuCamGradientShell(
        variant: MiuCamShellVariant.server,
        child: SafeArea(
          child: StreamBuilder<ServerRuntimeState>(
            stream: widget.runtime.states,
            initialData: widget.runtime.currentState,
            builder: (context, snapshot) => AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              transitionBuilder: _hardWipe,
              child: _buildDestination(snapshot.data!),
            ),
          ),
        ),
      ),
      // Runtime emissions rebuild the destination body, but not navigation.
      bottomNavigationBar: MiuCamBottomNav(
        items: [
          for (final destination in ServerHomeDestination.values)
            destination.navigationItem(strings),
        ],
        currentIndex: _destination.index,
        activeColor: MiuCamDesignTokens.serverCyan,
        dark: true,
        onTap: (index) =>
            _selectDestination(ServerHomeDestination.fromIndex(index)),
      ),
    );
  }

  Widget _buildFullscreenPreview() {
    return StreamBuilder<ServerRuntimeState>(
      stream: widget.runtime.states,
      initialData: widget.runtime.currentState,
      builder: (context, snapshot) => PopScope<void>(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _exitFullscreenPreview();
        },
        child: Scaffold(
          backgroundColor: Colors.black,
          body: ServerFullscreenPreview(
            state: snapshot.data!,
            previewSource: widget.runtime.previewSource,
            fit: _previewFit,
            onExit: _exitFullscreenPreview,
            onToggleFit: _togglePreviewFit,
          ),
        ),
      ),
    );
  }

  Widget _buildDestination(ServerRuntimeState state) {
    return ServerTabFrame(
      key: ValueKey(_destination.viewKey),
      activeRole: widget.activeRole,
      onRoleSelected: widget.onRoleSelected,
      switchingRole: widget.switchingRole,
      children: switch (_destination) {
        ServerHomeDestination.stream => _streamChildren(state),
        ServerHomeDestination.pairing => [
            ServerPairingSection(runtime: widget.runtime, state: state),
          ],
        ServerHomeDestination.services => [
            ServerServicesSection(state: state),
          ],
        ServerHomeDestination.settings => [
            ServerSettingsSection(
              config: widget.config,
              runtime: widget.runtime,
            ),
          ],
      },
    );
  }

  List<Widget> _streamChildren(ServerRuntimeState state) {
    final strings = AppStrings.of(context);
    return [
      ServerLiveStatusCard(
        state: state,
        onConnectParent: () =>
            _selectDestination(ServerHomeDestination.pairing),
        onRetry: widget.onRestartServer ?? _retryLocalPreview,
        onRestart: widget.onRestartServer,
        onOpenAppSettings: _openSystemSettings,
      ),
      const SizedBox(height: 12),
      ServerLivePreviewCard(
        state: state,
        previewSource: widget.runtime.previewSource,
        fit: _previewFit,
        actionBusy: _previewActionBusy,
        actionTargetEnabled: _previewActionTargetEnabled,
        onEnterFullscreen: _enterFullscreenPreview,
        onToggleFit: _togglePreviewFit,
        onTogglePreview: () => _toggleLocalPreview(state.localPreviewActive),
      ),
      if (state.broadcastAccess case final broadcastAccess?) ...[
        const SizedBox(height: 16),
        ServerBroadcastAccessCard(
          snapshot: broadcastAccess,
          runtime: widget.runtime,
          onUnlocked: _retryLocalPreview,
        ),
      ],
      const SizedBox(height: 12),
      const ServerSafeRoomSetupCard(),
      const SizedBox(height: 12),
      ServerStreamDetailsCard(
        state: state,
        phaseLabel: _phaseLabel(strings, state.phase),
      ),
      if (state.phase != ServerRuntimePhase.stopped) ...[
        const SizedBox(height: 6),
        ServerStopRoomStreamButton(onPressed: _confirmStopStream),
      ],
    ];
  }

  void _selectDestination(ServerHomeDestination destination) {
    if (destination == _destination) return;
    final previous = _destination;
    setState(() => _destination = destination);

    if (previous == ServerHomeDestination.stream &&
        destination != ServerHomeDestination.stream) {
      unawaited(widget.runtime.stopLocalPreview().catchError((_) {}));
    }
    if (previous == ServerHomeDestination.pairing &&
        destination != ServerHomeDestination.pairing) {
      unawaited(widget.runtime.stopPairingMode());
    }
    if (destination == ServerHomeDestination.pairing) {
      unawaited(widget.runtime.startPairingMode());
    } else if (destination == ServerHomeDestination.stream) {
      _activatePreviewDestination();
    }
  }

  void _activatePreviewDestination() {
    unawaited(widget.runtime.startPairingMode());
    if (_localPreviewWanted) {
      unawaited(_changeLocalPreview(true, showFailureMessage: false));
    }
  }

  void _retryLocalPreview() {
    _localPreviewWanted = true;
    _activatePreviewDestination();
  }

  Future<void> _toggleLocalPreview(bool currentlyActive) =>
      _changeLocalPreview(!currentlyActive, showFailureMessage: true);

  Future<void> _changeLocalPreview(
    bool enabled, {
    required bool showFailureMessage,
  }) async {
    if (_previewActionBusy || !mounted) return;
    final strings = AppStrings.of(context);
    setState(() {
      _localPreviewWanted = enabled;
      _previewActionBusy = true;
      _previewActionTargetEnabled = enabled;
    });
    try {
      if (enabled) {
        await widget.runtime.startLocalPreview();
      } else {
        await widget.runtime.stopLocalPreview();
      }
    } catch (_) {
      if (enabled) _localPreviewWanted = false;
      if (mounted && showFailureMessage) {
        _showMessage(strings.ui('localPreviewChangeFailed'));
      }
    } finally {
      if (mounted) {
        setState(() {
          _previewActionBusy = false;
          _previewActionTargetEnabled = null;
        });
      }
    }
  }

  void _enterFullscreenPreview() {
    setState(() => _fullscreenPreview = true);
    unawaited(
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky),
    );
  }

  void _exitFullscreenPreview() {
    setState(() => _fullscreenPreview = false);
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
  }

  void _togglePreviewFit() {
    setState(() {
      _previewFit = _previewFit == BoxFit.cover ? BoxFit.contain : BoxFit.cover;
    });
  }

  Future<void> _confirmStopStream() async {
    final strings = AppStrings.of(context);
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => LayoutBuilder(
        builder: (context, constraints) {
          final stackActions = constraints.maxWidth < 420 ||
              MediaQuery.textScalerOf(context).scale(1) > 1.3;
          final cancelButton = OutlinedButton(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 48),
            ),
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(strings.ui('cancel')),
          );
          final stopButton = FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.stop_circle_rounded),
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 48),
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            label: Text(
              strings.ui('stopRoomStream'),
              textAlign: TextAlign.center,
            ),
          );

          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              24,
              4,
              24,
              18 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  strings.ui('stopRoomStreamConfirmTitle'),
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  strings.ui('stopRoomStreamConfirmBody'),
                  style: const TextStyle(fontSize: 15.5, height: 1.35),
                ),
                const SizedBox(height: 22),
                if (stackActions)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      cancelButton,
                      const SizedBox(height: 12),
                      stopButton,
                    ],
                  )
                else
                  Row(
                    children: [
                      Expanded(child: cancelButton),
                      const SizedBox(width: 12),
                      Expanded(child: stopButton),
                    ],
                  ),
              ],
            ),
          );
        },
      ),
    );
    if (confirmed == true) await widget.runtime.stop();
  }

  void _openSystemSettings() {
    unawaited(widget.openSettings?.call() ?? openAppSettings());
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _hardWipe(Widget child, Animation<double> animation) {
    final offset = Tween<Offset>(
      begin: const Offset(1, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic));
    return ClipRect(child: SlideTransition(position: offset, child: child));
  }

  static String _phaseLabel(AppStrings strings, ServerRuntimePhase phase) {
    return switch (phase) {
      ServerRuntimePhase.stopped => strings.ui('phaseStopped'),
      ServerRuntimePhase.pairingIdle => strings.ui('phasePairingIdle'),
      ServerRuntimePhase.pairingActive => strings.ui('phasePairingActive'),
      ServerRuntimePhase.clientPaired => strings.ui('phaseClientPaired'),
      ServerRuntimePhase.mediaIdle => strings.ui('phaseMediaIdle'),
      ServerRuntimePhase.mediaStarting => strings.ui('phaseMediaStarting'),
      ServerRuntimePhase.mediaActive => strings.ui('phaseMediaActive'),
      ServerRuntimePhase.error => strings.ui('phaseError'),
    };
  }
}
