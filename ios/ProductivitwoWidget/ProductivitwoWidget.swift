// ProductivitwoWidget.swift
// Widgets de l'écran d'accueil (refonte 2026-10-31, maquette « Widgets revus ») :
// tout vient de `today_json`, calculé par l'app sur la journée vécue
// (lib/widget_service.dart, _todayJson). Le widget ne recalcule que le bloc en
// cours, d'après les heures des blocs, pour basculer sans que l'app tourne.

import WidgetKit
import SwiftUI
import Foundation
import AppIntents

// MARK: - Constantes

private let appGroup = "group.com.madabinghy.productivitwo"
private let appScheme = "com.madabinghy.productivitwo://"

private extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

// Thème vert sombre de l'app.
private let kBg = Color(hex: 0x0C1C14)
private let kText = Color(hex: 0xE8F3ED)
private let kText2 = Color(hex: 0xB9CFC4)
private let kText3 = Color(hex: 0x9FB8AB)
private let kGreen = Color(hex: 0x4CBF75)
private let kGreenLight = Color(hex: 0x7FD3A0)
private let kTrack = Color(hex: 0x27382D)
private let kEmber = Color(hex: 0xFFB27A)
private let kGold = Color(hex: 0xFFD27A)
private let kAmber = Color(hex: 0xE0A93A)
private let kGuerilla = Color(hex: 0xC5D38A)
private let kOffensive = Color(hex: 0xFF9B6E)
private let kNight = Color(hex: 0x1D2A44)
private let kNightText = Color(hex: 0xA9B8E8)

private func appDefaults() -> UserDefaults? { UserDefaults(suiteName: appGroup) }

// MARK: - Données (today_json)

struct TBlock: Decodable {
    let id: String
    let doc: String?
    let startMs: Double
    let endMs: Double
    let time: String
    let end: String
    let title: String
    let status: String
    let mirror: Bool?
    let ctx: String?
    let action: String?
    let step: String?
    let stepIdx: Int?
    let stepTotal: Int?
    let projectId: String?
    let taskId: String?
    let actionId: String?
    let itemId: String?

    var start: Date { Date(timeIntervalSince1970: startMs / 1000) }
    var finish: Date { Date(timeIntervalSince1970: endMs / 1000) }
    var isDone: Bool { status == "done" }
    var isSleep: Bool {
        let t = title.lowercased()
        return t.hasPrefix("sommeil") || t.hasPrefix("dormir") || t.hasPrefix("nuit") || t.hasPrefix("coucher")
    }
}

struct TPerfect: Decodable {
    let value: String
    let sub: String?
    let cells: [Bool]
    let done: Int
    let total: Int
}

struct TMode: Decodable {
    let label: String?
    let key: String?
    let wins: Int?
}

struct TRun: Decodable {
    let activity: String
    let startMs: Double
    var start: Date { Date(timeIntervalSince1970: startMs / 1000) }
}

struct TRoutine: Decodable {
    let id: String
    let label: String
    let done: Int
    let target: Int
    let series: Int?
}

struct TRoutines: Decodable {
    let moment: String
    let done: Int
    let total: Int
    let later: Int?
    let todo: [TRoutine]
}

struct TFocusItem: Decodable {
    let title: String
    let done: Bool
    let projectId: String?
    let taskId: String?
    let activityId: String?
    let actionId: String
}

struct TFocused: Decodable {
    let done: Int
    let total: Int
    let items: [TFocusItem]
}

struct TWatchItem: Decodable {
    let name: String
    let missing: Int
    let frac: Double
}

struct TWatch: Decodable {
    let covered: Int
    let total: Int
    let behind: [TWatchItem]
}

struct TProject: Decodable {
    let id: String
    let title: String
    let pill: String?
    let bricks: [String]
    let line: String
    let next: String?
}

struct TodayData: Decodable {
    let ymd: String?
    let blocks: [TBlock]?
    let running: TRun?
    let perfect: TPerfect?
    let embers: String?
    let mode: TMode?
    let routines: TRoutines?
    let focused: TFocused?
    let watch: TWatch?
    let project: TProject?

    static let empty = TodayData(ymd: nil, blocks: nil, running: nil, perfect: nil, embers: nil, mode: nil,
                                 routines: nil, focused: nil, watch: nil, project: nil)

    static func load() -> TodayData {
        guard let raw = appDefaults()?.string(forKey: "today_json"),
              let data = raw.data(using: .utf8),
              let d = try? JSONDecoder().decode(TodayData.self, from: data) else { return .empty }
        return d
    }

