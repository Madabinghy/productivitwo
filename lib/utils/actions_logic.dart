import 'package:collection/collection.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/mode.dart';
import 'package:productivitwo_v1/utils/project_health.dart';

/// Logique pure de l'onglet Actions (refonte web § 5) — testable sans widget.

/// « J'ai… » : 15 min · 1 h · plus. Une action sans estimation passe toujours.
enum TimeBucket { quarter, hour, more }

bool passesContexts(TaskAction a, Set<String> selected) {
  if (selected.isEmpty) return true;
  final ctx = a.allContexts;
  if (ctx.isEmpty) return true;
  return ctx.any(selected.contains);
}

bool passesTime(TaskAction a, TimeBucket? bucket) {
  final est = a.estimatedMin;
  if (bucket == null || est == null) return true;
  return switch (bucket) {
    TimeBucket.quarter => est <= 15,
    TimeBucket.hour => est <= 60,
    TimeBucket.more => est > 60,
  };
}

/// « 15 min » · « 1 h » · « plus d'1 h ».
String timeBucketLabel(TimeBucket b) => switch (b) {
      TimeBucket.quarter => '15 min',
      TimeBucket.hour => '1 h',
      TimeBucket.more => 'plus d\'1 h',
    };

/// Avec « J'ai … » actif, on cherche ce qui rentre dans le creux : les actions
/// estimées d'abord, de la plus courte à la plus longue ; celles sans
/// estimation (qui passent toujours le filtre) après, dans leur ordre
/// d'origine. Tri stable.
List<T> sortedByEstimate<T>(Iterable<T> items, int? Function(T) estimateOf) {
  final indexed = items.indexed.toList();
  indexed.sort((x, y) {
    final ex = estimateOf(x.$2), ey = estimateOf(y.$2);
    if (ex != null && ey != null && ex != ey) return ex.compareTo(ey);
    if (ex == null && ey != null) return 1;
    if (ex != null && ey == null) return -1;
    return x.$1.compareTo(y.$1);
  });
  return [for (final r in indexed) r.$2];
}

/// Quand rien ne passe « J'ai … » : l'action la plus proche du créneau parmi
/// celles qui le ratent — la plus courte au-delà de 15 min / 1 h, la plus
/// longue en deçà pour « plus d'1 h ». null si aucune n'est estimée.
({TaskAction action, int min})? nearestOutsideBucket(Iterable<TaskAction> missed, TimeBucket b) {
  ({TaskAction action, int min})? best;
  for (final a in missed) {
    final est = a.estimatedMin;
    if (est == null || passesTime(a, b)) continue;
    final better = best == null || (b == TimeBucket.more ? est > best.min : est < best.min);
    if (better) best = (action: a, min: est);
  }
  return best;
}

const _kFold = {
  'à': 'a', 'â': 'a', 'ä': 'a', 'á': 'a', 'ã': 'a', 'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
  'î': 'i', 'ï': 'i', 'í': 'i', 'ô': 'o', 'ö': 'o', 'ó': 'o', 'ù': 'u', 'û': 'u', 'ü': 'u', 'ú': 'u',
  'ç': 'c', 'ÿ': 'y', 'ñ': 'n', 'œ': 'oe', 'æ': 'ae', '’': "'",
};

/// Minuscules sans accents, pour la recherche (« Dévis » trouve « devis »).
String foldForSearch(String s) {
  final b = StringBuffer();
  for (final r in s.toLowerCase().runes) {
    final ch = String.fromCharCode(r);
    b.write(_kFold[ch] ?? ch);
  }
  return b.toString();
}

/// Recherche de l'onglet Actions : chaque mot de la requête doit apparaître
/// dans l'un des champs (titre de l'action, tâche, projet, activité). Requête
/// vide = tout passe.
bool matchesQuery(String query, Iterable<String?> fields) {
  final words = foldForSearch(query).split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return true;
  final hay = fields.whereType<String>().map(foldForSearch).join(' \u0000 ');
  return words.every(hay.contains);
}

/// Tâche « Au fil de l'eau » d'un projet : porte les actions posées sans
/// tâche précise (« Prochaine action », tri des captures). Créée au besoin,
/// réactivée si elle avait été close ; sans échéance → triée en dernier.
const String kFlowTaskId = 'gtd-flow';

