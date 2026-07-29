import 'dart:async';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../app/app_role.dart';
import '../../core/network/lan_endpoint.dart';
import '../../core/protocol/alert_event_dto.dart';
import '../../core/protocol/pairing_payload.dart';
import '../../l10n/app_strings.dart';
import '../../services/client_preferences_service.dart';
import '../../services/discovery/miucam_service_discovery.dart';
import '../../services/notification_service.dart';
import '../shared/presentation/miucam_design_tokens.dart';
import '../shared/presentation/miucam_shells.dart';
import 'client_runtime.dart';
import 'media/watch_screen.dart';
import 'pairing/client_pairing_flow.dart';
import 'pairing/pairing_failure.dart';
import 'pairing/pairing_payload_gateway.dart';
import 'pairing/qr_scan_screen.dart';

part 'presentation/client_home_components.dart';
part 'presentation/client_home_notifications.dart';
part 'presentation/client_home_settings.dart';

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
  late _ClientHomeTab _tab;
  late bool _keepScreenAwake;
  Locale? _selectedLocale;
  StreamSubscription<String>? _notificationTapSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tab = _ClientHomeTab.values[widget.initialTab.clamp(0, 3)];
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
    if (_tab != _ClientHomeTab.history) {
      setState(() => _tab = _ClientHomeTab.history);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _notificationTapSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: MiuCamGradientShell(
        variant: MiuCamShellVariant.client,
        child: SafeArea(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            transitionBuilder: _hardWipe,
            child: _tab == _ClientHomeTab.watch
                ? StreamBuilder<ClientRuntimeState>(
                    key: const ValueKey('client-watch-runtime'),
                    stream: widget.runtime.states,
                    initialData: widget.runtime.currentState,
                    builder: (context, snapshot) =>
                        _buildTab(context, snapshot.data!),
                  )
                : _buildTab(context, widget.runtime.currentState),
          ),
        ),
      ),
      bottomNavigationBar: MiuCamBottomNav(
        items: _clientNavItems(context),
        currentIndex: _tab.index,
        activeColor: MiuCamDesignTokens.pink,
        onTap: (index) => setState(
          () => _tab = _ClientHomeTab.values[index],
        ),
      ),
    );
  }

  Widget _buildTab(BuildContext context, ClientRuntimeState state) {
    final strings = AppStrings.of(context);
    final watchAvailable =
        state.session != null && state.phase != ClientRuntimePhase.revoked;
    return switch (_tab) {
      _ClientHomeTab.watch => _ClientTabFrame(
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
              _NoRoomCard(
                onOpenFind: () => setState(() => _tab = _ClientHomeTab.find),
              )
            else ...[
              _RoomCard(
                title: state.session!.payload.deviceName,
                status: _clientRoomStatus(strings, state.phase),
                tone: _clientRoomTone(state.phase),
                alertsActive: state.alertsActive,
                alertsConnected: widget.runtime.alertTransportConnected,
                systemNotificationsEnabled:
                    widget.runtime.systemNotificationsEnabled,
                onWatch:
                    watchAvailable ? () => _openWatch(context, state) : null,
              ),
              if (watchAvailable) ...[
                const SizedBox(height: 16),
                _ClientWatchSummary(onWatch: () => _openWatch(context, state)),
              ],
            ],
          ],
        ),
      _ClientHomeTab.find => _ClientFindSection(
          key: const ValueKey('client-find'),
          activeRole: widget.activeRole,
          onRoleSelected: widget.onRoleSelected,
          switchingRole: widget.switchingRole,
          runtime: widget.runtime,
          onScanQr: () => _scanQr(context),
          onManualConnect: (address) => _connectManualIp(context, address),
          onConnectDiscovered: (service) =>
              _connectDiscoveredService(context, service),
        ),
      _ClientHomeTab.history => _ClientNotificationSection(
          key: const ValueKey('client-history'),
          activeRole: widget.activeRole,
          onRoleSelected: widget.onRoleSelected,
          switchingRole: widget.switchingRole,
          runtime: widget.runtime,
          onWatch: state.session == null
              ? null
              : () => _openWatch(context, widget.runtime.currentState),
        ),
      _ClientHomeTab.settings => _ClientTabFrame(
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
              onNotificationsTap: () =>
                  setState(() => _tab = _ClientHomeTab.history),
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

  String _clientRoomStatus(
    AppStrings strings,
    ClientRuntimePhase phase,
  ) {
    return switch (phase) {
      ClientRuntimePhase.pairedIdle ||
      ClientRuntimePhase.watching ||
      ClientRuntimePhase.alertOnly =>
        strings.ui('pairedWithQr'),
      ClientRuntimePhase.scanningQr => strings.ui('clientTitleScanningQr'),
      ClientRuntimePhase.pairing => strings.ui('clientTitlePairing'),
      ClientRuntimePhase.renewingToken =>
        strings.ui('clientTitleRenewingToken'),
      ClientRuntimePhase.reconnecting => strings.ui('clientTitleReconnecting'),
      ClientRuntimePhase.offline => strings.ui('clientTitleOffline'),
      ClientRuntimePhase.revoked => strings.ui('clientTitleRevoked'),
      ClientRuntimePhase.error => strings.ui('clientTitleError'),
      ClientRuntimePhase.unpaired => strings.ui('clientTitleUnpaired'),
    };
  }

  Color _clientRoomTone(ClientRuntimePhase phase) {
    return switch (phase) {
      ClientRuntimePhase.pairedIdle ||
      ClientRuntimePhase.watching ||
      ClientRuntimePhase.alertOnly =>
        MiuCamDesignTokens.mint,
      ClientRuntimePhase.renewingToken ||
      ClientRuntimePhase.reconnecting ||
      ClientRuntimePhase.offline =>
        MiuCamDesignTokens.amberSoft,
      ClientRuntimePhase.revoked ||
      ClientRuntimePhase.error =>
        MiuCamDesignTokens.blushSoft,
      ClientRuntimePhase.unpaired ||
      ClientRuntimePhase.scanningQr ||
      ClientRuntimePhase.pairing =>
        MiuCamDesignTokens.lavenderSoft,
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
      setState(() => _tab = _ClientHomeTab.watch);
      _showMessage(context,
          strings.uiFormat('pairedMessage', {'name': payload.deviceName}));
    } catch (error) {
      if (!context.mounted) return;
      _showMessage(context, _pairingFailureMessage(strings, error));
    }
  }

  Future<void> _connectManualIp(
    BuildContext context,
    String manualAddress,
  ) async {
    final strings = AppStrings.of(context);
    final parsed = _parseManualAddress(manualAddress);
    if (parsed == null) {
      _showMessage(context, strings.ui('invalidIpFormat'));
      return;
    }
    try {
      final payload = await _fetchManualPairingPayload(parsed);
      await ClientPairingFlow(widget.runtime).pairAndArmAlerts(payload);
      if (!context.mounted) return;
      setState(() => _tab = _ClientHomeTab.watch);
      _showMessage(context,
          strings.uiFormat('pairedMessage', {'name': payload.deviceName}));
    } catch (error) {
      if (!context.mounted) return;
      _showMessage(context, _pairingFailureMessage(strings, error));
    }
  }

  Future<void> _connectDiscoveredService(
    BuildContext context,
    MiuCamDiscoveredService service,
  ) async {
    final strings = AppStrings.of(context);
    try {
      final payload = await _fetchManualPairingPayload(
        (host: service.host, port: service.port),
      );
      await ClientPairingFlow(widget.runtime).pairAndArmAlerts(payload);
      if (!context.mounted) return;
      setState(() => _tab = _ClientHomeTab.watch);
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
                style: MiuCamDesignTokens.cardTitle),
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
