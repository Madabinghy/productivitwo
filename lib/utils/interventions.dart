import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/today_logic.dart' show blockStartMin, blockEndMin;

// Brief « Projets opérationnel » (2026-10), chantiers 2.1 / 2.2 : lecture des
// INTERVENTIONS d'un projet. Source native d'abord (`Project.interventions`
// + tâches taguées `interventionId` / `interventionRole`, posées par le
// serveur) ; repli sur la convention historique pour les tâches non migrées :
// un jalon (🎯 / 🏁 / isMilestone) + préparation « 📝 … » + clôture « ✅ … »
// de même `groupLabel`. Logique pure, partagée web / mobile.

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

bool _startsWithAny(String s, List<String> prefixes) {
  final t = s.trimLeft();
  return prefixes.any(t.startsWith);
}

bool isMilestoneTask(ProjectTask t) => t.isMilestone || _startsWithAny(t.title, ['🎯', '🏁']);
bool isPrepTask(ProjectTask t) => _startsWithAny(t.title, ['📝']);
bool isClosureTask(ProjectTask t) => _startsWithAny(t.title, ['✅']);

/// Action d'impression : contexte @impression ou verbe « Imprimer ».
bool isPrintAction(TaskAction a) =>
    a.allContexts.any((c) => c.toLowerCase() == '@impression') ||
    a.title.trimLeft().toLowerCase().startsWith('imprimer');

/// Titre sans l'émoji de tête ni le tiret de séparation (« 🎯 Lun 5 oct — X » → « Lun 5 oct — X »).
String stripLeadEmoji(String title) =>
    title.replaceFirst(RegExp(r'^\s*(📝|🎯|🏁|✅|✍️)\s*'), '').trim();

enum PrepState { none, todo, readyToPrint, ready, done }

enum ClosureState { none, todo, done }

class Intervention {
  final Project project;
  final String? groupLabel;
  final ProjectTask milestone;
  final ProjectTask? prep;
  final ProjectTask? closure;
  /// Objet natif quand il existe (date, créneau, lieu, bilan font foi).
  final ProjectIntervention? native;
  const Intervention({
    required this.project,
    required this.groupLabel,
    required this.milestone,
    this.prep,
    this.closure,
    this.native,
  });

  String get title => native?.title ?? groupLabel ?? stripLeadEmoji(milestone.title);

  DateTime get date => native != null ? _day(native!.date) : _day(milestone.endDate ?? milestone.startDate);

  /// Créneau « 13h15–15h00 » : celui de l'objet natif, sinon lu dans les
  /// actions du jalon, son titre, puis la description du projet. Null si absent.
  String? get timeRange {
    final n = native;
    if (n != null && n.startTime.isNotEmpty && n.endTime.isNotEmpty) {
      String fr(String hm) {
        final p = hm.split(':');
        return p.length == 2 ? '${int.tryParse(p[0]) ?? p[0]}h${p[1]}' : hm;
      }
      return '${fr(n.startTime)}–${fr(n.endTime)}';
    }
    final re = RegExp(r'(\d{1,2}\s?h\s?\d{0,2})\s*(?:–|-|—|à)\s*(\d{1,2}\s?h\s?\d{0,2})');
    for (final s in [
      ...milestone.actions.map((a) => a.title),
      milestone.title,
      project.description ?? '',
    ]) {
      final m = re.firstMatch(s);
      if (m != null) {
        String fix(String x) {
          final y = x.replaceAll(' ', '');
          return y.endsWith('h') ? '${y}00' : y;
        }
        return '${fix(m.group(1)!)}–${fix(m.group(2)!)}';
      }
    }
    return null;
  }

  bool get isCancelled => native?.status == 'cancelled' || milestone.status == 'skipped';

  bool get isDone =>
      native?.status == 'done' ||
      milestone.status == 'done' ||
      (milestone.actions.isNotEmpty && milestone.actions.every((a) => a.done));

