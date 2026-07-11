part of '../models.dart';

// ── Priorités du jour libres (hors projet / routine) ──────────────────────────
class TodayItem {
  String id;
  String text;
  bool done;
  String date; // YYYY-MM-DD

  TodayItem({
    String? id,
    required this.text,
    this.done = false,
    required this.date,
  }) : id = id ?? _uuid.v4();

  Map<String, dynamic> toJson() =>
      {'id': id, 'text': text, 'done': done, 'date': date};

  static TodayItem from(Map j) => TodayItem(
        id: j['id'] ?? _uuid.v4(),
        text: j['text'] ?? '',
        done: j['done'] as bool? ?? false,
        date: j['date'] ?? '',
      );
}

// ─── PROGRAMME HORAIRE JOURNALIER ────────────────────────────────────────────
//
// Un doc par jour : users/{uid}/daily_schedules/{YYYY-MM-DD}
// Généré par Claude à la demande ou par ORION automatiquement chaque matin.

class ScheduleBlock {
  String id;
  String startTime;   // "HH:mm"
  int durationMin;
  String title;
  String category;    // project | routine | personal | break
  String? projectId;
  String? taskId;
  String? activityId;
  String? actionId; // action ciblée (TaskAction propre OU action de projet)
  String status;      // pending | done | skipped | deleted
  DateTime? doneAt;
  bool challenge;     // bloc né d'un « Challenge me » programmé (badge 🔥 + streak)
  List<String> reminders; // dates ISO des rappels programmés (max 2 pour un défi)
  // ── Préparation la veille ──────────────────────────────────────────────────
  // Absents = bloc normal (rétrocompatible). kind:"prep" = mini-bloc « préparer
  // ses affaires » le soir, lié à un bloc cible du lendemain matin. La référence
  // vers le bloc cible est (date, id) car il vit dans le doc d'un autre jour.
  // kind:"bilan" = bilan d'essai posé à J+14 par la renégociation structurelle.
  // kind:"session" = session de définition d'un domaine (onboarding 18b) —
  // domainId pointe le domaine à définir, le tap lance la session.
  String kind;            // "normal" (défaut) | "prep" | "bilan" | "session"
  String? prepForDate;    // "YYYY-MM-DD" — jour du bloc cible (souvent J+1)
  String? prepForBlockId; // id du bloc cible dans daily_schedules/{prepForDate}
  String? domainId;       // domaine ciblé (kind:"session")
  // ── Check-in du soir ───────────────────────────────────────────────────────
  // Pourquoi l'engagement a sauté — fait tracké, écrit par le check-in guidé.
  // Enum ouvert : "imprevu" | "energie" | "sous_estime" | "evite" | texte libre.
  String? skipReason;
  // Raison donnée AU MOMENT du report (skipReason "reporte" garde son sens
  // serveur : « demain il passe en premier ») : "pas_sur_place" | "imprevu" |
  // "energie" | "pas_le_moment" | texte libre. Le check-in et la proposition
  // du lendemain la citent telle quelle.
  String? reportReason;

  ScheduleBlock({
    String? id,
    required this.startTime,
    required this.durationMin,
    required this.title,
    this.category = 'personal',
    this.projectId,
    this.taskId,
    this.activityId,
    this.actionId,
    this.status = 'pending',
    this.doneAt,
    this.challenge = false,
    List<String>? reminders,
    this.kind = 'normal',
    this.prepForDate,
    this.prepForBlockId,
    this.domainId,
    this.skipReason,
    this.reportReason,
  })  : id = id ?? _uuid.v4(),
        reminders = reminders ?? [];

  bool get isPrep => kind == 'prep';

  Map<String, dynamic> toJson() => {
        'id': id,
        'startTime': startTime,
        'durationMin': durationMin,
        'title': title,
        'category': category,
        'projectId': projectId,
        'taskId': taskId,
        'activityId': activityId,
        'actionId': actionId,
        'status': status,
        'doneAt': doneAt?.toIso8601String(),
        'challenge': challenge,
        'reminders': reminders,
        'kind': kind,
        'prepForDate': prepForDate,
        'prepForBlockId': prepForBlockId,
        'domainId': domainId,
        'skipReason': skipReason,
        'reportReason': reportReason,
      };

