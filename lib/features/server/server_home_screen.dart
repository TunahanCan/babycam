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
    return Scaffold(body: _DarkShell(child: SafeArea(child: ListView(padding: const EdgeInsets.fromLTRB(26, 18, 26, 28), children: [
      _Top(action: widget.onResetRole), const SizedBox(height: 46),
      const Text('Bebek odası', style: _darkTitle),
      const SizedBox(height: 6),
      const Text('Yayın hazır. Ebeveyn cihazı QR tarayabilir veya URL girebilir.', style: _darkSubtitle),
      const SizedBox(height: 20), const _LightPill('Yayında'), const SizedBox(height: 34),
      Container(height: 460, decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(34), border: Border.all(color: Colors.white, width: 1.2))),
      const SizedBox(height: 28),
      _Card(child: Row(children: [Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Bağlantı adresi', style: _cardTitle), const SizedBox(height: 16), Container(padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18), decoration: BoxDecoration(color: const Color(0xFFF2F0F8), borderRadius: BorderRadius.circular(22)), child: const Text('http://192.168.1.20:8080', style: TextStyle(color: _navy, fontSize: 21, fontWeight: FontWeight.w900))), const SizedBox(height: 28), const Text('QR kodu ebeveyn cihazına göster', style: TextStyle(color: _slate, fontSize: 19))])), const SizedBox(width: 28), QrImageView(data: state.qrPayload ?? 'http://192.168.1.20:8080', size: 140, padding: EdgeInsets.zero, eyeStyle: const QrEyeStyle(color: _navy), dataModuleStyle: const QrDataModuleStyle(color: _navy))])),
      const SizedBox(height: 28),
      Row(children: const [Expanded(child: _Stat(label: 'Client', value: '2 bağlı', color: _mint)), SizedBox(width: 14), Expanded(child: _Stat(label: 'Video', value: 'MJPEG aktif', color: _pink)), SizedBox(width: 14), Expanded(child: _Stat(label: 'Ses', value: 'WAV açık', color: _amber))]),
      const SizedBox(height: 28),
      _Card(child: Opacity(opacity: .20, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [Text('Aktif algılama', style: _cardTitle), SizedBox(height: 22), _KeyVal('Ağlama eşiği', '%65'), SizedBox(height: 16), _KeyVal('Hareket eşiği', '%22'), SizedBox(height: 16), _KeyVal('Cooldown', '60 sn')]))),
      const SizedBox(height: 54), SizedBox(height: 72, child: FilledButton(onPressed: widget.runtime.stop, style: FilledButton.styleFrom(backgroundColor: _pink, shape: const StadiumBorder()), child: const Text('Yayını durdur', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900))))
    ]))));
  });
}

class _Stat extends StatelessWidget { const _Stat({required this.label, required this.value, required this.color}); final String label; final String value; final Color color; @override Widget build(BuildContext context) => Container(height: 138, padding: const EdgeInsets.all(22), decoration: _cardDecoration(), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: const TextStyle(color: _slate, fontSize: 18)), const Spacer(), Text(value, style: const TextStyle(color: _navy, fontSize: 22, fontWeight: FontWeight.w900)), const SizedBox(height: 12), Container(height: 12, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10))) ])); }
class _KeyVal extends StatelessWidget { const _KeyVal(this.k, this.v); final String k; final String v; @override Widget build(BuildContext context) => Row(children: [Text(k, style: const TextStyle(fontSize: 19, color: _slate)), const Spacer(), Text(v, style: const TextStyle(fontSize: 19, color: _slate, fontWeight: FontWeight.w900))]); }
class _Card extends StatelessWidget { const _Card({required this.child}); final Widget child; @override Widget build(BuildContext context) => Container(width: double.infinity, padding: const EdgeInsets.all(28), decoration: _cardDecoration(), child: child); }
class _DarkShell extends StatelessWidget { const _DarkShell({required this.child}); final Widget child; @override Widget build(BuildContext context) => Container(decoration: const BoxDecoration(gradient: RadialGradient(center: Alignment(.7, -.85), radius: .9, colors: [Color(0xFF24465A), _navy, Color(0xFF07111F)])), child: child); }
class _Top extends StatelessWidget { const _Top({required this.action}); final VoidCallback action; @override Widget build(BuildContext context) => Row(children: [const Text('09:41', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18)), const Spacer(), TextButton(onPressed: action, child: const Text('Rol')), const Icon(Icons.signal_cellular_alt_rounded, color: Colors.white), const SizedBox(width: 12), const Icon(Icons.battery_5_bar_rounded, color: Colors.white)]); }
class _LightPill extends StatelessWidget { const _LightPill(this.text); final String text; @override Widget build(BuildContext context) => Container(width: 132, padding: const EdgeInsets.symmetric(vertical: 10), decoration: const ShapeDecoration(color: Colors.white, shape: StadiumBorder()), child: Text(text, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFFF5F7FB), fontWeight: FontWeight.w900, fontSize: 18))); }
BoxDecoration _cardDecoration() => BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(34), border: Border.all(color: const Color(0xFFE2E8F0)), boxShadow: const [BoxShadow(color: Color(0x24111827), blurRadius: 28, offset: Offset(0, 16))]);
const _navy = Color(0xFF101B31); const _slate = Color(0xFF6E7686); const _pink = Color(0xFFFF708B); const _mint = Color(0xFF87D8CC); const _amber = Color(0xFFFFD37B);
const _darkTitle = TextStyle(color: Colors.white, fontSize: 44, height: 1.05, fontWeight: FontWeight.w900); const _darkSubtitle = TextStyle(color: Colors.white70, fontSize: 21, height: 1.18); const _cardTitle = TextStyle(color: _navy, fontSize: 23, fontWeight: FontWeight.w900);
