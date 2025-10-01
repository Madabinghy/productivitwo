import 'dart:convert';
import 'dart:math' as math;
import 'package:uuid/uuid.dart';

const _uuid = Uuid();
const int kMinDailyGoalMin = 1;
enum PlanKind { action, activityTime, habit }

enum HabitFreq { daily, weekly, monthly }

class DayPlanItem {
  String id;
  PlanKind kind;
  String? refId; // activityId si activity/habit, sinon null pour action volante
  String title; // libellé si action volante
  String yyyymmdd; // jour planifié
  bool done; // pour actions & activités
  bool allDay; // pour les habitudes "à suivre toute la journée"
  int order; // tri visuel

  DayPlanItem({
    required this.id,
    required this.kind,
    this.refId,
    required this.title,
    required this.yyyymmdd,
    this.done = false,
    this.allDay = false,
    this.order = 0,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        'refId': refId,
        'title': title,
        'yyyymmdd': yyyymmdd,
        'done': done,
        'allDay': allDay,
        'order': order,
      };

  static DayPlanItem from(Map j) => DayPlanItem(
        id: j['id'],
        kind: PlanKind.values.firstWhere((k) => k.name == j['kind']),
        refId: j['refId'],
        title: j['title'] ?? '',
        yyyymmdd: j['yyyymmdd'],
        done: j['done'] ?? false,
        allDay: j['allDay'] ?? false,
        order: j['order'] ?? 0,
      );
}

class InboxItem {
  String id;
  String title;
  DateTime createdAt;
  InboxItem({String? id, required this.title, DateTime? createdAt})
      : id = id ?? _uuid.v4(),
        createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'createdAt': createdAt.toIso8601String(),
      };
  static InboxItem from(Map j) => InboxItem(
        id: j['id'],
        title: j['title'],
        createdAt: DateTime.parse(j['createdAt']),
      );
}

// --- OBJECTIFS (GTD light) ---
// status: 'active' | 'done' | 'archived'
class Goal {
  String id, domainId, title;
  String status; // 'active' par défaut
  String? activityId; // activité support (optionnel)
  String? nextAction; // une seule "prochaine action"
  String? context; // ex: "maison", "travail" (optionnel)
  DateTime createdAt;
  DateTime? doneAt;

  int? effortEstimateMin; // estimation totale en minutes (ex: 600 = 10 h)
  int? stepsPlanned; // nb d'étapes prévues (ex: 5 chapitres)
  int stepsDone; // nb d'étapes réalisées
  DateTime? dueDate; // (optionnel) pour plus tard

