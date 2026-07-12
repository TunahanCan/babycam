enum PairingFailureCode {
  payloadExpired,
  pairingNotActive,
  nonceInvalidOrExpired,
  rateLimited,
  selfPairingNotAllowed,
  maxTrustedClientsReached,
  maxChildProfilesReached,
  connectionUnavailable,
  invalidServerResponse,
  pairingInProgress,
  rejected,
}

/// A stable, transport-independent pairing failure.
///
/// The UI maps this code to the parent device's language; raw HTTP or socket
/// errors must not leak directly into a pairing snackbar.
class PairingFailure implements Exception {
  const PairingFailure(this.code, {this.statusCode, this.serverMessage});

  final PairingFailureCode code;
  final int? statusCode;
  final String? serverMessage;

  @override
  String toString() => 'PairingFailure(${code.name})';
}
