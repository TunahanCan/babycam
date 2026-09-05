import 'package:flutter/material.dart';

import '../../../l10n/app_strings.dart';
import '../../shared/presentation/localized_time.dart';
import '../../shared/presentation/miucam_design_tokens.dart';
import '../../shared/presentation/miucam_shells.dart';
import '../pairing/trusted_client_repository.dart';
import '../server_runtime.dart';

/// Shared by pairing and settings so remembered access is visible at setup.
class ServerTrustedDevicesCard extends StatefulWidget {
  const ServerTrustedDevicesCard({super.key, required this.runtime});
  final ServerRuntime runtime;

  @override
  State<ServerTrustedDevicesCard> createState() =>
      _ServerTrustedDevicesCardState();
}

class _ServerTrustedDevicesCardState extends State<ServerTrustedDevicesCard> {
  String? _revokingClientId;
  bool _revokingAllClients = false;
  bool get _busy => _revokingAllClients || _revokingClientId != null;

  Future<void> _confirmRevokeClient(TrustedClientRecord client) async {
    if (_revokingClientId != null || _revokingAllClients) return;
    final strings = AppStrings.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(strings.ui('revokeDeviceConfirmTitle')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(strings.uiFormat(
                'revokeDeviceConfirmBody', {'name': client.clientName})),
            const SizedBox(height: 8),
            Text(_deviceCode(client), textDirection: TextDirection.ltr),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(strings.ui('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(strings.ui('revokeDevice')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _revokingClientId = client.clientId);
    await _revokeTrustedDevices(
      () => widget.runtime.revokeTrustedClient(client.clientId),
    );
    if (mounted) setState(() => _revokingClientId = null);
  }

  Future<void> _confirmRevokeAllClients() async {
    if (_revokingClientId != null || _revokingAllClients) return;
    final strings = AppStrings.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(strings.ui('revokeAllDevices')),
        content: Text(strings.ui('revokeAllDevicesConfirmBody')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(strings.ui('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(strings.ui('revokeAllDevices')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _revokingAllClients = true);
    await _revokeTrustedDevices(widget.runtime.revokeAllTrustedClients);
    if (mounted) setState(() => _revokingAllClients = false);
  }

  Future<void> _revokeTrustedDevices(
    Future<void> Function() revoke,
  ) async {
    final strings = AppStrings.of(context);
    try {
      await revoke();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(content: Text(strings.ui('trustedDeviceRevoked'))),
        );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(content: Text(strings.ui('deviceRemovalSaveFailed'))),
        );
    }
  }

  Future<void> _rename(TrustedClientRecord client) async {
    if (_busy) return;
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _DeviceNameDialog(
          initialName: client.clientName, deviceCode: _deviceCode(client)),
    );
    if (!mounted || name == null || name == client.clientName || _busy) return;
    setState(() => _revokingClientId = client.clientId);
    try {
      await widget.runtime.renameTrustedClient(client.clientId, name);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(AppStrings.of(context).ui('deviceNameSaveFailed')),
        ));
      }
    } finally {
      if (mounted) setState(() => _revokingClientId = null);
    }
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<ServerRuntimeState>(
        stream: widget.runtime.states,
        builder: (context, _) => StreamBuilder<void>(
          stream: widget.runtime.trustedClientsChanged,
          builder: (context, _) => _buildCard(context),
        ),
      );

  Widget _buildCard(BuildContext context) {
    final strings = AppStrings.of(context);
    final clients = widget.runtime.trustedClients;
    final savedCount = clients.where((client) => !client.revoked).length;
    final watching = widget.runtime.activeWatchClientIds;
    final notifications = widget.runtime.notificationClientIds;
    const muted =
        TextStyle(color: MiuCamDesignTokens.serverTextMuted, height: 1.4);
    return MiuCamCard(
      dark: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.phonelink_lock_rounded,
                color: MiuCamDesignTokens.serverCyan),
            const SizedBox(width: 10),
            Expanded(
                child: Text(strings.ui('trustedDevicesTitle'),
                    style: const TextStyle(
                      color: MiuCamDesignTokens.serverText,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ))),
          ]),
          const SizedBox(height: 10),
          Wrap(spacing: 12, runSpacing: 6, children: [
            Text(
                strings.uiFormat('rememberedDeviceCount', {
                  'count': savedCount,
                  'max': widget.runtime.maxTrustedClients,
                }),
                style: const TextStyle(
                    color: MiuCamDesignTokens.serverCyan,
                    fontWeight: FontWeight.w700)),
            Text(
                strings.uiFormat('watchingDeviceCount', {
                  'count': watching.length,
                  'max': widget.runtime.maxActiveWatchClients,
                }),
                style: muted),
          ]),
          const SizedBox(height: 8),
          Text(strings.ui('trustedDevicesDescription'), style: muted),
          if (savedCount >= widget.runtime.maxTrustedClients) ...[
            const SizedBox(height: 8),
            Text(strings.ui('trustedDeviceCapacityFull'),
                style: const TextStyle(
                  color: MiuCamDesignTokens.serverCyan,
                  height: 1.4,
                )),
          ],
          const SizedBox(height: 12),
          if (clients.isEmpty)
            Text(strings.ui('noTrustedDevices'), style: muted),
          for (final client in clients) ...[
            _DeviceRow(
              key: ValueKey('trusted-device-${client.clientId}'),
              client: client,
              watching: watching.contains(client.clientId),
              notifications: notifications.contains(client.clientId),
              busy: _revokingAllClients || _revokingClientId == client.clientId,
              onRename: _busy ||
                      client.revoked ||
                      !widget.runtime.canRenameTrustedClients
                  ? null
                  : () => _rename(client),
              onRevoke: _busy ? null : () => _confirmRevokeClient(client),
            ),
            const Divider(color: MiuCamDesignTokens.serverOutline),
          ],
          if (clients.isNotEmpty)
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton(
                onPressed: _busy ? null : _confirmRevokeAllClients,
                child: Text(strings.ui('revokeAllDevices')),
              ),
            ),
        ],
      ),
    );
  }
}