  Goal({
    String? id,
    required this.domainId,
    required this.title,
    this.status = 'active',
    this.activityId,
    this.nextAction,
    this.context,
    DateTime? createdAt,
    this.doneAt,
    this.effortEstimateMin,
    this.stepsPlanned,
    this.stepsDone = 0,
    this.dueDate,
  })  : id = id ?? _uuid.v4(),
        createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'domainId': domainId,
        'title': title,
        'status': status,
        'activityId': activityId,
        'nextAction': nextAction,
        'context': context,
        'createdAt': createdAt.toIso8601String(),
        'doneAt': doneAt?.toIso8601String(),
        'effortEstimateMin': effortEstimateMin,
        'stepsPlanned': stepsPlanned,
        'stepsDone': stepsDone,
        'dueDate': dueDate?.toIso8601String(),
      };

  static Goal from(Map j) => Goal(
        id: j['id'],
        domainId: j['domainId'],
        title: j['title'],
        status: j['status'] ?? 'active',
        activityId: j['activityId'],
        nextAction: j['nextAction'],
        context: j['context'],
        createdAt: DateTime.parse(j['createdAt']),
        doneAt: j['doneAt'] != null ? DateTime.parse(j['doneAt']) : null,
        effortEstimateMin: j['effortEstimateMin'],
        stepsPlanned: j['stepsPlanned'],
        stepsDone: (j['stepsDone'] ?? 0),
        dueDate: j['dueDate'] != null ? DateTime.parse(j['dueDate']) : null,
      );
}

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
  String? unit;
  int? dailyTarget;

  // NEW: quand créée + quand dernier ajustement
  DateTime createdAt;
  DateTime? lastTunedAt;

  // Habitudes (nouveau modèle unifié)
  HabitFreq? habitFreq; // null => legacy (dailyTarget)
  int habitTarget; // nombre par période (jour/sem/mois)
  bool autoTune; // true par défaut
  DateTime? lastTuneAt; // anti spam (cooldown)

  Activity({
    String? id,
    required this.domainId,
    required this.name,
    this.type = 'time',
    this.goalMin = kMinDailyGoalMin,
    this.unit,
    this.dailyTarget,
    DateTime? createdAt,
    this.lastTunedAt,
    this.habitFreq,
    required this.habitTarget,
    this.autoTune = true,
    this.lastTuneAt,
  })  : id = id ?? _uuid.v4(),
        createdAt = createdAt ?? DateTime.now();

  bool get isHabit => type == 'habit';

  Map<String, dynamic> toJson() => {
        'id': id,
        'domainId': domainId,
        'name': name,
        'type': type,
        'goalMin': goalMin,
        'unit': unit,
        'dailyTarget': dailyTarget,
        'createdAt': createdAt.toIso8601String(),
        'lastTunedAt': lastTunedAt?.toIso8601String(),
        'habitFreq': habitFreq?.index,
        'habitTarget': habitTarget,
        'autoTune': autoTune,
        'lastTuneAt': lastTuneAt?.toIso8601String(),
      };

  static Activity from(Map j) => Activity(
        id: j['id'],
        domainId: j['domainId'],
        name: j['name'],
        type: (j['type'] ?? 'time'),
        goalMin: math.max(kMinDailyGoalMin, j['goalMin'] ?? kMinDailyGoalMin),
        unit: j['unit'],
        dailyTarget: 1,
        createdAt: j['createdAt'] != null
            ? DateTime.parse(j['createdAt'])
            : DateTime.now(),
        lastTunedAt:
            j['lastTunedAt'] != null ? DateTime.parse(j['lastTunedAt']) : null,
        habitFreq: HabitFreq.monthly,
        habitTarget: 1,
        autoTune: true,
        lastTuneAt:
            j['lastTuneAt'] != null ? DateTime.parse(j['lastTuneAt']) : null,
            
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
  List<Goal> goals;
  List<InboxItem> inbox;
  List<DayPlanItem> dayPlan;
  String? lastRolloverYmd;

  AppState({
    required this.domains,
    required this.activities,
    required this.sessions,
    required this.habitProgress,
    this.lastGoalsReview,
    Map<String, String>? snoozedUntil,
    List<Goal>? goals,
    List<InboxItem>? inbox,
    this.dayPlan = const [],
  })  : snoozedUntil = snoozedUntil ?? {},
        goals = goals ?? [],
        inbox = inbox ?? [];

  Map<String, dynamic> toJson() => {
        'domains': domains.map((e) => e.toJson()).toList(),
        'activities': activities.map((e) => e.toJson()).toList(),
        'sessions': sessions.map((e) => e.toJson()).toList(),
        'habitProgress': habitProgress.map((e) => e.toJson()).toList(),
        'lastGoalsReview': lastGoalsReview?.toIso8601String(),
        'snoozedUntil': snoozedUntil,
        'goals': goals.map((e) => e.toJson()).toList(),
        'inbox': inbox.map((e) => e.toJson()).toList(),
        'dayPlan': dayPlan.map((e) => e.toJson()).toList(),
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
        snoozedUntil: (j['snoozedUntil'] as Map?)
                ?.map((k, v) => MapEntry(k as String, v as String)) ??
            {},
        goals: (j['goals'] == null)
            ? <Goal>[]
            : (j['goals'] as List).map((e) => Goal.from(e)).toList(),
        inbox: (j['inbox'] == null)
            ? <InboxItem>[]
            : (j['inbox'] as List).map((e) => InboxItem.from(e)).toList(),
        dayPlan: (j['dayPlan'] == null)
            ? <DayPlanItem>[]
            : (j['dayPlan'] as List).map((e) => DayPlanItem.from(e)).toList(),
      );

  String encode() => jsonEncode(toJson());
  static AppState decode(String s) => from(jsonDecode(s));
}

/// Utilitaires de date
String yyyymmdd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';
