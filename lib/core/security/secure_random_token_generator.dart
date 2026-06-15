import 'dart:math';

class SecureRandomTokenGenerator {
  SecureRandomTokenGenerator({Random? random}) : _random = random ?? Random.secure();
  final Random _random;

  String generateHex({int byteCount = 32}) => List<int>.generate(byteCount, (_) => _random.nextInt(256)).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}
