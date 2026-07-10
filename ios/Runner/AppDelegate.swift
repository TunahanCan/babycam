import AVFoundation
import Flutter
import Network
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let cameraPermissionRequester = CameraPermissionRequester()
  private let localNetworkPermissionRequester = LocalNetworkPermissionRequester()
  private let platformRuntime = PlatformRuntimeBridge.shared
  private lazy var pcmAudioPlayer = PcmAudioPlayer { [weak self] type, details in
    guard let self else { return }
    self.platformRuntime.emit(type, details: details)
    switch type {
    case "audioPlaybackStarted":
      self.platformRuntime.setAudioOutputActive(true, reason: type)
    case "audioOutputResumedFromBackground":
      self.platformRuntime.setAudioOutputActive(
        details["recovered"] as? Bool ?? false,
        reason: type
      )
    case "audioPlaybackStopped", "audioOutputSuspendedForBackground",
         "audioInterruptionBegan":
      self.platformRuntime.setAudioOutputActive(false, reason: type)
    case "audioInterruptionEnded", "audioMediaServicesReset":
      self.platformRuntime.setAudioOutputActive(
        details["outputActive"] as? Bool ??
          (details["recovered"] as? Bool ?? false),
        reason: type
      )
    default:
      break
    }
  }

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    registerCameraPermissionChannel()
    registerLocalNetworkPermissionChannel()
    registerPlatformRuntimeChannels()
    registerPcmAudioChannel()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func registerPlatformRuntimeChannels() {
    guard let registrar = registrar(forPlugin: "MimiCamPlatformRuntime") else {
      return
    }
    let methodChannel = FlutterMethodChannel(
      name: "mimicam/platform_runtime",
      binaryMessenger: registrar.messenger()
    )
    methodChannel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(nil)
        return
      }
      switch call.method {
      case "snapshot":
        result(self.platformRuntime.snapshot())
      case "setMediaDemand":
        let args = call.arguments as? [String: Any]
        let active = args?["active"] as? Bool ?? false
        self.platformRuntime.setMediaDemand(
          active: active,
          camera: args?["camera"] as? Bool ?? false,
          microphone: args?["microphone"] as? Bool ?? false,
          playback: args?["playback"] as? Bool ?? false
        )
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    FlutterEventChannel(
      name: "mimicam/platform_runtime_events",
      binaryMessenger: registrar.messenger()
    ).setStreamHandler(platformRuntime)

    let resourcesChannel = FlutterMethodChannel(
      name: "mimicam/device_resources",
      binaryMessenger: registrar.messenger()
    )
    resourcesChannel.setMethodCallHandler { call, result in
      guard call.method == "snapshot" else {
        result(FlutterMethodNotImplemented)
        return
      }
      UIDevice.current.isBatteryMonitoringEnabled = true
      let thermalState: String
      switch ProcessInfo.processInfo.thermalState {
      case .nominal:
        thermalState = "nominal"
      case .fair:
        thermalState = "fair"
      case .serious:
        thermalState = "serious"
      case .critical:
        thermalState = "critical"
      @unknown default:
        thermalState = "unknown"
      }
      let batteryState = UIDevice.current.batteryState
      let batteryLevel = UIDevice.current.batteryLevel
      let batteryLevelPercent: Any = batteryLevel >= 0
        ? Int((batteryLevel * 100).rounded())
        : NSNull()
      result([
        "thermalState": thermalState,
        "lowPowerMode": ProcessInfo.processInfo.isLowPowerModeEnabled,
        "charging": batteryState == .charging || batteryState == .full,
        "batteryLevelPercent": batteryLevelPercent
      ])
    }
  }

  private func registerCameraPermissionChannel() {
    guard let registrar = registrar(forPlugin: "MimiCamCameraPermission") else {
      return
    }
    let channel = FlutterMethodChannel(
      name: "mimicam/camera_permission",
      binaryMessenger: registrar.messenger()
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(nil)
        return
      }
      switch call.method {
      case "status":
        self.cameraPermissionRequester.status(result: result)
      case "request":
        self.cameraPermissionRequester.request(result: result)
      case "openSettings":
        self.cameraPermissionRequester.openSettings(result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func registerLocalNetworkPermissionChannel() {
    guard let registrar = registrar(forPlugin: "MimiCamLocalNetworkPermission") else {
      return
    }
    let channel = FlutterMethodChannel(
      name: "mimicam/local_network_permission",
      binaryMessenger: registrar.messenger()
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "request" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let self else {
        result(nil)
        return
      }
      self.localNetworkPermissionRequester.request(result: result)
    }
  }

  private func registerPcmAudioChannel() {
    guard let registrar = registrar(forPlugin: "MimiCamPcmAudio") else {
      return
    }
    let channel = FlutterMethodChannel(
      name: "mimicam/pcm_audio",
      binaryMessenger: registrar.messenger()
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(nil)
        return
      }
      switch call.method {
      case "start":
        let args = call.arguments as? [String: Any]
        let sampleRate = (args?["sampleRate"] as? NSNumber)?.intValue ?? 16000
        let channels = (args?["channels"] as? NSNumber)?.intValue ?? 1
        do {
          try self.pcmAudioPlayer.start(sampleRate: sampleRate, channels: channels)
          result(nil)
        } catch {
          self.platformRuntime.setAudioOutputActive(
            false,
            reason: "audioPlaybackStartFailed"
          )
          result(FlutterError(
            code: "PCM_AUDIO_START_FAILED",
            message: error.localizedDescription,
            details: self.pcmAudioPlayer.status()
          ))
        }
      case "write":
        if let typed = call.arguments as? FlutterStandardTypedData {
          result(self.pcmAudioPlayer.write(typed.data))
        } else {
          result(false)
        }
      case "status":
        result(self.pcmAudioPlayer.status())
      case "playTestTone":
        let args = call.arguments as? [String: Any]
        let sampleRate = (args?["sampleRate"] as? NSNumber)?.intValue ?? 16000
        let channels = (args?["channels"] as? NSNumber)?.intValue ?? 1
        let durationMs = (args?["durationMs"] as? NSNumber)?.intValue ?? 1200
        let frequencyHz = (args?["frequencyHz"] as? NSNumber)?.intValue ?? 440
        let amplitude = (args?["amplitude"] as? NSNumber)?.doubleValue ?? 0.35
        do {
          try self.pcmAudioPlayer.playTestTone(
            sampleRate: sampleRate,
            channels: channels,
            durationMs: durationMs,
            frequencyHz: frequencyHz,
            amplitude: amplitude
          )
          result(nil)
        } catch {
          self.platformRuntime.setAudioOutputActive(
            false,
            reason: "audioTestToneStartFailed"
          )
          result(FlutterError(
            code: "PCM_AUDIO_TEST_TONE_FAILED",
            message: error.localizedDescription,
            details: self.pcmAudioPlayer.status()
          ))
        }
      case "stop":
        self.pcmAudioPlayer.stop()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}

final class PlatformRuntimeBridge: NSObject, FlutterStreamHandler {
  static let shared = PlatformRuntimeBridge()

  private let lock = NSLock()
  private var eventSink: FlutterEventSink?
  private var sequence: Int64 = 0
  private var applicationState = "foreground"
  private var cameraDemand = false
  private var microphoneDemand = false
  private var playbackDemand = false
  private var audioOutputActive = false
  private var mediaPauseIssued = false

  var isApplicationForeground: Bool {
    lock.lock()
    let foreground = applicationState == "foreground" || applicationState == "foregroundActive"
    lock.unlock()
    return foreground
  }

  func onListen(
    withArguments arguments: Any?,
    eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    lock.lock()
    eventSink = events
    lock.unlock()
    emit("snapshot", details: snapshot())
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    lock.lock()
    eventSink = nil
    lock.unlock()
    return nil
  }

  func snapshot() -> [String: Any] {
    lock.lock()
    let state = applicationState
    let currentCameraDemand = cameraDemand
    let currentMicrophoneDemand = microphoneDemand
    let currentPlaybackDemand = playbackDemand
    let currentAudioOutputActive = audioOutputActive
    lock.unlock()
    return [
      "platform": "ios",
      "applicationState": state,
      "supportsCameraInBackground": false,
      "cameraRequiresForegroundStart": true,
      "backgroundRecoveryAfterProcessDeath": false,
      "foregroundServiceActive": false,
      "cameraDemand": currentCameraDemand,
      "microphoneDemand": currentMicrophoneDemand,
      "playbackDemand": currentPlaybackDemand,
      "audioOutputActive": currentAudioOutputActive,
      "supportsServerInBackground": false,
      "supportsAudioOutputInBackground": false,
      "serviceOwnsMediaHardware": false,
      "activityAttached": state == "foregroundActive" || state == "foreground",
      "serviceOwnsEngine": false,
      "engineAvailable": true,
      "contractMessage":
        "iOS oda sunucusu, kamera ve oda sesi yalnız uygulama ön plandayken desteklenir."
    ]
  }

  func setMediaDemand(
    active: Bool,
    camera: Bool,
    microphone: Bool,
    playback: Bool
  ) {
    let hasDemand = active && (camera || microphone || playback)
    lock.lock()
    cameraDemand = hasDemand && camera
    microphoneDemand = hasDemand && microphone
    playbackDemand = hasDemand && playback
    let details: [String: Any] = [
      "active": hasDemand,
      "cameraDemand": cameraDemand,
      "microphoneDemand": microphoneDemand,
      "playbackDemand": playbackDemand
    ]
    lock.unlock()
    emit("mediaDemandChanged", details: details)
  }

  func setAudioOutputActive(_ active: Bool, reason: String) {
    lock.lock()
    let changed = audioOutputActive != active
    audioOutputActive = active
    lock.unlock()
    guard changed else { return }
    emit(
      "audioOutputStateChanged",
      details: ["active": active, "reason": reason]
    )
  }

  func setApplicationState(_ state: String) {
    lock.lock()
    let changed = applicationState != state
    applicationState = state
    let shouldPause = (state == "inactive" || state == "background") && !mediaPauseIssued
    let shouldRecover = state == "foregroundActive" && mediaPauseIssued
    if shouldPause {
      mediaPauseIssued = true
    } else if shouldRecover {
      mediaPauseIssued = false
    }
    lock.unlock()
    guard changed else { return }
    emit("applicationLifecycle", details: ["state": state])
    if shouldPause {
      emit(
        "mediaPauseRequired",
        details: [
          "reason": state == "inactive"
            ? "ios_application_inactive"
            : "ios_application_backgrounded",
          "cameraBackgroundSupported": false,
          "serverBackgroundSupported": false,
          "audioOutputBackgroundSupported": false
        ]
      )
    } else if shouldRecover {
      emit(
        "mediaRecoveryRequested",
        details: ["reason": "application_foregrounded"]
      )
    }
  }

  func emit(_ type: String, details: [String: Any] = [:]) {
    lock.lock()
    sequence += 1
    let currentSequence = sequence
    let sink = eventSink
    lock.unlock()
    var payload = details
    payload["type"] = type
    payload["timestampMs"] = Int64(Date().timeIntervalSince1970 * 1000)
    payload["sequence"] = currentSequence
    DispatchQueue.main.async {
      sink?(payload)
    }
  }
}

private final class CameraPermissionRequester {
  func status(result: FlutterResult) {
    result(Self.statusString(AVCaptureDevice.authorizationStatus(for: .video)))
  }

  func request(result: @escaping FlutterResult) {
    AVCaptureDevice.requestAccess(for: .video) { _ in
      DispatchQueue.main.async {
        result(Self.statusString(AVCaptureDevice.authorizationStatus(for: .video)))
      }
    }
  }

  func openSettings(result: @escaping FlutterResult) {
    guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else {
      result(false)
      return
    }
    UIApplication.shared.open(settingsURL, options: [:]) { opened in
      result(opened)
    }
  }

  private static func statusString(_ status: AVAuthorizationStatus) -> String {
    switch status {
    case .authorized:
      return "authorized"
    case .denied:
      return "denied"
    case .restricted:
      return "restricted"
    case .notDetermined:
      return "notDetermined"
    @unknown default:
      return "denied"
    }
  }
}

private final class LocalNetworkPermissionRequester {
  private var browser: NWBrowser?
  private let queue = DispatchQueue(label: "com.mimicam.local-network-permission")

  func request(result: @escaping FlutterResult) {
    guard #available(iOS 14.0, *) else {
      result(nil)
      return
    }

    if browser != nil {
      result(nil)
      return
    }

    let parameters = NWParameters()
    parameters.includePeerToPeer = true

    let browser = NWBrowser(
      for: .bonjour(type: "_mimicam._tcp", domain: nil),
      using: parameters
    )
    self.browser = browser
    browser.stateUpdateHandler = { [weak self] state in
      switch state {
      case .failed(_), .cancelled:
        DispatchQueue.main.async {
          self?.browser = nil
        }
      default:
        break
      }
    }
    browser.start(queue: queue)

    DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
      self?.browser?.cancel()
      self?.browser = nil
    }
    result(nil)
  }
}

/// Coordinates MimiCam's native output without deactivating the process-wide
/// AVAudioSession that `record` or WebRTC may currently use for microphone
/// input. AVAudioSession is a singleton; output ownership must therefore be
/// reference-counted and configured for simultaneous input/output.
private final class SharedAudioSessionPolicy {
  static let shared = SharedAudioSessionPolicy()

  private let lock = NSLock()
  private var outputOwners = 0

  func acquireOutput() throws {
    lock.lock()
    outputOwners += 1
    lock.unlock()
    do {
      try configureAndActivate()
    } catch {
      releaseOutput()
      throw error
    }
  }

  func recoverOutputIfNeeded() throws {
    lock.lock()
    let required = outputOwners > 0
    lock.unlock()
    if required { try configureAndActivate() }
  }

  func releaseOutput() {
    lock.lock()
    outputOwners = max(0, outputOwners - 1)
    lock.unlock()
    // Never call setActive(false) here. The recorder and WebRTC plugin share
    // this same session and may still own an input path.
  }

  func status() -> [String: Any] {
    lock.lock()
    let owners = outputOwners
    lock.unlock()
    let session = AVAudioSession.sharedInstance()
    return [
      "outputOwners": owners,
      "category": session.category.rawValue,
      "mode": session.mode.rawValue,
      "activeOutputRequired": owners > 0
    ]
  }

  private func configureAndActivate() throws {
    let session = AVAudioSession.sharedInstance()
    try session.setCategory(
      .playAndRecord,
      mode: .default,
      options: [.defaultToSpeaker, .allowBluetoothHFP, .mixWithOthers]
    )
    try session.setPreferredIOBufferDuration(0.02)
    try session.setActive(true)
  }
}

private enum PcmAudioPlayerError: LocalizedError {
  case invalidFormat(sampleRate: Int, channels: Int)
  case testToneWriteRejected
  case outputRequiresForeground

  var errorDescription: String? {
    switch self {
    case let .invalidFormat(sampleRate, channels):
      return "Could not create PCM format for \(sampleRate) Hz / \(channels) channel(s)"
    case .testToneWriteRejected:
      return "PCM test tone could not be queued"
    case .outputRequiresForeground:
      return "Room audio output requires MimiCam to be active in the foreground"
    }
  }
}

private final class PcmAudioPlayer {
  typealias EventEmitter = (_ type: String, _ details: [String: Any]) -> Void

  private let queue = DispatchQueue(label: "com.mimicam.pcm-audio")
  private let eventEmitter: EventEmitter
  private let audioSessionPolicy = SharedAudioSessionPolicy.shared
  private var observers: [NSObjectProtocol] = []
  private var engine: AVAudioEngine?
  private var playerNode: AVAudioPlayerNode?
  private var format: AVAudioFormat?
  private var queuedFrames = 0
  private var playbackGeneration: UInt64 = 0
  private var sampleRate = 0
  private var channels = 0
  private var starts = 0
  private var writesAccepted = 0
  private var writesDropped = 0
  private var writeErrors = 0
  private var bytesWritten = 0
  private var lastStartAtMs = 0
  private var lastWriteAtMs = 0
  private var lastError: String?
  private var interruptionCount = 0
  private var routeChangeCount = 0
  private var mediaServicesResetCount = 0
  private var interrupted = false
  private var backgroundSuspended = false
  private var ownsAudioSessionOutput = false

  init(eventEmitter: @escaping EventEmitter) {
    self.eventEmitter = eventEmitter
    registerAudioSessionObservers()
  }

  deinit {
    for observer in observers {
      NotificationCenter.default.removeObserver(observer)
    }
  }

  func start(sampleRate: Int, channels: Int) throws {
    guard PlatformRuntimeBridge.shared.isApplicationForeground else {
      throw PcmAudioPlayerError.outputRequiresForeground
    }
    let safeSampleRate = min(max(sampleRate, 8000), 48000)
    let safeChannels = max(1, min(channels, 2))
    try queue.sync {
      self.stopLocked(releaseAudioSession: true)
      do {
        try self.startLocked(sampleRate: safeSampleRate, channels: safeChannels)
      } catch {
        self.writeErrors += 1
        self.lastError = "\(type(of: error)): \(error.localizedDescription)"
        self.stopLocked(releaseAudioSession: true)
        throw error
      }
    }
    eventEmitter(
      "audioPlaybackStarted",
      ["sampleRate": safeSampleRate, "channels": safeChannels]
    )
  }

  private func startLocked(sampleRate: Int, channels: Int) throws {
    try audioSessionPolicy.acquireOutput()
    ownsAudioSessionOutput = true

    guard let format = AVAudioFormat(
      commonFormat: .pcmFormatInt16,
      sampleRate: Double(sampleRate),
      channels: AVAudioChannelCount(channels),
      interleaved: true
    ) else {
      throw PcmAudioPlayerError.invalidFormat(
        sampleRate: sampleRate,
        channels: channels
      )
    }
    let engine = AVAudioEngine()
    let playerNode = AVAudioPlayerNode()
    engine.attach(playerNode)
    engine.connect(playerNode, to: engine.mainMixerNode, format: format)
    engine.prepare()
    try engine.start()
    self.engine = engine
    self.playerNode = playerNode
    self.format = format
    self.playbackGeneration &+= 1
    self.sampleRate = sampleRate
    self.channels = channels
    self.starts += 1
    self.lastStartAtMs = Self.nowMs()
    self.interrupted = false
    self.backgroundSuspended = false
    self.lastError = nil
  }

  @discardableResult
  func write(_ data: Data) -> Bool {
    enqueue(data, enforceQueueLimit: true)
  }

  private func enqueue(_ data: Data, enforceQueueLimit: Bool) -> Bool {
    if data.isEmpty { return false }
    return queue.sync {
      guard !self.interrupted,
            !self.backgroundSuspended,
            let playerNode = self.playerNode,
            let format = self.format else {
        self.writesDropped += 1
        self.lastError = self.backgroundSuspended
          ? "write while application is backgrounded"
          : self.interrupted
            ? "write while audio session is interrupted"
            : "write before start"
        return false
      }
      let bytesPerFrame = Int(format.streamDescription.pointee.mBytesPerFrame)
      guard bytesPerFrame > 0 else {
        self.writeErrors += 1
        self.lastError = "invalid bytesPerFrame"
        return false
      }
      let alignedByteCount = data.count - (data.count % bytesPerFrame)
      guard alignedByteCount > 0 else {
        self.writesDropped += 1
        return false
      }
      let frameCount = AVAudioFrameCount(alignedByteCount / bytesPerFrame)
      let maxQueuedFrames = Int(format.sampleRate * 0.24)
      if enforceQueueLimit &&
          self.queuedFrames + Int(frameCount) > maxQueuedFrames {
        self.writesDropped += 1
        return false
      }
      guard let buffer = AVAudioPCMBuffer(
        pcmFormat: format,
        frameCapacity: frameCount
      ) else {
        self.writeErrors += 1
        self.lastError = "AVAudioPCMBuffer allocation failed"
        return false
      }
      buffer.frameLength = frameCount
      data.withUnsafeBytes { source in
        guard let sourceBase = source.baseAddress else { return }
        let audioBufferList = buffer.mutableAudioBufferList
        audioBufferList.pointee.mBuffers.mData?.copyMemory(
          from: sourceBase,
          byteCount: alignedByteCount
        )
        audioBufferList.pointee.mBuffers.mDataByteSize =
          UInt32(alignedByteCount)
      }
      self.queuedFrames += Int(frameCount)
      self.writesAccepted += 1
      self.bytesWritten += alignedByteCount
      self.lastWriteAtMs = Self.nowMs()
      let scheduledGeneration = self.playbackGeneration
      playerNode.scheduleBuffer(
        buffer,
        completionCallbackType: .dataPlayedBack
      ) { [weak self] _ in
        self?.queue.async {
          guard let self else { return }
          guard self.playbackGeneration == scheduledGeneration else { return }
          self.queuedFrames = max(0, self.queuedFrames - Int(frameCount))
        }
      }
      if !playerNode.isPlaying {
        playerNode.play()
      }
      return true
    }
  }

  func playTestTone(
    sampleRate: Int,
    channels: Int,
    durationMs: Int,
    frequencyHz: Int,
    amplitude: Double
  ) throws {
    let safeSampleRate = min(max(sampleRate, 8000), 48000)
    let safeChannels = max(1, min(channels, 2))
    let safeDurationMs = min(max(durationMs, 100), 5000)
    let safeFrequencyHz = min(max(frequencyHz, 80), 2000)
    let safeAmplitude = min(max(amplitude, 0.02), 0.80)
    let frameCount = safeSampleRate * safeDurationMs / 1000
    var data = Data(capacity: frameCount * safeChannels * 2)
    let amplitudeInt = Int(32767.0 * safeAmplitude)
    for frame in 0..<frameCount {
      let sample = Int(
        sin(2.0 * Double.pi * Double(safeFrequencyHz) * Double(frame) / Double(safeSampleRate))
          * Double(amplitudeInt)
      )
      for _ in 0..<safeChannels {
        data.append(UInt8(sample & 0xff))
        data.append(UInt8((sample >> 8) & 0xff))
      }
    }
    try start(sampleRate: safeSampleRate, channels: safeChannels)
    guard enqueue(data, enforceQueueLimit: false) else {
      throw PcmAudioPlayerError.testToneWriteRejected
    }
  }

  func status() -> [String: Any] {
    queue.sync {
      [
        "started": playerNode != nil,
        "sampleRate": sampleRate,
        "channels": channels,
        "queuedFrames": queuedFrames,
        "queuedAudioMs": sampleRate > 0 ? queuedFrames * 1000 / sampleRate : 0,
        "starts": starts,
        "writesAccepted": writesAccepted,
        "writesDropped": writesDropped,
        "writeErrors": writeErrors,
        "bytesWritten": bytesWritten,
        "lastStartAtMs": lastStartAtMs,
        "lastWriteAtMs": lastWriteAtMs,
        "lastError": lastError ?? NSNull(),
        "playing": playerNode?.isPlaying ?? false,
        "interrupted": interrupted,
        "backgroundSuspended": backgroundSuspended,
        "interruptionCount": interruptionCount,
        "routeChangeCount": routeChangeCount,
        "mediaServicesResetCount": mediaServicesResetCount,
        "outputRoute": Self.outputRouteDetails(),
        "audioSessionPolicy": audioSessionPolicy.status()
      ]
    }
  }

  func stop() {
    queue.async { [weak self] in
      self?.stopLocked(releaseAudioSession: true)
      self?.eventEmitter("audioPlaybackStopped", [:])
    }
  }

  private func stopLocked(releaseAudioSession: Bool) {
    playbackGeneration &+= 1
    playerNode?.stop()
    if let node = playerNode {
      engine?.detach(node)
    }
    engine?.stop()
    playerNode = nil
    engine = nil
    format = nil
    queuedFrames = 0
    interrupted = false
    backgroundSuspended = false
    if releaseAudioSession && ownsAudioSessionOutput {
      audioSessionPolicy.releaseOutput()
      ownsAudioSessionOutput = false
    }
  }

  private func registerAudioSessionObservers() {
    let center = NotificationCenter.default
    observers.append(center.addObserver(
      forName: AVAudioSession.interruptionNotification,
      object: nil,
      queue: nil
    ) { [weak self] notification in
      self?.handleInterruption(notification)
    })
    observers.append(center.addObserver(
      forName: AVAudioSession.routeChangeNotification,
      object: nil,
      queue: nil
    ) { [weak self] notification in
      self?.handleRouteChange(notification)
    })
    observers.append(center.addObserver(
      forName: AVAudioSession.mediaServicesWereResetNotification,
      object: nil,
      queue: nil
    ) { [weak self] _ in
      self?.handleMediaServicesReset()
    })
    observers.append(center.addObserver(
      forName: UIApplication.willResignActiveNotification,
      object: nil,
      queue: nil
    ) { [weak self] _ in
      self?.suspendOutputForBackground()
    })
    observers.append(center.addObserver(
      forName: UIApplication.didBecomeActiveNotification,
      object: nil,
      queue: nil
    ) { [weak self] _ in
      self?.recoverOutputFromBackground()
    })
  }

  private func handleInterruption(_ notification: Notification) {
    guard let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
          let type = AVAudioSession.InterruptionType(rawValue: rawType) else {
      return
    }
    switch type {
    case .began:
      queue.async { [weak self] in
        guard let self else { return }
        self.interruptionCount += 1
        self.interrupted = true
        self.playerNode?.pause()
        self.eventEmitter("audioInterruptionBegan", [:])
      }
    case .ended:
      let rawOptions = notification.userInfo?[AVAudioSessionInterruptionOptionKey]
        as? UInt ?? 0
      let shouldResume = AVAudioSession.InterruptionOptions(rawValue: rawOptions)
        .contains(.shouldResume)
      queue.async { [weak self] in
        guard let self else { return }
        var recovered = false
        if shouldResume,
           !self.backgroundSuspended,
           self.playerNode != nil {
          do {
            try self.audioSessionPolicy.recoverOutputIfNeeded()
            if let engine = self.engine, !engine.isRunning {
              try engine.start()
            }
            self.playerNode?.play()
            self.interrupted = false
            recovered = true
          } catch {
            self.lastError = "interruption recovery: \(error.localizedDescription)"
            self.writeErrors += 1
          }
        }
        self.eventEmitter(
          "audioInterruptionEnded",
          ["shouldResume": shouldResume, "recovered": recovered]
        )
      }
    @unknown default:
      break
    }
  }

  private func handleRouteChange(_ notification: Notification) {
    let rawReason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey]
      as? UInt ?? 0
    queue.async { [weak self] in
      guard let self else { return }
      self.routeChangeCount += 1
      self.eventEmitter(
        "audioRouteChanged",
        [
          "reason": Int(rawReason),
          "outputs": Self.outputRouteDetails()
        ]
      )
    }
  }

  private func handleMediaServicesReset() {
    queue.async { [weak self] in
      guard let self else { return }
      self.mediaServicesResetCount += 1
      let shouldRestart = self.playerNode != nil && self.sampleRate > 0
      let shouldRemainBackgroundSuspended = self.backgroundSuspended
      let previousSampleRate = self.sampleRate
      let previousChannels = self.channels
      self.stopLocked(releaseAudioSession: true)
      var recovered = false
      if shouldRestart {
        do {
          try self.startLocked(
            sampleRate: previousSampleRate,
            channels: previousChannels
          )
          if shouldRemainBackgroundSuspended {
            self.backgroundSuspended = true
            self.playerNode?.pause()
          }
          recovered = true
        } catch {
          self.writeErrors += 1
          self.lastError = "media services reset: \(error.localizedDescription)"
        }
      }
      self.eventEmitter(
        "audioMediaServicesReset",
        [
          "recovered": recovered,
          "outputActive": recovered && !shouldRemainBackgroundSuspended
        ]
      )
    }
  }

  private func suspendOutputForBackground() {
    queue.async { [weak self] in
      guard let self, self.playerNode != nil, !self.backgroundSuspended else {
        return
      }
      self.backgroundSuspended = true
      self.playerNode?.pause()
      self.eventEmitter(
        "audioOutputSuspendedForBackground",
        ["backgroundOutputSupported": false]
      )
    }
  }

  private func recoverOutputFromBackground() {
    queue.async { [weak self] in
      guard let self, self.backgroundSuspended, self.playerNode != nil else {
        return
      }
      var recovered = false
      do {
        try self.audioSessionPolicy.recoverOutputIfNeeded()
        if let engine = self.engine, !engine.isRunning {
          try engine.start()
        }
        self.playerNode?.play()
        self.backgroundSuspended = false
        self.interrupted = false
        recovered = true
      } catch {
        self.writeErrors += 1
        self.lastError = "background recovery: \(error.localizedDescription)"
      }
      self.eventEmitter(
        "audioOutputResumedFromBackground",
        ["recovered": recovered]
      )
    }
  }

  private static func outputRouteDetails() -> [[String: Any]] {
    AVAudioSession.sharedInstance().currentRoute.outputs.map {
      [
        "uid": $0.uid,
        "name": $0.portName,
        "type": $0.portType.rawValue
      ]
    }
  }

  private static func nowMs() -> Int {
    Int(Date().timeIntervalSince1970 * 1000)
  }
}
