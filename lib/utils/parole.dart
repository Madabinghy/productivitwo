import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/engagement_stats.dart' show ymdOf;

/// Parole tenue (maquette validée 2026-10-31) : la veille, on vise au moins
/// [kParoleMin] actions pour le lendemain ; le lendemain, toutes faites avant
/// la bascule = une journée de parole tenue.
///
/// Anti-triche : seule compte une action visée AVANT le début de son jour
/// (`TaskAction.focusSetAt`) ; la parole d'un jour est GELÉE dans
/// `data/meta.paroles` (au début du jour par l'app, ou au « Donner ma parole »
/// de la Planification) — une action déplacée ensuite à un autre jour reste
/// dans la parole et la journée ne compte pas.
const kParoleMin = 3;
const kParoleTiers = [5, 20, 50];

class ParoleDay {
  final String ymd;
  final List<String> ids;
  final DateTime? givenAt;
  const ParoleDay(this.ymd, this.ids, {this.givenAt});

  Map<String, dynamic> toJson() => {'ids': ids, if (givenAt != null) 'givenAt': givenAt!.toIso8601String()};

  static ParoleDay? from(String ymd, Object? raw) {
    if (raw is! Map) return null;
    final ids = (raw['ids'] as List?)?.map((e) => e.toString()).where((e) => e.isNotEmpty).toList() ?? const <String>[];
    if (ids.isEmpty) return null;
    final g = raw['givenAt'];
    return ParoleDay(ymd, ids, givenAt: g is String ? DateTime.tryParse(g) : null);
  }
}

Map<String, ParoleDay> parseParoles(Object? raw) {
  if (raw is! Map) return const {};
  final out = <String, ParoleDay>{};
  for (final e in raw.entries) {
    final ymd = e.key.toString();
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(ymd)) continue;
    final d = ParoleDay.from(ymd, e.value);
    if (d != null) out[ymd] = d;
  }
  return out;
}

Map<String, dynamic> parolesToJson(Map<String, ParoleDay> p) => {for (final e in p.entries) e.key: e.value.toJson()};

/// Une action avec son porteur, pour l'affichage.
class ParoleAction {
  final TaskAction action;
  final Project? project;
  final ProjectTask? task;
  final Activity? activity;
  const ParoleAction(this.action, {this.project, this.task, this.activity});
  String get context => project != null ? '${project!.title} › ${task?.title ?? ''}' : (activity?.name ?? '');
}

/// Toutes les actions (projets vivants + actions propres des activités), par id.
Map<String, ParoleAction> paroleIndex(List<Project> projects, List<Activity> activities) {
  final out = <String, ParoleAction>{};
  for (final p in projects) {
    for (final t in p.tasks) {
      for (final a in t.actions) {
        out[a.id] = ParoleAction(a, project: p, task: t);
      }
    }
  }
  for (final act in activities) {
    if (act.deleted) continue;
    for (final a in act.ownActions) {
      out[a.id] = ParoleAction(a, activity: act);
    }
  }
  return out;
}

DateTime _dayOf(String ymd) {
  final p = ymd.split('-').map(int.parse).toList();
  return DateTime(p[0], p[1], p[2]);
}

/// Début du jour vécu [ymd] (minuit + bascule).
DateTime paroleDayStart(String ymd, int dayStartMin) => _dayOf(ymd).add(Duration(minutes: dayStartMin));

/// Actions visées pour [ymd] posées avant le début de ce jour vécu.
List<String> paroleCandidates(Map<String, ParoleAction> index, String ymd, int dayStartMin) {
  final start = paroleDayStart(ymd, dayStartMin);
  return [
    for (final e in index.entries)
      if (e.value.action.focusDate != null &&
          ymdOf(e.value.action.focusDate!) == ymd &&
          e.value.action.focusSetAt != null &&
          e.value.action.focusSetAt!.isBefore(start))
        e.key,
  ];
}

/// Gèle la parole de [ymd] : union de ce qui est déjà gelé et des candidates.
/// Rien à geler (aucune candidate, rien d'existant) → la map reste telle quelle.
Map<String, ParoleDay> freezeParole(Map<String, ParoleDay> paroles, String ymd, List<String> candidates, {DateTime? givenAt}) {
  final cur = paroles[ymd];
  final ids = <String>{...?cur?.ids, ...candidates}.toList();
  if (ids.isEmpty) return paroles;
  if (cur != null && ids.length == cur.ids.length && givenAt == null) return paroles;
  return {...paroles, ymd: ParoleDay(ymd, ids, givenAt: cur?.givenAt ?? givenAt)};
}

class ParoleOutcome {
  final String ymd;
  final int total;
  final int done;
  const ParoleOutcome(this.ymd, this.total, this.done);
  bool get counts => total >= kParoleMin;
  bool get held => counts && done == total;
  int get left => total - done;
}

/// Bilan d'un jour : faite = cochée avant la fin du jour vécu (une action
/// supprimée ou introuvable n'est pas faite).
ParoleOutcome paroleOutcome(ParoleDay day, Map<String, ParoleAction> index, int dayStartMin) {
  final end = paroleDayStart(day.ymd, dayStartMin).add(const Duration(days: 1));
  var done = 0;
  for (final id in day.ids) {
    final a = index[id]?.action;
    if (a == null || !a.done) continue;
    if (a.doneAt != null && !a.doneAt!.isBefore(end)) continue;
    done++;
  }
  return ParoleOutcome(day.ymd, day.ids.length, done);
}

class ParoleStats {
  final List<ParoleOutcome> closed; // jours clos où une parole (≥ 3) a été donnée, chronologique
  final List<String> heldYmds;
  final int bestRun;
  const ParoleStats(this.closed, this.heldYmds, this.bestRun);
  int get held => heldYmds.length;
  int get given => closed.length;
}

/// Jours clos (avant [todayYmd]) : journées tenues et record d'affilée
/// (jours de parole tenue consécutifs au calendrier).
ParoleStats paroleStats(Map<String, ParoleDay> paroles, Map<String, ParoleAction> index, int dayStartMin, String todayYmd) {
  final closed = [
    for (final d in paroles.values)
      if (d.ymd.compareTo(todayYmd) < 0) paroleOutcome(d, index, dayStartMin),
  ].where((o) => o.counts).toList()
    ..sort((a, b) => a.ymd.compareTo(b.ymd));
  final held = [for (final o in closed) if (o.held) o.ymd];
  var best = 0, run = 0;
  DateTime? prev;
  for (final y in held) {
    final d = _dayOf(y);
    run = (prev != null && d.difference(prev).inDays == 1) ? run + 1 : 1;
    if (run > best) best = run;
    prev = d;
  }
  return ParoleStats(closed, held, best);
}

/// La parole du jour en cours : la gelée si elle existe, sinon les candidates
/// (avant le premier gel de l'app).
ParoleDay? paroleOfDay(Map<String, ParoleDay> paroles, Map<String, ParoleAction> index, String ymd, int dayStartMin) {
  final frozen = freezeParole(paroles, ymd, paroleCandidates(index, ymd, dayStartMin));
  return frozen[ymd];
}
