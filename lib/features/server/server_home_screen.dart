import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../app/app_role.dart';
import '../../l10n/app_strings.dart';
import '../../services/configuration_service.dart';
import '../shared/presentation/mimicam_design_tokens.dart';
import '../shared/presentation/mimicam_shells.dart';
import 'server_runtime.dart';

class ServerHomeScreen extends StatefulWidget {
  const ServerHomeScreen({
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
  State<ServerHomeScreen> createState() => _ServerHomeScreenState();
}

class _ServerHomeScreenState extends State<ServerHomeScreen> {
  late double _motionThreshold;
  late double _cryScoreThreshold;
  late double _notifyCooldownSeconds;
  late double _motionDurationSeconds;
  late double _cryDurationSeconds;
  bool _savingSettings = false;
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _loadSettings();
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
    await save();
    await widget.runtime.reloadAnalysisSettings();
    if (mounted) setState(() => _savingSettings = false);
  }

  Future<void> _resetSettings() async {
    setState(() => _savingSettings = true);
    await widget.config.resetToDefaults();
    _loadSettings();
    await widget.runtime.reloadAnalysisSettings();
    if (mounted) setState(() => _savingSettings = false);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<ServerRuntimeState>(
      stream: widget.runtime.states,
      initialData: widget.runtime.currentState,
      builder: (context, snapshot) {
        final state = snapshot.data!;
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
            activeColor: MimiCamDesignTokens.pink,
            dark: true,
            onTap: _selectTab,
          ),
        );
      },
    );
  }

  void _selectTab(int index) {
    final leavingPairingTab = _tab == 1 && index != 1;
    setState(() => _tab = index);
    if (leavingPairingTab) {
      widget.runtime.stopPairingMode();
    }
    if (index == 1) {
      widget.runtime.startPairingMode();
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
            _ServerHeroCard(
              state: state,
              phaseLabel: _phaseLabel(strings, state.phase),
              onStop: widget.runtime.stop,
            ),
            const SizedBox(height: 16),
            _LivePreviewCard(
              state: state,
              previewSource: widget.runtime.previewSource,
            ),
            const SizedBox(height: 16),
            _RuntimeStats(state: state),
            const SizedBox(height: 16),
            _DetectionCard(state: state),
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
              onReset: _resetSettings,
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

class _ServerHeroCard extends StatelessWidget {
  const _ServerHeroCard({
    required this.state,
    required this.phaseLabel,
    required this.onStop,
  });

  final ServerRuntimeState state;
  final String phaseLabel;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: const BoxDecoration(
                  color: MimiCamDesignTokens.pink,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.child_care_rounded,
                  color: MimiCamDesignTokens.navy,
                  size: 31,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      strings.ui('babyRoomMode'),
                      style: const TextStyle(
                        color: MimiCamDesignTokens.mint,
                        fontSize: 10.5,
                        letterSpacing: 1.0,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      strings.ui('roomStreamReady'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        height: 1.08,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      state.errorMessage ?? strings.ui('serverHeroReadyText'),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 15,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _ServerPill(
                label: phaseLabel,
                color: state.phase == ServerRuntimePhase.error
                    ? MimiCamDesignTokens.amber
                    : MimiCamDesignTokens.mint,
              ),
              _ServerPill(
                label: state.cameraActive
                    ? strings.ui('cameraOpen')
                    : strings.ui('cameraWaiting'),
                color: state.cameraActive
                    ? MimiCamDesignTokens.mint
                    : MimiCamDesignTokens.amber,
              ),
              _ServerPill(
                label: strings
                    .uiFormat('parentsCount', {'count': state.activeClients}),
                color: MimiCamDesignTokens.pink,
              ),
              _ServerPill(
                label:
                    state.mediaProfile?.label ?? strings.ui('qualityMeasuring'),
                color: MimiCamDesignTokens.amber,
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: OutlinedButton.icon(
              onPressed: onStop,
              icon: const Icon(Icons.stop_circle_rounded),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white38),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              label: Text(
                strings.ui('stopRoomStream'),
                style:
                    const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
              ),
            ),
          ),
        ],
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
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 14.5,
            height: 1.25,
          ),
        ),
      ],
    );
  }
}

