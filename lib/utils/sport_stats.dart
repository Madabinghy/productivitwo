import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/engagement_stats.dart' show ymdOf;
import 'package:productivitwo_v1/utils/lived_day.dart' show livedDate;

/// Suivi du sport (maquette validée 2026-11-01 « Suivi du sport ») : rien à
/// saisir. Les séances viennent des chronos des activités de sport (≥ 10 min
/// dans la journée vécue, plusieurs chronos de la même activité = une séance)
/// et des +1 des routines de séance (Footing, Aller à la salle) sans chrono ce
/// jour-là ; les routines de répétitions (Pompes, Tractions) se comptent à part
/// et ne font pas une séance.

const kSportSessionMin = 10;
const kSportImpactMinDays = 5;
const kSportWeeks = 8;

/// Domaines lus comme « sport » par défaut.
bool isSportDomainName(String name) {
  final n = name.toLowerCase();
  const keys = ['sport', 'muscu', 'fitness', 'course', 'running', 'natation', 'yoga', 'vélo', 'velo', 'gym', 'cardio', 'entraînement', 'entrainement'];
  return keys.any(n.contains);
}

enum SportKind { session, sessionRoutine, reps }

/// Rôle d'une activité dans le suivi : chrono = séance ; routine quotidienne
/// à cible ≥ 5 = répétitions ; autre routine = routine de séance.
SportKind sportKindOf(Activity a) {
  if (a.type != 'habit') return SportKind.session;
  if (a.effHabitFreq == HabitFreq.daily && a.effHabitTarget >= 5) return SportKind.reps;
  return SportKind.sessionRoutine;
}

/// Réglage « Mes activités de sport » : `data/meta.sportPick {add, remove}`.
class SportOverrides {
  final Set<String> add;
  final Set<String> remove;
  const SportOverrides({this.add = const {}, this.remove = const {}});

  static SportOverrides from(Object? raw) {
    if (raw is! Map) return const SportOverrides();
    Set<String> ids(Object? v) => v is List ? {for (final x in v) '$x'} : const {};
    return SportOverrides(add: ids(raw['add']), remove: ids(raw['remove']));
  }

  Map<String, dynamic> toJson() => {'add': add.toList()..sort(), 'remove': remove.toList()..sort()};

  /// Bascule une activité, en partant de ce que donnent les domaines par défaut.
  SportOverrides toggled(String id, {required bool byDefault, required bool on}) {
    final a = {...add}..remove(id);
    final r = {...remove}..remove(id);
    if (on && !byDefault) a.add(id);
    if (!on && byDefault) r.add(id);
    return SportOverrides(add: a, remove: r);
  }

  bool sameAs(SportOverrides o) => add.length == o.add.length && remove.length == o.remove.length && add.containsAll(o.add) && remove.containsAll(o.remove);
}

class SportPick {
  final Map<String, SportKind> kinds;
  final Map<String, Activity> byId;
  const SportPick(this.kinds, this.byId);

  bool get isEmpty => kinds.isEmpty;
  Iterable<Activity> of(SportKind k) => [for (final e in kinds.entries) if (e.value == k && byId[e.key] != null) byId[e.key]!];
  List<Activity> get sessionActivities => of(SportKind.session).toList();
  List<Activity> get sessionRoutines => of(SportKind.sessionRoutine).toList();
  List<Activity> get repRoutines => of(SportKind.reps).toList();
  bool contains(String id) => kinds.containsKey(id);
}

/// Activités vivantes des domaines de sport.
Set<String> defaultSportIds(List<Activity> activities, List<Domain> domains) {
  final sportDomains = {for (final d in domains) if (!d.deleted && isSportDomainName(d.name)) d.id};
  return {for (final a in activities) if (!a.deleted && sportDomains.contains(a.domainId)) a.id};
}

SportPick resolveSportPick(List<Activity> activities, List<Domain> domains, [SportOverrides o = const SportOverrides()]) {
  final ids = {...defaultSportIds(activities, domains), ...o.add}..removeAll(o.remove);
  final byId = {for (final a in activities) if (!a.deleted) a.id: a};
  return SportPick({for (final id in ids) if (byId[id] != null) id: sportKindOf(byId[id]!)}, byId);
}

class SportDay {
  final String ymd;
  final Map<String, int> minutes; // activité de séance → minutes (tous chronos)
  final List<String> sessionIds; // activités ou routines qui font une séance ce jour
  final Map<String, int> reps; // routine de répétitions → nombre
  const SportDay(this.ymd, this.minutes, this.sessionIds, this.reps);

