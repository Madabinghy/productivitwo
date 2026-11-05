import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/engagement_stats.dart' show mondayOf, ymdOf;
import 'package:productivitwo_v1/utils/objective_progress.dart' show computeObjectiveProgress;
import 'package:productivitwo_v1/utils/objective_trajectory.dart' show expectedMetricAt, objectiveStart;

/// Saisons, refonte 2026-11-04 (maquette validée « Saisons et objectifs ») : une
/// saison = la PÉRIODE DE TES OBJECTIFS. On pose le cap au début (durée 4 · 6 ·
/// 8 · 12 semaines, objectifs visés et leur cible à la fin), chaque tuile
/// d'Organisation montre la cible de la saison sur son graphique, le bilan de
/// fin se lit objectif par objectif (Garder · Ajuster · Laisser). Plus de
/// chasses de badges : les anciennes saisons (format `hunts`) sont relues mais
/// ignorées. Stockage `data/meta.seasons` (liste, la dernière peut être en cours).
/// Le résultat d'une saison close est figé au bilan (`held` / `total`) : c'est
/// lui que compte le badge « Saisons » (le moteur des badges n'a pas les objectifs).
const kSeasonWeeks = 6;
const kSeasonDurations = [4, 6, 8, 12];
const kSeasonMaxGoals = 5;
const kSeasonTiers = [1, 4, 8];
const kSeasonsKept = 40;
/// Sur la trajectoire : rythme hebdo ≥ 85 % ; métrique à moins de 10 % de l'écart visé.
const kSeasonRhythmOk = 0.85;
const kSeasonMetricTolerance = 0.10;

enum SeasonGoalKind { metric, rhythm }

enum SeasonDecision { keep, adjust, drop }

class SeasonGoal {
  final String objectiveId;
  final String name; // titre de l'objectif à l'ouverture (bilan même s'il disparaît)
  final SeasonGoalKind kind;
  /// Métrique : valeur au départ de la saison (dernier relevé, sinon départ de l'objectif) et cible à la fin.
  final double? from;
  final double? target;
  final String? unit;
  final SeasonDecision? decision;
  const SeasonGoal({required this.objectiveId, this.name = '', this.kind = SeasonGoalKind.rhythm, this.from, this.target, this.unit, this.decision});

  Map<String, dynamic> toJson() => {
        'objectiveId': objectiveId,
        if (name.isNotEmpty) 'name': name,
        'kind': kind.name,
        if (from != null) 'from': from,
        if (target != null) 'target': target,
        if (unit != null && unit!.isNotEmpty) 'unit': unit,
        if (decision != null) 'decision': decision!.name,
      };

  static SeasonGoal? fromJson(dynamic j) {
    if (j is! Map || j['objectiveId'] is! String) return null;
    return SeasonGoal(
      objectiveId: j['objectiveId'] as String,
      name: (j['name'] ?? '').toString(),
      kind: j['kind'] == 'metric' ? SeasonGoalKind.metric : SeasonGoalKind.rhythm,
      from: (j['from'] as num?)?.toDouble(),
      target: (j['target'] as num?)?.toDouble(),
      unit: j['unit'] as String?,
      decision: SeasonDecision.values.where((d) => d.name == j['decision']).firstOrNull,
    );
  }

  SeasonGoal copyWith({double? target, SeasonDecision? decision}) =>
      SeasonGoal(objectiveId: objectiveId, name: name, kind: kind, from: from, target: target ?? this.target, unit: unit, decision: decision ?? this.decision);
}

class Season {
  final int n;
  final String start; // YYYY-MM-DD, jour d'ouverture
  final String end; // YYYY-MM-DD, un dimanche, inclus
  final List<SeasonGoal> goals;
  final bool bilanSeen;
  /// Figé au bilan : objectifs tenus sur le total.
  final int? held;
  final int? total;
  /// Ancienne saison (chasses de badges) : relue, jamais en cours.
  final bool legacy;
  const Season({required this.n, required this.start, required this.end, this.goals = const [], this.bilanSeen = false, this.held, this.total, this.legacy = false});

