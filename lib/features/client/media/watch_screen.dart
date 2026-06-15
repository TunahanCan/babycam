import 'package:flutter/material.dart';

import '../client_runtime.dart';

class WatchScreen extends StatefulWidget {
  const WatchScreen({super.key, required this.runtime});
  final ClientRuntime runtime;
  @override State<WatchScreen> createState() => _WatchScreenState();
}
class _WatchScreenState extends State<WatchScreen> {
  @override void initState() { super.initState(); widget.runtime.startWatching(); }
  @override void dispose() { widget.runtime.stopWatching(); super.dispose(); }
  @override Widget build(BuildContext context) => const Scaffold(body: Center(child: Text('Canlı izleme')));
}
