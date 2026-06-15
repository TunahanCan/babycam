class MicrophoneCaptureService { bool started = false; Future<void> start() async => started = true; Future<void> stop() async => started = false; }
