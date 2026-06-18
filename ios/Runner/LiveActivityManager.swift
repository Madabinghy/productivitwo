import Foundation
import Flutter

#if canImport(ActivityKit)
import ActivityKit

// Gère la Live Activity « minuteur » (ActivityKit). Une seule active à la fois.
// Observe aussi les tokens APNs (push‑to‑start + token d'activité) et les renvoie à
// Dart (→ Firestore) pour le démarrage/fin distant app fermée (cf. Cloud Function APNs).
@available(iOS 16.1, *)
final class LiveActivityManager {
  static let shared = LiveActivityManager()
  private init() {}

  weak var channel: FlutterMethodChannel?
  private var startedObserver = false

  /// Démarre (en terminant l'éventuelle précédente) une Live Activity comptant
  /// au‑dessus depuis `startAtMs`. Retourne l'id, ou nil si indisponible.
  @discardableResult
  func start(name: String, startAtMs: Int, colorArgb: Int) -> String? {
    guard ActivityAuthorizationInfo().areActivitiesEnabled else { return nil }
    end(id: nil) // une seule à la fois
    let attributes = TimerActivityAttributes(name: name, colorArgb: colorArgb)
    let state = TimerActivityAttributes.ContentState(startAtMs: startAtMs, paused: false)
    do {
      let activity: Activity<TimerActivityAttributes>
      if #available(iOS 16.2, *) {
        activity = try Activity.request(
          attributes: attributes,
          content: .init(state: state, staleDate: nil),
          pushType: .token) // token → on peut la METTRE À JOUR / TERMINER à distance
      } else {
        activity = try Activity.request(attributes: attributes, contentState: state)
      }
      observeActivityToken(activity)
      return activity.id
    } catch {
      return nil
    }
  }

  /// Termine la Live Activity d'`id` (ou toutes celles du minuteur si nil).
  func end(id: String?) {
    Task {
      for activity in Activity<TimerActivityAttributes>.activities where id == nil || activity.id == id {
        if #available(iOS 16.2, *) {
          await activity.end(nil, dismissalPolicy: .immediate)
        } else {
          await activity.end(dismissalPolicy: .immediate)
        }
      }
    }
  }

  // Token de mise à jour d'une activité donnée → Dart (pour pousser un « end » distant).
  private func observeActivityToken(_ activity: Activity<TimerActivityAttributes>) {
    Task {
      for await tokenData in activity.pushTokenUpdates {
        let token = tokenData.map { String(format: "%02x", $0) }.joined()
        await MainActor.run {
          self.channel?.invokeMethod("onActivityToken",
                                     arguments: ["id": activity.id, "token": token])
        }
      }
    }
  }

  /// (iOS 17.2+) Observe les tokens push‑to‑start (permet de DÉMARRER une Live
  /// Activity à distance, app fermée) → renvoyés à Dart.
  @available(iOS 17.2, *)
  func registerPushToStart() {
    guard !startedObserver else { return }
    startedObserver = true
    Task {
      for await tokenData in Activity<TimerActivityAttributes>.pushToStartTokenUpdates {
        let token = tokenData.map { String(format: "%02x", $0) }.joined()
        await MainActor.run {
          self.channel?.invokeMethod("onPushToStartToken", arguments: token)
        }
      }
    }
    // Récupère aussi le token des activités déjà actives (relancement de l'app).
    for activity in Activity<TimerActivityAttributes>.activities {
      observeActivityToken(activity)
    }
  }
}
#endif
