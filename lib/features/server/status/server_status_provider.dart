class ServerStatusProvider {
  Map<String, Object?> status(
          {required bool mediaActive, required int clients}) =>
      {'mediaActive': mediaActive, 'clients': clients};
}
