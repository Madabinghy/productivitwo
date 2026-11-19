import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/engagement_stats.dart' show ymdOf;
import 'package:productivitwo_v1/utils/lived_day.dart';

/// Routines « sur 7 jours » (2026-11-19, maquette validée « Routines sur 7 jours ») :
/// une routine quotidienne réglée `rolling` se compte sur les 7 derniers jours.
/// Ce qui est fait en plus couvre les jours suivants ; le retard, lui, ne
/// s'accumule pas : un jour sans avance demande la cible normale, jamais plus.

/// Fenêtre glissante, aujourd'hui compris.
const int kRoutineWindowDays = 7;

/// Cible par jour d'une routine quotidienne (1 au moins).
int routineDayTargetOf(Activity a) {
  final t = a.habitTarget ?? 1;
  return t <= 0 ? 1 : t;
}

bool isRollingRoutine(Activity a) => a.isHabit && a.habitFreq == HabitFreq.daily && a.rolling;

/// Ce qu'un jour demande d'après les 6 jours d'avant : l'avance le réduit
/// (jusqu'à zéro), le retard ne l'augmente pas.
int rollingDayTarget(int target, int pastSum) {
  final need = kRoutineWindowDays * target - pastSum;
  if (need <= 0) return 0;
  return need > target ? target : need;
}

DateTime _d(DateTime x) => DateTime(x.year, x.month, x.day);

/// Coches par jour vécu (`YYYY-MM-DD`).
Map<String, int> routineDayCounts(Activity a, List<HabitHit> hits, {int dayStartMin = kDefaultDayStartMin}) {
  final counts = <String, int>{};
  for (final h in hits) {
    if (h.habitId != a.id) continue;
    final k = ymdOf(livedDate(h.ts, dayStartMin));
    counts[k] = (counts[k] ?? 0) + 1;
  }
  return counts;
}

/// Où en est une routine « sur 7 jours » aujourd'hui.
class RoutineCover {
  /// Cible par jour.
  final int target;
  final int todayDone;
  /// Coches des 6 jours passés de la fenêtre.
  final int pastDone;
  /// Ce qu'aujourd'hui demande (0 = l'avance couvre la journée).
  final int dayTarget;
  /// Jours À VENIR déjà couverts si rien d'autre n'est fait.
  final int aheadDays;
  /// Ce que demain demandera si rien d'autre n'est fait aujourd'hui.
  final int tomorrowTarget;
  /// La journée vécue du calcul.
  final DateTime today;
  const RoutineCover({
    required this.today,
    required this.target,
    required this.todayDone,
    required this.pastDone,
    required this.dayTarget,
    required this.aheadDays,
    required this.tomorrowTarget,
  });

  /// La journée est tenue : la part du jour est faite, ou l'avance la couvre.
  bool get held => todayDone >= dayTarget;
  int get left => held ? 0 : dayTarget - todayDone;
  /// Tenue sans rien faire aujourd'hui.
  bool get coveredByAdvance => dayTarget == 0;
  int get windowDone => pastDone + todayDone;
  int get windowTarget => kRoutineWindowDays * target;
  /// Tenue ce soir, mais demain demandera quelque chose : c'est là qu'on
  /// peut prendre de l'avance.
  bool get canGetAhead => held && aheadDays == 0 && tomorrowTarget > 0;

  /// Ce que l'avance tient : « couverte jusqu'à samedi », « couverte par ton
  /// avance » (aujourd'hui seulement) ; null si la journée n'est pas tenue ou
  /// l'est par les coches du jour, sans avance pour demain.
  String? get heldLabel {
    if (!held) return null;
    if (aheadDays > 0) return 'couverte jusqu\'à ${coveredUntilLabel(today, aheadDays)}';
    if (coveredByAdvance) return 'couverte par ton avance';
    return null;
  }
}

/// [now] = l'instant ; « aujourd'hui » est la journée vécue.
RoutineCover routineCover(Activity a, List<HabitHit> hits, DateTime now, {int dayStartMin = kDefaultDayStartMin}) {
  final t = routineDayTargetOf(a);
  final counts = routineDayCounts(a, hits, dayStartMin: dayStartMin);
  final today = _d(livedDate(now, dayStartMin));
  int on(int back) => counts[ymdOf(today.subtract(Duration(days: back)))] ?? 0;
  // window[0] = il y a 6 jours … window[5] = hier.
  final window = [for (var i = kRoutineWindowDays - 1; i >= 1; i--) on(i)];
  final past = window.fold<int>(0, (s, v) => s + v);
  final todayDone = on(0);
  final dayTarget = rollingDayTarget(t, past);
  // Les jours suivants, sans rien faire de plus.
  final future = [...window, todayDone];
  int nextTarget() => rollingDayTarget(t, future.skip(future.length - (kRoutineWindowDays - 1)).fold<int>(0, (s, v) => s + v));
  final tomorrow = nextTarget();
  var ahead = 0;
  if (todayDone >= dayTarget) {
    while (ahead < kRoutineWindowDays - 1 && nextTarget() == 0) {
      ahead++;
      future.add(0);
    }
  }
  return RoutineCover(today: today, target: t, todayDone: todayDone, pastDone: past, dayTarget: dayTarget, aheadDays: ahead, tomorrowTarget: tomorrow);
}