  int get prepOpen => prep?.actions.where((a) => !a.done).length ?? 0;
  int get prepTotal => prep?.actions.length ?? 0;

  PrepState get prepState {
    final p = prep;
    if (p == null) return PrepState.none;
    if (p.status == 'done') return PrepState.done;
    if (p.actions.isEmpty) return p.status == 'done' ? PrepState.done : PrepState.todo;
    if (p.actions.every((a) => a.done)) return PrepState.done;
    final nonPrint = p.actions.where((a) => !isPrintAction(a));
    if (nonPrint.isNotEmpty && nonPrint.every((a) => a.done)) {
      return p.actions.any(isPrintAction) ? PrepState.readyToPrint : PrepState.ready;
    }
    return PrepState.todo;
  }

  int get closureOpen => closure?.actions.where((a) => !a.done).length ?? 0;

  ClosureState get closureState {
    final c = closure;
    if (c == null) return ClosureState.none;
    if (c.status == 'done' || (c.actions.isNotEmpty && c.actions.every((a) => a.done))) {
      return ClosureState.done;
    }
    return ClosureState.todo;
  }
}

/// Toutes les interventions d'un projet (un jalon = une intervention), triées
/// par date. Les tâches annulées (`skipped`) sont ignorées ; une préparation
/// ou clôture sans jalon dans son groupe n'est pas une intervention.
List<Intervention> interventionsOf(Project p) {
  final live = p.tasks.where((t) => t.status != 'skipped').toList();
  final out = <Intervention>[];
  // 1) Natives : une par objet (hors annulées), tâches retrouvées par rôle.
  final nativeTaskIds = <String>{};
  for (final n in p.interventions) {
    final mine = p.tasks.where((t) => t.interventionId == n.id).toList();
    nativeTaskIds.addAll(mine.map((t) => t.id));
    if (n.status == 'cancelled') continue;
    final session = mine.where((t) => t.interventionRole == 'session').firstOrNull ??
        mine.where(isMilestoneTask).firstOrNull;
    if (session == null) continue;
    out.add(Intervention(
      project: p,
      groupLabel: n.title,
      milestone: session,
      prep: mine.where((t) => t.interventionRole == 'prep').firstOrNull,
      closure: mine.where((t) => t.interventionRole == 'closure').firstOrNull,
      native: n,
    ));
  }
  // 2) Convention historique pour le reste (tâches non migrées).
  for (final m in live.where((t) => isMilestoneTask(t) && !nativeTaskIds.contains(t.id))) {
    final g = (m.groupLabel ?? '').trim();
    final siblings = g.isEmpty
        ? const <ProjectTask>[]
        : live
            .where((t) =>
                t.id != m.id && !nativeTaskIds.contains(t.id) && (t.groupLabel ?? '').trim() == g)
            .toList();
    out.add(Intervention(
      project: p,
      groupLabel: g.isEmpty ? null : g,
      milestone: m,
      prep: siblings.where(isPrepTask).firstOrNull,
      closure: siblings.where(isClosureTask).firstOrNull,
    ));
  }
  out.sort((a, b) => a.date.compareTo(b.date));
  return out;
}

/// Prochaine intervention non faite (la plus ancienne : un jalon passé non
/// coché reste « prochain » — il est en retard, pas oublié).
Intervention? nextInterventionOf(Project p, DateTime today) =>
    interventionsOf(p).where((i) => !i.isDone).firstOrNull;

/// Dernière intervention passée (faite, ou datée avant aujourd'hui) qui
/// précède [next] — c'est sa clôture qu'on surveille.
Intervention? previousInterventionOf(Project p, DateTime today, {Intervention? next}) {
  final d = _day(today);
  final all = interventionsOf(p);
  final before = all.where((i) =>
      i.milestone.id != next?.milestone.id &&
      (i.isDone || i.date.isBefore(d)) &&
      (next == null || !i.date.isAfter(next.date)));
  return before.lastOrNull;
}

