import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/badge_texts.dart';
import 'package:productivitwo_v1/utils/chain_session.dart' show chainRunCounts, kChainTiers;
import 'package:productivitwo_v1/utils/elan_logic.dart';
import 'package:productivitwo_v1/utils/embers.dart';
import 'package:productivitwo_v1/utils/engagement_stats.dart' show ymdOf, mondayOf;
import 'package:productivitwo_v1/utils/lived_day.dart';
import 'package:productivitwo_v1/utils/objective_trajectory.dart';
import 'package:productivitwo_v1/utils/held_weeks.dart';
import 'package:productivitwo_v1/utils/reprise.dart';
import 'package:productivitwo_v1/utils/rest_periods.dart';

/// Badges (lot 1, 2026-10) : catalogue et calcul des paliers depuis les
/// données d'exécution. Logique pure, aucune écriture : un badge est un FAIT
/// recalculé, jamais stocké (rien ne se perd, une série cassée garde son
/// palier). Design : système « Badges Productivitwo » (gabarit, familles,
/// règles de texte). La famille Enchaîner n'a pas encore de donnée source
/// (`measured: false`) : elle compte dans le total, à 0. Discipline se mesure
/// sur les pointages d'élan (`moodMarks`, lot 2, `utils/elan_logic.dart`).

enum BadgeFamily { routines, objectives, days, discipline, chain, actions, time }

String badgeFamilyLabel(BadgeFamily f) => switch (f) {
      BadgeFamily.routines => 'Séries de routine',
      BadgeFamily.objectives => 'Objectifs',
      BadgeFamily.days => 'Journées',
      BadgeFamily.discipline => 'Discipline',
      BadgeFamily.chain => 'Enchaîner',
      BadgeFamily.actions => 'Actions accomplies',
      BadgeFamily.time => 'Temps investi',
    };

const kRoutineTiers = [3, 7, 21, 66, 100];
const kTrajectoryTiers = [4, 8, 12];
const kReadingTiers = [8, 20];
const kActionTiers = [10, 50, 100, 250, 500, 1000, 5000, 10000];
const kTimeTiersHours = [100, 500, 1000];
const kDisciplineTiers = [10, 50, 200];
const kBarometerTiers = [30, 100, 365];
const kDeepWorkTiers = [3, 10, 30];

/// Un badge du catalogue. `tiers` = paliers (un seul = badge simple) ;
/// `subjectId` = routine ou objectif porteur (null = badge global).
class BadgeDef {
  final String id;
  final BadgeFamily family;
  final String name;
  final String symbol; // clé du symbole du gabarit (badge_painter.dart)
  final List<int> tiers;
  final String unit; // « j », « h », « sem. »
  final String unitLong; // « jours », « heures »
  final String? label; // texte du ruban (badge simple ou > 5 paliers)
  final bool measured;
  final String? subjectId;

  const BadgeDef({
    required this.id,
    required this.family,
    required this.name,
    required this.symbol,
    required this.tiers,
    this.unit = '',
    this.unitLong = '',
    this.label,
    this.measured = true,
    this.subjectId,
  });

  int get levels => tiers.length;

  /// À quoi correspond le badge, et comment l'obtenir (`badge_texts.dart`).
  String get what => badgeTexts(id, name: name).what;
  String get how => badgeTexts(id, name: name).how;
}

/// L'état d'un badge pour une personne : paliers atteints, mesure courante,
/// date d'obtention de chaque palier, faits à montrer dans la fiche.
class BadgeState {
  final BadgeDef def;
  final int level;
  final num value;
  final List<DateTime?> tierDates;
  final List<(String, String)> facts;
  /// Graphique d'avancement (bande de cases), null quand rien ne se suit.
  final BadgeTrack? track;

  const BadgeState({
    required this.def,
    required this.level,
    required this.value,
    this.tierDates = const [],
    this.facts = const [],
    this.track,
  });

  BadgeState withTrack(BadgeTrack? t) => BadgeState(def: def, level: level, value: value, tierDates: tierDates, facts: facts, track: t);

  bool get acquired => level > 0;
  bool get complete => level >= def.tiers.length;
  int get paliersTotal => def.tiers.length;
  int get paliersDone => level.clamp(0, def.tiers.length);
  int? get nextTarget => complete ? null : def.tiers[level];

  /// Date du dernier palier obtenu.
  DateTime? get obtained {
    for (var i = level - 1; i >= 0; i--) {
      if (i < tierDates.length && tierDates[i] != null) return tierDates[i];
    }
    return null;
  }

  /// Progression vers le prochain palier (0..1), null si complet.
  double? get progress {
    final t = nextTarget;
    if (t == null || t <= 0) return null;
    return (value / t).clamp(0.0, 1.0).toDouble();
  }

  /// La jauge ne se dessine que pour une mesure continue : un badge simple
  /// « obtenu ou pas » (palier 1) n'en a pas.
  bool get showGauge => nextTarget != null && nextTarget! > 1;

  /// Texte du ruban : le palier atteint pour une ligne à paliers, sinon le
  /// libellé fixe du badge.
  String get ribbonLabel => def.tiers.length > 5 && level > 0 ? fmtInt(def.tiers[level - 1]) : (def.label ?? '');
}

/// Une case du graphique d'avancement.
/// `bridged` = jour comblé par une braise (série de routine seulement) ;
/// `frozen` = jour gelé par une veille du domaine (ni tenu ni manqué).
enum TrackCell { hit, miss, neutral, current, future, bridged, frozen }

/// Bande de cases de la plus ancienne à la plus récente, avec sa légende.
class BadgeTrack {
  final List<TrackCell> cells;
  final String caption; // « 30 derniers jours · 24 atteints »
  final String hitLabel; // « atteint », « solide », « sur le plan »…
  final String missLabel;
  const BadgeTrack({required this.cells, required this.caption, this.hitLabel = 'atteint', this.missLabel = 'manqué'});
  int get hits => cells.where((c) => c == TrackCell.hit).length;
}

class BadgeDeck {
  final List<BadgeState> badges;
  /// Braises (réserve, rallumages) ; vide quand le deck vient d'un instantané.
  final EmberLedger embers;
  /// Reprises possibles ou en cours aujourd'hui, par routine (`reprise.dart`).
  final Map<String, RepriseNow> reprises;
  /// Semaines tenues (`held_weeks.dart`) : série, semaine en cours, coches qui manquent.
  final HeldWeeks weeks;
  const BadgeDeck(this.badges, {this.embers = EmberLedger.empty, this.reprises = const {}, this.weeks = HeldWeeks.empty});

  /// Le compteur « n sur N » compte les paliers de toutes les familles SAUF les
  /// séries de routine (décision 2026-10-26) : un badge par routine gonflait le
  /// total avec chaque routine créée. Les séries se montrent à part
  /// (`seriesRunning`).
  List<BadgeState> get counted => badges.where((b) => b.def.family != BadgeFamily.routines).toList();
  int get total => counted.fold(0, (s, b) => s + b.paliersTotal);
  int get acquired => counted.fold(0, (s, b) => s + b.paliersDone);

  List<BadgeState> get series => ofFamily(BadgeFamily.routines);
  /// Séries de routine en cours (au moins un jour d'affilée).
  int get seriesRunning => series.where((b) => b.value > 0).length;
  /// Séries ayant atteint au moins un palier.
  int get seriesWithTier => series.where((b) => b.acquired).length;