/// Jours vécus TENUS par une routine « sur 7 jours », jusqu'à [now] compris :
/// la part du jour est faite, ou l'avance des 6 jours d'avant la couvre.
Set<String> rollingHeldDays(Activity a, List<HabitHit> hits, DateTime now, {int dayStartMin = kDefaultDayStartMin}) {
  final t = routineDayTargetOf(a);
  final counts = routineDayCounts(a, hits, dayStartMin: dayStartMin);
  if (counts.isEmpty) return const {};
  final first = DateTime.parse((counts.keys.toList()..sort()).first);
  final today = _d(livedDate(now, dayStartMin));
  final out = <String>{};
  final window = <int>[]; // les 6 jours d'avant, au plus
  var past = 0;
  for (var d = first; !d.isAfter(today); d = DateTime(d.year, d.month, d.day + 1)) {
    final k = ymdOf(d);
    final c = counts[k] ?? 0;
    if (c >= rollingDayTarget(t, past)) out.add(k);
    window.add(c);
    past += c;
    if (window.length > kRoutineWindowDays - 1) past -= window.removeAt(0);
  }
  return out;
}

/// « jusqu'à samedi » : dernier jour couvert par l'avance.
String coveredUntilLabel(DateTime today, int aheadDays) {
  const names = ['lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche'];
  if (aheadDays <= 0) return 'ce soir';
  if (aheadDays == 1) return 'demain soir';
  final d = DateTime(today.year, today.month, today.day + aheadDays);
  return names[d.weekday - 1];
}

/// Routine HEBDO atteinte (n coches sur les 7 derniers jours) : jours À VENIR
/// encore couverts si rien d'autre n'est fait — elle revient d'elle-même quand
/// la coche la plus ancienne qui compte sort de la fenêtre. Null si la routine
/// n'est pas hebdomadaire ou pas atteinte.
int? weeklyAheadDays(Activity a, List<HabitHit> hits, DateTime now, {int dayStartMin = kDefaultDayStartMin}) {
  if (!a.isHabit || a.habitFreq != HabitFreq.weekly) return null;
  final target = (a.habitTarget ?? 1) <= 0 ? 1 : (a.habitTarget ?? 1);
  final from = now.subtract(const Duration(days: kRoutineWindowDays));
  final ts = [
    for (final h in hits)
      if (h.habitId == a.id && !h.ts.isBefore(from) && !h.ts.isAfter(now.add(const Duration(minutes: 1)))) h.ts,
  ]..sort();
  if (ts.length < target) return null;
  final expiry = ts[ts.length - target].add(const Duration(days: kRoutineWindowDays));
  DateTime u(DateTime x) => DateTime.utc(x.year, x.month, x.day);
  final n = u(livedDate(expiry, dayStartMin)).difference(u(livedDate(now, dayStartMin))).inDays - 1;
  return n < 0 ? 0 : n;
}

// ── « 1 coche = n min » : le chrono de l'activité liée coche la routine ─────

/// La routine se coche par le chrono : une durée par coche et une activité liée.
bool hasTimeHits(Activity a) => a.isHabit && (a.minPerHit ?? 0) > 0 && (a.linkedActivityId ?? '').trim().isNotEmpty;

/// Minutes de chrono de la journée vécue sur l'activité [activityId] (chrono en cours compris).
int livedMinutesOn(String activityId, List<Session> sessions, DateTime now, {int dayStartMin = kDefaultDayStartMin}) {
  final from = livedDayStart(now, dayStartMin);
  var sec = 0;
  for (final s in sessions) {
    if (s.deleted || s.activityId != activityId) continue;
    final end = s.endAt ?? now;
    final a = s.startAt.isBefore(from) ? from : s.startAt;
    final b = end.isAfter(now) ? now : end;
    if (b.isAfter(a)) sec += b.difference(a).inSeconds;
  }
  return sec ~/ 60;
}

/// Coches que le chrono du jour donne à la routine : minutes ÷ durée d'une coche.
int timeHitsEarned(Activity routine, List<Session> sessions, DateTime now, {int dayStartMin = kDefaultDayStartMin}) {
  if (!hasTimeHits(routine)) return 0;
  return livedMinutesOn(routine.linkedActivityId!.trim(), sessions, now, dayStartMin: dayStartMin) ~/ routine.minPerHit!;
}

/// Id d'une coche du chrono : le même sur tous les appareils, donc jamais posée deux fois.
String timeHitId(String habitId, String ymd, int k) => 'time-$habitId-$ymd-$k';

/// Rang le plus haut déjà posé par le chrono ce jour-là (0 = aucune).
int timeHitsGiven(String habitId, String ymd, List<HabitHit> hits) {
  final prefix = 'time-$habitId-$ymd-';
  var max = 0;
  for (final h in hits) {
    if (!h.id.startsWith(prefix)) continue;
    final k = int.tryParse(h.id.substring(prefix.length)) ?? 0;
    if (k > max) max = k;
  }
  return max;
}
