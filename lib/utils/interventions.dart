import 'package:productivitwo_v1/models.dart';

// Brief « Projets opérationnel » (2026-10), chantier 2.1 : lecture des
// INTERVENTIONS existantes sans nouveau modèle. Une intervention = le groupe
// de tâches d'un même `groupLabel` autour d'un jalon (🎯 / 🏁 / isMilestone),
// avec sa préparation (titre « 📝 … ») et sa clôture (titre « ✅ … »).
// Logique pure, partagée web / mobile ; le modèle natif (2.2) la remplacera.

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
  const Intervention({
    required this.project,
    required this.groupLabel,
    required this.milestone,
    this.prep,
    this.closure,
  });

  DateTime get date => _day(milestone.endDate ?? milestone.startDate);

  /// Créneau « 13h15–15h00 » lu dans les actions du jalon, son titre, puis la
  /// description du projet (« Lundi 13h15–15h00, CM1-CM2 »). Null si absent.
  String? get timeRange {
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

  bool get isDone =>
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
  for (final m in live.where(isMilestoneTask)) {
    final g = (m.groupLabel ?? '').trim();
    final siblings = g.isEmpty
        ? const <ProjectTask>[]
        : live.where((t) => t.id != m.id && (t.groupLabel ?? '').trim() == g).toList();
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