  List<BadgeState> ofFamily(BadgeFamily f) => badges.where((b) => b.def.family == f).toList();

  BadgeState? get lastObtained {
    BadgeState? best;
    for (final b in badges) {
      final d = b.obtained;
      if (d == null) continue;
      if (best == null || d.isAfter(best.obtained!)) best = b;
    }
    return best;
  }

  BadgeState? byId(String id) {
    for (final b in badges) {
      if (b.def.id == id) return b;
    }
    return null;
  }
}

String fmtInt(num n) {
  final s = n.round().toString();
  final out = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) out.write(' ');
    out.write(s[i]);
  }
  return out.toString();
}

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// Dates des paliers : pour chaque palier k, le premier jour où une série
/// (`runs` = (début, longueur), dans l'ordre chronologique) a atteint k.
List<DateTime?> _tierDatesFromRuns(List<int> tiers, List<(DateTime, int)> runs) {
  final out = List<DateTime?>.filled(tiers.length, null);
  for (final (start, len) in runs) {
    for (var i = 0; i < tiers.length; i++) {
      if (out[i] == null && len >= tiers[i]) out[i] = start.add(Duration(days: tiers[i] - 1));
    }
  }
  return out;
}

int _levelOf(List<int> tiers, num value) {
  var lv = 0;
  for (final t in tiers) {
    if (value >= t) lv++;
  }
  return lv;
}

/// Séries consécutives (début, longueur) dans un ensemble de jours `YYYY-MM-DD`.
/// [skip] = jours transparents (gelés) : ils ne cassent pas la série et ne
/// comptent pas dans sa longueur.
List<(DateTime, int)> _runsOf(Set<String> days, {Set<String> skip = const {}}) {
  final sorted = days.map((s) => DateTime.parse(s)).toList()..sort();
  final runs = <(DateTime, int)>[];
  DateTime? start;
  DateTime? prev;
  var len = 0;
  bool bridgedBySkip(DateTime a, DateTime b) {
    if (skip.isEmpty) return false;
    for (var d = DateTime(a.year, a.month, a.day + 1); d.isBefore(b); d = DateTime(d.year, d.month, d.day + 1)) {
      if (!skip.contains(ymdOf(d))) return false;
    }
    return true;
  }
  for (final d in sorted) {
    if (prev != null && (d.difference(prev).inDays == 1 || bridgedBySkip(prev, d))) {
      len++;
    } else {
      if (start != null) runs.add((start, len));
      start = d;
      len = 1;
    }
    prev = d;
  }
  if (start != null) runs.add((start, len));
  return runs;
}

/// Série en cours : jours consécutifs jusqu'à `today` inclus, ou jusqu'à
/// hier si aujourd'hui n'est pas (encore) atteint.
int _currentRun(Set<String> days, DateTime today, {Set<String> skip = const {}}) {
  var d = _day(today);
  if (!days.contains(ymdOf(d))) d = DateTime(d.year, d.month, d.day - 1);
  var n = 0;
  var guard = 0;
  while (guard++ < 4000) {
    final y = ymdOf(d);
    if (days.contains(y)) {
      n++;
    } else if (!skip.contains(y)) {
      break;
    }
    d = DateTime(d.year, d.month, d.day - 1);
  }
  return n;
}

// ─── Séries de routine ──────────────────────────────────────────────────────

class RoutineSeries {
  final int current; // jours d'affilée en cours
  final int longest;
  final int reachedDays; // jours où la cible a été atteinte, depuis le début
  final int sinceDays; // jours depuis le premier hit
  final List<DateTime?> tierDates;
  const RoutineSeries({
    required this.current,
    required this.longest,
    required this.reachedDays,
    required this.sinceDays,
    required this.tierDates,
  });
}

/// Jours vécus où la routine QUOTIDIENNE `a` a atteint sa cible
/// (`habitTarget`, 1 au moins). Les hits nocturnes suivent la journée vécue.
Set<String> routineReachedDays(Activity a, List<HabitHit> hits, {int dayStartMin = kDefaultDayStartMin}) {
  final target = (a.habitTarget ?? 1) <= 0 ? 1 : (a.habitTarget ?? 1);
  final counts = <String, int>{};
  for (final h in hits) {
    if (h.habitId != a.id) continue;
    final k = ymdOf(livedDate(h.ts, dayStartMin));
    counts[k] = (counts[k] ?? 0) + 1;
  }
  return counts.entries.where((e) => e.value >= target).map((e) => e.key).toSet();
}

/// [bridged] = jours comblés par une braise : ils tiennent la série, mais ne
/// comptent pas comme « jours atteints ». [frozen] = jours gelés par une veille
/// du domaine : ni tenus ni manqués.
RoutineSeries routineSeries(Activity a, List<HabitHit> hits, DateTime now,
    {int dayStartMin = kDefaultDayStartMin, Set<String> bridged = const {}, Set<String> frozen = const {}}) {
  final reachedOnly = routineReachedDays(a, hits, dayStartMin: dayStartMin);
  final days = {...reachedOnly, ...bridged};
  final runs = _runsOf(days, skip: frozen);
  final longest = runs.fold(0, (m, r) => r.$2 > m ? r.$2 : m);
  final today = livedDate(now, dayStartMin);
  DateTime? first;
  for (final h in hits) {
    if (h.habitId != a.id) continue;
    if (first == null || h.ts.isBefore(first)) first = h.ts;
  }
  final since = first == null ? 0 : today.difference(_day(livedDate(first, dayStartMin))).inDays + 1;
  return RoutineSeries(
    current: _currentRun(days, today, skip: frozen),
    longest: longest,
    reachedDays: reachedOnly.length,
    sinceDays: since,
    tierDates: _tierDatesFromRuns(kRoutineTiers, runs),
  );
}

/// Ligne du record d'une série : « Record en cours · 21 j » ou « Encore 5 j
/// pour égaler ton record (21 j) » ; rien sans série en cours ni record d'au
/// moins 3 jours.
String? recordLine(int current, int longest) {
  if (current <= 0 || longest < 3) return null;
  if (current >= longest) return 'Record en cours · $current j';
  return 'Encore ${longest - current} j pour égaler ton record ($longest j)';
}

