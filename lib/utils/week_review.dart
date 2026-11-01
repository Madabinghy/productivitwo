import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/engagement_stats.dart' show ymdOf;
import 'package:productivitwo_v1/utils/lived_day.dart' show livedDate;

/// Revue du dimanche (maquette validée 2026-11-01 « Revue du dimanche ») :
/// regarder la semaine qui finit, trancher ce qui a coûté, poser la suivante.
/// Rien de neuf à saisir : la revue elle-même est gardée dans
/// `data/meta.weekReviews.<lundi>` {at, intention, decisions}.

/// Carte d'entrée : du samedi 18 h au lundi midi (journée vécue).
bool reviewWindowOpen(DateTime now, int dayStartMin) {
  final d = livedDate(now, dayStartMin);
  if (d.weekday == DateTime.saturday) return now.hour >= 18;
  if (d.weekday == DateTime.sunday) return true;
  if (d.weekday == DateTime.monday) return now.hour < 12;
  return false;
}

/// Lundi (`YYYY-MM-DD`) de la semaine que la revue regarde : la semaine en
/// cours du samedi au dimanche, la précédente le lundi et les autres jours.
String reviewedMonday(DateTime now, int dayStartMin) {
  final d = livedDate(now, dayStartMin);
  final monday = DateTime(d.year, d.month, d.day - (d.weekday - 1));
  final weekend = d.weekday == DateTime.saturday || d.weekday == DateTime.sunday;
  return ymdOf(weekend ? monday : DateTime(monday.year, monday.month, monday.day - 7));
}

/// Les sept jours (`YYYY-MM-DD`) de la semaine qui commence à [monday].
List<String> weekDays(String monday) {
  final p = monday.split('-').map(int.parse).toList();
  return [for (var i = 0; i < 7; i++) ymdOf(DateTime(p[0], p[1], p[2] + i))];
}

class WeekReview {
  final DateTime at;
  final String intention;
  final List<String> decisions;
  const WeekReview(this.at, {this.intention = '', this.decisions = const []});

  Map<String, dynamic> toJson() => {
        'at': at.toIso8601String(),
        if (intention.trim().isNotEmpty) 'intention': intention.trim(),
        if (decisions.isNotEmpty) 'decisions': decisions,
      };

  static WeekReview? from(Object? raw) {
    if (raw is! Map) return null;
    final at = raw['at'] is String ? DateTime.tryParse(raw['at'] as String) : null;
    if (at == null) return null;
    return WeekReview(at,
        intention: (raw['intention'] as String?) ?? '',
        decisions: (raw['decisions'] as List?)?.map((e) => '$e').toList() ?? const []);
  }
}

Map<String, WeekReview> parseWeekReviews(Object? raw) {
  if (raw is! Map) return const {};
  return {
    for (final e in raw.entries)
      if (WeekReview.from(e.value) != null) e.key.toString(): WeekReview.from(e.value)!,
  };
}

/// La phrase de la semaine en cours (posée par la revue du dimanche d'avant),
/// à rappeler en tête d'Aujourd'hui le lundi.
String? weekIntention(Map<String, WeekReview> reviews, DateTime now, int dayStartMin) {
  final d = livedDate(now, dayStartMin);
  final monday = DateTime(d.year, d.month, d.day - (d.weekday - 1));
  final prev = ymdOf(DateTime(monday.year, monday.month, monday.day - 7));
  final i = reviews[prev]?.intention.trim() ?? '';
  return i.isEmpty ? null : i;
}

/// Un projet et ce qu'il a avancé dans la semaine.
class ProjectWeek {
  final Project project;
  final int actions;
  final int tasks;
  const ProjectWeek(this.project, this.actions, this.tasks);
}

/// Actions cochées et tâches finies (dernière action cochée dans la semaine)
/// par projet vivant, les plus avancés d'abord ; les projets sans rien ensuite.
List<ProjectWeek> projectWeeks(List<Project> projects, List<String> days, int dayStartMin) {
  final set = days.toSet();
  bool inWeek(DateTime? t) => t != null && set.contains(ymdOf(livedDate(t, dayStartMin)));
  final out = <ProjectWeek>[];
  for (final p in projects) {
    if (p.status != 'active') continue;
    if (p.tasks.isEmpty) continue;
    var actions = 0, tasks = 0;
    for (final t in p.tasks) {
      final done = t.actions.where((a) => a.done && inWeek(a.doneAt)).length;
      actions += done;
      if (t.actions.isNotEmpty && t.actions.every((a) => a.done)) {
        final last = t.actions.map((a) => a.doneAt).whereType<DateTime>().fold<DateTime?>(null, (m, x) => m == null || x.isAfter(m) ? x : m);
        if (inWeek(last)) tasks++;
      }
    }
    out.add(ProjectWeek(p, actions, tasks));
  }
  out.sort((a, b) => b.actions.compareTo(a.actions));
  return out;
}

/// Dernière action cochée d'un projet (null = jamais).
DateTime? lastDoneOf(Project p) {
  DateTime? last;
  for (final t in p.tasks) {
    for (final a in t.actions) {
      if (a.done && a.doneAt != null && (last == null || a.doneAt!.isAfter(last))) last = a.doneAt;
    }
  }
  return last;
}

/// Minutes chronométrées par domaine sur la semaine (sessions coupées aux bornes).
Map<String, int> minutesByDomainOf(List<Session> sessions, List<Activity> activities, List<String> days, DateTime now) {
  final p = days.first.split('-').map(int.parse).toList();
  final from = DateTime(p[0], p[1], p[2]);
  final to = from.add(Duration(days: days.length));
  final dom = {for (final a in activities) a.id: a.domainId};
  final out = <String, int>{};
  for (final s in sessions) {
    if (s.deleted) continue;
    final start = s.startAt.isBefore(from) ? from : s.startAt;
    final end0 = s.endAt ?? now;
    final end = end0.isAfter(to) ? to : end0;
    if (!end.isAfter(start)) continue;
    final d = dom[s.activityId];
    if (d == null) continue;
    out[d] = (out[d] ?? 0) + end.difference(start).inMinutes;
  }
  return out;
}

enum ReviewDecisionKind { minimum, stalledProject, sleep }

/// Une chose à trancher à l'étape 3.
class ReviewDecision {
  final ReviewDecisionKind kind;
  final String title;
  final String detail;
  final String? activityId;
  final int? suggestedMin;
  final Project? project;
  final int? plannedBed; // horloge autour de minuit
  const ReviewDecision(this.kind, this.title, this.detail, {this.activityId, this.suggestedMin, this.project, this.plannedBed});
}

/// Projets vivants sans action cochée depuis [days] jours (au moins une
/// action ouverte), les plus endormis d'abord.
List<(Project, int)> stalledProjects(List<Project> projects, DateTime now, {int days = 10}) {
  final out = <(Project, int)>[];
  for (final p in projects) {
    if (p.status != 'active' || p.paused || p.tasks.isEmpty) continue;
    if (!p.tasks.any((t) => t.actions.any((a) => !a.done))) continue;
    final last = lastDoneOf(p);
    final idle = last == null ? days : now.difference(last).inDays;
    if (idle >= days) out.add((p, idle));
  }
  out.sort((a, b) => b.$2.compareTo(a.$2));
  return out;
}
