import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../app/app_role.dart';
import '../../l10n/app_strings.dart';
import '../../services/configuration_service.dart';
import '../../services/monetization/broadcast_access_service.dart';
import '../../services/platform/platform_runtime_contract.dart';
import '../shared/presentation/localized_measurement_text.dart';
import '../shared/presentation/media_profile_text.dart';
import '../shared/presentation/mimicam_design_tokens.dart';
import '../shared/presentation/mimicam_shells.dart';
import 'server_runtime.dart';
import 'media/server_media_source.dart';

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
  });

  final ServerRuntime runtime;
  final ConfigurationService config;
  final AppRole activeRole;
  final ValueChanged<AppRole> onRoleSelected;
  final bool switchingRole;
  final int initialTab;
  final VoidCallback? onRestartServer;

  @override
  State<ServerHomeScreen> createState() => _ServerHomeScreenState();
}

class _ServerHomeScreenState extends State<ServerHomeScreen> {
  late double _motionThreshold;
  late double _cryScoreThreshold;
  late double _notifyCooldownSeconds;
  late double _motionDurationSeconds;
  late double _cryDurationSeconds;
  bool _savingSettings = false;
  bool _fullscreenPreview = false;
  // Camera preview is intentionally opt-in. Opening the room device should be
  // fast and low-power; the parent can be paired before the local camera view
  // is needed for framing.
  bool _localPreviewWanted = false;
  bool _previewActionBusy = false;
  bool? _previewActionTargetEnabled;
  bool _purchaseBusy = false;
  BoxFit _previewFit = BoxFit.cover;
  late int _tab;

  @override
  void initState() {
    super.initState();
    _tab = widget.initialTab.clamp(0, 3);
    _loadSettings();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_tab == 1) {
        unawaited(widget.runtime.startPairingMode());
      } else if (_tab == 0) {
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

  void _loadSettings() {
    _motionThreshold = widget.config.motionThreshold.clamp(.05, .60).toDouble();
    _cryScoreThreshold =
        widget.config.cryScoreThreshold.clamp(.20, .95).toDouble();
    _notifyCooldownSeconds =
        (widget.config.notifyCooldownMs / 1000).clamp(10, 180).toDouble();
    _motionDurationSeconds =
        (widget.config.motionMinDurationMs / 1000).clamp(.5, 6).toDouble();
    _cryDurationSeconds =
        (widget.config.cryMinDurationMs / 1000).clamp(.5, 6).toDouble();
  }

  Future<void> _persistSettings(Future<void> Function() save) async {
    setState(() => _savingSettings = true);
    try {
      await save();
      await widget.runtime.reloadAnalysisSettings();
    } finally {
      if (mounted) setState(() => _savingSettings = false);
    }
  }

  Future<void> _resetSettings() async {
    setState(() => _savingSettings = true);
    try {
      await widget.config.resetToDefaults();
      _loadSettings();
      await widget.runtime.reloadAnalysisSettings();
    } finally {
      if (mounted) setState(() => _savingSettings = false);
    }
  }

  Future<void> _confirmResetSettings() async {
    final strings = AppStrings.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(strings.ui('resetSettingsTitle')),
        content: Text(strings.ui('resetSettingsDescription')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(strings.ui('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(strings.ui('resetDefaults')),
          ),
        ],
      ),
    );
    if (confirmed == true) await _resetSettings();
  }

  Future<void> _confirmStopStream() async {
    final strings = AppStrings.of(context);
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              strings.ui('stopRoomStreamConfirmTitle'),
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 10),
            Text(
              strings.ui('stopRoomStreamConfirmBody'),
              style: const TextStyle(fontSize: 15.5, height: 1.35),
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
                  child: FilledButton.icon(
                    onPressed: () => Navigator.of(context).pop(true),
                    icon: const Icon(Icons.stop_circle_rounded),
                    style: FilledButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.error,
                      foregroundColor: Theme.of(context).colorScheme.onError,
                    ),
                    label: Text(strings.ui('stopRoomStream')),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    await widget.runtime.stop();
  }

  Future<void> _applyDetectionPreset(_DetectionPreset preset) async {
    final values = preset.settings;
    setState(() {
      _savingSettings = true;
      _motionThreshold = values.motionThreshold;
      _cryScoreThreshold = values.cryScoreThreshold;
      _notifyCooldownSeconds = values.notifyCooldownSeconds;
      _motionDurationSeconds = values.motionDurationSeconds;
      _cryDurationSeconds = values.cryDurationSeconds;
    });
    try {
      await Future.wait<void>([
        widget.config.setMotionThreshold(values.motionThreshold),
        widget.config.setCryScoreThreshold(values.cryScoreThreshold),
        widget.config
            .setNotifyCooldownMs((values.notifyCooldownSeconds * 1000).round()),
        widget.config.setMotionMinDurationMs(
            (values.motionDurationSeconds * 1000).round()),
        widget.config
            .setCryMinDurationMs((values.cryDurationSeconds * 1000).round()),
      ]);
      await widget.runtime.reloadAnalysisSettings();
    } finally {
      if (mounted) setState(() => _savingSettings = false);
    }
  }

  _DetectionPreset? get _activeDetectionPreset {
    for (final preset in _DetectionPreset.values) {
      final values = preset.settings;
      if ((_motionThreshold - values.motionThreshold).abs() < .001 &&
          (_cryScoreThreshold - values.cryScoreThreshold).abs() < .001 &&
          (_notifyCooldownSeconds - values.notifyCooldownSeconds).abs() < .01 &&
          (_motionDurationSeconds - values.motionDurationSeconds).abs() < .01 &&
          (_cryDurationSeconds - values.cryDurationSeconds).abs() < .01) {
        return preset;
      }
    }
    return null;
  }

  void _enterFullscreenPreview() {
    setState(() => _fullscreenPreview = true);
    unawaited(
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky));
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

  Future<void> _unlockBroadcastAccess() async {
    if (_purchaseBusy) return;
    final strings = AppStrings.of(context);
    setState(() => _purchaseBusy = true);
    try {
      await widget.runtime.unlockBroadcastAccess();
      if (!mounted) return;
      _showMessage(strings.ui('broadcastAccessUnlocked'));
      _retryLocalPreview();
    } catch (error) {
      if (!mounted) return;
      _showMessage(_purchaseMessage(strings, error));
    } finally {
      if (mounted) setState(() => _purchaseBusy = false);
    }
  }

  Future<void> _restoreBroadcastAccess() async {
    if (_purchaseBusy) return;
    final strings = AppStrings.of(context);
    setState(() => _purchaseBusy = true);
    try {
      await widget.runtime.restoreBroadcastAccessPurchase();
      if (!mounted) return;
      _showMessage(strings.ui('broadcastAccessUnlocked'));
      _retryLocalPreview();
    } catch (error) {
      if (!mounted) return;
      _showMessage(_purchaseMessage(strings, error));
    } finally {
      if (mounted) setState(() => _purchaseBusy = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String _purchaseMessage(AppStrings strings, Object error) {
    if (error is BroadcastPurchaseException) {
      return switch (error.result.status) {
        BroadcastPurchaseStatus.pending => strings.ui('purchasePending'),
        BroadcastPurchaseStatus.canceled => strings.ui('purchaseCanceled'),
        BroadcastPurchaseStatus.unavailable =>
          strings.ui('purchaseUnavailable'),
        _ => error.result.message ?? strings.ui('purchaseFailed'),
      };
    }
    if (error is BroadcastAccessLockedException) {
      return strings.ui('broadcastAccessLockedBody');
    }
    return strings.ui('purchaseFailed');
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<ServerRuntimeState>(
      stream: widget.runtime.states,
      initialData: widget.runtime.currentState,
      builder: (context, snapshot) {
        final state = snapshot.data!;
        if (_fullscreenPreview) {
          return PopScope<void>(
            canPop: false,
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop) _exitFullscreenPreview();
            },
            child: Scaffold(
              backgroundColor: Colors.black,
              body: _FullscreenPreview(
                state: state,
                previewSource: widget.runtime.previewSource,
                fit: _previewFit,
                onExit: _exitFullscreenPreview,
                onToggleFit: _togglePreviewFit,
              ),
            ),
          );
        }
        return Scaffold(
          body: MimiCamGradientShell(
            variant: MimiCamShellVariant.server,
            child: SafeArea(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                transitionBuilder: _hardWipe,
                child: _buildTab(context, state),
              ),
            ),
          ),
          bottomNavigationBar: MimiCamBottomNav(
            items: _serverNavItems(context),
            currentIndex: _tab,
            activeColor: MimiCamDesignTokens.serverCyan,
            dark: true,
            onTap: _selectTab,
          ),
        );
      },
    );
  }