ProjectTask flowTaskOf(Project p) {
  final existing = p.tasks.where((t) => t.id == kFlowTaskId).firstOrNull;
  if (existing != null) {
    if (existing.status != 'pending') existing.status = 'pending';
    return existing;
  }
  final t = ProjectTask(id: kFlowTaskId, title: 'Au fil de l\'eau', startDate: DateTime.now());
  p.tasks.add(t);
  return t;
}

/// Rattache une action SIMPLE (action propre d'une activité) à un projet, en
/// mémoire : retirée des `ownActions`, ajoutée à [task] (sinon « Au fil de
/// l'eau » du projet). Elle garde titre, détail, contextes, estimation, état
/// et son activité comme lien chrono (`linkedActivityId`). Null si absente.
ProjectTask? attachOwnActionToProject(Activity a, String actionId, Project p, {ProjectTask? task}) {
  final idx = a.ownActions.indexWhere((x) => x.id == actionId);
  if (idx < 0) return null;
  final action = a.ownActions.removeAt(idx);
  action.linkedActivityId ??= a.id;
  final target = task ?? flowTaskOf(p);
  if (target.status != 'pending' && !action.done) target.status = 'pending';
  target.actions.add(action);
  return target;
}

/// Contextes connus : défauts + tous ceux rencontrés sur les actions ouvertes.
List<String> knownContexts(List<Project> projects, List<Activity> activities) {
  final seen = <String>{...kDefaultGtdContexts};
  final extra = <String>[];
  void visit(TaskAction a) {
    for (final c in a.allContexts) {
      if (seen.add(c)) extra.add(c);
    }
  }
  for (final p in projects) {
    for (final t in p.tasks) {
      for (final a in t.actions) {
        if (!a.done) visit(a);
      }
    }
  }
  for (final act in activities) {
    for (final a in act.ownActions) {
      if (!a.done) visit(a);
    }
  }
  extra.sort();
  return [...kDefaultGtdContexts, ...extra];
}

/// `milestone` = par urgence du prochain jalon / séance du projet (brief 2.4 :
/// « j'ai 20 min » → d'abord ce qui sert la séance la plus proche).
enum ActionsSort { dueDate, domain, alpha, milestone }

class ProjectActions {
  final Project project;
  /// Actions ouvertes, prochaine action en tête, puis ordre Gantt.
  final List<({ProjectTask task, TaskAction action})> entries;
  const ProjectActions(this.project, this.entries);
}

/// Un groupe par projet actif non en pause, filtré et trié.
List<ProjectActions> projectActionGroups(
  List<Project> projects, {
  required bool Function(TaskAction) filter,
  /// Filtre sur la tâche porteuse (ex. tâche pas encore commencée) ;
  /// null = toutes.
  bool Function(ProjectTask)? taskFilter,
  /// Filtre sur le couple tâche + action (ex. « En retard » PAR ACTION, via
  /// l'échéance effective) ; null = toutes.
  bool Function(ProjectTask, TaskAction)? entryFilter,
  ActionsSort sort = ActionsSort.dueDate,
  List<String> domainOrder = const [],
  /// Date du prochain jalon / séance d'un projet (tri `milestone`) ; null = aucun.
  DateTime? Function(Project)? urgencyOf,
}) {
  final out = <ProjectActions>[];
  for (final p in projects) {
    if (p.status != 'active' || p.paused) continue;
    final entries = <({ProjectTask task, TaskAction action})>[];
    final next = nextAction(p);
    if (next != null &&
        filter(next.action) &&
        (taskFilter?.call(next.task) ?? true) &&
        (entryFilter?.call(next.task, next.action) ?? true)) {
      entries.add(next);
    }
    for (final t in ganttOrder(p)) {
      if (t.status == 'done' || t.status == 'skipped') continue;
      if (taskFilter != null && !taskFilter(t)) continue;
      for (final a in t.actions) {
        if (a.done || !filter(a)) continue;
        if (entryFilter != null && !entryFilter(t, a)) continue;
        if (next != null && a.id == next.action.id) continue;
        entries.add((task: t, action: a));
      }
    }
    out.add(ProjectActions(p, entries));
  }
  int byDue(Project a, Project b) {
    if (a.endDate == null) return b.endDate == null ? 0 : 1;
    if (b.endDate == null) return -1;
    return a.endDate!.compareTo(b.endDate!);
  }
  out.sort((x, y) {
    final a = x.project, b = y.project;
    switch (sort) {
      case ActionsSort.dueDate:
        return byDue(a, b);
      case ActionsSort.milestone:
        final ua = urgencyOf?.call(a), ub = urgencyOf?.call(b);
        if (ua == null && ub == null) return byDue(a, b);
        if (ua == null) return 1;
        if (ub == null) return -1;
        final c = ua.compareTo(ub);
        return c != 0 ? c : byDue(a, b);
      case ActionsSort.alpha:
        return a.title.toLowerCase().compareTo(b.title.toLowerCase());
      case ActionsSort.domain:
        final ia = domainOrder.indexOf(a.domainId ?? '');
        final ib = domainOrder.indexOf(b.domainId ?? '');
        final ra = ia < 0 ? domainOrder.length : ia;
        final rb = ib < 0 ? domainOrder.length : ib;
        return ra != rb ? ra.compareTo(rb) : byDue(a, b);
    }
  });
  return out;
}

