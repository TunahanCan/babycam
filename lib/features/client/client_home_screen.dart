import 'dart:async';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../app/app_role.dart';
import '../../core/alerts/alert_severity.dart';
import '../../core/network/lan_endpoint.dart';
import '../../core/protocol/alert_event_dto.dart';
import '../../core/protocol/pairing_payload.dart';
import '../../l10n/app_strings.dart';
import '../../services/client_preferences_service.dart';
import '../../services/discovery/miucam_service_discovery.dart';
import '../../services/notification_service.dart';
import '../shared/presentation/miucam_design_tokens.dart';
import '../shared/presentation/miucam_shells.dart';
import '../shared/presentation/localized_time.dart';
import '../shared/presentation/localized_room_name.dart';
import 'client_runtime.dart';
import 'controls/room_audio_detection_notice.dart';
import 'media/watch_screen.dart';
import 'presentation/client_broadcast_access_card.dart';
import 'pairing/client_pairing_flow.dart';
import 'pairing/pairing_failure.dart';
import 'pairing/pairing_code_dialog.dart';
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
  bool _pairingBusy = false;
  bool _watchRouteOpen = false;
  DialogRoute<String>? _pairingCodeRoute;
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
    if (state.session == null || !state.alertsActive) return;
    // This is important on iOS: a user who enables notifications in Settings
    // should not need to pair the room again before alert delivery resumes.
    // Refresh only an armed transport; foregrounding must preserve Alerts Off.
    await widget.runtime.startAlertListening().catchError((_) => false);
  }

  void _openNotificationTab(String payload) {
    final uri = Uri.tryParse(payload);
    if (uri?.scheme != 'miucam' ||
        uri?.host != 'alerts' ||
        (uri?.path.isNotEmpty ?? true)) {
      return;
    }
    NotificationService.takePendingTap();
    if (!mounted) return;
    final alertId = uri!.queryParameters['alertId'];
    // History is drained and cleared when pairing switches rooms. An older
    // notification retained by the OS must not dismiss the new room's watch
    // screen or present that room's history as if it belonged to this alert.
    if (widget.runtime.currentState.phase == ClientRuntimePhase.pairing ||
        (alertId != null &&
            !widget.runtime.alerts.any((alert) => alert.id == alertId))) {
      return;
    }
    Navigator.maybeOf(context)?.popUntil((route) => route.isFirst);
    if (_tab != _ClientHomeTab.history) {
      setState(() => _tab = _ClientHomeTab.history);
    }
  }

  @override
  void didUpdateWidget(covariant ClientHomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.switchingRole || oldWidget.runtime != widget.runtime) {
      _dismissPairingCodeDialog();
    }
  }

  @override
  void dispose() {
    _dismissPairingCodeDialog();
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
    final broadcastLocked = state.broadcastAccess?.isLocked == true;
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
                title: localizedRoomName(
                    strings, state.session!.payload.deviceName),
                status: broadcastLocked
                    ? strings.ui('broadcastAccessLockedTitle')
                    : _clientRoomStatus(strings, state.phase),
                tone: broadcastLocked
                    ? MiuCamDesignTokens.pink
                    : _clientRoomTone(state.phase),
                broadcastLocked: broadcastLocked,
                alertsActive: state.alertsActive,
                alertsConnected: widget.runtime.alertTransportConnected,
                systemNotificationsEnabled:
                    widget.runtime.systemNotificationsEnabled,
                onWatch:
                    watchAvailable ? () => _openWatch(context, state) : null,
              ),
              if (widget.runtime.canManageBroadcastPurchase) ...[
                const SizedBox(height: 16),
                ClientBroadcastAccessCard(runtime: widget.runtime),
              ],
              if (widget.runtime.roomControls != null)
                RoomAudioDetectionNotice(
                  controls: widget.runtime.roomControls!,
                  session: state.session!,
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
          connecting: _pairingBusy,
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

  Future<void> _scanQr(BuildContext context) => _runPairing(
        context,
        () async {
          final code = await Navigator.of(context).push<String>(
            MaterialPageRoute(builder: (_) => const QRScanScreen()),
          );
          if (!context.mounted || code == null) return null;
          final payload = PairingPayload.parseUri(code);
          if (payload == null) {
            _showMessage(context, AppStrings.of(context).ui('invalidQrCode'));
          }
          return payload;
        },
      );

  Future<void> _connectManualIp(
    BuildContext context,
    String manualAddress,
  ) async {
    if (_pairingBusy) return;
    final parsed = _parseManualAddress(manualAddress);
    if (parsed == null) {
      _showMessage(context, AppStrings.of(context).ui('invalidIpFormat'));
      return;
    }
    await _runPairing(
        context, () => _fetchManualPairingPayload(context, parsed));
  }

  Future<void> _connectDiscoveredService(
    BuildContext context,
    MiuCamDiscoveredService service,
  ) =>
      _runPairing(
        context,
        () => _fetchManualPairingPayload(
          context,
          (host: service.host, port: service.port),
        ),
      );

  Future<void> _runPairing(
    BuildContext context,
    Future<PairingPayload?> Function() loadPayload,
  ) async {
    if (_pairingBusy || widget.runtime.isDisposed || widget.switchingRole) {
      return;
    }
    final runtime = widget.runtime;
    final strings = AppStrings.of(context);
    setState(() => _pairingBusy = true);
    try {
      final payload = await loadPayload();
      // A LAN reply can arrive after this screen or its role has closed.
      if (!mounted ||
          !context.mounted ||
          widget.runtime.isDisposed ||
          !identical(widget.runtime, runtime) ||
          widget.switchingRole ||
          payload == null) {
        return;
      }
      await ClientPairingFlow(runtime).pairAndArmAlerts(payload);
      if (!mounted || !context.mounted || widget.runtime.isDisposed) return;
      setState(() => _tab = _ClientHomeTab.watch);
      _showMessage(
        context,
        strings.uiFormat('pairedMessage',
            {'name': localizedRoomName(strings, payload.deviceName)}),
      );
    } catch (error) {
      if (!mounted || !context.mounted || widget.runtime.isDisposed) return;
      _showMessage(context, _pairingFailureMessage(strings, error));
    } finally {
      if (mounted) setState(() => _pairingBusy = false);
    }
  }

  String _pairingFailureMessage(AppStrings strings, Object error) {
    if (error is PairingFailure) {
      return strings.pairingFailureMessage(error.code.name);
    }
    return strings
        .pairingFailureMessage(PairingFailureCode.connectionUnavailable.name);
  }

  Future<PairingPayload?> _fetchManualPairingPayload(
    BuildContext context,
    ({String host, int port}) address,
  ) async {
    final runtime = widget.runtime;
    final payload = await widget.pairingPayloadGateway.fetch(
      host: address.host,
      port: address.port,
    );
    if (!mounted ||
        !context.mounted ||
        widget.runtime.isDisposed ||
        !identical(widget.runtime, runtime) ||
        widget.switchingRole) {
      return null;
    }
    if (!payload.requiresPairingCode) return payload;
    final route = DialogRoute<String>(
      context: context,
      builder: (_) => PairingCodeDialog(
        canSubmit: () =>
            mounted &&
            identical(widget.runtime, runtime) &&
            !runtime.isDisposed &&
            !widget.switchingRole,
      ),
    );
    _pairingCodeRoute = route;
    try {
      final code = await Navigator.of(context).push(route);
      if (!mounted ||
          !context.mounted ||
          widget.runtime.isDisposed ||
          !identical(widget.runtime, runtime) ||
          widget.switchingRole ||
          code == null) {
        return null;
      }
      return payload.withPairingCode(code);
    } finally {
      if (identical(_pairingCodeRoute, route)) _pairingCodeRoute = null;
    }
  }

  void _dismissPairingCodeDialog() {
    final route = _pairingCodeRoute;
    _pairingCodeRoute = null;
    if (route == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final navigator = route.navigator;
      if (navigator != null && route.isActive) navigator.removeRoute(route);
    });
  }

  ({String host, int port})? _parseManualAddress(String value) {
    final endpoint = LanEndpoint.parse(value);
    return endpoint == null ? null : (host: endpoint.host, port: endpoint.port);
  }

  Future<void> _openWatch(
      BuildContext context, ClientRuntimeState state) async {
    if (_watchRouteOpen || widget.switchingRole || widget.runtime.isDisposed) {
      return;
    }
    if (state.session == null) {
      _showMessage(context, AppStrings.of(context).ui('scanServerQrFirst'));
      return;
    }
    _watchRouteOpen = true;
    try {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => WatchScreen(
            runtime: widget.runtime,
            keepScreenAwake: _keepScreenAwake,
            onKeepScreenAwakeChanged: _persistKeepScreenAwake,
          ),
        ),
      );
    } finally {
      _watchRouteOpen = false;
    }
  }

  Future<void> _setKeepScreenAwake(bool enabled) async {
    try {
      await _persistKeepScreenAwake(enabled);
    } catch (_) {
      if (mounted) {
        _showMessage(context, AppStrings.of(context).ui('settingsSaveFailed'));
      }
    }
  }

  Future<void> _persistKeepScreenAwake(bool enabled) async {
    if (_keepScreenAwake == enabled) return;
    await widget.preferences?.setKeepScreenAwake(enabled);
    if (mounted) setState(() => _keepScreenAwake = enabled);
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
    try {
      await widget.preferences?.setLocale(selected);
    } catch (_) {
      if (mounted) _showMessage(context, strings.ui('settingsSaveFailed'));
      return;
    }
    if (!mounted) return;
    setState(() => _selectedLocale = selected);
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
