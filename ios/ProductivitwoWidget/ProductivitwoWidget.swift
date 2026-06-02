// ProductivitwoWidget.swift
// Widget iOS home screen — Small (anneau routines) + Medium (top 4 tâches Gantt) + Large (Gantt groupé)

import WidgetKit
import SwiftUI

// MARK: - Constantes

private let appGroup = "group.com.madabinghy.productivitwo"

// MARK: - Modèles de données

struct GanttTask: Identifiable, Decodable {
    let id = UUID()
    let project: String
    let task: String
    let done: Int
    let total: Int
    enum CodingKeys: String, CodingKey { case project, task, done, total }

    var progress: Double { total > 0 ? Double(done) / Double(total) : 0 }
    var isDone: Bool { total > 0 && done >= total }
}

struct WidgetData {
    let routinesDone: Int
    let routinesTotal: Int
    let ganttTasks: [GanttTask]
    let lastUpdate: String?   // sentinel écrit par l'app — diagnostic App Group

    static func load() -> WidgetData {
        let defaults = UserDefaults(suiteName: appGroup)
        let done  = defaults?.integer(forKey: "routines_done")  ?? 0
        let total = defaults?.integer(forKey: "routines_total") ?? 0
        var tasks: [GanttTask] = []
        if let raw = defaults?.string(forKey: "gantt_json"),
           let data = raw.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([GanttTask].self, from: data) {
            tasks = decoded
        }
        let last = defaults?.string(forKey: "last_update")
        return WidgetData(routinesDone: done, routinesTotal: total, ganttTasks: tasks, lastUpdate: last)
    }

    var routineRatio: Double {
        routinesTotal > 0 ? Double(routinesDone) / Double(routinesTotal) : 0
    }

    // Ligne de diagnostic temporaire (App Group / données partagées).
    var diagText: String {
        let maj = lastUpdate.map { String($0.suffix(8)) } ?? "jamais"
        return "sync \(maj) · R\(routinesTotal) G\(ganttTasks.count)"
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
            routinesDone: 3, routinesTotal: 5,
            ganttTasks: [
                GanttTask(project: "Mon App", task: "Développer le backend", done: 2, total: 5),
                GanttTask(project: "Mon App", task: "Design UI", done: 3, total: 3),
                GanttTask(project: "Lancement", task: "Rédiger la landing page", done: 0, total: 4),
                GanttTask(project: "Lancement", task: "Préparer les visuels", done: 1, total: 2),
            ],
            lastUpdate: "preview"
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

private let brandPurple = Color(red: 0.42, green: 0.18, blue: 0.88)

// MARK: - Widget Small : anneau de routines

struct SmallWidgetView: View {
    let data: WidgetData
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ZStack {
            ContainerRelativeShape()
                .fill(colorScheme == .dark ? Color(white: 0.10) : Color(white: 0.97))

            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .stroke(brandPurple.opacity(0.18), lineWidth: 10)
                    Circle()
                        .trim(from: 0, to: data.routineRatio)
                        .stroke(brandPurple, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90))

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

// MARK: - Widget Medium : anneau routines + top 4 tâches Gantt

struct MediumWidgetView: View {
    let data: WidgetData
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ZStack {
            ContainerRelativeShape()
                .fill(colorScheme == .dark ? Color(white: 0.10) : Color(white: 0.97))

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
                        Text("\(Int(data.routineRatio * 100))%")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundColor(brandPurple)
                    }
                    .frame(width: 54, height: 54)

                    Text("\(data.routinesDone)/\(data.routinesTotal)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)

                    Text("routines")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary.opacity(0.7))
                }
                .frame(width: 58)

                Rectangle()
                    .fill(brandPurple.opacity(0.15))
                    .frame(width: 1)
                    .padding(.vertical, 4)

                // Colonne droite : top 4 tâches Gantt actives
                VStack(alignment: .leading, spacing: 0) {
                    Text("Tâches actives")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                        .tracking(0.6)
                        .padding(.bottom, 6)

                    if data.ganttTasks.isEmpty {
                        Text("Aucune tâche active\n\(data.diagText)")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary.opacity(0.6))
                            .italic()
                    } else {
                        ForEach(data.ganttTasks.prefix(4)) { task in
                            GanttTaskRow(task: task)
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

// MARK: - Widget Large : tâches Gantt actives

struct LargeWidgetView: View {
    let data: WidgetData
    @Environment(\.colorScheme) var colorScheme

    private var grouped: [(project: String, tasks: [GanttTask])] {
        var order: [String] = []
        var dict: [String: [GanttTask]] = [:]
        for t in data.ganttTasks {
            if dict[t.project] == nil { order.append(t.project); dict[t.project] = [] }
            dict[t.project]!.append(t)
        }
        return order.map { (project: $0, tasks: dict[$0]!) }
    }

    var body: some View {
        ZStack {
            ContainerRelativeShape()
                .fill(colorScheme == .dark ? Color(white: 0.10) : Color(white: 0.97))

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .stroke(brandPurple.opacity(0.18), lineWidth: 6)
                        Circle()
                            .trim(from: 0, to: data.routineRatio)
                            .stroke(brandPurple, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Text("\(Int(data.routineRatio * 100))%")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(brandPurple)
                    }
                    .frame(width: 42, height: 42)

                    VStack(alignment: .leading, spacing: 1) {
                        Text("Projets actifs")
                            .font(.system(size: 14, weight: .bold))
                        Text("\(data.ganttTasks.count) tâche\(data.ganttTasks.count > 1 ? "s" : "") · \(data.routinesDone)/\(data.routinesTotal) rout. · \(data.diagText)")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(.bottom, 10)

                Divider().opacity(0.4).padding(.bottom, 8)

                if data.ganttTasks.isEmpty {
                    Spacer()
                    HStack {
                        Spacer()
                        Text("Aucune tâche active")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary.opacity(0.6))
                            .italic()
                        Spacer()
                    }
                    Spacer()
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(grouped, id: \.project) { group in
                            Text(group.project.uppercased())
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(brandPurple.opacity(0.8))
                                .tracking(0.8)
                                .padding(.bottom, 4)
                                .padding(.top, 6)

                            ForEach(group.tasks) { task in
                                GanttTaskRow(task: task)
                                    .padding(.bottom, 5)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
    }
}

struct GanttTaskRow: View {
    let task: GanttTask

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(task.isDone ? brandPurple : Color.clear)
                    .overlay(Circle().stroke(
                        task.isDone ? brandPurple : Color.secondary.opacity(0.3),
                        lineWidth: 1.2))
                    .frame(width: 14, height: 14)
                if task.isDone {
                    Image(systemName: "checkmark")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundColor(.white)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(task.task)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundColor(task.isDone ? .secondary : .primary)
                    .strikethrough(task.isDone, color: .secondary)
                    .lineLimit(1)

                if task.total > 0 {
                    HStack(spacing: 4) {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(brandPurple.opacity(0.15))
                                    .frame(height: 3)
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(brandPurple)
                                    .frame(width: geo.size.width * task.progress, height: 3)
                            }
                        }
                        .frame(height: 3)

                        Text("\(task.done)/\(task.total)")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                            .frame(width: 28, alignment: .trailing)
                    }
                }
            }
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
        .description("Routines et tâches Gantt actives")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct ProductivitwoWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: ProductivitwoEntry

    var body: some View {
        switch family {
        case .systemSmall:  SmallWidgetView(data: entry.data)
        case .systemMedium: MediumWidgetView(data: entry.data)
        case .systemLarge:  LargeWidgetView(data: entry.data)
        default:            SmallWidgetView(data: entry.data)
        }
    }
}