  int get sessions => sessionIds.length;
  bool get isRest => sessionIds.isEmpty;
  bool get repsOnly => isRest && reps.values.any((v) => v > 0);
  int get activeMin => minutes.values.fold(0, (s, v) => s + v);
}

DateTime _d(String ymd) {
  final p = ymd.split('-').map(int.parse).toList();
  return DateTime(p[0], p[1], p[2]);
}

String _plus(String ymd, int days) {
  final d = _d(ymd);
  return ymdOf(DateTime(d.year, d.month, d.day + days));
}

/// Les journées vécues [fromYmd] → [toYmd], dans l'ordre.
List<SportDay> sportDays({
  required SportPick pick,
  required List<Session> sessions,
  required List<HabitHit> hits,
  required String fromYmd,
  required String toYmd,
  required DateTime now,
  required int dayStartMin,
}) {
  final sessionIds = {for (final a in pick.sessionActivities) a.id};
  final minutes = <String, Map<String, int>>{};
  for (final s in sessions) {
    if (s.deleted || !sessionIds.contains(s.activityId) || s.startAt.isAfter(now)) continue;
    final end = s.endAt ?? now;
    if (!end.isAfter(s.startAt)) continue;
    final ymd = ymdOf(livedDate(s.startAt, dayStartMin));
    if (ymd.compareTo(fromYmd) < 0 || ymd.compareTo(toYmd) > 0) continue;
    final m = minutes.putIfAbsent(ymd, () => {});
    m[s.activityId] = (m[s.activityId] ?? 0) + end.difference(s.startAt).inMinutes;
  }
  final routineIds = {for (final a in pick.sessionRoutines) a.id};
  final repIds = {for (final a in pick.repRoutines) a.id};
  final routineHits = <String, Map<String, int>>{};
  final reps = <String, Map<String, int>>{};
  for (final h in hits) {
    final isR = routineIds.contains(h.habitId), isP = repIds.contains(h.habitId);
    if (!isR && !isP) continue;
    final ymd = ymdOf(livedDate(h.ts, dayStartMin));
    if (ymd.compareTo(fromYmd) < 0 || ymd.compareTo(toYmd) > 0) continue;
    final m = (isR ? routineHits : reps).putIfAbsent(ymd, () => {});
    m[h.habitId] = (m[h.habitId] ?? 0) + 1;
  }
  final out = <SportDay>[];
  for (var ymd = fromYmd; ymd.compareTo(toYmd) <= 0; ymd = _plus(ymd, 1)) {
    final m = minutes[ymd] ?? const {};
    final chrono = [for (final e in m.entries) if (e.value >= kSportSessionMin) e.key];
    final ids = [...chrono];
    for (final e in (routineHits[ymd] ?? const <String, int>{}).entries) {
      if (e.value <= 0) continue;
      final linked = pick.byId[e.key]?.linkedActivityId;
      final covered = linked != null ? chrono.contains(linked) : chrono.isNotEmpty;
      if (!covered) ids.add(e.key);
    }
    out.add(SportDay(ymd, m, ids, reps[ymd] ?? const {}));
  }
  return out;
}

/// Lundi (`YYYY-MM-DD`) de la semaine qui contient [ymd].
String mondayOf(String ymd) {
  final d = _d(ymd);
  return ymdOf(DateTime(d.year, d.month, d.day - (d.weekday - 1)));
}

class SportSummary {
  final List<SportDay> week; // lundi → dimanche de la semaine en cours
  final int weekMin;
  final int weekSessions;
  final int weekRestDays; // jours passés (aujourd'hui exclu s'il est vide) sans séance
  final int sessions7; // 7 derniers jours, aujourd'hui compris
  final int weeksWithThree; // sur les [kSportWeeks] dernières semaines, la courante comprise
  final int longestRest; // plus long repos (jours d'affilée) sur 30 jours
  const SportSummary(this.week, this.weekMin, this.weekSessions, this.weekRestDays, this.sessions7, this.weeksWithThree, this.longestRest);
}