/// Le badge de série d'une routine quotidienne, complet (paliers, faits, bande
/// des 30 derniers jours) : le deck et la fiche routine / le segment Routines
/// d'Aujourd'hui l'affichent tel quel.
BadgeState routineBadge(Activity a, List<HabitHit> hits, DateTime now,
    {int dayStartMin = kDefaultDayStartMin, Set<String> bridged = const {}, Set<String> frozen = const {}}) {
  final s = routineSeries(a, hits, now, dayStartMin: dayStartMin, bridged: bridged, frozen: frozen);
  final reached = routineReachedDays(a, hits, dayStartMin: dayStartMin);
  final first = reached.isEmpty ? null : (reached.toList()..sort()).first;
  final today = livedDate(now, dayStartMin);
  final cells = <TrackCell>[];
  for (var i = 29; i >= 0; i--) {
    final y = ymdOf(today.subtract(Duration(days: i)));
    if (i == 0) {
      cells.add(reached.contains(y) ? TrackCell.hit : (frozen.contains(y) ? TrackCell.frozen : TrackCell.current));
    } else if (first == null || y.compareTo(first) < 0) {
      cells.add(TrackCell.neutral);
    } else {
      cells.add(reached.contains(y)
          ? TrackCell.hit
          : (bridged.contains(y) ? TrackCell.bridged : (frozen.contains(y) ? TrackCell.frozen : TrackCell.miss)));
    }
  }
  final hits30 = cells.where((c) => c == TrackCell.hit).length;
  final bridged30 = cells.where((c) => c == TrackCell.bridged).length;
  final frozen30 = cells.where((c) => c == TrackCell.frozen).length;
  return BadgeState(
    def: BadgeDef(id: 'serie-${a.id}', family: BadgeFamily.routines, name: a.name, symbol: 'flame', tiers: kRoutineTiers, unit: 'j', unitLong: 'jours', subjectId: a.id),
    level: _levelOf(kRoutineTiers, s.longest),
    value: s.current,
    tierDates: s.tierDates,
    facts: [
      ('Série en cours', _plural(s.current, 'jour', 'jours')),
      ('Série la plus longue', _plural(s.longest, 'jour', 'jours')),
      if (s.longest > s.current && s.current > 0) ('Pour égaler le record', _plural(s.longest - s.current, 'jour', 'jours')),
      if (s.sinceDays > 0) ('Jours atteints sur ${s.sinceDays}', '${s.reachedDays}'),
      if (bridged.isNotEmpty) ('Jours rallumés', '${bridged.length}'),
      if (frozen.isNotEmpty) ('Jours gelés (veille)', '${frozen.length}'),
    ],
    track: BadgeTrack(
        cells: cells,
        caption: '30 derniers jours · $hits30 jours atteints${bridged30 > 0 ? ' · $bridged30 rallumé${bridged30 > 1 ? 's' : ''}' : ''}${frozen30 > 0 ? ' · $frozen30 gelé${frozen30 > 1 ? 's' : ''}' : ''}'),
  );
}

// ─── Journées ───────────────────────────────────────────────────────────────

class DayScore {
  final String ymd;
  final int routinesDue, routinesReached, blocks, blocksDone;
  const DayScore(this.ymd, this.routinesDue, this.routinesReached, this.blocks, this.blocksDone);

  /// Journée neutre : rien à tenir ce jour-là, elle ne compte ni pour ni contre.
  bool get neutral => routinesDue + blocks == 0;
  double get routineRatio => routinesDue == 0 ? 1 : routinesReached / routinesDue;
  double get blockRatio => blocks == 0 ? 1 : blocksDone / blocks;
  bool get perfect => !neutral && routinesReached == routinesDue && blocksDone == blocks;
  bool solidAt(double threshold) => !neutral && routineRatio >= threshold && blockRatio >= threshold;
}

/// Bloc qui compte pour les journées (parfaite, solide) : bloc normal ou deep
/// work, hors miroir d'agenda, fait ou à faire. Partagé avec `badge_today.dart`.
bool countsForBadges(ScheduleBlock b) =>
    (b.kind == 'normal' || b.kind == 'deepwork') && b.gcalEventId == null && (b.status == 'done' || b.status == 'pending');

/// Score d'un jour vécu : routines quotidiennes dues (créées avant ce jour,
/// non supprimées) et blocs du programme (hors miroirs d'agenda, sautés,
/// supprimés, préparation / bilan / session).
DayScore scoreDay(DateTime day, {
  required List<Activity> activities,
  required Map<String, Set<String>> reachedDaysByRoutine,
  DailySchedule? schedule,
}) {
  final ymd = ymdOf(day);
  var due = 0, reached = 0;
  for (final a in activities) {
    if (a.deleted || !a.isHabit || a.habitFreq != HabitFreq.daily) continue;
    if (_day(a.createdAt).isAfter(day)) continue;
    due++;
    if (reachedDaysByRoutine[a.id]?.contains(ymd) ?? false) reached++;
  }
  var blocks = 0, done = 0;
  if (schedule != null) {
    for (final b in schedule.blocks) {
      if (!countsForBadges(b)) continue;
      blocks++;
      if (b.status == 'done') done++;
    }
  }
  return DayScore(ymd, due, reached, blocks, done);
}

/// Scores de tous les jours passés (hier vécu compris), du plus ancien au plus
/// récent, à partir du premier hit ou du premier programme. 400 jours au plus.
List<DayScore> scoreDays({
  required List<Activity> activities,
  required List<HabitHit> hits,
  required List<DailySchedule> schedules,
  required DateTime now,
  int dayStartMin = kDefaultDayStartMin,
}) {
  final reached = <String, Set<String>>{};
  for (final a in activities) {
    if (a.deleted || !a.isHabit || a.habitFreq != HabitFreq.daily) continue;
    reached[a.id] = routineReachedDays(a, hits, dayStartMin: dayStartMin);
  }
  final byDate = {for (final s in schedules) s.date: s};
  final yesterday = livedDate(now, dayStartMin).subtract(const Duration(days: 1));
  DateTime? first;
  for (final h in hits) {
    final d = _day(livedDate(h.ts, dayStartMin));
    if (first == null || d.isBefore(first)) first = d;
  }
  for (final s in schedules) {
    final d = DateTime.tryParse(s.date);
    if (d != null && (first == null || d.isBefore(first))) first = d;
  }
  if (first == null || first.isAfter(yesterday)) return const [];
  final floor = yesterday.subtract(const Duration(days: 399));
  if (first.isBefore(floor)) first = floor;
  final out = <DayScore>[];
  for (var d = first; !d.isAfter(yesterday); d = d.add(const Duration(days: 1))) {
    out.add(scoreDay(d, activities: activities, reachedDaysByRoutine: reached, schedule: byDate[ymdOf(d)]));
  }
  return out;
}

/// Séries (début, longueur) de journées solides à `threshold`, les journées
/// neutres enjambées sans casser.
List<(DateTime, int)> solidRuns(List<DayScore> days, double threshold) {
  final runs = <(DateTime, int)>[];
  DateTime? start;
  var len = 0;
  for (final s in days) {
    if (s.neutral) continue;
    if (s.solidAt(threshold)) {
      start ??= DateTime.parse(s.ymd);
      len++;
    } else {
      if (start != null) runs.add((start, len));
      start = null;
      len = 0;
    }
  }
  if (start != null) runs.add((start, len));
  return runs;
}

// ─── Objectifs ──────────────────────────────────────────────────────────────

bool _onPlan(TrajectoryStatus s) => s == TrajectoryStatus.ahead || s == TrajectoryStatus.onTrack;

