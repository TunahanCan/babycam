import 'dart:io';

/// Models Wi-Fi disappearing without either endpoint receiving FIN or RST.
class BlackholeTcpProxy {
  BlackholeTcpProxy._(this._server, this._upstreamPort) {
    _server.listen(_accept);
  }

  final ServerSocket _server;
  final int _upstreamPort;
  final _sockets = <Socket>[];
  int _blackholedThrough = 0;
  int connections = 0;
  bool _closed = false;

  int get port => _server.port;

  static Future<BlackholeTcpProxy> start(int upstreamPort) async =>
      BlackholeTcpProxy._(
        await ServerSocket.bind(InternetAddress.loopbackIPv4, 0),
        upstreamPort,
      );

  void blackholeExistingConnections() => _blackholedThrough = connections;

  Future<void> _accept(Socket downstream) async {
    final connection = ++connections;
    _sockets.add(downstream);
    final upstream = await Socket.connect(
      InternetAddress.loopbackIPv4,
      _upstreamPort,
    );
    if (_closed) {
      upstream.destroy();
      downstream.destroy();
      return;
    }
    _sockets.add(upstream);
    downstream.listen(
      (data) {
        if (connection > _blackholedThrough) upstream.add(data);
      },
      onError: (Object _) => upstream.destroy(),
      onDone: upstream.destroy,
    );
    upstream.listen(
      (data) {
        if (connection > _blackholedThrough) downstream.add(data);
      },
      onError: (Object _) => downstream.destroy(),
      onDone: downstream.destroy,
    );
  }

  Future<void> close() async {
    _closed = true;
    for (final socket in _sockets) {
      socket.destroy();
    }
    await _server.close();
  }
}
