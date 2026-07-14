import 'dart:io';

enum MimiCamRouteAuthMode { none, bearer, streamToken, testAccess }

typedef MimiCamRouteHandler = Future<void> Function(
  HttpRequest request,
  String? clientId,
);

class MimiCamHttpRoute {
  const MimiCamHttpRoute(
    this.path,
    this.authMode,
    this.allowedMethods,
    this.handle,
  );

  final String path;
  final MimiCamRouteAuthMode authMode;
  final Set<String> allowedMethods;
  final MimiCamRouteHandler handle;

  bool allowsMethod(String method) => allowedMethods.contains(method);
}

typedef MimiCamRouteAuthorization = ({bool ok, String? clientId});

/// Owns the transport-level HTTP pipeline.
///
/// Domain handlers stay on their focused controllers while this dispatcher
/// applies the shared network, method, authentication and error policy once.
class MimiCamHttpDispatcher {
  MimiCamHttpDispatcher({
    required Iterable<MimiCamHttpRoute> routes,
    required this.isDisposed,
    required this.isRemoteAddressAllowed,
    required this.isEventSocketPath,
    required this.handleEventSocket,
    required this.authorize,
    required this.writeLandingPage,
    required this.onLog,
  }) : _routes = Map<String, MimiCamHttpRoute>.unmodifiable({
          for (final route in routes) route.path: route,
        }) {
    if (_routes.length != routes.length) {
      throw StateError('Duplicate MimiCam HTTP route path.');
    }
  }

  final Map<String, MimiCamHttpRoute> _routes;
  final bool Function() isDisposed;
  final bool Function(InternetAddress address) isRemoteAddressAllowed;
  final bool Function(String path) isEventSocketPath;
  final Future<bool> Function(HttpRequest request) handleEventSocket;
  final Future<MimiCamRouteAuthorization> Function(
    HttpRequest request,
    MimiCamRouteAuthMode mode,
  ) authorize;
  final Future<void> Function(HttpResponse response) writeLandingPage;
  final void Function(String message) onLog;

  Future<void> dispatch(HttpRequest request) async {
    try {
      if (isDisposed()) {
        await request.response.close();
        return;
      }
      final remoteAddress = request.connectionInfo?.remoteAddress;
      if (remoteAddress != null && !isRemoteAddressAllowed(remoteAddress)) {
        request.response.statusCode = HttpStatus.forbidden;
        await request.response.close();
        return;
      }
      if (isEventSocketPath(request.uri.path)) {
        if (await handleEventSocket(request)) return;
        request.response.statusCode = HttpStatus.upgradeRequired;
        await request.response.close();
        return;
      }

      final route = _routes[request.uri.path];
      if (route == null) {
        if (request.uri.path == '/') {
          await writeLandingPage(request.response);
        } else {
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
        }
        return;
      }
      if (!route.allowsMethod(request.method)) {
        request.response
          ..statusCode = HttpStatus.methodNotAllowed
          ..headers.set(
            HttpHeaders.allowHeader,
            route.allowedMethods.join(', '),
          );
        await request.response.close();
        return;
      }

      final auth = await authorize(request, route.authMode);
      if (!auth.ok) return;
      await route.handle(request, auth.clientId);
    } catch (error) {
      onLog('HTTP isteği tamamlanamadı: $error');
      try {
        request.response.statusCode = HttpStatus.internalServerError;
        await request.response.close();
      } catch (_) {}
    }
  }
}

class HttpMethod {
  const HttpMethod._();

  static const get = 'GET';
  static const post = 'POST';
}
