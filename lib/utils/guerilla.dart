import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/actions_logic.dart' show isFocusedOn;
import 'package:productivitwo_v1/utils/recharge.dart' show isBasicNeedName;
import 'package:productivitwo_v1/utils/routine_moments.dart' show RoutineDay, kMomentAllDay, kMomentAny;

/// Guérilla (maquette validée 2026-10-30, « la flemme ou moi ») : pas bien,
/// mais debout. L'app choisit, on enchaîne des coups de 5 min au plus, sans
/// réfléchir : routines du moment et de toute la journée non atteintes (+1, ou +5 pour une routine à
/// grosse cible), 5 min sur une action (actions visées aujourd'hui, puis
/// actions propres des activités). Un point d'étape tous les
/// [kGuerillaPauseEvery] coups ; « moins bien » arrête. Une guérilla est une
/// [ChainRun] `kind:"guerilla"` (corps avant / après, 1 → 5) ; elle compte
/// pour le badge Guérilla dès [kGuerillaCountedMin] coups. Logique pure.
const kGuerillaKind = 'guerilla';
const kGuerillaCoupMin = 5;
const kGuerillaPauseEvery = 3;
const kGuerillaCountedMin = 3;
const kGuerillaTiers = [1, 5, 15];
const kGuerillaMaxCoups = 12;

enum GuerillaKind { routine, action }

class GuerillaCoup {
  final GuerillaKind kind;
  final String title;
  final String hint;
  /// Routine (+[delta]) ou activité du chrono de l'action.
  final String? activityId;
  final int delta;
  final TaskAction? action;
  final String? projectId;
  final String? taskId;
  const GuerillaCoup({
    required this.kind,
    required this.title,
    required this.hint,
    this.activityId,
    this.delta = 1,
    this.action,
    this.projectId,
    this.taskId,
  });

  String get key => kind == GuerillaKind.routine ? 'r:$activityId' : 'a:${action?.id}';
}

/// Routines : +1, sauf une grosse cible (≥ 10 par jour) qui avance par 5.
int guerillaDelta(int? dayTarget, int dayDone) {
  if (dayTarget == null || dayTarget < 10) return 1;
  final left = dayTarget - dayDone;
  return left < 5 ? (left < 1 ? 1 : left) : 5;
}