/// Projet racine (client) d'un projet : on remonte `parentProjectId` jusqu'à
/// un projet sans parent connu. Un parent introuvable = le projet est racine.
Project rootProjectOf(Project p, List<Project> all) {
  var cur = p;
  final seen = <String>{p.id};
  while (cur.parentProjectId != null) {
    final parent = all.where((x) => x.id == cur.parentProjectId).firstOrNull;
    if (parent == null || !seen.add(parent.id)) break;
    cur = parent;
  }
  return cur;
}

bool _liveProject(Project p) => p.status == 'active' && !p.paused;

/// « Pour… » : les racines (clients, dossiers) qui ont au moins un projet
/// vivant sous elles (elles comprises), triées par titre.
List<Project> clientRoots(List<Project> all) {
  final roots = <String, Project>{};
  for (final p in all) {
    // Un dossier ne compte que par ses enfants vivants.
    if (!_liveProject(p) || isFolderProject(p, all)) continue;
    final r = rootProjectOf(p, all);
    roots[r.id] = r;
  }
  return roots.values.toList()
    ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
}

/// Entrée « Perso » du filtre « Pour… » : les actions SANS projet (actions
/// propres d'activité). Un client choisi ne montre que ses projets ; sans
/// cette entrée, les actions simples n'auraient plus d'endroit où apparaître
/// filtrées.
const String kPersoClientId = '__perso__';
const String kPersoClientLabel = 'Perso';

/// Filtre « Pour… » : null = tout ; [kPersoClientId] = actions sans projet ;
/// sinon le projet racine (client / dossier) de [p] doit être [clientId].
/// Une action simple n'est « pour » aucun client.
bool inClient(String? clientId, Project? p, List<Project> all) {
  if (clientId == null) return true;
  if (clientId == kPersoClientId) return p == null;
  return p != null && rootProjectOf(p, all).id == clientId;
}

/// Dossier : un projet racine sans tâche dont d'autres projets dépendent —
/// il sert de client, pas de liste d'actions (jamais « Définir la prochaine »).
bool isFolderProject(Project p, List<Project> all) =>
    p.tasks.isEmpty && all.any((x) => x.parentProjectId == p.id);

DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Tâche PAS ENCORE COMMENCÉE (2026-10) : sa date de début est après
/// aujourd'hui. Ses actions sortent de la liste principale d'Actions (mobile et
/// web) et vont dans « À venir » : générées en masse, elles noyaient ce qu'on
/// peut faire maintenant (« Corriger les contrôles » avant de les ramasser).
bool isUpcomingTask(ProjectTask t, DateTime today) =>
    _dayOnly(t.startDate).isAfter(_dayOnly(today));

/// Tâche qui DÉMARRE aujourd'hui : ses actions viennent d'arriver dans la
/// liste (pastille « nouveau », groupe « Arrivées aujourd'hui »).
bool startsToday(ProjectTask t, DateTime today) =>
    _dayOnly(t.startDate) == _dayOnly(today);

