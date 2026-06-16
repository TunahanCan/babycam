import 'package:flutter/material.dart';

import '../../app/app_role.dart';
import '../../core/theme/babycam_colors.dart';

class RoleSelectionScreen extends StatefulWidget {
  const RoleSelectionScreen({super.key, required this.onRoleSelected});
  final ValueChanged<AppRole> onRoleSelected;

  @override
  State<RoleSelectionScreen> createState() => _RoleSelectionScreenState();
}

class _RoleSelectionScreenState extends State<RoleSelectionScreen> {
  AppRole _selected = AppRole.server;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: _GradientPage(
          child: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 28),
              children: [
                const _StatusBar(),
                const SizedBox(height: 34),
                Text('BabyCam', style: Theme.of(context).textTheme.titleLarge?.copyWith(color: BabyCamColors.brandPinkDark, fontWeight: FontWeight.w900)),
                const SizedBox(height: 16),
                Text('Bu cihaz ne olarak\nçalışacak?', style: Theme.of(context).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w900, color: BabyCamColors.navy, height: 1.08)),
                const SizedBox(height: 14),
                const Text('Rol seçildikten sonra uygulama sadece o role ait ekranları gösterir.', style: TextStyle(color: BabyCamColors.slate, fontSize: 18, height: 1.3)),
                const SizedBox(height: 34),
                _RoleCard(selected: _selected == AppRole.server, title: 'Bebek odası cihazı', mode: 'Server modu', description: 'Kamera ve mikrofon bu cihazda açılır. QR üretir, token verir, video/ses/uyarı yayınlar.', icon: Icons.camera_alt_rounded, color: BabyCamColors.brandBlueDark, chips: const ['QR üretir', 'LAN 8080'], onTap: () => setState(() => _selected = AppRole.server)),
                const SizedBox(height: 20),
                _RoleCard(selected: _selected == AppRole.client, title: 'Ebeveyn cihazı', mode: 'Client modu', description: 'Server QR kodunu okutur, session token alır; video, ses ve bildirimleri tüketir.', icon: Icons.bubble_chart_rounded, color: BabyCamColors.brandPinkDark, chips: const ['QR okutur', 'Bildirim alır'], onTap: () => setState(() => _selected = AppRole.client)),
                const SizedBox(height: 26),
                _InfoCard(),
                const SizedBox(height: 32),
                SizedBox(height: 64, child: FilledButton(onPressed: () => widget.onRoleSelected(_selected), style: FilledButton.styleFrom(backgroundColor: BabyCamColors.navy, shape: const StadiumBorder()), child: const Text('Seçimi kaydet ve devam et', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)))),
                const SizedBox(height: 22),
                const Center(child: Text('Daha sonra Ayarlar > Rolü sıfırla ile değiştirilebilir.', style: TextStyle(color: BabyCamColors.mutedBlue, fontSize: 14))),
              ],
            ),
          ),
        ),
      );
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({required this.selected, required this.title, required this.mode, required this.description, required this.icon, required this.color, required this.chips, required this.onTap});
  final bool selected; final String title; final String mode; final String description; final IconData icon; final Color color; final List<String> chips; final VoidCallback onTap;
  @override Widget build(BuildContext context) => InkWell(onTap: onTap, borderRadius: BorderRadius.circular(28), child: Container(padding: const EdgeInsets.all(22), decoration: _cardDecoration(selected), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Container(width: 70, height: 58, decoration: BoxDecoration(color: color.withOpacity(.9), borderRadius: BorderRadius.circular(14)), child: Icon(icon, color: Colors.white, size: 34)), const SizedBox(width: 18), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(color: BabyCamColors.navy, fontSize: 22, fontWeight: FontWeight.w900)), const SizedBox(height: 4), Text(mode, style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.w900))]))]), const SizedBox(height: 22), Text(description, style: const TextStyle(color: BabyCamColors.slate, fontSize: 17, height: 1.35)), const SizedBox(height: 18), Wrap(spacing: 12, runSpacing: 10, children: [for (final chip in chips) _Pill(text: chip, color: chip.contains('LAN') || chip.contains('Bildirim') ? BabyCamColors.brandPinkDark : BabyCamColors.brandBlueDark)])])));
}

class _InfoCard extends StatelessWidget { @override Widget build(BuildContext context) => Container(padding: const EdgeInsets.all(22), decoration: _cardDecoration(false).copyWith(color: Colors.white.withOpacity(.72)), child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [ _Pill(text: 'Güvenlik', color: Color(0xFF18BBA8)), SizedBox(height: 18), Text('Aynı Wi‑Fi/LAN içinde çalışır. İnternete doğrudan açmayın; uzaktan erişim için VPN veya güvenli tünel kullanın.', style: TextStyle(color: BabyCamColors.slate, fontSize: 17, height: 1.35))])); }
class _Pill extends StatelessWidget { const _Pill({required this.text, required this.color}); final String text; final Color color; @override Widget build(BuildContext context) => Container(padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10), decoration: ShapeDecoration(color: color.withOpacity(.16), shape: const StadiumBorder()), child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w900))); }
class _StatusBar extends StatelessWidget { const _StatusBar(); @override Widget build(BuildContext context) => const Row(children: [Text('09:41', style: TextStyle(color: BabyCamColors.navy, fontWeight: FontWeight.w900, fontSize: 18)), Spacer(), Icon(Icons.battery_5_bar_rounded, color: BabyCamColors.navy)]); }
class _GradientPage extends StatelessWidget { const _GradientPage({required this.child}); final Widget child; @override Widget build(BuildContext context) => Container(decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft, colors: [Color(0xFFEAF4FF), Color(0xFFFFFFFF), Color(0xFFFFEEF7)])), child: child); }
BoxDecoration _cardDecoration(bool selected) => BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(28), border: Border.all(color: selected ? const Color(0xFFD8E8FA) : const Color(0xFFE4EEF8), width: 1.5), boxShadow: const [BoxShadow(color: Color(0x1A16324F), blurRadius: 22, offset: Offset(0, 12))]);