  Map<String, dynamic> toJson() => {
        'n': n,
        'start': start,
        'end': end,
        if (!legacy) 'v': 2,
        'goals': [for (final g in goals) g.toJson()],
        if (bilanSeen) 'bilanSeen': true,
        if (held != null) 'held': held,
        if (total != null) 'total': total,
      };

  static Season? fromJson(dynamic j) {
    if (j is! Map) return null;
    final s = j['start'], e = j['end'];
    if (s is! String || e is! String || DateTime.tryParse(s) == null || DateTime.tryParse(e) == null) return null;
    final goals = j['goals'] is List ? [for (final x in j['goals'] as List) if (SeasonGoal.fromJson(x) case final g?) g] : <SeasonGoal>[];
    return Season(
      n: (j['n'] as num?)?.toInt() ?? 1,
      start: s,
      end: e,
      goals: goals,
      bilanSeen: j['bilanSeen'] == true,
      held: (j['held'] as num?)?.toInt(),
      total: (j['total'] as num?)?.toInt(),
      legacy: j['v'] != 2,
    );
  }

  Season copyWith({List<SeasonGoal>? goals, bool? bilanSeen, int? held, int? total}) => Season(
      n: n, start: start, end: end, goals: goals ?? this.goals, bilanSeen: bilanSeen ?? this.bilanSeen, held: held ?? this.held, total: total ?? this.total, legacy: legacy);

  bool isOpenOn(String ymd) => !legacy && start.compareTo(ymd) <= 0 && end.compareTo(ymd) >= 0;
  bool isOverOn(String ymd) => end.compareTo(ymd) < 0;
  int get totalDays => DateTime.parse(end).difference(DateTime.parse(start)).inDays + 1;
  int daysLeft(String ymd) => DateTime.parse(end).difference(DateTime.parse(ymd)).inDays.clamp(0, totalDays);
  /// Semaine en cours (1-based), calée sur les lundis à partir de l'ouverture.
  int weekOf(String ymd) => (DateTime.parse(ymd).difference(mondayOf(DateTime.parse(start))).inDays ~/ 7 + 1).clamp(1, weeks);
  int get weeks => (DateTime.parse(end).difference(mondayOf(DateTime.parse(start))).inDays ~/ 7) + 1;
  /// Part du temps écoulé (0..1), aujourd'hui compris.
  double elapsed(String ymd) => ((DateTime.parse(ymd).difference(DateTime.parse(start)).inDays + 1) / totalDays).clamp(0.0, 1.0);
  SeasonGoal? goalOf(String objectiveId) => goals.where((g) => g.objectiveId == objectiveId).firstOrNull;
  /// Réussie : au moins deux tiers des objectifs tenus (2 sur 3).
  bool get won => held != null && total != null && total! > 0 && held! >= seasonHeldNeeded(total!);
}

int seasonHeldNeeded(int total) => total <= 1 ? total : (total * 2 / 3).ceil();

List<Season> parseSeasons(dynamic raw) => raw is List ? [for (final x in raw) if (Season.fromJson(x) case final s?) s] : const [];

/// Fin d'une saison de [weeks] semaines ouverte le [startYmd] : le dimanche de la
/// dernière semaine pleine (ouverte un lundi : ce lundi + 7×weeks − 1 ; sinon à
/// partir du lundi suivant, la semaine entamée en plus).
String seasonEndFor(String startYmd, {int weeks = kSeasonWeeks}) {
  final d = DateTime.parse(startYmd);
  final firstMonday = d.weekday == DateTime.monday ? d : mondayOf(d).add(const Duration(days: 7));
  return ymdOf(DateTime(firstMonday.year, firstMonday.month, firstMonday.day + weeks * 7 - 1));
}

