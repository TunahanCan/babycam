import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../shared/presentation/babycam_design_tokens.dart';
import '../shared/presentation/babycam_shells.dart';
import 'server_runtime.dart';

class ServerHomeScreen extends StatefulWidget {
  const ServerHomeScreen({
    super.key,
    required this.runtime,
    required this.onResetRole,
  });

  final ServerRuntime runtime;
  final VoidCallback onResetRole;

  @override
  State<ServerHomeScreen> createState() => _ServerHomeScreenState();
}

class _ServerHomeScreenState extends State<ServerHomeScreen> {
  @override
  void initState() {
    super.initState();
    widget.runtime.startPairingMode();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<ServerRuntimeState>(
      stream: widget.runtime.states,
      initialData: widget.runtime.currentState,
      builder: (context, snapshot) {
        final state = snapshot.data!;
        return Scaffold(
          body: BabyCamGradientShell(
            variant: BabyCamShellVariant.server,
            child: SafeArea(
              child: ListView(
                padding: BabyCamDesignTokens.screenPadding,
                children: [
                  BabyCamTopBar(onResetRole: widget.onResetRole, dark: true),
                  const SizedBox(height: 46),
                  const Text('Bebek odası', style: BabyCamDesignTokens.darkTitle),
                  const SizedBox(height: 6),
                  const Text(
                    'Yayın hazır. Ebeveyn cihazı QR tarayabilir veya URL girebilir.',
                    style: BabyCamDesignTokens.darkSubtitle,
                  ),
                  const SizedBox(height: 20),
                  _StatusPill(label: _phaseLabel(state.phase)),
                  const SizedBox(height: 34),
                  const _PreviewPlaceholder(),
                  const SizedBox(height: 28),
                  _ConnectionCard(qrPayload: state.qrPayload),
                  const SizedBox(height: 28),
                  _RuntimeStats(state: state),
                  const SizedBox(height: 28),
                  _DetectionCard(state: state),
                  const SizedBox(height: 54),
                  SizedBox(
                    height: 72,
                    child: FilledButton(
                      onPressed: widget.runtime.stop,
                      style: FilledButton.styleFrom(
                        backgroundColor: BabyCamDesignTokens.pink,
                        shape: const StadiumBorder(),
                      ),
                      child: const Text(
                        'Yayını durdur',
                        style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
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

class _ConnectionCard extends StatelessWidget {
  const _ConnectionCard({required this.qrPayload});

  final String? qrPayload;

  @override
  Widget build(BuildContext context) {
    final payload = qrPayload ?? 'babycam://pairing/pending';
    return BabyCamCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Bağlantı adresi', style: BabyCamDesignTokens.cardTitle),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF2F0F8),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Text(
                    payload,
                    style: const TextStyle(
                      color: BabyCamDesignTokens.navy,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                const Text(
                  'QR kodu ebeveyn cihazına göster',
                  style: TextStyle(color: BabyCamDesignTokens.slate, fontSize: 19),
                ),
              ],
            ),
          ),
          const SizedBox(width: 28),
          QrImageView(
            data: payload,
            size: 140,
            padding: EdgeInsets.zero,
            eyeStyle: const QrEyeStyle(color: BabyCamDesignTokens.navy),
            dataModuleStyle: const QrDataModuleStyle(color: BabyCamDesignTokens.navy),
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
    return Row(
      children: [
        Expanded(
          child: _Stat(
            label: 'Client',
            value: '${state.activeClients} bağlı',
            color: BabyCamDesignTokens.mint,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: _Stat(
            label: 'Video',
            value: state.cameraActive ? 'MJPEG aktif' : 'Beklemede',
            color: BabyCamDesignTokens.pink,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: _Stat(
            label: 'Ses',
            value: state.microphoneActive ? 'WAV açık' : 'Kapalı',
            color: BabyCamDesignTokens.amber,
          ),
        ),
      ],
    );
  }
}

class _DetectionCard extends StatelessWidget {
  const _DetectionCard({required this.state});

  final ServerRuntimeState state;

  @override
  Widget build(BuildContext context) {
    return BabyCamCard(
      child: Opacity(
        opacity: .72,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Aktif algılama', style: BabyCamDesignTokens.cardTitle),
            const SizedBox(height: 22),
            _KeyVal('Ağlama analizi', state.cryAnalyzerActive ? 'Açık' : 'Kapalı'),
            const SizedBox(height: 16),
            _KeyVal('Hareket analizi', state.motionAnalyzerActive ? 'Açık' : 'Kapalı'),
            const SizedBox(height: 16),
            _KeyVal('Güç modu', state.powerMode.name),
          ],
        ),
      ),
    );
  }
}

class _PreviewPlaceholder extends StatelessWidget {
  const _PreviewPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 460,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(34),
        border: Border.all(color: Colors.white, width: 1.2),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 160,
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const ShapeDecoration(color: Colors.white, shape: StadiumBorder()),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: BabyCamDesignTokens.navy,
          fontWeight: FontWeight.w900,
          fontSize: 18,
        ),
      ),
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
      height: 138,
      padding: const EdgeInsets.all(22),
      decoration: BabyCamDesignTokens.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: BabyCamDesignTokens.slate, fontSize: 18)),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(
              color: BabyCamDesignTokens.navy,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          Container(height: 12, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10))),
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
        Text(label, style: const TextStyle(fontSize: 19, color: BabyCamDesignTokens.slate)),
        const Spacer(),
        Text(
          value,
          style: const TextStyle(
            fontSize: 19,
            color: BabyCamDesignTokens.slate,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}