    var allBlocks: [TBlock] { blocks ?? [] }

    /// Bloc en cours à [t] : un bloc à faire d'abord, sinon n'importe lequel.
    func current(at t: Date) -> TBlock? {
        let live = allBlocks.filter { $0.start <= t && t < $0.finish }
        return live.first(where: { !$0.isDone }) ?? live.first
    }

    /// Blocs à faire qui commencent après [t].
    func upcoming(after t: Date) -> [TBlock] {
        allBlocks.filter { !$0.isDone && $0.start > t }
    }

    var modeLabel: String? {
        guard let m = mode, let l = m.label else { return nil }
        if m.key == "low", let w = m.wins, w > 0 { return "\(l) · \(w)" }
        return l
    }

    var modeColor: Color {
        switch mode?.key {
        case "low": return kGuerilla
        case "high": return kOffensive
        case "recharge": return kNightText
        default: return kGreenLight
        }
    }
}

// MARK: - Timeline (une entrée à chaque début et fin de bloc)

struct TodayEntry: TimelineEntry {
    let date: Date
    let data: TodayData
}

struct TodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayEntry {
        TodayEntry(date: Date(), data: .empty)
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        completion(TodayEntry(date: Date(), data: TodayData.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        let data = TodayData.load()
        let now = Date()
        let horizon = now.addingTimeInterval(16 * 3600)
        var dates: Set<Date> = [now]
        for b in data.allBlocks {
            if b.start > now && b.start < horizon { dates.insert(b.start) }
            if b.finish > now && b.finish < horizon { dates.insert(b.finish) }
        }
        let sorted = dates.sorted().prefix(40)
        let entries = sorted.map { TodayEntry(date: $0, data: data) }
        let refresh = now.addingTimeInterval(30 * 60)
        completion(Timeline(entries: entries, policy: .after(refresh)))
    }
}

// MARK: - Briques communes

private struct SectionLabel: View {
    let text: String
    var color: Color = kText3
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10.5, weight: .heavy))
            .tracking(0.8)
            .foregroundColor(color)
            .lineLimit(1)
    }
}

private struct Pill: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text)
            .font(.system(size: 11.5, weight: .bold))
            .foregroundColor(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.16)))
            .lineLimit(1)
    }
}

private struct Bar: View {
    let frac: Double
    let color: Color
    var height: CGFloat = 4
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(kTrack)
                Capsule().fill(color).frame(width: geo.size.width * CGFloat(max(0, min(1, frac))))
            }
        }
        .frame(height: height)
    }
}

private struct StepDots: View {
    let done: Int
    let total: Int
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<min(total, 12), id: \.self) { i in
                Capsule()
                    .fill(i < done ? kGreen : (i == done ? kGreenLight : kTrack))
                    .frame(height: 5)
            }
        }
    }
}

private func isAccessory(_ f: WidgetFamily) -> Bool {
    f == .accessoryCircular || f == .accessoryRectangular || f == .accessoryInline
}

private extension View {
    func todayBackground(_ family: WidgetFamily) -> some View {
        containerBackground(isAccessory(family) ? Color.clear : kBg, for: .widget)
    }
}

private func checkCircle(done: Bool, color: Color = kGreen) -> some View {
    Image(systemName: done ? "checkmark.circle.fill" : "circle")
        .font(.system(size: 16))
        .foregroundColor(done ? color : kText3.opacity(0.7))
}

// MARK: ════════ ACTIONS DEPUIS LE WIDGET (App Intents) ════════

private func todayISO() -> String {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    return f.string(from: Date())
}

/// Appel authentifié à mcpHandler (JSON-RPC tools/call) avec uid + token de l'App Group.
private func widgetMcpCall(tool: String, args: [String: Any]) async {
    let d = appDefaults()
    guard let uid = d?.string(forKey: "mcp_uid"),
          let token = d?.string(forKey: "mcp_token"),
          !uid.isEmpty, !token.isEmpty,
          let url = URL(string: "https://mcphandler-dzos75b65q-uc.a.run.app/mcp/\(uid)/\(token)")
    else { return }
    var req = URLRequest(url: url)
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    let body: [String: Any] = [
        "jsonrpc": "2.0", "id": 1, "method": "tools/call",
        "params": ["name": tool, "arguments": args],
    ]
    req.httpBody = try? JSONSerialization.data(withJSONObject: body)
    _ = try? await URLSession.shared.data(for: req)
}

