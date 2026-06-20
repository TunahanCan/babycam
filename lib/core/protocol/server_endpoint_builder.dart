import 'pairing_session.dart';

class ServerEndpointBuilder {
  const ServerEndpointBuilder(this.session);

  final PairingSession session;

  Uri http(String path, {Map<String, String>? query}) => Uri(
        scheme: session.httpScheme,
        host: session.host,
        port: session.port,
        path: _normalizePath(path),
        queryParameters: query,
      );

  Uri ws(String path, {Map<String, String>? query}) => Uri(
        scheme: session.wsScheme,
        host: session.host,
        port: session.port,
        path: _normalizePath(path),
        queryParameters: query,
      );

  String _normalizePath(String path) => path.startsWith('/') ? path : '/$path';
}
