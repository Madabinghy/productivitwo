import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/lived_day.dart' show livedDayStart;
import 'package:productivitwo_v1/utils/recharge.dart' show isSleepName;

/// Suivi du sommeil (maquette validée 2026-11-01 « Suivi du sommeil ») : les
/// nuits viennent des chronos Sommeil (même fenêtre que `sleepNights` : de 10 h
/// avant à 7 h après la bascule de la journée vécue qui suit la nuit), la cible
/// du minimum de l'activité Sommeil, le prévu du bloc Sommeil du programme.

const kSleepDefaultTargetMin = 450; // 7 h 30
const kSleepImpactMinNights = 5;

typedef SleepSpan = ({DateTime start, DateTime end});

class SleepNight {
  /// Bascule de la journée vécue qui suit la nuit (le « lendemain »).
  final DateTime pivot;
  /// Chronos de la nuit, dans l'ordre ; un réveil = le trou entre deux.
  final List<SleepSpan> spans;
  const SleepNight(this.pivot, this.spans);

  DateTime get bed => spans.first.start;
  DateTime get wake => spans.last.end;
  int get minutes => spans.fold(0, (s, x) => s + x.end.difference(x.start).inMinutes);
  int get awakeMin => wake.difference(bed).inMinutes - minutes;
  /// `YYYY-MM-DD` du lendemain (journée vécue qui commence à [pivot]).
  String get nextYmd => _ymd(pivot);
}