class _ServerPill extends StatelessWidget {
  const _ServerPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: ShapeDecoration(color: color, shape: const StadiumBorder()),
      child: Text(
        label,
        style: const TextStyle(
          color: MimiCamDesignTokens.navy,
          fontSize: 12.5,
          fontWeight: FontWeight.w900,
        ),
      ),
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
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  )),
              const SizedBox(height: 6),
              Text(
                strings.ui('parentQrScanText'),
                style: const TextStyle(color: Colors.white70, fontSize: 14.5),
              ),
              if (!isCompact) ...[
                const SizedBox(height: 12),
                _PayloadBox(payload: payload),
                const SizedBox(height: 12),
              ] else
                const SizedBox(height: 8),
              Text(
                strings.ui('keepCodeVisible'),
                style: const TextStyle(color: Colors.white70, fontSize: 14.5),
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
        color: const Color(0xFFF2F0F8),
        borderRadius: BorderRadius.circular(14),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SelectableText(
          payload,
          maxLines: 1,
          style: const TextStyle(
            color: MimiCamDesignTokens.navy,
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
          eyeStyle: const QrEyeStyle(color: MimiCamDesignTokens.navy),
          dataModuleStyle:
              const QrDataModuleStyle(color: MimiCamDesignTokens.navy),
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
                backgroundColor: MimiCamDesignTokens.pink,
                foregroundColor: Colors.white,
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
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white24),
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
            ? MimiCamDesignTokens.mint
            : MimiCamDesignTokens.amber,
      ),
      _ServiceStatusCard(
        icon: Icons.mic_rounded,
        title: strings.ui('microphone'),
        value:
            state.microphoneActive ? strings.ui('active') : strings.ui('off'),
        color: state.microphoneActive
            ? MimiCamDesignTokens.mint
            : MimiCamDesignTokens.amber,
      ),
      _ServiceStatusCard(
        icon: Icons.hub_rounded,
        title: 'WebSocket',
        value: strings
            .uiFormat('eventClientsCount', {'count': state.activeEventClients}),
        color: MimiCamDesignTokens.pink,
      ),
      _ServiceStatusCard(
        icon: Icons.people_alt_rounded,
        title: strings.ui('clientCount'),
        value:
            strings.uiFormat('connectedCount', {'count': state.activeClients}),
        color: MimiCamDesignTokens.amber,
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
            child: Icon(icon, color: MimiCamDesignTokens.navy),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white70,
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

class _RuntimeStats extends StatelessWidget {
  const _RuntimeStats({required this.state});

  final ServerRuntimeState state;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final profile = state.mediaProfile;
    final stats = [
      _Stat(
          label: strings.ui('viewers'),
          value: state.activeClients == 0 ? '0' : '${state.activeClients}',
          footnote: strings.ui('connection'),
          color: MimiCamDesignTokens.mint),
      _Stat(
          label: 'FPS',
          value: profile == null ? '12' : '${profile.targetFps}',
          footnote: 'fps',
          color: MimiCamDesignTokens.pink),
      _Stat(
          label: strings.ui('resolution'),
          value: profile == null
              ? '640x480'
              : '${profile.width}x${profile.height}',
          footnote: profile?.label ?? strings.ui('automatic'),
          color: MimiCamDesignTokens.amber),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        return Row(
          children: [
            for (final stat in stats) ...[
              Expanded(child: stat),
              if (stat != stats.last) const SizedBox(width: 10),
            ],
          ],
        );
      },
    );
  }
}

class _DetectionCard extends StatelessWidget {
  const _DetectionCard({required this.state});

  final ServerRuntimeState state;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return MimiCamCard(
      dark: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            strings.ui('detectionStatus'),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            strings.ui('smartAlertsSubtitle'),
            style: const TextStyle(color: Colors.white70, fontSize: 14.5),
          ),
          const SizedBox(height: 14),
          _KeyVal(strings.ui('cryTracking'),
              state.cryAnalyzerActive ? strings.ui('ready') : strings.ui('off'),
              dark: true),
          const SizedBox(height: 10),
          _KeyVal(
              strings.ui('motionTracking'),
              state.motionAnalyzerActive
                  ? strings.ui('ready')
                  : strings.ui('off'),
              dark: true),
          const SizedBox(height: 10),
          _KeyVal(strings.ui('operatingMode'),
              _powerModeLabel(strings, state.powerMode.name),
              dark: true),
          const SizedBox(height: 10),
          _KeyVal(
            strings.ui('streamProfile'),
            state.mediaProfile?.summary ?? strings.ui('autoMeasuring'),
            dark: true,
          ),
        ],
      ),
    );
  }

  static String _powerModeLabel(AppStrings strings, String value) {
    return switch (value) {
      'liveWatch' => strings.ui('liveWatching'),
      'notificationArmed' => strings.ui('notificationTracking'),
      _ => strings.ui('roomReady'),
    };
  }
}

class _LivePreviewCard extends StatelessWidget {
  const _LivePreviewCard({required this.state, required this.previewSource});

  final ServerRuntimeState state;
  final Object? previewSource;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final controller = previewSource is CameraController
        ? previewSource as CameraController
        : null;
    final showCamera = state.cameraActive &&
        controller != null &&
        controller.value.isInitialized;