Season? currentSeason(List<Season> seasons, String todayYmd) {
  for (final s in seasons.reversed) {
    if (s.isOpenOn(todayYmd)) return s;
  }
  return null;
}

/// Dernière saison close (nouveau format) dont le bilan n'a pas été vu.
Season? unseenBilan(List<Season> seasons, String todayYmd) {
  for (final s in seasons.reversed) {
    if (s.legacy) continue;
    if (s.isOverOn(todayYmd)) return s.bilanSeen ? null : s;
  }
  return null;
}

/// Ouvre une saison aujourd'hui. Une saison en cours est close d'office à hier
/// (on repose le cap) ; une saison close au bilan pas vu le garde à voir.
List<Season> withSeasonOpened(List<Season> seasons, List<SeasonGoal> goals, String todayYmd, {int weeks = kSeasonWeeks}) {
  final yesterday = ymdOf(DateTime.parse(todayYmd).subtract(const Duration(days: 1)));
  final next = [
    for (final s in seasons)
      s.isOpenOn(todayYmd) ? Season(n: s.n, start: s.start, end: yesterday.compareTo(s.start) < 0 ? s.start : yesterday, goals: s.goals, bilanSeen: true) : s,
    Season(
      n: seasons.isEmpty ? 1 : seasons.map((s) => s.n).reduce((a, b) => a > b ? a : b) + 1,
      start: todayYmd,
      end: seasonEndFor(todayYmd, weeks: weeks),
      goals: goals.take(kSeasonMaxGoals).toList(),
    ),
  ];
  return next.length > kSeasonsKept ? next.sublist(next.length - kSeasonsKept) : next;
}

List<Season> withSeasonReplaced(List<Season> seasons, Season updated) => [for (final s in seasons) s.n == updated.n ? updated : s];

/// Saisons réussies (résultat figé au bilan), de la plus ancienne à la plus récente.
List<Season> wonSeasons(List<Season> seasons) => [for (final s in seasons) if (!s.legacy && s.won) s];

// ── Un objectif dans la saison ───────────────────────────────────────────────

/// Le but posé pour [o] en ouvrant une saison : métrique = dernier relevé (sinon
/// départ) → là où la ligne de l'objectif arrive à [seasonEnd] (sa cible s'il finit
/// avant) ; sinon le rythme hebdo de ses engagements.
SeasonGoal goalFor(StrategicObjective o, {String? seasonEnd}) {
  final m = o.metric;
  if (m == null) return SeasonGoal(objectiveId: o.id, name: o.title, kind: SeasonGoalKind.rhythm);
  final sorted = [...o.readings]..sort((a, b) => a.date.compareTo(b.date));
  final last = sorted.isEmpty ? null : sorted.last.value;
  final target = seasonEnd == null ? m.targetValue : seasonMetricTarget(o, seasonEnd)!;
  return SeasonGoal(objectiveId: o.id, name: o.title, kind: SeasonGoalKind.metric, from: last ?? m.startValue, target: target, unit: m.unit);
}

/// Cible de saison d'un objectif chiffré (retour user 2026-11-05 : 12 livres
/// jusqu'en juin, visés en 4 semaines) : la valeur de sa ligne départ → cible au
/// soir de [seasonEndYmd], arrondie au dixième ; sa cible s'il finit avant.
double? seasonMetricTarget(StrategicObjective o, String seasonEndYmd) {
  final m = o.metric;
  if (m == null) return null;
  final end = o.endDate;
  final seasonEnd = DateTime.parse(seasonEndYmd).add(const Duration(hours: 23, minutes: 59));
  if (end == null || !end.isAfter(seasonEnd)) return m.targetValue;
  final v = expectedMetricAt(m, objectiveStart(o), end, seasonEnd);
  return (v * 10).round() / 10;
}

