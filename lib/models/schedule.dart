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
  String kind;            // "normal" (défaut) | "prep"
  String? prepForDate;    // "YYYY-MM-DD" — jour du bloc cible (souvent J+1)
  String? prepForBlockId; // id du bloc cible dans daily_schedules/{prepForDate}
  // ── Check-in du soir ───────────────────────────────────────────────────────
  // Pourquoi l'engagement a sauté — fait tracké, écrit par le check-in guidé.
  // Enum ouvert : "imprevu" | "energie" | "sous_estime" | "evite" | texte libre.
  String? skipReason;

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
    this.skipReason,
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
        'skipReason': skipReason,
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
        skipReason: j['skipReason'],
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

  DailySchedule({
    required this.date,
    this.generatedBy = 'claude',
    DateTime? generatedAt,
    List<ScheduleBlock>? blocks,
    this.dayReason,
    this.plannedAt,
    this.plannedSameDay = false,
  })  : generatedAt = generatedAt ?? DateTime.now(),
        blocks = blocks ?? [];

  Map<String, dynamic> toJson() => {
        'date': date,
        'generatedBy': generatedBy,
        'generatedAt': generatedAt.toIso8601String(),
        'blocks': blocks.map((b) => b.toJson()).toList(),
        'dayReason': dayReason,
        'plannedAt': plannedAt?.toIso8601String(),
        'plannedSameDay': plannedSameDay,
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
      );
}