class _DeviceRow extends StatelessWidget {
  const _DeviceRow(
      {super.key,
      required this.client,
      required this.watching,
      required this.notifications,
      required this.busy,
      this.onRename,
      this.onRevoke});
  final TrustedClientRecord client;
  final bool watching;
  final bool notifications;
  final bool busy;
  final VoidCallback? onRename;
  final VoidCallback? onRevoke;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final statusKey = client.revoked
        ? 'deviceRemovalPending'
        : watching
            ? 'deviceWatching'
            : notifications
                ? 'deviceNotificationsOnly'
                : 'deviceRemembered';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.phone_android_rounded,
              color: MiuCamDesignTokens.serverCyan),
          const SizedBox(width: 10),
          Expanded(
              child: Text(
                  client.clientName.trim().isEmpty
                      ? client.clientId
                      : client.clientName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: MiuCamDesignTokens.serverText,
                      fontWeight: FontWeight.w900))),
          if (busy)
            const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox.square(
                    dimension: 24,
                    child: CircularProgressIndicator(strokeWidth: 2.5)))
          else ...[
            if (onRename != null)
              IconButton(
                  tooltip: strings.ui('renameDevice'),
                  onPressed: onRename,
                  icon: const Icon(Icons.edit_outlined)),
            IconButton(
                tooltip: strings.ui('revokeDevice'),
                onPressed: onRevoke,
                icon: const Icon(Icons.link_off_rounded)),
          ],
        ]),
        Text(_deviceCode(client),
            textDirection: TextDirection.ltr,
            style: const TextStyle(
                color: MiuCamDesignTokens.serverTextMuted, fontSize: 12)),
        const SizedBox(height: 4),
        Text(strings.ui(statusKey),
            style: TextStyle(
                color: watching || client.revoked
                    ? MiuCamDesignTokens.serverCyan
                    : MiuCamDesignTokens.serverTextMuted,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(
            strings.uiFormat('deviceLastSeen', {
              'time': formatAlertTimestamp(context, client.lastSeenAtMs),
            }),
            style: const TextStyle(
                color: MiuCamDesignTokens.serverTextMuted, fontSize: 12)),
      ]),
    );
  }
}

class _DeviceNameDialog extends StatefulWidget {
  const _DeviceNameDialog(
      {required this.initialName, required this.deviceCode});
  final String initialName;
  final String deviceCode;
  @override
  State<_DeviceNameDialog> createState() => _DeviceNameDialogState();
}

class _DeviceNameDialogState extends State<_DeviceNameDialog> {
  late final _controller = TextEditingController(text: widget.initialName);
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final name = _controller.text.trim();
    if (name.isNotEmpty) Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return AlertDialog(
      title: Text(strings.ui('renameDevice')),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 80,
        textCapitalization: TextCapitalization.words,
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(
            labelText: strings.ui('deviceNameLabel'),
            helper: Text(widget.deviceCode, textDirection: TextDirection.ltr)),
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) => _save(),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(strings.ui('cancel'))),
        FilledButton(
            onPressed: _controller.text.trim().isEmpty ? null : _save,
            child: Text(strings.ui('saveDeviceName'))),
      ],
    );
  }
}

// A stable suffix distinguishes phones that share the default display name.
String _deviceCode(TrustedClientRecord client) {
  final id = client.clientId;
  return '#${id.length > 8 ? id.substring(id.length - 8) : id}';
}
