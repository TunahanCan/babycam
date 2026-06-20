class StreamBackpressureGate<T extends Object> {
  final _busyClients = <T>{};

  bool tryMarkBusy(T client) => _busyClients.add(client);

  void markIdle(T client) {
    _busyClients.remove(client);
  }

  void remove(T client) {
    _busyClients.remove(client);
  }

  void clear() {
    _busyClients.clear();
  }

  int get busyCount => _busyClients.length;
}