/// Lit today_json, le modifie, le réécrit (mise à jour optimiste, l'app recalcule à la prochaine ouverture).
private func mutateToday(_ transform: (inout [String: Any]) -> Void) {
    let d = appDefaults()
    guard let raw = d?.string(forKey: "today_json"), let data = raw.data(using: .utf8),
          var obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }
    transform(&obj)
    if let out = try? JSONSerialization.data(withJSONObject: obj),
       let s = String(data: out, encoding: .utf8) { d?.set(s, forKey: "today_json") }
}

/// +1 sur une routine (widget Routines). Atteinte : elle quitte la liste « à faire ».
struct AddRoutineHitIntent: AppIntent {
    static var title: LocalizedStringResource = "Ajouter un à une routine"
    @Parameter(title: "Routine") var activityId: String
    init() {}
    init(activityId: String) { self.activityId = activityId }
    func perform() async throws -> some IntentResult {
        let id = activityId
        mutateToday { obj in
            guard var r = obj["routines"] as? [String: Any],
                  var todo = r["todo"] as? [[String: Any]],
                  let i = todo.firstIndex(where: { ($0["id"] as? String) == id }) else { return }
            let done = ((todo[i]["done"] as? Int) ?? 0) + 1
            let target = (todo[i]["target"] as? Int) ?? 1
            if done >= target {
                todo.remove(at: i)
                r["done"] = ((r["done"] as? Int) ?? 0) + 1
            } else {
                todo[i]["done"] = done
            }
            r["todo"] = todo
            obj["routines"] = r
        }
        WidgetCenter.shared.reloadAllTimelines()
        await widgetMcpCall(tool: "log_routine_hit", args: ["activityId": id, "delta": 1])
        return .result()
    }
}

/// Coche / décoche un bloc du programme (doc du bloc : la nuit vit sur le doc du lendemain).
struct MarkBlockDoneIntent: AppIntent {
    static var title: LocalizedStringResource = "Marquer un bloc fait"
    @Parameter(title: "Bloc") var blockId: String
    @Parameter(title: "Jour") var date: String?
    init() {}
    init(blockId: String, date: String?) { self.blockId = blockId; self.date = date }
    func perform() async throws -> some IntentResult {
        let id = blockId
        var newDone = true
        mutateToday { obj in
            guard var blocks = obj["blocks"] as? [[String: Any]],
                  let i = blocks.firstIndex(where: { ($0["id"] as? String) == id }) else { return }
            newDone = (blocks[i]["status"] as? String) != "done"
            blocks[i]["status"] = newDone ? "done" : "pending"
            obj["blocks"] = blocks
        }
        WidgetCenter.shared.reloadAllTimelines()
        await widgetMcpCall(tool: "mark_block_done",
                            args: ["date": date ?? todayISO(), "blockId": id, "done": newDone])
        return .result()
    }
}

/// « Étape faite » du widget Maintenant : coche l'étape en cours de l'action visée.
struct MarkChecklistStepIntent: AppIntent {
    static var title: LocalizedStringResource = "Cocher l'étape en cours"
    @Parameter(title: "Projet") var projectId: String
    @Parameter(title: "Tâche") var taskId: String
    @Parameter(title: "Action") var actionId: String
    @Parameter(title: "Étape") var itemId: String
    init() {}
    init(projectId: String, taskId: String, actionId: String, itemId: String) {
        self.projectId = projectId; self.taskId = taskId; self.actionId = actionId; self.itemId = itemId
    }
    func perform() async throws -> some IntentResult {
        let item = itemId
        mutateToday { obj in
            guard var blocks = obj["blocks"] as? [[String: Any]] else { return }
            for i in blocks.indices where (blocks[i]["itemId"] as? String) == item {
                blocks[i]["itemId"] = nil
                blocks[i]["step"] = "étape cochée"
                blocks[i]["stepIdx"] = ((blocks[i]["stepIdx"] as? Int) ?? 0) + 1
            }
            obj["blocks"] = blocks
        }
        WidgetCenter.shared.reloadAllTimelines()
        await widgetMcpCall(tool: "mark_checklist_item", args: [
            "projectId": projectId, "taskId": taskId, "actionId": actionId, "itemId": item, "done": true,
        ])
        return .result()
    }
}

