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
  String status;      // pending | done | skipped
  DateTime? doneAt;
  bool challenge;     // bloc né d'un « Challenge me » programmé (badge 🔥 + streak)
  List<String> reminders; // dates ISO des rappels programmés (max 2 pour un défi)

  ScheduleBlock({
    String? id,
    required this.startTime,
    required this.durationMin,
    required this.title,
    this.category = 'personal',
    this.projectId,
    this.taskId,
    this.activityId,
    this.status = 'pending',
    this.doneAt,
    this.challenge = false,
    List<String>? reminders,
  })  : id = id ?? _uuid.v4(),
        reminders = reminders ?? [];

  Map<String, dynamic> toJson() => {
        'id': id,
        'startTime': startTime,
        'durationMin': durationMin,
        'title': title,
        'category': category,
        'projectId': projectId,
        'taskId': taskId,
        'activityId': activityId,
        'status': status,
        'doneAt': doneAt?.toIso8601String(),
        'challenge': challenge,
        'reminders': reminders,
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
        status: j['status'] ?? 'pending',
        doneAt: _parseDateOrNull(j['doneAt']),
        challenge: j['challenge'] == true,
        reminders: (j['reminders'] as List?)?.map((e) => e.toString()).toList(),
      );
}

class DailySchedule {
  String date;        // YYYY-MM-DD
  String generatedBy; // claude | orion
  DateTime generatedAt;
  List<ScheduleBlock> blocks;

  DailySchedule({
    required this.date,
    this.generatedBy = 'claude',
    DateTime? generatedAt,
    List<ScheduleBlock>? blocks,
  })  : generatedAt = generatedAt ?? DateTime.now(),
        blocks = blocks ?? [];

  Map<String, dynamic> toJson() => {
        'date': date,
        'generatedBy': generatedBy,
        'generatedAt': generatedAt.toIso8601String(),
        'blocks': blocks.map((b) => b.toJson()).toList(),
      };

  static DailySchedule from(Map j) => DailySchedule(
        date: j['date'] ?? '',
        generatedBy: j['generatedBy'] ?? 'claude',
        generatedAt: _parseDate(j['generatedAt']),
        blocks: (j['blocks'] as List?)
                ?.map((b) => ScheduleBlock.from(b))
                .toList() ??
            [],
      );
}
