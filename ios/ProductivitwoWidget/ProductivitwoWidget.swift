// ProductivitwoWidget.swift
// Widget iOS home screen — Small (anneau routines) + Medium (plan du jour)

import WidgetKit
import SwiftUI

// MARK: - Constantes

private let appGroup = "group.com.madabinghy.productivitwo"

// MARK: - Modèles de données

struct PlanItem: Identifiable, Decodable {
    let id = UUID()
    let title: String
    let done: Bool
    enum CodingKeys: String, CodingKey { case title, done }
}

struct WidgetData {
    let routinesDone: Int
    let routinesTotal: Int
    let planItems: [PlanItem]

    static func load() -> WidgetData {
        let defaults = UserDefaults(suiteName: appGroup)
        let done  = defaults?.integer(forKey: "routines_done")  ?? 0
        let total = defaults?.integer(forKey: "routines_total") ?? 0
        var items: [PlanItem] = []
        if let raw = defaults?.string(forKey: "plan_json"),
           let data = raw.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([PlanItem].self, from: data) {
            items = decoded
        }
        return WidgetData(routinesDone: done, routinesTotal: total, planItems: items)
    }

    var routineRatio: Double {
        routinesTotal > 0 ? Double(routinesDone) / Double(routinesTotal) : 0
    }
}

// MARK: - Timeline provider

struct ProductivitwoEntry: TimelineEntry {
    let date: Date
    let data: WidgetData
}

struct ProductivitwoProvider: TimelineProvider {
    func placeholder(in context: Context) -> ProductivitwoEntry {
        ProductivitwoEntry(date: Date(), data: WidgetData(
            routinesDone: 3,
            routinesTotal: 5,
            planItems: [
                PlanItem(title: "Méditation", done: true),
                PlanItem(title: "Sport 30 min", done: false),
                PlanItem(title: "Revue emails", done: false),
                PlanItem(title: "Deep work", done: false),
            ]
        ))
    }

    func getSnapshot(in context: Context, completion: @escaping (ProductivitwoEntry) -> Void) {
        completion(ProductivitwoEntry(date: Date(), data: WidgetData.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ProductivitwoEntry>) -> Void) {
        let entry = ProductivitwoEntry(date: Date(), data: WidgetData.load())
        let next = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
        let timeline = Timeline(entries: [entry], policy: .after(next))
        completion(timeline)
    }
}

// MARK: - Couleurs de marque

private let brandPurple   = Color(red: 0.42, green: 0.18, blue: 0.88)
private let brandPurpleFg = Color(red: 0.85, green: 0.75, blue: 1.00)

// MARK: - Widget Small : anneau de routines

struct SmallWidgetView: View {
    let data: WidgetData
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ZStack {
            ContainerRelativeShape()
                .fill(colorScheme == .dark
                      ? Color(white: 0.10)
                      : Color(white: 0.97))

            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .stroke(brandPurple.opacity(0.18), lineWidth: 10)
                    Circle()
                        .trim(from: 0, to: data.routineRatio)
                        .stroke(brandPurple, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.easeOut(duration: 0.6), value: data.routineRatio)

                    VStack(spacing: 1) {
                        Text("\(Int(data.routineRatio * 100))%")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundColor(brandPurple)
                        Text("\(data.routinesDone)/\(data.routinesTotal)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }
                .frame(width: 80, height: 80)

                Text("Routines")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.8)
            }
            .padding(12)
        }
    }
}

// MARK: - Widget Medium : plan du jour

struct MediumWidgetView: View {
    let data: WidgetData
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ZStack {
            ContainerRelativeShape()
                .fill(colorScheme == .dark
                      ? Color(white: 0.10)
                      : Color(white: 0.97))

            HStack(alignment: .top, spacing: 14) {
                // Colonne gauche : anneau compact
                VStack(spacing: 4) {
                    ZStack {
                        Circle()
                            .stroke(brandPurple.opacity(0.18), lineWidth: 7)
                        Circle()
                            .trim(from: 0, to: data.routineRatio)
                            .stroke(brandPurple, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        VStack(spacing: 0) {
                            Text("\(Int(data.routineRatio * 100))%")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundColor(brandPurple)
                        }
                    }
                    .frame(width: 54, height: 54)

                    Text("\(data.routinesDone)/\(data.routinesTotal)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)

                    Text("routines")
                        .font(.system(size: 9, weight: .regular))
                        .foregroundColor(.secondary.opacity(0.7))
                }
                .frame(width: 58)

                Rectangle()
                    .fill(brandPurple.opacity(0.15))
                    .frame(width: 1)
                    .padding(.vertical, 4)

                // Colonne droite : plan du jour
                VStack(alignment: .leading, spacing: 0) {
                    Text("Aujourd'hui")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                        .tracking(0.6)
                        .padding(.bottom, 6)

                    if data.planItems.isEmpty {
                        Text("Aucune action planifiée")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary.opacity(0.6))
                            .italic()
                    } else {
                        ForEach(Array(data.planItems.prefix(4).enumerated()), id: \.offset) { _, item in
                            PlanRowView(item: item)
                                .padding(.bottom, 5)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
    }
}

struct PlanRowView: View {
    let item: PlanItem

    var body: some View {
        HStack(spacing: 7) {
            ZStack {
                Circle()
                    .fill(item.done ? brandPurple : Color.clear)
                    .overlay(Circle().stroke(
                        item.done ? brandPurple : Color.secondary.opacity(0.35),
                        lineWidth: 1.2))
                    .frame(width: 14, height: 14)

                if item.done {
                    Image(systemName: "checkmark")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundColor(.white)
                }
            }

            Text(item.title)
                .font(.system(size: 12.5, weight: item.done ? .regular : .medium))
                .foregroundColor(item.done ? .secondary : .primary)
                .strikethrough(item.done, color: .secondary)
                .lineLimit(1)
        }
    }
}

// MARK: - Extension principale

struct ProductivitwoWidget: Widget {
    let kind: String = "ProductivitwoWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ProductivitwoProvider()) { entry in
            ProductivitwoWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Productivitwo")
        .description("Routines et plan du jour")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct ProductivitwoWidgetEntryView: View {
    let entry: ProductivitwoEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .systemSmall:
            SmallWidgetView(data: entry.data)
        case .systemMedium:
            MediumWidgetView(data: entry.data)
        default:
            SmallWidgetView(data: entry.data)
        }
    }
}

// MARK: - Bundle
// L'entry point @main est dans ProductivitwoWidgetBundle.swift (généré par Xcode)

// MARK: - Preview

#Preview(as: .systemSmall) {
    ProductivitwoWidget()
} timeline: {
    ProductivitwoEntry(date: .now, data: WidgetData(
        routinesDone: 3, routinesTotal: 5,
        planItems: []
    ))
}

#Preview(as: .systemMedium) {
    ProductivitwoWidget()
} timeline: {
    ProductivitwoEntry(date: .now, data: WidgetData(
        routinesDone: 3, routinesTotal: 5,
        planItems: [
            PlanItem(title: "Méditation", done: true),
            PlanItem(title: "Sport 30 min", done: false),
            PlanItem(title: "Deep work", done: false),
            PlanItem(title: "Revue emails", done: false),
        ]
    ))
}
