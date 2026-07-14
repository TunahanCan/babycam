import 'dart:io';
import 'dart:typed_data';

import '../../core/media/media_session_telemetry.dart';
import '../../features/server/media/microphone_capture_service.dart';
import '../../features/server/media/mjpeg_stream_service.dart';
import '../../features/server/media/wav_audio_stream_service.dart';

/// Facade for the server's three transport-facing media services.
///
/// Capture policy can evolve independently from HTTP session handling while
/// stream attachment, fan-out and teardown keep one lifecycle owner.
class ServerMediaTransportController {
  ServerMediaTransportController({
    required int sampleRate,
    required int channels,
    required int bitsPerSample,
    required MediaSessionTelemetry telemetry,
  })  : video = MjpegStreamService(telemetry: telemetry),
        audio = WavAudioStreamService(
          sampleRate: sampleRate,
          channels: channels,
          bitsPerSample: bitsPerSample,
          telemetry: telemetry,
        ),
        microphone = MicrophoneCaptureService(
          sampleRate: sampleRate,
          channels: channels,
        );

  final MjpegStreamService video;
  final WavAudioStreamService audio;
  final MicrophoneCaptureService microphone;

  bool get hasVideoClients => video.hasClients;
  bool get hasAudioClients => audio.hasClients;

  Future<void> attachVideo(
    HttpResponse response,
    String clientId, {
    Uint8List? firstFrame,
    void Function()? onDetached,
  }) =>
      video.attachClient(
        response,
        clientId,
        firstFrame: firstFrame,
        onDetached: onDetached,
      );

  Future<void> attachAudio(
    HttpResponse response,
    String clientId, {
    void Function()? onDetached,
  }) =>
      audio.attachClient(response, clientId, onDetached: onDetached);

  void broadcastVideo(
    Uint8List jpeg, {
    int? capturedAtMs,
    int? capturedAtMonoUs,
    int? encodeDurationUs,
    String? traceId,
  }) {
    video.broadcast(
      jpeg,
      capturedAtMs: capturedAtMs,
      capturedAtMonoUs: capturedAtMonoUs,
      encodeDurationUs: encodeDurationUs,
      traceId: traceId,
    );
  }

  void broadcastAudio(Uint8List pcm16le) => audio.broadcast(pcm16le);

  Future<void> closeAll() async {
    await microphone.dispose();
    await video.closeAll();
    await audio.closeAll();
  }

  void resetDiagnostics() {
    video.resetDiagnostics();
    audio.resetDiagnostics();
  }
}