    return MimiCamCard(
      dark: true,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < 420;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    strings.ui('roomCamera'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 19,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  _PreviewStatusChip(
                    label: showCamera
                        ? strings.ui('livePreview')
                        : strings.ui('cameraStarting'),
                    color: showCamera
                        ? MimiCamDesignTokens.mint
                        : MimiCamDesignTokens.amber,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: isCompact ? 190 : 240),
                child: AspectRatio(
                  aspectRatio:
                      showCamera ? controller.value.aspectRatio : 16 / 9,
                  child: RepaintBoundary(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: ColoredBox(
                        color: Colors.black,
                        child: showCamera
                            ? FittedBox(
                                fit: BoxFit.cover,
                                child: SizedBox(
                                  width: controller.value.previewSize?.height ??
                                      constraints.maxWidth,
                                  height: controller.value.previewSize?.width ??
                                      constraints.maxWidth / 1.6,
                                  child: CameraPreview(controller),
                                ),
                              )
                            : const _PreviewWaitingContent(),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                showCamera
                    ? strings.ui('cameraRoomCheckText')
                    : strings.ui('cameraPermissionPreviewText'),
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
            ],
          );
        },
      ),
    );
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
          color: MimiCamDesignTokens.navy,
          fontWeight: FontWeight.w900,
          fontSize: 12.5,
        ),
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
          const Icon(Icons.videocam_off_rounded,
              color: Colors.white54, size: 34),
          const SizedBox(height: 8),
          Text(
            strings.ui('cameraPreparing'),
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _ServerSettingsCard extends StatelessWidget {
  const _ServerSettingsCard({
    required this.motionThreshold,
    required this.cryScoreThreshold,
    required this.notifyCooldownSeconds,
    required this.motionDurationSeconds,
    required this.cryDurationSeconds,
    required this.saving,
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(strings.ui('silentSafeDetection'),
                  style: MimiCamDesignTokens.cardTitle),
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
              color: MimiCamDesignTokens.slate,
              fontSize: 14.5,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 14),
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
          const SizedBox(height: 2),
          _KeyVal(strings.ui('localNotification'),
              strings.ui('sentToClientDevice')),
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
        color: MimiCamDesignTokens.mint,
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
        color: MimiCamDesignTokens.amber,
        onChanged: onMotionThresholdChanged,
        onChangeEnd: onMotionThresholdChangeEnd,
      ),
      _SettingSliderSpec(
        title: strings.ui('notificationCooldown'),
        description: strings.ui('notificationCooldownDescription'),
        valueLabel: '${notifyCooldownSeconds.round()} sn',
        value: notifyCooldownSeconds,
        min: 10,
        max: 180,
        divisions: 34,
        color: MimiCamDesignTokens.pink,
        onChanged: onNotifyCooldownChanged,
        onChangeEnd: onNotifyCooldownChangeEnd,
      ),
      _SettingSliderSpec(
        title: strings.ui('cryMinimumDuration'),
        description: strings.ui('cryMinimumDurationDescription'),
        valueLabel: '${cryDurationSeconds.toStringAsFixed(1)} sn',
        value: cryDurationSeconds,
        min: .5,
        max: 6,
        divisions: 11,
        color: MimiCamDesignTokens.mint,
        onChanged: onCryDurationChanged,
        onChangeEnd: onCryDurationChangeEnd,
      ),
      _SettingSliderSpec(
        title: strings.ui('motionMinimumDuration'),
        description: strings.ui('motionMinimumDurationDescription'),
        valueLabel: '${motionDurationSeconds.toStringAsFixed(1)} sn',
        value: motionDurationSeconds,
        min: .5,
        max: 6,
        divisions: 11,
        color: MimiCamDesignTokens.amber,
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
        color:
            saving ? MimiCamDesignTokens.amber : MimiCamDesignTokens.mintSoft,
        shape: const StadiumBorder(),
      ),
      child: Text(
        saving ? strings.ui('saving') : strings.ui('realSettings'),
        style: const TextStyle(
          color: MimiCamDesignTokens.navy,
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
                  color: MimiCamDesignTokens.navy,
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
            color: MimiCamDesignTokens.slate,
            fontSize: 13.5,
            height: 1.25,
          ),
        ),
        Slider(
          activeColor: color,
          inactiveColor: const Color(0xFFE9EDF4),
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

class _Stat extends StatelessWidget {
  const _Stat({
    required this.label,
    required this.value,
    required this.footnote,
    required this.color,
  });

  final String label;
  final String value;
  final String footnote;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 104,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: MimiCamDesignTokens.plumSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: .12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(label,
              style: const TextStyle(color: Colors.white70, fontSize: 12)),
          const Spacer(),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            footnote,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
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
              color: dark ? Colors.white70 : MimiCamDesignTokens.slate,
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
              color: dark ? Colors.white : MimiCamDesignTokens.slate,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    );
  }
}
