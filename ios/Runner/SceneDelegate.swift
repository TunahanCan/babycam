import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  override func sceneDidBecomeActive(_ scene: UIScene) {
    super.sceneDidBecomeActive(scene)
    PlatformRuntimeBridge.shared.setApplicationState("foregroundActive")
  }

  override func sceneWillResignActive(_ scene: UIScene) {
    PlatformRuntimeBridge.shared.setApplicationState("inactive")
    super.sceneWillResignActive(scene)
  }

  override func sceneWillEnterForeground(_ scene: UIScene) {
    super.sceneWillEnterForeground(scene)
    PlatformRuntimeBridge.shared.setApplicationState("foreground")
  }

  override func sceneDidEnterBackground(_ scene: UIScene) {
    PlatformRuntimeBridge.shared.setApplicationState("background")
    super.sceneDidEnterBackground(scene)
  }
}