/// Coche / décoche une action (visée aujourd'hui, ou l'action d'un bloc) : action de
/// projet (projectId + taskId) ou action propre d'une activité (activityId).
struct MarkActionIntent: AppIntent {
    static var title: LocalizedStringResource = "Cocher une action"
    @Parameter(title: "Projet") var projectId: String?
    @Parameter(title: "Tâche") var taskId: String?
    @Parameter(title: "Activité") var activityId: String?
    @Parameter(title: "Action") var actionId: String
    @Parameter(title: "Fait") var done: Bool
    init() {}
    init(projectId: String?, taskId: String?, activityId: String?, actionId: String, done: Bool) {
        self.projectId = projectId; self.taskId = taskId; self.activityId = activityId
        self.actionId = actionId; self.done = done
    }
    func perform() async throws -> some IntentResult {
        let aid = actionId, newDone = done
        mutateToday { obj in
            guard var f = obj["focused"] as? [String: Any],
                  var items = f["items"] as? [[String: Any]],
                  let i = items.firstIndex(where: { ($0["actionId"] as? String) == aid }) else { return }
            let was = (items[i]["done"] as? Bool) ?? false
            items[i]["done"] = newDone
            if was != newDone { f["done"] = max(0, ((f["done"] as? Int) ?? 0) + (newDone ? 1 : -1)) }
            f["items"] = items
            obj["focused"] = f
        }
        WidgetCenter.shared.reloadAllTimelines()
        if let p = projectId, let t = taskId {
            await widgetMcpCall(tool: "mark_action_done",
                                args: ["projectId": p, "taskId": t, "actionId": aid, "done": newDone])
        } else if let a = activityId {
            await widgetMcpCall(tool: "update_action", args: ["activityId": a, "actionId": aid, "done": newDone])
        }
        return .result()
    }
}

// MARK: ════════ JOURNÉE PARFAITE ════════

struct PerfectDayView: View {
    let entry: TodayEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        let d = entry.data
        Group {
            switch family {
            case .accessoryCircular: circular(d)
            case .accessoryInline: inline(d)
            default: small(d)
            }
        }
        .widgetURL(URL(string: appScheme + "perfect"))
        .todayBackground(family)
    }

    func inline(_ d: TodayData) -> some View {
        let v = d.perfect?.value ?? "Journée parfaite"
        return Text(d.embers.map { "\(v) · Braises \($0)" } ?? v)
    }

    func circular(_ d: TodayData) -> some View {
        let p = d.perfect
        let frac = (p?.total ?? 0) > 0 ? Double(p!.done) / Double(p!.total) : 0
        return ZStack {
            AccessoryWidgetBackground()
            Circle().stroke(Color.white.opacity(0.25), lineWidth: 5).padding(5)
            Circle().trim(from: 0, to: frac)
                .stroke(Color.white, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90)).padding(5)
            Text(p.map { "\($0.done)/\($0.total)" } ?? "–")
                .font(.system(size: 13, weight: .heavy))
                .minimumScaleFactor(0.6)
        }
    }

    func small(_ d: TodayData) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            SectionLabel(text: "Journée parfaite")
            if let p = d.perfect {
                Text(p.value)
                    .font(.system(size: 24, weight: .heavy))
                    .foregroundColor(kText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                cells(p.cells)
                if let s = p.sub {
                    Text(s).font(.system(size: 11.5)).foregroundColor(kText2).lineLimit(2)
                }
            } else {
                Text("Ouvre l'app pour charger ta journée")
                    .font(.system(size: 12)).foregroundColor(kText2)
            }
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                if let e = d.embers {
                    Text("Braises \(e)").font(.system(size: 11.5, weight: .bold)).foregroundColor(kEmber).lineLimit(1)
                }
                Spacer(minLength: 0)
                if let m = d.modeLabel { Pill(text: m, color: d.modeColor) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    func cells(_ c: [Bool]) -> some View {
        let rows = stride(from: 0, to: c.count, by: 6).map { Array(c[$0..<min($0 + 6, c.count)]) }
        return VStack(alignment: .leading, spacing: 4) {
            ForEach(0..<rows.count, id: \.self) { r in
                HStack(spacing: 4) {
                    ForEach(0..<rows[r].count, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(rows[r][i] ? kGreen : kTrack)
                            .frame(width: 18, height: 11)
                    }
                }
            }
        }
    }
}

struct ProductivitwoWidget: Widget {
    let kind: String = "ProductivitwoWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TodayProvider()) { entry in
            PerfectDayView(entry: entry)
        }
        .configurationDisplayName("Journée parfaite")
        .description("Ce qu'il manque pour une journée parfaite, les braises et le mode du jour")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryInline])
    }
}

// MARK: ════════ LANCEURS (Guérilla · Offensive) ════════

