import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../app/app_role.dart';
import '../../core/protocol/mimicam_protocol.dart';
import '../../core/protocol/pairing_payload.dart';
import '../shared/presentation/mimicam_design_tokens.dart';
import '../shared/presentation/mimicam_shells.dart';
import 'client_runtime.dart';
import 'media/watch_screen.dart';
import 'pairing/client_pairing_flow.dart';
import 'pairing/qr_scan_screen.dart';

class ClientHomeScreen extends StatefulWidget {
  const ClientHomeScreen({
    super.key,
    required this.runtime,
    required this.activeRole,
    required this.onRoleSelected,
    this.switchingRole = false,
  });

  final ClientRuntime runtime;
  final AppRole activeRole;
  final ValueChanged<AppRole> onRoleSelected;
  final bool switchingRole;

  @override
  State<ClientHomeScreen> createState() => _ClientHomeScreenState();
}

class _ClientHomeScreenState extends State<ClientHomeScreen> {
  final _manualIpController = TextEditingController();
  int _tab = 0;

  @override
  void dispose() {
    _manualIpController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<ClientRuntimeState>(
      stream: widget.runtime.states,
      initialData: widget.runtime.currentState,
      builder: (context, snapshot) {
        final state = snapshot.data!;
        return Scaffold(
          body: MimiCamGradientShell(
            variant: MimiCamShellVariant.client,
            child: SafeArea(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                transitionBuilder: _hardWipe,
                child: _buildTab(context, state),
              ),
            ),
          ),
          bottomNavigationBar: MimiCamBottomNav(
            items: _clientNavItems,
            currentIndex: _tab,
            activeColor: MimiCamDesignTokens.mint,
            onTap: (index) => setState(() => _tab = index),
          ),
        );
      },
    );
  }

  Widget _buildTab(BuildContext context, ClientRuntimeState state) {
    return switch (_tab) {
      0 => _ClientTabFrame(
          key: const ValueKey('client-watch'),
          activeRole: widget.activeRole,
          onRoleSelected: widget.onRoleSelected,
          switchingRole: widget.switchingRole,
          children: [
            _ClientHeroCard(phase: state.phase),
            const SizedBox(height: 12),
            _ClientNotificationFocusCard(
              phase: state.phase,
              paired: state.session != null,
              onOpenFind: () => setState(() => _tab = 1),
              onOpenNotifications: () => setState(() => _tab = 2),
            ),
            const SizedBox(height: 16),
            _SectionHeader(
              eyebrow: state.session == null ? 'İzle' : 'Canlı',
              title:
                  state.session == null ? 'Önce oda seç' : 'Bebek odası hazır',
              subtitle: state.session == null
                  ? 'Client izleme ekranı sadece eşleşmiş server yayınını gösterir.'
                  : 'Canlı yayın ve son uyarılar ebeveyn cihazında takip edilir.',
            ),
            const SizedBox(height: 10),
            if (state.session == null)
              const _NoRoomCard()
            else ...[
              _RoomCard(
                title: state.session!.payload.deviceName,
                status: 'QR ile eşleşti',
                address:
                    '${state.session!.payload.host}:${state.session!.payload.port}',
                tone: MimiCamDesignTokens.mint,
                onWatch: () => _openWatch(context, state),
              ),
              const SizedBox(height: 10),
              _ClientWatchSummary(onWatch: () => _openWatch(context, state)),
            ],
          ],
        ),
      1 => _ClientTabFrame(
          key: const ValueKey('client-find'),
          activeRole: widget.activeRole,
          onRoleSelected: widget.onRoleSelected,
          switchingRole: widget.switchingRole,
          children: [
            const _SectionHeader(
              eyebrow: 'Bul',
              title: 'Bebek odasına bağlan',
              subtitle:
                  'Oda cihazını QR ile eşleştir; gerekirse IP adresini elle gir.',
            ),
            const SizedBox(height: 10),
            const _ConnectionChoices(),
            const SizedBox(height: 12),
            _FindActionCard(
              onScanQr: () => _scanQr(context),
              manualIpController: _manualIpController,
              onManualConnect: () => _connectManualIp(context),
            ),
            const SizedBox(height: 12),
            if (state.session == null)
              const _NoRoomCard()
            else
              _RoomCard(
                title: state.session!.payload.deviceName,
                status: 'Eşleşmiş cihaz',
                address:
                    '${state.session!.payload.host}:${state.session!.payload.port}',
                tone: MimiCamDesignTokens.mint,
                onWatch: () => _openWatch(context, state),
              ),
          ],
        ),
      2 => _ClientTabFrame(
          key: const ValueKey('client-history'),
          activeRole: widget.activeRole,
          onRoleSelected: widget.onRoleSelected,
          switchingRole: widget.switchingRole,
          children: const [
            _SectionHeader(
              eyebrow: 'Bildirim',
              title: 'Son durum ve bildirimler',
              subtitle:
                  'Ağlama, hareket ve sistem olayları anne ekranında öne çıkar.',
            ),
            SizedBox(height: 10),
            _ClientPlaceholderCard(
              icon: Icons.notifications_active_rounded,
              title: 'Son durum bekleniyor',
              text:
                  'Eşleşmiş server uyarı gönderdiğinde en önemli durum burada görünecek.',
            ),
          ],
        ),
      _ => _ClientTabFrame(
          key: const ValueKey('client-settings'),
          activeRole: widget.activeRole,
          onRoleSelected: widget.onRoleSelected,
          switchingRole: widget.switchingRole,
          children: const [
            _SectionHeader(
              eyebrow: 'Ayarlar',
              title: 'Ebeveyn cihazı tercihleri',
              subtitle:
                  'Bildirim ve izleme davranışı burada kalır; server portu veya yayın kontrolü yoktur.',
            ),
            SizedBox(height: 10),
            _ClientPlaceholderCard(
              icon: Icons.notifications_active_rounded,
              title: 'Client ayarları',
              text:
                  'Yerel bildirim, reconnect ve viewer tercihleri burada yönetilecek.',
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

  Future<void> _scanQr(BuildContext context) async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const QRScanScreen()),
    );
    if (!context.mounted || code == null) return;

    final payload = PairingPayload.parseUri(code);
    if (payload == null) {
      _showMessage(context, 'Geçersiz veya süresi dolmuş MimiCam QR kodu.');
      return;
    }

    try {
      await ClientPairingFlow(widget.runtime).pairAndArmAlerts(payload);
      if (!context.mounted) return;
      setState(() => _tab = 0);
      _showMessage(context, '${payload.deviceName} eşleşti.');
    } catch (error) {
      if (!context.mounted) return;
      _showMessage(context, 'Eşleşme kurulamadı: $error');
    }
  }

  Future<void> _connectManualIp(BuildContext context) async {
    final parsed = _parseManualAddress(_manualIpController.text);
    if (parsed == null) {
      _showMessage(context, 'IP formatı geçersiz. Örnek: 192.168.1.20:8080');
      return;
    }
    try {
      final payload = await _fetchManualPairingPayload(parsed);
      await ClientPairingFlow(widget.runtime).pairAndArmAlerts(payload);
      if (!context.mounted) return;
      setState(() => _tab = 0);
      _showMessage(context, '${payload.deviceName} eşleşti.');
    } catch (error) {
      if (!context.mounted) return;
      _showMessage(context, 'IP ile eşleşme kurulamadı: $error');
    }
  }

  Future<PairingPayload> _fetchManualPairingPayload(
      ({String host, int port}) address) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(
        Uri(
          scheme: 'http',
          host: address.host,
          port: address.port,
          path: MimiCamProtocolV2.statusPublic,
        ),
      );
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw StateError('Server bulunamadı: ${response.statusCode}');
      }
      final body = await utf8.decoder.bind(response).join();
      final json = jsonDecode(body);
      if (json is! Map) throw StateError('Geçersiz server yanıtı');
      final nonce = json['pairingNonce']?.toString();
      if (nonce == null || nonce.isEmpty) {
        throw StateError('Server pairing nonce üretmedi');
      }
      final capabilities = json['capabilities'] is Map
          ? Map<String, Object?>.from(json['capabilities'] as Map)
          : const <String, Object?>{
              'video': 'mjpeg',
              'audio': 'pcm16le',
              'events': 'json',
              'transport': 'http',
            };
      return PairingPayload(
        schemaVersion: MimiCamProtocolV2.schemaVersion,
        host: address.host,
        port: address.port,
        deviceId: json['serverDeviceId']?.toString() ?? 'manual_server',
        deviceName: json['serverName']?.toString() ?? 'Manual IP Server',
        pairingNonce: nonce,
        expiresAtMs: DateTime.now()
            .add(const Duration(minutes: 2))
            .millisecondsSinceEpoch,
        capabilities: capabilities,
      );
    } finally {
      client.close(force: true);
    }
  }

  ({String host, int port})? _parseManualAddress(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    final parts = trimmed.split(':');
    if (parts.length > 2 || parts.first.isEmpty) return null;
    final port = parts.length == 2 ? int.tryParse(parts.last) : 8080;
    if (port == null || port <= 0 || port > 65535) return null;
    return (host: parts.first, port: port);
  }

  void _openWatch(BuildContext context, ClientRuntimeState state) {
    if (state.session == null) {
      _showMessage(context, 'Önce server QR kodunu tara.');
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => WatchScreen(runtime: widget.runtime)),
    );
  }

  void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