class ProjectRadar {
  final Project project;
  final Intervention? next;
  final Intervention? previous;
  const ProjectRadar(this.project, this.next, this.previous);

  /// Jours jusqu'au prochain jalon (négatif = en retard) ; null sans jalon.
  int? daysTo(DateTime today) => next == null ? null : next!.date.difference(_day(today)).inDays;

  /// « Replié par défaut » : pas de jalon à 14 jours.
  bool isQuiet(DateTime today, {int horizonDays = 14}) {
    final d = daysTo(today);
    return d == null || d > horizonDays;
  }
}

/// Radar de la semaine : un `ProjectRadar` par projet vivant (actif, non en
/// pause ; les dossiers sont exclus — ils regroupent), trié par date du
/// prochain jalon, les projets sans jalon en dernier.
List<ProjectRadar> weekRadar(List<Project> projects, DateTime today) {
  final hasChildren = {for (final p in projects) if (p.parentProjectId != null) p.parentProjectId!};
  final out = <ProjectRadar>[];
  for (final p in projects) {
    if (p.status != 'active' || p.paused) continue;
    if (p.tasks.isEmpty && hasChildren.contains(p.id)) continue;
    final next = nextInterventionOf(p, today);
    final prev = previousInterventionOf(p, today, next: next);
    if (next == null && prev == null) continue;
    out.add(ProjectRadar(p, next, prev));
  }
  out.sort((a, b) {
    if (a.next == null) return b.next == null ? 0 : 1;
    if (b.next == null) return -1;
    return a.next!.date.compareTo(b.next!.date);
  });
  return out;
}

/// Un miroir Google Agenda posé le jour d'une séance native du même créneau
/// EST cette séance (2026-10) : le bloc reçoit, en mémoire, le projet et la
/// tâche 🎯 de l'intervention (▶, écran séance, déroulé cochable, temps
/// attribué). Rien n'est stocké : un événement récurrent change d'id à chaque
/// occurrence, l'appariement se refait à chaque chargement. Ne touche que les
/// miroirs sans tâche ; en cas de plusieurs séances, le plus grand recouvrement
/// gagne (15 min au moins). Retourne le nombre de blocs reliés.
int linkMirrorsToSessions(Iterable<ScheduleBlock> blocks, Iterable<Project> projects, DateTime day) {
  final d0 = DateTime(day.year, day.month, day.day);
  int toMin(String hm) {
    final p = hm.split(':');
    if (p.length != 2) return 0;
    return (int.tryParse(p[0]) ?? 0) * 60 + (int.tryParse(p[1]) ?? 0);
  }
  final candidates = <({Project p, ProjectIntervention i, ProjectTask t, int s, int e})>[];
  for (final p in projects) {
    if (p.status != 'active' || p.paused) continue;
    for (final i in p.interventions) {
      if (i.status == 'cancelled') continue;
      if (DateTime(i.date.year, i.date.month, i.date.day) != d0) continue;
      final t = p.tasks
          .where((t) => t.interventionId == i.id && t.interventionRole == 'session')
          .firstOrNull;
      if (t == null) continue;
      candidates.add((p: p, i: i, t: t, s: toMin(i.startTime), e: toMin(i.endTime)));
    }
  }
  if (candidates.isEmpty) return 0;
  var n = 0;
  for (final b in blocks) {
    if (b.gcalEventId == null || b.taskId != null || b.status == 'deleted') continue;
    final bs = blockStartMin(b), be = blockEndMin(b);
    ({Project p, ProjectIntervention i, ProjectTask t, int s, int e})? best;
    var bestOverlap = 0;
    for (final c in candidates) {
      final ov = (be < c.e ? be : c.e) - (bs > c.s ? bs : c.s);
      if (ov >= 15 && ov > bestOverlap) {
        best = c;
        bestOverlap = ov;
      }
    }
    if (best == null) continue;
    b.projectId = best.p.id;
    b.taskId = best.t.id;
    n++;
  }
  return n;
}
