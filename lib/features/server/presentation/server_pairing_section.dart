import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../l10n/app_strings.dart';
import '../../shared/presentation/miucam_design_tokens.dart';
import '../../shared/presentation/miucam_shells.dart';
import '../server_runtime.dart';
import 'server_home_components.dart';

class ServerPairingSection extends StatefulWidget {
  const ServerPairingSection({
    super.key,
    required this.runtime,
    required this.state,
  });

  final ServerRuntime runtime;
  final ServerRuntimeState state;

  @override
  State<ServerPairingSection> createState() => _ServerPairingSectionState();
}

class _ServerPairingSectionState extends State<ServerPairingSection> {
  bool _refreshing = false;

  Future<bool> _refreshPairingTicket() async {
    if (_refreshing || !mounted) return false;
    setState(() => _refreshing = true);
    try {
      await widget.runtime.startPairingMode();
      final state = widget.runtime.currentState;
      return state.qrPayload?.isNotEmpty == true && state.errorMessage == null;
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final payload = widget.state.qrPayload;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ServerSectionHeader(
          title: strings.ui('qrIpTicketTitle'),
          subtitle: strings.ui('qrIpTicketSubtitle'),
        ),
        const SizedBox(height: 10),
        _ConnectionCard(
          qrPayload: payload,
          loading: _refreshing,
          failed: payload == null && widget.state.errorMessage != null,
        ),
        const SizedBox(height: 10),
        _QrIpActions(
          payload: payload,
          refreshing: _refreshing,
          onRefresh: _refreshPairingTicket,
        ),
      ],
    );
  }
}

class _ConnectionCard extends StatelessWidget {
  const _ConnectionCard({
    required this.qrPayload,
    required this.loading,
    required this.failed,
  });

  final String? qrPayload;
  final bool loading;
  final bool failed;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return MiuCamCard(
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
          final qr = qrPayload != null
              ? _QrPanel(payload: qrPayload!, size: qrSize)
              : _QrPlaceholder(
                  size: qrSize,
                  loading: loading || !failed,
                );
          final details = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                strings.ui('secureQrPairing'),
                style: const TextStyle(
                  color: MiuCamDesignTokens.serverText,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                strings.ui('parentQrScanText'),
                style: const TextStyle(
                  color: MiuCamDesignTokens.serverTextMuted,
                  fontSize: 14.5,
                ),
              ),
              if (!isCompact) ...[
                const SizedBox(height: 12),
                if (qrPayload case final payload?)
                  _PayloadBox(payload: payload),
                const SizedBox(height: 12),
              ] else
                const SizedBox(height: 8),
              if (qrPayload != null)
                Text(
                  strings.ui('keepCodeVisible'),
                  style: const TextStyle(
                    color: MiuCamDesignTokens.serverTextMuted,
                    fontSize: 14.5,
                  ),
                ),
            ],
          );

          if (isCompact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(child: qr),
                const SizedBox(height: 16),
                details,
              ],
            );
          }

          return Row(
            children: [
              Expanded(child: details),
              const SizedBox(width: 20),
              qr,
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

class _QrPlaceholder extends StatelessWidget {
  const _QrPlaceholder({required this.size, required this.loading});

  final double size;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Container(
      key: const ValueKey('server-qr-placeholder'),
      width: size + _QrPanel.outerPadding * 2,
      height: size + _QrPanel.outerPadding * 2,
      decoration: BoxDecoration(
        color: MiuCamDesignTokens.serverSurfaceRaised,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: MiuCamDesignTokens.serverOutline),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (loading)
                const SizedBox.square(
                  dimension: 34,
                  child: CircularProgressIndicator(strokeWidth: 3),
                )
              else
                const Icon(
                  Icons.qr_code_2_rounded,
                  color: MiuCamDesignTokens.serverError,
                  size: 42,
                ),
              const SizedBox(height: 14),
              Text(
                strings.ui(
                  loading ? 'qrTicketPreparing' : 'qrTicketUnavailable',
                ),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: MiuCamDesignTokens.serverText,
                  fontSize: 14,
                  height: 1.3,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
        color: MiuCamDesignTokens.serverIce,
        borderRadius: BorderRadius.circular(14),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SelectableText(
          payload,
          maxLines: 1,
          style: const TextStyle(
            color: MiuCamDesignTokens.serverText,
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
          eyeStyle: const QrEyeStyle(color: MiuCamDesignTokens.serverText),
          dataModuleStyle:
              const QrDataModuleStyle(color: MiuCamDesignTokens.serverText),
        ),
      ),
    );
  }
}

class _QrIpActions extends StatelessWidget {
  const _QrIpActions({
    required this.payload,
    required this.refreshing,
    required this.onRefresh,
  });

  final String? payload;
  final bool refreshing;
  final Future<bool> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return MiuCamCard(
      dark: true,
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          SizedBox(
            height: 48,
            child: FilledButton.icon(
              onPressed: refreshing
                  ? null
                  : () async {
                      final refreshed = await onRefresh();
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context)
                        ..clearSnackBars()
                        ..showSnackBar(
                          SnackBar(
                            content: Text(
                              strings.ui(
                                refreshed
                                    ? 'qrTicketRefreshed'
                                    : 'qrTicketRefreshFailed',
                              ),
                            ),
                          ),
                        );
                    },
              icon: refreshing
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: MiuCamDesignTokens.serverOnAccent,
                      ),
                    )
                  : const Icon(Icons.refresh_rounded),
              style: FilledButton.styleFrom(
                backgroundColor: MiuCamDesignTokens.serverCyan,
                foregroundColor: MiuCamDesignTokens.serverOnAccent,
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
              onPressed: payload == null || refreshing
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
                foregroundColor: MiuCamDesignTokens.serverText,
                side: const BorderSide(
                  color: MiuCamDesignTokens.serverOutline,
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