/// La file d'une guérilla : routines de la file du moment (restées puis moment
/// courant) en alternance avec 5 min sur une action. Jamais un besoin de base
/// (« Manger », « Sieste »…), jamais une activité en pause.
List<GuerillaCoup> buildGuerillaQueue({
  required RoutineDay day,
  required List<Activity> activities,
  required List<Project> projects,
  required DateTime now,
  Set<String> pausedActivityIds = const {},
}) {
  final routines = <GuerillaCoup>[];
  // File du moment (restées puis moment courant), puis « toute la journée » et libres.
  final slots = [
    ...day.queue,
    for (final k in const [kMomentAllDay, kMomentAny]) ...day.of(k).where((s) => !s.reached && !day.dismissed.contains(s.id)),
  ];
  final seenRoutine = <String>{};
  for (final s in slots) {
    if (!seenRoutine.add(s.id)) continue;
    final a = s.activity;
    if (pausedActivityIds.contains(a.id) || isBasicNeedName(a.name)) continue;
    final d = guerillaDelta(s.todo.dayTarget, s.todo.dayDone);
    routines.add(GuerillaCoup(
      kind: GuerillaKind.routine,
      title: d > 1 ? '$d × ${a.name}' : a.name,
      hint: s.todo.dayTarget == null ? 'Une fois, et c\'est compté.' : '${s.todo.dayDone} / ${s.todo.dayTarget} aujourd\'hui',
      activityId: a.id,
      delta: d,
    ));
  }

  final byId = {for (final a in activities) a.id: a};
  bool usable(String? activityId) => activityId == null || (!pausedActivityIds.contains(activityId) && byId[activityId]?.deleted != true);
  final actions = <GuerillaCoup>[];
  final seen = <String>{};
  for (final p in projects) {
    if (p.paused || p.status == 'done' || p.status == 'archived') continue;
    for (final t in p.tasks) {
      if (t.status == 'done') continue;
      for (final a in t.actions) {
        if (a.done || !isFocusedOn(a, now) || !seen.add(a.id)) continue;
        final chrono = a.linkedActivityId ?? p.linkedActivityId;
        if (!usable(chrono)) continue;
        actions.add(GuerillaCoup(
            kind: GuerillaKind.action, title: a.title, hint: 'Juste 5 min. Le premier pas, pas plus.', activityId: chrono, action: a, projectId: p.id, taskId: t.id));
      }
    }
  }
  for (final act in activities) {
    if (act.deleted || pausedActivityIds.contains(act.id) || isBasicNeedName(act.name)) continue;
    for (final a in act.ownActions) {
      if (a.done || !seen.add(a.id)) continue;
      actions.add(GuerillaCoup(kind: GuerillaKind.action, title: a.title, hint: 'Juste 5 min. Le premier pas, pas plus.', activityId: act.id, action: a));
    }
  }

  final out = <GuerillaCoup>[];
  var r = 0, x = 0;
  // Deux routines (gestes du corps) pour une action : on démarre par le plus facile.
  while (out.length < kGuerillaMaxCoups && (r < routines.length || x < actions.length)) {
    for (var k = 0; k < 2 && r < routines.length && out.length < kGuerillaMaxCoups; k++) {
      out.add(routines[r++]);
    }
    if (x < actions.length && out.length < kGuerillaMaxCoups) out.add(actions[x++]);
  }
  return out;
}

/// Le coup suivant de la file après [index], en sautant ceux passés (« Pas ça »).
int? nextCoupIndex(List<GuerillaCoup> queue, int index, Set<String> passed) {
  for (var i = index + 1; i < queue.length; i++) {
    if (!passed.contains(queue[i].key)) return i;
  }
  return null;
}

bool isGuerillaRun(ChainRun r) => r.kind == kGuerillaKind;

bool guerillaCounts(ChainRun r) => isGuerillaRun(r) && r.doneCount >= kGuerillaCountedMin;

/// Point d'étape dû après [done] coups faits.
bool guerillaPauseDue(int done) => done > 0 && done % kGuerillaPauseEvery == 0;

/// Guérillas notées avant ET après, et celles qui ont fait remonter.
({int rated, int lifted}) guerillaLift(Iterable<ChainRun> runs) {
  var rated = 0, lifted = 0;
  for (final r in runs.where(isGuerillaRun)) {
    final b = r.bodyBefore, a = r.bodyAfter;
    if (b == null || a == null) continue;
    rated++;
    if (a > b) lifted++;
  }
  return (rated: rated, lifted: lifted);
}

/// « Sur tes 4 guérillas, 3 t'ont fait remonter. » (null sans guérilla notée).
String? guerillaLiftLine(Iterable<ChainRun> runs) {
  final l = guerillaLift(runs);
  if (l.rated == 0) return null;
  if (l.rated == 1) return l.lifted == 1 ? 'Ta première guérilla t\'a fait remonter.' : 'Première guérilla notée : on verra sur les suivantes.';
  return 'Sur tes ${l.rated} guérillas, ${l.lifted} t\'${l.lifted > 1 ? 'ont' : 'a'} fait remonter.';
}

/// « Guérilla comptée · 4 coups » / « Encore 1 coup pour qu'elle compte ».
String guerillaCountLine(int done) {
  if (done >= kGuerillaCountedMin) return 'Guérilla comptée · $done coup${done > 1 ? 's' : ''}';
  final left = kGuerillaCountedMin - done;
  return 'Encore $left coup${left > 1 ? 's' : ''} pour qu\'elle compte';
}
