import 'dart:async';

import 'package:flutter/material.dart';

import '../../../l10n/app_strings.dart';
import '../../../services/platform/platform_runtime_contract.dart';
import '../../shared/presentation/miucam_design_tokens.dart';
import '../../shared/presentation/miucam_shells.dart';
import '../server_runtime.dart';
import 'server_home_components.dart';

class ServerServicesSection extends StatelessWidget {
  const ServerServicesSection({super.key, required this.state});

  final ServerRuntimeState state;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ServerSectionHeader(
          title: strings.ui('serviceStatus'),
          subtitle: strings.ui('serviceStatusSubtitle'),
        ),
        const SizedBox(height: 10),
        _ServiceStatusGrid(state: state),
        const SizedBox(height: 12),
        const _PlatformRuntimeContractCard(),
      ],
    );
  }
}

class _ServiceStatusGrid extends StatelessWidget {
  const _ServiceStatusGrid({required this.state});

  final ServerRuntimeState state;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final inactive = state.phase == ServerRuntimePhase.stopped ||
        state.phase == ServerRuntimePhase.error;
    final cards = [
      _ServiceStatusCard(
        icon: Icons.videocam_rounded,
        title: strings.ui('camera'),
        value: state.cameraActive
            ? strings.ui('active')
            : inactive
                ? strings.ui('off')
                : state.phase == ServerRuntimePhase.mediaStarting
                    ? strings.ui('preparing')
                    : strings.ui('waiting'),
        color: state.cameraActive
            ? MiuCamDesignTokens.serverSuccess
            : inactive
                ? MiuCamDesignTokens.serverDisabled
                : state.phase == ServerRuntimePhase.mediaStarting
                    ? MiuCamDesignTokens.serverBlue
                    : MiuCamDesignTokens.serverDisabled,
      ),
      _ServiceStatusCard(
        icon: Icons.mic_rounded,
        title: strings.ui('microphone'),
        value:
            state.microphoneActive ? strings.ui('active') : strings.ui('off'),
        color: state.microphoneActive
            ? MiuCamDesignTokens.serverSuccess
            : MiuCamDesignTokens.serverDisabled,
      ),
      _ServiceStatusCard(
        icon: Icons.hub_rounded,
        title: 'WebSocket',
        value: strings
            .uiFormat('eventClientsCount', {'count': state.activeEventClients}),
        color: state.activeEventClients > 0
            ? MiuCamDesignTokens.serverSuccess
            : MiuCamDesignTokens.serverBlue,
      ),
      _ServiceStatusCard(
        icon: Icons.people_alt_rounded,
        title: strings.ui('clientCount'),
        value:
            strings.uiFormat('connectedCount', {'count': state.activeClients}),
        color: state.activeClients > 0
            ? MiuCamDesignTokens.serverSuccess
            : MiuCamDesignTokens.serverDisabled,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 520) {
          return Column(
            children: [
              for (var index = 0; index < cards.length; index++) ...[
                cards[index],
                if (index < cards.length - 1) const SizedBox(height: 10),
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

/// Owns its polling lifecycle so the two-second platform refresh only rebuilds
/// this card, not the server navigation or the live camera tree.
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
  bool _refreshInFlight = false;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
    // ServerRuntime is the sole native EventChannel owner. This read-only
    // method-channel snapshot avoids replacing its event sink on iOS/Android.
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => unawaited(_refresh()),
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
    return MiuCamCard(
      dark: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            backgroundColor: active
                ? MiuCamDesignTokens.serverSuccess
                : MiuCamDesignTokens.serverDisabled,
            child: Icon(
              platform == PlatformRuntimeKind.ios
                  ? Icons.phone_iphone_rounded
                  : Icons.settings_applications_rounded,
              color: MiuCamDesignTokens.serverOnAccent,
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
                    color: MiuCamDesignTokens.serverText,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  message,
                  style: const TextStyle(
                    color: MiuCamDesignTokens.serverTextMuted,
                    fontSize: 13.5,
                    height: 1.3,
                  ),
                ),
                if (snapshot?.backgroundRecoveryAfterProcessDeath == false) ...[
                  const SizedBox(height: 6),
                  Text(
                    strings.ui('processRecoveryForegroundContract'),
                    style: const TextStyle(
                      color: MiuCamDesignTokens.serverWarning,
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

  Future<void> _refresh() async {
    if (_refreshInFlight) return;
    _refreshInFlight = true;
    try {
      final snapshot = await _contract.snapshot();
      if (mounted) setState(() => _snapshot = snapshot);
    } catch (_) {
      // Keep the last known snapshot. The next poll retries without creating
      // overlapping method-channel calls or disturbing the server runtime.
    } finally {
      _refreshInFlight = false;
    }
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
      decoration: MiuCamDesignTokens.cardDecoration(dark: true),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: color,
            child: Icon(icon, color: MiuCamDesignTokens.serverOnAccent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: MiuCamDesignTokens.serverText,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    color: MiuCamDesignTokens.serverTextMuted,
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