/// Semaines consécutives « sur la trajectoire » : chaque lundi écoulé depuis
/// le début, la trajectoire évaluée CE lundi-là (relevés connus à cette date)
/// a ses moyens et son résultat sur le plan. Retourne (série en cours, plus
/// longue, lundis des séries).
({int current, int longest, List<(DateTime, int)> runs, Set<String> onPlan}) trajectoryWeeks(
    StrategicObjective o, List<Session> sessions, DateTime now) {
  final hasMeans = o.timeCommitments.isNotEmpty;
  final hasResult = o.metric != null;
  if (!hasMeans && !hasResult) return (current: 0, longest: 0, runs: const [], onPlan: const {});
  final start = objectiveStart(o);
  final lastMonday = mondayOf(now);
  final weeks = <String>{};
  var m = mondayOf(start).add(const Duration(days: 7));
  var guard = 0;
  while (!m.isAfter(lastMonday) && guard++ < 520) {
    final snapshot = StrategicObjective.from(o.toJson());
    final ymd = ymdOf(m);
    snapshot.readings.removeWhere((r) => r.date.compareTo(ymd) > 0);
    final t = computeObjectiveTrajectory(snapshot, sessions, m);
    final meansOk = !hasMeans || _onPlan(t.means.status);
    final resultOk = !hasResult || (t.result != null && _onPlan(t.result!.status));
    if (meansOk && resultOk) weeks.add(ymd);
    m = m.add(const Duration(days: 7));
  }
  // Les lundis consécutifs sont espacés de 7 jours : on les ramène à des jours.
  final asDays = <String>{};
  for (final w in weeks) {
    final d = DateTime.parse(w);
    asDays.add(ymdOf(mondayOf(start).add(Duration(days: d.difference(mondayOf(start)).inDays ~/ 7))));
  }
  final runs = _runsOf(asDays);
  final longest = runs.fold(0, (mx, r) => r.$2 > mx ? r.$2 : mx);
  final lastIdx = lastMonday.difference(mondayOf(start)).inDays ~/ 7;
  final current = _currentRun(asDays, mondayOf(start).add(Duration(days: lastIdx)));
  final realRuns = runs.map((r) => (mondayOf(start).add(Duration(days: 7 * r.$1.difference(mondayOf(start)).inDays)), r.$2)).toList();
  return (current: current, longest: longest, runs: realRuns, onPlan: weeks);
}

/// Plus longue suite de relevés sans trou (écart ≤ `checkInEvery` + 1 jour),
/// et la date du k-ième relevé de la première suite qui atteint chaque palier.
({int longest, int current, List<DateTime?> tierDates}) faithfulReadings(StrategicObjective o) {
  final every = (o.checkInEvery < 1 ? 7 : o.checkInEvery) + 1;
  final dates = o.readings.map((r) => DateTime.tryParse(r.date)).whereType<DateTime>().toSet().toList()..sort();
  final tierDates = List<DateTime?>.filled(kReadingTiers.length, null);
  var longest = 0, run = 0;
  DateTime? prev;
  final runDates = <DateTime>[];
  for (final d in dates) {
    if (prev != null && d.difference(prev).inDays <= every) {
      run++;
      runDates.add(d);
    } else {
      run = 1;
      runDates
        ..clear()
        ..add(d);
    }
    for (var i = 0; i < kReadingTiers.length; i++) {
      if (tierDates[i] == null && run >= kReadingTiers[i]) tierDates[i] = runDates[kReadingTiers[i] - 1];
    }
    if (run > longest) longest = run;
    prev = d;
  }
  return (longest: longest, current: run, tierDates: tierDates);
}

bool metricReached(StrategicObjective o) {
  final m = o.metric;
  final r = latestReading(o);
  if (m == null || r == null) return false;
  return m.decreasing ? r.value <= m.targetValue : r.value >= m.targetValue;
}

// ─── Temps investi ──────────────────────────────────────────────────────────

/// Heures de chrono sur les activités engagées d'un objectif depuis son
/// début, et la date où chaque palier a été franchi.
({double hours, List<DateTime?> tierDates}) investedHours(StrategicObjective o, List<Session> sessions, DateTime now) {
  final ids = o.timeCommitments.map((c) => c.activityId).toSet();
  final tierDates = List<DateTime?>.filled(kTimeTiersHours.length, null);
  if (ids.isEmpty) return (hours: 0, tierDates: tierDates);
  final start = objectiveStart(o);
  final closed = sessions.where((s) => !s.deleted && ids.contains(s.activityId) && s.endAt != null && !s.endAt!.isBefore(start)).toList()
    ..sort((a, b) => a.endAt!.compareTo(b.endAt!));
  var min = 0;
  for (final s in closed) {
    final from = s.startAt.isBefore(start) ? start : s.startAt;
    final m = s.endAt!.difference(from).inMinutes;
    if (m <= 0) continue;
    min += m;
    for (var i = 0; i < kTimeTiersHours.length; i++) {
      if (tierDates[i] == null && min >= kTimeTiersHours[i] * 60) tierDates[i] = _day(s.endAt!);
    }
  }
  min += committedMinutesSince(o, sessions.where((s) => s.endAt == null).toList(), start, now);
  return (hours: min / 60, tierDates: tierDates);
}

// ─── Le deck ────────────────────────────────────────────────────────────────

String _fmtDate(DateTime d) {
  const months = ['janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'];
  return '${d.day == 1 ? '1er' : d.day} ${months[d.month - 1]} ${d.year}';
}

String _plural(int n, String one, String many) => '$n ${n > 1 ? many : one}';

