class ClientAlertListener {
  bool isListening = false;
  Future<void> start() async => isListening = true;
  Future<void> stop() async => isListening = false;
}