/// Actions ouvertes des tâches à venir, par date de début puis ordre Gantt.
List<({Project project, ProjectTask task, TaskAction action})> upcomingActions(
  List<Project> projects, {
  required bool Function(TaskAction) filter,
  required DateTime today,
}) {
  final out = <({Project project, ProjectTask task, TaskAction action})>[];
  for (final p in projects) {
    if (p.status != 'active' || p.paused) continue;
    for (final t in ganttOrder(p)) {
      if (t.status == 'done' || t.status == 'skipped' || !isUpcomingTask(t, today)) continue;
      for (final a in t.actions) {
        if (!a.done && filter(a)) out.add((project: p, task: t, action: a));
      }
    }
  }
  final order = {for (var i = 0; i < out.length; i++) out[i].action.id: i};
  out.sort((x, y) {
    final c = _dayOnly(x.task.startDate).compareTo(_dayOnly(y.task.startDate));
    return c != 0 ? c : order[x.action.id]!.compareTo(order[y.action.id]!);
  });
  return out;
}

/// « dès demain » / « dès jeu. 15 oct. » / « dès le 2 nov. » (au-delà d'une semaine).
String upcomingLabel(DateTime start, DateTime today) {
  const days = ['lun.', 'mar.', 'mer.', 'jeu.', 'ven.', 'sam.', 'dim.'];
  const months = ['janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'];
  final s = _dayOnly(start), t = _dayOnly(today);
  final diff = s.difference(t).inDays;
  if (diff <= 1) return 'dès demain';
  if (diff < 7) return 'dès ${days[s.weekday - 1]} ${s.day} ${months[s.month - 1]}';
  return 'dès le ${s.day} ${months[s.month - 1]}';
}

/// Tâche EN RETARD : ouverte (ni faite ni annulée) et échéance strictement
/// avant le jour de [today]. Règle unique du filtre « En retard » (web), du
/// groupe « En retard » et de la pastille.
bool isOverdueTask(ProjectTask t, DateTime today) {
  if (t.status == 'done' || t.status == 'skipped' || t.endDate == null) return false;
  final d = DateTime(today.year, today.month, today.day);
  final due = DateTime(t.endDate!.year, t.endDate!.month, t.endDate!.day);
  return due.isBefore(d);
}

/// Échéance EFFECTIVE d'une action (2026-10) : la sienne si posée
/// (`TaskAction.dueDate`), sinon celle de sa tâche. Jour seul ; null = aucune.
/// C'est LE lecteur de l'échéance d'une action : ne jamais lire `dueDate` ou
/// `task.endDate` seuls pour décider d'un retard.
DateTime? effectiveDueDate(TaskAction a, ProjectTask? t) {
  final d = a.dueDate ?? t?.endDate;
  return d == null ? null : _dayOnly(d);
}

/// Action EN RETARD : ouverte, dans une tâche ouverte (ni faite ni annulée),
/// dont l'échéance effective est avant [today].
bool isOverdueAction(TaskAction a, ProjectTask? t, DateTime today) {
  if (a.done) return false;
  if (t != null && (t.status == 'done' || t.status == 'skipped')) return false;
  final due = effectiveDueDate(a, t);
  return due != null && due.isBefore(_dayOnly(today));
}

const _kMonthsFr = ['janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'];

/// « 7 oct. » (« 7 oct. 2027 » si l'année diffère de [today]).
String shortDateFr(DateTime d, {DateTime? today}) {
  final y = (today ?? DateTime.now()).year;
  return '${d.day} ${_kMonthsFr[d.month - 1]}${d.year == y ? '' : ' ${d.year}'}';
}

/// Étiquette d'échéance d'une action : « −3 j » (dépassée), « aujourd'hui »,
/// « demain », sinon « éch. 7 oct. ». [due] et [today] au jour.
String actionDueLabel(DateTime due, DateTime today) {
  final d = _dayOnly(due).difference(_dayOnly(today)).inDays;
  if (d < 0) return '−${-d} j';
  if (d == 0) return "aujourd'hui";
  if (d == 1) return 'demain';
  return 'éch. ${shortDateFr(due, today: today)}';
}