struct LaunchersView: View {
    let entry: TodayEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        Group {
            if family == .accessoryCircular {
                ZStack {
                    AccessoryWidgetBackground()
                    VStack(spacing: 1) {
                        Image(systemName: "bolt.fill").font(.system(size: 18, weight: .bold))
                        Text("Guérilla").font(.system(size: 10, weight: .bold)).minimumScaleFactor(0.7)
                    }
                }
                .widgetURL(URL(string: appScheme + "guerilla"))
            } else {
                VStack(spacing: 8) {
                    launcher(host: "guerilla", icon: "bolt.fill", title: "Guérilla", sub: "la flemme ou moi", color: kGuerilla)
                    launcher(host: "offensive", icon: "arrow.up.right", title: "Offensive", sub: "en forme, à fond", color: kOffensive)
                }
                .widgetURL(URL(string: appScheme + "guerilla"))
            }
        }
        .todayBackground(family)
    }

    @ViewBuilder
    func launcher(host: String, icon: String, title: String, sub: String, color: Color) -> some View {
        let content = VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 14, weight: .bold))
                Text(title).font(.system(size: 15, weight: .heavy))
            }
            .foregroundColor(color)
            Text(sub).font(.system(size: 11.5)).foregroundColor(kText2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .background(RoundedRectangle(cornerRadius: 14).fill(color.opacity(0.14)))
        if #available(iOS 18.0, *) {
            Button(intent: OpenURLIntent(URL(string: appScheme + host)!)) { content }.buttonStyle(.plain)
        } else {
            content
        }
    }
}

struct LaunchersWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LaunchersWidget", provider: TodayProvider()) { entry in
            LaunchersView(entry: entry)
        }
        .configurationDisplayName("Guérilla · Offensive")
        .description("Lance une guérilla ou une offensive d'un tap")
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}

// MARK: ════════ MAINTENANT ════════

struct NowView: View {
    let entry: TodayEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        let d = entry.data
        let cur = d.current(at: entry.date)
        Group {
            if family == .accessoryRectangular {
                rectangular(d, cur)
            } else {
                medium(d, cur)
            }
        }
        .widgetURL(URL(string: appScheme + "today"))
        .todayBackground(family)
    }

    func rectangular(_ d: TodayData, _ cur: TBlock?) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Text("Maintenant").font(.system(size: 12, weight: .bold))
                if let r = d.running {
                    Text("·").font(.system(size: 12, weight: .bold))
                    Text(r.start, style: .timer).font(.system(size: 12, weight: .bold)).monospacedDigit()
                }
            }
            if let b = cur {
                Text(b.action ?? b.title).font(.system(size: 15, weight: .bold)).lineLimit(1)
                Text(stepLine(b) ?? "fin \(b.end)").font(.system(size: 12)).lineLimit(1)
            } else if let r = d.running {
                Text(r.activity).font(.system(size: 15, weight: .bold)).lineLimit(1)
            } else if let n = d.upcoming(after: entry.date).first {
                Text(n.title).font(.system(size: 15, weight: .bold)).lineLimit(1)
                Text("à \(n.time)").font(.system(size: 12))
            } else {
                Text("Rien de prévu").font(.system(size: 15, weight: .bold))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func stepLine(_ b: TBlock) -> String? {
        guard let i = b.stepIdx, let n = b.stepTotal, n > 0 else { return nil }
        return "étape \(i) / \(n) · fin \(b.end)"
    }

    func medium(_ d: TodayData, _ cur: TBlock?) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                SectionLabel(text: cur.map { "Maintenant · bloc \($0.time) → \($0.end)" } ?? "Maintenant", color: kGreenLight)
                Spacer(minLength: 4)
                if let r = d.running {
                    Text(r.start, style: .timer)
                        .font(.system(size: 13, weight: .heavy)).monospacedDigit()
                        .foregroundColor(kGreenLight)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 70, alignment: .trailing)
                }
            }
            if let b = cur {
                if let c = b.ctx {
                    Text(c).font(.system(size: 11.5)).foregroundColor(kText3).lineLimit(1)
                }
                Text(b.action ?? b.title)
                    .font(.system(size: 17, weight: .heavy)).foregroundColor(kText).lineLimit(2)
                if let n = b.stepTotal, n > 0 {
                    StepDots(done: max(0, (b.stepIdx ?? 1) - 1), total: n)
                    if let s = b.step {
                        Text("Étape \(b.stepIdx ?? 1) / \(n) : \(s)").font(.system(size: 12.5)).foregroundColor(kText2).lineLimit(1)
                    }
                }
            } else if let r = d.running {
                Text(r.activity).font(.system(size: 17, weight: .heavy)).foregroundColor(kText).lineLimit(2)
                Text("chrono en cours, hors programme").font(.system(size: 12.5)).foregroundColor(kText2)
            } else {
                Text("Pas de bloc en cours").font(.system(size: 17, weight: .heavy)).foregroundColor(kText)
            }
            Spacer(minLength: 0)
            HStack(spacing: 10) {
                if let b = cur { actionButton(b) }
                Spacer(minLength: 0)
                if let n = d.upcoming(after: entry.date).first {
                    Text("Ensuite \(n.time) · \(n.title)")
                        .font(.system(size: 12)).foregroundColor(kText3).lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    func actionButton(_ b: TBlock) -> some View {
        if let p = b.projectId, let t = b.taskId, let a = b.actionId, let item = b.itemId {
            Button(intent: MarkChecklistStepIntent(projectId: p, taskId: t, actionId: a, itemId: item)) {
                filled("Étape faite")
            }.buttonStyle(.plain)
        } else if let p = b.projectId, let t = b.taskId, let a = b.actionId {
            Button(intent: MarkActionIntent(projectId: p, taskId: t, activityId: nil, actionId: a, done: true)) {
                filled("Action faite")
            }.buttonStyle(.plain)
        } else if !b.isDone {
            Button(intent: MarkBlockDoneIntent(blockId: b.id, date: b.doc)) {
                filled("Bloc fait")
            }.buttonStyle(.plain)
        }
    }

    func filled(_ s: String) -> some View {
        Text(s)
            .font(.system(size: 13, weight: .heavy))
            .foregroundColor(Color(hex: 0x07100D))
            .padding(.horizontal, 14)
            .frame(height: 30)
            .background(Capsule().fill(kGreen))
    }
}

struct NowWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NowWidget", provider: TodayProvider()) { entry in
            NowView(entry: entry)
        }
        .configurationDisplayName("Maintenant")
        .description("Le bloc en cours, son action, l'étape et le chrono")
        .supportedFamilies([.systemMedium, .accessoryRectangular])
    }
}