/// Le but d'une saison tel qu'il doit se lire : une saison ouverte avant le
/// 2026-11-05 a pu garder la cible FINALE d'un objectif qui court au-delà ;
/// elle est ramenée à la ligne de l'objectif à la fin de la saison.
SeasonGoal effectiveSeasonGoal(Season s, SeasonGoal g, StrategicObjective? o) {
  final m = o?.metric;
  if (g.kind != SeasonGoalKind.metric || m == null || g.target == null) return g;
  if ((g.target! - m.targetValue).abs() > 1e-9) return g;
  final t = seasonMetricTarget(o!, s.end);
  return t == null || (t - g.target!).abs() < 1e-9 ? g : g.copyWith(target: t);
}

enum SeasonGoalState { onTrack, behind, reached, missed, none }

class SeasonGoalView {
  final SeasonGoal goal;
  final SeasonGoalState state;
  /// Métrique : dernier relevé dans la saison (sinon départ) et attendu aujourd'hui.
  final double? latest;
  final double? expected;
  /// Rythme : rythme de la semaine (0..1), ou moyenne des semaines (bilan).
  final double? rhythm;
  const SeasonGoalView(this.goal, this.state, {this.latest, this.expected, this.rhythm});

  bool get ok => state == SeasonGoalState.onTrack || state == SeasonGoalState.reached;

  /// « −0,6 kg », « sur la ligne », « 92 % du rythme », « 84,1 / 85 kg ».
  String label({bool closed = false}) {
    final u = goal.unit == null || goal.unit!.isEmpty ? '' : ' ${goal.unit}';
    if (goal.kind == SeasonGoalKind.metric) {
      if (latest == null || goal.target == null) return 'pas de relevé';
      if (closed) return state == SeasonGoalState.reached ? 'atteint · ${seasonNum(latest!)}$u' : '${seasonNum(latest!)} / ${seasonNum(goal.target!)}$u';
      if (state == SeasonGoalState.reached) return 'cible atteinte';
      final d = (latest! - (expected ?? latest!)) * ((goal.target! >= (goal.from ?? goal.target!)) ? 1 : -1);
      if (state == SeasonGoalState.onTrack) return d.abs() < 0.05 ? 'sur la ligne' : '${d > 0 ? '+' : '−'}${seasonNum(d.abs())}$u';
      return '−${seasonNum(d.abs())}$u';
    }
    if (rhythm == null) return 'rien à mesurer';
    return '${(rhythm! * 100).round()} % du rythme';
  }
}

/// « 84,1 », « 85 ».
String seasonNum(double v) => (v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1)).replaceAll('.', ',');

/// Où en est [g] de la saison [s] au jour [todayYmd] (ou à la fin si elle est close).
SeasonGoalView seasonGoalView(
  Season s,
  SeasonGoal g,
  StrategicObjective? o, {
  required String todayYmd,
  List<Activity> activities = const [],
  List<Session> sessions = const [],
  List<HabitHit> hits = const [],
}) {
  g = effectiveSeasonGoal(s, g, o);
  final closed = s.isOverOn(todayYmd);
  final day = closed ? s.end : todayYmd;
  if (g.kind == SeasonGoalKind.metric) {
    final from = g.from, target = g.target;
    if (o == null || from == null || target == null) return SeasonGoalView(g, SeasonGoalState.none);
    final inSeason = o.readings.where((r) => r.date.compareTo(s.start) >= 0 && r.date.compareTo(day) <= 0).toList()..sort((a, b) => a.date.compareTo(b.date));
    final latest = inSeason.isEmpty ? from : inSeason.last.value;
    final up = target >= from;
    final reachedNow = up ? latest >= target : latest <= target;
    final expected = from + (target - from) * s.elapsed(day);
    if (reachedNow) return SeasonGoalView(g, SeasonGoalState.reached, latest: latest, expected: expected);
    if (closed) return SeasonGoalView(g, SeasonGoalState.missed, latest: latest, expected: target);
    final gap = (target - from).abs();
    final behindBy = up ? expected - latest : latest - expected;
    final ok = behindBy <= gap * kSeasonMetricTolerance + 1e-9;
    return SeasonGoalView(g, ok ? SeasonGoalState.onTrack : SeasonGoalState.behind, latest: latest, expected: expected);
  }
  if (o == null) return SeasonGoalView(g, SeasonGoalState.none);
  if (!closed) {
    final now = DateTime.parse(todayYmd).add(const Duration(hours: 23, minutes: 59));
    final p = computeObjectiveProgress(o, activities, sessions, hits, now);
    final r = p.weekPercent;
    if (r == null) return SeasonGoalView(g, SeasonGoalState.none);
    return SeasonGoalView(g, r >= kSeasonRhythmOk ? SeasonGoalState.onTrack : SeasonGoalState.behind, rhythm: r);
  }
  final r = seasonRhythmMean(s, o, activities: activities, sessions: sessions, hits: hits);
  if (r == null) return SeasonGoalView(g, SeasonGoalState.none);
  return SeasonGoalView(g, r >= kSeasonRhythmOk ? SeasonGoalState.reached : SeasonGoalState.missed, rhythm: r);
}

