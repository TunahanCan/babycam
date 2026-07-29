import 'dart:async';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../../l10n/app_strings.dart';
import '../../../services/monetization/broadcast_access_service.dart';
import '../../shared/presentation/miucam_design_tokens.dart';
import '../../shared/presentation/miucam_shells.dart';
import '../media/server_media_source.dart';
import '../server_runtime.dart';

class ServerLivePreviewCard extends StatelessWidget {
  const ServerLivePreviewCard({
    super.key,
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

    return MiuCamCard(
      key: const ValueKey('server-live-preview-card'),
      dark: true,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < 420;
          final stackHeader = constraints.maxWidth < 240 ||
              MediaQuery.textScalerOf(context).scale(16) > 20;
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
              _PreviewTitle(strings: strings),
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
                              color: MiuCamDesignTokens.serverSuccess,
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
                  color: MiuCamDesignTokens.serverTextMuted,
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

class _PreviewTitle extends StatelessWidget {
  const _PreviewTitle({required this.strings});

  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(
          Icons.videocam_rounded,
          color: MiuCamDesignTokens.serverCyan,
          size: 22,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            strings.ui('roomCamera'),
            style: const TextStyle(
              color: MiuCamDesignTokens.serverText,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
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
        : strings.ui(active ? 'turnOffLocalPreview' : 'turnOnLocalPreview');
    final label = strings
        .ui(active ? 'hideLocalPreviewAction' : 'showLocalPreviewAction');
    final icon = busy
        ? SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2.2,
              color: active
                  ? MiuCamDesignTokens.serverCyan
                  : MiuCamDesignTokens.serverOnAccent,
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
                MiuCamDesignTokens.serverSurfaceRaised.withValues(alpha: .94),
              ),
              foregroundColor: const WidgetStatePropertyAll(
                MiuCamDesignTokens.serverCyan,
              ),
              side: WidgetStatePropertyAll(
                BorderSide(
                  color: enabled
                      ? MiuCamDesignTokens.serverCyan
                      : MiuCamDesignTokens.serverDisabled,
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
                    ? MiuCamDesignTokens.serverDisabled
                    : MiuCamDesignTokens.serverCyan,
              ),
              foregroundColor: const WidgetStatePropertyAll(
                MiuCamDesignTokens.serverOnAccent,
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

/// Encapsulates purchase-side effects so purchase progress never rebuilds the
/// live camera surface or bottom navigation.
class ServerBroadcastAccessCard extends StatefulWidget {
  const ServerBroadcastAccessCard({
    super.key,
    required this.snapshot,
    required this.runtime,
    required this.onUnlocked,
  });

  final BroadcastAccessSnapshot snapshot;
  final ServerRuntime runtime;
  final VoidCallback onUnlocked;

  @override
  State<ServerBroadcastAccessCard> createState() =>
      _ServerBroadcastAccessCardState();
}

class _ServerBroadcastAccessCardState extends State<ServerBroadcastAccessCard> {
  bool _busy = false;

  Future<void> _runPurchase({required bool restore}) async {
    if (_busy) return;
    setState(() => _busy = true);
    final strings = AppStrings.of(context);
    try {
      if (restore) {
        await widget.runtime.restoreBroadcastAccessPurchase();
      } else {
        await widget.runtime.unlockBroadcastAccess();
      }
      if (!mounted) return;
      _showMessage(strings.ui('broadcastAccessUnlocked'));
      widget.onUnlocked();
    } catch (error) {
      if (mounted) _showMessage(_purchaseMessage(strings, error));
    } finally {
      if (mounted) setState(() => _busy = false);
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
    final strings = AppStrings.of(context);
    final snapshot = widget.snapshot;
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
                'remaining': _remainingText(strings, snapshot.remaining),
                'price': snapshot.priceLabel,
              });
    return MiuCamCard(
      dark: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: unlocked
                    ? MiuCamDesignTokens.serverSuccess
                    : locked
                        ? MiuCamDesignTokens.serverWarning
                        : MiuCamDesignTokens.serverBlue,
                child: Icon(
                  unlocked
                      ? Icons.verified_rounded
                      : locked
                          ? Icons.lock_rounded
                          : Icons.hourglass_bottom_rounded,
                  color: MiuCamDesignTokens.serverOnAccent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: MiuCamDesignTokens.serverText,
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
              color: MiuCamDesignTokens.serverTextMuted,
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
                    MiuCamDesignTokens.serverOutline.withValues(alpha: .46),
                valueColor: AlwaysStoppedAnimation<Color>(
                  locked
                      ? MiuCamDesignTokens.serverWarning
                      : MiuCamDesignTokens.serverCyan,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  onPressed: _busy
                      ? null
                      : () => unawaited(_runPurchase(restore: false)),
                  icon: _busy
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.lock_open_rounded),
                  style: FilledButton.styleFrom(
                    backgroundColor: MiuCamDesignTokens.serverCyan,
                    foregroundColor: MiuCamDesignTokens.serverOnAccent,
                  ),
                  label: Text(
                    strings.uiFormat('unlockLifetimePrice', {
                      'price': snapshot.priceLabel,
                    }),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _busy
                      ? null
                      : () => unawaited(_runPurchase(restore: true)),
                  icon: const Icon(Icons.restore_rounded),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: MiuCamDesignTokens.serverText,
                    side: const BorderSide(
                      color: MiuCamDesignTokens.serverOutline,
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

  static String _remainingText(AppStrings strings, Duration duration) {
    final totalMinutes = duration.inMinutes.clamp(0, 24 * 60);
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    if (hours == 0) {
      return strings.uiFormat('durationMinutesShort', {'minutes': minutes});
    }
    if (minutes == 0) {
      return strings.uiFormat('durationHoursShort', {'hours': hours});
    }
    return strings.uiFormat(
      'durationHoursMinutesShort',
      {'hours': hours, 'minutes': minutes},
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
      decoration: ShapeDecoration(color: color, shape: const StadiumBorder()),
      child: Text(
        label,
        style: const TextStyle(
          color: MiuCamDesignTokens.serverOnAccent,
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
        color: MiuCamDesignTokens.serverSurfaceRaised.withValues(alpha: .92),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 48,
            height: 48,
            child: Icon(
              icon,
              color: MiuCamDesignTokens.serverText,
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
            if (!localPreviewActive) return const _PreviewOffContent();
            if (!showCamera) return const _PreviewWaitingContent();
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
            final controller = previewSource is CameraController
                ? previewSource as CameraController
                : null;
            if (controller == null || !controller.value.isInitialized) {
              return const _PreviewWaitingContent();
            }
            return FittedBox(
              fit: fit,
              child: SizedBox(
                width: controller.value.previewSize?.height ??
                    constraints.maxWidth,
                height: controller.value.previewSize?.width ??
                    constraints.maxHeight,
                child: CameraPreview(controller),
              ),
            );
          },
        ),
      ),
    );
  }
}

class ServerFullscreenPreview extends StatelessWidget {
  const ServerFullscreenPreview({
    super.key,
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
                  ? MiuCamDesignTokens.serverSuccess
                  : state.localPreviewActive
                      ? MiuCamDesignTokens.serverBlue
                      : MiuCamDesignTokens.serverDisabled,
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
            color: Colors.white54,
            size: 36,
          ),
          const SizedBox(height: 8),
          Text(
            strings.ui('localPreviewOff'),
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
            color: Colors.white54,
            size: 34,
          ),
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