String _ymd(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

Set<String> sleepActivityIds(List<Activity> activities) => {for (final a in activities) if (!a.deleted && isSleepName(a.name)) a.id};

/// L'activité Sommeil (activité-temps), s'il y en a une.
Activity? sleepActivityOf(List<Activity> activities) =>
    activities.where((a) => !a.deleted && a.type == 'time' && isSleepName(a.name)).firstOrNull;

/// Cible d'une nuit : le minimum de l'activité Sommeil s'il ressemble à une
/// nuit (≥ 4 h), sinon 7 h 30.
int sleepTargetMin(Activity? sleep) {
  final g = sleep?.goalMin ?? 0;
  return g >= 240 ? g : kSleepDefaultTargetMin;
}

/// Les [nights] dernières nuits, la plus ancienne d'abord (null = aucun chrono
/// Sommeil). Comme `sleepNights` : la dernière case est la nuit qui vient dès
/// qu'un chrono de sommeil y a commencé, sinon la nuit passée ; un chrono qui
/// tourne compte jusqu'à [now].
List<SleepNight?> sleepNightList({
  required List<Session> sessions,
  required List<Activity> activities,
  required DateTime now,
  required int dayStartMin,
  int nights = 14,
}) {
  final ids = sleepActivityIds(activities);
  final pivot = livedDayStart(now, dayStartMin);
  final next = _night(sessions, ids, pivot.add(const Duration(days: 1)), now);
  final last = next != null ? pivot.add(const Duration(days: 1)) : pivot;
  return [for (var k = nights - 1; k >= 0; k--) _night(sessions, ids, DateTime(last.year, last.month, last.day - k, last.hour, last.minute), now)];
}

SleepNight? _night(List<Session> sessions, Set<String> ids, DateTime pivot, DateTime now) {
  if (ids.isEmpty) return null;
  final from = pivot.subtract(const Duration(hours: 10));
  final to = pivot.add(const Duration(hours: 7));
  final spans = <SleepSpan>[];
  for (final s in sessions) {
    if (s.deleted || !ids.contains(s.activityId)) continue;
    if (s.startAt.isBefore(from) || !s.startAt.isBefore(to) || s.startAt.isAfter(now)) continue;
    final end = s.endAt ?? now;
    if (!end.isAfter(s.startAt)) continue;
    spans.add((start: s.startAt, end: end));
  }
  if (spans.isEmpty) return null;
  spans.sort((a, b) => a.start.compareTo(b.start));
  // Chronos qui se chevauchent (doublon) : fusionnés, jamais comptés deux fois.
  final merged = <SleepSpan>[spans.first];
  for (final s in spans.skip(1)) {
    final l = merged.last;
    if (!s.start.isAfter(l.end)) {
      merged[merged.length - 1] = (start: l.start, end: s.end.isAfter(l.end) ? s.end : l.end);
    } else {
      merged.add(s);
    }
  }
  return SleepNight(pivot, merged);
}

/// Minutes d'une heure ramenées autour de minuit (18:00 → 18:00) : 23:40 = −20,
/// 00:20 = +20, pour moyenner des couchers de part et d'autre de minuit.
int bedClockMin(DateTime t) {
  final m = t.hour * 60 + t.minute;
  return m >= 18 * 60 ? m - 24 * 60 : m;
}

/// Inverse de [bedClockMin] : « 23:45 ».
String clockOf(int m) {
  final v = ((m % 1440) + 1440) % 1440;
  return '${(v ~/ 60).toString().padLeft(2, '0')}:${(v % 60).toString().padLeft(2, '0')}';
}

class SleepStats {
  final int nights; // nuits avec un chrono
  final int? avgMin;
  final int debtMin; // ce qui manque à la cible, nuit par nuit
  final int? avgBed; // horloge autour de minuit (bedClockMin)
  final int? avgWake; // minutes depuis minuit
  final int? spreadMin; // écart moyen du coucher à sa moyenne
  const SleepStats({required this.nights, this.avgMin, required this.debtMin, this.avgBed, this.avgWake, this.spreadMin});
}

SleepStats sleepStats(Iterable<SleepNight?> nights, int targetMin) {
  final ns = nights.whereType<SleepNight>().toList();
  if (ns.isEmpty) return const SleepStats(nights: 0, debtMin: 0);
  final total = ns.fold<int>(0, (s, n) => s + n.minutes);
  final debt = ns.fold<int>(0, (s, n) => s + (targetMin - n.minutes).clamp(0, targetMin));
  final beds = [for (final n in ns) bedClockMin(n.bed)];
  final avgBed = (beds.reduce((a, b) => a + b) / beds.length).round();
  final spread = (beds.fold<int>(0, (s, b) => s + (b - avgBed).abs()) / beds.length).round();
  final wakes = [for (final n in ns) n.wake.hour * 60 + n.wake.minute];
  return SleepStats(
    nights: ns.length,
    avgMin: (total / ns.length).round(),
    debtMin: debt,
    avgBed: avgBed,
    avgWake: (wakes.reduce((a, b) => a + b) / wakes.length).round(),
    spreadMin: spread,
  );
}

/// Le bloc Sommeil d'un programme (titre ou activité de sommeil), à faire ou
/// fait : début (horloge autour de minuit) et durée.
({int bed, int durationMin})? sleepBlockOf(DailySchedule? s, Set<String> sleepIds) {
  if (s == null) return null;
  for (final b in s.blocks) {
    if (b.status == 'deleted' || b.status == 'skipped') continue;
    if (!isSleepName(b.title) && !sleepIds.contains(b.activityId)) continue;
    final p = b.startTime.split(':');
    if (p.length < 2) continue;
    final h = int.tryParse(p[0]), m = int.tryParse(p[1]);
    if (h == null || m == null) continue;
    final clock = h * 60 + m;
    return (bed: clock >= 18 * 60 ? clock - 24 * 60 : clock, durationMin: b.durationMin);
  }
  return null;
}

/// Le coucher prévu : le bloc Sommeil le plus récent parmi ces programmes
/// (du plus ancien au plus récent).
({int bed, int durationMin})? plannedSleep(List<DailySchedule> schedules, Set<String> sleepIds) {
  for (final s in schedules.reversed) {
    final b = sleepBlockOf(s, sleepIds);
    if (b != null) return b;
  }
  return null;
}

/// Le lendemain d'une nuit, vu par le reste de l'app.
class SleepNextDay {
  final double? elan; // élan moyen pondéré
  final double? lowShare; // part du temps dit passé en Flemme (0..1)
  final int actions; // actions cochées dans la journée vécue
  final bool perfect;
  const SleepNextDay({this.elan, this.lowShare, this.actions = 0, this.perfect = false});
}

class SleepSide {
  final int days;
  final double? elan;
  final double? lowShare;
  final double actions;
  final int perfect;
  const SleepSide({required this.days, this.elan, this.lowShare, required this.actions, required this.perfect});
}

class SleepImpact {
  final SleepSide long; // nuits ≥ cible − 30 min
  final SleepSide short; // nuits < cible − 60 min
  final int longMin, shortMin; // seuils
  const SleepImpact(this.long, this.short, this.longMin, this.shortMin);
  bool get enough => long.days >= kSleepImpactMinNights && short.days >= kSleepImpactMinNights;

  /// La phrase du bas : la flemme double / l'élan baisse / pas de différence.
  String? get sentence {
    if (!enough) return null;
    final l = long.lowShare, s = short.lowShare;
    if (l != null && s != null && s >= 0.05 && l > 0 && s / l >= 1.8) return 'Une nuit courte, et ta flemme double le lendemain.';
    if (l != null && s != null && s - l >= 0.1) return 'Après une nuit courte, tu passes plus de temps en Flemme.';
    final le = long.elan, se = short.elan;
    if (le != null && se != null && le - se >= 0.5) return 'Après une nuit courte, ton élan baisse nettement.';
    if (long.actions - short.actions >= 1.5) return 'Après une nuit courte, tu fais moins de choses.';
    return 'Pas de différence nette pour l’instant entre nuits longues et courtes.';
  }
}

/// Nuits longues contre nuits courtes, d'après leur lendemain. Les nuits entre
/// les deux seuils ne comptent ni d'un côté ni de l'autre ; un lendemain encore
/// en cours non plus (`nextYmd` ≥ [todayYmd]).
SleepImpact sleepImpact(Iterable<SleepNight?> nights, Map<String, SleepNextDay> nextDays, int targetMin, String todayYmd) {
  final longMin = targetMin - 30, shortMin = targetMin - 60;
  final long = <SleepNextDay>[], short = <SleepNextDay>[];
  for (final n in nights.whereType<SleepNight>()) {
    if (n.nextYmd.compareTo(todayYmd) >= 0) continue;
    final d = nextDays[n.nextYmd];
    if (d == null) continue;
    if (n.minutes >= longMin) {
      long.add(d);
    } else if (n.minutes < shortMin) {
      short.add(d);
    }
  }
  return SleepImpact(_side(long), _side(short), longMin, shortMin);
}

SleepSide _side(List<SleepNextDay> ds) {
  double? avg(Iterable<double?> xs) {
    final v = xs.whereType<double>().toList();
    return v.isEmpty ? null : v.reduce((a, b) => a + b) / v.length;
  }

  return SleepSide(
    days: ds.length,
    elan: avg(ds.map((d) => d.elan)),
    lowShare: avg(ds.map((d) => d.lowShare)),
    actions: ds.isEmpty ? 0 : ds.fold<int>(0, (s, d) => s + d.actions) / ds.length,
    perfect: ds.where((d) => d.perfect).length,
  );
}

/// Couché ce soir à quelle heure pour [nightMin] avec le lever habituel ?
int bedFor(int wakeMin, int nightMin) => wakeMin - nightMin;

/// « 6 h 10 » / « 45 min » / « 0 min ».
String fmtNight(int min) {
  if (min <= 0) return '0 min';
  return min < 60 ? '$min min' : '${min ~/ 60} h ${(min % 60).toString().padLeft(2, '0')}';
}
