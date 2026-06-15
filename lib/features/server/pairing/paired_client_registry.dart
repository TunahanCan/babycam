class PairedClientRegistry {
  final _tokens = <String>{};
  int get count => _tokens.length;
  void add(String token) => _tokens.add(token);
  void remove(String token) => _tokens.remove(token);
  void clear() => _tokens.clear();
}
