import 'dart:convert';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// --- DOMAINES ---
class Domain {
  String id, name;
  int? goalMinDay; // minutes/jour, null => auto (somme des activités time)
  bool autoGoal; // true => objectif = somme des activités time

  Domain({
    String? id,
    required this.name,
    this.goalMinDay,
    this.autoGoal = true,
  }) : id = id ?? _uuid.v4();

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'goalMinDay': goalMinDay,
        'autoGoal': autoGoal,
      };

  static Domain from(Map j) => Domain(
        id: j['id'],
        name: j['name'],
        goalMinDay: j['goalMinDay'],
        autoGoal: j['autoGoal'] ?? true,
      );
}

/// --- ACTIVITÉS ---
/// type = "time" (timer) ou "habit" (compteur)
class Activity {
  String id, domainId, name;
  String type; // "time" | "habit"
  int goalMin; // pour type=time
  // Pour type=habit :
  String? unit; // ex: "verres", "pompes"
  int? dailyTarget; // objectif quotidien (nombre)

  Activity({
    String? id,
    required this.domainId,
    required this.name,
    this.type = 'time',
    this.goalMin = 15,
    this.unit,
    this.dailyTarget,
  }) : id = id ?? _uuid.v4();

  bool get isHabit => type == 'habit';

  Map<String, dynamic> toJson() => {
        'id': id,
        'domainId': domainId,
        'name': name,
        'type': type,
        'goalMin': goalMin,
        'unit': unit,
        'dailyTarget': dailyTarget,
      };

  static Activity from(Map j) => Activity(
        id: j['id'],
        domainId: j['domainId'],
        name: j['name'],
        type: (j['type'] ?? 'time'),
        goalMin: j['goalMin'] ?? 15,
        unit: j['unit'],
        dailyTarget: j['dailyTarget'],
      );
}

/// --- SESSIONS TEMPS ---
class Session {
  String id, activityId;
  DateTime startAt;
  DateTime? endAt;
  Session(
      {String? id, required this.activityId, required this.startAt, this.endAt})
      : id = id ?? _uuid.v4();
  Duration get duration => (endAt ?? DateTime.now()).difference(startAt);
  Map<String, dynamic> toJson() => {
        'id': id,
        'activityId': activityId,
        'startAt': startAt.toIso8601String(),
        'endAt': endAt?.toIso8601String()
      };
  static Session from(Map j) => Session(
      id: j['id'],
      activityId: j['activityId'],
      startAt: DateTime.parse(j['startAt']),
      endAt: j['endAt'] != null ? DateTime.parse(j['endAt']) : null);
}

/// --- PROGRESSION HABITUDES ---
/// Stocke la valeur d’une habitude pour un jour donné (clé date "YYYYMMDD")
class HabitProgress {
  String id, activityId, yyyymmdd;
  int value;
  HabitProgress({
    String? id,
    required this.activityId,
    required this.yyyymmdd,
    this.value = 0,
  }) : id = id ?? _uuid.v4();

  Map<String, dynamic> toJson() => {
        'id': id,
        'activityId': activityId,
        'yyyymmdd': yyyymmdd,
        'value': value
      };

  static HabitProgress from(Map j) => HabitProgress(
        id: j['id'],
        activityId: j['activityId'],
        yyyymmdd: j['yyyymmdd'],
        value: j['value'] ?? 0,
      );
}

/// --- APP STATE ---
class AppState {
  List<Domain> domains;
  List<Activity> activities;
  List<Session> sessions;
  List<HabitProgress> habitProgress;
  DateTime? lastGoalsReview;
    // NEW: activité → ISO8601 jusqu’à quand elle est “snoozed”
  Map<String, String> snoozedUntil;

  AppState({
    required this.domains,
    required this.activities,
    required this.sessions,
    required this.habitProgress,
    this.lastGoalsReview,
    Map<String, String>? snoozedUntil,       
  }) : snoozedUntil = snoozedUntil ?? {};

  Map<String, dynamic> toJson() => {
        'domains': domains.map((e) => e.toJson()).toList(),
        'activities': activities.map((e) => e.toJson()).toList(),
        'sessions': sessions.map((e) => e.toJson()).toList(),
        'habitProgress': habitProgress.map((e) => e.toJson()).toList(),
        'lastGoalsReview': lastGoalsReview?.toIso8601String(),
        'snoozedUntil': snoozedUntil,
      };

  static AppState from(Map j) => AppState(
        domains: (j['domains'] as List).map((e) => Domain.from(e)).toList(),
        activities:
            (j['activities'] as List).map((e) => Activity.from(e)).toList(),
        sessions: (j['sessions'] as List).map((e) => Session.from(e)).toList(),
        habitProgress: (j['habitProgress'] == null)
            ? <HabitProgress>[]
            : (j['habitProgress'] as List)
                .map((e) => HabitProgress.from(e))
                .toList(),
        lastGoalsReview: j['lastGoalsReview'] == null
            ? null
            : DateTime.parse(j['lastGoalsReview']),
            snoozedUntil: (j['snoozedUntil'] as Map?)?.map((k, v) => MapEntry(k as String, v as String)) ?? {},
      );

  String encode() => jsonEncode(toJson());
  static AppState decode(String s) => from(jsonDecode(s));
}

/// Utilitaires de date
String yyyymmdd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';