BadgeDeck computeBadges({
  required List<Activity> activities,
  required List<HabitHit> habitHits,
  required List<DailySchedule> schedules,
  required List<Project> projects,
  required List<StrategicObjective> objectives,
  required List<Session> sessions,
  required DateTime now,
  List<MoodMark> moodMarks = const [],
  List<ChainRun> chainRuns = const [],
  int dayStartMin = kDefaultDayStartMin,
  List<EmberSpend> emberSpends = const [],
  List<RestPeriod> restPeriods = const [],
  Map<String, String> restDomains = const {},
}) {
  final out = <BadgeState>[];
  // Journées closes : les journées parfaites forgent les braises, qui
  // comblent ensuite les séries (les jours comblés ne comptent jamais ici).
  final days = scoreDays(activities: activities, hits: habitHits, schedules: schedules, now: now, dayStartMin: dayStartMin);

  // Séries de routine : un badge par routine quotidienne active, par nom.
  final routines = activities.where((a) => !a.deleted && a.isHabit && a.habitFreq == HabitFreq.daily).toList()
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  final todayYmd = ymdOf(livedDate(now, dayStartMin));
  final frozenByDomain = <String, Set<String>>{};
  Set<String> frozenOf(Activity a) => frozenByDomain.putIfAbsent(a.domainId, () => frozenDaysOf(a.domainId, restPeriods, restDomains, todayYmd));
  // Semaines tenues : le contrat de la semaine à 80 %, une braise par semaine tenue.
  final weeks = heldWeeks(activities: activities, hits: habitHits, objectives: objectives, now: now, dayStartMin: dayStartMin, frozenOf: frozenOf);
  final embers = emberLedger(
    perfectYmds: [for (final d in days) if (d.perfect) d.ymd],
    heldWeekYmds: weeks.heldSundays,
    spends: emberSpends,
    reached: {for (final a in routines) a.id: routineReachedDays(a, habitHits, dayStartMin: dayStartMin)},
    todayYmd: todayYmd,
  );
  final repriseEvents = <(String, RepriseEvent)>[];
  final reprisesNow = <String, RepriseNow>{};
  for (final a in routines) {
    final bridged = embers.bridged[a.id] ?? const <String>{};
    out.add(routineBadge(a, habitHits, now, dayStartMin: dayStartMin, bridged: bridged, frozen: frozenOf(a)));
    final r = reprisesOf({...routineReachedDays(a, habitHits, dayStartMin: dayStartMin), ...bridged}, frozenOf(a), todayYmd);
    for (final e in r.events) {
      repriseEvents.add((a.name, e));
    }
    if (r.now != null) reprisesNow[a.id] = r.now!;
  }

  // Semaines tenues (famille Objectifs : c'est le Contrat d'Engagement).
  final thisWeek = weeks.thisWeek;
  out.add(BadgeState(
    def: const BadgeDef(id: 'semaines-tenues', family: BadgeFamily.objectives, name: 'Semaines tenues', symbol: 'week', tiers: kHeldWeekTiers, unit: 'sem.', unitLong: 'semaines'),
    level: _levelOf(kHeldWeekTiers, weeks.longest),
    value: weeks.current,
    tierDates: weeks.tierDates,
    facts: [
      ('Série en cours', _plural(weeks.current, 'semaine', 'semaines')),
      ('Plus longue série', _plural(weeks.longest, 'semaine', 'semaines')),
      if (weeks.closedCount > 0) ('Semaines tenues', '${weeks.heldCount} sur ${weeks.closedCount}'),
      if (thisWeek?.pct != null) ('Cette semaine', '${(thisWeek!.pct! * 100).round()} %${weeks.missing > 0 ? ' · encore ${weeks.missing} coche${weeks.missing > 1 ? 's' : ''}' : ' · tenue'}'),
      if (embers.history.any((e) => e.week && e.kind == EmberEventKind.earned))
        ('Braises forgées', '${embers.history.where((e) => e.week && e.kind == EmberEventKind.earned).length}'),
    ],
  ));

  // Objectifs.
  final done = objectives.where((o) => o.status == 'done').toList();
  DateTime? firstDone;
  for (final o in done) {
    final d = o.updatedAt ?? o.endDate ?? o.createdAt;
    if (firstDone == null || d.isBefore(firstDone)) firstDone = d;
  }
  out.add(BadgeState(
    def: const BadgeDef(id: 'premiere-cible', family: BadgeFamily.objectives, name: 'Première cible', symbol: 'target', tiers: [1], label: '1re'),
    level: done.isEmpty ? 0 : 1,
    value: done.length,
    tierDates: [firstDone],
    facts: [('Objectifs atteints', '${done.length}'), if (firstDone != null) ('Le premier', _fmtDate(firstDone))],
  ));

  var trajCurrent = 0, trajLongest = 0;
  List<(DateTime, int)> trajRuns = const [];
  String? trajBest;
  Set<String> trajOnPlan = const {};
  StrategicObjective? trajObj;
  for (final o in objectives) {
    if (o.status == 'archived') continue;
    final t = trajectoryWeeks(o, sessions, now);
    if (t.longest > trajLongest || trajBest == null) {
      trajLongest = t.longest;
      trajRuns = t.runs;
      trajBest = o.title;
      trajOnPlan = t.onPlan;
      trajObj = o;
    }
    if (t.current > trajCurrent) trajCurrent = t.current;
  }
  out.add(BadgeState(
    def: const BadgeDef(id: 'trajectoire', family: BadgeFamily.objectives, name: 'Sur la trajectoire', symbol: 'trajectory', tiers: kTrajectoryTiers, unit: 'sem.', unitLong: 'semaines'),
    level: _levelOf(kTrajectoryTiers, trajLongest),
    value: trajCurrent,
    tierDates: _tierDatesFromRuns(kTrajectoryTiers, trajRuns.map((r) => (r.$1, r.$2)).toList()),
    facts: [
      ('Semaines d’affilée en cours', '$trajCurrent'),
      ('Plus longue suite', _plural(trajLongest, 'semaine', 'semaines')),
      if (trajBest != null && trajLongest > 0) ('Objectif', trajBest),
    ],
  ));

  var readLongest = 0, readCurrent = 0;
  var readDates = List<DateTime?>.filled(kReadingTiers.length, null);
  StrategicObjective? readObj;
  for (final o in objectives) {
    final f = faithfulReadings(o);
    if (f.longest > readLongest || (readObj == null && o.metric != null)) {
      readLongest = f.longest;
      readDates = f.tierDates;
      readObj = o;
    }
    if (f.current > readCurrent) readCurrent = f.current;
  }
  out.add(BadgeState(
    def: const BadgeDef(id: 'releve-fidele', family: BadgeFamily.objectives, name: 'Relevé fidèle', symbol: 'ledger', tiers: kReadingTiers, unit: 'relevés', unitLong: 'relevés'),
    level: _levelOf(kReadingTiers, readLongest),
    value: readCurrent,
    tierDates: readDates,
    facts: [('Relevés sans trou, en cours', '$readCurrent'), ('Plus longue suite', '$readLongest')],
  ));

  final hit = objectives.where((o) => o.status == 'done' && metricReached(o)).toList();
  DateTime? firstHit;
  for (final o in hit) {
    final d = o.updatedAt ?? o.endDate ?? o.createdAt;
    if (firstHit == null || d.isBefore(firstHit)) firstHit = d;
  }
  out.add(BadgeState(
    def: const BadgeDef(id: 'cible-atteinte', family: BadgeFamily.objectives, name: 'Cible atteinte', symbol: 'hit', tiers: [1], label: 'Atteint'),
    level: hit.isEmpty ? 0 : 1,
    value: hit.length,
    tierDates: [firstHit],
    facts: [('Objectifs terminés à la cible', '${hit.length}')],
  ));

  // Journées (`days` calculées en tête).
  final perfect = days.where((d) => d.perfect).toList();
  out.add(BadgeState(
    def: const BadgeDef(id: 'journee-parfaite', family: BadgeFamily.days, name: 'Journée parfaite', symbol: 'sun', tiers: [1], label: 'Parfaite'),
    level: perfect.isEmpty ? 0 : 1,
    value: perfect.length,
    tierDates: [perfect.isEmpty ? null : DateTime.parse(perfect.first.ymd)],
    facts: [('Journées parfaites', '${perfect.length}'), if (perfect.isNotEmpty) ('La dernière', _fmtDate(DateTime.parse(perfect.last.ymd)))],
  ));
  final runs80 = solidRuns(days, 0.8);
  final longest80 = runs80.fold(0, (m, r) => r.$2 > m ? r.$2 : m);
  final current80 = _currentSolidRun(days);
  for (final (id, name, symbol, tier, label) in [
    ('semaine-solide', 'Semaine solide', 'bricks2', 7, '7 j'),
    ('mois-solide', 'Mois solide', 'bricks3', 30, '30 j'),
  ]) {
    out.add(BadgeState(
      def: BadgeDef(id: id, family: BadgeFamily.days, name: name, symbol: symbol, tiers: [tier], unit: 'j', unitLong: 'jours', label: label),
      level: longest80 >= tier ? 1 : 0,
      value: current80,
      tierDates: _tierDatesFromRuns([tier], runs80),
      facts: [('Jours solides d’affilée, en cours', '$current80'), ('Plus longue suite', _plural(longest80, 'jour', 'jours'))],
    ));
  }

  // Discipline : ce que je fais quand l'élan est bas.
  final disc = disciplineStats(marks: moodMarks, schedules: schedules, hits: habitHits, activities: activities, dayStartMin: dayStartMin);
  out.add(BadgeState(
    def: const BadgeDef(id: 'malgre-tout', family: BadgeFamily.discipline, name: 'Malgré tout', symbol: 'anvil', tiers: kDisciplineTiers, unit: 'victoires', unitLong: 'victoires sur la flemme'),
    level: _levelOf(kDisciplineTiers, disc.wins.length),
    value: disc.wins.length,
    tierDates: [for (final t in kDisciplineTiers) t <= disc.wins.length ? _day(disc.wins[t - 1]) : null],
    facts: [
      ('Victoires sur la flemme', '${disc.wins.length}'),
      if (disc.wins.isNotEmpty) ('La dernière', _fmtDate(disc.wins.last)),
      ('Pointages « Flemme » ou « Mou »', '${moodMarks.where((m) => m.lowElan).length}'),
    ],
  ));
  // Vent contraire : une suite de 7 jours solides (critère de Semaine solide) à élan moyen ≤ 2,5.
  DateTime? ventDate;
  var ventCurrent = 0;
  for (final (start, len) in runs80) {
    for (var i = 0; i + 7 <= len && ventDate == null; i++) {
      var sum = 0.0, n = 0;
      for (var d = 0; d < 7; d++) {
        final m = disc.meanByYmd[ymdOf(start.add(Duration(days: i + d)))];
        if (m != null) {
          sum += m;
          n++;
        }
      }
      if (n >= 3 && sum / n <= 2.5) ventDate = start.add(Duration(days: i + 6));
    }
  }
  if (ventDate == null && current80 > 0) {
    var sum = 0.0, n = 0;
    final today = livedDate(now, dayStartMin);
    for (var d = 1; d <= current80 && d <= 7; d++) {
      final m = disc.meanByYmd[ymdOf(today.subtract(Duration(days: d)))];
      if (m != null) {
        sum += m;
        n++;
      }
    }
    if (n > 0 && sum / n <= 2.5) ventCurrent = current80.clamp(0, 7);
  }
  out.add(BadgeState(
    def: const BadgeDef(id: 'vent-contraire', family: BadgeFamily.discipline, name: 'Vent contraire', symbol: 'wind', tiers: [1], label: 'Contre'),
    level: ventDate == null ? 0 : 1,
    value: ventDate == null ? 0 : 1,
    tierDates: [ventDate],
    facts: [
      ('Semaine solide à élan bas', ventDate == null ? 'pas encore' : 'le ${_fmtDate(ventDate)}'),
      if (ventDate == null && ventCurrent > 0) ('Jours solides à élan bas, en cours', '$ventCurrent / 7'),
    ],
  ));
  // Marée haute : jours pointés d'affilée à élan moyen ≥ 4 (les jours sans pointage sont enjambés).
  final highDays = disc.meanByYmd.entries.where((e) => e.value >= 4).map((e) => e.key).toList()..sort();
  final pointed = disc.meanByYmd.keys.toList()..sort();
  final highRuns = <(DateTime, int)>[];
  var hStart = '', hLen = 0, hCurrent = 0;
  for (final ymd in pointed) {
    if (highDays.contains(ymd)) {
      if (hLen == 0) hStart = ymd;
      hLen++;
    } else {
      if (hLen > 0) highRuns.add((DateTime.parse(hStart), hLen));
      hLen = 0;
    }
  }
  if (hLen > 0) highRuns.add((DateTime.parse(hStart), hLen));
  hCurrent = hLen;
  final highLongest = highRuns.fold(0, (m, r) => r.$2 > m ? r.$2 : m);
  out.add(BadgeState(
    def: const BadgeDef(id: 'maree-haute', family: BadgeFamily.discipline, name: 'Marée haute', symbol: 'tide', tiers: [7], unit: 'j', unitLong: 'jours', label: '7 j'),
    level: highLongest >= 7 ? 1 : 0,
    value: hCurrent,
    tierDates: _tierDatesFromRuns([7], highRuns.map((r) => (r.$1, r.$2)).toList()),
    facts: [('Jours à élan ≥ 4 d\u2019affilée, en cours', '$hCurrent'), ('Plus longue suite', _plural(highLongest, 'jour', 'jours'))],
  ));
  out.add(BadgeState(
    def: const BadgeDef(id: 'barometre', family: BadgeFamily.discipline, name: 'Baromètre', symbol: 'barometer', tiers: kBarometerTiers, unit: 'pointages', unitLong: 'pointages'),
    level: _levelOf(kBarometerTiers, disc.elanMarkDates.length),
    value: disc.elanMarkDates.length,
    tierDates: [for (final t in kBarometerTiers) t <= disc.elanMarkDates.length ? _day(disc.elanMarkDates[t - 1]) : null],
    facts: [('Pointages d\u2019élan', '${disc.elanMarkDates.length}'), if (disc.elanMarkDates.isNotEmpty) ('Le premier', _fmtDate(disc.elanMarkDates.first))],
  ));
  // Deep work (Modes et coups) : un bloc de deep work CHOISI (kind "deepwork", posé par « Deep work 90 min »)
  // sur lequel le chrono a tenu ≥ 60 min d'affilée. Un chrono long tout seul (Sommeil, séance) ne compte pas.
  final deep = deepWorkSessions(sessions, schedules);
  out.add(BadgeState(
    def: const BadgeDef(id: 'deep-work', family: BadgeFamily.discipline, name: 'Deep work', symbol: 'focus', tiers: kDeepWorkTiers, unit: 'blocs', unitLong: 'blocs de deep work menés au bout'),
    level: _levelOf(kDeepWorkTiers, deep.length),
    value: deep.length,
    tierDates: [for (final t in kDeepWorkTiers) t <= deep.length ? _day(deep[t - 1]) : null],
    facts: [
      ('Blocs de deep work menés au bout', '${deep.length}'),
      if (deep.isNotEmpty) ('Le dernier', _fmtDate(deep.last)),
    ],
  ));
  // Reprise : une routine coupée au moins deux jours, puis tenue trois jours d'affilée.
  repriseEvents.sort((a, b) => a.$2.ymd.compareTo(b.$2.ymd));
  (String, RepriseEvent)? longestGap;
  for (final e in repriseEvents) {
    if (longestGap == null || e.$2.gap > longestGap.$2.gap) longestGap = e;
  }
  final routineName = {for (final a in routines) a.id: a.name};
  final inProgress = reprisesNow.entries.where((e) => !e.value.completedToday && e.value.held > 0).toList()
    ..sort((a, b) => b.value.held.compareTo(a.value.held));
  out.add(BadgeState(
    def: const BadgeDef(id: 'reprise', family: BadgeFamily.discipline, name: 'Reprise', symbol: 'rebound', tiers: kRepriseTiers, unit: 'reprises', unitLong: 'reprises'),
    level: _levelOf(kRepriseTiers, repriseEvents.length),
    value: repriseEvents.length,
    tierDates: [for (final t in kRepriseTiers) t <= repriseEvents.length ? DateTime.parse(repriseEvents[t - 1].$2.ymd) : null],
    facts: [
      ('Reprises', '${repriseEvents.length}'),
      if (inProgress.isNotEmpty) ('En cours', '${routineName[inProgress.first.key]} · ${inProgress.first.value.held} / $kRepriseHold j'),
      if (repriseEvents.isNotEmpty) ('La dernière', '${repriseEvents.last.$1} · ${_fmtDate(DateTime.parse(repriseEvents.last.$2.ymd))}'),
      if (longestGap != null) ('Plus longue coupure reprise', '${_plural(longestGap.$2.gap, 'jour', 'jours')} · ${longestGap.$1}'),
    ],
  ));
  // Enchaîner (règle 2026-10) : une session compte dès 3 choses faites d'affilée, sortie ou pas
  // (`chainRunCounts`) ; « Plein jour » garde seul l'exigence de la file vidée du premier au dernier bloc.
  final countedRuns = chainRuns.where(chainRunCounts).toList()..sort((a, b) => a.endedAt.compareTo(b.endedAt));
  final fullDays = chainRuns.where((r) => r.fullDay).toList()..sort((a, b) => a.endedAt.compareTo(b.endedAt));
  out.add(BadgeState(
    def: const BadgeDef(id: 'enchaineur', family: BadgeFamily.chain, name: 'Enchaîneur', symbol: 'chain', tiers: kChainTiers, unit: 'sessions', unitLong: 'sessions de 3 choses et plus'),
    level: _levelOf(kChainTiers, countedRuns.length),
    value: countedRuns.length,
    tierDates: [for (final t in kChainTiers) t <= countedRuns.length ? _day(countedRuns[t - 1].endedAt) : null],
    facts: [
      ('Sessions de 3 choses et plus', '${countedRuns.length}'),
      ('Sessions commencées', '${chainRuns.length}'),
      if (countedRuns.isNotEmpty) ('La dernière', _fmtDate(countedRuns.last.endedAt)),
    ],
  ));
  out.add(BadgeState(
    def: const BadgeDef(id: 'plein-jour', family: BadgeFamily.chain, name: 'Plein jour', symbol: 'sunrise', tiers: [1], label: 'Plein'),
    level: fullDays.isEmpty ? 0 : 1,
    value: fullDays.length,
    tierDates: [fullDays.isEmpty ? null : _day(fullDays.first.endedAt)],
    facts: [('Journées entières enchaînées', '${fullDays.length}'), if (fullDays.isNotEmpty) ('La première', _fmtDate(fullDays.first.endedAt))],
  ));

  // Actions accomplies : une ligne à paliers.
  final doneAt = <DateTime>[];
  var doneCount = 0;
  void countAction(TaskAction a) {
    if (!a.done) return;
    doneCount++;
    if (a.doneAt != null) doneAt.add(a.doneAt!);
  }
  for (final p in projects) {
    for (final t in p.tasks) {
      t.actions.forEach(countAction);
    }
  }
  for (final a in activities) {
    a.ownActions.forEach(countAction);
  }
  doneAt.sort();
  out.add(BadgeState(
    def: const BadgeDef(id: 'actions', family: BadgeFamily.actions, name: 'Actions accomplies', symbol: 'check', tiers: kActionTiers, unit: 'actions', unitLong: 'actions'),
    level: _levelOf(kActionTiers, doneCount),
    value: doneCount,
    tierDates: [for (final t in kActionTiers) t <= doneAt.length ? _day(doneAt[t - 1]) : null],
    facts: [('Actions faites', fmtInt(doneCount)), if (doneAt.isNotEmpty) ('La dernière', _fmtDate(doneAt.last))],
  ));

  // Temps investi : un badge par objectif avec des activités engagées.
  final timed = objectives.where((o) => o.status != 'archived' && o.timeCommitments.isNotEmpty).toList()
    ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
  for (final o in timed) {
    final h = investedHours(o, sessions, now);
    out.add(BadgeState(
      def: BadgeDef(id: 'temps-${o.id}', family: BadgeFamily.time, name: o.title, symbol: 'hourglass', tiers: kTimeTiersHours, unit: 'h', unitLong: 'heures', subjectId: o.id),
      level: _levelOf(kTimeTiersHours, h.hours),
      value: double.parse(h.hours.toStringAsFixed(1)),
      tierDates: h.tierDates,
      facts: [('Heures investies', '${h.hours.toStringAsFixed(1).replaceAll('.', ',')} h'), ('Depuis le', _fmtDate(objectiveStart(o)))],
    ));
  }

  // ── Graphiques d'avancement ────────────────────────────────────────────────
  final today = livedDate(now, dayStartMin);
  List<String> lastDays(int n) => [for (var i = n - 1; i >= 0; i--) ymdOf(today.subtract(Duration(days: i)))];
  final dayScoreByYmd = {for (final d in days) d.ymd: d};
  BadgeTrack daysTrack(bool Function(String ymd) hit, {bool Function(String ymd)? neutral, required String what, String hitLabel = 'atteint', String missLabel = 'manqué', int n = 30}) {
    final ymds = lastDays(n);
    final cells = <TrackCell>[];
    for (final y in ymds) {
      if (y == ymds.last) {
        cells.add(hit(y) ? TrackCell.hit : TrackCell.current);
      } else if (neutral != null && neutral(y)) {
        cells.add(TrackCell.neutral);
      } else {
        cells.add(hit(y) ? TrackCell.hit : TrackCell.miss);
      }
    }
    final hits = cells.where((c) => c == TrackCell.hit).length;
    return BadgeTrack(cells: cells, caption: '$n derniers jours · $hits $what', hitLabel: hitLabel, missLabel: missLabel);
  }
  bool solidDay(String y) => dayScoreByYmd[y]?.solidAt(0.8) ?? false;
  bool neutralDay(String y) => dayScoreByYmd[y]?.neutral ?? true;
  final lowWonByYmd = <String, bool>{};
  for (final w in disc.wins) {
    lowWonByYmd[ymdOf(livedDate(w, dayStartMin))] = true;
  }
  final lowByYmd = <String>{for (final m in moodMarks) if (m.lowElan) m.ymd};
  final actionsByYmd = <String, int>{};
  for (final t in doneAt) {
    final y = ymdOf(livedDate(t, dayStartMin));
    actionsByYmd[y] = (actionsByYmd[y] ?? 0) + 1;
  }

  BadgeTrack? trackOf(BadgeState b) {
    final id = b.def.id;
    if (id.startsWith('serie-')) return b.track; // posé par routineBadge
    if (id == 'semaines-tenues') {
      final last = weeks.weeks.length > 12 ? weeks.weeks.sublist(weeks.weeks.length - 12) : weeks.weeks;
      if (last.isEmpty) return null;
      final cells = [
        for (final w in last)
          switch (w.state) {
            WeekState.held => TrackCell.hit,
            WeekState.missed => TrackCell.miss,
            WeekState.current => TrackCell.current,
            WeekState.neutral => w.rest ? TrackCell.frozen : TrackCell.neutral,
          }
      ];
      final held = cells.where((c) => c == TrackCell.hit).length;
      return BadgeTrack(cells: cells, caption: '${last.length} dernières semaines · $held tenue${held > 1 ? 's' : ''}', hitLabel: 'tenue (≥ 80 %)', missLabel: 'sous 80 %');
    }
    if (id.startsWith('temps-')) {
      final o = objectives.where((x) => x.id == b.def.subjectId).firstOrNull;
      if (o == null) return null;
      final ids = o.timeCommitments.map((c) => c.activityId).toSet();
      final minByYmd = <String, int>{};
      for (final s in sessions) {
        if (s.deleted || !ids.contains(s.activityId)) continue;
        final y = ymdOf(livedDate(s.startAt, dayStartMin));
        minByYmd[y] = (minByYmd[y] ?? 0) + ((s.endAt ?? now).difference(s.startAt).inMinutes);
      }
      final startY = ymdOf(objectiveStart(o));
      final t = daysTrack((y) => (minByYmd[y] ?? 0) > 0, neutral: (y) => y.compareTo(startY) < 0, what: 'jours travaillés', hitLabel: 'chrono lancé', missLabel: 'rien');
      final total = lastDays(30).fold(0, (s, y) => s + (minByYmd[y] ?? 0));
      return BadgeTrack(cells: t.cells, caption: '${t.caption} · ${(total / 60).toStringAsFixed(1).replaceAll('.', ',')} h', hitLabel: t.hitLabel, missLabel: t.missLabel);
    }
    switch (id) {
      case 'journee-parfaite':
        return daysTrack((y) => dayScoreByYmd[y]?.perfect ?? false, neutral: neutralDay, what: 'journées parfaites', hitLabel: 'parfaite', missLabel: 'incomplète');
      case 'semaine-solide':
      case 'mois-solide':
      case 'vent-contraire':
        return daysTrack(solidDay, neutral: neutralDay, what: 'journées solides', hitLabel: 'solide (≥ 80 %)', missLabel: 'sous 80 %');
      case 'trajectoire':
        final o = trajObj;
        if (o == null) return null;
        final start = mondayOf(objectiveStart(o));
        final cells = <TrackCell>[];
        var m = mondayOf(now).subtract(const Duration(days: 7 * 11));
        for (var i = 0; i < 12; i++) {
          final y = ymdOf(m);
          if (!m.isAfter(start)) {
            cells.add(TrackCell.neutral);
          } else if (i == 11) {
            cells.add(TrackCell.current);
          } else {
            cells.add(trajOnPlan.contains(y) ? TrackCell.hit : TrackCell.miss);
          }
          m = m.add(const Duration(days: 7));
        }
        return BadgeTrack(cells: cells, caption: '12 dernières semaines · ${cells.where((c) => c == TrackCell.hit).length} sur le plan · ${o.title}', hitLabel: 'sur le plan', missLabel: 'en retard');
      case 'releve-fidele':
        final o = readObj;
        if (o == null) return null;
        final every = o.checkInEvery < 1 ? 7 : o.checkInEvery;
        final start = objectiveStart(o);
        final dates = o.readings.map((r) => r.date).toSet();
        final cells = <TrackCell>[];
        for (var i = 19; i >= 0; i--) {
          final to = today.subtract(Duration(days: every * i));
          final from = to.subtract(Duration(days: every - 1));
          if (to.isBefore(start)) {
            cells.add(TrackCell.neutral);
            continue;
          }
          var found = false;
          for (var d = from; !d.isAfter(to); d = d.add(const Duration(days: 1))) {
            if (dates.contains(ymdOf(d))) found = true;
          }
          cells.add(found ? TrackCell.hit : (i == 0 ? TrackCell.current : TrackCell.miss));
        }
        return BadgeTrack(cells: cells, caption: '20 dernières échéances (tous les $every j) · ${cells.where((c) => c == TrackCell.hit).length} relevés · ${o.title}', hitLabel: 'relevé noté', missLabel: 'manqué');
      case 'actions':
        final t = daysTrack((y) => (actionsByYmd[y] ?? 0) > 0, what: 'jours avec une action faite', hitLabel: 'action faite', missLabel: 'aucune');
        final total = lastDays(30).fold(0, (s, y) => s + (actionsByYmd[y] ?? 0));
        return BadgeTrack(cells: t.cells, caption: '30 derniers jours · $total actions faites', hitLabel: t.hitLabel, missLabel: t.missLabel);
      case 'malgre-tout':
        return daysTrack((y) => lowWonByYmd[y] ?? false, neutral: (y) => !lowByYmd.contains(y), what: 'victoires sur la flemme', hitLabel: 'fait malgré la flemme', missLabel: 'flemme, rien de fait');
      case 'barometre':
        final pointed = disc.meanByYmd.keys.toSet();
        final first = pointed.isEmpty ? null : (pointed.toList()..sort()).first;
        return daysTrack(pointed.contains, neutral: (y) => first == null || y.compareTo(first) < 0, what: 'jours pointés', hitLabel: 'élan pointé', missLabel: 'pas pointé');
      case 'maree-haute':
        return daysTrack((y) => (disc.meanByYmd[y] ?? 0) >= 4, neutral: (y) => !disc.meanByYmd.containsKey(y), what: 'jours à élan ≥ 4', hitLabel: 'élan ≥ 4', missLabel: 'élan < 4');
      case 'enchaineur':
      case 'plein-jour':
        final runs = chainRuns.toList()..sort((a, b) => a.endedAt.compareTo(b.endedAt));
        final last = runs.length > 20 ? runs.sublist(runs.length - 20) : runs;
        if (last.isEmpty) return null;
        final full = id == 'plein-jour';
        final cells = [for (final r in last) (full ? r.fullDay : chainRunCounts(r)) ? TrackCell.hit : TrackCell.miss];
        return BadgeTrack(cells: cells, caption: '${last.length} dernière${last.length > 1 ? 's' : ''} session${last.length > 1 ? 's' : ''} · ${cells.where((c) => c == TrackCell.hit).length} ${full ? 'journée(s) entière(s)' : 'comptée(s)'}', hitLabel: full ? 'journée entière' : 'comptée (3 choses et plus)', missLabel: full ? 'partielle' : 'moins de 3 choses');
      default:
        return null;
    }
  }

  return BadgeDeck([for (final b in out) b.withTrack(trackOf(b))], embers: embers, reprises: reprisesNow, weeks: weeks);
}

