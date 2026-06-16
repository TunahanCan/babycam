import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/theme/babycam_colors.dart';
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
    final active = state.phase == ServerRuntimePhase.mediaActive;
    return Scaffold(body: _Shell(child: SafeArea(child: ListView(padding: const EdgeInsets.fromLTRB(22, 18, 22, 28), children: [
      _TopLine(action: widget.onResetRole), const SizedBox(height: 34),
      Row(children: [const Text('Server', style: TextStyle(color: BabyCamColors.brandBlueDark, fontSize: 20, fontWeight: FontWeight.w900)), const Spacer(), _Pill(text: '• ${active ? 'mediaActive' : _label(state.phase)}', color: BabyCamColors.brandBlueDark)]),
      const SizedBox(height: 14),
      const Text('Bebek Odası Yayını', style: TextStyle(color: BabyCamColors.navy, fontSize: 34, fontWeight: FontWeight.w900)),
      const SizedBox(height: 16),
      const Text('Bu ekran sadece server rolünde görünür. Client izleme paneli yok.', style: TextStyle(color: BabyCamColors.slate, fontSize: 18, height: 1.35)),
      const SizedBox(height: 20),
      _Card(child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('QR ile eşleştir', style: TextStyle(color: BabyCamColors.navy, fontSize: 24, fontWeight: FontWeight.w900)), const SizedBox(height: 8), const Text('Nonce 02:00 içinde geçerli - tek kullanımlık', style: TextStyle(color: BabyCamColors.slate, fontSize: 16, height: 1.25)), const SizedBox(height: 16), Wrap(spacing: 10, runSpacing: 8, children: [_Pill(text: _label(state.phase), color: BabyCamColors.brandPinkDark), _Pill(text: '${state.activeClients} client', color: BabyCamColors.brandBlueDark)]), const SizedBox(height: 18), _EndpointBox(text: 'http://192.168.1.20:8080') ])), const SizedBox(width: 14), if (state.qrPayload != null) QrImageView(data: state.qrPayload!, size: 156, padding: EdgeInsets.zero) else const SizedBox(width: 120, height: 120, child: Center(child: CircularProgressIndicator()))])),
      const SizedBox(height: 20),
      _Card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Medya runtime', style: TextStyle(color: BabyCamColors.navy, fontSize: 24, fontWeight: FontWeight.w900)), const SizedBox(height: 10), const Text('Session başlayınca kamera + mikrofon + analiz pipeline açılır.', style: TextStyle(color: BabyCamColors.slate, fontSize: 17, height: 1.35)), const SizedBox(height: 26), const _Timeline(), const SizedBox(height: 22), Wrap(spacing: 16, runSpacing: 12, children: const [_Pill(text: '/video\nMJPEG', color: BabyCamColors.brandBlueDark), _Pill(text: '/audio\nPCM16', color: BabyCamColors.brandPinkDark), _Pill(text: '/ws/events\nAlert JSON', color: Color(0xFF6E59F5))])])),
      const SizedBox(height: 20),
      _Card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Analiz özeti', style: TextStyle(color: BabyCamColors.navy, fontSize: 24, fontWeight: FontWeight.w900)), const SizedBox(height: 8), _Metric(label: 'Cry score 0.66 / eşik 0.65', value: .66, color: BabyCamColors.brandPink), const SizedBox(height: 20), _Metric(label: 'Motion score 0.22 / eşik 0.22', value: .22, color: BabyCamColors.brandBlueDark), if (state.lastAlert != null) Padding(padding: const EdgeInsets.only(top: 16), child: Text('Son uyarı: ${state.lastAlert}', style: const TextStyle(color: BabyCamColors.brandPinkDark, fontWeight: FontWeight.w800))) ])),
      const SizedBox(height: 28),
      Row(children: [Expanded(child: SizedBox(height: 58, child: FilledButton(onPressed: () => widget.runtime.stopMediaRuntimeIfNoActiveClients(), style: FilledButton.styleFrom(backgroundColor: BabyCamColors.brandPink, shape: const StadiumBorder()), child: const Text('Yayını durdur', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17))))), const SizedBox(width: 14), Expanded(child: SizedBox(height: 58, child: OutlinedButton(onPressed: widget.runtime.stop, style: OutlinedButton.styleFrom(shape: const StadiumBorder()), child: const Text('Ayarlar / log', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17)))))]),
      const SizedBox(height: 24), const Center(child: Text('Log, Telegram, threshold ve hata durumları bu ekrandaki sheet içinde açılır.', textAlign: TextAlign.center, style: TextStyle(color: BabyCamColors.mutedBlue, fontSize: 14))),
    ]))));
  });
  static String _label(ServerRuntimePhase phase) => switch (phase) { ServerRuntimePhase.pairingActive => 'pairingActive', ServerRuntimePhase.pairingIdle => 'pairingIdle', ServerRuntimePhase.clientPaired => 'clientPaired', ServerRuntimePhase.mediaActive => 'mediaActive', _ => phase.name };
}

