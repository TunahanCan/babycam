import 'dart:async';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../app/app_role.dart';
import '../../core/network/lan_endpoint.dart';
import '../../core/protocol/alert_event_dto.dart';
import '../../core/protocol/pairing_payload.dart';
import '../../l10n/app_strings.dart';
import '../../services/client_preferences_service.dart';
import '../../services/discovery/mimicam_service_discovery.dart';
import '../../services/notification_service.dart';
import '../shared/presentation/mimicam_design_tokens.dart';
import '../shared/presentation/mimicam_shells.dart';
import 'client_runtime.dart';
import 'media/watch_screen.dart';
import 'pairing/client_pairing_flow.dart';
import 'pairing/pairing_failure.dart';
import 'pairing/pairing_payload_gateway.dart';
import 'pairing/qr_scan_screen.dart';

class ClientHomeScreen extends StatefulWidget {
  const ClientHomeScreen({
    super.key,
    required this.runtime,
    required this.activeRole,
    required this.onRoleSelected,
    this.switchingRole = false,
    this.initialTab = 0,
    this.preferences,
    this.selectedLocale,
    this.onLocaleChanged,
    this.notificationTapStream,
    this.pairingPayloadGateway = const HttpPairingPayloadGateway(),
  });

  final ClientRuntime runtime;
  final AppRole activeRole;
  final ValueChanged<AppRole> onRoleSelected;
  final bool switchingRole;
  final int initialTab;
  final ClientPreferencesService? preferences;
  final Locale? selectedLocale;
  final ValueChanged<Locale?>? onLocaleChanged;
  final Stream<String>? notificationTapStream;
  final PairingPayloadGateway pairingPayloadGateway;

  @override
  State<ClientHomeScreen> createState() => _ClientHomeScreenState();
}

