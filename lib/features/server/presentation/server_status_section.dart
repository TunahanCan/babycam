import 'package:flutter/material.dart';

import '../../../l10n/app_strings.dart';
import '../../shared/presentation/media_profile_text.dart';
import '../../shared/presentation/miucam_design_tokens.dart';
import '../../shared/presentation/miucam_shells.dart';
import '../server_runtime.dart';
import 'server_home_components.dart';

class ServerLiveStatusCard extends StatelessWidget {
  const ServerLiveStatusCard({
    super.key,
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
    final connectedParents = connectedParentCount(state);
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
        ? MiuCamDesignTokens.serverError
        : stopped
            ? MiuCamDesignTokens.serverDisabled
            : preparing
                ? MiuCamDesignTokens.serverBlue
                : MiuCamDesignTokens.serverSuccess;

    return Container(
      key: const ValueKey('server-live-status-card'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: MiuCamDesignTokens.serverPanel,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: accent.withValues(alpha: .38)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1424493D),
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _StatusHeadline(
            title: title,
            summary: summary,
            accent: accent,
            stopped: stopped,
            failed: failed,
            preparing: preparing,
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
                      style: _primaryButtonStyle(),
                      label: Text(strings.ui('tryAgain')),
                    )
                  : stopped
                      ? FilledButton.icon(
                          onPressed: onRestart,
                          icon: const Icon(Icons.restart_alt_rounded),
                          style: _primaryButtonStyle(),
                          label: Text(strings.ui('restartRoomStream')),
                        )
                      : FilledButton.icon(
                          onPressed: onConnectParent,
                          icon: const Icon(Icons.qr_code_2_rounded),
                          style: _primaryButtonStyle(),
                          label: Text(strings.ui('connectParentDevice')),
                        ),
            ),
          ],
          const SizedBox(height: 14),
          _ServerHealthStrip(state: state, stopped: stopped, failed: failed),
          if (!failed && !stopped && connectedParents > 0) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton.icon(
                onPressed: onConnectParent,
                icon: const Icon(Icons.add_link_rounded),
                style: OutlinedButton.styleFrom(
                  foregroundColor: MiuCamDesignTokens.serverText,
                  side: const BorderSide(
                    color: MiuCamDesignTokens.serverOutline,
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

  ButtonStyle _primaryButtonStyle() => FilledButton.styleFrom(
        backgroundColor: MiuCamDesignTokens.serverCyan,
        foregroundColor: MiuCamDesignTokens.serverOnAccent,
      );
}

class _StatusHeadline extends StatelessWidget {
  const _StatusHeadline({
    required this.title,
    required this.summary,
    required this.accent,
    required this.stopped,
    required this.failed,
    required this.preparing,
  });

  final String title;
  final String summary;
  final Color accent;
  final bool stopped;
  final bool failed;
  final bool preparing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
          child: Icon(
            failed
                ? Icons.error_outline_rounded
                : stopped
                    ? Icons.stop_rounded
                    : preparing
                        ? Icons.hourglass_top_rounded
                        : Icons.sensors_rounded,
            color: MiuCamDesignTokens.serverOnAccent,
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
                  color: MiuCamDesignTokens.serverText,
                  fontSize: 20,
                  height: 1.1,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                summary,
                style: const TextStyle(
                  color: MiuCamDesignTokens.serverTextMuted,
                  fontSize: 13.5,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ServerHealthStrip extends StatelessWidget {
  const _ServerHealthStrip({
    required this.state,
    required this.stopped,
    required this.failed,
  });

  final ServerRuntimeState state;
  final bool stopped;
  final bool failed;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final cameraPreparing = state.phase == ServerRuntimePhase.mediaStarting;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: BoxDecoration(
        color: MiuCamDesignTokens.serverSurfaceRaised,
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
                      : cameraPreparing
                          ? strings.ui('preparing')
                          : strings.ui('waiting'),
              color: state.cameraActive
                  ? MiuCamDesignTokens.serverSuccess
                  : stopped || failed
                      ? MiuCamDesignTokens.serverDisabled
                      : cameraPreparing
                          ? MiuCamDesignTokens.serverBlue
                          : MiuCamDesignTokens.serverDisabled,
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
                  ? MiuCamDesignTokens.serverSuccess
                  : stopped || failed
                      ? MiuCamDesignTokens.serverDisabled
                      : MiuCamDesignTokens.serverBlue,
            ),
          ),
          const _ServerHealthDivider(),
          Expanded(
            child: _ServerHealthIndicator(
              icon: Icons.notifications_active_rounded,
              label: strings.ui('alertsShort'),
              value: _alertValue(strings),
              color: _alertColor(),
            ),
          ),
        ],
      ),
    );
  }

  String _alertValue(AppStrings strings) {
    if (state.cryAnalyzerActive && state.motionAnalyzerActive) {
      return strings.ui('active');
    }
    if (state.cryAnalyzerActive || state.motionAnalyzerActive) {
      return strings.ui('partlyActive');
    }
    return strings.ui(stopped || failed ? 'off' : 'waiting');
  }

  Color _alertColor() {
    if (state.cryAnalyzerActive && state.motionAnalyzerActive) {
      return MiuCamDesignTokens.serverSuccess;
    }
    if (state.cryAnalyzerActive || state.motionAnalyzerActive) {
      return MiuCamDesignTokens.serverWarning;
    }
    return stopped || failed
        ? MiuCamDesignTokens.serverDisabled
        : MiuCamDesignTokens.serverBlue;
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
              color: MiuCamDesignTokens.serverTextMuted,
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
      color: MiuCamDesignTokens.serverOutline.withValues(alpha: .55),
    );
  }
}

class ServerSafeRoomSetupCard extends StatelessWidget {
  const ServerSafeRoomSetupCard({super.key});

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return MiuCamCard(
      key: const ValueKey('server-safe-room-setup'),
      dark: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const CircleAvatar(
                backgroundColor: MiuCamDesignTokens.serverCyan,
                child: Icon(
                  Icons.health_and_safety_rounded,
                  color: MiuCamDesignTokens.serverOnAccent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  strings.ui('safeRoomSetupTitle'),
                  style: const TextStyle(
                    color: MiuCamDesignTokens.serverText,
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
              color: MiuCamDesignTokens.serverTextMuted,
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
            color: MiuCamDesignTokens.serverCyan,
            size: 19,
          ),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: MiuCamDesignTokens.serverTextMuted,
              fontSize: 13.5,
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }
}

class ServerStreamDetailsCard extends StatelessWidget {
  const ServerStreamDetailsCard({
    super.key,
    required this.state,
    required this.phaseLabel,
  });

  final ServerRuntimeState state;
  final String phaseLabel;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final profile = state.mediaProfile;
    return MiuCamCard(
      key: const ValueKey('server-stream-details'),
      dark: true,
      child: Material(
        color: Colors.transparent,
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(top: 8),
            iconColor: MiuCamDesignTokens.serverCyan,
            collapsedIconColor: MiuCamDesignTokens.serverTextMuted,
            leading: const Icon(
              Icons.tune_rounded,
              color: MiuCamDesignTokens.serverCyan,
            ),
            title: Text(
              strings.ui('streamDetails'),
              style: const TextStyle(
                color: MiuCamDesignTokens.serverText,
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
            subtitle: Text(
              strings.ui('streamDetailsSubtitle'),
              style: const TextStyle(
                color: MiuCamDesignTokens.serverTextMuted,
                fontSize: 12.5,
              ),
            ),
            children: [
              ServerKeyValue(strings.ui('connection'), phaseLabel),
              const SizedBox(height: 10),
              ServerKeyValue(
                strings.ui('parent'),
                strings.uiFormat(
                  'parentsCount',
                  {'count': connectedParentCount(state)},
                ),
              ),
              const SizedBox(height: 10),
              ServerKeyValue(
                strings.ui('streamProfile'),
                profile == null
                    ? strings.ui('autoMeasuring')
                    : localizedMediaProfileSummary(strings, profile),
              ),
              const SizedBox(height: 10),
              ServerKeyValue(
                strings.ui('cryTracking'),
                state.cryAnalyzerActive
                    ? strings.ui('active')
                    : strings.ui('waiting'),
              ),
              const SizedBox(height: 10),
              ServerKeyValue(
                strings.ui('motionTracking'),
                state.motionAnalyzerActive
                    ? strings.ui('active')
                    : strings.ui('waiting'),
              ),
              if (state.errorMessage case final error?) ...[
                const SizedBox(height: 10),
                ServerKeyValue(strings.ui('technicalError'), error),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class ServerStopRoomStreamButton extends StatelessWidget {
  const ServerStopRoomStreamButton({
    super.key,
    required this.onPressed,
  });

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Align(
      child: TextButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.stop_circle_outlined, size: 20),
        style: TextButton.styleFrom(
          foregroundColor: MiuCamDesignTokens.serverTextMuted,
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
