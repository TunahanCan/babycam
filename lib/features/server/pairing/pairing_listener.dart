class PairingListener {
  bool isActive = false;
  Future<void> start() async => isActive = true;
  Future<void> stop() async => isActive = false;
}