  static ScheduleBlock from(Map j) => ScheduleBlock(
        id: j['id'],
        startTime: j['startTime'] ?? '00:00',
        durationMin: (j['durationMin'] as num?)?.toInt() ?? 30,
        title: j['title'] ?? '',
        category: j['category'] ?? 'personal',
        projectId: j['projectId'],
        taskId: j['taskId'],
        activityId: j['activityId'],
        actionId: j['actionId'],
        status: j['status'] ?? 'pending',
        doneAt: _parseDateOrNull(j['doneAt']),
        challenge: j['challenge'] == true,
        reminders: (j['reminders'] as List?)?.map((e) => e.toString()).toList(),
        kind: j['kind'] ?? 'normal',
        prepForDate: j['prepForDate'],
        prepForBlockId: j['prepForBlockId'],
        domainId: j['domainId'],
        skipReason: j['skipReason'],
        reportReason: j['reportReason'],
      );
}

class DailySchedule {
  String date;        // YYYY-MM-DD
  String generatedBy; // claude | orion
  DateTime generatedAt;
  List<ScheduleBlock> blocks;
  // ── Check-in du soir / planification — faits trackés (optionnels) ──────────
  // Cause globale quand 3+ engagements ont sauté (pas de skipReason par bloc) :
  // "imprevu_global" | "energie" | "irrealiste" | texte libre.
  String? dayReason;
  // Planification le jour même après 5h (rattrapage du matin) — rejoué au
  // check-in du soir sans culpabiliser (« 7 h 58 — planifié au réveil »).
  DateTime? plannedAt;
  bool plannedSameDay;
  // Mode soirée RÉVERSIBLE (23c) : « Terminer l'après-midi » bascule tout le
  // système en soirée — les blocs non faits passent « en attente, à recaser
  // ce soir » (jamais supprimés, recasés au check-in). « Revenir » restaure
  // le programme tel quel : les blocs ne sont jamais modifiés par la bascule.
  String dayMode; // "normal" | "evening"
  DateTime? dayModeActivatedAt;

  DailySchedule({
    required this.date,
    this.generatedBy = 'claude',
    DateTime? generatedAt,
    List<ScheduleBlock>? blocks,
    this.dayReason,
    this.plannedAt,
    this.plannedSameDay = false,
    this.dayMode = 'normal',
    this.dayModeActivatedAt,
  })  : generatedAt = generatedAt ?? DateTime.now(),
        blocks = blocks ?? [];

  bool get eveningMode => dayMode == 'evening';

  Map<String, dynamic> toJson() => {
        'date': date,
        'generatedBy': generatedBy,
        'generatedAt': generatedAt.toIso8601String(),
        'blocks': blocks.map((b) => b.toJson()).toList(),
        'dayReason': dayReason,
        'plannedAt': plannedAt?.toIso8601String(),
        'plannedSameDay': plannedSameDay,
        'dayMode': dayMode,
        'dayModeActivatedAt': dayModeActivatedAt?.toIso8601String(),
      };

  static DailySchedule from(Map j) => DailySchedule(
        date: j['date'] ?? '',
        generatedBy: j['generatedBy'] ?? 'claude',
        generatedAt: _parseDate(j['generatedAt']),
        blocks: (j['blocks'] as List?)
                ?.map((b) => ScheduleBlock.from(b))
                .toList() ??
            [],
        dayReason: j['dayReason'],
        plannedAt: _parseDateOrNull(j['plannedAt']),
        plannedSameDay: j['plannedSameDay'] == true,
        dayMode: j['dayMode']?.toString() == 'evening' ? 'evening' : 'normal',
        dayModeActivatedAt: _parseDateOrNull(j['dayModeActivatedAt']),
      );
}
