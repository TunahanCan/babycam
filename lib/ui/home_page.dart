import 'dart:async';
import 'dart:convert';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../core/app_log.dart';
import '../core/babycam_protocol.dart';
import '../l10n/app_strings.dart';
import '../services/babycam_server.dart';
import '../services/configuration_service.dart';
import '../services/discovery_service.dart';
import '../services/notification_service.dart';

enum AppMode { server, client }

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _log = AppLog();
  final _discovery = DiscoveryService();
  NotificationService? _notifications;
  AppStrings? _strings;
  bool _notificationsInitialized = false;
  final _addressController = TextEditingController();

  SharedPreferences? _prefs;
  ConfigurationService? _config;
  BabyCamServer? _server;
  StreamSubscription<String>? _discoverySubscription;
  StreamSubscription<List<String>>? _logSubscription;
  WebSocketChannel? _alertChannel;
  WebViewController? _webViewController;
  List<String> _logs = const [];
  AppMode? _mode;
  String? _serverUrl;
  String? _status;

  @override
  void initState() {
    super.initState();
    _logSubscription = _log.stream.listen((lines) => setState(() => _logs = lines));
    _bootstrap();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final strings = AppStrings.of(context);
    if (_strings?.locale.languageCode != strings.locale.languageCode) {
      _strings = strings;
      _notifications = NotificationService(strings);
      _status ??= strings.selectRoleStatus;
      if (!_notificationsInitialized) {
        _notificationsInitialized = true;
        _notifications!.initialize();
      }
    }
  }

  AppStrings get strings => _strings ?? AppStrings.of(context);

  Future<void> _bootstrap() async {
    _prefs = await SharedPreferences.getInstance();
    _config = ConfigurationService(_prefs!);
    final savedMode = _prefs?.getString('mode');
    if (savedMode == AppMode.server.name) await _selectMode(AppMode.server, save: false);
    if (savedMode == AppMode.client.name) await _selectMode(AppMode.client, save: false);
  }

  @override
  void dispose() {
    _addressController.dispose();
    _alertChannel?.sink.close();
    _discoverySubscription?.cancel();
    _logSubscription?.cancel();
    _server?.dispose();
    _discovery.dispose();
    _log.dispose();
    super.dispose();
  }

  Future<void> _selectMode(AppMode mode, {bool save = true}) async {
    if (save) await _prefs?.setString('mode', mode.name);
    await _alertChannel?.sink.close();
    await _discoverySubscription?.cancel();
    setState(() => _mode = mode);
    if (mode == AppMode.server) {
      await _startServerMode();
    } else {
      await _startClientMode();
    }
  }

  Future<void> _startServerMode() async {
    await [Permission.camera, Permission.microphone, Permission.notification].request();
    await WakelockPlus.enable();
    final config = _config ?? await ConfigurationService.load();
    final notificationService = _notifications ?? NotificationService(strings);
    _notifications = notificationService;
    if (!_notificationsInitialized) {
      _notificationsInitialized = true;
      await notificationService.initialize();
    }
    _server = BabyCamServer(config: config, strings: strings, onLog: _log.add, onAlert: notificationService.showAlert);
    final url = await _server!.start();
    setState(() {
      _serverUrl = url;
      _status = strings.serverActiveStatus(url);
    });
  }

  Future<void> _startClientMode() async {
    await _server?.dispose();
    _server = null;
    await WakelockPlus.disable();
    await Permission.notification.request();
    _log.add(strings.clientSearchingLog);
    _discoverySubscription = _discovery.listen().listen((address) {
      if (_addressController.text.isEmpty) {
        _addressController.text = address;
        _connectClient(address);
      }
    });
    final savedAddress = _prefs?.getString('server_address');
    if (savedAddress != null && savedAddress.isNotEmpty) {
      _addressController.text = savedAddress;
      await _connectClient(savedAddress);
    }
    setState(() => _status = strings.clientActiveStatus);
  }

  Future<void> _connectClient(String rawAddress) async {
    final address = _normalizeAddress(rawAddress);
    if (address.isEmpty) return;
    await _prefs?.setString('server_address', address);
    final httpUrl = 'http://$address/';
    final wsUrl = 'ws://$address/ws/stream';
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..loadRequest(Uri.parse(httpUrl));
    await _alertChannel?.sink.close();
    _alertChannel = WebSocketChannel.connect(Uri.parse(wsUrl));
    _alertChannel!.stream.listen(_handleAlertPacket, onError: (_) => _log.add(strings.alertWebSocketDisconnected));
    setState(() {
      _webViewController = controller;
      _status = strings.clientConnectedStatus(httpUrl);
    });
  }

  void _handleAlertPacket(Object packet) {
    if (packet is! List<int> || packet.isEmpty || packet.first != BabyCamProtocol.packetAlertText) return;
    final message = utf8.decode(packet.skip(1).toList());
    _notifications?.showAlert(message);
    _log.add(strings.serverAlertLog(message));
  }

  Future<void> _resetMode() async {
    await _prefs?.remove('mode');
    await _server?.dispose();
    _server = null;
    await _alertChannel?.sink.close();
    await _discoverySubscription?.cancel();
    setState(() {
      _mode = null;
      _serverUrl = null;
      _webViewController = null;
      _status = strings.roleResetStatus;
    });
  }

  String _normalizeAddress(String raw) {
    final cleaned = raw.trim().replaceFirst('http://', '').replaceFirst('https://', '').replaceAll(RegExp(r'/+$'), '');
    if (cleaned.isEmpty) return '';
    return cleaned.contains(':') ? cleaned : '$cleaned:${BabyCamProtocol.httpPort}';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(strings.appTitle),
          actions: [if (_mode != null) TextButton(onPressed: _resetMode, child: Text(strings.reset))],
        ),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(_status ?? strings.selectRoleStatus, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            if (_mode == null) _roleButtons(),
            if (_mode == AppMode.server) _serverPanel(),
            if (_mode == AppMode.client) _clientPanel(),
            const Divider(),
            Expanded(child: ListView(children: _logs.map(Text.new).toList())),
          ]),
        ),
      );

  Widget _roleButtons() => Row(children: [
        Expanded(child: FilledButton.icon(onPressed: () => _selectMode(AppMode.server), icon: const Icon(Icons.videocam), label: Text(strings.server))),
        const SizedBox(width: 12),
        Expanded(child: OutlinedButton.icon(onPressed: () => _selectMode(AppMode.client), icon: const Icon(Icons.monitor), label: Text(strings.client))),
      ]);

  Widget _serverPanel() {
    final cameraController = _server?.cameraController;
    return Expanded(
      child: ListView(children: [
        if (cameraController != null && cameraController.value.isInitialized) _cameraPreview(cameraController),
        const SizedBox(height: 12),
        if (_serverUrl != null) Center(child: QrImageView(data: _serverUrl!, size: 220)),
        SelectableText(_serverUrl ?? strings.addressPreparing),
      ]),
    );
  }

  Widget _cameraPreview(CameraController controller) => AspectRatio(
        aspectRatio: controller.value.aspectRatio,
        child: CameraPreview(controller),
      );

  Widget _clientPanel() => Expanded(
        child: Column(children: [
          Row(children: [
            Expanded(child: TextField(controller: _addressController, decoration: InputDecoration(labelText: strings.serverAddressLabel))),
            IconButton(onPressed: () => _connectClient(_addressController.text), icon: const Icon(Icons.link)),
          ]),
          Expanded(child: _webViewController == null ? Center(child: Text(strings.waitingForServer)) : WebViewWidget(controller: _webViewController!)),
        ]),
      );
}