  void _selectTab(int index) {
    final leavingPairingTab = _tab == 1 && index != 1;
    final leavingPreviewTab = _tab == 0 && index != 0;
    setState(() => _tab = index);
    if (leavingPairingTab) {
      unawaited(widget.runtime.stopPairingMode());
    }
    if (leavingPreviewTab) {
      unawaited(widget.runtime.stopLocalPreview().catchError((_) {}));
    }
    if (index == 1) {
      unawaited(widget.runtime.startPairingMode());
    } else if (index == 0) {
      _activatePreviewTab();
    }
  }

  void _activatePreviewTab() {
    unawaited(widget.runtime.startPairingMode());
    if (_localPreviewWanted) {
      unawaited(
        _changeLocalPreview(
          true,
          showFailureMessage: false,
        ),
      );
    }
  }

  void _retryLocalPreview() {
    _localPreviewWanted = true;
    _activatePreviewTab();
  }

  Future<void> _toggleLocalPreview(bool currentlyActive) => _changeLocalPreview(
        !currentlyActive,
        showFailureMessage: true,
      );

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

  Widget _buildTab(BuildContext context, ServerRuntimeState state) {
    final strings = AppStrings.of(context);
    return switch (_tab) {
      0 => _ServerTabFrame(
          key: const ValueKey('server-stream'),
          activeRole: widget.activeRole,
          onRoleSelected: widget.onRoleSelected,
          switchingRole: widget.switchingRole,
          children: [
            _ServerLiveStatusCard(
              state: state,
              onConnectParent: () => _selectTab(1),
              onRetry: _retryLocalPreview,
              onRestart: widget.onRestartServer,
            ),
            const SizedBox(height: 12),
            _LivePreviewCard(
              state: state,
              previewSource: widget.runtime.previewSource,
              fit: _previewFit,
              actionBusy: _previewActionBusy,
              actionTargetEnabled: _previewActionTargetEnabled,
              onEnterFullscreen: _enterFullscreenPreview,
              onToggleFit: _togglePreviewFit,
              onTogglePreview: () =>
                  _toggleLocalPreview(state.localPreviewActive),
            ),
            if (state.broadcastAccess != null) ...[
              const SizedBox(height: 16),
              _ServerBroadcastAccessCard(
                snapshot: state.broadcastAccess!,
                busy: _purchaseBusy,
                onUnlock: _unlockBroadcastAccess,
                onRestore: _restoreBroadcastAccess,
              ),
            ],
            const SizedBox(height: 12),
            const _SafeRoomSetupCard(),
            const SizedBox(height: 12),
            _ServerStreamDetailsCard(
              state: state,
              phaseLabel: _phaseLabel(strings, state.phase),
            ),
            if (state.phase != ServerRuntimePhase.stopped) ...[
              const SizedBox(height: 6),
              _StopRoomStreamButton(onPressed: _confirmStopStream),
            ],
          ],
        ),
      1 => _ServerTabFrame(
          key: const ValueKey('server-qr-ip'),
          activeRole: widget.activeRole,
          onRoleSelected: widget.onRoleSelected,
          switchingRole: widget.switchingRole,
          children: [
            _ServerSectionHeader(
              title: strings.ui('qrIpTicketTitle'),
              subtitle: strings.ui('qrIpTicketSubtitle'),
            ),
            const SizedBox(height: 10),
            _ConnectionCard(qrPayload: state.qrPayload),
            const SizedBox(height: 10),
            _QrIpActions(
              payload: state.qrPayload,
              onRefresh: widget.runtime.startPairingMode,
            ),
          ],
        ),
      2 => _ServerTabFrame(
          key: const ValueKey('server-services'),
          activeRole: widget.activeRole,
          onRoleSelected: widget.onRoleSelected,
          switchingRole: widget.switchingRole,
          children: [
            _ServerSectionHeader(
              title: strings.ui('serviceStatus'),
              subtitle: strings.ui('serviceStatusSubtitle'),
            ),
            const SizedBox(height: 10),
            _ServiceStatusGrid(state: state),
            const SizedBox(height: 12),
            const _PlatformRuntimeContractCard(),
          ],
        ),
      _ => _ServerTabFrame(
          key: const ValueKey('server-settings'),
          activeRole: widget.activeRole,
          onRoleSelected: widget.onRoleSelected,
          switchingRole: widget.switchingRole,
          children: [
            _ServerSectionHeader(
              title: strings.ui('serverSettings'),
              subtitle: strings.ui('serverSettingsSubtitle'),
            ),
            const SizedBox(height: 10),
            _ServerSettingsCard(
              motionThreshold: _motionThreshold,
              cryScoreThreshold: _cryScoreThreshold,
              notifyCooldownSeconds: _notifyCooldownSeconds,
              motionDurationSeconds: _motionDurationSeconds,
              cryDurationSeconds: _cryDurationSeconds,
              saving: _savingSettings,
              activePreset: _activeDetectionPreset,
              onPresetSelected: (preset) =>
                  unawaited(_applyDetectionPreset(preset)),
              onReset: _confirmResetSettings,
              onMotionThresholdChanged: (value) =>
                  setState(() => _motionThreshold = value),
              onMotionThresholdChangeEnd: (value) => _persistSettings(
                  () => widget.config.setMotionThreshold(value)),
              onCryScoreThresholdChanged: (value) =>
                  setState(() => _cryScoreThreshold = value),
              onCryScoreThresholdChangeEnd: (value) => _persistSettings(
                  () => widget.config.setCryScoreThreshold(value)),
              onNotifyCooldownChanged: (value) =>
                  setState(() => _notifyCooldownSeconds = value),
              onNotifyCooldownChangeEnd: (value) => _persistSettings(() =>
                  widget.config.setNotifyCooldownMs((value * 1000).round())),
              onMotionDurationChanged: (value) =>
                  setState(() => _motionDurationSeconds = value),
              onMotionDurationChangeEnd: (value) => _persistSettings(() =>
                  widget.config.setMotionMinDurationMs((value * 1000).round())),
              onCryDurationChanged: (value) =>
                  setState(() => _cryDurationSeconds = value),
              onCryDurationChangeEnd: (value) => _persistSettings(() =>
                  widget.config.setCryMinDurationMs((value * 1000).round())),
            ),
          ],
        ),
    };
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

List<MimiCamBottomNavItem> _serverNavItems(BuildContext context) {
  final strings = AppStrings.of(context);
  return [
    MimiCamBottomNavItem(
        icon: Icons.videocam_rounded, label: strings.ui('navStream')),
    MimiCamBottomNavItem(
        icon: Icons.qr_code_2_rounded, label: strings.ui('navQrIp')),
    MimiCamBottomNavItem(
        icon: Icons.settings_input_component_rounded,
        label: strings.ui('navService')),
    MimiCamBottomNavItem(
        icon: Icons.tune_rounded, label: strings.ui('navSettings')),
  ];
}

int _connectedParentCount(ServerRuntimeState state) {
  final connectedCount = state.activeClients > state.activeEventClients
      ? state.activeClients
      : state.activeEventClients;
  if (connectedCount == 0 && state.phase == ServerRuntimePhase.clientPaired) {
    return 1;
  }
  return connectedCount;
}

class _ServerTabFrame extends StatelessWidget {
  const _ServerTabFrame({
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
      padding: MimiCamDesignTokens.screenPadding.copyWith(top: 6, bottom: 18),
      children: [
        Align(
          alignment: Alignment.topRight,
          child: MimiCamRoleBadge(
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

class _ServerLiveStatusCard extends StatelessWidget {
  const _ServerLiveStatusCard({
    required this.state,
    required this.onConnectParent,
    required this.onRetry,
    required this.onRestart,
  });

  final ServerRuntimeState state;
  final VoidCallback onConnectParent;
  final VoidCallback onRetry;
  final VoidCallback? onRestart;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final stopped = state.phase == ServerRuntimePhase.stopped;
    final failed = state.phase == ServerRuntimePhase.error;
    final connectedParents = _connectedParentCount(state);
    final preparing = !stopped &&
        !failed &&
        (state.phase == ServerRuntimePhase.mediaStarting ||
            (state.localPreviewActive && !state.cameraActive));
    final title = failed
        ? strings.ui('streamStartFailed')
        : stopped
            ? strings.ui('serverStreamStoppedTitle')
            : preparing
                ? strings.ui('cameraPreparing')
                : strings.ui('roomStreamReady');
    final summary = failed
        ? strings.ui('serverStreamErrorBody')
        : stopped
            ? strings.ui('serverStreamStoppedBody')
            : preparing
                ? strings.ui('serverMediaPreparingBody')
                : connectedParents == 0
                    ? strings.ui('serverWaitingForParent')
                    : strings.uiFormat(
                        'serverParentsConnectedBody',
                        {'count': connectedParents},
                      );
    final accent = failed
        ? MimiCamDesignTokens.serverError
        : stopped
            ? MimiCamDesignTokens.serverDisabled
            : preparing
                ? MimiCamDesignTokens.serverBlue
                : MimiCamDesignTokens.serverSuccess;

    return Container(
      key: const ValueKey('server-live-status-card'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: MimiCamDesignTokens.serverPanel.withValues(alpha: .96),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: accent.withValues(alpha: .38),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .24),
            blurRadius: 18,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  failed
                      ? Icons.error_outline_rounded
                      : stopped
                          ? Icons.stop_rounded
                          : preparing
                              ? Icons.hourglass_top_rounded
                              : Icons.sensors_rounded,
                  color: MimiCamDesignTokens.serverInk,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: MimiCamDesignTokens.serverText,
                        fontSize: 20,
                        height: 1.1,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      summary,
                      style: const TextStyle(
                        color: MimiCamDesignTokens.serverTextMuted,
                        fontSize: 13.5,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (failed ||
              (stopped && onRestart != null) ||
              (!stopped && connectedParents == 0)) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: failed
                  ? FilledButton.icon(
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh_rounded),
                      style: FilledButton.styleFrom(
                        backgroundColor: MimiCamDesignTokens.serverCyan,
                        foregroundColor: MimiCamDesignTokens.serverInk,
                      ),
                      label: Text(strings.ui('tryAgain')),
                    )
                  : stopped
                      ? FilledButton.icon(
                          onPressed: onRestart,
                          icon: const Icon(Icons.restart_alt_rounded),
                          style: FilledButton.styleFrom(
                            backgroundColor: MimiCamDesignTokens.serverCyan,
                            foregroundColor: MimiCamDesignTokens.serverInk,
                          ),
                          label: Text(strings.ui('restartRoomStream')),
                        )
                      : FilledButton.icon(
                          onPressed: onConnectParent,
                          icon: const Icon(Icons.qr_code_2_rounded),
                          style: FilledButton.styleFrom(
                            backgroundColor: MimiCamDesignTokens.serverCyan,
                            foregroundColor: MimiCamDesignTokens.serverInk,
                          ),
                          label: Text(strings.ui('connectParentDevice')),
                        ),
            ),
          ],
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 11),
            decoration: BoxDecoration(
              color: MimiCamDesignTokens.serverInk.withValues(alpha: .38),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _ServerHealthIndicator(
                    icon: Icons.videocam_rounded,
                    label: strings.ui('camera'),
                    value: state.cameraActive
                        ? strings.ui('active')
                        : stopped || failed
                            ? strings.ui('off')
                            : strings.ui('preparing'),
                    color: state.cameraActive
                        ? MimiCamDesignTokens.serverSuccess
                        : stopped || failed
                            ? MimiCamDesignTokens.serverDisabled
                            : MimiCamDesignTokens.serverBlue,
                  ),
                ),
                const _ServerHealthDivider(),
                Expanded(
                  child: _ServerHealthIndicator(
                    icon: Icons.mic_rounded,
                    label: strings.ui('microphone'),
                    value: state.microphoneActive
                        ? strings.ui('active')
                        : stopped || failed
                            ? strings.ui('off')
                            : strings.ui('waiting'),
                    color: state.microphoneActive
                        ? MimiCamDesignTokens.serverSuccess
                        : stopped || failed
                            ? MimiCamDesignTokens.serverDisabled
                            : MimiCamDesignTokens.serverBlue,
                  ),
                ),
                const _ServerHealthDivider(),
                Expanded(
                  child: _ServerHealthIndicator(
                    icon: Icons.notifications_active_rounded,
                    label: strings.ui('alertsShort'),
                    value: state.cryAnalyzerActive || state.motionAnalyzerActive
                        ? state.cryAnalyzerActive && state.motionAnalyzerActive
                            ? strings.ui('active')
                            : strings.ui('partlyActive')
                        : stopped || failed
                            ? strings.ui('off')
                            : strings.ui('waiting'),
                    color: state.cryAnalyzerActive && state.motionAnalyzerActive
                        ? MimiCamDesignTokens.serverSuccess
                        : state.cryAnalyzerActive || state.motionAnalyzerActive
                            ? MimiCamDesignTokens.serverWarning
                            : stopped || failed
                                ? MimiCamDesignTokens.serverDisabled
                                : MimiCamDesignTokens.serverBlue,
                  ),
                ),
              ],
            ),
          ),
          if (!failed && !stopped && connectedParents > 0) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton.icon(
                onPressed: onConnectParent,
                icon: const Icon(Icons.add_link_rounded),
                style: OutlinedButton.styleFrom(
                  foregroundColor: MimiCamDesignTokens.serverText,
                  side: const BorderSide(
                    color: MimiCamDesignTokens.serverOutline,
                  ),
                ),
                label: Text(strings.ui('connectAnotherParent')),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ServerHealthIndicator extends StatelessWidget {
  const _ServerHealthIndicator({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$label: $value',
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 5),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: MimiCamDesignTokens.serverTextMuted,
              fontSize: 11.5,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: 12.5,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _ServerHealthDivider extends StatelessWidget {
  const _ServerHealthDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 56,
      color: MimiCamDesignTokens.serverOutline.withValues(alpha: .55),
    );
  }
}

class _SafeRoomSetupCard extends StatelessWidget {
  const _SafeRoomSetupCard();

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return MimiCamCard(
      key: const ValueKey('server-safe-room-setup'),
      dark: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const CircleAvatar(
                backgroundColor: MimiCamDesignTokens.serverCyan,
                child: Icon(
                  Icons.health_and_safety_rounded,
                  color: MimiCamDesignTokens.serverInk,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  strings.ui('safeRoomSetupTitle'),
                  style: const TextStyle(
                    color: MimiCamDesignTokens.serverText,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _SafeSetupItem(text: strings.ui('safeRoomSetupPlacement')),
          const SizedBox(height: 10),
          _SafeSetupItem(text: strings.ui('safeRoomSetupPower')),
          const SizedBox(height: 10),
          _SafeSetupItem(text: strings.ui('safeRoomSetupVerify')),
          const SizedBox(height: 14),
          Text(
            strings.ui('adultSupervisionNotice'),
            style: const TextStyle(
              color: MimiCamDesignTokens.serverTextMuted,
              fontSize: 12.5,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}

class _SafeSetupItem extends StatelessWidget {
  const _SafeSetupItem({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 1),
          child: Icon(
            Icons.chevron_right_rounded,
            color: MimiCamDesignTokens.serverCyan,
            size: 19,
          ),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: MimiCamDesignTokens.serverTextMuted,
              fontSize: 13.5,
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }
}

class _ServerStreamDetailsCard extends StatelessWidget {
  const _ServerStreamDetailsCard({
    required this.state,
    required this.phaseLabel,
  });

  final ServerRuntimeState state;
  final String phaseLabel;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final profile = state.mediaProfile;
    return MimiCamCard(
      key: const ValueKey('server-stream-details'),
      dark: true,
      child: Material(
        color: Colors.transparent,
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(top: 8),
            iconColor: MimiCamDesignTokens.serverCyan,
            collapsedIconColor: MimiCamDesignTokens.serverTextMuted,
            leading: const Icon(
              Icons.tune_rounded,
              color: MimiCamDesignTokens.serverCyan,
            ),
            title: Text(
              strings.ui('streamDetails'),
              style: const TextStyle(
                color: MimiCamDesignTokens.serverText,
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
            subtitle: Text(
              strings.ui('streamDetailsSubtitle'),
              style: const TextStyle(
                color: MimiCamDesignTokens.serverTextMuted,
                fontSize: 12.5,
              ),
            ),
            children: [
              _KeyVal(strings.ui('connection'), phaseLabel, dark: true),
              const SizedBox(height: 10),
              _KeyVal(
                strings.ui('parent'),
                strings.uiFormat(
                  'parentsCount',
                  {'count': _connectedParentCount(state)},
                ),
                dark: true,
              ),
              const SizedBox(height: 10),
              _KeyVal(
                strings.ui('streamProfile'),
                profile == null
                    ? strings.ui('autoMeasuring')
                    : localizedMediaProfileSummary(strings, profile),
                dark: true,
              ),
              const SizedBox(height: 10),
              _KeyVal(
                strings.ui('cryTracking'),
                state.cryAnalyzerActive
                    ? strings.ui('active')
                    : strings.ui('waiting'),
                dark: true,
              ),
              const SizedBox(height: 10),
              _KeyVal(
                strings.ui('motionTracking'),
                state.motionAnalyzerActive
                    ? strings.ui('active')
                    : strings.ui('waiting'),
                dark: true,
              ),
              if (state.errorMessage case final error?) ...[
                const SizedBox(height: 10),
                _KeyVal(
                  strings.ui('technicalError'),
                  error,
                  dark: true,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StopRoomStreamButton extends StatelessWidget {
  const _StopRoomStreamButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Align(
      child: TextButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.stop_circle_outlined, size: 20),
        style: TextButton.styleFrom(
          foregroundColor: MimiCamDesignTokens.serverTextMuted,
          minimumSize: const Size(48, 48),
        ),
        label: Text(
          strings.ui('stopRoomStream'),
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}

class _ServerSectionHeader extends StatelessWidget {
  const _ServerSectionHeader({required this.title, required this.subtitle});

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
            color: MimiCamDesignTokens.serverText,
            fontSize: 22,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: const TextStyle(
            color: MimiCamDesignTokens.serverTextMuted,
            fontSize: 14.5,
            height: 1.25,
          ),
        ),
      ],
    );
  }
}

class _ConnectionCard extends StatelessWidget {
  const _ConnectionCard({required this.qrPayload});

  final String? qrPayload;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final payload = qrPayload ?? 'mimicam://pairing/pending';
    return MimiCamCard(
      dark: true,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < 430;
          final isShortScreen = MediaQuery.sizeOf(context).height < 720;
          final qrSize = _readableQrSize(
            constraints.maxWidth,
            compact: isCompact,
            shortScreen: isShortScreen,
          );
          final details = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(strings.ui('secureQrPairing'),
                  style: const TextStyle(
                    color: MimiCamDesignTokens.serverText,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  )),
              const SizedBox(height: 6),
              Text(
                strings.ui('parentQrScanText'),
                style: const TextStyle(
                  color: MimiCamDesignTokens.serverTextMuted,
                  fontSize: 14.5,
                ),
              ),
              if (!isCompact) ...[
                const SizedBox(height: 12),
                _PayloadBox(payload: payload),
                const SizedBox(height: 12),
              ] else
                const SizedBox(height: 8),
              Text(
                strings.ui('keepCodeVisible'),
                style: const TextStyle(
                  color: MimiCamDesignTokens.serverTextMuted,
                  fontSize: 14.5,
                ),
              ),
            ],
          );

          if (isCompact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(child: _QrPanel(payload: payload, size: qrSize)),
                const SizedBox(height: 16),
                details,
              ],
            );
          }

          return Row(
            children: [
              Expanded(child: details),
              const SizedBox(width: 20),
              _QrPanel(payload: payload, size: qrSize),
            ],
          );
        },
      ),
    );
  }

  double _readableQrSize(
    double maxWidth, {
    required bool compact,
    required bool shortScreen,
  }) {
    final compactCap = shortScreen ? 212.0 : 244.0;
    final maxSafeSize = (maxWidth - _QrPanel.outerPadding * 2)
        .clamp(160.0, compact ? compactCap : 260.0);
    final preferredSize = maxWidth * (compact ? .70 : .42);
    final minReadableSize = maxSafeSize < 220 ? maxSafeSize : 220.0;
    return preferredSize.clamp(minReadableSize, maxSafeSize).toDouble();
  }
}

class _PayloadBox extends StatelessWidget {
  const _PayloadBox({required this.payload});

  final String payload;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: MimiCamDesignTokens.serverIce,
        borderRadius: BorderRadius.circular(14),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SelectableText(
          payload,
          maxLines: 1,
          style: const TextStyle(
            color: MimiCamDesignTokens.serverInk,
            fontSize: 14,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _QrPanel extends StatelessWidget {
  const _QrPanel({required this.payload, required this.size});

  static const outerPadding = 8.0;
  static const _radius = 18.0;

  final String payload;
  final double size;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Container(
        key: const ValueKey('server-qr-panel'),
        clipBehavior: Clip.antiAlias,
        padding: const EdgeInsets.all(outerPadding),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(_radius),
        ),
        child: QrImageView(
          data: payload,
          size: size,
          padding: EdgeInsets.zero,
          eyeStyle: const QrEyeStyle(color: MimiCamDesignTokens.serverInk),
          dataModuleStyle:
              const QrDataModuleStyle(color: MimiCamDesignTokens.serverInk),
        ),
      ),
    );
  }
}

class _QrIpActions extends StatelessWidget {
  const _QrIpActions({required this.payload, required this.onRefresh});

  final String? payload;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return MimiCamCard(
      dark: true,
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          SizedBox(
            height: 48,
            child: FilledButton.icon(
              onPressed: () async {
                await onRefresh();
                if (!context.mounted) return;
                ScaffoldMessenger.of(context)
                  ..clearSnackBars()
                  ..showSnackBar(
                    SnackBar(content: Text(strings.ui('qrTicketRefreshed'))),
                  );
              },
              icon: const Icon(Icons.refresh_rounded),
              style: FilledButton.styleFrom(
                backgroundColor: MimiCamDesignTokens.serverCyan,
                foregroundColor: MimiCamDesignTokens.serverInk,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              label: Text(
                strings.ui('refreshQr'),
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
          SizedBox(
            height: 48,
            child: OutlinedButton.icon(
              onPressed: payload == null
                  ? null
                  : () async {
                      await Clipboard.setData(ClipboardData(text: payload!));
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context)
                        ..clearSnackBars()
                        ..showSnackBar(
                          SnackBar(content: Text(strings.ui('ticketCopied'))),
                        );
                    },
              icon: const Icon(Icons.copy_rounded),
              style: OutlinedButton.styleFrom(
                foregroundColor: MimiCamDesignTokens.serverText,
                side: const BorderSide(
                  color: MimiCamDesignTokens.serverOutline,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              label: Text(
                strings.ui('copyAddress'),
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ServiceStatusGrid extends StatelessWidget {
  const _ServiceStatusGrid({required this.state});

  final ServerRuntimeState state;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final cards = [
      _ServiceStatusCard(
        icon: Icons.videocam_rounded,
        title: strings.ui('camera'),
        value:
            state.cameraActive ? strings.ui('active') : strings.ui('preparing'),
        color: state.cameraActive
            ? MimiCamDesignTokens.serverSuccess
            : MimiCamDesignTokens.serverBlue,
      ),
      _ServiceStatusCard(
        icon: Icons.mic_rounded,
        title: strings.ui('microphone'),
        value:
            state.microphoneActive ? strings.ui('active') : strings.ui('off'),
        color: state.microphoneActive
            ? MimiCamDesignTokens.serverSuccess
            : MimiCamDesignTokens.serverDisabled,
      ),
      _ServiceStatusCard(
        icon: Icons.hub_rounded,
        title: 'WebSocket',
        value: strings
            .uiFormat('eventClientsCount', {'count': state.activeEventClients}),
        color: state.activeEventClients > 0
            ? MimiCamDesignTokens.serverSuccess
            : MimiCamDesignTokens.serverBlue,
      ),
      _ServiceStatusCard(
        icon: Icons.people_alt_rounded,
        title: strings.ui('clientCount'),
        value:
            strings.uiFormat('connectedCount', {'count': state.activeClients}),
        color: state.activeClients > 0
            ? MimiCamDesignTokens.serverSuccess
            : MimiCamDesignTokens.serverDisabled,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 520) {
          return Column(
            children: [
              for (final card in cards) ...[
                card,
                if (card != cards.last) const SizedBox(height: 10),
              ],
            ],
          );
        }
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final card in cards)
              SizedBox(width: (constraints.maxWidth - 12) / 2, child: card),
          ],
        );
      },
    );
  }
}

class _PlatformRuntimeContractCard extends StatefulWidget {
  const _PlatformRuntimeContractCard();

  @override
  State<_PlatformRuntimeContractCard> createState() =>
      _PlatformRuntimeContractCardState();
}

class _PlatformRuntimeContractCardState
    extends State<_PlatformRuntimeContractCard> {
  static const _contract = PlatformRuntimeContract();
  Timer? _refreshTimer;
  PlatformRuntimeSnapshot? _snapshot;

  @override
  void initState() {
    super.initState();
    _refresh();
    // The native EventChannel has one lifecycle owner: ServerRuntime. A second
    // listener here could replace its event sink on iOS/Android, so this
    // presentation card refreshes the read-only method-channel snapshot.
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _refresh(),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final snapshot = _snapshot;
    final platform = snapshot?.platform;
    final active = snapshot?.foregroundServiceActive == true;
    final message = switch (platform) {
      PlatformRuntimeKind.ios => strings.ui('iosForegroundOnlyContract'),
      PlatformRuntimeKind.android when active =>
        strings.ui('androidServiceActiveContract'),
      PlatformRuntimeKind.android =>
        strings.ui('androidServiceInactiveContract'),
      _ => strings.ui('platformRuntimeUnknownContract'),
    };
    return MimiCamCard(
      dark: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            backgroundColor: active
                ? MimiCamDesignTokens.serverSuccess
                : MimiCamDesignTokens.serverDisabled,
            child: Icon(
              platform == PlatformRuntimeKind.ios
                  ? Icons.phone_iphone_rounded
                  : Icons.settings_applications_rounded,
              color: MimiCamDesignTokens.serverInk,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  strings.ui('platformRuntimeContractTitle'),
                  style: const TextStyle(
                    color: MimiCamDesignTokens.serverText,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  message,
                  style: const TextStyle(
                    color: MimiCamDesignTokens.serverTextMuted,
                    fontSize: 13.5,
                    height: 1.3,
                  ),
                ),
                if (snapshot?.backgroundRecoveryAfterProcessDeath == false) ...[
                  const SizedBox(height: 6),
                  Text(
                    strings.ui('processRecoveryForegroundContract'),
                    style: const TextStyle(
                      color: MimiCamDesignTokens.serverWarning,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _refresh() {
    unawaited(_contract.snapshot().then((snapshot) {
      if (mounted) setState(() => _snapshot = snapshot);
    }));
  }
}

class _ServiceStatusCard extends StatelessWidget {
  const _ServiceStatusCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: MimiCamDesignTokens.cardDecoration(dark: true),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: color,
            child: Icon(icon, color: MimiCamDesignTokens.serverInk),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: MimiCamDesignTokens.serverText,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    color: MimiCamDesignTokens.serverTextMuted,
                    fontSize: 13.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LivePreviewCard extends StatelessWidget {
  const _LivePreviewCard({
    required this.state,
    required this.previewSource,
    required this.fit,
    required this.actionBusy,
    required this.actionTargetEnabled,
    required this.onEnterFullscreen,
    required this.onToggleFit,
    required this.onTogglePreview,
  });

  final ServerRuntimeState state;
  final Object? previewSource;
  final BoxFit fit;
  final bool actionBusy;
  final bool? actionTargetEnabled;
  final VoidCallback onEnterFullscreen;
  final VoidCallback onToggleFit;
  final VoidCallback onTogglePreview;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final controller = previewSource is CameraController
        ? previewSource as CameraController
        : null;
    final jpegSource = previewSource is ServerJpegPreviewSource
        ? previewSource as ServerJpegPreviewSource
        : null;
    final stopped = state.phase == ServerRuntimePhase.stopped;
    final previewActive = state.localPreviewActive;
    final blockedByParentWatch =
        state.externalCaptureActive && !state.localPreviewActive;
    final showCamera = previewActive &&
        state.cameraActive &&
        ((controller != null && controller.value.isInitialized) ||
            jpegSource != null);
    final description = stopped
        ? strings.ui('serverStreamStoppedBody')
        : blockedByParentWatch
            ? strings.ui('localPreviewUnavailableDuringParentWatch')
            : !previewActive
                ? strings.ui('localPreviewOffBody')
                : showCamera
                    ? strings.ui('cameraRoomCheckText')
                    : state.cameraActive
                        ? strings.ui('localPreviewPreparingText')
                        : strings.ui('cameraPermissionPreviewText');

    return MimiCamCard(
      key: const ValueKey('server-live-preview-card'),
      dark: true,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < 420;
          final stackHeader = constraints.maxWidth < 240 ||
              MediaQuery.textScalerOf(context).scale(16) > 20;
          final title = Row(
            children: [
              const Icon(
                Icons.videocam_rounded,
                color: MimiCamDesignTokens.serverCyan,
                size: 22,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  strings.ui('roomCamera'),
                  style: const TextStyle(
                    color: MimiCamDesignTokens.serverText,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          );
          final toggle = _LocalPreviewToggleButton(
            active: previewActive,
            busy: actionBusy,
            targetEnabled: actionTargetEnabled,
            enabled: !blockedByParentWatch,
            onPressed: onTogglePreview,
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              title,
              if (!stopped && stackHeader) ...[
                const SizedBox(height: 10),
                SizedBox(width: double.infinity, child: toggle),
              ],
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: isCompact ? 190 : 280),
                child: AspectRatio(
                  aspectRatio:
                      controller != null && controller.value.isInitialized
                          ? controller.value.aspectRatio
                          : 16 / 9,
                  child: RepaintBoundary(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        _CameraPreviewSurface(
                          previewSource: previewSource,
                          showCamera: showCamera,
                          localPreviewActive: previewActive,
                          fit: fit,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        if (!stopped && !stackHeader)
                          Positioned(
                            top: 8,
                            left: 8,
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: showCamera
                                    ? constraints.maxWidth - 122
                                    : constraints.maxWidth - 16,
                              ),
                              child: toggle,
                            ),
                          ),
                        if (showCamera)
                          Positioned(
                            bottom: 10,
                            left: 10,
                            child: _PreviewStatusChip(
                              label: strings.ui('livePreview'),
                              color: MimiCamDesignTokens.serverSuccess,
                            ),
                          ),
                        if (showCamera)
                          Positioned(
                            top: 8,
                            right: 8,
                            child: Row(
                              children: [
                                _PreviewIconButton(
                                  icon: fit == BoxFit.cover
                                      ? Icons.fit_screen_rounded
                                      : Icons.crop_free_rounded,
                                  tooltip: fit == BoxFit.cover
                                      ? strings.ui('videoFitContain')
                                      : strings.ui('videoFitCover'),
                                  onTap: onToggleFit,
                                ),
                                const SizedBox(width: 4),
                                _PreviewIconButton(
                                  icon: Icons.fullscreen_rounded,
                                  tooltip:
                                      strings.ui('serverPreviewFullScreen'),
                                  onTap: onEnterFullscreen,
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                description,
                style: const TextStyle(
                  color: MimiCamDesignTokens.serverTextMuted,
                  fontSize: 14,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _LocalPreviewToggleButton extends StatelessWidget {
  const _LocalPreviewToggleButton({
    required this.active,
    required this.busy,
    required this.targetEnabled,
    required this.enabled,
    required this.onPressed,
  });

  final bool active;
  final bool busy;
  final bool? targetEnabled;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final target = targetEnabled ?? active;
    final semanticLabel = busy
        ? strings.ui(
            target ? 'localPreviewTurningOn' : 'localPreviewTurningOff',
          )
        : strings.ui(
            active ? 'turnOffLocalPreview' : 'turnOnLocalPreview',
          );
    final label = strings.ui(
      active ? 'hideLocalPreviewAction' : 'showLocalPreviewAction',
    );
    final icon = busy
        ? SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2.2,
              color: active
                  ? MimiCamDesignTokens.serverCyan
                  : MimiCamDesignTokens.serverInk,
            ),
          )
        : Icon(
            active ? Icons.visibility_off_rounded : Icons.visibility_rounded,
            size: 19,
          );
    final callback = busy || !enabled ? null : onPressed;
    final sharedStyle = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(0, 48)),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 12),
      ),
      textStyle: const WidgetStatePropertyAll(
        TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800),
      ),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );

    final button = active
        ? OutlinedButton.icon(
            key: const ValueKey('server-local-preview-toggle'),
            onPressed: callback,
            style: sharedStyle.copyWith(
              backgroundColor: WidgetStatePropertyAll(
                MimiCamDesignTokens.serverSurfaceRaised.withValues(alpha: .94),
              ),
              foregroundColor: const WidgetStatePropertyAll(
                MimiCamDesignTokens.serverCyan,
              ),
              side: WidgetStatePropertyAll(
                BorderSide(
                  color: enabled
                      ? MimiCamDesignTokens.serverCyan
                      : MimiCamDesignTokens.serverDisabled,
                ),
              ),
            ),
            icon: icon,
            label: Text(label),
          )
        : FilledButton.icon(
            key: const ValueKey('server-local-preview-toggle'),
            onPressed: callback,
            style: sharedStyle.copyWith(
              backgroundColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.disabled)
                    ? MimiCamDesignTokens.serverDisabled
                    : MimiCamDesignTokens.serverCyan,
              ),
              foregroundColor: const WidgetStatePropertyAll(
                MimiCamDesignTokens.serverInk,
              ),
            ),
            icon: icon,
            label: Text(label),
          );

    return Tooltip(
      message: semanticLabel,
      child: Semantics(
        button: true,
        label: semanticLabel,
        toggled: active,
        enabled: callback != null,
        liveRegion: busy,
        onTap: callback,
        child: ExcludeSemantics(child: button),
      ),
    );
  }
}

class _ServerBroadcastAccessCard extends StatelessWidget {
  const _ServerBroadcastAccessCard({
    required this.snapshot,
    required this.busy,
    required this.onUnlock,
    required this.onRestore,
  });

  final BroadcastAccessSnapshot snapshot;
  final bool busy;
  final VoidCallback onUnlock;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final locked = snapshot.isLocked;
    final unlocked = snapshot.unlocked;
    final title = unlocked
        ? strings.ui('broadcastAccessUnlockedTitle')
        : locked
            ? strings.ui('broadcastAccessLockedTitle')
            : strings.ui('broadcastAccessTrialTitle');
    final body = unlocked
        ? strings.ui('broadcastAccessUnlockedBody')
        : locked
            ? strings.ui('broadcastAccessLockedBody')
            : strings.uiFormat('broadcastAccessTrialBody', {
                'remaining': _remainingText(snapshot.remaining),
                'price': snapshot.priceLabel,
              });
    return MimiCamCard(
      dark: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: unlocked
                    ? MimiCamDesignTokens.serverSuccess
                    : locked
                        ? MimiCamDesignTokens.serverWarning
                        : MimiCamDesignTokens.serverBlue,
                child: Icon(
                  unlocked
                      ? Icons.verified_rounded
                      : locked
                          ? Icons.lock_rounded
                          : Icons.hourglass_bottom_rounded,
                  color: MimiCamDesignTokens.serverInk,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: MimiCamDesignTokens.serverText,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            body,
            style: const TextStyle(
              color: MimiCamDesignTokens.serverTextMuted,
              fontSize: 14,
              height: 1.25,
            ),
          ),
          if (!unlocked) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                minHeight: 8,
                value: snapshot.usedRatio,
                backgroundColor:
                    MimiCamDesignTokens.serverOutline.withValues(alpha: .46),
                valueColor: AlwaysStoppedAnimation<Color>(
                  locked
                      ? MimiCamDesignTokens.serverWarning
                      : MimiCamDesignTokens.serverCyan,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  onPressed: busy ? null : onUnlock,
                  icon: busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.lock_open_rounded),
                  style: FilledButton.styleFrom(
                    backgroundColor: MimiCamDesignTokens.serverCyan,
                    foregroundColor: MimiCamDesignTokens.serverInk,
                  ),
                  label: Text(
                    strings.uiFormat('unlockLifetimePrice', {
                      'price': snapshot.priceLabel,
                    }),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: busy ? null : onRestore,
                  icon: const Icon(Icons.restore_rounded),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: MimiCamDesignTokens.serverText,
                    side: const BorderSide(
                      color: MimiCamDesignTokens.serverOutline,
                    ),
                  ),
                  label: Text(strings.ui('restorePurchase')),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  static String _remainingText(Duration duration) {
    final totalMinutes = duration.inMinutes.clamp(0, 24 * 60);
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    if (hours == 0) return '$minutes dk';
    if (minutes == 0) return '$hours sa';
    return '$hours sa $minutes dk';
  }
}

class _PreviewStatusChip extends StatelessWidget {
  const _PreviewStatusChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: ShapeDecoration(
        color: color,
        shape: const StadiumBorder(),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: MimiCamDesignTokens.serverInk,
          fontWeight: FontWeight.w900,
          fontSize: 12.5,
        ),
      ),
    );
  }
}

class _PreviewIconButton extends StatelessWidget {
  const _PreviewIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: MimiCamDesignTokens.serverSurfaceRaised.withValues(alpha: .92),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 48,
            height: 48,
            child: Icon(
              icon,
              color: MimiCamDesignTokens.serverText,
              size: 22,
            ),
          ),
        ),
      ),
    );
  }
}

class _CameraPreviewSurface extends StatelessWidget {
  const _CameraPreviewSurface({
    required this.previewSource,
    required this.showCamera,
    required this.localPreviewActive,
    required this.fit,
    this.borderRadius = BorderRadius.zero,
  });

  final Object? previewSource;
  final bool showCamera;
  final bool localPreviewActive;
  final BoxFit fit;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: borderRadius,
      child: ColoredBox(
        color: Colors.black,
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (!localPreviewActive) {
              return const _PreviewOffContent();
            }
            if (!showCamera) {
              return const _PreviewWaitingContent();
            }
            final jpegSource = previewSource is ServerJpegPreviewSource
                ? previewSource as ServerJpegPreviewSource
                : null;
            if (jpegSource != null) {
              return StreamBuilder<Uint8List>(
                stream: jpegSource.previewFrames,
                initialData: jpegSource.latestPreviewFrame,
                builder: (context, snapshot) {
                  final frame = snapshot.data;
                  if (frame == null || frame.isEmpty) {
                    return const _PreviewWaitingContent();
                  }
                  return Image.memory(
                    frame,
                    fit: fit,
                    gaplessPlayback: true,
                    filterQuality: FilterQuality.low,
                    width: constraints.maxWidth,
                    height: constraints.maxHeight,
                  );
                },
              );
            }
            final activeController = previewSource is CameraController
                ? previewSource as CameraController
                : null;
            if (activeController == null ||
                !activeController.value.isInitialized) {
              return const _PreviewWaitingContent();
            }
            return FittedBox(
              fit: fit,
              child: SizedBox(
                width: activeController.value.previewSize?.height ??
                    constraints.maxWidth,
                height: activeController.value.previewSize?.width ??
                    constraints.maxHeight,
                child: CameraPreview(activeController),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _FullscreenPreview extends StatelessWidget {
  const _FullscreenPreview({
    required this.state,
    required this.previewSource,
    required this.fit,
    required this.onExit,
    required this.onToggleFit,
  });

  final ServerRuntimeState state;
  final Object? previewSource;
  final BoxFit fit;
  final VoidCallback onExit;
  final VoidCallback onToggleFit;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final controller = previewSource is CameraController
        ? previewSource as CameraController
        : null;
    final jpegSource = previewSource is ServerJpegPreviewSource
        ? previewSource as ServerJpegPreviewSource
        : null;
    final showCamera = state.localPreviewActive &&
        state.cameraActive &&
        ((controller != null && controller.value.isInitialized) ||
            jpegSource != null);
    return SafeArea(
      child: Stack(
        fit: StackFit.expand,
        children: [
          _CameraPreviewSurface(
            previewSource: previewSource,
            showCamera: showCamera,
            localPreviewActive: state.localPreviewActive,
            fit: fit,
          ),
          Positioned(
            top: 12,
            left: 12,
            child: _PreviewIconButton(
              icon: Icons.close_rounded,
              tooltip: strings.ui('exitFullScreen'),
              onTap: onExit,
            ),
          ),
          Positioned(
            top: 12,
            right: 12,
            child: _PreviewIconButton(
              icon: fit == BoxFit.cover
                  ? Icons.fit_screen_rounded
                  : Icons.crop_free_rounded,
              tooltip: fit == BoxFit.cover
                  ? strings.ui('videoFitContain')
                  : strings.ui('videoFitCover'),
              onTap: onToggleFit,
            ),
          ),
          Positioned(
            left: 12,
            bottom: 12,
            child: _PreviewStatusChip(
              label: showCamera
                  ? strings.ui('livePreview')
                  : state.localPreviewActive
                      ? strings.ui('cameraStarting')
                      : strings.ui('localPreviewOff'),
              color: showCamera
                  ? MimiCamDesignTokens.serverSuccess
                  : state.localPreviewActive
                      ? MimiCamDesignTokens.serverBlue
                      : MimiCamDesignTokens.serverDisabled,
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewOffContent extends StatelessWidget {
  const _PreviewOffContent();

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Center(
      key: const ValueKey('server-local-preview-off'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.visibility_off_rounded,
            color: MimiCamDesignTokens.serverDisabled,
            size: 36,
          ),
          const SizedBox(height: 8),
          Text(
            strings.ui('localPreviewOff'),
            style: const TextStyle(
              color: MimiCamDesignTokens.serverTextMuted,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewWaitingContent extends StatelessWidget {
  const _PreviewWaitingContent();

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.videocam_off_rounded,
            color: MimiCamDesignTokens.serverDisabled,
            size: 34,
          ),
          const SizedBox(height: 8),
          Text(
            strings.ui('cameraPreparing'),
            style: const TextStyle(
              color: MimiCamDesignTokens.serverTextMuted,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

enum _DetectionPreset {
  sensitive,
  balanced,
  fewerAlerts;

  IconData get icon => switch (this) {
        sensitive => Icons.hearing_rounded,
        balanced => Icons.balance_rounded,
        fewerAlerts => Icons.notifications_paused_rounded,
      };

  _DetectionPresetSettings get settings => switch (this) {
        sensitive => const _DetectionPresetSettings(
            motionThreshold: .15,
            cryScoreThreshold: .50,
            notifyCooldownSeconds: 45,
            motionDurationSeconds: 1,
            cryDurationSeconds: 1,
          ),
        balanced => const _DetectionPresetSettings(
            motionThreshold: .22,
            cryScoreThreshold: .65,
            notifyCooldownSeconds: 60,
            motionDurationSeconds: 2,
            cryDurationSeconds: 1.5,
          ),
        fewerAlerts => const _DetectionPresetSettings(
            motionThreshold: .35,
            cryScoreThreshold: .78,
            notifyCooldownSeconds: 90,
            motionDurationSeconds: 3.5,
            cryDurationSeconds: 2.5,
          ),
      };

  String label(AppStrings strings) => switch (this) {
        sensitive => strings.ui('sensitivePreset'),
        balanced => strings.ui('balancedPreset'),
        fewerAlerts => strings.ui('fewerAlertsPreset'),
      };

  String description(AppStrings strings) => switch (this) {
        sensitive => strings.ui('sensitivePresetDescription'),
        balanced => strings.ui('balancedPresetDescription'),
        fewerAlerts => strings.ui('fewerAlertsPresetDescription'),
      };
}

class _DetectionPresetSettings {
  const _DetectionPresetSettings({
    required this.motionThreshold,
    required this.cryScoreThreshold,
    required this.notifyCooldownSeconds,
    required this.motionDurationSeconds,
    required this.cryDurationSeconds,
  });

  final double motionThreshold;
  final double cryScoreThreshold;
  final double notifyCooldownSeconds;
  final double motionDurationSeconds;
  final double cryDurationSeconds;
}

class _ServerSettingsCard extends StatelessWidget {
  const _ServerSettingsCard({
    required this.motionThreshold,
    required this.cryScoreThreshold,
    required this.notifyCooldownSeconds,
    required this.motionDurationSeconds,
    required this.cryDurationSeconds,
    required this.saving,
    required this.activePreset,
    required this.onPresetSelected,
    required this.onReset,
    required this.onMotionThresholdChanged,
    required this.onMotionThresholdChangeEnd,
    required this.onCryScoreThresholdChanged,
    required this.onCryScoreThresholdChangeEnd,
    required this.onNotifyCooldownChanged,
    required this.onNotifyCooldownChangeEnd,
    required this.onMotionDurationChanged,
    required this.onMotionDurationChangeEnd,
    required this.onCryDurationChanged,
    required this.onCryDurationChangeEnd,
  });

  final double motionThreshold;
  final double cryScoreThreshold;
  final double notifyCooldownSeconds;
  final double motionDurationSeconds;
  final double cryDurationSeconds;
  final bool saving;
  final _DetectionPreset? activePreset;
  final ValueChanged<_DetectionPreset> onPresetSelected;
  final VoidCallback onReset;
  final ValueChanged<double> onMotionThresholdChanged;
  final ValueChanged<double> onMotionThresholdChangeEnd;
  final ValueChanged<double> onCryScoreThresholdChanged;
  final ValueChanged<double> onCryScoreThresholdChangeEnd;
  final ValueChanged<double> onNotifyCooldownChanged;
  final ValueChanged<double> onNotifyCooldownChangeEnd;
  final ValueChanged<double> onMotionDurationChanged;
  final ValueChanged<double> onMotionDurationChangeEnd;
  final ValueChanged<double> onCryDurationChanged;
  final ValueChanged<double> onCryDurationChangeEnd;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return MimiCamCard(
      dark: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                strings.ui('silentSafeDetection'),
                style: const TextStyle(
                  color: MimiCamDesignTokens.serverText,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              _SettingsSaveChip(saving: saving),
              TextButton.icon(
                onPressed: saving ? null : onReset,
                icon: const Icon(Icons.restart_alt_rounded),
                label: Text(strings.ui('resetDefaults')),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            strings.ui('detectionSettingsSubtitle'),
            style: const TextStyle(
              color: MimiCamDesignTokens.serverTextMuted,
              fontSize: 14.5,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 14),
          Text(strings.ui('quickSetup'),
              style: const TextStyle(
                color: MimiCamDesignTokens.serverText,
                fontSize: 15,
                fontWeight: FontWeight.w900,
              )),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final preset in _DetectionPreset.values)
                ChoiceChip(
                  selected: activePreset == preset,
                  onSelected: saving ? null : (_) => onPresetSelected(preset),
                  showCheckmark: false,
                  selectedColor:
                      MimiCamDesignTokens.serverCyan.withValues(alpha: .18),
                  backgroundColor: MimiCamDesignTokens.serverSurfaceRaised
                      .withValues(alpha: .74),
                  side: BorderSide(
                    color: activePreset == preset
                        ? MimiCamDesignTokens.serverCyan
                        : MimiCamDesignTokens.serverOutline,
                  ),
                  avatar: Icon(
                    preset.icon,
                    size: 17,
                    color: activePreset == preset
                        ? MimiCamDesignTokens.serverCyan
                        : MimiCamDesignTokens.serverTextMuted,
                  ),
                  labelStyle: TextStyle(
                    color: activePreset == preset
                        ? MimiCamDesignTokens.serverText
                        : MimiCamDesignTokens.serverTextMuted,
                    fontWeight: activePreset == preset
                        ? FontWeight.w900
                        : FontWeight.w700,
                  ),
                  label: Text(preset.label(strings)),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            activePreset?.description(strings) ??
                strings.ui('customDetectionPresetDescription'),
            style: const TextStyle(
              color: MimiCamDesignTokens.serverTextMuted,
              fontSize: 13.5,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 8),
          Material(
            color: Colors.transparent,
            child: Theme(
              data:
                  Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                title: Text(strings.ui('advancedSettings'),
                    style: const TextStyle(
                      color: MimiCamDesignTokens.serverText,
                      fontWeight: FontWeight.w900,
                    )),
                subtitle: Text(
                  strings.ui('advancedSettingsDescription'),
                  style: const TextStyle(
                    color: MimiCamDesignTokens.serverTextMuted,
                  ),
                ),
                iconColor: MimiCamDesignTokens.serverCyan,
                collapsedIconColor: MimiCamDesignTokens.serverTextMuted,
                children: [
                  for (final spec in _sliderSpecs(strings)) ...[
                    _SettingSlider(
                      title: spec.title,
                      description: spec.description,
                      valueLabel: spec.valueLabel,
                      value: spec.value,
                      min: spec.min,
                      max: spec.max,
                      divisions: spec.divisions,
                      color: spec.color,
                      onChanged: spec.onChanged,
                      onChangeEnd: spec.onChangeEnd,
                    ),
                    const SizedBox(height: 12),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 2),
          _KeyVal(
            strings.ui('localNotification'),
            strings.ui('sentToClientDevice'),
            dark: true,
          ),
        ],
      ),
    );
  }

  List<_SettingSliderSpec> _sliderSpecs(AppStrings strings) {
    // Slider constraints are kept together so changing a detection policy does
    // not require editing the responsive settings layout.
    return [
      _SettingSliderSpec(
        title: strings.ui('cryThreshold'),
        description: strings.ui('cryThresholdDescription'),
        valueLabel: '%${(cryScoreThreshold * 100).round()}',
        value: cryScoreThreshold,
        min: .20,
        max: .95,
        divisions: 75,
        color: MimiCamDesignTokens.serverCyan,
        onChanged: onCryScoreThresholdChanged,
        onChangeEnd: onCryScoreThresholdChangeEnd,
      ),
      _SettingSliderSpec(
        title: strings.ui('motionThreshold'),
        description: strings.ui('motionThresholdDescription'),
        valueLabel: '%${(motionThreshold * 100).round()}',
        value: motionThreshold,
        min: .05,
        max: .60,
        divisions: 55,
        color: MimiCamDesignTokens.serverViolet,
        onChanged: onMotionThresholdChanged,
        onChangeEnd: onMotionThresholdChangeEnd,
      ),
      _SettingSliderSpec(
        title: strings.ui('notificationCooldown'),
        description: strings.ui('notificationCooldownDescription'),
        valueLabel: localizedSecondsLabel(strings, notifyCooldownSeconds),
        value: notifyCooldownSeconds,
        min: 10,
        max: 180,
        divisions: 34,
        color: MimiCamDesignTokens.serverBlue,
        onChanged: onNotifyCooldownChanged,
        onChangeEnd: onNotifyCooldownChangeEnd,
      ),
      _SettingSliderSpec(
        title: strings.ui('cryMinimumDuration'),
        description: strings.ui('cryMinimumDurationDescription'),
        valueLabel: localizedSecondsLabel(
          strings,
          cryDurationSeconds,
          fractionDigits: 1,
        ),
        value: cryDurationSeconds,
        min: .5,
        max: 6,
        divisions: 11,
        color: MimiCamDesignTokens.serverCyan,
        onChanged: onCryDurationChanged,
        onChangeEnd: onCryDurationChangeEnd,
      ),
      _SettingSliderSpec(
        title: strings.ui('motionMinimumDuration'),
        description: strings.ui('motionMinimumDurationDescription'),
        valueLabel: localizedSecondsLabel(
          strings,
          motionDurationSeconds,
          fractionDigits: 1,
        ),
        value: motionDurationSeconds,
        min: .5,
        max: 6,
        divisions: 11,
        color: MimiCamDesignTokens.serverViolet,
        onChanged: onMotionDurationChanged,
        onChangeEnd: onMotionDurationChangeEnd,
      ),
    ];
  }
}

class _SettingSliderSpec {
  const _SettingSliderSpec({
    required this.title,
    required this.description,
    required this.valueLabel,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.color,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final String title;
  final String description;
  final String valueLabel;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final Color color;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;
}

class _SettingsSaveChip extends StatelessWidget {
  const _SettingsSaveChip({required this.saving});

  final bool saving;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: ShapeDecoration(
        color: saving
            ? MimiCamDesignTokens.serverBlue
            : MimiCamDesignTokens.serverSuccess,
        shape: const StadiumBorder(),
      ),
      child: Text(
        saving ? strings.ui('saving') : strings.ui('realSettings'),
        style: const TextStyle(
          color: MimiCamDesignTokens.serverInk,
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _SettingSlider extends StatelessWidget {
  const _SettingSlider({
    required this.title,
    required this.description,
    required this.valueLabel,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.color,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final String title;
  final String description;
  final String valueLabel;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final Color color;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  @override
  Widget build(BuildContext context) {
    final safeValue = value.clamp(min, max).toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: MimiCamDesignTokens.serverText,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            Text(
              valueLabel,
              style: TextStyle(
                color: color,
                fontSize: 15,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          description,
          style: const TextStyle(
            color: MimiCamDesignTokens.serverTextMuted,
            fontSize: 13.5,
            height: 1.25,
          ),
        ),
        Slider(
          activeColor: color,
          inactiveColor:
              MimiCamDesignTokens.serverOutline.withValues(alpha: .58),
          value: safeValue,
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
          onChangeEnd: onChangeEnd,
        ),
      ],
    );
  }
}

class _KeyVal extends StatelessWidget {
  const _KeyVal(this.label, this.value, {this.dark = false});

  final String label;
  final String value;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 15,
              color: dark
                  ? MimiCamDesignTokens.serverTextMuted
                  : MimiCamDesignTokens.slate,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 15,
              color: dark
                  ? MimiCamDesignTokens.serverText
                  : MimiCamDesignTokens.slate,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    );
  }
}
