import 'package:flutter/material.dart';

import 'client_runtime.dart';
import 'media/watch_screen.dart';

class ClientHomeScreen extends StatelessWidget {
  const ClientHomeScreen({super.key, required this.runtime, required this.onResetRole});
  final ClientRuntime runtime;
  final VoidCallback onResetRole;
  @override Widget build(BuildContext context) => StreamBuilder<ClientRuntimeState>(
    stream: runtime.states,
    initialData: runtime.currentState,
    builder: (context, snapshot) {
      final state = snapshot.data!;
      final paired = state.session != null;
      return Scaffold(appBar: AppBar(title: const Text('Ebeveyn Cihazı'), actions: [TextButton(onPressed: onResetRole, child: const Text('Rolü sıfırla'))]), body: ListView(padding: const EdgeInsets.all(16), children: [
        Text(paired ? 'Server: ${state.session!.payload.deviceName}' : 'Server cihazındaki QR kodu okutun'),
        const SizedBox(height: 12),
        if (!paired) FilledButton.icon(onPressed: () {}, icon: const Icon(Icons.qr_code_scanner), label: const Text('QR okut')),
        if (paired) FilledButton.icon(onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => WatchScreen(runtime: runtime))), icon: const Icon(Icons.play_arrow), label: const Text('Canlı izle')),
        SwitchListTile(value: true, onChanged: (_) {}, title: const Text('Bildirimler açık')),
        const ListTile(title: Text('Son uyarılar'), subtitle: Text('Henüz uyarı yok')),
        TextButton(onPressed: runtime.clearPairing, child: const Text('Eşleşmeyi sil')),
      ]));
    });
}
