import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/actions_logic.dart' show effectiveDueDate, isOverdueAction, isUpcomingTask;
import 'package:productivitwo_v1/utils/project_health.dart' show ganttOrder;

/// Mur des projets (2026-10, maquette « Mur des projets ») : UNE brique,
/// répétée à trois profondeurs. Un projet = une rangée de briques (une par
/// tâche), chaque brique remplie par les actions faites ; une tâche = une
/// rangée (une par action) remplie par ses étapes ; une action = ses étapes.
/// Même couleur et même repère « attendu aujourd'hui » à chaque niveau.
/// Briques de largeur ÉGALE (c'est le compte qu'on lit, pas l'estimation).

enum BrickState {
  /// Finie.
  done,
  /// Entamée : une partie de ses enfants est faite.
  started,
  /// Échéance effective dépassée (bord corail).
  late,
  /// Un chrono tourne dessus (bord bleu-vert).
  running,
  /// Pas commencée.
  todo,
  /// Date de début pas encore arrivée (brique creuse).
  upcoming,
}

class Brick {
  final String id;
  final String title;
  final BrickState state;
  /// Part des enfants faits (0..1) ; 1 pour une brique finie.
  final double fill;
  final int done;
  final int total;
  const Brick({required this.id, required this.title, required this.state, required this.fill, this.done = 0, this.total = 0});

  bool get open => state != BrickState.done;
}

class BrickRow {
  final List<Brick> bricks;
  /// Nombre de briques ATTENDUES à ce jour (position du trait du plan).
  final int expected;
  const BrickRow({required this.bricks, required this.expected});

  int get total => bricks.length;
  int get done => bricks.where((b) => b.state == BrickState.done).length;
  int get late => bricks.where((b) => b.state == BrickState.late).length;
  bool get hasRunning => bricks.any((b) => b.state == BrickState.running);
  /// Position du trait (0..1) ; null sans briques ou sans attendu.
  double? get tickX => total == 0 || expected <= 0 ? null : (expected / total).clamp(0.0, 1.0);
  /// Briques à gauche du trait qui ne sont pas finies = retard visible.
  int get behindTick => expected <= 0 ? 0 : bricks.take(expected).where((b) => b.open).length;
}

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// Part faite d'une action : faite = 1, sinon étapes cochées / étapes (0 sans étape).
double actionFill(TaskAction a) {
  if (a.done) return 1;
  if (a.checklist.isEmpty) return 0;
  return a.checklist.where((c) => c.done).length / a.checklist.length;
}

/// Part faite d'une tâche : faite = 1 ; sinon moyenne des parts de ses actions
/// (une action entamée par ses étapes remplit déjà un peu la brique) ; 0 sans action.
double taskFill(ProjectTask t) {
  if (t.status == 'done') return 1;
  if (t.actions.isEmpty) return 0;
  var sum = 0.0;
  for (final a in t.actions) {
    sum += actionFill(a);
  }
  return sum / t.actions.length;
}

/// Tâche en retard : échéance passée, ou une action ouverte dont l'échéance propre est passée.
bool _taskLate(ProjectTask t, DateTime today) {
  final d = _day(today);
  final end = t.endDate;
  if (end != null && _day(end).isBefore(d)) return true;
  return t.actions.any((a) => isOverdueAction(a, t, today));
}

Brick taskBrick(ProjectTask t, DateTime today, {Set<String> runningTaskIds = const {}, Set<String> runningActionIds = const {}}) {
  final fill = taskFill(t);
  final done = t.actions.where((a) => a.done).length;
  final BrickState state;
  if (t.status == 'done') {
    state = BrickState.done;
  } else if (runningTaskIds.contains(t.id) || t.actions.any((a) => runningActionIds.contains(a.id))) {
    state = BrickState.running;
  } else if (_taskLate(t, today)) {
    state = BrickState.late;
  } else if (fill > 0) {
    state = BrickState.started;
  } else if (isUpcomingTask(t, today)) {
    state = BrickState.upcoming;
  } else {
    state = BrickState.todo;
  }
  return Brick(id: t.id, title: t.title, state: state, fill: fill, done: done, total: t.actions.length);
}

