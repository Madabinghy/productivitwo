import UIKit
import Flutter
import WidgetKit
import UserNotifications
import AppIntents
import alarm

// Cycle de vie « UIScene » (obligatoire à partir d'iOS 27 : sans lui l'app se
// ferme dès le lancement). La fenêtre n'existe plus dans
// `didFinishLaunchingWithOptions` : les plugins et les canaux se branchent
// dans `didInitializeImplicitFlutterEngine`, quand le moteur est prêt.
@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let appGroup = "group.com.madabinghy.productivitwo"
  private let channelName = "com.madabinghy.productivitwo/widget"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Package `alarm` : délégué notifications + enregistrement des background tasks
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self as UNUserNotificationCenterDelegate
    }
    SwiftAlarmPlugin.registerBackgroundTasks()

    // Sous UIScene, `applicationDidBecomeActive` n'est plus appelé : on écoute
    // la notification, toujours émise.
    NotificationCenter.default.addObserver(
      forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
    ) { _ in
      UIApplication.shared.applicationIconBadgeNumber = 0
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let messenger = engineBridge.applicationRegistrar.messenger()

    // Method channel pour écrire directement dans le UserDefaults de l'App Group
    // — bypass home_widget plugin qui peut écrire dans la mauvaise suite sur iOS.
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] (call, result) in
      guard let self = self else { result(FlutterError(code: "DEALLOC", message: nil, details: nil)); return }
      guard let defaults = UserDefaults(suiteName: self.appGroup) else {
        result(FlutterError(code: "NO_GROUP", message: "App Group introuvable", details: nil)); return
      }
      let args = call.arguments as? [String: Any] ?? [:]

      switch call.method {
      case "setInt":
        if let key = args["key"] as? String, let value = args["value"] as? Int {
          defaults.set(value, forKey: key); result(true)
        } else { result(false) }
      case "setString":
        if let key = args["key"] as? String, let value = args["value"] as? String {
          defaults.set(value, forKey: key); result(true)
        } else { result(false) }
      case "getInt":
        if let key = args["key"] as? String { result(defaults.integer(forKey: key)) }
        else { result(0) }
      case "getString":
        if let key = args["key"] as? String { result(defaults.string(forKey: key)) }
        else { result(nil) }
      case "reload":
        if #available(iOS 14.0, *) { WidgetCenter.shared.reloadAllTimelines() }
        result(true)
      case "updateSiriShortcuts":
        // Rafraîchit les options des raccourcis Siri (ex : liste des routines).
        if #available(iOS 16.0, *) { ProductivitwoShortcuts.updateAppShortcutParameters() }
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    // Method channel Live Activity (minuteur ActivityKit) — délégué au manager.
    let laChannel = FlutterMethodChannel(
      name: "productivitwo/live_activity", binaryMessenger: messenger)
    laChannel.setMethodCallHandler { (call, result) in
      let args = call.arguments as? [String: Any] ?? [:]
      switch call.method {
      case "start":
        if #available(iOS 16.1, *) {
          let id = LiveActivityManager.shared.start(
            name: args["name"] as? String ?? "Activité",
            startAtMs: (args["startAtMs"] as? Int) ?? 0,
            colorArgb: (args["colorArgb"] as? Int) ?? 0xFF4F8DF7)
          result(id)
        } else { result(nil) }
      case "end":
        if #available(iOS 16.1, *) {
          LiveActivityManager.shared.end(id: args["id"] as? String)
        }
        result(nil)
      case "pushToStartToken":
        if #available(iOS 17.2, *) {
          LiveActivityManager.shared.pushToStartToken { token in result(token) }
        } else { result(nil) }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
