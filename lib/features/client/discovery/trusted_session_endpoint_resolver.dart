import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../core/network/lan_endpoint.dart';
import '../../../core/network/retry_policy.dart';
import '../../../core/protocol/mimicam_protocol.dart';
import '../../../core/protocol/pairing_payload.dart';
import '../../../core/protocol/pairing_session.dart';
import '../../../core/protocol/server_endpoint_builder.dart';
import '../../../services/discovery/mimicam_service_discovery.dart';

typedef TrustedEndpointProbe = Future<bool> Function(PairingSession candidate);

/// Rebinds a trusted session when DNS-SD reports the same stable device ID at a
/// new IPv4/IPv6 endpoint.
///
/// DNS-SD announcements are not authenticated. Automatic rebinding is
/// therefore disabled by default: probing a newly announced address with the
/// long-lived bearer token would disclose that token to a spoofed service.
/// It may only be enabled by a transport that authenticates the server first
/// (for example, QR-pinned TLS).
class TrustedSessionEndpointResolver {
  TrustedSessionEndpointResolver({
    required this.browser,
    TrustedEndpointProbe? probe,
    RetryPolicy? retryPolicy,
    this.maxProbeAttempts = 3,
    this.probeTimeout = const Duration(seconds: 2),
    this.allowUnverifiedEndpointRebind = false,
  })  : _probe = probe,
        _retryPolicy = retryPolicy ??
            ExponentialBackoffPolicy(
              initialDelay: const Duration(milliseconds: 200),
              maxDelay: const Duration(seconds: 2),
              jitterRatio: .2,
            ) {
    if (maxProbeAttempts <= 0) {
      throw ArgumentError.value(
        maxProbeAttempts,
        'maxProbeAttempts',
        'must be positive',
      );
    }
  }

  final MimiCamServiceBrowser browser;
  final TrustedEndpointProbe? _probe;
  final RetryPolicy _retryPolicy;
  final int maxProbeAttempts;
  final Duration probeTimeout;
  final bool allowUnverifiedEndpointRebind;

  Stream<PairingSession> watch(PairingSession initialSession) async* {
    if (!allowUnverifiedEndpointRebind) return;
    final queue = StreamController<List<MimiCamDiscoveredService>>();
    void enqueue(List<MimiCamDiscoveredService> services) {
      if (!queue.isClosed) queue.add(services);
    }

    final subscription = browser.updates.listen(
      enqueue,
      onError: (Object error, StackTrace stackTrace) {
        if (!queue.isClosed) queue.addError(error, stackTrace);
      },
      onDone: () {
        if (!queue.isClosed) unawaited(queue.close());
      },
    );
    try {
      await browser.start();
    } catch (_) {
      // Remain subscribed: a later foreground/UI refresh may restart DNS-SD.
    }

    var current = initialSession;
    String? lastEndpointSignature;
    enqueue(browser.services);
    try {
      await for (final services in queue.stream) {
        final service = _matchingService(current, services);
        if (service == null) {
          lastEndpointSignature = null;
          continue;
        }
        final signature = _endpointSignature(service);
        if (signature == lastEndpointSignature) continue;
        final hasAlternative = service.endpoints.any(
          (endpoint) =>
              endpoint.port != current.port ||
              !lanHostsEqual(endpoint.host, current.host),
        );
        if (!hasAlternative && _containsCurrentEndpoint(current, service)) {
          lastEndpointSignature = signature;
          continue;
        }
        final rebound = await _resolveReachableEndpoint(current, service);
        if (rebound == null) {
          // Do not permanently suppress an identical DNS-SD refresh after a
          // transient probe outage. A later announcement must get a new try.
          lastEndpointSignature = null;
          continue;
        }
        lastEndpointSignature = signature;
        if (_sameEndpoint(current, rebound)) continue;
        current = rebound;
        yield rebound;
      }
    } finally {
      await subscription.cancel();
      if (!queue.isClosed) await queue.close();
    }
  }

  String _endpointSignature(MimiCamDiscoveredService service) {
    final authorities = service.endpoints
        .map((endpoint) => endpoint.authority.toLowerCase())
        .toList(growable: false)
      ..sort();
    return authorities.join('|');
  }

  MimiCamDiscoveredService? _matchingService(
    PairingSession session,
    List<MimiCamDiscoveredService> services,
  ) {
    final deviceId = session.deviceId.trim();
    if (deviceId.isEmpty) return null;
    final matches = services
        .where((service) => service.deviceId?.trim() == deviceId)
        .toList(growable: false);
    return matches.length == 1 ? matches.single : null;
  }

  bool _containsCurrentEndpoint(
    PairingSession current,
    MimiCamDiscoveredService service,
  ) =>
      current.port == service.port &&
      service.endpoints.any(
        (endpoint) => lanHostsEqual(endpoint.host, current.host),
      );

  Future<PairingSession?> _resolveReachableEndpoint(
    PairingSession current,
    MimiCamDiscoveredService service,
  ) async {
    final candidates = [
      for (final endpoint in service.endpoints)
        if (endpoint.port == current.port &&
            lanHostsEqual(endpoint.host, current.host))
          _withEndpoint(current, endpoint),
      for (final endpoint in service.endpoints)
        if (endpoint.port != current.port ||
            !lanHostsEqual(endpoint.host, current.host))
          _withEndpoint(current, endpoint),
    ];
    for (var attempt = 0; attempt < maxProbeAttempts; attempt++) {
      for (final candidate in candidates) {
        try {
          final reachable =
              await (_probe?.call(candidate) ?? _probeTrustedStatus(candidate))
                  .timeout(probeTimeout);
          if (reachable) return candidate;
        } catch (_) {
          // Try the other address family before backing off.
        }
      }
      if (attempt + 1 < maxProbeAttempts) {
        await Future<void>.delayed(_retryPolicy.delayForAttempt(attempt));
      }
    }
    return null;
  }

  Future<bool> _probeTrustedStatus(PairingSession candidate) async {
    final client = HttpClient()..connectionTimeout = probeTimeout;
    try {
      final request = await client
          .getUrl(
            ServerEndpointBuilder(candidate).http(MimiCamProtocolV2.status),
          )
          .timeout(probeTimeout);
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer ${candidate.sessionToken}',
      );
      final response = await request.close().timeout(probeTimeout);
      final body =
          await utf8.decoder.bind(response).join().timeout(probeTimeout);
      if (response.statusCode != HttpStatus.ok) return false;
      final decoded = jsonDecode(body);
      return decoded is Map;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  PairingSession _withEndpoint(
    PairingSession session,
    LanEndpoint endpoint,
  ) {
    final payload = session.payload;
    return session.copyWith(
      payload: PairingPayload(
        schemaVersion: payload.schemaVersion,
        scheme: payload.scheme,
        host: endpoint.host,
        port: endpoint.port,
        deviceId: payload.deviceId,
        deviceName: payload.deviceName,
        pairingNonce: payload.pairingNonce,
        expiresAtMs: payload.expiresAtMs,
        transport: payload.transport,
        capabilities: payload.capabilities,
      ),
    );
  }

  bool _sameEndpoint(PairingSession left, PairingSession right) =>
      left.port == right.port && lanHostsEqual(left.host, right.host);
}