const _clientNavItems = [
  MimiCamBottomNavItem(icon: Icons.live_tv_rounded, label: 'İzle'),
  MimiCamBottomNavItem(icon: Icons.radar_rounded, label: 'Bul'),
  MimiCamBottomNavItem(
      icon: Icons.notifications_active_rounded, label: 'Bildirim'),
  MimiCamBottomNavItem(icon: Icons.settings_rounded, label: 'Ayarlar'),
];

class _ClientTabFrame extends StatelessWidget {
  const _ClientTabFrame({
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
          ),
        ),
        const SizedBox(height: 12),
        ...children,
      ],
    );
  }
}

class _ClientHeroCard extends StatelessWidget {
  const _ClientHeroCard({required this.phase});

  final ClientRuntimePhase phase;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [
          BoxShadow(
            color: Color(0x18111827),
            blurRadius: 20,
            offset: Offset(0, 10),
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
                width: 56,
                height: 56,
                decoration: const BoxDecoration(
                  color: MimiCamDesignTokens.mintSoft,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.monitor_heart_rounded,
                  color: MimiCamDesignTokens.navy,
                  size: 30,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _TinyLabel('Ebeveyn modu'),
                    const SizedBox(height: 5),
                    Text(
                      _titleFor(phase),
                      style: const TextStyle(
                        color: MimiCamDesignTokens.navy,
                        fontSize: 26,
                        height: 1.08,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            _subtitleFor(phase),
            style: const TextStyle(
              color: MimiCamDesignTokens.slate,
              fontSize: 15,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 16),
          const Wrap(
            spacing: 8,
            runSpacing: 8,
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

class _ClientNotificationFocusCard extends StatelessWidget {
  const _ClientNotificationFocusCard({
    required this.phase,
    required this.paired,
    required this.onOpenFind,
    required this.onOpenNotifications,
  });

  final ClientRuntimePhase phase;
  final bool paired;
  final VoidCallback onOpenFind;
  final VoidCallback onOpenNotifications;

  @override
  Widget build(BuildContext context) {
    final active = paired &&
        (phase == ClientRuntimePhase.alertOnly ||
            phase == ClientRuntimePhase.watching ||
            phase == ClientRuntimePhase.pairedIdle);
    final title = active ? 'Son durum takipte' : 'Bildirim için oda eşleştir';
    final text = active
        ? 'Ağlama, hareket ve bağlantı uyarıları bu anne ekranında öne çıkar.'
        : 'QR veya IP ile eşleşince bebeğin son durumu burada görünür.';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: MimiCamDesignTokens.navy,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x26111827),
            blurRadius: 20,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor:
                active ? MimiCamDesignTokens.pink : MimiCamDesignTokens.amber,
            child: Icon(
              active
                  ? Icons.notifications_active_rounded
                  : Icons.notifications_none_rounded,
              color: MimiCamDesignTokens.navy,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'ANNE İÇİN ÖNCELİK',
                  style: TextStyle(
                    color: MimiCamDesignTokens.mint,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  text,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    onPressed: active ? onOpenNotifications : onOpenFind,
                    icon: Icon(
                      active
                          ? Icons.arrow_forward_rounded
                          : Icons.qr_code_scanner_rounded,
                      size: 18,
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: active
                          ? MimiCamDesignTokens.pink
                          : MimiCamDesignTokens.mint,
                      foregroundColor: MimiCamDesignTokens.navy,
                      visualDensity: VisualDensity.compact,
                      shape: const StadiumBorder(),
                    ),
                    label: Text(
                      active ? 'Bildirimleri aç' : 'Odayı eşleştir',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
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
            fontSize: 22,
            height: 1.12,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: const TextStyle(
            color: MimiCamDesignTokens.slate,
            fontSize: 14.5,
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
        final compact = constraints.maxWidth < 520;
        final children = [
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
                  if (child != children.last) const SizedBox(height: 10),
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
      constraints: const BoxConstraints(minHeight: 98),
      padding: const EdgeInsets.all(14),
      decoration: MimiCamDesignTokens.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            backgroundColor: color,
            child: Icon(icon, color: MimiCamDesignTokens.navy),
          ),
          const SizedBox(height: 10),
          Text(
            title,
            style: const TextStyle(
              color: MimiCamDesignTokens.navy,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(
              color: MimiCamDesignTokens.slate,
              fontSize: 13,
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
  });

  final String title;
  final String status;
  final String address;
  final Color tone;
  final VoidCallback? onWatch;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: MimiCamDesignTokens.cardDecoration(),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: tone,
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(
              Icons.child_care_rounded,
              color: MimiCamDesignTokens.navy,
              size: 26,
            ),
          ),
          const SizedBox(width: 12),
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
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  status,
                  style: const TextStyle(
                    color: MimiCamDesignTokens.slate,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  address,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: MimiCamDesignTokens.slate,
                    fontSize: 12.5,
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

class _NoRoomCard extends StatelessWidget {
  const _NoRoomCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: MimiCamDesignTokens.cardDecoration(),
      child: const Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: Color(0xFFE9EDF2),
            child: Icon(
              Icons.qr_code_scanner_rounded,
              color: MimiCamDesignTokens.navy,
              size: 25,
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'QR bekleniyor',
                  style: TextStyle(
                    color: MimiCamDesignTokens.navy,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Kendi kendine oda göstermeyecek; sadece taranan server bağlanır.',
                  style: TextStyle(
                    color: MimiCamDesignTokens.slate,
                    fontSize: 14,
                    height: 1.2,
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

class _ClientWatchSummary extends StatelessWidget {
  const _ClientWatchSummary({required this.onWatch});

  final VoidCallback onWatch;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: MimiCamDesignTokens.cardDecoration(dark: true),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              CircleAvatar(
                backgroundColor: MimiCamDesignTokens.mint,
                child: Icon(
                  Icons.monitor_heart_rounded,
                  color: MimiCamDesignTokens.navy,
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Canlı izleme dashboard',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'Video, WS durumu ve son uyarılar bu ebeveyn alanında açılır.',
            style:
                TextStyle(color: Colors.white70, fontSize: 14.5, height: 1.25),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton.icon(
              onPressed: onWatch,
              icon: const Icon(Icons.play_arrow_rounded),
              style: FilledButton.styleFrom(
                backgroundColor: MimiCamDesignTokens.mint,
                foregroundColor: MimiCamDesignTokens.navy,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              label: const Text(
                'Canlı izlemeyi aç',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FindActionCard extends StatelessWidget {
  const _FindActionCard({
    required this.onScanQr,
    required this.manualIpController,
    required this.onManualConnect,
  });

  final VoidCallback onScanQr;
  final TextEditingController manualIpController;
  final VoidCallback onManualConnect;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: MimiCamDesignTokens.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Bağlantı yolları', style: MimiCamDesignTokens.cardTitle),
          const SizedBox(height: 8),
          const Text(
            'QR tarayarak güvenli eşleş; gerekirse IP:port yazarak bağlan.',
            style: TextStyle(
              color: MimiCamDesignTokens.slate,
              fontSize: 14.5,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: FilledButton.icon(
              onPressed: onScanQr,
              icon: const Icon(Icons.qr_code_scanner_rounded),
              style: FilledButton.styleFrom(
                backgroundColor: MimiCamDesignTokens.mint,
                foregroundColor: MimiCamDesignTokens.navy,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              label: const Text(
                'QR Tara',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: manualIpController,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'IP veya IP:port',
              hintText: '192.168.1.20:8080',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton.icon(
              onPressed: onManualConnect,
              icon: const Icon(Icons.link_rounded),
              style: OutlinedButton.styleFrom(
                foregroundColor: MimiCamDesignTokens.navy,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              label: const Text(
                'IP ile bağlan',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ClientPlaceholderCard extends StatelessWidget {
  const _ClientPlaceholderCard({
    required this.icon,
    required this.title,
    required this.text,
  });

  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: MimiCamDesignTokens.cardDecoration(),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: MimiCamDesignTokens.mintSoft,
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
                    color: MimiCamDesignTokens.navy,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  text,
                  style: const TextStyle(
                    color: MimiCamDesignTokens.slate,
                    fontSize: 14.5,
                    height: 1.25,
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

class _ComfortChip extends StatelessWidget {
  const _ComfortChip({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: const ShapeDecoration(
        color: Color(0xFFF1F6FA),
        shape: StadiumBorder(),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: MimiCamDesignTokens.navy, size: 16),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(
              color: MimiCamDesignTokens.navy,
              fontSize: 12.5,
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
        fontSize: 10.5,
        letterSpacing: 1.0,
        fontWeight: FontWeight.w900,
      ),
    );
  }
}
