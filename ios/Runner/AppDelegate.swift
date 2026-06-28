import AVFoundation
import Flutter
import Network
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let cameraPermissionRequester = CameraPermissionRequester()
  private let localNetworkPermissionRequester = LocalNetworkPermissionRequester()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    registerCameraPermissionChannel()
    registerLocalNetworkPermissionChannel()
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
