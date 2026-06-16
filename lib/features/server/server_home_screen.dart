import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../services/configuration_service.dart';
import '../shared/presentation/mimicam_design_tokens.dart';
import '../shared/presentation/mimicam_shells.dart';
import 'server_runtime.dart';

class ServerHomeScreen extends StatefulWidget {
  const ServerHomeScreen({
    super.key,
    required this.runtime,
    required this.config,
    required this.onResetRole,
  });

  final ServerRuntime runtime;
  final ConfigurationService config;
  final VoidCallback onResetRole;

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

  @override
  void initState() {
    super.initState();
    _loadSettings();
    widget.runtime.startPairingMode();
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
              child: ListView(
                padding: MimiCamDesignTokens.screenPadding,
                children: [
                  MimiCamTopBar(onResetRole: widget.onResetRole, dark: true),
                  const SizedBox(height: 24),
                  _ServerHeroCard(
                    state: state,
                    phaseLabel: _phaseLabel(state.phase),
                    onStop: widget.runtime.stop,
                  ),
                  const SizedBox(height: 22),
                  _LivePreviewCard(
                    state: state,
                    previewSource: widget.runtime.previewSource,
                  ),
                  const SizedBox(height: 24),
                  const _ServerSectionHeader(
                    title: 'Ebeveyn cihazını bağla',
                    subtitle:
                        'QR kodu göster; eşleşme sadece aynı ağdaki güvenilir cihazlar için açılır.',
                  ),
                  const SizedBox(height: 14),
                  _ConnectionCard(qrPayload: state.qrPayload),
                  const SizedBox(height: 24),
                  _RuntimeStats(state: state),
                  const SizedBox(height: 24),
                  _DetectionCard(state: state),
                  const SizedBox(height: 24),
                  _ServerSettingsCard(
                    motionThreshold: _motionThreshold,
                    cryScoreThreshold: _cryScoreThreshold,
                    notifyCooldownSeconds: _notifyCooldownSeconds,
                    motionDurationSeconds: _motionDurationSeconds,
                    cryDurationSeconds: _cryDurationSeconds,
                    saving: _savingSettings,
                    telegramEnabled:
                        widget.config.telegramBotToken.isNotEmpty &&
                            widget.config.telegramChatId.isNotEmpty,
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
                        widget.config
                            .setNotifyCooldownMs((value * 1000).round())),
                    onMotionDurationChanged: (value) =>
                        setState(() => _motionDurationSeconds = value),
                    onMotionDurationChangeEnd: (value) => _persistSettings(() =>
                        widget.config
                            .setMotionMinDurationMs((value * 1000).round())),
                    onCryDurationChanged: (value) =>
                        setState(() => _cryDurationSeconds = value),
                    onCryDurationChangeEnd: (value) => _persistSettings(() =>
                        widget.config
                            .setCryMinDurationMs((value * 1000).round())),
                  ),
                  const SizedBox(height: 30),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  static String _phaseLabel(ServerRuntimePhase phase) {
    return switch (phase) {
      ServerRuntimePhase.stopped => 'Durdu',
      ServerRuntimePhase.pairingIdle => 'Eşleşme bekliyor',
      ServerRuntimePhase.pairingActive => 'Yayında',
      ServerRuntimePhase.clientPaired => 'Client bağlı',
      ServerRuntimePhase.mediaIdle => 'Medya beklemede',
      ServerRuntimePhase.mediaStarting => 'Medya başlıyor',
      ServerRuntimePhase.mediaActive => 'Medya aktif',
      ServerRuntimePhase.error => 'Hata',
    };
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
    return Container(
      padding: const EdgeInsets.all(26),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(36),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: const BoxDecoration(
                  color: MimiCamDesignTokens.pink,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.child_care_rounded,
                  color: MimiCamDesignTokens.navy,
                  size: 40,
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'BEBEK ODASI MODU',
                      style: TextStyle(
                        color: MimiCamDesignTokens.mint,
                        fontSize: 12,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Oda yayına hazır',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 34,
                        height: 1.02,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      state.errorMessage ??
                          'Kamera açık, eşleşme hazır. Telefonu sabit bir yere bırakabilirsin.',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 17,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
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
                label: state.cameraActive ? 'Kamera açık' : 'Kamera bekliyor',
                color: state.cameraActive
                    ? MimiCamDesignTokens.mint
                    : MimiCamDesignTokens.amber,
              ),
              _ServerPill(
                label: '${state.activeClients} ebeveyn',
                color: MimiCamDesignTokens.pink,
              ),
            ],
          ),
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: OutlinedButton.icon(
              onPressed: onStop,
              icon: const Icon(Icons.stop_circle_rounded),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white38),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(22),
                ),
              ),
              label: const Text(
                'Oda yayınını durdur',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
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
            fontSize: 26,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 17,
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
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
      decoration: ShapeDecoration(color: color, shape: const StadiumBorder()),
      child: Text(
        label,
        style: const TextStyle(
          color: MimiCamDesignTokens.navy,
          fontSize: 14,
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
    final payload = qrPayload ?? 'mimicam://pairing/pending';
    return MimiCamCard(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < 430;
          final details = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Güvenli QR eşleşme',
                  style: MimiCamDesignTokens.cardTitle),
              const SizedBox(height: 8),
              const Text(
                'Ebeveyn cihazında QR tara; bağlantı bilgisi otomatik aktarılır.',
                style:
                    TextStyle(color: MimiCamDesignTokens.slate, fontSize: 16),
              ),
              const SizedBox(height: 16),
              _PayloadBox(payload: payload),
              const SizedBox(height: 18),
              const Text(
                'Kod görünür kalsın; eşleşme bitince yayın izlenebilir.',
                style:
                    TextStyle(color: MimiCamDesignTokens.slate, fontSize: 18),
              ),
            ],
          );

          if (isCompact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(child: _QrPanel(payload: payload, size: 150)),
                const SizedBox(height: 22),
                details,
              ],
            );
          }

