import 'package:flutter/material.dart';

import '../shared/presentation/babycam_design_tokens.dart';
import '../shared/presentation/babycam_shells.dart';
import 'client_runtime.dart';
import 'media/watch_screen.dart';

class ClientHomeScreen extends StatelessWidget {
  const ClientHomeScreen({
    super.key,
    required this.runtime,
    required this.onResetRole,
  });

  final ClientRuntime runtime;
  final VoidCallback onResetRole;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<ClientRuntimeState>(
      stream: runtime.states,
      initialData: runtime.currentState,
      builder: (context, snapshot) {
        final state = snapshot.data!;
        return Scaffold(
          body: BabyCamGradientShell(
            variant: BabyCamShellVariant.client,
            child: SafeArea(
              child: ListView(
                padding: BabyCamDesignTokens.screenPadding,
                children: [
                  BabyCamTopBar(onResetRole: onResetRole),
                  const SizedBox(height: 46),
                  const Text('Ebeveyn cihazı', style: BabyCamDesignTokens.title),
                  const SizedBox(height: 6),
                  const Text(
                    'Bebek odası cihazını otomatik bul, QR tara veya IP adresini gir.',
                    style: BabyCamDesignTokens.subtitle,
                  ),
                  const SizedBox(height: 72),
                  _DiscoveryCard(phase: state.phase),
                  const SizedBox(height: 34),
                  const Text(
                    'Bulunan cihazlar',
                    style: TextStyle(
                      color: BabyCamDesignTokens.navy,
                      fontSize: 30,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 18),
                  const _Device(
                    title: 'Bebek Odası',
                    ip: '192.168.1.20:8080',
                    chip: 'Güçlü sinyal',
                  ),
                  const SizedBox(height: 22),
                  const _Device(
                    title: 'Salon yedek cihaz',
                    ip: '192.168.1.34:8080',
                    chip: 'Beklemede',
                    muted: true,
                  ),
                  const SizedBox(height: 48),
                  const _ConnectionMethodCard(),
                  const SizedBox(height: 170),
                  _Actions(runtime: runtime),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _DiscoveryCard extends StatelessWidget {
  const _DiscoveryCard({required this.phase});

  final ClientRuntimePhase phase;

  @override
  Widget build(BuildContext context) {
    return BabyCamCard(
      child: Column(
        children: [
          const SizedBox(height: 270, child: _Radar()),
          const SizedBox(height: 8),
          Text(
            _phaseTitle(phase),
            style: const TextStyle(
              color: BabyCamDesignTokens.navy,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'UDP discovery aktif; bulamazsa QR veya IP kullan.',
            style: TextStyle(color: BabyCamDesignTokens.slate, fontSize: 18),
          ),
        ],
      ),
    );
  }

  static String _phaseTitle(ClientRuntimePhase phase) {
    return switch (phase) {
      ClientRuntimePhase.unpaired => 'Ağda BabyCam aranıyor...',
      ClientRuntimePhase.scanningQr => 'QR kod bekleniyor...',
      ClientRuntimePhase.pairing => 'Eşleşme kuruluyor...',
      ClientRuntimePhase.pairedIdle => 'Bebek odası hazır',
      ClientRuntimePhase.renewingToken => 'Güvenli oturum yenileniyor...',
      ClientRuntimePhase.watching => 'Canlı izleme açık',
      ClientRuntimePhase.alertOnly => 'Sadece uyarılar açık',
      ClientRuntimePhase.reconnecting => 'Yeniden bağlanılıyor...',
      ClientRuntimePhase.offline => 'Cihaz çevrim dışı',
      ClientRuntimePhase.revoked => 'Eşleşme iptal edildi',
      ClientRuntimePhase.error => 'Bağlantı hatası',
    };
  }
}

class _Actions extends StatelessWidget {
  const _Actions({required this.runtime});

  final ClientRuntime runtime;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 72,
            child: FilledButton(
              onPressed: () {},
              style: FilledButton.styleFrom(
                backgroundColor: BabyCamDesignTokens.mint,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
              ),
              child: const Text(
                'QR Tara',
                style: TextStyle(
                  color: BabyCamDesignTokens.navy,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 28),
        Expanded(
          child: SizedBox(
            height: 72,
            child: FilledButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => WatchScreen(runtime: runtime)),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: BabyCamDesignTokens.pink,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
              ),
              child: const Text(
                'Bağlan',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ConnectionMethodCard extends StatelessWidget {
  const _ConnectionMethodCard();

  @override
  Widget build(BuildContext context) {
    return BabyCamCard(
      dark: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Bağlanma yöntemi',
            style: TextStyle(color: Colors.white, fontSize: 25, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 22),
          Container(
            height: 58,
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: const Text(
              '192.168.1.20:8080',
              style: TextStyle(color: BabyCamDesignTokens.navy, fontSize: 20),
            ),
          ),
        ],
      ),
    );
  }
}

class _Device extends StatelessWidget {
  const _Device({
    required this.title,
    required this.ip,
    required this.chip,
    this.muted = false,
  });

  final String title;
  final String ip;
  final String chip;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BabyCamDesignTokens.cardDecoration(),
      child: Row(
        children: [
          const CircleAvatar(radius: 32, backgroundColor: BabyCamDesignTokens.mintSoft),
          const SizedBox(width: 22),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: BabyCamDesignTokens.navy,
                    fontSize: 23,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(ip, style: const TextStyle(color: BabyCamDesignTokens.slate, fontSize: 19)),
              ],
            ),
          ),
          _SmallChip(
            text: chip,
            color: muted ? const Color(0xFFE9EDF2) : const Color(0xFFFFDCE6),
          ),
        ],
      ),
    );
  }
}

class _Radar extends StatelessWidget {
  const _Radar();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: const _RadarPainter(), child: const SizedBox.expand());
  }
}

class _RadarPainter extends CustomPainter {
  const _RadarPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2 - 10);
    final ringPaint = Paint()
      ..color = BabyCamDesignTokens.pink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6;
    for (final radius in [52.0, 92.0, 132.0]) {
      canvas.drawCircle(center, radius, ringPaint);
    }
    canvas.drawCircle(center, 50, Paint()..color = BabyCamDesignTokens.navy);
    canvas.drawCircle(center, 16, Paint()..color = BabyCamDesignTokens.mint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _SmallChip extends StatelessWidget {
  const _SmallChip({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: ShapeDecoration(color: color, shape: const StadiumBorder()),
      child: Text(
        text,
        style: const TextStyle(
          color: BabyCamDesignTokens.navy,
          fontWeight: FontWeight.w800,
          fontSize: 16,
        ),
      ),
    );
  }
}
