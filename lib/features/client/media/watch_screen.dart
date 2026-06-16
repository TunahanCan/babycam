import 'package:flutter/material.dart';

import '../../../core/theme/babycam_colors.dart';
import '../client_runtime.dart';

class WatchScreen extends StatefulWidget {
  const WatchScreen({super.key, required this.runtime});
  final ClientRuntime runtime;
  @override State<WatchScreen> createState() => _WatchScreenState();
}
class _WatchScreenState extends State<WatchScreen> {
  @override void initState() { super.initState(); widget.runtime.startWatching(); }
  @override void dispose() { widget.runtime.stopWatching(); super.dispose(); }
  @override Widget build(BuildContext context) => Scaffold(body: _Shell(child: SafeArea(child: ListView(padding: const EdgeInsets.fromLTRB(22, 18, 22, 28), children: [
    const _TopLine(), const SizedBox(height: 34),
    Row(children: const [Text('Client', style: TextStyle(color: BabyCamColors.brandPinkDark, fontSize: 20, fontWeight: FontWeight.w900)), Spacer(), _Pill(text: '• watching', color: BabyCamColors.brandPinkDark)]), const SizedBox(height: 14),
    const Text('Bebeği izle', style: TextStyle(color: BabyCamColors.navy, fontSize: 34, fontWeight: FontWeight.w900)), const SizedBox(height: 16),
    const Text('Video + ses + bildirim bu cihazda tüketilir; server ayarları gösterilmez.', style: TextStyle(color: BabyCamColors.slate, fontSize: 18, height: 1.35)), const SizedBox(height: 20),
    _Card(child: Column(children: [Container(height: 260, decoration: BoxDecoration(color: const Color(0xFF223F60), borderRadius: BorderRadius.circular(24)), child: CustomPaint(painter: _CameraPainter(), child: const SizedBox.expand())), const SizedBox(height: 22), Wrap(spacing: 14, runSpacing: 10, children: const [_Pill(text: 'Ses açık', color: BabyCamColors.brandBlueDark), _Pill(text: 'Bildirim açık', color: BabyCamColors.brandPinkDark), _Pill(text: 'WS bağlı', color: Color(0xFF18BBA8))])])),
    const SizedBox(height: 20),
    _Card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [Row(children: [Text('Son uyarı', style: TextStyle(color: BabyCamColors.navy, fontSize: 24, fontWeight: FontWeight.w900)), Spacer(), _Pill(text: 'now', color: BabyCamColors.brandPinkDark)]), SizedBox(height: 18), Text('Ağlama algılandı', style: TextStyle(color: BabyCamColors.brandPinkDark, fontSize: 24, fontWeight: FontWeight.w900)), SizedBox(height: 8), Text('Client local notification gösterdi. Cooldown aktif, tekrar bildirim bastırıldı.', style: TextStyle(color: BabyCamColors.slate, fontSize: 17, height: 1.35)), SizedBox(height: 10), _Pill(text: '/ws/events JSON', color: BabyCamColors.brandBlueDark)])),
    const SizedBox(height: 20),
    _Card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Bildirimleri ilet', style: TextStyle(color: BabyCamColors.navy, fontSize: 24, fontWeight: FontWeight.w900)), const SizedBox(height: 10), const Text('AlertShareService son uyarıyı aileyle paylaşır; video/ses linki token olmadan açılmaz.', style: TextStyle(color: BabyCamColors.slate, fontSize: 17, height: 1.35)), const SizedBox(height: 20), Row(children: [Expanded(child: FilledButton(onPressed: () {}, child: const Text('Babaya gönder'))), const SizedBox(width: 12), Expanded(child: FilledButton(onPressed: () {}, style: FilledButton.styleFrom(backgroundColor: BabyCamColors.brandPink), child: const Text('Aileye paylaş')))]) ])),
    const SizedBox(height: 22), Wrap(spacing: 16, runSpacing: 10, children: const [_Pill(text: 'alertOnly', color: BabyCamColors.brandBlueDark), _Pill(text: 'reconnecting', color: Color(0xFFFFB23F))]),
    const SizedBox(height: 22), SizedBox(height: 64, child: FilledButton(onPressed: () => Navigator.of(context).maybePop(), style: FilledButton.styleFrom(backgroundColor: BabyCamColors.navy, shape: const StadiumBorder()), child: const Text('İzlemeyi durdur', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)))),
  ]))));
}
class _Shell extends StatelessWidget { const _Shell({required this.child}); final Widget child; @override Widget build(BuildContext context) => Container(decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft, colors: [Color(0xFFEAF4FF), Color(0xFFFFFFFF), Color(0xFFFFEEF7)])), child: child); }
class _TopLine extends StatelessWidget { const _TopLine(); @override Widget build(BuildContext context) => const Row(children: [Text('09:41', style: TextStyle(color: BabyCamColors.navy, fontWeight: FontWeight.w900, fontSize: 18)), Spacer(), Icon(Icons.battery_5_bar_rounded, color: BabyCamColors.navy)]); }
class _Card extends StatelessWidget { const _Card({required this.child}); final Widget child; @override Widget build(BuildContext context) => Container(width: double.infinity, padding: const EdgeInsets.all(22), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(28), border: Border.all(color: const Color(0xFFE4EEF8)), boxShadow: const [BoxShadow(color: Color(0x1A16324F), blurRadius: 22, offset: Offset(0, 12))]), child: child); }
class _Pill extends StatelessWidget { const _Pill({required this.text, required this.color}); final String text; final Color color; @override Widget build(BuildContext context) => Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9), decoration: ShapeDecoration(color: color.withOpacity(.16), shape: const StadiumBorder()), child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w900))); }
class _CameraPainter extends CustomPainter { @override void paint(Canvas canvas, Size size) { final p = Paint()..color = Colors.white; canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(28, 20, 120, 50), const Radius.circular(16)), p); canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(size.width-148, 20, 120, 50), const Radius.circular(16)), p); final arc = Paint()..color = const Color(0xFF9BD2FF)..strokeWidth = 8..style = PaintingStyle.stroke; canvas.drawArc(Rect.fromCenter(center: Offset(size.width/2, 122), width: 190, height: 160), 3.55, 2.35, false, arc); canvas.drawCircle(Offset(size.width/2, 150), 62, Paint()..color = const Color(0xFFFFD6E8)); canvas.drawCircle(Offset(size.width/2, 150), 38, Paint()..color = const Color(0xFFFFC0DC)); } @override bool shouldRepaint(covariant CustomPainter oldDelegate) => false; }
