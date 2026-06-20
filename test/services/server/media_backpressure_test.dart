import 'package:flutter_test/flutter_test.dart';
import 'package:mimicam/services/server/media_frame_policy.dart';

void main() {
  test('MJPEG encode sadece izleyici varken yapılır', () {
    const policy = MediaEncodingPolicy();

    expect(
      policy.shouldEncodeJpeg(
        hasMjpegClients: false,
        legacyWebSocketEnabled: false,
      ),
      isFalse,
    );
    expect(
      policy.shouldEncodeJpeg(
        hasMjpegClients: true,
        legacyWebSocketEnabled: false,
      ),
      isTrue,
    );
  });

  test('frame budget backlog biriktirmek yerine ara frameleri düşürür', () {
    final budget =
        MediaFrameBudget(minInterval: const Duration(milliseconds: 250));

    expect(budget.shouldProcess(1000), isTrue);
    expect(budget.shouldProcess(1100), isFalse);
    expect(budget.shouldProcess(1200), isFalse);
    expect(budget.shouldProcess(1250), isTrue);
  });
}
