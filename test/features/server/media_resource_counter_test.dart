import 'package:flutter_test/flutter_test.dart';
import 'package:mimicam/features/server/media/media_resource_counter.dart';

void main() {
  test('server local preview kamera ve mikrofonu birlikte aktif ister', () {
    final counter = MediaResourceCounter()..localPreviewActive = true;

    expect(counter.needsVideoCapture, isTrue);
    expect(counter.needsAudioCapture, isTrue);
    expect(counter.hasLiveWatch, isFalse);
  });

  test('bildirim talebi analiz kaynaklarını açık tutar', () {
    final counter = MediaResourceCounter()
      ..wantsCryDetection = true
      ..wantsMotionDetection = true
      ..activeEventClients = 1;

    expect(counter.needsAudioCapture, isTrue);
    expect(counter.needsVideoCapture, isTrue);
    expect(counter.hasNotificationDemand, isTrue);
  });
}
