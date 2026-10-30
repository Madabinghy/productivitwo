import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/objective_day.dart';

/// Fiche « Objectifs aujourd'hui » (maquette validée 2026-10-30) : lire, puis
/// agir. Trois étages — le chiffre du jour, OÙ J'EN SUIS (une ligne par
/// objectif), À FAIRE (UNE liste de gestes classés, l'objectif servi en
/// étiquette). Logique pure : la vue fournit les comptes et le rythme.
enum ObjTodoKind { time, routine, reading, block, action }

class ObjTodo {
  final ObjTodoKind kind;
  final StrategicObjective objective;
  final String title;
  final String sub;
  /// Forme courte pour « reste aujourd'hui » (« 25 min de Courir », « Pompes »).
  final String short;
  final bool done;
  /// Compte dans « k / n choses » (les prochaines actions n'y entrent pas).
  final bool counted;
  final int weight;
  final Activity? activity;
  final ScheduleBlock? block;
  final ({Project project, ProjectTask task, TaskAction action})? next;
  const ObjTodo({
    required this.kind,
    required this.objective,
    required this.title,
    required this.sub,
    required this.short,
    required this.done,
    this.counted = true,
    required this.weight,
    this.activity,
    this.block,
    this.next,
  });

  String get key => switch (kind) {
        ObjTodoKind.time || ObjTodoKind.routine => '${kind.name}:${activity?.id}',
        ObjTodoKind.block => 'block:${block?.id}',
        ObjTodoKind.reading => 'reading:${objective.id}',
        ObjTodoKind.action => 'action:${next?.action.id}',
      };
}

class ObjStatus {
  final StrategicObjective objective;
  /// Part du rythme de la semaine (0..), null sans engagement mesurable.
  final int? pct;
  final List<String> left;
  final bool heldToday;
  const ObjStatus(this.objective, this.pct, this.left, this.heldToday);
  bool get late => pct != null && pct! < 85;
}

class ObjectivesToday {
  final List<ObjStatus> statuses;
  /// À faire, le plus utile d'abord.
  final List<ObjTodo> todo;
  final List<ObjTodo> done;
  const ObjectivesToday(this.statuses, this.todo, this.done);
  int get doneCount => done.where((t) => t.counted).length;
  int get total => doneCount + todo.where((t) => t.counted).length;
  int get remaining => total - doneCount;
  int get lateCount => statuses.where((s) => s.late).length;
}

String _min(int m) => m >= 60 ? '${m ~/ 60} h${m % 60 == 0 ? '' : ' ${(m % 60).toString().padLeft(2, '0')}'}' : '$m min';

ObjectivesToday buildObjectivesToday(
  List<ObjectiveDay> days, {
  /// (fait, cible) de la routine sur sa période (jour, 7 j, 30 j).
  required (int, int) Function(Activity a) routineProgress,
  required bool Function(StrategicObjective o) readingDue,
  required int? Function(StrategicObjective o) pctOf,
  String? runningActivityId,
}) {
  final todo = <ObjTodo>[];
  final done = <ObjTodo>[];
  final seen = <String>{};
  final statuses = <ObjStatus>[];
  for (final d in days) {
    final o = d.objective;
    final pct = pctOf(o);
    final lateness = pct == null ? 0 : (100 - pct).clamp(0, 100);
    final mine = <ObjTodo>[];
    for (final t in d.times) {
      final left = t.expectedTodayMin - t.doneTodayMin;
      mine.add(ObjTodo(
        kind: ObjTodoKind.time,
        objective: o,
        title: left > 0 ? '${t.name} · encore ${_min(left)}' : t.name,
        sub: '${_min(t.doneTodayMin)} / ${_min(t.expectedTodayMin)} aujourd’hui · ${_min(t.doneWeekMin)} / ${_min(t.weeklyMin)} cette semaine',
        short: '${_min(left)} de ${t.name}',
        done: left <= 0,
        weight: lateness + 10 + (t.activityId == runningActivityId ? 50 : 0),
        activity: t.activity,
      ));
    }
    for (final a in d.routines) {
      final (n, target) = routineProgress(a);
      final period = switch (a.habitFreq) { HabitFreq.weekly => ' sur 7 j', HabitFreq.monthly => ' sur 30 j', _ => '' };
      mine.add(ObjTodo(
        kind: ObjTodoKind.routine,
        objective: o,
        title: '${a.name} · $n / $target$period',
        sub: 'routine',
        short: a.name,
        done: n >= target,
        weight: lateness + 8,
        activity: a,
      ));
    }
    if (readingDue(o)) {
      final label = o.metric?.label ?? 'métrique';
      mine.add(ObjTodo(
        kind: ObjTodoKind.reading,
        objective: o,
        title: 'Noter le relevé · $label',
        sub: 'relevé dû',
        short: 'relevé',
        done: false,
        weight: lateness + 15,
      ));
    }
    for (final b in d.blocks) {
      if (b.status == 'skipped' || b.status == 'deleted') continue;
      mine.add(ObjTodo(
        kind: ObjTodoKind.block,
        objective: o,
        title: 'Bloc ${b.startTime} · ${b.title}',
        sub: '${b.durationMin} min',
        short: 'bloc ${b.startTime}',
        done: b.status == 'done',
        weight: lateness + 12,
        block: b,
      ));
    }
    for (final n in d.nextActions) {
      mine.add(ObjTodo(
        kind: ObjTodoKind.action,
        objective: o,
        title: n.action.title,
        sub: '${n.project.title} › ${n.task.title}',
        short: n.action.title,
        done: false,
        counted: false,
        weight: lateness - 20,
        next: n,
      ));
    }
    final open = [for (final t in mine) if (!t.done && t.counted) t];
    final countedMine = mine.where((t) => t.counted).length;
    statuses.add(ObjStatus(o, pct, [for (final t in open) t.short], countedMine > 0 && open.isEmpty));
    for (final t in mine) {
      if (!seen.add(t.key)) continue; // un même geste sert plusieurs objectifs : une seule ligne
      (t.done ? done : todo).add(t);
    }
  }
  todo.sort((a, b) => b.weight.compareTo(a.weight));
  statuses.sort((a, b) {
    if (a.heldToday != b.heldToday) return a.heldToday ? 1 : -1;
    return (a.pct ?? 100).compareTo(b.pct ?? 100);
  });
  return ObjectivesToday(statuses, todo, done);
}