/// Actions EN RETARD des projets vivants (`isOverdueAction`). Même règle que
/// le groupe « En retard » d'Actions (mobile et web) — alimente la pastille de
/// l'onglet Actions.
int overdueActionCount(List<Project> projects, DateTime today) {
  var n = 0;
  for (final p in projects) {
    if (p.status != 'active' || p.paused) continue;
    for (final t in p.tasks) {
      n += t.actions.where((a) => isOverdueAction(a, t, today)).length;
    }
  }
  return n;
}

/// Groupe de projets sous un dossier (racine sans tâche) : [folder] null =
/// projet hors dossier, seul dans son groupe.
class FolderGroup {
  final Project? folder;
  final List<Project> projects;
  const FolderGroup(this.folder, this.projects);
}

/// Regroupe [projects] par FAMILLE (projet racine), que la racine soit un
/// dossier ou un projet qui a ses propres tâches (Chérubins, SOF Conseil) :
/// une famille de plusieurs projets donne un groupe dont `folder` est la
/// racine et dont la racine, si elle est listée, vient en tête. Un projet
/// seul dans sa famille reste seul (`folder` null). Ordre d'apparition gardé ;
/// un dossier n'est jamais listé comme projet.
List<FolderGroup> groupByRoot(List<Project> projects, List<Project> all) {
  final order = <String>[];
  final roots = <String, Project>{};
  final members = <String, List<Project>>{};
  for (final p in projects) {
    if (isFolderProject(p, all)) continue;
    final r = rootProjectOf(p, all);
    if (!members.containsKey(r.id)) {
      order.add(r.id);
      roots[r.id] = r;
      members[r.id] = [];
    }
    members[r.id]!.add(p);
  }
  return [
    for (final id in order)
      if (members[id]!.length == 1 && members[id]!.single.id == id)
        FolderGroup(null, members[id]!)
      else
        FolderGroup(roots[id], [
          ...members[id]!.where((p) => p.id == id),
          ...members[id]!.where((p) => p.id != id),
        ]),
  ];
}

/// Regroupe [projects] par dossier en gardant l'ordre d'apparition : le
/// premier projet d'un dossier ouvre son groupe, les suivants s'y rangent.
/// Les dossiers eux-mêmes présents dans [projects] ne sont pas listés (ils
/// sont l'en-tête du groupe) ; un dossier sans enfant listé n'apparaît pas.
List<FolderGroup> groupByFolder(List<Project> projects, List<Project> all) {
  final out = <FolderGroup>[];
  final byFolder = <String, FolderGroup>{};
  for (final p in projects) {
    if (isFolderProject(p, all)) continue;
    final root = rootProjectOf(p, all);
    if (root.id == p.id || !isFolderProject(root, all)) {
      out.add(FolderGroup(null, [p]));
      continue;
    }
    final g = byFolder[root.id];
    if (g != null) {
      g.projects.add(p);
    } else {
      final ng = FolderGroup(root, [p]);
      byFolder[root.id] = ng;
      out.add(ng);
    }
  }
  return out;
}

/// Filtre actif (contexte ou temps) : on ne montre que les projets qui ont au
/// moins une action qui passe — « que puis-je faire @maison ? » va droit à
/// l'essentiel. Les autres sont comptés (lien « Afficher ») au lieu d'être
/// listés vides. Sans filtre, tout reste visible (« Définir la prochaine »).
({List<ProjectActions> shown, int hidden}) visibleProjectGroups(
    List<ProjectActions> groups, {required bool filtering}) {
  if (!filtering) return (shown: groups, hidden: 0);
  final shown = groups.where((g) => g.entries.isNotEmpty).toList();
  return (shown: shown, hidden: groups.length - shown.length);
}