// MARK: ════════ PROGRAMME DU JOUR ════════

struct ScheduleView: View {
    let entry: TodayEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        let d = entry.data
        let blocks = d.allBlocks
        let cur = d.current(at: entry.date)
        let rows = (cur.map { [$0] } ?? []).filter { !$0.isDone } + d.upcoming(after: entry.date)
        let max = family == .systemLarge ? 8 : 3
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel(text: "Programme" + dayLabel(d.ymd))
                Spacer(minLength: 4)
                Text("\(blocks.filter { $0.isDone }.count) / \(blocks.count) blocs")
                    .font(.system(size: 12)).foregroundColor(kText2)
            }
            if blocks.isEmpty {
                Spacer()
                Text("Rien de prévu").font(.system(size: 14, weight: .semibold)).foregroundColor(kText2)
                Spacer()
            } else {
                strip(blocks, cur)
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(rows.prefix(max).enumerated()), id: \.offset) { _, b in row(b) }
                }
                if rows.isEmpty {
                    Text("Tout est fait ✓").font(.system(size: 13, weight: .semibold)).foregroundColor(kGreenLight)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(URL(string: appScheme + "program"))
        .todayBackground(family)
    }

    func dayLabel(_ ymd: String?) -> String {
        guard let s = ymd else { return "" }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        guard let date = f.date(from: s) else { return "" }
        let o = DateFormatter()
        o.locale = Locale(identifier: "fr_FR")
        o.dateFormat = "EEEE d"
        return " · " + o.string(from: date)
    }

    func strip(_ blocks: [TBlock], _ cur: TBlock?) -> some View {
        let total = blocks.reduce(0.0) { $0 + max(1, $1.endMs - $1.startMs) }
        return GeometryReader { geo in
            let gaps = CGFloat(max(0, blocks.count - 1)) * 3
            let w = max(0, geo.size.width - gaps)
            HStack(spacing: 3) {
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, b in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color(b, cur))
                        .frame(width: max(2, w * CGFloat(max(1, b.endMs - b.startMs) / total)))
                }
            }
        }
        .frame(height: 14)
    }

    func color(_ b: TBlock, _ cur: TBlock?) -> Color {
        if b.id == cur?.id { return kGreenLight }
        if b.isDone { return kGreen }
        if b.isSleep { return kNight }
        return kTrack
    }

    func row(_ b: TBlock) -> some View {
        HStack(spacing: 10) {
            Button(intent: MarkBlockDoneIntent(blockId: b.id, date: b.doc)) {
                checkCircle(done: b.isDone)
            }.buttonStyle(.plain)
            Text(b.time).font(.system(size: 12)).monospacedDigit().foregroundColor(kText3).frame(width: 40, alignment: .leading)
            Text(b.isSleep ? "\(b.title) · jusqu'à \(b.end)" : b.title)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundColor(b.isSleep ? kNightText : kText)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }
}

