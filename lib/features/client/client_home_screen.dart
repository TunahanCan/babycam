import 'package:flutter/material.dart';

import '../shared/presentation/mimicam_design_tokens.dart';
import '../shared/presentation/mimicam_shells.dart';
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
          body: MimiCamGradientShell(
            variant: MimiCamShellVariant.client,
            child: SafeArea(
              child: Stack(
                children: [
                  ListView(
                    padding:
                        MimiCamDesignTokens.screenPadding.copyWith(bottom: 138),
                    children: [
                      MimiCamTopBar(onResetRole: onResetRole),
                      const SizedBox(height: 24),
                      _ClientHeroCard(phase: state.phase),
                      const SizedBox(height: 22),
                      const _SectionHeader(
                        eyebrow: 'Bağlantı',
                        title: 'Bebek odasına bağlan',
                        subtitle:
                            'Aynı Wi‑Fi içindeysen otomatik bulur; olmazsa QR veya IP ile devam edersin.',
                      ),
                      const SizedBox(height: 14),
                      const _ConnectionChoices(),
                      const SizedBox(height: 24),
                      const _SectionHeader(
                        eyebrow: 'Yakında',
                        title: 'Bulunan odalar',
                        subtitle: 'Güvenli eşleşen cihazlar burada görünür.',
                      ),
                      const SizedBox(height: 14),
                      _RoomCard(
                        title: 'Bebek Odası',
                        status: 'Hazır ve aynı ağda',
                        address: '192.168.1.20:8080',
                        tone: MimiCamDesignTokens.mint,
                        onWatch: () => _openWatch(context),
                      ),
                      const SizedBox(height: 14),
                      const _RoomCard(
                        title: 'Salon yedek cihaz',
                        status: 'Beklemede',
                        address: '192.168.1.34:8080',
                        tone: MimiCamDesignTokens.amber,
                        muted: true,
                      ),
                    ],
                  ),
                  Positioned(
                    left: 18,
                    right: 18,
                    bottom: 16,
                    child: _BottomActionDock(
                      onScanQr: () {},
                      onConnect: () => _openWatch(context),
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

  void _openWatch(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => WatchScreen(runtime: runtime)),
    );
  }
}

class _ClientHeroCard extends StatelessWidget {
  const _ClientHeroCard({required this.phase});

  final ClientRuntimePhase phase;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(26),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(36),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22111827),
            blurRadius: 30,
            offset: Offset(0, 16),
          ),
        ],
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
                  color: MimiCamDesignTokens.mintSoft,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.monitor_heart_rounded,
                  color: MimiCamDesignTokens.navy,
                  size: 38,
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _TinyLabel('Ebeveyn modu'),
                    const SizedBox(height: 8),
                    Text(
                      _titleFor(phase),
                      style: const TextStyle(
                        color: MimiCamDesignTokens.navy,
                        fontSize: 32,
                        height: 1.02,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            _subtitleFor(phase),
            style: const TextStyle(
              color: MimiCamDesignTokens.slate,
              fontSize: 18,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 22),
          const Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _ComfortChip(icon: Icons.wifi_rounded, text: 'Aynı Wi‑Fi'),
              _ComfortChip(icon: Icons.qr_code_rounded, text: 'QR hazır'),
              _ComfortChip(
                  icon: Icons.notifications_active_rounded, text: 'Uyarılar'),
            ],
          ),
        ],
      ),
    );
  }

  static String _titleFor(ClientRuntimePhase phase) {
    return switch (phase) {
      ClientRuntimePhase.unpaired => 'Odayı bulalım',
      ClientRuntimePhase.scanningQr => 'QR kodu tarat',
      ClientRuntimePhase.pairing => 'Güvenli eşleşiyor',
      ClientRuntimePhase.pairedIdle => 'Bebek odası hazır',
      ClientRuntimePhase.renewingToken => 'Oturum yenileniyor',
      ClientRuntimePhase.watching => 'Canlı izleme açık',
      ClientRuntimePhase.alertOnly => 'Uyarılar takipte',
      ClientRuntimePhase.reconnecting => 'Yeniden bağlanıyor',
      ClientRuntimePhase.offline => 'Oda çevrim dışı',
      ClientRuntimePhase.revoked => 'Eşleşme iptal edildi',
      ClientRuntimePhase.error => 'Bağlantıyı toparlayalım',
    };
  }

  static String _subtitleFor(ClientRuntimePhase phase) {
    return switch (phase) {
      ClientRuntimePhase.error =>
        'Ağ bağlantısını kontrol et; QR veya IP ile yeniden deneyebilirsin.',
      ClientRuntimePhase.offline =>
        'Bebek odası cihazı aynı ağda görünmüyor. Yakında tekrar arayacağız.',
      ClientRuntimePhase.watching =>
        'Canlı yayın ve son uyarılar izleme ekranında hazır.',
      _ =>
        'MimiCam yakındaki bebek odası cihazını sakin ve güvenli şekilde arar.',
    };
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.eyebrow,
    required this.title,
    required this.subtitle,
  });

  final String eyebrow;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _TinyLabel(eyebrow),
        const SizedBox(height: 6),
        Text(
          title,
          style: const TextStyle(
            color: MimiCamDesignTokens.navy,
            fontSize: 27,
            height: 1.05,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: const TextStyle(
            color: MimiCamDesignTokens.slate,
            fontSize: 17,
            height: 1.25,
          ),
        ),
      ],
    );
  }
}