/// [days] = au moins les 8 dernières semaines jusqu'à aujourd'hui (dernier = aujourd'hui).
SportSummary sportSummary(List<SportDay> days) {
  final today = days.last.ymd;
  final monday = mondayOf(today);
  final week = [
    for (var i = 0; i < 7; i++) days.where((d) => d.ymd == _plus(monday, i)).firstOrNull ?? SportDay(_plus(monday, i), const {}, const [], const {}),
  ];
  final upToToday = week.where((d) => d.ymd.compareTo(today) <= 0);
  final rest = upToToday.where((d) => d.isRest && d.ymd != today).length;
  final last7 = days.length >= 7 ? days.sublist(days.length - 7) : days;
  var three = 0;
  for (var w = 0; w < kSportWeeks; w++) {
    final m = _plus(monday, -7 * w);
    final n = days.where((d) => mondayOf(d.ymd) == m).fold(0, (s, d) => s + d.sessions);
    if (n >= 3) three++;
  }
  final last30 = days.length >= 30 ? days.sublist(days.length - 30) : days;
  var run = 0, best = 0;
  for (final d in last30) {
    if (d.ymd == today && d.isRest) break;
    run = d.isRest ? run + 1 : 0;
    if (run > best) best = run;
  }
  return SportSummary(
    week,
    week.fold(0, (s, d) => s + d.activeMin),
    week.fold(0, (s, d) => s + d.sessions),
    rest,
    last7.fold(0, (s, d) => s + d.sessions),
    three,
    best,
  );
}

class SportWeekVolume {
  final String monday;
  final Map<String, int> minutes;
  const SportWeekVolume(this.monday, this.minutes);
  int get total => minutes.values.fold(0, (s, v) => s + v);
}

/// Temps actif par semaine calendaire, la plus ancienne d'abord, la dernière =
/// la semaine en cours.
List<SportWeekVolume> sportWeeks(List<SportDay> days, {int weeks = kSportWeeks}) {
  final monday = mondayOf(days.last.ymd);
  return [
    for (var w = weeks - 1; w >= 0; w--)
      () {
        final m = _plus(monday, -7 * w);
        final out = <String, int>{};
        for (final d in days.where((d) => mondayOf(d.ymd) == m)) {
          d.minutes.forEach((k, v) => out[k] = (out[k] ?? 0) + v);
        }
        return SportWeekVolume(m, out);
      }(),
  ];
}

/// « La Musculation baisse depuis 4 semaines » : moyenne des 4 dernières
/// semaines closes < moitié des 4 d'avant (qui faisaient ≥ 30 min / sem).
({String activityId, int recentMin, int priorMin})? sportDecline(List<SportWeekVolume> weeks) {
  if (weeks.length < 9) return null;
  final closed = weeks.sublist(weeks.length - 9, weeks.length - 1);
  final ids = {for (final w in closed) ...w.minutes.keys};
  ({String activityId, int recentMin, int priorMin})? worst;
  for (final id in ids) {
    int avg(Iterable<SportWeekVolume> ws) => (ws.fold(0, (s, w) => s + (w.minutes[id] ?? 0)) / 4).round();
    final prior = avg(closed.take(4)), recent = avg(closed.skip(4));
    if (prior < 30 || recent * 2 >= prior) continue;
    if (worst == null || prior - recent > worst.priorMin - worst.recentMin) worst = (activityId: id, recentMin: recent, priorMin: prior);
  }
  return worst;
}

class RepsStat {
  final Activity activity;
  final int week; // cette semaine
  final int weekTarget; // cible quotidienne × 7
  final int record; // meilleur jour
  final List<int> weeks; // [kSportWeeks] semaines, la courante en dernier
  const RepsStat(this.activity, this.week, this.weekTarget, this.record, this.weeks);
}

/// Répétitions : [allHits] pour le record (toute l'histoire), [days] pour les semaines.
List<RepsStat> repsStats(SportPick pick, List<SportDay> days, List<HabitHit> allHits, int dayStartMin) {
  final monday = mondayOf(days.last.ymd);
  return [
    for (final a in pick.repRoutines)
      () {
        final perDay = <String, int>{};
        for (final h in allHits) {
          if (h.habitId != a.id) continue;
          final y = ymdOf(livedDate(h.ts, dayStartMin));
          perDay[y] = (perDay[y] ?? 0) + 1;
        }
        final weeks = [
          for (var w = kSportWeeks - 1; w >= 0; w--)
            days.where((d) => mondayOf(d.ymd) == _plus(monday, -7 * w)).fold(0, (s, d) => s + (d.reps[a.id] ?? 0)),
        ];
        return RepsStat(a, weeks.last, a.effHabitTarget * 7, perDay.values.fold(0, (m, v) => v > m ? v : m), weeks);
      }(),
  ];
}

class SportCommitment {
  final Activity activity;
  final int target; // minutes / semaine (temps) ou fois / semaine (routine)
  final int done;
  final bool isTime;
  const SportCommitment(this.activity, this.target, this.done, this.isTime);
  double get ratio => target <= 0 ? 1 : done / target;
}