struct ScheduleWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ScheduleWidget", provider: TodayProvider()) { entry in
            ScheduleView(entry: entry)
        }
        .configurationDisplayName("Programme du jour")
        .description("Ta journée vécue, nuit comprise : les blocs à venir, à cocher")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

// MARK: ════════ ROUTINES ════════

struct RoutinesView: View {
    let entry: TodayEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        let r = entry.data.routines
        Group {
            if family == .systemSmall {
                small(r)
            } else {
                list(r)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(URL(string: appScheme + "today"))
        .todayBackground(family)
    }

    func small(_ r: TRoutines?) -> some View {
        let frac = (r?.total ?? 0) > 0 ? Double(r!.done) / Double(r!.total) : 0
        return VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Routines")
            ZStack {
                Circle().stroke(kTrack, lineWidth: 9)
                Circle().trim(from: 0, to: frac)
                    .stroke(kGreen, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(r.map { "\($0.done)/\($0.total)" } ?? "–")
                    .font(.system(size: 17, weight: .heavy)).foregroundColor(kText)
            }
            .frame(width: 72, height: 72)
            Text(r.map { $0.todo.isEmpty ? "rien à faire \($0.moment)" : "\($0.todo.count) à faire \($0.moment)" } ?? "")
                .font(.system(size: 11.5)).foregroundColor(kText2).lineLimit(2)
        }
    }

    func list(_ r: TRoutines?) -> some View {
        let max = family == .systemLarge ? 8 : 3
        return VStack(alignment: .leading, spacing: 7) {
            HStack {
                SectionLabel(text: "Routines · " + (r?.moment ?? ""))
                Spacer(minLength: 4)
                if let r = r {
                    Text("\(r.done) / \(r.total)").font(.system(size: 12)).foregroundColor(kText2)
                }
            }
            if let r = r, !r.todo.isEmpty {
                ForEach(Array(r.todo.prefix(max).enumerated()), id: \.offset) { _, x in row(x) }
            } else {
                Text("Rien à faire \(r?.moment ?? "maintenant") ✓")
                    .font(.system(size: 13.5, weight: .semibold)).foregroundColor(kGreenLight)
            }
            Spacer(minLength: 0)
            if let r = r {
                let later = r.later ?? 0
                Text("Faites · \(r.done)" + (later > 0 ? "  ·  ensuite : \(later)" : ""))
                    .font(.system(size: 12)).foregroundColor(kText3)
            }
        }
    }

    func row(_ x: TRoutine) -> some View {
        HStack(spacing: 10) {
            Text(x.label).font(.system(size: 14, weight: .semibold)).foregroundColor(kText).lineLimit(1)
            Spacer(minLength: 4)
            if let s = x.series, s > 0 {
                Text("série \(s) j").font(.system(size: 11.5)).foregroundColor(kEmber).lineLimit(1)
            }
            Text("\(x.done) / \(x.target)").font(.system(size: 12)).monospacedDigit().foregroundColor(kText3)
            Button(intent: AddRoutineHitIntent(activityId: x.id)) {
                Text("+1")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundColor(kGreenLight)
                    .frame(width: 36, height: 28)
                    .background(Capsule().fill(kGreen.opacity(0.18)))
            }.buttonStyle(.plain)
        }
    }
}

struct RoutinesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "RoutinesWidget", provider: TodayProvider()) { entry in
            RoutinesView(entry: entry)
        }
        .configurationDisplayName("Routines")
        .description("Le moment en cours : ce qui reste, +1 sans ouvrir l'app")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: ════════ ACTIONS VISÉES AUJOURD'HUI ════════

