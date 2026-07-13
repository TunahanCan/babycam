import 'package:flutter_test/flutter_test.dart';
import 'package:mimicam/features/server/media/media_resource_counter.dart';

void main() {
  test('server local preview yalnız kamera demandi üretir', () {
    final counter = MediaResourceCounter()..localPreviewActive = true;

    expect(counter.needsVideoCapture, isTrue);
    expect(counter.needsVideoEncoding, isTrue);
    expect(counter.needsAudioCapture, isFalse);
    expect(counter.hasLiveWatch, isFalse);
  });

  test('external WebRTC capture legacy kamera ve mikrofonu tekrar istemez', () {
    final counter = MediaResourceCounter()
      ..activeVideoClients = 1
      ..activeAudioClients = 1
      ..externalVideoClients = 1
      ..externalAudioClients = 1;

    expect(counter.needsVideoCapture, isFalse);
    expect(counter.needsVideoEncoding, isFalse);
    expect(counter.needsAudioCapture, isFalse);
    expect(counter.hasLiveWatch, isTrue);
  });

  test('bildirim talebi analiz kaynaklarını açık tutar', () {
    final counter = MediaResourceCounter()
      ..wantsCryDetection = true
      ..wantsMotionDetection = true
      ..activeEventClients = 1;

    expect(counter.needsAudioCapture, isTrue);
    expect(counter.needsVideoCapture, isTrue);
    expect(counter.needsVideoEncoding, isFalse);
    expect(counter.hasNotificationDemand, isTrue);
  });
}
