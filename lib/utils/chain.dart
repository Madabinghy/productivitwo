import 'dart:math' as math;

import 'package:productivitwo_v1/utils/lived_day.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/block_work.dart';
import 'package:productivitwo_v1/utils/routine_moments.dart';
import 'package:productivitwo_v1/utils/routines_today.dart';
import 'package:productivitwo_v1/utils/today_logic.dart';

/// Mode « Enchaîner » (mobile, 2026-10) : la journée déroulée une chose à la
/// fois. La file se construit SEULE depuis le programme du jour — blocs à
/// faire dans l'ordre ; dans un bloc de tâche, l'action visée puis les autres
/// actions ouvertes ; une action avec des étapes = une étape par écran ; un
/// bloc de routine = une carte « +1 » ; un rendez-vous ou un bloc perso = une
/// carte « fait ». Elle est recalculée à chaque changement : ce qui vient
/// d'être coché disparaît, le suivant arrive.
enum ChainKind { step, action, routine, session, block }

class ChainItem {
  final ChainKind kind;
  final ScheduleBlock block;
  final Project? project;
  final ProjectTask? task;
  final TaskAction? action;
  final ChecklistItem? step;
  final Activity? activity;
  /// Rang de l'étape parmi les étapes ouvertes de l'action (1-based) et total.
  final int index;
  final int total;

  const ChainItem({
    required this.kind,
    required this.block,
    this.project,
    this.task,
    this.action,
    this.step,
    this.activity,
    this.index = 1,
    this.total = 1,
  });

  /// Identité stable d'un écran (reports « plus tard », écartés).
  String get key => '${block.id}/${activity?.id ?? ''}/${action?.id ?? ''}/${step?.id ?? ''}';

  /// Bloc fabriqué pour porter une routine accrochée (moment, entre deux
  /// blocs) : n'existe pas dans le programme — ni transition, ni écriture.
  bool get synthetic => block.id.startsWith(kSyntheticPrefix);

  String get title =>
      step?.title ?? action?.title ?? activity?.name ?? block.title;

  /// Ligne au-dessus du titre : d'où vient ce qu'on fait.
  String? get context {
    switch (kind) {
      case ChainKind.step:
        return action?.title;
      case ChainKind.action:
        return task?.title ?? activity?.name;
      case ChainKind.routine:
        return 'Routine';
      case ChainKind.session:
        return project?.title;
      case ChainKind.block:
        return null;
    }
  }

  /// Un chrono a un sens sur cet écran (tâche, action d'activité, bloc avec
  /// activité-temps) ; jamais sur une routine ni un bloc libre.
  bool get timed => kind != ChainKind.routine && (block.projectId != null || block.activityId != null);
}

ProjectTask? _taskOf(ScheduleBlock b, List<Project> projects) {
  final tid = b.taskId;
  if (tid == null || tid.isEmpty) return null;
  final own = b.projectId == null ? null : projects.where((p) => p.id == b.projectId).firstOrNull;
  for (final p in [if (own != null) own, ...projects]) {
    for (final t in p.tasks) {
      if (t.id == tid) return t;
    }
  }
  return null;
}

Project? _projectOfTask(ProjectTask t, List<Project> projects) =>
    projects.where((p) => p.tasks.any((x) => identical(x, t) || x.id == t.id)).firstOrNull;

List<ChainItem> _itemsOfAction(ScheduleBlock b, TaskAction a,
    {Project? project, ProjectTask? task, Activity? activity}) {
  if (a.done) return const [];
  final open = a.checklist.where((c) => !c.done).toList();
  if (open.isEmpty) {
    return [ChainItem(kind: ChainKind.action, block: b, project: project, task: task, action: a, activity: activity)];
  }
  return [
    for (var i = 0; i < open.length; i++)
      ChainItem(
        kind: ChainKind.step,
        block: b,
        project: project,
        task: task,
        action: a,
        step: open[i],
        activity: activity,
        index: i + 1,
        total: open.length,
      ),
  ];
}

