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
        return WidgetData(routinesDone: done, routinesTotal: total, ganttTasks: tasks)
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
            routinesDone: 3, routinesTotal: 5,
            ganttTasks: [
                GanttTask(project: "Mon App", task: "Développer le backend", done: 2, total: 5),
                GanttTask(project: "Mon App", task: "Design UI", done: 3, total: 3),
                GanttTask(project: "Lancement", task: "Rédiger la landing page", done: 0, total: 4),
                GanttTask(project: "Lancement", task: "Préparer les visuels", done: 1, total: 2),
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
                        Text("Aucune tâche active")
                            .font(.system(size: 12))
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
                        Text("\(data.ganttTasks.count) tâche\(data.ganttTasks.count > 1 ? "s" : "") · \(data.routinesDone)/\(data.routinesTotal) routines")
                            .font(.system(size: 11))
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

// MARK: - Helpers partagés

private func hexColor(_ s: String?, fallback: Color = brandPurple) -> Color {
    guard var h = s else { return fallback }
    h = h.replacingOccurrences(of: "#", with: "")
    guard h.count == 6, let v = Int(h, radix: 16) else { return fallback }
    return Color(red: Double((v >> 16) & 0xFF) / 255.0,
                 green: Double((v >> 8) & 0xFF) / 255.0,
                 blue: Double(v & 0xFF) / 255.0)
}

private func appDefaults() -> UserDefaults? { UserDefaults(suiteName: appGroup) }

// MARK: ════════ WIDGET PROGRAMME DU JOUR ════════

struct ScheduleItem: Decodable {
    let time: String
    let title: String
    let cat: String
    let status: String
    var isDone: Bool { status == "done" }
    var color: Color {
        switch cat {
        case "routine": return Color(red: 0.11, green: 0.62, blue: 0.46)
        case "personal": return Color(red: 0.36, green: 0.55, blue: 0.94)
        case "break": return Color.gray
        default: return brandPurple
        }
    }
}

struct ScheduleEntry: TimelineEntry { let date: Date; let items: [ScheduleItem] }

struct ScheduleProvider: TimelineProvider {
    func loadItems() -> [ScheduleItem] {
        guard let raw = appDefaults()?.string(forKey: "schedule_json"),
              let data = raw.data(using: .utf8),
              let arr = try? JSONDecoder().decode([ScheduleItem].self, from: data) else { return [] }
        return arr
    }
    func placeholder(in c: Context) -> ScheduleEntry {
        ScheduleEntry(date: Date(), items: [
            ScheduleItem(time: "09:00", title: "Deep Work", cat: "project", status: "pending"),
            ScheduleItem(time: "11:00", title: "Prospection", cat: "project", status: "done"),
            ScheduleItem(time: "14:00", title: "Sport", cat: "routine", status: "pending"),
        ])
    }
    func getSnapshot(in c: Context, completion: @escaping (ScheduleEntry) -> Void) {
        completion(ScheduleEntry(date: Date(), items: loadItems()))
    }
    func getTimeline(in c: Context, completion: @escaping (Timeline<ScheduleEntry>) -> Void) {
        let next = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
        completion(Timeline(entries: [ScheduleEntry(date: Date(), items: loadItems())], policy: .after(next)))
    }
}

struct ScheduleWidgetView: View {
    let items: [ScheduleItem]
    @Environment(\.widgetFamily) var family

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("PROGRAMME DU JOUR")
                .font(.system(size: 10, weight: .semibold)).tracking(0.8)
                .foregroundColor(brandPurple.opacity(0.9))
                .padding(.bottom, 8)
            if items.isEmpty {
                Spacer()
                Text("Aucun bloc planifié").font(.system(size: 13)).italic()
                    .foregroundColor(.secondary.opacity(0.6))
                Spacer()
            } else {
                let max = family == .systemLarge ? 8 : 4
                ForEach(Array(items.prefix(max).enumerated()), id: \.offset) { _, b in
                    HStack(spacing: 8) {
                        Text(b.time).font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundColor(.secondary).frame(width: 38, alignment: .leading)
                        Circle().fill(b.color).frame(width: 6, height: 6)
                        Text(b.title).font(.system(size: 13, weight: .medium))
                            .foregroundColor(b.isDone ? .secondary : .primary)
                            .strikethrough(b.isDone, color: .secondary).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 4)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct ScheduleWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ScheduleWidget", provider: ScheduleProvider()) { entry in
            ScheduleWidgetView(items: entry.items)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Programme du jour")
        .description("Tes blocs horaires du jour")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

// MARK: ════════ WIDGET ROUTINES (anneau + reste à faire) ════════

struct RoutineItem: Decodable {
    let label: String
    let done: Int
    let target: Int
    let color: String?
    var isDone: Bool { done >= target }
}

struct RoutinesEntry: TimelineEntry { let date: Date; let done: Int; let total: Int; let items: [RoutineItem] }

struct RoutinesProvider: TimelineProvider {
    func load() -> RoutinesEntry {
        let d = appDefaults()
        var items: [RoutineItem] = []
        if let raw = d?.string(forKey: "routines_json"), let data = raw.data(using: .utf8),
           let arr = try? JSONDecoder().decode([RoutineItem].self, from: data) { items = arr }
        return RoutinesEntry(date: Date(),
                             done: d?.integer(forKey: "routines_done") ?? 0,
                             total: d?.integer(forKey: "routines_total") ?? 0,
                             items: items)
    }
    func placeholder(in c: Context) -> RoutinesEntry {
        RoutinesEntry(date: Date(), done: 2, total: 5, items: [
            RoutineItem(label: "Méditation", done: 0, target: 1, color: "#1d9e75"),
            RoutineItem(label: "Boire de l'eau", done: 3, target: 8, color: "#3b82f6"),
            RoutineItem(label: "Lecture", done: 0, target: 1, color: "#c9a84c"),
        ])
    }
    func getSnapshot(in c: Context, completion: @escaping (RoutinesEntry) -> Void) { completion(load()) }
    func getTimeline(in c: Context, completion: @escaping (Timeline<RoutinesEntry>) -> Void) {
        let next = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
        completion(Timeline(entries: [load()], policy: .after(next)))
    }
}

struct RoutinesWidgetView: View {
    let entry: RoutinesEntry
    @Environment(\.widgetFamily) var family
    var ratio: Double { entry.total > 0 ? Double(entry.done) / Double(entry.total) : 0 }
    var remaining: [RoutineItem] { entry.items.filter { !$0.isDone } }

    var body: some View {
        if family == .systemSmall {
            VStack(spacing: 6) {
                ring(size: 80, line: 10, font: 18)
                Text("Routines").font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary).textCase(.uppercase).tracking(0.8)
            }
        } else {
            HStack(alignment: .top, spacing: 14) {
                VStack(spacing: 4) {
                    ring(size: 54, line: 7, font: 13)
                    Text("\(entry.done)/\(entry.total)").font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                }.frame(width: 60)
                Rectangle().fill(brandPurple.opacity(0.15)).frame(width: 1)
                VStack(alignment: .leading, spacing: 0) {
                    Text("À FAIRE").font(.system(size: 10, weight: .semibold)).tracking(0.6)
                        .foregroundColor(.secondary).padding(.bottom, 6)
                    if remaining.isEmpty {
                        Text("Tout est fait 🎉").font(.system(size: 13)).italic()
                            .foregroundColor(.secondary.opacity(0.7))
                    } else {
                        let max = family == .systemLarge ? 7 : 3
                        ForEach(Array(remaining.prefix(max).enumerated()), id: \.offset) { _, r in
                            HStack(spacing: 7) {
                                Circle().fill(hexColor(r.color)).frame(width: 7, height: 7)
                                Text(r.label).font(.system(size: 13)).lineLimit(1)
                                Spacer(minLength: 0)
                                if r.target > 1 {
                                    Text("\(r.done)/\(r.target)").font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }
                            }.padding(.vertical, 3.5)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    func ring(size: CGFloat, line: CGFloat, font: CGFloat) -> some View {
        ZStack {
            Circle().stroke(brandPurple.opacity(0.18), lineWidth: line)
            Circle().trim(from: 0, to: ratio)
                .stroke(brandPurple, style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int(ratio * 100))%").font(.system(size: font, weight: .bold, design: .rounded))
                .foregroundColor(brandPurple)
        }.frame(width: size, height: size)
    }
}

struct RoutinesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "RoutinesWidget", provider: RoutinesProvider()) { entry in
            RoutinesWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Routines")
        .description("Anneau de progression + routines restantes")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: ════════ WIDGET PROJETS (navigable) ════════

struct ProjectItem: Decodable, Identifiable {
    let id: String
    let title: String
    let done: Int
    let total: Int
    let color: String?
    var progress: Double { total > 0 ? Double(done) / Double(total) : 0 }
    var url: URL { URL(string: "com.madabinghy.productivitwo://project/\(id)")! }
}

struct ProjectsEntry: TimelineEntry { let date: Date; let items: [ProjectItem] }

struct ProjectsProvider: TimelineProvider {
    func loadItems() -> [ProjectItem] {
        guard let raw = appDefaults()?.string(forKey: "projects_json"),
              let data = raw.data(using: .utf8),
              let arr = try? JSONDecoder().decode([ProjectItem].self, from: data) else { return [] }
        return arr
    }
    func placeholder(in c: Context) -> ProjectsEntry {
        ProjectsEntry(date: Date(), items: [
            ProjectItem(id: "1", title: "Lancement Formation", done: 4, total: 12, color: "#c9a84c"),
            ProjectItem(id: "2", title: "Dev Productivitwo", done: 8, total: 20, color: "#6366f1"),
        ])
    }
    func getSnapshot(in c: Context, completion: @escaping (ProjectsEntry) -> Void) {
        completion(ProjectsEntry(date: Date(), items: loadItems()))
    }
    func getTimeline(in c: Context, completion: @escaping (Timeline<ProjectsEntry>) -> Void) {
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: Date())!
        completion(Timeline(entries: [ProjectsEntry(date: Date(), items: loadItems())], policy: .after(next)))
    }
}

struct ProjectsWidgetView: View {
    let items: [ProjectItem]
    @Environment(\.widgetFamily) var family

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("PROJETS").font(.system(size: 10, weight: .semibold)).tracking(0.8)
                .foregroundColor(brandPurple.opacity(0.9)).padding(.bottom, 8)
            if items.isEmpty {
                Spacer()
                Text("Aucun projet actif").font(.system(size: 13)).italic()
                    .foregroundColor(.secondary.opacity(0.6))
                Spacer()
            } else {
                let max = family == .systemLarge ? 7 : 3
                ForEach(items.prefix(max)) { p in
                    Link(destination: p.url) {
                        HStack(spacing: 8) {
                            Circle().fill(hexColor(p.color)).frame(width: 7, height: 7)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(p.title).font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.primary).lineLimit(1)
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        RoundedRectangle(cornerRadius: 2).fill(hexColor(p.color).opacity(0.15)).frame(height: 3)
                                        RoundedRectangle(cornerRadius: 2).fill(hexColor(p.color)).frame(width: geo.size.width * p.progress, height: 3)
                                    }
                                }.frame(height: 3)
                            }
                            Text("\(p.done)/\(p.total)").font(.system(size: 10))
                                .foregroundColor(.secondary).frame(width: 30, alignment: .trailing)
                            Image(systemName: "chevron.right").font(.system(size: 9)).foregroundColor(.secondary.opacity(0.5))
                        }.padding(.vertical, 5)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct ProjectsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ProjectsWidget", provider: ProjectsProvider()) { entry in
            ProjectsWidgetView(items: entry.items)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Projets")
        .description("Tes projets — tap pour ouvrir")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}