/// « Possible maintenant » : actions ouvertes dont l'activité-temps liée est
/// celle du chrono en cours — lien propre (`TaskAction.linkedActivityId`),
/// lien du projet, ou action simple de cette activité.
List<({TaskAction action, Project? project, ProjectTask? task, Activity? activity})>
    possibleNow(
  List<Project> projects,
  List<Activity> activities,
  String activityId, {
  required bool Function(TaskAction) filter,
}) {
  final out = <({TaskAction action, Project? project, ProjectTask? task, Activity? activity})>[];
  for (final p in projects) {
    if (p.status != 'active' || p.paused) continue;
    for (final t in ganttOrder(p)) {
      if (t.status == 'done' || t.status == 'skipped') continue;
      for (final a in t.actions) {
        if (a.done || !filter(a)) continue;
        final linked = a.linkedActivityId ?? p.linkedActivityId;
        if (linked == activityId) {
          out.add((action: a, project: p, task: t, activity: null));
        }
      }
    }
  }
  for (final act in activities) {
    if (act.deleted || act.id != activityId) continue;
    for (final a in act.ownActions) {
      if (!a.done && filter(a)) {
        out.add((action: a, project: null, task: null, activity: act));
      }
    }
  }
  return out;
}

/// « C'était pour quoi ? » (2026-10) : à l'arrêt d'un chrono qui ne visait
/// aucune action, les actions probables de son activité — celles au programme
/// du jour d'abord, puis par échéance de la tâche ; jamais une tâche à venir.
List<({TaskAction action, Project? project, ProjectTask? task, Activity? activity})>
    stopTargetCandidates(
  List<Project> projects,
  List<Activity> activities,
  String activityId, {
  required DateTime today,
  Set<String> plannedIds = const {},
  int limit = 3,
}) {
  final all = possibleNow(projects, activities, activityId, filter: (_) => true)
      .where((x) => x.task == null || !isUpcomingTask(x.task!, today))
      .toList();
  final order = {for (var i = 0; i < all.length; i++) all[i].action.id: i};
  int rank(({TaskAction action, Project? project, ProjectTask? task, Activity? activity}) x) =>
      plannedIds.contains(x.action.id) ? 0 : 1;
  all.sort((a, b) {
    final r = rank(a).compareTo(rank(b));
    if (r != 0) return r;
    final da = a.task?.endDate, db = b.task?.endDate;
    if (da != null && db != null && da != db) return da.compareTo(db);
    if (da != null && db == null) return -1;
    if (da == null && db != null) return 1;
    return order[a.action.id]!.compareTo(order[b.action.id]!);
  });
  return all.take(limit).toList();
}

/// Actions simples ouvertes (`Activity.ownActions`), par activité.
List<({Activity activity, List<TaskAction> actions})> ownActionGroups(
  List<Activity> activities, {
  required bool Function(TaskAction) filter,
}) =>
    [
      for (final act in activities)
        if (!act.deleted)
          if (act.ownActions.any((a) => !a.done && filter(a)))
            (
              activity: act,
              actions: act.ownActions.where((a) => !a.done && filter(a)).toList(),
            ),
    ];

// ── Action du moment (« une carte, une fiche », lot 2, 2026-10) ──────────────

typedef ActionEntry = ({TaskAction action, Project? project, ProjectTask? task, Activity? activity});

enum ActionMomentKind { running, block, late, today, next, week, rest, short, deep }

class ActionMoment {
  final ActionEntry entry;
  final ActionMomentKind kind;
  final ScheduleBlock? block;
  final DateTime? due;
  const ActionMoment(this.entry, this.kind, {this.block, this.due});
}

