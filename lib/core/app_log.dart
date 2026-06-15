import 'dart:async';

class AppLog {
  AppLog({this.capacity = 160});

  final int capacity;
  final _lines = <String>[];
  final _controller = StreamController<List<String>>.broadcast();

  Stream<List<String>> get stream => _controller.stream;
  List<String> get lines => List.unmodifiable(_lines);

  void add(String message) {
    final time = DateTime.now().toIso8601String().substring(11, 19);
    _lines.add('$time  $message');
    if (_lines.length > capacity) _lines.removeAt(0);
    _controller.add(lines);
  }

  Future<void> dispose() => _controller.close();
}