struct FocusedView: View {
    let entry: TodayEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        let f = entry.data.focused
        let max = family == .systemSmall ? 3 : (family == .systemLarge ? 9 : 4)
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: "Visées aujourd'hui", color: kGold)
            if let f = f, f.total > 0 {
                Text("\(f.done) / \(f.total)").font(.system(size: 24, weight: .heavy)).foregroundColor(kText)
                ForEach(Array(f.items.prefix(max).enumerated()), id: \.offset) { _, a in row(a) }
            } else {
                Text("Aucune action visée").font(.system(size: 13.5, weight: .semibold)).foregroundColor(kText2)
                Text("Vise une action pour aujourd'hui dans l'app").font(.system(size: 11.5)).foregroundColor(kText3)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(URL(string: appScheme + "today"))
        .todayBackground(family)
    }

    func row(_ a: TFocusItem) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Button(intent: MarkActionIntent(projectId: a.projectId, taskId: a.taskId, activityId: a.activityId,
                                            actionId: a.actionId, done: !a.done)) {
                checkCircle(done: a.done)
            }.buttonStyle(.plain)
            Text(a.title)
                .font(.system(size: 12.5))
                .foregroundColor(a.done ? kText3 : kText)
                .strikethrough(a.done, color: kText3)
                .lineLimit(1)
        }
    }
}

struct FocusTaskWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FocusTaskWidget", provider: TodayProvider()) { entry in
            FocusedView(entry: entry)
        }
        .configurationDisplayName("Visées aujourd'hui")
        .description("Les actions que tu as visées pour aujourd'hui, à cocher")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: ════════ MONTRE SUISSE ════════

struct WatchView: View {
    let entry: TodayEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        let w = entry.data.watch
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: "Montre suisse")
            if let w = w, w.total > 0 {
                Text("\(w.covered) / \(w.total)").font(.system(size: 24, weight: .heavy)).foregroundColor(kText)
                Text("activités couvertes").font(.system(size: 12)).foregroundColor(kText2)
                if w.behind.isEmpty {
                    Text("Toutes couvertes ✓").font(.system(size: 12.5, weight: .semibold)).foregroundColor(kGreenLight)
                } else {
                    ForEach(Array(w.behind.prefix(2).enumerated()), id: \.offset) { _, x in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(x.name).font(.system(size: 12)).foregroundColor(kText).lineLimit(1)
                                Spacer(minLength: 2)
                                Text("reste \(x.missing) min").font(.system(size: 11.5)).foregroundColor(kGold).lineLimit(1)
                            }
                            Bar(frac: x.frac, color: kAmber)
                        }
                    }
                }
            } else {
                Text("Aucun minimum").font(.system(size: 13.5, weight: .semibold)).foregroundColor(kText2)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(URL(string: appScheme + "today"))
        .todayBackground(family)
    }
}

struct WatchWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WatchWidget", provider: TodayProvider()) { entry in
            WatchView(entry: entry)
        }
        .configurationDisplayName("Montre suisse")
        .description("Tes activités couvertes sur 7 jours, et ce qu'il reste")
        .supportedFamilies([.systemSmall])
    }
}

// MARK: ════════ PROJET DU MOMENT ════════

struct ProjectMomentView: View {
    let entry: TodayEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        let p = entry.data.project
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                SectionLabel(text: "Projet du moment")
                Spacer(minLength: 4)
                if let pill = p?.pill { Pill(text: pill, color: kGold) }
            }
            if let p = p {
                Text(p.title).font(.system(size: 17, weight: .heavy)).foregroundColor(kText).lineLimit(1)
                HStack(spacing: 4) {
                    ForEach(Array(p.bricks.enumerated()), id: \.offset) { _, s in
                        RoundedRectangle(cornerRadius: 3).fill(brickColor(s)).frame(height: 16)
                    }
                }
                Text(p.line).font(.system(size: 12)).foregroundColor(kText2).lineLimit(1)
                Spacer(minLength: 0)
                if let n = p.next {
                    (Text("Prochaine action · ").foregroundColor(kText3) + Text(n).foregroundColor(kText))
                        .font(.system(size: 13)).lineLimit(1)
                }
            } else {
                Text("Aucun projet en cours").font(.system(size: 13.5, weight: .semibold)).foregroundColor(kText2)
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(URL(string: appScheme + (p.map { "project/\($0.id)" } ?? "today")))
        .todayBackground(family)
    }

    func brickColor(_ s: String) -> Color {
        switch s {
        case "done": return kGreen
        case "started": return kGreen.opacity(0.55)
        case "late": return kAmber
        case "running": return kGreenLight
        case "upcoming": return kTrack.opacity(0.5)
        default: return kTrack
        }
    }
}

struct ProjectsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ProjectsWidget", provider: TodayProvider()) { entry in
            ProjectMomentView(entry: entry)
        }
        .configurationDisplayName("Projet du moment")
        .description("Le projet qui compte maintenant : ses briques et la prochaine action")
        .supportedFamilies([.systemMedium])
    }
}