/// L'ACTION DU MOMENT parmi les actions ouvertes affichées : celle que vise le
/// chrono en cours, sinon celle du bloc en cours, sinon la plus en retard,
/// sinon la première au programme du jour (ordre des blocs), sinon celle du
/// prochain bloc, sinon la plus proche échéance à 7 jours, sinon la première
/// de la liste (prochaine action du premier projet). Null si rien.
ActionMoment? pickActionMoment(
  List<ActionEntry> entries, {
  required List<ScheduleBlock> blocks,
  required int nowMin,
  required DateTime today,
  String? runningActionId,
  ActionEntry? Function(ScheduleBlock b)? entryForBlock,
  DayMode mode = DayMode.normal,
  String? focusProjectId,
}) {
  if (entries.isEmpty) return null;
  final d = _dayOnly(today);
  ActionEntry? byId(String? id) => id == null ? null : entries.where((e) => e.action.id == id).firstOrNull;
  if (byId(runningActionId) case final e?) return ActionMoment(e, ActionMomentKind.running);
  // Modes et coups (lot 2) : ce qu'on est en train de faire gagne toujours
  // (chrono, bloc en cours) ; sinon Flemme = la plus courte faisable, étapes
  // d'abord ; En forme = la plus longue du projet le plus en retard
  // ([focusProjectId]), sinon la plus longue tout court.
  if (mode == DayMode.low) {
    final current = _currentBlock(blocks, nowMin);
    final cur = current == null ? null : (byId(current.actionId) ?? entryForBlock?.call(current));
    if (cur != null) return ActionMoment(cur, ActionMomentKind.block, block: current);
    final pool = entries.where((e) => passesTime(e.action, TimeBucket.quarter)).toList();
    final list = pool.isEmpty ? entries : pool;
    ActionEntry? best;
    int score(ActionEntry e) => (e.action.checklist.any((c) => !c.done) ? 0 : 1000) + (e.action.estimatedMin ?? 45);
    for (final e in list) {
      if (best == null || score(e) < score(best)) best = e;
    }
    return ActionMoment(best!, ActionMomentKind.short);
  }
  if (mode == DayMode.high) {
    final current = _currentBlock(blocks, nowMin);
    final cur = current == null ? null : (byId(current.actionId) ?? entryForBlock?.call(current));
    if (cur != null) return ActionMoment(cur, ActionMomentKind.block, block: current);
    final inFocus = focusProjectId == null ? const <ActionEntry>[] : entries.where((e) => e.project?.id == focusProjectId).toList();
    final list = inFocus.isEmpty ? entries : inFocus;
    ActionEntry? best;
    for (final e in list) {
      if (best == null || (e.action.estimatedMin ?? 45) > (best.action.estimatedMin ?? 45)) best = e;
    }
    return ActionMoment(best!, ActionMomentKind.deep);
  }

  final live = blocks.where((b) => b.status == 'pending').toList()..sort((a, b) => a.startTime.compareTo(b.startTime));
  ScheduleBlock? current, next;
  for (final b in live) {
    final p = b.startTime.split(':');
    final s = (int.tryParse(p[0]) ?? 0) * 60 + (p.length > 1 ? int.tryParse(p[1]) ?? 0 : 0);
    if (s <= nowMin && nowMin < s + b.durationMin) {
      current ??= b;
    } else if (s > nowMin) {
      next ??= b;
    }
  }
  ActionEntry? ofBlock(ScheduleBlock? b) {
    if (b == null) return null;
    return byId(b.actionId) ?? entryForBlock?.call(b);
  }
  if (ofBlock(current) case final e?) return ActionMoment(e, ActionMomentKind.block, block: current);

  ActionEntry? best;
  DateTime? bestDue;
  for (final e in entries) {
    final due = effectiveDueDate(e.action, e.task);
    if (due == null || !_dayOnly(due).isBefore(d)) continue;
    if (bestDue == null || _dayOnly(due).isBefore(bestDue)) {
      best = e;
      bestDue = _dayOnly(due);
    }
  }
  if (best != null) return ActionMoment(best, ActionMomentKind.late, due: bestDue);

  for (final b in live) {
    final e = byId(b.actionId);
    if (e != null) return ActionMoment(e, ActionMomentKind.today, block: b);
  }
  if (ofBlock(next) case final e?) return ActionMoment(e, ActionMomentKind.next, block: next);

  final limit = d.add(const Duration(days: 7));
  for (final e in entries) {
    final due = effectiveDueDate(e.action, e.task);
    if (due == null || _dayOnly(due).isAfter(limit)) continue;
    if (bestDue == null || _dayOnly(due).isBefore(bestDue)) {
      best = e;
      bestDue = _dayOnly(due);
    }
  }
  if (best != null) return ActionMoment(best, ActionMomentKind.week, due: bestDue);
  return ActionMoment(entries.first, ActionMomentKind.rest);
}

ScheduleBlock? _currentBlock(List<ScheduleBlock> blocks, int nowMin) {
  for (final b in blocks) {
    if (b.status != 'pending') continue;
    final p = b.startTime.split(':');
    final s = (int.tryParse(p[0]) ?? 0) * 60 + (p.length > 1 ? int.tryParse(p[1]) ?? 0 : 0);
    if (s <= nowMin && nowMin < s + b.durationMin) return b;
  }
  return null;
}