class _ClientHomeScreenState extends State<ClientHomeScreen>
    with WidgetsBindingObserver {
  final _manualIpController = TextEditingController();
  late int _tab;
  late bool _keepScreenAwake;
  Locale? _selectedLocale;
  StreamSubscription<String>? _notificationTapSubscription;
  _AlertFilter _alertFilter = _AlertFilter.all;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tab = widget.initialTab.clamp(0, 3);
    _keepScreenAwake = widget.preferences?.keepScreenAwake ?? true;
    _selectedLocale = widget.selectedLocale ?? widget.preferences?.locale;
    _notificationTapSubscription =
        (widget.notificationTapStream ?? NotificationService.notificationTaps)
            .listen(_openNotificationTab);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await NotificationService.refreshLaunchTap();
      if (!mounted) return;
      final pendingTap = NotificationService.takePendingTap();
      if (pendingTap != null) _openNotificationTab(pendingTap);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(NotificationService.refreshLaunchTap());
      unawaited(_resumeAlertDelivery());
    }
  }

  Future<void> _resumeAlertDelivery() async {
    final state = widget.runtime.currentState;
    if (state.session == null) return;
    // This is important on iOS: a user who enables notifications in Settings
    // should not need to pair the room again before alert delivery resumes.
    await widget.runtime.startAlertListening().catchError((_) => false);
  }

  void _openNotificationTab(String payload) {
    if (!payload.startsWith(NotificationService.alertsPayload)) return;
    NotificationService.takePendingTap();
    if (!mounted) return;
    Navigator.maybeOf(context)?.popUntil((route) => route.isFirst);
    if (_tab != 2) setState(() => _tab = 2);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _notificationTapSubscription?.cancel();
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
              _RoomCard(
                title: state.session!.payload.deviceName,
                status: strings.ui('pairedWithQr'),
                tone: MimiCamDesignTokens.mint,
                alertsActive: state.alertsActive,
                alertsConnected: widget.runtime.alertTransportConnected,
                systemNotificationsEnabled:
                    widget.runtime.systemNotificationsEnabled,
                onWatch: () => _openWatch(context, state),
              ),
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
            const SizedBox(height: 14),
            StreamBuilder<List<MimiCamDiscoveredService>>(
              stream: widget.runtime.discoveryUpdates,
              initialData: widget.runtime.discoveredServices,
              builder: (context, snapshot) => _DiscoveredRoomsCard(
                services: snapshot.data ?? const [],
                onRefresh: widget.runtime.startDiscovery,
                onConnect: (service) =>
                    _connectDiscoveredService(context, service),
              ),
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
            _NotificationFilterBar(
              selected: _alertFilter,
              onChanged: (filter) => setState(() => _alertFilter = filter),
            ),
            const SizedBox(height: 14),
            StreamBuilder<List<AlertEventDto>>(
              stream: widget.runtime.alertUpdates,
              initialData: widget.runtime.alerts,
              builder: (context, snapshot) => _NotificationList(
                alerts: snapshot.data ?? const [],
                filter: _alertFilter,
                onWatch: state.session == null
                    ? null
                    : () => _openWatch(context, state),
              ),
            ),
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
            _ClientSettingsList(
              onNotificationsTap: () => setState(() => _tab = 2),
              onOpenSystemSettings: openAppSettings,
              onLanguageTap: _showLanguagePicker,
              languageLabel: _languageLabel(context),
              keepScreenAwake: _keepScreenAwake,
              onKeepScreenAwakeChanged: _setKeepScreenAwake,
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
      _showMessage(context, _pairingFailureMessage(strings, error));
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
      final payload = await _fetchManualPairingPayload(parsed);
      await ClientPairingFlow(widget.runtime).pairAndArmAlerts(payload);
      if (!context.mounted) return;
      setState(() => _tab = 0);
      _showMessage(context,
          strings.uiFormat('pairedMessage', {'name': payload.deviceName}));
    } catch (error) {
      if (!context.mounted) return;
      _showMessage(context, _pairingFailureMessage(strings, error));
    }
  }

  Future<void> _connectDiscoveredService(
    BuildContext context,
    MimiCamDiscoveredService service,
  ) async {
    final strings = AppStrings.of(context);
    try {
      final payload = await _fetchManualPairingPayload(
        (host: service.host, port: service.port),
      );
      await ClientPairingFlow(widget.runtime).pairAndArmAlerts(payload);
      if (!context.mounted) return;
      setState(() => _tab = 0);
      _showMessage(
        context,
        strings.uiFormat('pairedMessage', {'name': payload.deviceName}),
      );
    } catch (error) {
      if (!context.mounted) return;
      _showMessage(context, _pairingFailureMessage(strings, error));
    }
  }

  String _pairingFailureMessage(AppStrings strings, Object error) {
    if (error is PairingFailure) {
      return strings.pairingFailureMessage(error.code.name);
    }
    return strings.uiFormat('pairingFailed', {'error': error});
  }

  Future<PairingPayload> _fetchManualPairingPayload(
    ({String host, int port}) address,
  ) =>
      widget.pairingPayloadGateway.fetch(
        host: address.host,
        port: address.port,
      );

  ({String host, int port})? _parseManualAddress(String value) {
    final endpoint = LanEndpoint.parse(value);
    return endpoint == null ? null : (host: endpoint.host, port: endpoint.port);
  }

  void _openWatch(BuildContext context, ClientRuntimeState state) {
    if (state.session == null) {
      _showMessage(context, AppStrings.of(context).ui('scanServerQrFirst'));
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WatchScreen(
          runtime: widget.runtime,
          keepScreenAwake: _keepScreenAwake,
          onKeepScreenAwakeChanged: _setKeepScreenAwake,
        ),
      ),
    );
  }

  Future<void> _setKeepScreenAwake(bool enabled) async {
    if (_keepScreenAwake == enabled) return;
    setState(() => _keepScreenAwake = enabled);
    await widget.preferences?.setKeepScreenAwake(enabled);
  }

  String _languageLabel(BuildContext context) {
    final strings = AppStrings.of(context);
    if (_selectedLocale == null) return strings.ui('systemLanguageShort');
    return _localeName(_selectedLocale!);
  }

  Future<void> _showLanguagePicker() async {
    final strings = AppStrings.of(context);
    final selectedTag = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
          children: [
            Text(strings.ui('chooseLanguage'),
                style: MimiCamDesignTokens.cardTitle),
            const SizedBox(height: 8),
            ListTile(
              title: Text(strings.ui('systemLanguage')),
              subtitle: Text(strings.ui('systemLanguageDescription')),
              trailing: _selectedLocale == null
                  ? const Icon(Icons.check_circle_rounded)
                  : null,
              onTap: () => Navigator.of(context).pop('system'),
            ),
            for (final locale in AppStrings.supportedLocales)
              ListTile(
                title: Text(_localeName(locale)),
                trailing:
                    _selectedLocale?.toLanguageTag() == locale.toLanguageTag()
                        ? const Icon(Icons.check_circle_rounded)
                        : null,
                onTap: () => Navigator.of(context).pop(locale.toLanguageTag()),
              ),
          ],
        ),
      ),
    );
    if (!mounted || selectedTag == null) return;
    final selected = selectedTag == 'system'
        ? null
        : AppStrings.supportedLocales.firstWhere(
            (locale) => locale.toLanguageTag() == selectedTag,
          );
    if (selected == _selectedLocale) return;
    setState(() => _selectedLocale = selected);
    await widget.preferences?.setLocale(selected);
    if (!mounted) return;
    widget.onLocaleChanged?.call(selected);
  }

  static String _localeName(Locale locale) {
    if (locale.languageCode == 'ar') {
      return locale.countryCode == 'QA'
          ? 'العربية (قطر)'
          : 'العربية (السعودية)';
    }
    return switch (locale.languageCode) {
      'tr' => 'Türkçe',
      'en' => 'English (United States)',
      'zh' => '中文',
      'hi' => 'हिन्दी',
      'es' => 'Español',
      'fr' => 'Français',
      'de' => 'Deutsch',
      _ => locale.toLanguageTag(),
    };
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
          strings.ui('babyRoomHeader'),
          style: const TextStyle(
            color: MimiCamDesignTokens.slate,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          paired ? strings.ui('roomConnectedTitle') : _titleFor(strings, phase),
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
    required this.tone,
    required this.alertsActive,
    required this.alertsConnected,
    required this.systemNotificationsEnabled,
    this.onWatch,
  });

  final String title;
  final String status;
  final Color tone;
  final bool alertsActive;
  final bool alertsConnected;
  final bool? systemNotificationsEnabled;
  final VoidCallback? onWatch;

  @override
  Widget build(BuildContext context) {
    final alertsReady = alertsActive && alertsConnected;
    final alertsReconnecting = alertsActive && !alertsConnected;
    final inAppOnly = alertsReady && systemNotificationsEnabled == false;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: MimiCamDesignTokens.cardDecoration(),
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
                  color: MimiCamDesignTokens.navy,
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
                  ? MimiCamDesignTokens.amberSoft
                  : alertsReady
                      ? MimiCamDesignTokens.mintSoft
                      : alertsReconnecting
                          ? MimiCamDesignTokens.amberSoft
                          : MimiCamDesignTokens.lavenderSoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  inAppOnly
                      ? Icons.notifications_none_rounded
                      : alertsReady
                          ? Icons.notifications_active_rounded
                          : alertsReconnecting
                              ? Icons.sync_rounded
                              : Icons.notifications_off_outlined,
                  color: inAppOnly
                      ? MimiCamDesignTokens.amber
                      : alertsReady
                          ? MimiCamDesignTokens.mint
                          : alertsReconnecting
                              ? MimiCamDesignTokens.amber
                              : MimiCamDesignTokens.pink,
                  size: 19,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    inAppOnly
                        ? AppStrings.of(context).ui('notificationsInAppOnly')
                        : alertsReady
                            ? AppStrings.of(context).ui('notificationsOn')
                            : alertsReconnecting
                                ? AppStrings.of(context)
                                    .ui('clientTitleReconnecting')
                                : AppStrings.of(context).ui('notificationsOff'),
                    style: const TextStyle(
                      color: MimiCamDesignTokens.navy,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const Icon(
                  Icons.lock_outline_rounded,
                  color: MimiCamDesignTokens.slate,
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
                    foregroundColor: MimiCamDesignTokens.nightPlum,
                    backgroundColor: MimiCamDesignTokens.blushSoft,
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

  final List<MimiCamDiscoveredService> services;
  final Future<void> Function() onRefresh;
  final ValueChanged<MimiCamDiscoveredService> onConnect;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: MimiCamDesignTokens.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.wifi_find_rounded,
                color: MimiCamDesignTokens.pink,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  strings.ui('discoveredRoomsTitle'),
                  style: MimiCamDesignTokens.cardTitle,
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
              color: MimiCamDesignTokens.slate,
              fontSize: 13.5,
            ),
          ),
          if (services.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (final service in services) ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const CircleAvatar(
                  backgroundColor: MimiCamDesignTokens.mintSoft,
                  child: Icon(
                    Icons.child_care_rounded,
                    color: MimiCamDesignTokens.navy,
                  ),
                ),
                title: Text(
                  service.name,
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

enum _AlertFilter { all, motion, audio, system }

class _NotificationFilterBar extends StatelessWidget {
  const _NotificationFilterBar({
    required this.selected,
    required this.onChanged,
  });

  final _AlertFilter selected;
  final ValueChanged<_AlertFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _FilterChip(
            text: strings.ui('all'),
            active: selected == _AlertFilter.all,
            onTap: () => onChanged(_AlertFilter.all),
          ),
          const SizedBox(width: 10),
          _FilterChip(
            text: strings.ui('motion'),
            active: selected == _AlertFilter.motion,
            onTap: () => onChanged(_AlertFilter.motion),
          ),
          const SizedBox(width: 10),
          _FilterChip(
            text: strings.ui('audio'),
            active: selected == _AlertFilter.audio,
            onTap: () => onChanged(_AlertFilter.audio),
          ),
          const SizedBox(width: 10),
          _FilterChip(
            text: strings.ui('system'),
            active: selected == _AlertFilter.system,
            onTap: () => onChanged(_AlertFilter.system),
          ),
        ],
      ),
    );
  }
}