int _currentSolidRun(List<DayScore> days) {
  var n = 0;
  for (var i = days.length - 1; i >= 0; i--) {
    final s = days[i];
    if (s.neutral) continue;
    if (s.solidAt(0.8)) {
      n++;
    } else {
      break;
    }
  }
  return n;
}

/// Clés des paliers acquis (`id#palier`), pour la mémoire des déblocages signalés.
Set<String> acquiredTierKeys(BadgeDeck d) => {
      for (final b in d.badges)
        for (var i = 1; i <= b.paliersDone; i++) '${b.def.id}#$i',
    };

/// Paliers acquis que `seen` ne connaît pas encore.
Set<String> newTierKeys(BadgeDeck d, Set<String> seen) => acquiredTierKeys(d).difference(seen);

/// Blocs de deep work menés au bout : un bloc `kind: "deepwork"` (choisi via
/// « Deep work 90 min ») sur lequel UN chrono TERMINÉ de la même source a couvert
/// au moins [minMin] minutes d'affilée dans son créneau. Un par bloc, dans
/// l'ordre des fins. Un chrono long sans bloc de deep work (Sommeil, séance,
/// activité libre) ne compte pas : le deep work est un choix, pas une durée.
List<DateTime> deepWorkSessions(List<Session> sessions, List<DailySchedule> schedules, {int minMin = 60}) {
  final out = <DateTime>[];
  for (final sch in schedules) {
    final day = DateTime.tryParse(sch.date);
    if (day == null) continue;
    for (final b in sch.blocks) {
      if (b.kind != 'deepwork' || b.status == 'deleted') continue;
      final p = b.startTime.split(':');
      final startMin = (int.tryParse(p[0]) ?? 0) * 60 + (p.length > 1 ? int.tryParse(p[1]) ?? 0 : 0);
      final from = DateTime(day.year, day.month, day.day).add(Duration(minutes: startMin));
      final to = from.add(Duration(minutes: b.durationMin));
      DateTime? reached;
      for (final s in sessions) {
        final end = s.endAt;
        if (s.deleted || end == null) continue;
        final sameSource = b.taskId != null
            ? s.taskId == b.taskId
            : b.activityId != null
                ? s.activityId == b.activityId
                : b.actionId != null && s.actionId == b.actionId;
        if (!sameSource) continue;
        final a = s.startAt.isAfter(from) ? s.startAt : from;
        final z = end.isBefore(to) ? end : to;
        if (z.difference(a).inMinutes >= minMin && (reached == null || z.isBefore(reached))) reached = z;
      }
      if (reached != null) out.add(reached);
    }
  }
  out.sort();
  return out;
}
