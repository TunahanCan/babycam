part of '../client_home_screen.dart';

enum _ClientHomeTab { watch, find, history, settings }

class _ClientFindSection extends StatefulWidget {
  const _ClientFindSection({
    super.key,
    required this.activeRole,
    required this.onRoleSelected,
    required this.switchingRole,
    required this.runtime,
    required this.onScanQr,
    required this.onManualConnect,
    required this.onConnectDiscovered,
  });

  final AppRole activeRole;
  final ValueChanged<AppRole> onRoleSelected;
  final bool switchingRole;
  final ClientRuntime runtime;
  final VoidCallback onScanQr;
  final ValueChanged<String> onManualConnect;
  final ValueChanged<MiuCamDiscoveredService> onConnectDiscovered;

  @override
  State<_ClientFindSection> createState() => _ClientFindSectionState();
}

class _ClientFindSectionState extends State<_ClientFindSection> {
  final _manualIpController = TextEditingController();

  @override
  void dispose() {
    _manualIpController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return _ClientTabFrame(
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
          onScanQr: widget.onScanQr,
          manualIpController: _manualIpController,
          onManualConnect: () =>
              widget.onManualConnect(_manualIpController.text),
        ),
        const SizedBox(height: 14),
        StreamBuilder<List<MiuCamDiscoveredService>>(
          stream: widget.runtime.discoveryUpdates,
          initialData: widget.runtime.discoveredServices,
          builder: (context, snapshot) => _DiscoveredRoomsCard(
            services: snapshot.data ?? const [],
            onRefresh: widget.runtime.startDiscovery,
            onConnect: widget.onConnectDiscovered,
          ),
        ),
      ],
    );
  }
}

class _ClientNotificationSection extends StatefulWidget {
  const _ClientNotificationSection({
    super.key,
    required this.activeRole,
    required this.onRoleSelected,
    required this.switchingRole,
    required this.runtime,
    required this.onWatch,
  });

  final AppRole activeRole;
  final ValueChanged<AppRole> onRoleSelected;
  final bool switchingRole;
  final ClientRuntime runtime;
  final VoidCallback? onWatch;

  @override
  State<_ClientNotificationSection> createState() =>
      _ClientNotificationSectionState();
}

class _ClientNotificationSectionState
    extends State<_ClientNotificationSection> {
  _AlertFilter _filter = _AlertFilter.all;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return _ClientTabFrame(
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
        _NotificationFilterBar(
          selected: _filter,
          onChanged: (filter) => setState(() => _filter = filter),
        ),
        const SizedBox(height: 14),
        StreamBuilder<List<AlertEventDto>>(
          stream: widget.runtime.alertUpdates,
          initialData: widget.runtime.alerts,
          builder: (context, snapshot) => _NotificationList(
            alerts: snapshot.data ?? const [],
            filter: _filter,
            onWatch: widget.onWatch,
          ),
        ),
      ],
    );
  }
}

