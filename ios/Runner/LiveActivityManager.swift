import Foundation

#if canImport(ActivityKit)
import ActivityKit

// Gère la Live Activity « minuteur » (ActivityKit). Une seule active à la fois.
@available(iOS 16.1, *)
final class LiveActivityManager {
  static let shared = LiveActivityManager()
  private init() {}

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
          pushType: nil)
      } else {
        activity = try Activity.request(attributes: attributes, contentState: state)
      }
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

  // (Phase 2) Token push‑to‑start (iOS 17.2+) pour démarrage distant app fermée.
  @available(iOS 17.2, *)
  func pushToStartToken(_ completion: @escaping (String?) -> Void) {
    Task {
      for await data in Activity<TimerActivityAttributes>.pushToStartTokenUpdates {
        completion(data.map { String(format: "%02x", $0) }.joined())
        return
      }
      completion(nil)
    }
  }
}
#endif
