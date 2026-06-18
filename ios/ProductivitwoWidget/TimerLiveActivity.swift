import Foundation

#if canImport(ActivityKit)
import ActivityKit
import SwiftUI
import WidgetKit

// Live Activity « minuteur » : écran verrouillé + Dynamic Island. Le compte au‑dessus
// est rendu PAR iOS via `Text(_, style: .timer)` → aucun push par seconde nécessaire.
@available(iOS 16.1, *)
struct TimerLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: TimerActivityAttributes.self) { context in
      let start = Date(timeIntervalSince1970: Double(context.state.startAtMs) / 1000.0)
      HStack(spacing: 12) {
        Image(systemName: "timer")
          .font(.title2)
          .foregroundColor(Color(argb: context.attributes.colorArgb))
        VStack(alignment: .leading, spacing: 2) {
          Text(context.attributes.name).font(.headline).lineLimit(1)
          Text(start, style: .timer).font(.title3).monospacedDigit()
        }
        Spacer()
      }
      .padding()
      .activityBackgroundTint(Color.black.opacity(0.6))
      .activitySystemActionForegroundColor(Color.white)
    } dynamicIsland: { context in
      let start = Date(timeIntervalSince1970: Double(context.state.startAtMs) / 1000.0)
      return DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          Image(systemName: "timer")
            .foregroundColor(Color(argb: context.attributes.colorArgb))
        }
        DynamicIslandExpandedRegion(.center) {
          Text(context.attributes.name).font(.caption).lineLimit(1)
        }
        DynamicIslandExpandedRegion(.trailing) {
          Text(start, style: .timer).monospacedDigit().frame(maxWidth: 64)
        }
      } compactLeading: {
        Image(systemName: "timer")
          .foregroundColor(Color(argb: context.attributes.colorArgb))
      } compactTrailing: {
        Text(start, style: .timer).monospacedDigit().frame(maxWidth: 44)
      } minimal: {
        Image(systemName: "timer")
      }
    }
  }
}

@available(iOS 16.1, *)
extension Color {
  init(argb: Int) {
    self.init(
      .sRGB,
      red: Double((argb >> 16) & 0xFF) / 255.0,
      green: Double((argb >> 8) & 0xFF) / 255.0,
      blue: Double(argb & 0xFF) / 255.0,
      opacity: Double((argb >> 24) & 0xFF) / 255.0)
  }
}
#endif