/// Écrans d'un bloc, dans l'ordre où on les enchaîne.
List<ChainItem> chainItemsOf(
  ScheduleBlock b, {
  required List<Project> projects,
  required List<Activity> activities,
  required List<HabitHit> hits,
  required DateTime now,
  int dayStartMin = kDefaultDayStartMin,
}) {
  final task = _taskOf(b, projects);
  if (task != null) {
    final project = _projectOfTask(task, projects);
    if (task.interventionRole == 'session' && task.interventionId != null) {
      return [ChainItem(kind: ChainKind.session, block: b, project: project, task: task)];
    }
    final w = blockWork(task, b.actionId);
    final out = <ChainItem>[
      if (w.focus != null) ..._itemsOfAction(b, w.focus!, project: project, task: task),
      for (final a in w.open) ..._itemsOfAction(b, a, project: project, task: task),
    ];
    // Tâche sans aucune action : une carte « bloc » (on y définira l'action) ;
    // toutes les actions faites : le bloc est épuisé, rien à montrer.
    if (out.isEmpty && task.actions.isEmpty) {
      return [ChainItem(kind: ChainKind.block, block: b, project: project, task: task)];
    }
    return out;
  }
  final act = b.activityId == null ? null : activities.where((a) => a.id == b.activityId).firstOrNull;
  if (act != null && act.isHabit) {
    final r = routinesForToday([act], hits, now, dayStartMin: dayStartMin).firstOrNull;
    if (r != null && r.reached) return const [];
    return [ChainItem(kind: ChainKind.routine, block: b, activity: act)];
  }
  if (act != null && b.actionId != null) {
    final own = act.ownActions.where((a) => a.id == b.actionId).firstOrNull;
    if (own != null) {
      final items = _itemsOfAction(b, own, activity: act);
      if (items.isNotEmpty) return items;
    }
  }
  return [ChainItem(kind: ChainKind.block, block: b, activity: act)];
}

const kSyntheticPrefix = '~';

ScheduleBlock _momentBlock(Moment m, String title) => ScheduleBlock(
      id: '$kSyntheticPrefix${m.key}',
      startTime: '${(m.startMin ~/ 60).toString().padLeft(2, '0')}:${(m.startMin % 60).toString().padLeft(2, '0')}',
      durationMin: m.endMin - m.startMin,
      title: title,
      category: 'routine',
    );

ChainItem _anchored(ScheduleBlock holder, RoutineSlot s) =>
    ChainItem(kind: ChainKind.routine, block: holder, activity: s.activity);

/// La file complète : blocs à faire (ni faits, ni sautés, ni supprimés) dont
/// la fin n'est pas passée, du bloc en cours à la fin du programme — et les
/// **routines accrochées** (lot 2 du mode Enchaîner, 2026-10) : en tête, la
/// file du moment courant (restées des moments passés puis routines du
/// moment, ordre de la vue Routines) ; quand la file entre dans un moment
/// suivant (premier bloc qui y commence), les routines de ce moment ; après
/// chaque bloc de travail (tâche ou action), UNE routine « toute la journée »
/// pas encore atteinte, à tour de rôle. Une routine déjà posée en bloc dans
/// le programme n'est pas accrochée en plus. [pushed] / [deferred] /
/// [dismissed] = état du jour de la vue Routines.
List<ChainItem> buildChain({
  required List<ScheduleBlock> blocks,
  required List<Project> projects,
  required List<Activity> activities,
  required List<HabitHit> hits,
  required DateTime now,
  bool anchorRoutines = true,
  Map<String, String> pushed = const {},
  List<String> deferred = const [],
  Set<String> dismissed = const {},
  int dayStartMin = kDefaultDayStartMin,
}) {
  final nowMin = now.hour * 60 + now.minute;
  final live = blocks
      .where((b) => b.status == 'pending' && blockEndMin(b) > nowMin)
      .toList()
    ..sort((a, b) {
      final c = blockStartMin(a).compareTo(blockStartMin(b));
      return c != 0 ? c : a.id.compareTo(b.id);
    });
  List<ChainItem> itemsOf(ScheduleBlock b) =>
      chainItemsOf(b, projects: projects, activities: activities, hits: hits, now: now, dayStartMin: dayStartMin);
  if (!anchorRoutines) return [for (final b in live) ...itemsOf(b)];

  final day = buildRoutineDay(
      activities: activities, hits: hits, now: now, pushed: pushed, deferred: deferred, dismissed: dismissed,
      dayStartMin: dayStartMin);
  // Routines déjà au programme : pas d'accroche en plus.
  final inProgram = {for (final b in live) if (b.activityId != null) b.activityId!};
  final out = <ChainItem>[];
  final cur = day.current;
  final queue = day.queue.where((s) => !inProgram.contains(s.id)).toList();
  // Blocs déjà en cours avant le moment courant (nuit, bloc à cheval) :
  // d'abord, tels quels.
  final early = live.where((b) => blockStartMin(b) < cur.startMin).toList();
  for (final b in early) {
    out.addAll(itemsOf(b));
  }
  final rest = live.where((b) => blockStartMin(b) >= cur.startMin).toList();
  final moments = kTimedMoments.where((m) => m.startMin >= cur.startMin).toList();
  final allday = day.of(kMomentAllDay).where((s) => !s.reached && !dismissed.contains(s.id) && !inProgram.contains(s.id)).toList();
  var alldayIdx = 0;
  void afterWork(ScheduleBlock b) {
    if (allday.isEmpty || (b.taskId == null && b.actionId == null)) return;
    final s = allday[alldayIdx % allday.length];
    alldayIdx++;
    final holder = ScheduleBlock(
        id: '$kSyntheticPrefix${b.id}', startTime: b.startTime, durationMin: b.durationMin, title: 'Après « ${b.title} »', category: 'routine');
    out.add(_anchored(holder, s));
  }

  for (var i = 0; i < moments.length; i++) {
    final m = moments[i];
    final next = i + 1 < moments.length ? moments[i + 1] : null;
    final slots = m.key == cur.key
        ? queue
        : day.of(m.key).where((s) => !s.reached && !dismissed.contains(s.id) && !inProgram.contains(s.id)).toList();
    final holder = _momentBlock(m, 'Routines ${m.of}');
    for (final s in slots) {
      out.add(_anchored(holder, s));
    }
    final inMoment = rest.where((b) {
      final st = blockStartMin(b);
      return st >= m.startMin && (next == null || st < next.startMin);
    });
    for (final b in inMoment) {
      final items = itemsOf(b);
      out.addAll(items);
      if (items.isNotEmpty) afterWork(b);
    }
  }
  return out;
}