class _NotificationList extends StatelessWidget {
  const _NotificationList({
    required this.alerts,
    required this.filter,
    this.onWatch,
  });

  final List<AlertEventDto> alerts;
  final _AlertFilter filter;
  final VoidCallback? onWatch;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final filteredAlerts = alerts
        .where((alert) => _matchesAlertFilter(alert, filter))
        .toList(growable: false)
      ..sort((a, b) => b.timestampMs.compareTo(a.timestampMs));
    final items = filteredAlerts.isEmpty
        ? [_emptyNotificationSpec(strings)]
        : filteredAlerts
            .map((alert) => _notificationSpecFromAlert(strings, alert));

    return Column(
      children: [
        for (final item in items) ...[
          _NotificationCard(item, onWatch: onWatch),
          if (item != items.last) const SizedBox(height: 10),
        ],
      ],
    );
  }
}

bool _matchesAlertFilter(AlertEventDto alert, _AlertFilter filter) {
  if (filter == _AlertFilter.all) return true;
  return switch (filter) {
    _AlertFilter.all => true,
    _AlertFilter.motion => alert.category == AlertCategory.motion,
    _AlertFilter.audio => alert.category == AlertCategory.audio,
    _AlertFilter.system => alert.category == AlertCategory.system,
  };
}

_NotificationSpec _emptyNotificationSpec(AppStrings strings) =>
    _NotificationSpec(
      Icons.notifications_none_rounded,
      strings.ui('waitingLatestStatus'),
      strings.ui('pairedServerAlertAppears'),
      '--:--',
      strings.ui('system'),
      const Color(0xFFF1F5FB),
    );

