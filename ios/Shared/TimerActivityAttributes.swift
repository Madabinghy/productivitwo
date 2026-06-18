import Foundation

#if canImport(ActivityKit)
import ActivityKit

// ⚠️ Xcode : ce fichier doit appartenir aux DEUX targets (Runner + ProductivitwoWidget)
// via « Target Membership », car le type ActivityAttributes doit être partagé entre
// l'app (qui démarre/termine) et l'extension widget (qui affiche).
@available(iOS 16.1, *)
struct TimerActivityAttributes: ActivityAttributes {
  public struct ContentState: Codable, Hashable {
    /// Début de la session (ms epoch) — le minuteur compte AU‑DESSUS depuis cette date.
    var startAtMs: Int
    var paused: Bool
  }

  /// Nom de l'activité/routine (fixe pendant la Live Activity).
  var name: String
  /// Couleur d'accent ARGB (du domaine).
  var colorArgb: Int
}
#endif