class _Shell extends StatelessWidget { const _Shell({required this.child}); final Widget child; @override Widget build(BuildContext context) => Container(decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft, colors: [Color(0xFFEAF4FF), Color(0xFFFFFFFF), Color(0xFFFFEEF7)])), child: child); }
class _TopLine extends StatelessWidget { const _TopLine({required this.action}); final VoidCallback action; @override Widget build(BuildContext context) => Row(children: [const Text('09:41', style: TextStyle(color: BabyCamColors.navy, fontWeight: FontWeight.w900, fontSize: 18)), const Spacer(), TextButton(onPressed: action, child: const Text('Rolü sıfırla')), const Icon(Icons.battery_5_bar_rounded, color: BabyCamColors.navy)]); }
class _Card extends StatelessWidget { const _Card({required this.child}); final Widget child; @override Widget build(BuildContext context) => Container(width: double.infinity, padding: const EdgeInsets.all(22), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(28), border: Border.all(color: const Color(0xFFE4EEF8)), boxShadow: const [BoxShadow(color: Color(0x1A16324F), blurRadius: 22, offset: Offset(0, 12))]), child: child); }
class _Pill extends StatelessWidget { const _Pill({required this.text, required this.color}); final String text; final Color color; @override Widget build(BuildContext context) => Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9), decoration: ShapeDecoration(color: color.withOpacity(.16), shape: const StadiumBorder()), child: Text(text, textAlign: TextAlign.center, style: TextStyle(color: color, fontWeight: FontWeight.w900))); }
class _EndpointBox extends StatelessWidget { const _EndpointBox({required this.text}); final String text; @override Widget build(BuildContext context) => Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10), decoration: BoxDecoration(color: const Color(0xFFF5FAFF), border: Border.all(color: const Color(0xFFD4E5F8)), borderRadius: BorderRadius.circular(14)), child: Text(text, overflow: TextOverflow.ellipsis, style: const TextStyle(color: BabyCamColors.brandBlueDark, fontWeight: FontWeight.w900, fontSize: 16))); }
class _Timeline extends StatelessWidget { const _Timeline(); @override Widget build(BuildContext context) => Row(children: [for (final c in [BabyCamColors.brandPink, Color(0xFFFFB23F), BabyCamColors.brandBlueDark]) ...[Expanded(child: Container(height: 4, color: const Color(0xFFD4E5F8))), Container(width: 22, height: 22, decoration: BoxDecoration(color: c, shape: BoxShape.circle))], Expanded(child: Container(height: 4, color: const Color(0xFFD4E5F8)))]); }
class _Metric extends StatelessWidget { const _Metric({required this.label, required this.value, required this.color}); final String label; final double value; final Color color; @override Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: const TextStyle(color: BabyCamColors.slate, fontSize: 17)), const SizedBox(height: 8), ClipRRect(borderRadius: BorderRadius.circular(12), child: LinearProgressIndicator(value: value, minHeight: 16, color: color, backgroundColor: const Color(0xFFEAF4FF))) ]); }