_NotificationSpec _notificationSpecFromAlert(
  AppStrings strings,
  AlertEventDto alert,
) {
  final family = alert.category;
  return _NotificationSpec(
    switch (family) {
      AlertCategory.motion => Icons.directions_run_rounded,
      AlertCategory.audio => Icons.notifications_active_outlined,
      AlertCategory.system => Icons.wifi_rounded,
    },
    alert.localizedTitle(strings),
    alert.localizedMessage(strings),
    _formatAlertTime(alert.timestampMs),
    _severityLabel(strings, alert.severity),
    switch (family) {
      AlertCategory.motion => const Color(0xFFEFFAF5),
      AlertCategory.audio => MimiCamDesignTokens.blushSoft,
      AlertCategory.system => const Color(0xFFF1F5FB),
    },
  );
}

String _severityLabel(AppStrings strings, String severity) {
  final normalized = severity.toLowerCase();
  if (normalized.contains('critical') || normalized.contains('high')) {
    return strings.ui('important');
  }
  if (normalized.contains('warning') || normalized.contains('medium')) {
    return strings.ui('warning');
  }
  if (normalized.contains('attention')) {
    return strings.ui('important');
  }
  if (normalized.contains('info') || normalized.contains('low')) {
    return strings.ui('info');
  }
  return strings.ui('system');
}

