/// Durable destinations, recorded before opening a chargeable store sheet.
///
/// Implementations must reject an unconfirmed write. A failed write may not be
/// exposed as durable state to a coordinator recreated in the same process.
abstract interface class PendingRoomActivationRepository {
  Set<String> load();
  Future<void> save(Set<String> roomIds);
}