List<MiuCamBottomNavItem> _clientNavItems(BuildContext context) {
  final strings = AppStrings.of(context);
  return [
    MiuCamBottomNavItem(
        icon: Icons.live_tv_rounded, label: strings.ui('navWatch')),
    MiuCamBottomNavItem(
        icon: Icons.radar_rounded, label: strings.ui('navFind')),
    MiuCamBottomNavItem(
        icon: Icons.notifications_active_rounded,
        label: strings.ui('navNotifications')),
    MiuCamBottomNavItem(
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
      padding: MiuCamDesignTokens.screenPadding.copyWith(top: 6, bottom: 18),
      children: [
        Align(
          alignment: Alignment.topRight,
          child: MiuCamRoleBadge(
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
    final connected = paired &&
        (phase == ClientRuntimePhase.pairedIdle ||
            phase == ClientRuntimePhase.watching ||
            phase == ClientRuntimePhase.alertOnly);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _TinyLabel(strings.ui('parentPriority')),
        const SizedBox(height: 10),
        Text(
          strings.ui('babyRoomHeader'),
          style: const TextStyle(
            color: MiuCamDesignTokens.slate,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          connected
              ? strings.ui('roomConnectedTitle')
              : _titleFor(strings, phase),
          style: const TextStyle(
            color: MiuCamDesignTokens.nightPlum,
            fontSize: 26,
            height: 1.08,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          connected
              ? strings.ui('liveAndAlertsParentText')
              : _subtitleFor(strings, phase),
          style: const TextStyle(
            color: MiuCamDesignTokens.slate,
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

  static String _subtitleFor(
    AppStrings strings,
    ClientRuntimePhase phase,
  ) {
    return switch (phase) {
      ClientRuntimePhase.reconnecting ||
      ClientRuntimePhase.offline =>
        strings.ui('clientSubtitleOffline'),
      ClientRuntimePhase.revoked ||
      ClientRuntimePhase.error =>
        strings.ui('clientSubtitleError'),
      ClientRuntimePhase.watching ||
      ClientRuntimePhase.alertOnly =>
        strings.ui('clientSubtitleWatching'),
      _ => strings.ui('clientSubtitleDefault'),
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
            color: MiuCamDesignTokens.navy,
            fontSize: 22,
            height: 1.12,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: const TextStyle(
            color: MiuCamDesignTokens.slate,
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
    required this.tone,
    required this.alertsActive,
    required this.alertsConnected,
    required this.systemNotificationsEnabled,
    this.broadcastLocked = false,
    this.onWatch,
  });

  final String title;
  final String status;
  final Color tone;
  final bool alertsActive;
  final bool alertsConnected;
  final bool? systemNotificationsEnabled;
  final bool broadcastLocked;
  final VoidCallback? onWatch;

  @override
  Widget build(BuildContext context) {
    final alertsReady = !broadcastLocked && alertsActive && alertsConnected;
    final alertsReconnecting =
        !broadcastLocked && alertsActive && !alertsConnected;
    final inAppOnly = alertsReady && systemNotificationsEnabled == false;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: MiuCamDesignTokens.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: tone,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.child_care_rounded,
                  color: MiuCamDesignTokens.navy,
                  size: 25,
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
                        color: MiuCamDesignTokens.navy,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      status,
                      style: const TextStyle(
                        color: MiuCamDesignTokens.slate,
                        fontSize: 13.5,
                      ),
                    ),
                  ],
                ),
              ),
              if (onWatch != null)
                IconButton.filledTonal(
                  onPressed: onWatch,
                  tooltip: AppStrings.of(context).ui('openLiveWatch'),
                  icon: const Icon(Icons.play_arrow_rounded),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: inAppOnly
                  ? MiuCamDesignTokens.amberSoft
                  : alertsReady
                      ? MiuCamDesignTokens.mintSoft
                      : alertsReconnecting
                          ? MiuCamDesignTokens.amberSoft
                          : MiuCamDesignTokens.lavenderSoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  broadcastLocked
                      ? Icons.lock_outline_rounded
                      : inAppOnly
                          ? Icons.notifications_none_rounded
                          : alertsReady
                              ? Icons.notifications_active_rounded
                              : alertsReconnecting
                                  ? Icons.sync_rounded
                                  : Icons.notifications_off_outlined,
                  color: inAppOnly
                      ? MiuCamDesignTokens.amber
                      : alertsReady
                          ? MiuCamDesignTokens.mint
                          : alertsReconnecting
                              ? MiuCamDesignTokens.amber
                              : MiuCamDesignTokens.pink,
                  size: 19,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    broadcastLocked
                        ? AppStrings.of(context)
                            .ui('broadcastAccessRemoteLockedBody')
                        : inAppOnly
                            ? AppStrings.of(context)
                                .ui('notificationsInAppOnly')
                            : alertsReady
                                ? AppStrings.of(context).ui('alertConnectionOn')
                                : alertsReconnecting
                                    ? AppStrings.of(context)
                                        .ui('clientTitleReconnecting')
                                    : AppStrings.of(context)
                                        .ui('notificationsOff'),
                    style: const TextStyle(
                      color: MiuCamDesignTokens.navy,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const Icon(
                  Icons.lock_outline_rounded,
                  color: MiuCamDesignTokens.slate,
                  size: 17,
                ),
              ],
            ),
          ),
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
          decoration: MiuCamDesignTokens.cardDecoration(),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 128,
                height: 104,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: MiuCamDesignTokens.pink.withValues(alpha: .55),
                    width: 2,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Center(
                  child: Icon(
                    Icons.favorite_rounded,
                    color: MiuCamDesignTokens.pink,
                    size: 28,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                strings.ui('chooseRoomFirst'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: MiuCamDesignTokens.nightPlum,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                strings.ui('noRoomCalmText'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: MiuCamDesignTokens.slate,
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
                backgroundColor: MiuCamDesignTokens.pink,
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
          backgroundColor: MiuCamDesignTokens.pink,
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
          backgroundColor: MiuCamDesignTokens.mintSoft,
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
                    color: MiuCamDesignTokens.slate,
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
          decoration: MiuCamDesignTokens.cardDecoration(
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
                      color: MiuCamDesignTokens.nightPlum,
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
                          style: MiuCamDesignTokens.cardTitle,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          strings.ui('manualIpConnectText'),
                          style: const TextStyle(
                            color: MiuCamDesignTokens.slate,
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
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => onManualConnect(),
                decoration: InputDecoration(
                  labelText: strings.ui('ipOrHostPort'),
                  hintText: '192.168.1.20:8080',
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton.tonalIcon(
                  onPressed: onManualConnect,
                  icon: const Icon(Icons.link_rounded),
                  style: FilledButton.styleFrom(
                    foregroundColor: MiuCamDesignTokens.nightPlum,
                    backgroundColor: MiuCamDesignTokens.blushSoft,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
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

class _DiscoveredRoomsCard extends StatelessWidget {
  const _DiscoveredRoomsCard({
    required this.services,
    required this.onRefresh,
    required this.onConnect,
  });

  final List<MiuCamDiscoveredService> services;
  final Future<void> Function() onRefresh;
  final ValueChanged<MiuCamDiscoveredService> onConnect;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: MiuCamDesignTokens.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.wifi_find_rounded,
                color: MiuCamDesignTokens.pink,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  strings.ui('discoveredRoomsTitle'),
                  style: MiuCamDesignTokens.cardTitle,
                ),
              ),
              IconButton(
                tooltip: strings.ui('refreshDiscovery'),
                onPressed: () => onRefresh().catchError((_) {}),
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            services.isEmpty
                ? strings.ui('noRoomsDiscovered')
                : strings.ui('discoveredRoomsSubtitle'),
            style: const TextStyle(
              color: MiuCamDesignTokens.slate,
              fontSize: 13.5,
            ),
          ),
          if (services.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (final service in services) ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const CircleAvatar(
                  backgroundColor: MiuCamDesignTokens.mintSoft,
                  child: Icon(
                    Icons.child_care_rounded,
                    color: MiuCamDesignTokens.navy,
                  ),
                ),
                title: Text(
                  localizedRoomName(strings, service.name),
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                subtitle: Text(
                  '${service.authority}'
                  '${service.webRtcAvailable ? ' · WebRTC' : ''}',
                ),
                trailing: FilledButton(
                  onPressed: () => onConnect(service),
                  child: Text(strings.ui('connectDiscoveredRoom')),
                ),
              ),
              if (service != services.last) const Divider(height: 1),
            ],
          ],
        ],
      ),
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
          decoration: MiuCamDesignTokens.cardDecoration().copyWith(
            color: backgroundColor,
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 34,
                backgroundColor: Colors.white.withValues(alpha: .55),
                child: Icon(
                  icon,
                  color: MiuCamDesignTokens.nightPlum,
                  size: 30,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: MiuCamDesignTokens.cardTitle),
                    const SizedBox(height: 8),
                    Text(
                      text,
                      style: const TextStyle(
                        color: MiuCamDesignTokens.slate,
                        fontSize: 14,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: MiuCamDesignTokens.nightPlum,
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
      decoration: MiuCamDesignTokens.cardDecoration().copyWith(
        color: MiuCamDesignTokens.amberSoft,
      ),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 20,
            backgroundColor: Colors.white,
            child: Icon(
              Icons.shield_outlined,
              color: MiuCamDesignTokens.nightPlum,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: MiuCamDesignTokens.slate,
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
