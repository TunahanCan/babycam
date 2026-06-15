import 'package:flutter/material.dart';

class QRScanScreen extends StatefulWidget {
  const QRScanScreen({super.key, required this.onCode});
  final ValueChanged<String> onCode;
  @override State<QRScanScreen> createState() => _QRScanScreenState();
}
class _QRScanScreenState extends State<QRScanScreen> {
  bool disposedAfterSuccess = false;
  void submit(String code) { widget.onCode(code); disposedAfterSuccess = true; Navigator.of(context).maybePop(); }
  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('QR Okut')), body: Center(child: FilledButton(onPressed: () {}, child: const Text('Server QR kodunu okutun'))));
}
