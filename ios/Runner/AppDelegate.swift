import AVFoundation
import Flutter
import Network
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let cameraPermissionRequester = CameraPermissionRequester()
  private let localNetworkPermissionRequester = LocalNetworkPermissionRequester()
  private let pcmAudioPlayer = PcmAudioPlayer()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    registerCameraPermissionChannel()
    registerLocalNetworkPermissionChannel()
    registerPcmAudioChannel()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
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
        self.pcmAudioPlayer.start(sampleRate: sampleRate, channels: channels)
        result(nil)
      case "write":
        if let typed = call.arguments as? FlutterStandardTypedData {
          self.pcmAudioPlayer.write(typed.data)
        }
        result(nil)
      case "stop":
        self.pcmAudioPlayer.stop()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
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

private final class PcmAudioPlayer {
  private let queue = DispatchQueue(label: "com.mimicam.pcm-audio")
  private var engine: AVAudioEngine?
  private var playerNode: AVAudioPlayerNode?
  private var format: AVAudioFormat?
  private var queuedFrames = 0

  func start(sampleRate: Int, channels: Int) {
    let safeSampleRate = max(sampleRate, 8000)
    let safeChannels = max(1, min(channels, 2))
    queue.async { [weak self] in
      guard let self else { return }
      self.stopLocked()
      do {
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(
          .playback,
          mode: .default,
          options: [.mixWithOthers]
        )
        try audioSession.setActive(true)

        guard let format = AVAudioFormat(
          commonFormat: .pcmFormatInt16,
          sampleRate: Double(safeSampleRate),
          channels: AVAudioChannelCount(safeChannels),
          interleaved: true
        ) else {
          return
        }
        let engine = AVAudioEngine()
        let playerNode = AVAudioPlayerNode()
        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)
        try engine.start()
        playerNode.play()
        self.engine = engine
        self.playerNode = playerNode
        self.format = format
      } catch {
        self.stopLocked()
      }
    }
  }

  func write(_ data: Data) {
    if data.isEmpty { return }
    queue.async { [weak self] in
      guard let self,
            let playerNode = self.playerNode,
            let format = self.format else {
        return
      }
      let bytesPerFrame = Int(format.streamDescription.pointee.mBytesPerFrame)
      guard bytesPerFrame > 0 else { return }
      let alignedByteCount = data.count - (data.count % bytesPerFrame)
      guard alignedByteCount > 0 else { return }
      let frameCount = AVAudioFrameCount(alignedByteCount / bytesPerFrame)
      let maxQueuedFrames = Int(format.sampleRate * 0.6)
      if self.queuedFrames > maxQueuedFrames {
        return
      }
      guard let buffer = AVAudioPCMBuffer(
        pcmFormat: format,
        frameCapacity: frameCount
      ) else {
        return
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
      if !playerNode.isPlaying {
        playerNode.play()
      }
      self.queuedFrames += Int(frameCount)
      playerNode.scheduleBuffer(buffer) { [weak self] in
        self?.queue.async {
          guard let self else { return }
          self.queuedFrames = max(0, self.queuedFrames - Int(frameCount))
        }
      }
    }
  }

  func stop() {
    queue.async { [weak self] in
      self?.stopLocked()
    }
  }

  private func stopLocked() {
    playerNode?.stop()
    if let node = playerNode {
      engine?.detach(node)
    }
    engine?.stop()
    playerNode = nil
    engine = nil
    format = nil
    queuedFrames = 0
  }
}