/// Engagements des objectifs actifs sur les activités de sport (cette semaine).
List<SportCommitment> sportCommitments(SportPick pick, List<StrategicObjective> objectives, List<SportDay> week) {
  final time = <String, int>{}, routine = <String, int>{};
  for (final o in objectives.where((o) => o.status == 'active')) {
    for (final c in o.timeCommitments) {
      if (pick.kinds[c.activityId] == SportKind.session && c.weeklyMin > (time[c.activityId] ?? 0)) time[c.activityId] = c.weeklyMin;
    }
    for (final c in o.routineCommitments) {
      final a = pick.byId[c.activityId];
      if (a == null || pick.kinds[c.activityId] != SportKind.sessionRoutine) continue;
      routine[c.activityId] = a.effHabitFreq == HabitFreq.daily ? a.effHabitTarget * 7 : a.effHabitTarget;
    }
  }
  return [
    for (final e in time.entries)
      SportCommitment(pick.byId[e.key]!, e.value, week.fold(0, (s, d) => s + (d.minutes[e.key] ?? 0)), true),
    for (final e in routine.entries)
      SportCommitment(pick.byId[e.key]!, e.value, week.fold(0, (s, d) => s + (d.sessionIds.contains(e.key) ? 1 : 0)), false),
  ];
}

/// L'objectif chiffré qui engage le sport (le poids) : actif, avec métrique,
/// qui engage au moins une activité suivie ; celui qui a des relevés d'abord.
StrategicObjective? sportObjective(SportPick pick, List<StrategicObjective> objectives) {
  final cands = objectives.where((o) =>
      o.status == 'active' &&
      o.metric != null &&
      (o.timeCommitments.any((c) => pick.contains(c.activityId)) || o.routineCommitments.any((c) => pick.contains(c.activityId))));
  final list = cands.toList()..sort((a, b) => b.readings.length.compareTo(a.readings.length));
  return list.firstOrNull;
}

/// « Lancer une séance » : les activités de séance, du plus en retard (part de
/// l'engagement de la semaine) au plus avancé, puis les autres par temps.
List<Activity> sportLaunchOrder(SportPick pick, List<SportCommitment> commitments, List<SportDay> week, {bool Function(Activity a)? paused}) {
  final ratio = {for (final c in commitments.where((c) => c.isTime)) c.activity.id: c.ratio};
  int min(String id) => week.fold(0, (s, d) => s + (d.minutes[id] ?? 0));
  final list = pick.sessionActivities.where((a) => paused == null || !paused(a)).toList()
    ..sort((a, b) {
      final ra = ratio[a.id], rb = ratio[b.id];
      if (ra != null && rb != null) return ra.compareTo(rb);
      if (ra != null) return -1;
      if (rb != null) return 1;
      return min(b.id).compareTo(min(a.id));
    });
  return list;
}

class SportSide {
  final int days;
  final double? lowShare; // part du temps dit en Flemme le lendemain
  final int? sleepMin; // nuit moyenne qui suit
  const SportSide(this.days, this.lowShare, this.sleepMin);
}

class SportImpact {
  final SportSide after; // lendemain d'une séance
  final SportSide without; // lendemain d'un jour sans
  const SportImpact(this.after, this.without);
  bool get enough => after.days >= kSportImpactMinDays && without.days >= kSportImpactMinDays;
}

/// Lendemains des journées closes de [days] (le lendemain doit être clos aussi).
/// [lowShareByYmd] : part de Flemme d'un jour (seulement les jours où l'élan
/// est dit) ; [nightAfterByYmd] : minutes de la nuit qui suit un jour.
SportImpact sportImpact(List<SportDay> days, Map<String, double> lowShareByYmd, Map<String, int> nightAfterByYmd, String todayYmd) {
  final a = <(double, int?)>[], w = <(double, int?)>[];
  for (final d in days) {
    final next = _plus(d.ymd, 1);
    if (next.compareTo(todayYmd) >= 0) continue;
    final low = lowShareByYmd[next];
    if (low == null) continue;
    (d.isRest ? w : a).add((low, nightAfterByYmd[d.ymd]));
  }
  SportSide side(List<(double, int?)> xs) {
    if (xs.isEmpty) return const SportSide(0, null, null);
    final nights = [for (final x in xs) if (x.$2 != null) x.$2!];
    return SportSide(xs.length, xs.fold(0.0, (s, x) => s + x.$1) / xs.length, nights.isEmpty ? null : (nights.fold(0, (s, n) => s + n) / nights.length).round());
  }

  return SportImpact(side(a), side(w));
}