          return Row(
            children: [
              Expanded(child: details),
              const SizedBox(width: 28),
              _QrPanel(payload: payload, size: 140),
            ],
          );
        },
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
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F0F8),
        borderRadius: BorderRadius.circular(18),
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

  final String payload;
  final double size;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
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

class _RuntimeStats extends StatelessWidget {
  const _RuntimeStats({required this.state});

  final ServerRuntimeState state;

  @override
  Widget build(BuildContext context) {
    final stats = [
      _Stat(
          label: 'Ebeveyn',
          value: state.activeClients == 0
              ? 'Bekleniyor'
              : '${state.activeClients} bağlı',
          color: MimiCamDesignTokens.mint),
      _Stat(
          label: 'Kamera',
          value: state.cameraActive ? 'Açık' : 'Hazırlanıyor',
          color: MimiCamDesignTokens.pink),
      _Stat(
          label: 'Mikrofon',
          value: state.microphoneActive ? 'Dinliyor' : 'Kapalı',
          color: MimiCamDesignTokens.amber),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 430) {
          return Column(
            children: [
              for (final stat in stats) ...[
                stat,
                if (stat != stats.last) const SizedBox(height: 14),
              ],
            ],
          );
        }

        return Row(
          children: [
            for (final stat in stats) ...[
              Expanded(child: stat),
              if (stat != stats.last) const SizedBox(width: 14),
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
    return MimiCamCard(
      child: Opacity(
        opacity: .72,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Akıllı uyarılar', style: MimiCamDesignTokens.cardTitle),
            const SizedBox(height: 8),
            const Text(
              'Sadece önemli değişimleri sakin uyarılara dönüştürür.',
              style: TextStyle(color: MimiCamDesignTokens.slate, fontSize: 16),
            ),
            const SizedBox(height: 22),
            _KeyVal(
                'Ağlama takibi', state.cryAnalyzerActive ? 'Hazır' : 'Kapalı'),
            const SizedBox(height: 16),
            _KeyVal('Hareket takibi',
                state.motionAnalyzerActive ? 'Hazır' : 'Kapalı'),
            const SizedBox(height: 16),
            _KeyVal('Çalışma modu', _powerModeLabel(state.powerMode.name)),
          ],
        ),
      ),
    );
  }

  static String _powerModeLabel(String value) {
    return switch (value) {
      'liveWatch' => 'Canlı izleme',
      'notificationArmed' => 'Uyarı takibi',
      _ => 'Oda hazır',
    };
  }
}

class _LivePreviewCard extends StatelessWidget {
  const _LivePreviewCard({required this.state, required this.previewSource});

  final ServerRuntimeState state;
  final Object? previewSource;

  @override
  Widget build(BuildContext context) {
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
                  const Text(
                    'Oda kamerası',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 23,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  _PreviewStatusChip(
                    label: showCamera ? 'Canlı önizleme' : 'Kamera açılıyor',
                    color: showCamera
                        ? MimiCamDesignTokens.mint
                        : MimiCamDesignTokens.amber,
                  ),
                ],
              ),
              const SizedBox(height: 18),
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: isCompact ? 220 : 280),
                child: AspectRatio(
                  aspectRatio:
                      showCamera ? controller.value.aspectRatio : 16 / 9,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(26),
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
              const SizedBox(height: 14),
              Text(
                showCamera
                    ? 'Telefonun bebek odasına baktığını buradan hızlıca kontrol edebilirsin.'
                    : 'Kamera izni verildiğinde oda görüntüsü burada görünecek.',
                style: const TextStyle(color: Colors.white70, fontSize: 16),
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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: ShapeDecoration(
        color: color,
        shape: const StadiumBorder(),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: MimiCamDesignTokens.navy,
          fontWeight: FontWeight.w900,
          fontSize: 14,
        ),
      ),
    );
  }
}