String _formatAlertTime(int timestampMs) {
  final time = DateTime.fromMillisecondsSinceEpoch(timestampMs);
  return '${time.hour.toString().padLeft(2, '0')}:'
      '${time.minute.toString().padLeft(2, '0')}';
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
  const _NotificationCard(this.item, {this.onWatch});

  final _NotificationSpec item;
  final VoidCallback? onWatch;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final decoration = MimiCamDesignTokens.cardDecoration().copyWith(
      color: item.backgroundColor,
    );
    return Semantics(
      button: onWatch != null,
      label: onWatch == null ? item.title : strings.ui('openLiveWatch'),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onWatch,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: decoration,
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
                        onWatch == null
                            ? item.time
                            : '${item.time} · ${strings.ui('openLiveWatch')}',
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
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 11,
                        vertical: 6,
                      ),
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
                    if (onWatch != null) ...[
                      const SizedBox(height: 18),
                      const Icon(
                        Icons.play_circle_fill_rounded,
                        color: MimiCamDesignTokens.pink,
                        size: 22,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ClientSettingsList extends StatelessWidget {
  const _ClientSettingsList({
    required this.onNotificationsTap,
    required this.onOpenSystemSettings,
    required this.onLanguageTap,
    required this.languageLabel,
    required this.keepScreenAwake,
    required this.onKeepScreenAwakeChanged,
  });

  final VoidCallback onNotificationsTap;
  final Future<bool> Function() onOpenSystemSettings;
  final VoidCallback onLanguageTap;
  final String languageLabel;
  final bool keepScreenAwake;
  final ValueChanged<bool> onKeepScreenAwakeChanged;

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
          onTap: onNotificationsTap,
        ),
        const SizedBox(height: 12),
        _SettingsRow(
          icon: Icons.language_rounded,
          title: strings.ui('language'),
          text: strings.ui('languageSelectText'),
          backgroundColor: MimiCamDesignTokens.mintSoft,
          trailing: SizedBox(
            width: 92,
            child: Text(
              languageLabel,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: const TextStyle(
                color: Color(0xFF4CB89E),
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          onTap: onLanguageTap,
        ),
        const SizedBox(height: 12),
        _SettingsRow(
          icon: Icons.nights_stay_rounded,
          title: strings.ui('keepDeviceAwake'),
          text: strings.ui('keepAwakeClientText'),
          backgroundColor: MimiCamDesignTokens.lavenderSoft,
          trailing: Switch(
            value: keepScreenAwake,
            activeThumbColor: Colors.white,
            activeTrackColor: const Color(0xFF51C796),
            onChanged: onKeepScreenAwakeChanged,
          ),
          onTap: () => onKeepScreenAwakeChanged(!keepScreenAwake),
        ),
        const SizedBox(height: 12),
        _SystemNotificationSettingsCard(
            onOpenSystemSettings: onOpenSystemSettings),
        const SizedBox(height: 28),
        _PrivacyNote(text: strings.ui('serverSettingsHiddenText')),
      ],
    );
  }
}

class _SystemNotificationSettingsCard extends StatelessWidget {
  const _SystemNotificationSettingsCard({required this.onOpenSystemSettings});

  final Future<bool> Function() onOpenSystemSettings;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: MimiCamDesignTokens.cardDecoration().copyWith(
        color: MimiCamDesignTokens.lavenderSoft,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CircleAvatar(
            radius: 22,
            backgroundColor: Colors.white,
            child: Icon(
              Icons.notifications_outlined,
              color: MimiCamDesignTokens.pink,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  strings.ui('navNotifications'),
                  style: const TextStyle(
                    color: MimiCamDesignTokens.navy,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  strings.ui('notificationsManageText'),
                  style: const TextStyle(
                    color: MimiCamDesignTokens.slate,
                    fontSize: 13,
                    height: 1.28,
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => unawaited(onOpenSystemSettings()),
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  label: Text(strings.ui('openAppSettings')),
                ),
              ],
            ),
          ),
        ],
      ),
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
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String text;
  final Color backgroundColor;
  final Widget trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Ink(
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
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.text,
    required this.active,
    required this.onTap,
  });

  final String text;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: active,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            decoration: ShapeDecoration(
              color: active ? MimiCamDesignTokens.pink : Colors.white,
              shape: StadiumBorder(
                side: BorderSide(
                  color: active
                      ? MimiCamDesignTokens.pink
                      : const Color(0xFFE2E8F0),
                  width: 1.5,
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
          ),
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
