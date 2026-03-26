import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    if let controller = window?.rootViewController as? FlutterViewController {
      AlarmKitBridge.shared.register(binaryMessenger: controller.binaryMessenger)
    }
  }

  override func stateRestorationActivity(for scene: UIScene) -> NSUserActivity? {
    nil
  }

  override func scene(
    _ scene: UIScene,
    restoreInteractionStateWith stateRestorationActivity: NSUserActivity
  ) {
    // Intentionally ignore any restored scene state so onboarding always
    // starts from our explicit app-controlled state.
  }
}
