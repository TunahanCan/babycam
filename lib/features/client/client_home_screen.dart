import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../app/app_role.dart';
import '../../core/protocol/mimicam_protocol.dart';
import '../../core/protocol/pairing_payload.dart';
import '../../l10n/app_strings.dart';
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
            items: _clientNavItems(context),
            currentIndex: _tab,
            activeColor: MimiCamDesignTokens.pink,
            onTap: (index) => setState(() => _tab = index),
          ),
        );
      },
    );
  }

  Widget _buildTab(BuildContext context, ClientRuntimeState state) {
    final strings = AppStrings.of(context);
    return switch (_tab) {
      0 => _ClientTabFrame(
          key: const ValueKey('client-watch'),
          activeRole: widget.activeRole,
          onRoleSelected: widget.onRoleSelected,
          switchingRole: widget.switchingRole,
          children: [
            _ClientHeroCard(
              phase: state.phase,
              paired: state.session != null,
            ),
            const SizedBox(height: 16),
            if (state.session == null)
              _NoRoomCard(onOpenFind: () => setState(() => _tab = 1))
            else ...[
              const _BabyMonitorPreview(),
              const SizedBox(height: 8),
              _RoomCard(
                title: state.session!.payload.deviceName,
                status: strings.ui('pairedWithQr'),
                address:
                    '${state.session!.payload.host}:${state.session!.payload.port}',
                tone: MimiCamDesignTokens.mint,
                onWatch: () => _openWatch(context, state),
              ),
              const SizedBox(height: 10),
              const _ClientStatusGrid(),
              const SizedBox(height: 16),
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
            _SectionHeader(
              eyebrow: strings.ui('navFind'),
              title: strings.ui('connectBabyRoom'),
              subtitle: strings.ui('connectBabyRoomSubtitle'),
            ),
            const SizedBox(height: 18),
            _FindActionCard(
              onScanQr: () => _scanQr(context),
              manualIpController: _manualIpController,
              onManualConnect: () => _connectManualIp(context),
            ),
          ],
        ),
      2 => _ClientTabFrame(
          key: const ValueKey('client-history'),
          activeRole: widget.activeRole,
          onRoleSelected: widget.onRoleSelected,
          switchingRole: widget.switchingRole,
          children: [
            _SectionHeader(
              eyebrow: strings.ui('navNotifications'),
              title: strings.ui('latestStatusAndNotifications'),
              subtitle: strings.ui('parentEventsPriorityText'),
            ),
            const SizedBox(height: 18),
            const _NotificationFilterBar(),
            const SizedBox(height: 14),
            const _NotificationList(),
          ],
        ),
      _ => _ClientTabFrame(
          key: const ValueKey('client-settings'),
          activeRole: widget.activeRole,
          onRoleSelected: widget.onRoleSelected,
          switchingRole: widget.switchingRole,
          children: [
            _SectionHeader(
              eyebrow: strings.ui('navSettings'),
              title: strings.ui('parentDevicePreferences'),
              subtitle: strings.ui('noServerControlsText'),
            ),
            const SizedBox(height: 18),
            const _ClientSettingsList(),
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
    final strings = AppStrings.of(context);
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const QRScanScreen()),
    );
    if (!context.mounted || code == null) return;

    final payload = PairingPayload.parseUri(code);
    if (payload == null) {
      _showMessage(context, strings.ui('invalidQrCode'));
      return;
    }

    try {
      await ClientPairingFlow(widget.runtime).pairAndArmAlerts(payload);
      if (!context.mounted) return;
      setState(() => _tab = 0);
      _showMessage(context,
          strings.uiFormat('pairedMessage', {'name': payload.deviceName}));
    } catch (error) {
      if (!context.mounted) return;
      _showMessage(
          context, strings.uiFormat('pairingFailed', {'error': error}));
    }
  }

  Future<void> _connectManualIp(BuildContext context) async {
    final strings = AppStrings.of(context);
    final parsed = _parseManualAddress(_manualIpController.text);
    if (parsed == null) {
      _showMessage(context, strings.ui('invalidIpFormat'));
      return;
    }
    try {
      final payload = await _fetchManualPairingPayload(strings, parsed);
      await ClientPairingFlow(widget.runtime).pairAndArmAlerts(payload);
      if (!context.mounted) return;
      setState(() => _tab = 0);
      _showMessage(context,
          strings.uiFormat('pairedMessage', {'name': payload.deviceName}));
    } catch (error) {
      if (!context.mounted) return;
      _showMessage(
          context, strings.uiFormat('manualPairingFailed', {'error': error}));
    }
  }

  Future<PairingPayload> _fetchManualPairingPayload(
      AppStrings strings, ({String host, int port}) address) async {
    final client = HttpClient();
    try {
      return await _fetchManualPairingPayloadWithClient(
        strings,
        address,
        client: client,
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<PairingPayload> _fetchManualPairingPayloadWithClient(
    AppStrings strings,
    ({String host, int port}) address, {
    required HttpClient client,
  }) async {
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
      throw StateError(
          strings.uiFormat('serverNotFound', {'code': response.statusCode}));
    }
    final body = await utf8.decoder.bind(response).join();
    final json = jsonDecode(body);
    if (json is! Map) {
      throw StateError(strings.ui('invalidServerResponse'));
    }
    final nonce = json['pairingNonce']?.toString();
    if (nonce == null || nonce.isEmpty) {
      throw StateError(strings.ui('missingPairingNonce'));
    }
    final capabilities = json['capabilities'] is Map
        ? Map<String, Object?>.from(json['capabilities'] as Map)
        : <String, Object?>{
            'video': 'mjpeg',
            'audio': 'pcm16le',
            'events': 'json',
            'maxClients': 5,
          };
    return PairingPayload(
      schemaVersion: MimiCamProtocolV2.schemaVersion,
      host: address.host,
      port: address.port,
      deviceId: json['serverDeviceId']?.toString() ?? 'manual_server',
      deviceName: json['serverName']?.toString() ?? 'Manual IP Server',
      pairingNonce: nonce,
      expiresAtMs:
          DateTime.now().add(const Duration(minutes: 2)).millisecondsSinceEpoch,
      transport: json['transport']?.toString() ?? 'http_ws',
      capabilities: capabilities,
    );
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
      _showMessage(context, AppStrings.of(context).ui('scanServerQrFirst'));
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

List<MimiCamBottomNavItem> _clientNavItems(BuildContext context) {
  final strings = AppStrings.of(context);
  return [
    MimiCamBottomNavItem(
        icon: Icons.live_tv_rounded, label: strings.ui('navWatch')),
    MimiCamBottomNavItem(
        icon: Icons.radar_rounded, label: strings.ui('navFind')),
    MimiCamBottomNavItem(
        icon: Icons.notifications_active_rounded,
        label: strings.ui('navNotifications')),
    MimiCamBottomNavItem(
        icon: Icons.settings_rounded, label: strings.ui('navSettings')),
  ];
}

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
  const _ClientHeroCard({required this.phase, required this.paired});

  final ClientRuntimePhase phase;
  final bool paired;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _TinyLabel(strings.ui('parentPriority')),
        const SizedBox(height: 10),
        Text(
          strings.ui('goodMorning'),
          style: const TextStyle(
            color: MimiCamDesignTokens.slate,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          paired ? strings.ui('babySleepingWell') : _titleFor(strings, phase),
          style: const TextStyle(
            color: MimiCamDesignTokens.nightPlum,
            fontSize: 26,
            height: 1.08,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          paired
              ? strings.ui('liveAndAlertsParentText')
              : strings.ui('clientSubtitleDefault'),
          style: const TextStyle(
            color: MimiCamDesignTokens.slate,
            fontSize: 14.5,
            height: 1.25,
          ),
        ),
      ],
    );
  }

  static String _titleFor(AppStrings strings, ClientRuntimePhase phase) {
    return switch (phase) {
      ClientRuntimePhase.unpaired => strings.ui('clientTitleUnpaired'),
      ClientRuntimePhase.scanningQr => strings.ui('clientTitleScanningQr'),
      ClientRuntimePhase.pairing => strings.ui('clientTitlePairing'),
      ClientRuntimePhase.pairedIdle => strings.ui('clientTitlePairedIdle'),
      ClientRuntimePhase.renewingToken =>
        strings.ui('clientTitleRenewingToken'),
      ClientRuntimePhase.watching => strings.ui('clientTitleWatching'),
      ClientRuntimePhase.alertOnly => strings.ui('clientTitleAlertOnly'),
      ClientRuntimePhase.reconnecting => strings.ui('clientTitleReconnecting'),
      ClientRuntimePhase.offline => strings.ui('clientTitleOffline'),
      ClientRuntimePhase.revoked => strings.ui('clientTitleRevoked'),
      ClientRuntimePhase.error => strings.ui('clientTitleError'),
    };
  }
}

class _BabyMonitorPreview extends StatelessWidget {
  const _BabyMonitorPreview();

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return AspectRatio(
      aspectRatio: 16 / 10,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFA47465),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFF2D8CD), width: 4),
        ),
        child: Stack(
          children: [
            for (final left in [24.0, 82.0, 140.0, 198.0, 256.0])
              Positioned(
                left: left,
                top: 22,
                bottom: 22,
                child: Container(width: 1, color: Colors.white54),
              ),
            const Positioned(
              top: 10,
              left: 12,
              child: _LiveBadge(),
            ),
            const Align(
              alignment: Alignment.center,
              child: _CribSketch(),
            ),
            Positioned(
              right: 14,
              bottom: 12,
              child: Icon(
                Icons.signal_cellular_alt_rounded,
                color: Colors.white.withValues(alpha: .8),
                size: 22,
              ),
            ),
            Positioned(
              left: 14,
              bottom: 12,
              child: Text(
                strings.ui('live'),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ClientStatusGrid extends StatelessWidget {
  const _ClientStatusGrid();

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Row(
      children: [
        Expanded(
          child: _MiniStatusCard(
            title: strings.ui('roomStatus'),
            value: strings.ui('temperatureHumidity'),
            footnote: strings.ui('fine'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _MiniStatusCard(
            title: strings.ui('lastMotion'),
            value: strings.ui('twoMinutesAgo'),
            footnote: strings.ui('lightMotionDetected'),
          ),
        ),
      ],
    );
  }
}

class _MiniStatusCard extends StatelessWidget {
  const _MiniStatusCard({
    required this.title,
    required this.value,
    required this.footnote,
  });

  final String title;
  final String value;
  final String footnote;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 96,
      padding: const EdgeInsets.all(14),
      decoration: MimiCamDesignTokens.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: MimiCamDesignTokens.nightPlum,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
          const Spacer(),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: MimiCamDesignTokens.slate,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            footnote,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF38A879),
              fontSize: 12.5,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _LiveBadge extends StatelessWidget {
  const _LiveBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: const ShapeDecoration(
        color: Colors.white,
        shape: StadiumBorder(),
      ),
      child: Text(
        AppStrings.of(context).ui('live').toUpperCase(),
        style: const TextStyle(
          color: Color(0xFF218765),
          fontSize: 10,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _CribSketch extends StatelessWidget {
  const _CribSketch();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      height: 116,
      child: Stack(
        children: [
          Positioned(
            left: 34,
            right: 22,
            top: 44,
            child: Container(
              height: 62,
              decoration: BoxDecoration(
                color: const Color(0xFFFFDCCD),
                borderRadius: BorderRadius.circular(50),
              ),
            ),
          ),
          Positioned(
            left: 84,
            top: 22,
            child: Container(
              width: 70,
              height: 42,
              decoration: BoxDecoration(
                color: const Color(0xFFF0BFAE),
                borderRadius: BorderRadius.circular(32),
              ),
            ),
          ),
          const Positioned(
            right: 20,
            top: 42,
            child: CircleAvatar(
              radius: 18,
              backgroundColor: Color(0xFFC4A08E),
            ),
          ),
          const Positioned(
            right: 0,
            top: 58,
            child: CircleAvatar(
              radius: 13,
              backgroundColor: Color(0xFFC4A08E),
            ),
          ),
          const Positioned(
            left: 104,
            top: 48,
            child: SizedBox(
              width: 28,
              child: Divider(
                color: MimiCamDesignTokens.nightPlum,
                thickness: 1,
              ),
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
  const _NoRoomCard({this.onOpenFind});

  final VoidCallback? onOpenFind;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Column(
      children: [
        Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 246),
          padding: const EdgeInsets.all(22),
          decoration: MimiCamDesignTokens.cardDecoration(),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 128,
                height: 104,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: MimiCamDesignTokens.pink.withValues(alpha: .55),
                    width: 2,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Center(
                  child: Icon(
                    Icons.favorite_rounded,
                    color: MimiCamDesignTokens.pink,
                    size: 28,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                strings.ui('chooseRoomFirst'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: MimiCamDesignTokens.nightPlum,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                strings.ui('noRoomCalmText'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: MimiCamDesignTokens.slate,
                  fontSize: 13.5,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
        if (onOpenFind != null) ...[
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 58,
            child: FilledButton(
              onPressed: onOpenFind,
              style: FilledButton.styleFrom(
                backgroundColor: MimiCamDesignTokens.pink,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
              child: Text(
                strings.ui('findAndConnectRoom'),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _ClientWatchSummary extends StatelessWidget {
  const _ClientWatchSummary({required this.onWatch});

  final VoidCallback onWatch;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return SizedBox(
      width: double.infinity,
      height: 58,
      child: FilledButton(
        onPressed: onWatch,
        style: FilledButton.styleFrom(
          backgroundColor: MimiCamDesignTokens.pink,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
        ),
        child: Text(
          strings.ui('openLiveWatch'),
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
        ),
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
    final strings = AppStrings.of(context);
    return Column(
      children: [
        _ConnectionActionCard(
          icon: Icons.qr_code_2_rounded,
          title: strings.ui('scanQr'),
          text: strings.ui('scanQrSecurely'),
          backgroundColor: MimiCamDesignTokens.mintSoft,
          onTap: onScanQr,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 22),
          child: Row(
            children: [
              const Expanded(child: Divider(color: Color(0xFFE8DCD6))),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  strings.ui('or'),
                  style: const TextStyle(
                    color: MimiCamDesignTokens.slate,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Expanded(child: Divider(color: Color(0xFFE8DCD6))),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: MimiCamDesignTokens.cardDecoration(
            dark: false,
          ).copyWith(color: const Color(0xFFFFFBF7)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const CircleAvatar(
                    radius: 32,
                    backgroundColor: Colors.white,
                    child: Icon(
                      Icons.link_rounded,
                      color: MimiCamDesignTokens.nightPlum,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          strings.ui('manualIpConnectTitle'),
                          style: MimiCamDesignTokens.cardTitle,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          strings.ui('manualIpConnectText'),
                          style: const TextStyle(
                            color: MimiCamDesignTokens.slate,
                            fontSize: 14,
                            height: 1.25,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: manualIpController,
                keyboardType: TextInputType.url,
                decoration: InputDecoration(
                  labelText: strings.ui('ipOrHostPort'),
                  hintText: '192.168.1.20:8080',
                  filled: true,
                  fillColor: Colors.white,
                  suffixIcon: IconButton.filled(
                    onPressed: onManualConnect,
                    style: IconButton.styleFrom(
                      backgroundColor: MimiCamDesignTokens.pink,
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.arrow_forward_rounded),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: const BorderSide(color: Color(0xFFE8DCD6)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: const BorderSide(color: Color(0xFFE8DCD6)),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: onManualConnect,
                  icon: const Icon(Icons.link_rounded),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: MimiCamDesignTokens.nightPlum,
                    side: const BorderSide(color: Color(0xFFE8DCD6)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  label: Text(
                    strings.ui('connectWithIp'),
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        _PrivacyNote(text: strings.ui('localNetworkPrivacyNote')),
      ],
    );
  }
}

class _ConnectionActionCard extends StatelessWidget {
  const _ConnectionActionCard({
    required this.icon,
    required this.title,
    required this.text,
    required this.backgroundColor,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String text;
  final Color backgroundColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: MimiCamDesignTokens.cardDecoration().copyWith(
            color: backgroundColor,
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 34,
                backgroundColor: Colors.white.withValues(alpha: .55),
                child: Icon(
                  icon,
                  color: MimiCamDesignTokens.nightPlum,
                  size: 30,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: MimiCamDesignTokens.cardTitle),
                    const SizedBox(height: 8),
                    Text(
                      text,
                      style: const TextStyle(
                        color: MimiCamDesignTokens.slate,
                        fontSize: 14,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: MimiCamDesignTokens.nightPlum,
                size: 28,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PrivacyNote extends StatelessWidget {
  const _PrivacyNote({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: MimiCamDesignTokens.cardDecoration().copyWith(
        color: MimiCamDesignTokens.amberSoft,
      ),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 20,
            backgroundColor: Colors.white,
            child: Icon(
              Icons.shield_outlined,
              color: MimiCamDesignTokens.nightPlum,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: MimiCamDesignTokens.slate,
                fontSize: 13.5,
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NotificationFilterBar extends StatelessWidget {
  const _NotificationFilterBar();

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _FilterChip(text: strings.ui('all'), active: true),
          const SizedBox(width: 10),
          _FilterChip(text: strings.ui('motion'), active: false),
          const SizedBox(width: 10),
          _FilterChip(text: strings.ui('audio'), active: false),
          const SizedBox(width: 10),
          _FilterChip(text: strings.ui('system'), active: false),
        ],
      ),
    );
  }
}

class _NotificationList extends StatelessWidget {
  const _NotificationList();

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final items = _parentNotificationSpecs(strings);

    return Column(
      children: [
        for (final item in items) ...[
          _NotificationCard(item),
          if (item != items.last) const SizedBox(height: 10),
        ],
      ],
    );
  }
}

List<_NotificationSpec> _parentNotificationSpecs(AppStrings strings) {
  // Demo parent feed items stay data-only so the screen build tree does not
  // need to change when real alert history replaces these fixtures.
  return [
    _NotificationSpec(
      Icons.notifications_active_outlined,
      strings.ui('cryDetectedTitle'),
      strings.ui('cryDetectedText'),
      '12:32',
      strings.ui('important'),
      MimiCamDesignTokens.blushSoft,
    ),
    _NotificationSpec(
      Icons.directions_run_rounded,
      strings.ui('motionDetectedTitle'),
      strings.ui('motionDetectedText'),
      '12:28',
      strings.ui('info'),
      const Color(0xFFEFFAF5),
    ),
    _NotificationSpec(
      Icons.nights_stay_rounded,
      strings.ui('temperatureWarningTitle'),
      strings.ui('temperatureWarningText'),
      '11:45',
      strings.ui('warning'),
      const Color(0xFFFFF7E8),
    ),
    _NotificationSpec(
      Icons.wifi_rounded,
      strings.ui('connectionRenewedTitle'),
      strings.ui('connectionRenewedText'),
      '11:30',
      strings.ui('system'),
      const Color(0xFFF1F5FB),
    ),
    _NotificationSpec(
      Icons.water_drop_outlined,
      strings.ui('humidityNormalTitle'),
      strings.ui('humidityNormalText'),
      '10:55',
      strings.ui('info'),
      const Color(0xFFF7EFFB),
    ),
  ];
}

class _NotificationSpec {
  const _NotificationSpec(
    this.icon,
    this.title,
    this.text,
    this.time,
    this.badge,
    this.backgroundColor,
  );

  final IconData icon;
  final String title;
  final String text;
  final String time;
  final String badge;
  final Color backgroundColor;
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard(this.item);

  final _NotificationSpec item;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: MimiCamDesignTokens.cardDecoration().copyWith(
        color: item.backgroundColor,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: Colors.white,
            child: Icon(item.icon, color: MimiCamDesignTokens.nightPlum),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: const TextStyle(
                    color: MimiCamDesignTokens.nightPlum,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  item.text,
                  style: const TextStyle(
                    color: MimiCamDesignTokens.slate,
                    fontSize: 13.5,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  item.time,
                  style: const TextStyle(
                    color: MimiCamDesignTokens.slate,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
            decoration: const ShapeDecoration(
              color: Colors.white,
              shape: StadiumBorder(),
            ),
            child: Text(
              item.badge,
              style: const TextStyle(
                color: MimiCamDesignTokens.pink,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ClientSettingsList extends StatelessWidget {
  const _ClientSettingsList();

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Column(
      children: [
        _SettingsRow(
          icon: Icons.notifications_none_rounded,
          title: strings.ui('navNotifications'),
          text: strings.ui('notificationsManageText'),
          backgroundColor: MimiCamDesignTokens.blushSoft,
          trailing: const Icon(Icons.chevron_right_rounded),
        ),
        const SizedBox(height: 12),
        _SettingsRow(
          icon: Icons.language_rounded,
          title: strings.ui('language'),
          text: strings.ui('languageSelectText'),
          backgroundColor: MimiCamDesignTokens.mintSoft,
          trailing: Text(
            strings.ui('turkishShort'),
            style: const TextStyle(
              color: Color(0xFF4CB89E),
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(height: 12),
        _SettingsRow(
          icon: Icons.nights_stay_rounded,
          title: strings.ui('keepDeviceAwake'),
          text: strings.ui('keepAwakeClientText'),
          backgroundColor: MimiCamDesignTokens.lavenderSoft,
          trailing: Switch(
            value: true,
            activeThumbColor: Colors.white,
            activeTrackColor: const Color(0xFF51C796),
            onChanged: (_) {},
          ),
        ),
        const SizedBox(height: 28),
        _PrivacyNote(text: strings.ui('serverSettingsHiddenText')),
      ],
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.icon,
    required this.title,
    required this.text,
    required this.backgroundColor,
    required this.trailing,
  });

  final IconData icon;
  final String title;
  final String text;
  final Color backgroundColor;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: MimiCamDesignTokens.cardDecoration().copyWith(
        color: backgroundColor,
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: Colors.white.withValues(alpha: .72),
            child: Icon(icon, color: MimiCamDesignTokens.nightPlum),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: MimiCamDesignTokens.cardTitle),
                const SizedBox(height: 6),
                Text(
                  text,
                  style: const TextStyle(
                    color: MimiCamDesignTokens.slate,
                    fontSize: 13.5,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          trailing,
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.text, required this.active});

  final String text;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: ShapeDecoration(
        color: active ? MimiCamDesignTokens.pink : Colors.white,
        shape: StadiumBorder(
          side: BorderSide(
            color: active ? MimiCamDesignTokens.pink : const Color(0xFFE8DCD6),
            width: 2,
          ),
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: active ? Colors.white : MimiCamDesignTokens.nightPlum,
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
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
