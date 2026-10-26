import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/elan_logic.dart';
import 'package:productivitwo_v1/utils/engagement_stats.dart' show ymdOf, mondayOf;
import 'package:productivitwo_v1/utils/lived_day.dart';
import 'package:productivitwo_v1/utils/objective_trajectory.dart';

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
}

/// L'état d'un badge pour une personne : paliers atteints, mesure courante,
/// date d'obtention de chaque palier, faits à montrer dans la fiche.
class BadgeState {
  final BadgeDef def;
  final int level;
  final num value;
  final List<DateTime?> tierDates;
  final List<(String, String)> facts;

  const BadgeState({
    required this.def,
    required this.level,
    required this.value,
    this.tierDates = const [],
    this.facts = const [],
  });

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

class BadgeDeck {
  final List<BadgeState> badges;
  const BadgeDeck(this.badges);

  int get total => badges.fold(0, (s, b) => s + b.paliersTotal);
  int get acquired => badges.fold(0, (s, b) => s + b.paliersDone);

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
List<(DateTime, int)> _runsOf(Set<String> days) {
  final sorted = days.map((s) => DateTime.parse(s)).toList()..sort();
  final runs = <(DateTime, int)>[];
  DateTime? start;
  DateTime? prev;
  var len = 0;
  for (final d in sorted) {
    if (prev != null && d.difference(prev).inDays == 1) {
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
int _currentRun(Set<String> days, DateTime today) {
  var d = _day(today);
  if (!days.contains(ymdOf(d))) d = d.subtract(const Duration(days: 1));
  var n = 0;
  while (days.contains(ymdOf(d)) && n < 3650) {
    n++;
    d = d.subtract(const Duration(days: 1));
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

RoutineSeries routineSeries(Activity a, List<HabitHit> hits, DateTime now, {int dayStartMin = kDefaultDayStartMin}) {
  final days = routineReachedDays(a, hits, dayStartMin: dayStartMin);
  final runs = _runsOf(days);
  final longest = runs.fold(0, (m, r) => r.$2 > m ? r.$2 : m);
  final today = livedDate(now, dayStartMin);
  DateTime? first;
  for (final h in hits) {
    if (h.habitId != a.id) continue;
    if (first == null || h.ts.isBefore(first)) first = h.ts;
  }
  final since = first == null ? 0 : today.difference(_day(livedDate(first, dayStartMin))).inDays + 1;
  return RoutineSeries(
    current: _currentRun(days, today),
    longest: longest,
    reachedDays: days.length,
    sinceDays: since,
    tierDates: _tierDatesFromRuns(kRoutineTiers, runs),
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

bool _countsForDay(ScheduleBlock b) =>
    b.kind == 'normal' && b.gcalEventId == null && (b.status == 'done' || b.status == 'pending');

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
      if (!_countsForDay(b)) continue;
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
({int current, int longest, List<(DateTime, int)> runs}) trajectoryWeeks(
    StrategicObjective o, List<Session> sessions, DateTime now) {
  final hasMeans = o.timeCommitments.isNotEmpty;
  final hasResult = o.metric != null;
  if (!hasMeans && !hasResult) return (current: 0, longest: 0, runs: const []);
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
  return (current: current, longest: longest, runs: realRuns);
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
  int dayStartMin = kDefaultDayStartMin,
}) {
  final out = <BadgeState>[];

  // Séries de routine : un badge par routine quotidienne active, par nom.
  final routines = activities.where((a) => !a.deleted && a.isHabit && a.habitFreq == HabitFreq.daily).toList()
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  for (final a in routines) {
    final s = routineSeries(a, habitHits, now, dayStartMin: dayStartMin);
    out.add(BadgeState(
      def: BadgeDef(id: 'serie-${a.id}', family: BadgeFamily.routines, name: a.name, symbol: 'flame', tiers: kRoutineTiers, unit: 'j', unitLong: 'jours', subjectId: a.id),
      level: _levelOf(kRoutineTiers, s.longest),
      value: s.current,
      tierDates: s.tierDates,
      facts: [
        ('Série en cours', _plural(s.current, 'jour', 'jours')),
        ('Série la plus longue', _plural(s.longest, 'jour', 'jours')),
        if (s.sinceDays > 0) ('Jours atteints sur ${s.sinceDays}', '${s.reachedDays}'),
      ],
    ));
  }

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
  for (final o in objectives) {
    if (o.status == 'archived') continue;
    final t = trajectoryWeeks(o, sessions, now);
    if (t.longest > trajLongest || trajBest == null) {
      trajLongest = t.longest;
      trajRuns = t.runs;
      trajBest = o.title;
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
  for (final o in objectives) {
    final f = faithfulReadings(o);
    if (f.longest > readLongest) {
      readLongest = f.longest;
      readDates = f.tierDates;
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

  // Journées.
  final days = scoreDays(activities: activities, hits: habitHits, schedules: schedules, now: now, dayStartMin: dayStartMin);
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
  // Enchaîner : pas encore de donnée source (sessions menées au bout).
  for (final (id, name, symbol, tiers, label, unit, unitLong) in [
    ('enchaineur', 'Enchaîneur', 'chain', const [10], '×10', 'sessions', 'sessions'),
    ('plein-jour', 'Plein jour', 'sunrise', const [1], 'Plein', '', ''),
  ]) {
    out.add(BadgeState(
      def: BadgeDef(id: id, family: BadgeFamily.chain, name: name, symbol: symbol, tiers: tiers, label: label, unit: unit, unitLong: unitLong, measured: false),
      level: 0,
      value: 0,
      facts: const [('Mesure', 'pas encore disponible')],
    ));
  }

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

  return BadgeDeck(out);
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