class _ConnectionChoices extends StatelessWidget {
  const _ConnectionChoices();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 410;
        final children = [
          const Expanded(
            child: _ConnectionChoice(
              icon: Icons.auto_awesome_rounded,
              title: 'Otomatik',
              subtitle: 'Aynı ağda bul',
              color: MimiCamDesignTokens.mint,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: _ConnectionChoice(
              icon: Icons.qr_code_scanner_rounded,
              title: 'QR',
              subtitle: 'En hızlı yol',
              color: MimiCamDesignTokens.pink,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: _ConnectionChoice(
              icon: Icons.link_rounded,
              title: 'IP',
              subtitle: 'Elle bağlan',
              color: MimiCamDesignTokens.amber,
            ),
          ),
        ];
        if (compact) {
          return Column(
            children: [
              for (final child in children)
                if (child is Expanded) ...[
                  SizedBox(width: double.infinity, child: child.child),
                  if (child != children.last) const SizedBox(height: 12),
                ],
            ],
          );
        }
        return Row(children: children);
      },
    );
  }
}

class _ConnectionChoice extends StatelessWidget {
  const _ConnectionChoice({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 116),
      padding: const EdgeInsets.all(18),
      decoration: MimiCamDesignTokens.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            backgroundColor: color,
            child: Icon(icon, color: MimiCamDesignTokens.navy),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            style: const TextStyle(
              color: MimiCamDesignTokens.navy,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(
              color: MimiCamDesignTokens.slate,
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }
}

class _RoomCard extends StatelessWidget {
  const _RoomCard({
    required this.title,
    required this.status,
    required this.address,
    required this.tone,
    this.onWatch,
    this.muted = false,
  });

  final String title;
  final String status;
  final String address;
  final Color tone;
  final VoidCallback? onWatch;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: MimiCamDesignTokens.cardDecoration(),
      child: Row(
        children: [
          Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              color: muted ? const Color(0xFFE9EDF2) : tone,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Icon(
              muted ? Icons.bedtime_rounded : Icons.child_care_rounded,
              color: MimiCamDesignTokens.navy,
              size: 30,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: MimiCamDesignTokens.navy,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  status,
                  style: const TextStyle(
                    color: MimiCamDesignTokens.slate,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  address,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: MimiCamDesignTokens.slate,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          if (onWatch != null) ...[
            const SizedBox(width: 10),
            IconButton.filled(
              onPressed: onWatch,
              style: IconButton.styleFrom(
                backgroundColor: MimiCamDesignTokens.navy,
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.play_arrow_rounded),
            ),
          ],
        ],
      ),
    );
  }
}

class _BottomActionDock extends StatelessWidget {
  const _BottomActionDock({required this.onScanQr, required this.onConnect});

  final VoidCallback onScanQr;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .94),
        borderRadius: BorderRadius.circular(34),
        boxShadow: const [
          BoxShadow(
            color: Color(0x30111827),
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: _DockButton(
              label: 'QR Tara',
              icon: Icons.qr_code_scanner_rounded,
              backgroundColor: MimiCamDesignTokens.mint,
              foregroundColor: MimiCamDesignTokens.navy,
              onPressed: onScanQr,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _DockButton(
              label: 'Canlı İzle',
              icon: Icons.play_arrow_rounded,
              backgroundColor: MimiCamDesignTokens.pink,
              foregroundColor: Colors.white,
              onPressed: onConnect,
            ),
          ),
        ],
      ),
    );
  }
}

class _DockButton extends StatelessWidget {
  const _DockButton({
    required this.label,
    required this.icon,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final Color backgroundColor;
  final Color foregroundColor;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 62,
      child: FilledButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, color: foregroundColor, size: 24),
        style: FilledButton.styleFrom(
          backgroundColor: backgroundColor,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          padding: const EdgeInsets.symmetric(horizontal: 12),
        ),
        label: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: foregroundColor,
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _ComfortChip extends StatelessWidget {
  const _ComfortChip({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
      decoration: const ShapeDecoration(
        color: Color(0xFFF1F6FA),
        shape: StadiumBorder(),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: MimiCamDesignTokens.navy, size: 18),
          const SizedBox(width: 7),
          Text(
            text,
            style: const TextStyle(
              color: MimiCamDesignTokens.navy,
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _TinyLabel extends StatelessWidget {
  const _TinyLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        color: MimiCamDesignTokens.pink,
        fontSize: 12,
        letterSpacing: 1.2,
        fontWeight: FontWeight.w900,
      ),
    );
  }
}