/// Rythme moyen d'un objectif sur les semaines pleines de la saison (chaque semaine
/// mesurée jusqu'à son dimanche, sans ce qui est venu après).
double? seasonRhythmMean(Season s, StrategicObjective o, {List<Activity> activities = const [], List<Session> sessions = const [], List<HabitHit> hits = const []}) {
  final out = seasonRhythmWeeks(s, o, activities: activities, sessions: sessions, hits: hits).whereType<double>().toList();
  return out.isEmpty ? null : out.reduce((a, b) => a + b) / out.length;
}

/// Le rythme de chaque semaine de la saison (null = rien à mesurer), jusqu'à la
/// semaine de [untilYmd] comprise (par défaut toute la saison).
List<double?> seasonRhythmWeeks(Season s, StrategicObjective o,
    {List<Activity> activities = const [], List<Session> sessions = const [], List<HabitHit> hits = const [], String? untilYmd}) {
  final out = <double?>[];
  var monday = mondayOf(DateTime.parse(s.start));
  final last = DateTime.parse(untilYmd != null && untilYmd.compareTo(s.end) < 0 ? untilYmd : s.end);
  while (!monday.isAfter(last)) {
    final lastEnd = DateTime(last.year, last.month, last.day, 23, 59);
    final sundayEnd = DateTime(monday.year, monday.month, monday.day + 6, 23, 59);
    // Semaine en cours : mesurée à ce jour (attendu au prorata), pas au dimanche.
    final sunday = sundayEnd.isAfter(lastEnd) ? lastEnd : sundayEnd;
    final next = DateTime(monday.year, monday.month, monday.day + 7);
    final p = computeObjectiveProgress(
      o,
      activities,
      [for (final x in sessions) if (x.startAt.isBefore(next)) x],
      [for (final h in hits) if (h.ts.isBefore(next)) h],
      sunday,
    );
    out.add(p.weekPercent);
    monday = next;
  }
  return out;
}

/// Toutes les vues d'une saison, dans l'ordre des objectifs posés.
List<SeasonGoalView> seasonViews(
  Season s,
  List<StrategicObjective> objectives, {
  required String todayYmd,
  List<Activity> activities = const [],
  List<Session> sessions = const [],
  List<HabitHit> hits = const [],
}) {
  final byId = {for (final o in objectives) o.id: o};
  return [
    for (final g in s.goals) seasonGoalView(s, g, byId[g.objectiveId], todayYmd: todayYmd, activities: activities, sessions: sessions, hits: hits),
  ];
}

/// « Jusqu'au dim. 14 déc. »
String seasonEndLabel(Season s) {
  const days = ['lun.', 'mar.', 'mer.', 'jeu.', 'ven.', 'sam.', 'dim.'];
  const months = ['janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'];
  final d = DateTime.parse(s.end);
  return '${days[d.weekday - 1]} ${d.day} ${months[d.month - 1]}';
}