/// Ordre d'affichage : les écrans écartés (« pas aujourd'hui », routine déjà
/// comptée) disparaissent ; ceux remis « à plus tard » passent en fin de file,
/// dans l'ordre où on les a reportés.
List<ChainItem> orderChain(List<ChainItem> items,
    {required List<String> deferred, required Set<String> dismissed}) {
  final kept = items.where((i) => !dismissed.contains(i.key)).toList();
  final later = <ChainItem>[];
  final first = <ChainItem>[];
  for (final i in kept) {
    (deferred.contains(i.key) ? later : first).add(i);
  }
  later.sort((a, b) => deferred.indexOf(a.key).compareTo(deferred.indexOf(b.key)));
  return [...first, ...later];
}

/// Fin de la file : fin du dernier bloc.
int? chainEndMin(List<ChainItem> items) =>
    items.isEmpty ? null : items.map((i) => blockEndMin(i.block)).reduce(math.max);

/// « 18:00 », ou « 05:00 demain » quand le dernier bloc passe minuit
/// (Sommeil 23:30 → 05:00 donnait « 29:00 »).
String chainEndLabel(int endMin) {
  final m = endMin % (24 * 60);
  final hm = '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
  return endMin >= 24 * 60 ? '$hm demain' : hm;
}

/// Dépassement d'un bloc, arrondi au quart d'heure supérieur (0 = à l'heure).
int overrunMin(ScheduleBlock b, int nowMin) {
  final over = nowMin - blockEndMin(b);
  return over <= 0 ? 0 : ((over + 14) ~/ 15) * 15;
}

/// « Décaler la suite » : les blocs à faire qui commencent à la fin de
/// [after] ou plus tard reculent de [deltaMin] — sauf les rendez-vous agenda,
/// qui ne bougent pas d'ici. Modifie les blocs en place et retourne ceux qui
/// ont changé (à enregistrer).
List<ScheduleBlock> shiftFollowing(List<ScheduleBlock> blocks, ScheduleBlock after, int deltaMin) {
  if (deltaMin <= 0) return const [];
  final from = blockEndMin(after);
  final changed = <ScheduleBlock>[];
  for (final b in blocks) {
    if (b.id == after.id || b.status != 'pending' || b.gcalEventId != null) continue;
    final start = blockStartMin(b);
    if (start < from) continue;
    // Plafond = minuit moins la durée, mais jamais en arrière : un bloc qui
    // passe déjà minuit (Sommeil 23:30 → 05:00) reste où il est.
    final next = math.min(start + deltaMin, 24 * 60 - b.durationMin);
    if (next <= start) continue;
    b.startTime = '${(next ~/ 60).toString().padLeft(2, '0')}:${(next % 60).toString().padLeft(2, '0')}';
    changed.add(b);
  }
  return changed;
}

/// Minutes de chrono passées sur [block] depuis [since] (sessions qui le
/// servent, bornées à maintenant).
int chainMinutesOn(ScheduleBlock block, List<Session> sessions, DateTime since, DateTime now,
    bool Function(Session, ScheduleBlock) matches) {
  var total = 0;
  for (final s in sessions) {
    if (s.deleted || s.startAt.isBefore(since) || !matches(s, block)) continue;
    total += (s.endAt ?? now).difference(s.startAt).inMinutes;
  }
  return total;
}
