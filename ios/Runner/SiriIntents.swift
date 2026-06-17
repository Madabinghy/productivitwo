// SiriIntents.swift — App Intents exposés à Siri (target Runner / app principale)
//
// « Connexion Siri » = pont authentifié sans ré-auth : l'app écrit déjà uid + token
// dans l'App Group au sign-in (voir WidgetService.provisionAuth). Ces intents
// réutilisent ce token pour lire (App Group, hors-ligne) et écrire (mcpHandler).
//
// AppShortcutsProvider doit vivre dans le target app principal → ce fichier est
// indépendant des intents du widget (ProductivitwoWidget.swift) bien qu'il lise
// les mêmes clés App Group et appelle les mêmes outils MCP.

import AppIntents
import WidgetKit
import Foundation

// MARK: - Constantes & helpers partagés

private let siriAppGroup = "group.com.madabinghy.productivitwo"

private func siriDefaults() -> UserDefaults? { UserDefaults(suiteName: siriAppGroup) }

private func siriTodayISO() -> String {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    return f.string(from: Date())
}

/// Appel authentifié à mcpHandler (JSON-RPC tools/call) avec uid + token de l'App Group.
/// Mêmes endpoint et format que widgetMcpCall côté widget.
private func siriMcpCall(tool: String, args: [String: Any]) async {
    let d = siriDefaults()
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

// MARK: - Entité Routine (résoluble à la voix par son nom)

@available(iOS 16.0, *)
struct RoutineAppEntity: AppEntity {
    let id: String
    let label: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Routine"
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(label)") }
    static var defaultQuery = RoutineEntityQuery()
}

@available(iOS 16.0, *)
struct RoutineEntityQuery: EntityQuery {
    private func all() -> [RoutineAppEntity] {
        guard let raw = siriDefaults()?.string(forKey: "routines_json"),
              let data = raw.data(using: .utf8),
              let arr = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]]
        else { return [] }
        return arr.compactMap { d in
            guard let id = d["id"] as? String, let label = d["label"] as? String else { return nil }
            return RoutineAppEntity(id: id, label: label)
        }
    }

    func entities(for identifiers: [String]) async throws -> [RoutineAppEntity] {
        all().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [RoutineAppEntity] { all() }
}

// MARK: - Intent : cocher une routine (écriture)

@available(iOS 16.0, *)
struct LogRoutineSiriIntent: AppIntent {
    static var title: LocalizedStringResource = "Cocher une routine"
    static var description = IntentDescription("Marque une de tes routines comme faite.")

    @Parameter(title: "Routine") var routine: RoutineAppEntity

    static var parameterSummary: some ParameterSummary { Summary("Cocher \(\.$routine)") }

    init() {}
    init(routine: RoutineAppEntity) { self.routine = routine }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let id = routine.id
        // Tap normal = +1 ; une routine déjà complétée (done >= target) se décrémente (-1).
        var delta = 1
        let d = siriDefaults()
        if let raw = d?.string(forKey: "routines_json"),
           let data = raw.data(using: .utf8),
           var arr = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]],
           let i = arr.firstIndex(where: { ($0["id"] as? String) == id }) {
            let done = (arr[i]["done"] as? Int) ?? 0
            let target = (arr[i]["target"] as? Int) ?? 1
            let wasComplete = done >= target
            delta = wasComplete ? -1 : 1
            let newDone = max(0, done + delta)
            arr[i]["done"] = newDone
            let nowComplete = newDone >= target
            if nowComplete != wasComplete {
                let cur = d?.integer(forKey: "routines_done") ?? 0
                d?.set(max(0, cur + (nowComplete ? 1 : -1)), forKey: "routines_done")
            }
            if let out = try? JSONSerialization.data(withJSONObject: arr),
               let s = String(data: out, encoding: .utf8) { d?.set(s, forKey: "routines_json") }
        }
        WidgetCenter.shared.reloadAllTimelines()
        await siriMcpCall(tool: "log_routine_hit", args: ["activityId": id, "delta": delta])
        let verb = delta > 0 ? "cochée" : "décochée"
        return .result(dialog: IntentDialog(stringLiteral: "\(routine.label) \(verb)."))
    }
}

// MARK: - Intent : lire le programme du jour (lecture)

@available(iOS 16.0, *)
struct TodayScheduleIntent: AppIntent {
    static var title: LocalizedStringResource = "Mon programme du jour"
    static var description = IntentDescription("Lit ton programme horaire du jour.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let raw = siriDefaults()?.string(forKey: "schedule_json"),
              let data = raw.data(using: .utf8),
              let arr = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]],
              !arr.isEmpty
        else { return .result(dialog: "Tu n'as pas encore de programme aujourd'hui.") }

        let lines = arr.prefix(8).compactMap { d -> String? in
            guard let time = d["time"] as? String, let title = d["title"] as? String else { return nil }
            let mark = (d["status"] as? String) == "done" ? " (fait)" : ""
            return "\(time) \(title)\(mark)"
        }
        let spoken = lines.joined(separator: ", ")
        return .result(dialog: IntentDialog(stringLiteral: "Ton programme du jour : \(spoken)."))
    }
}

// MARK: - Intent : lire la tâche du jour (lecture)

@available(iOS 16.0, *)
struct FocusTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "Ma tâche du jour"
    static var description = IntentDescription("Lit ta tâche prioritaire et son avancement.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let raw = siriDefaults()?.string(forKey: "focus_task_json"),
              raw != "null",
              let data = raw.data(using: .utf8),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let title = obj["title"] as? String
        else { return .result(dialog: "Tu n'as pas de tâche active pour le moment.") }

        let projectTitle = obj["projectTitle"] as? String ?? ""
        let actions = obj["actions"] as? [[String: Any]] ?? []
        let doneCount = actions.filter { ($0["done"] as? Bool) == true }.count
        let total = actions.count

        var dialog = "Ta tâche du jour : \(title)"
        if !projectTitle.isEmpty { dialog += ", projet \(projectTitle)" }
        if total > 0 {
            dialog += ". \(doneCount) action sur \(total) faite\(doneCount > 1 ? "s" : "")."
        } else {
            dialog += "."
        }
        return .result(dialog: IntentDialog(stringLiteral: dialog))
    }
}

// MARK: - Raccourcis Siri (phrases vocales)

@available(iOS 16.0, *)
struct ProductivitwoShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: TodayScheduleIntent(),
            phrases: [
                "Quel est mon programme dans \(.applicationName)",
                "Mon programme du jour dans \(.applicationName)",
                "Programme \(.applicationName)",
            ],
            shortTitle: "Programme du jour",
            systemImageName: "calendar"
        )
        AppShortcut(
            intent: FocusTaskIntent(),
            phrases: [
                "Quelle est ma tâche du jour dans \(.applicationName)",
                "Ma tâche dans \(.applicationName)",
            ],
            shortTitle: "Tâche du jour",
            systemImageName: "checklist"
        )
        AppShortcut(
            intent: LogRoutineSiriIntent(),
            phrases: [
                "Coche ma routine dans \(.applicationName)",
                "Marque une routine faite dans \(.applicationName)",
            ],
            shortTitle: "Cocher une routine",
            systemImageName: "circle.circle"
        )
    }
}
