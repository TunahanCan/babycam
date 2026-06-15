import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'server_runtime.dart';

class ServerHomeScreen extends StatefulWidget {
  const ServerHomeScreen({super.key, required this.runtime, required this.onResetRole});
  final ServerRuntime runtime;
  final VoidCallback onResetRole;
  @override State<ServerHomeScreen> createState() => _ServerHomeScreenState();
}
class _ServerHomeScreenState extends State<ServerHomeScreen> {
  @override void initState() { super.initState(); widget.runtime.startPairingMode(); }
  @override Widget build(BuildContext context) => StreamBuilder<ServerRuntimeState>(stream: widget.runtime.states, initialData: widget.runtime.currentState, builder: (context, snapshot) {
    final state = snapshot.data!;
    final qr = state.qrPayload;
    return Scaffold(appBar: AppBar(title: const Text('Bebek Odası Cihazı'), actions: [TextButton(onPressed: onResetRole, child: const Text('Rolü sıfırla'))]), body: ListView(padding: const EdgeInsets.all(16), children: [
      Chip(label: Text(_label(state.phase))),
      const SizedBox(height: 12),
      Card(child: Padding(padding: const EdgeInsets.all(20), child: Column(children: [const Text('QR kod alanı'), if (qr != null) QrImageView(data: qr, size: 220) else const CircularProgressIndicator(), const Text('Ebeveyn cihazıyla bu QR kodu okutun')]))),
      ListTile(title: const Text('Bağlı client sayısı'), trailing: Text('${state.activeClients}')),
      ListTile(title: const Text('Kamera/mikrofon durumu'), subtitle: Text(state.phase == ServerRuntimePhase.mediaActive ? 'Aktif' : 'Kapalı')),
      ListTile(title: const Text('Analiz durumu'), subtitle: Text(state.phase == ServerRuntimePhase.mediaActive ? 'Aktif' : 'Kapalı')),
      ListTile(title: const Text('Son uyarı'), subtitle: Text(state.lastAlert ?? 'Yok')),
      FilledButton(onPressed: () => widget.runtime.stopMediaRuntimeIfNoActiveClients(), child: const Text('Yayını durdur / yeniden başlat')),
      OutlinedButton(onPressed: widget.runtime.stop, child: const Text('Tüm clientları çıkar')),
    ]));
  });
  String _label(ServerRuntimePhase phase) => switch (phase) { ServerRuntimePhase.pairingActive || ServerRuntimePhase.pairingIdle => 'Pairing bekleniyor', ServerRuntimePhase.clientPaired => 'Client bağlı', ServerRuntimePhase.mediaActive => 'Yayın aktif', _ => phase.name };
}
