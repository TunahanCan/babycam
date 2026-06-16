import 'package:flutter/material.dart';

import '../../core/theme/babycam_colors.dart';
import 'client_runtime.dart';
import 'media/watch_screen.dart';

class ClientHomeScreen extends StatelessWidget {
  const ClientHomeScreen({super.key, required this.runtime, required this.onResetRole});
  final ClientRuntime runtime;
  final VoidCallback onResetRole;
  @override Widget build(BuildContext context) => StreamBuilder<ClientRuntimeState>(stream: runtime.states, initialData: runtime.currentState, builder: (context, snapshot) {
    final state = snapshot.data!;
    final paired = state.session != null;
    return Scaffold(body: _Shell(child: SafeArea(child: ListView(padding: const EdgeInsets.fromLTRB(22, 18, 22, 28), children: [
      _TopLine(action: onResetRole), const SizedBox(height: 34),
      const Text('Client', style: TextStyle(color: BabyCamColors.brandPinkDark, fontSize: 20, fontWeight: FontWeight.w900)), const SizedBox(height: 14),
      Text(paired ? 'Bebeği izle' : 'Server QR kodunu okut', style: const TextStyle(color: BabyCamColors.navy, fontSize: 34, fontWeight: FontWeight.w900)), const SizedBox(height: 16),
      Text(paired ? 'Video + ses + bildirim bu cihazda tüketilir; server ayarları gösterilmez.' : 'Bu ekran sadece client rolünde görünür. Kamera/mikrofon server kontrolü yok.', style: const TextStyle(color: BabyCamColors.slate, fontSize: 18, height: 1.35)), const SizedBox(height: 20),
      _Card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Container(height: 260, decoration: BoxDecoration(color: const Color(0xFFF0F7FF), borderRadius: BorderRadius.circular(24), border: Border.all(color: const Color(0xFFC9DDF4), width: 2)), child: Center(child: Container(padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 22), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFFD4E5F8))), child: const Column(mainAxisSize: MainAxisSize.min, children: [Text('babycam://pair', style: TextStyle(color: BabyCamColors.navy, fontSize: 18, fontWeight: FontWeight.w900)), SizedBox(height: 8), Text('nonce + host + port', style: TextStyle(color: BabyCamColors.slate))]))),), const SizedBox(height: 20), const Text('Okutunca /pair/confirm çağrılır, session token cihazda saklanır.', style: TextStyle(color: BabyCamColors.slate, fontSize: 17, height: 1.35))])),
      const SizedBox(height: 20),
      _Card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('QR yoksa', style: TextStyle(color: BabyCamColors.navy, fontSize: 24, fontWeight: FontWeight.w900)), const SizedBox(height: 10), const Text('UDP discovery sadece yardımcıdır. Ana bağlantı yolu QR + nonce + token.', style: TextStyle(color: BabyCamColors.slate, fontSize: 17, height: 1.35)), const SizedBox(height: 18), Row(children: [const Expanded(child: _EndpointBox(text: '192.168.1.20:8080')), const SizedBox(width: 12), SizedBox(height: 52, child: FilledButton(onPressed: () {}, style: FilledButton.styleFrom(backgroundColor: BabyCamColors.brandBlueDark, shape: const StadiumBorder()), child: const Text('Bağlan', style: TextStyle(fontWeight: FontWeight.w900))))])])),
      const SizedBox(height: 20),
      _Card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const _Pill(text: 'pairedIdle', color: Color(0xFF18BBA8)), const SizedBox(height: 18), const Text('Eşleşme bitince aynı ekranda iki seçim görünür:', style: TextStyle(color: BabyCamColors.slate, fontSize: 17)), const SizedBox(height: 14), Wrap(spacing: 12, runSpacing: 10, children: const [_Pill(text: 'İzle + dinle', color: BabyCamColors.brandPinkDark), _Pill(text: 'Sadece bildirim', color: BabyCamColors.brandBlueDark)])])),
      const SizedBox(height: 26),
      SizedBox(height: 64, child: FilledButton(onPressed: paired ? () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => WatchScreen(runtime: runtime))) : () {}, style: FilledButton.styleFrom(backgroundColor: BabyCamColors.brandPink, shape: const StadiumBorder()), child: Text(paired ? 'İzle + dinle' : 'QR tara', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)))),
      if (paired) TextButton(onPressed: runtime.clearPairing, child: const Text('Eşleşmeyi sil')),
    ]))));
  });
}
class _Shell extends StatelessWidget { const _Shell({required this.child}); final Widget child; @override Widget build(BuildContext context) => Container(decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft, colors: [Color(0xFFEAF4FF), Color(0xFFFFFFFF), Color(0xFFFFEEF7)])), child: child); }
class _TopLine extends StatelessWidget { const _TopLine({required this.action}); final VoidCallback action; @override Widget build(BuildContext context) => Row(children: [const Text('09:41', style: TextStyle(color: BabyCamColors.navy, fontWeight: FontWeight.w900, fontSize: 18)), const Spacer(), TextButton(onPressed: action, child: const Text('Rolü sıfırla')), const Icon(Icons.battery_5_bar_rounded, color: BabyCamColors.navy)]); }
class _Card extends StatelessWidget { const _Card({required this.child}); final Widget child; @override Widget build(BuildContext context) => Container(width: double.infinity, padding: const EdgeInsets.all(22), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(28), border: Border.all(color: const Color(0xFFE4EEF8)), boxShadow: const [BoxShadow(color: Color(0x1A16324F), blurRadius: 22, offset: Offset(0, 12))]), child: child); }
class _Pill extends StatelessWidget { const _Pill({required this.text, required this.color}); final String text; final Color color; @override Widget build(BuildContext context) => Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9), decoration: ShapeDecoration(color: color.withOpacity(.16), shape: const StadiumBorder()), child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w900))); }
class _EndpointBox extends StatelessWidget { const _EndpointBox({required this.text}); final String text; @override Widget build(BuildContext context) => Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13), decoration: BoxDecoration(color: const Color(0xFFF5FAFF), border: Border.all(color: const Color(0xFFD4E5F8)), borderRadius: BorderRadius.circular(16)), child: Text(text, overflow: TextOverflow.ellipsis, style: const TextStyle(color: BabyCamColors.brandBlueDark, fontWeight: FontWeight.w900, fontSize: 18))); }
