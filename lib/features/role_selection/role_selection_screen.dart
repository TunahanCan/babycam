import 'package:flutter/material.dart';

import '../../app/app_role.dart';
import '../../core/theme/babycam_colors.dart';

class RoleSelectionScreen extends StatelessWidget {
  const RoleSelectionScreen({super.key, required this.onRoleSelected});
  final ValueChanged<AppRole> onRoleSelected;
  @override Widget build(BuildContext context) => Scaffold(body: SafeArea(child: ListView(padding: const EdgeInsets.all(20), children: [
    Text('BabyCam rolünü seç', style: Theme.of(context).textTheme.headlineMedium),
    const SizedBox(height: 20),
    _RoleCard(title: 'Ebeveyn Cihazı', subtitle: 'QR okut, canlı izle, bildirim al', icon: Icons.monitor_heart, color: BabyCamColors.brandBlue, soft: BabyCamColors.brandBlueSoft, onTap: () => onRoleSelected(AppRole.client)),
    const SizedBox(height: 16),
    _RoleCard(title: 'Bebek Odası Cihazı', subtitle: 'QR göster, kamera/mikrofon yayını başlat, ağlama ve hareket algıla', icon: Icons.child_care, color: BabyCamColors.brandPink, soft: BabyCamColors.brandPinkSoft, onTap: () => onRoleSelected(AppRole.server)),
  ])));
}
class _RoleCard extends StatelessWidget {
  const _RoleCard({required this.title, required this.subtitle, required this.icon, required this.color, required this.soft, required this.onTap});
  final String title; final String subtitle; final IconData icon; final Color color; final Color soft; final VoidCallback onTap;
  @override Widget build(BuildContext context) => InkWell(onTap: onTap, borderRadius: BorderRadius.circular(28), child: Container(padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: soft, borderRadius: BorderRadius.circular(28), border: Border.all(color: color, width: 2)), child: Row(children: [Icon(icon, color: color, size: 42), const SizedBox(width: 16), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(color: color, fontWeight: FontWeight.bold)), Text(subtitle)]))])));
}
