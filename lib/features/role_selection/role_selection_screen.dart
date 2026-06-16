import 'package:flutter/material.dart';

import '../../app/app_role.dart';

class RoleSelectionScreen extends StatelessWidget {
  const RoleSelectionScreen({super.key, required this.onRoleSelected});
  final ValueChanged<AppRole> onRoleSelected;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: _LightShell(
          child: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(26, 18, 26, 28),
              children: [
                const _StatusBar(),
                const SizedBox(height: 48),
                const Text('Bu cihaz ne olacak?', style: _titleStyle),
                const SizedBox(height: 6),
                const Text('Rolü daha sonra Ayarlar > Rolü değiştir bölümünden\ndeğiştirebilirsin.', style: _subtitleStyle),
                const SizedBox(height: 44),
                _RoleChoiceCard(
                  dark: true,
                  badge: 'S',
                  title: 'Bebek odası cihazı',
                  description: 'Kamera ve mikrofon bu telefonda açılır. Yayın URL\nve QR kod ile paylaşılır.',
                  chip: 'Önerilen',
                  button: 'Server olarak kur',
                  onPressed: () => onRoleSelected(AppRole.server),
                ),
                const SizedBox(height: 28),
                _RoleChoiceCard(
                  badge: 'C',
                  title: 'Ebeveyn cihazı',
                  description: 'Aynı Wi‑Fi içinde server bulunur, canlı yayın izlenir\nve uyarılar bildirim olur.',
                  chip: 'İzleyici',
                  button: 'Client olarak bağlan',
                  onPressed: () => onRoleSelected(AppRole.client),
                ),
                const SizedBox(height: 180),
                _InfoStrip(title: 'Güvenlik notu', text: 'Bu uygulama doğrudan internete açılmak için\ntasarlanmadı. Aynı Wi‑Fi/LAN içinde kullan.'),
              ],
            ),
          ),
        ),
      );
}

class _RoleChoiceCard extends StatelessWidget {
  const _RoleChoiceCard({this.dark = false, required this.badge, required this.title, required this.description, required this.chip, required this.button, required this.onPressed});
  final bool dark; final String badge; final String title; final String description; final String chip; final String button; final VoidCallback onPressed;
  @override Widget build(BuildContext context) => Container(padding: const EdgeInsets.all(30), decoration: _cardDecoration(dark: dark), child: Column(children: [Row(crossAxisAlignment: CrossAxisAlignment.start, children: [CircleAvatar(radius: 40, backgroundColor: dark ? _pink : _mint, child: Text(badge, style: TextStyle(color: _navy, fontSize: 32, fontWeight: FontWeight.w900))), const SizedBox(width: 28), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: TextStyle(color: dark ? Colors.white : _navy, fontSize: 30, fontWeight: FontWeight.w900)), const SizedBox(height: 12), Text(description, style: TextStyle(color: dark ? Colors.white70 : _slate, fontSize: 18, height: 1.25))])), _Chip(text: chip, color: _pinkSoft)]), const SizedBox(height: 34), SizedBox(width: double.infinity, height: 74, child: FilledButton(onPressed: onPressed, style: FilledButton.styleFrom(backgroundColor: dark ? _pink : _navy, shape: const StadiumBorder()), child: Text(button, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900))))]));
}

class _InfoStrip extends StatelessWidget { const _InfoStrip({required this.title, required this.text}); final String title; final String text; @override Widget build(BuildContext context) => Container(padding: const EdgeInsets.all(26), decoration: _cardDecoration(), child: Row(children: [const CircleAvatar(radius: 30, backgroundColor: _mintSoft, child: Text('!', style: TextStyle(color: _navy, fontSize: 28, fontWeight: FontWeight.w900))), const SizedBox(width: 24), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(color: _navy, fontSize: 24, fontWeight: FontWeight.w900)), const SizedBox(height: 8), Text(text, style: const TextStyle(color: _slate, fontSize: 18, height: 1.25))]))])); }
class _LightShell extends StatelessWidget { const _LightShell({required this.child}); final Widget child; @override Widget build(BuildContext context) => Container(decoration: const BoxDecoration(gradient: RadialGradient(center: Alignment(.55, -.78), radius: .8, colors: [_mintSoft, Color(0xFFFDF7F4), Color(0xFFF9F7FC)])), child: child); }
class _StatusBar extends StatelessWidget { const _StatusBar(); @override Widget build(BuildContext context) => const Row(children: [Text('09:41', style: TextStyle(color: _navy, fontWeight: FontWeight.w900, fontSize: 18)), Spacer(), Icon(Icons.signal_cellular_alt_rounded, color: _navy), SizedBox(width: 12), Icon(Icons.battery_5_bar_rounded, color: _navy)]); }
class _Chip extends StatelessWidget { const _Chip({required this.text, required this.color}); final String text; final Color color; @override Widget build(BuildContext context) => Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7), decoration: ShapeDecoration(color: color, shape: const StadiumBorder()), child: Text(text, style: const TextStyle(color: _navy, fontWeight: FontWeight.w800))); }
BoxDecoration _cardDecoration({bool dark = false}) => BoxDecoration(color: dark ? _navy : Colors.white, borderRadius: BorderRadius.circular(34), border: Border.all(color: const Color(0xFFE2E8F0)), boxShadow: const [BoxShadow(color: Color(0x24111827), blurRadius: 28, offset: Offset(0, 16))]);
const _navy = Color(0xFF101B31); const _slate = Color(0xFF6E7686); const _pink = Color(0xFFFF708B); const _pinkSoft = Color(0xFFFFDCE6); const _mint = Color(0xFF87D8CC); const _mintSoft = Color(0xFFD9F7F1);
const _titleStyle = TextStyle(color: _navy, fontSize: 42, height: 1.05, fontWeight: FontWeight.w900);
const _subtitleStyle = TextStyle(color: _slate, fontSize: 22, height: 1.18);
