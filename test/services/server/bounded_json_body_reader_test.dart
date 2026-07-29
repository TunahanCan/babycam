import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:miucam/services/server/bounded_json_body_reader.dart';

void main() {
  test('declared ve streamed byte limitleri fail-fast uygulanır', () async {
    const reader = BoundedJsonBodyReader(maxBytes: 8);

    await expectLater(
      reader.readStream(const Stream.empty(), declaredLength: 9),
      throwsA(isA<RequestBodyTooLargeException>()),
    );
    await expectLater(
      reader.readStream(Stream.value(utf8.encode('{"value":1}'))),
      throwsA(isA<RequestBodyTooLargeException>()),
    );
  });

  test('tamamlanmayan chunked body aboneliği timeoutta iptal edilir', () async {
    var cancelled = false;
    final controller = StreamController<List<int>>(
      onCancel: () => cancelled = true,
    );
    const reader = BoundedJsonBodyReader(
      maxBytes: 1024,
      readTimeout: Duration(milliseconds: 20),
    );

    await expectLater(
      reader.readStream(controller.stream),
      throwsA(isA<RequestBodyReadTimeoutException>()),
    );
    expect(cancelled, isTrue);
    await controller.close();
  });

  test('geçerli küçük JSON object okunur', () async {
    const reader = BoundedJsonBodyReader(maxBytes: 1024);
    final decoded = await reader.readStream(
      Stream.value(utf8.encode('{"ok":true}')),
    );

    expect(decoded, {'ok': true});
  });
}