Brick actionBrick(TaskAction a, ProjectTask t, DateTime today, {Set<String> runningActionIds = const {}}) {
  final fill = actionFill(a);
  final done = a.checklist.where((c) => c.done).length;
  final BrickState state;
  if (a.done) {
    state = BrickState.done;
  } else if (runningActionIds.contains(a.id)) {
    state = BrickState.running;
  } else if (isOverdueAction(a, t, today)) {
    state = BrickState.late;
  } else if (fill > 0) {
    state = BrickState.started;
  } else if (isUpcomingTask(t, today)) {
    state = BrickState.upcoming;
  } else {
    state = BrickState.todo;
  }
  return Brick(id: a.id, title: a.title, state: state, fill: fill, done: done, total: a.checklist.length);
}

/// Rangée d'un projet : une brique par tâche dans l'ordre du Gantt (hors « Au
/// fil de l'eau » et tâches sautées) ; trait = tâches attendues à ce jour
/// (échéance, sinon début, passée ou aujourd'hui — même règle que `projectPlan`).
BrickRow projectBricks(Project p, DateTime today, {Set<String> runningTaskIds = const {}, Set<String> runningActionIds = const {}}) {
  final d = _day(today);
  final bricks = <Brick>[];
  var expected = 0;
  for (final t in ganttOrder(p)) {
    if (t.id == 'gtd-flow' || t.status == 'skipped') continue;
    bricks.add(taskBrick(t, today, runningTaskIds: runningTaskIds, runningActionIds: runningActionIds));
    if (!_day(t.endDate ?? t.startDate).isAfter(d)) expected++;
  }
  return BrickRow(bricks: bricks, expected: expected);
}

/// Rangée d'une tâche : une brique par action dans l'ordre de la tâche ; trait
/// = actions dont l'échéance effective est passée ou aujourd'hui.
BrickRow taskBricks(ProjectTask t, DateTime today, {Set<String> runningActionIds = const {}}) {
  final d = _day(today);
  final bricks = <Brick>[];
  var expected = 0;
  for (final a in t.actions) {
    bricks.add(actionBrick(a, t, today, runningActionIds: runningActionIds));
    final due = effectiveDueDate(a, t);
    if (due != null && !due.isAfter(d)) expected++;
  }
  return BrickRow(bricks: bricks, expected: expected);
}

/// Chronos ouverts → tâches et actions visées (pour l'état « chrono dessus »).
({Set<String> taskIds, Set<String> actionIds}) runningTargets(Iterable<Session> sessions) {
  final t = <String>{}, a = <String>{};
  for (final s in sessions) {
    if (s.endAt != null || s.deleted) continue;
    if (s.taskId != null && s.taskId!.isNotEmpty) t.add(s.taskId!);
    if (s.actionId != null && s.actionId!.isNotEmpty) a.add(s.actionId!);
  }
  return (taskIds: t, actionIds: a);
}

/// Synthèse du mur : tâches faites / total sur les projets donnés, projets en
/// retard sur le trait (au moins une brique ouverte à gauche du trait).
({int done, int total, int behind}) wallDigest(Iterable<BrickRow> rows) {
  var done = 0, total = 0, behind = 0;
  for (final r in rows) {
    done += r.done;
    total += r.total;
    if (r.behindTick > 0) behind++;
  }
  return (done: done, total: total, behind: behind);
}

/// « 3 tâches derrière le trait : 2 en retard, 1 en cours » ; null si rien.
String? behindLabel(BrickRow r) {
  final n = r.behindTick;
  if (n == 0) return null;
  final behind = r.bricks.take(r.expected).where((b) => b.open).toList();
  final late = behind.where((b) => b.state == BrickState.late).length;
  final rest = n - late;
  final parts = <String>[
    if (late > 0) '$late en retard',
    if (rest > 0) '$rest ${rest > 1 ? 'pas finies' : 'pas finie'}',
  ];
  return '$n tâche${n > 1 ? 's' : ''} derrière le trait : ${parts.join(', ')}';
}