class _PreviewWaitingContent extends StatelessWidget {
  const _PreviewWaitingContent();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.videocam_off_rounded, color: Colors.white54, size: 42),
          SizedBox(height: 12),
          Text(
            'Kamera hazırlanıyor',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 17,
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
    required this.telegramEnabled,
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
  final bool telegramEnabled;
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
    return MimiCamCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text('Sessiz ve güvenli algılama',
                  style: MimiCamDesignTokens.cardTitle),
              _SettingsSaveChip(saving: saving),
              TextButton.icon(
                onPressed: saving ? null : onReset,
                icon: const Icon(Icons.restart_alt_rounded),
                label: const Text('Varsayılanlara dön'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Hassasiyeti bebeğin odasına göre ayarla; değişiklikler otomatik kaydedilir.',
            style: TextStyle(
              color: MimiCamDesignTokens.slate,
              fontSize: 16,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 22),
          _SettingSlider(
            title: 'Ağlama eşiği',
            description:
                'Daha düşük değer, daha sessiz ağlamalara da tepki verir.',
            valueLabel: '%${(cryScoreThreshold * 100).round()}',
            value: cryScoreThreshold,
            min: .20,
            max: .95,
            divisions: 75,
            color: MimiCamDesignTokens.mint,
            onChanged: onCryScoreThresholdChanged,
            onChangeEnd: onCryScoreThresholdChangeEnd,
          ),
          const SizedBox(height: 18),
          _SettingSlider(
            title: 'Hareket eşiği',
            description:
                'Battaniye veya ışık değişimlerini ne kadar önemseyeceğini ayarlar.',
            valueLabel: '%${(motionThreshold * 100).round()}',
            value: motionThreshold,
            min: .05,
            max: .60,
            divisions: 55,
            color: MimiCamDesignTokens.amber,
            onChanged: onMotionThresholdChanged,
            onChangeEnd: onMotionThresholdChangeEnd,
          ),
          const SizedBox(height: 18),
          _SettingSlider(
            title: 'Bildirim cooldown',
            description: 'Aynı uyarının üst üste rahatsız etmesini engeller.',
            valueLabel: '${notifyCooldownSeconds.round()} sn',
            value: notifyCooldownSeconds,
            min: 10,
            max: 180,
            divisions: 34,
            color: MimiCamDesignTokens.pink,
            onChanged: onNotifyCooldownChanged,
            onChangeEnd: onNotifyCooldownChangeEnd,
          ),
          const SizedBox(height: 18),
          _SettingSlider(
            title: 'Ağlama minimum süre',
            description:
                'Sesin uyarı sayılması için eşik üstünde kalma süresi.',
            valueLabel: '${cryDurationSeconds.toStringAsFixed(1)} sn',
            value: cryDurationSeconds,
            min: .5,
            max: 6,
            divisions: 11,
            color: MimiCamDesignTokens.mint,
            onChanged: onCryDurationChanged,
            onChangeEnd: onCryDurationChangeEnd,
          ),
          const SizedBox(height: 18),
          _SettingSlider(
            title: 'Hareket minimum süre',
            description:
                'Kısa ışık/parazit değişimlerini filtrelemek için süre.',
            valueLabel: '${motionDurationSeconds.toStringAsFixed(1)} sn',
            value: motionDurationSeconds,
            min: .5,
            max: 6,
            divisions: 11,
            color: MimiCamDesignTokens.amber,
            onChanged: onMotionDurationChanged,
            onChangeEnd: onMotionDurationChangeEnd,
          ),
          const SizedBox(height: 22),
          _KeyVal('Telegram', telegramEnabled ? 'Kurulu' : 'Eksik / kapalı'),
        ],
      ),
    );
  }
}

class _SettingsSaveChip extends StatelessWidget {
  const _SettingsSaveChip({required this.saving});

  final bool saving;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: ShapeDecoration(
        color:
            saving ? MimiCamDesignTokens.amber : MimiCamDesignTokens.mintSoft,
        shape: const StadiumBorder(),
      ),
      child: Text(
        saving ? 'Kaydediliyor' : 'Gerçek ayarlar',
        style: const TextStyle(
          color: MimiCamDesignTokens.navy,
          fontSize: 13,
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
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            Text(
              valueLabel,
              style: TextStyle(
                color: color,
                fontSize: 18,
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
            fontSize: 15,
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
  const _Stat({required this.label, required this.value, required this.color});

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 126,
      padding: const EdgeInsets.all(22),
      decoration: MimiCamDesignTokens.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  color: MimiCamDesignTokens.slate, fontSize: 18)),
          const Spacer(),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: MimiCamDesignTokens.navy,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          Container(
              height: 12,
              decoration: BoxDecoration(
                  color: color, borderRadius: BorderRadius.circular(10))),
        ],
      ),
    );
  }
}

class _KeyVal extends StatelessWidget {
  const _KeyVal(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 19, color: MimiCamDesignTokens.slate)),
        const Spacer(),
        Text(
          value,
          style: const TextStyle(
            fontSize: 19,
            color: MimiCamDesignTokens.slate,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}
