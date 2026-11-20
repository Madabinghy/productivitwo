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

/// Un jour raté se rattrape (2026-11-19, maquette validée « Routines rattrapables ») : rythme « Rattrapable »
/// (`catchUp`, sans avance) ou « Sur 7 jours » (`rolling`, rattrapage et avance).
bool isCatchUpRoutine(Activity a) => a.isHabit && a.habitFreq == HabitFreq.daily && (a.catchUp || a.rolling);

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

/// Un jour raté encore rattrapable : ce qu'il lui manque.
class CatchUpHole {
  final DateTime day;
  final int deficit;
  const CatchUpHole(this.day, this.deficit);
}

/// Le rattrapage d'une routine : les jours déjà rattrapés, et ceux qui attendent encore AVANT aujourd'hui
/// (du plus récent au plus ancien, 6 jours au plus).
class CatchUp {
  final Set<String> repaired;
  final List<CatchUpHole> open;
  const CatchUp({this.repaired = const {}, this.open = const []});
  static const none = CatchUp();
}

/// Rejoue les jours d'une routine rattrapable : ce qu'un jour fait EN PLUS de ce qu'il demande comble les jours
/// ratés des 6 jours d'avant, le plus récent d'abord. Un jour comblé est « rattrapé » : il recolle la série, sans
/// devenir une journée parfaite après coup. [frozen] = jours gelés, qui ne sont jamais des trous.
CatchUp catchUpOf(Activity a, List<HabitHit> hits, DateTime now, {int dayStartMin = kDefaultDayStartMin, Set<String> frozen = const {}}) {
  if (!isCatchUpRoutine(a)) return CatchUp.none;
  final counts = routineDayCounts(a, hits, dayStartMin: dayStartMin);
  if (counts.isEmpty) return CatchUp.none;
  final first = DateTime.parse((counts.keys.toList()..sort()).first);
  final today = _d(livedDate(now, dayStartMin));
  final repaired = <String>{};
  var holes = <CatchUpHole>[]; // du plus ancien au plus récent
  var openBefore = const <CatchUpHole>[];
  final window = <int>[];
  var past = 0;
  for (var d = first; !d.isAfter(today); d = DateTime(d.year, d.month, d.day + 1)) {
    final limit = DateTime(d.year, d.month, d.day - (kRoutineWindowDays - 1));
    holes = [for (final h in holes) if (!h.day.isBefore(limit)) h];
    if (d == today) openBefore = holes.reversed.toList();
    final k = ymdOf(d);
    final c = counts[k] ?? 0;
    final t = a.targetOnYmd(k); // la cible de ce jour-là
    final need = a.rolling ? rollingDayTarget(t, past) : t;
    if (c > need) {
      var extra = c - need;
      for (var i = holes.length - 1; i >= 0 && extra > 0; i--) {
        final h = holes[i];
        final take = extra < h.deficit ? extra : h.deficit;
        extra -= take;
        if (take == h.deficit) {
          repaired.add(ymdOf(h.day));
          holes.removeAt(i);
        } else {
          holes[i] = CatchUpHole(h.day, h.deficit - take);
        }
      }
    } else if (c < need && d != today && !frozen.contains(k)) {
      holes.add(CatchUpHole(d, need - c));
    }
    window.add(c);
    past += c;
    if (window.length > kRoutineWindowDays - 1) past -= window.removeAt(0);
  }
  return CatchUp(repaired: repaired, open: openBefore);
}

/// Où en est une routine « sur 7 jours » ou « rattrapable » aujourd'hui.
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
  /// Coches à faire EN PLUS aujourd'hui pour que demain ne demande rien
  /// (peut dépasser la cible quand la semaine a des trous).
  final int toFreeTomorrow;
  /// Coches d'aujourd'hui qu'il faut pour tenir chaque jour : `[0]` = ce soir
  /// (la part du jour), `[k]` = le k-ième jour à venir, sans rien y faire.
  /// Croissant : un jour plus loin ne coûte jamais moins.
  final List<int> thresholds;
  /// La journée vécue du calcul.
  final DateTime today;
  /// « Sur 7 jours » : ce qui est fait en plus couvre les jours suivants. Faux = « Rattrapable », sans avance.
  final bool advance;
  /// Jours ratés encore rattrapables, du plus récent au plus ancien (avant les coches d'aujourd'hui).
  final List<CatchUpHole> holes;
  const RoutineCover({
    this.advance = true,
    this.holes = const [],
    required this.today,
    required this.target,
    required this.todayDone,
    required this.pastDone,
    required this.dayTarget,
    required this.aheadDays,
    required this.tomorrowTarget,
    required this.toFreeTomorrow,
    required this.thresholds,
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
  bool get canGetAhead => advance && held && aheadDays == 0 && tomorrowTarget > 0;

  /// Coches d'aujourd'hui où chaque jour raté est rattrapé : après la part du jour, le plus récent d'abord.
  List<int> get holeThresholds {
    var at = dayTarget;
    return [for (final h in holes) at += h.deficit];
  }

  /// Jours ratés que les coches d'aujourd'hui ont déjà rattrapés, et ceux qui attendent encore.
  int get holesFilled => holeThresholds.where((t) => todayDone >= t).length;
  int get holesLeft => holes.length - holesFilled;
  /// Tenue ce soir, et un jour raté peut encore se rattraper.
  bool get canCatchUp => held && holesLeft > 0;
  /// Coches à faire encore pour rattraper le prochain jour raté (0 = rien à rattraper).
  int get toNextHole {
    for (final t in holeThresholds) {
      if (todayDone < t) return t - todayDone;
    }
    return 0;
  }

  /// Le prochain jour raté à rattraper, null s'il n'y en a plus.
  CatchUpHole? get nextHole => holesLeft > 0 ? holes[holesFilled] : null;

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
RoutineCover routineCover(Activity a, List<HabitHit> hits, DateTime now, {int dayStartMin = kDefaultDayStartMin, Set<String> frozen = const {}}) {
  final t = routineDayTargetOf(a);
  final holes = catchUpOf(a, hits, now, dayStartMin: dayStartMin, frozen: frozen).open;
  if (!a.rolling) {
    // « Rattrapable » : chaque jour demande sa cible, rien ne couvre demain.
    final today = _d(livedDate(now, dayStartMin));
    final counts = routineDayCounts(a, hits, dayStartMin: dayStartMin);
    var past = 0;
    for (var i = 1; i < kRoutineWindowDays; i++) {
      past += counts[ymdOf(DateTime(today.year, today.month, today.day - i))] ?? 0;
    }
    return RoutineCover(
        advance: false, holes: holes, today: today, target: t, todayDone: counts[ymdOf(today)] ?? 0, pastDone: past, dayTarget: t, aheadDays: 0, tomorrowTarget: t, toFreeTomorrow: 0, thresholds: [t]);
  }
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
  int lastSix() => future.skip(future.length - (kRoutineWindowDays - 1)).fold<int>(0, (s, v) => s + v);
  int nextTarget() => rollingDayTarget(t, lastSix());
  final tomorrow = nextTarget();
  final missing = kRoutineWindowDays * t - lastSix();
  // Le k-ième jour à venir ne voit plus que les (6 − k) derniers jours passés.
  final thresholds = <int>[dayTarget];
  for (var k = 1; k < kRoutineWindowDays; k++) {
    final kept = window.skip(k).fold<int>(0, (s, v) => s + v);
    final need = kRoutineWindowDays * t - kept;
    thresholds.add(need > 0 ? need : 0);
  }
  var ahead = 0;
  if (todayDone >= dayTarget) {
    while (ahead < kRoutineWindowDays - 1 && nextTarget() == 0) {
      ahead++;
      future.add(0);
    }
  }
  return RoutineCover(holes: holes, today: today, target: t, todayDone: todayDone, pastDone: past, dayTarget: dayTarget, aheadDays: ahead, tomorrowTarget: tomorrow, toFreeTomorrow: missing > 0 ? missing : 0, thresholds: thresholds);
}

/// Une case de la jauge du jour (2026-11-19, maquette validée « Jauge des
/// routines 7 jours ») : ce que les coches d'AUJOURD'HUI achètent — ce soir,
/// puis demain, puis les jours suivants. Sa largeur est son prix en coches.
class CoverSlot {
  /// Jours couverts par la case : 0 = ce soir, 1 = demain… Plusieurs jours au
  /// même prix tiennent dans une seule case ([from] … [to]).
  final int from;
  final int to;
  /// Coches d'aujourd'hui où la case commence et où elle est pleine.
  final int lo;
  final int hi;
  final int done;
  /// Case d'un jour RATÉ à rattraper (le jour en question) ; null = ce soir ou un jour à venir.
  final DateTime? hole;
  const CoverSlot({required this.from, required this.to, required this.lo, required this.hi, required this.done, this.hole});

  /// Prix de la case ; 0 = elle ne coûte rien de plus que la précédente : déjà acquise par l'avance des jours
  /// passés, ou gagnée en même temps que le jour raté qui la précède.
  int get cost => hi - lo;
  bool get full => done >= hi;

  /// Une case sans prix n'est pleine que si son seuil est atteint (bug user 2026-11-20 : « demain » s'affichait
  /// vert alors que les jours à rattraper avant lui étaient vides).
  double get fill => cost <= 0 ? (full ? 1 : 0) : ((done - lo) / cost).clamp(0.0, 1.0).toDouble();
  /// Ce qu'il manque pour la remplir.
  int get left => full ? 0 : hi - (done > lo ? done : lo);
}

/// Les cases de la jauge : ce soir, puis les jours ratés à rattraper (le plus récent d'abord, 3 au plus), puis
/// les jours à venir que l'avance achète (« Sur 7 jours » seulement) — [days] cases de jours à venir au plus.
List<CoverSlot> coverSlots(RoutineCover c, {int days = 4}) {
  final out = <CoverSlot>[CoverSlot(from: 0, to: 0, lo: 0, hi: c.thresholds[0], done: c.todayDone)];
  var at = c.thresholds[0];
  final ht = c.holeThresholds;
  final nh = ht.length > 3 ? 3 : ht.length;
  for (var i = 0; i < nh; i++) {
    out.add(CoverSlot(from: 0, to: 0, lo: at, hi: ht[i], done: c.todayDone, hole: c.holes[i].day));
    at = ht[i];
  }
  if (!c.advance) return out;
  final room = days - nh < 2 ? 2 : days - nh;
  final n = room > c.thresholds.length ? c.thresholds.length : room;
  for (var k = 1; k < n; k++) {
    // Un jour à venir ne coûte jamais moins que ce qui le précède dans la jauge.
    final hi = c.thresholds[k] > at ? c.thresholds[k] : at;
    final p = out.last;
    if (hi == at && p.hole == null) {
      out[out.length - 1] = CoverSlot(from: p.from, to: k, lo: p.lo, hi: p.hi, done: c.todayDone);
      continue;
    }
    out.add(CoverSlot(from: k, to: k, lo: at, hi: hi, done: c.todayDone));
    at = hi;
  }
  return out;
}

/// Les cases qui tiennent dans [maxWidth], chacune à la largeur de son nom ([widths], dans l'ordre de [slots]) :
/// jamais d'étiquette coupée (bug user 2026-11-20 : « ce soi », « mer. 1 »). On retire d'abord les jours ratés
/// les plus anciens (il en reste un), puis les jours à venir les plus lointains (il en reste un), puis le
/// dernier jour raté ; « ce soir » reste toujours.
List<CoverSlot> fitCoverSlots(List<CoverSlot> slots, List<double> widths, double maxWidth, {double gap = 3}) {
  final keep = [for (var i = 0; i < slots.length; i++) i];
  double total() => keep.fold<double>(0, (a, i) => a + widths[i]) + gap * (keep.length - 1);
  List<int> holes() => [for (final i in keep) if (slots[i].hole != null) i];
  List<int> ahead() => [for (final i in keep) if (slots[i].hole == null && i > 0) i];
  while (keep.length > 1 && total() > maxWidth) {
    final h = holes(), f = ahead();
    if (h.length > 1) {
      keep.remove(h.last);
    } else if (f.length > 1) {
      keep.remove(f.last);
    } else if (h.isNotEmpty) {
      keep.remove(h.last);
    } else {
      keep.remove(f.last);
    }
  }
  return [for (final i in keep) slots[i]];
}

/// « mercredi », « hier » : le jour raté qu'on rattrape, en toutes lettres.
String holeDayLabel(DateTime today, DateTime day) {
  const names = ['lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche'];
  return DateTime(today.year, today.month, today.day - 1) == day ? 'hier' : names[day.weekday - 1];
}

/// « ce soir », « demain », « sam. » ; un jour à rattraper : « hier », « mer. 18 » ; plusieurs jours : « dem. + sam. », « dem. → lun. ».
String coverSlotLabel(DateTime today, CoverSlot s) {
  const names = ['lun.', 'mar.', 'mer.', 'jeu.', 'ven.', 'sam.', 'dim.'];
  // Un jour passé qu'on rattrape porte sa date : jamais confondu avec le même jour de la semaine à venir.
  if (s.hole case final h?) {
    return DateTime(today.year, today.month, today.day - 1) == h ? 'hier' : '${names[h.weekday - 1]} ${h.day}';
  }
  String day(int k, {bool short = false}) {
    if (k == 0) return 'ce soir';
    if (k == 1) return short ? 'dem.' : 'demain';
    return names[DateTime(today.year, today.month, today.day + k).weekday - 1];
  }

  if (s.from == s.to) return day(s.from);
  if (s.to == s.from + 1) return '${day(s.from, short: true)} + ${day(s.to, short: true)}';
  return '${day(s.from, short: true)} → ${day(s.to, short: true)}';
}

/// Jours vécus TENUS par une routine « sur 7 jours », jusqu'à [now] compris :
/// la part du jour est faite, ou l'avance des 6 jours d'avant la couvre.
Set<String> rollingHeldDays(Activity a, List<HabitHit> hits, DateTime now, {int dayStartMin = kDefaultDayStartMin}) {
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
    if (c >= rollingDayTarget(a.targetOnYmd(k), past)) out.add(k);
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

/// Minutes de chrono qui valent UNE coche de la routine, ou null quand le chrono ne la coche pas.
/// - réglé à la main (`minPerHit`) : cette durée ;
/// - éteint à la main (`chronoOff`) : jamais ;
/// - sinon D'OFFICE (2026-11-20, demande user : 25 min de chrono n'avaient rien coché) quand la routine a une
///   durée d'une fois et qu'elle est la SEULE routine liée à son activité dans [all]. Plusieurs routines sur la
///   même activité : rien d'office, la question est posée à l'arrêt du chrono (`routinesToAsk`).
int? chronoHitMin(Activity a, [Iterable<Activity> all = const []]) {
  final link = (a.linkedActivityId ?? '').trim();
  if (!a.isHabit || link.isEmpty) return null;
  if ((a.minPerHit ?? 0) > 0) return a.minPerHit;
  if (a.chronoOff) return null;
  final once = a.onceMin;
  if (once == null) return null;
  final same = all.where((x) => x.isHabit && !x.deleted && (x.linkedActivityId ?? '').trim() == link);
  return same.length == 1 && same.first.id == a.id ? once : null;
}

/// La routine se coche par le chrono (réglé à la main, ou d'office avec [all]).
bool hasTimeHits(Activity a, [Iterable<Activity> all = const []]) => chronoHitMin(a, all) != null;

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
int timeHitsEarned(Activity routine, List<Session> sessions, DateTime now, {int dayStartMin = kDefaultDayStartMin, Iterable<Activity> all = const []}) {
  final per = chronoHitMin(routine, all);
  if (per == null) return 0;
  return livedMinutesOn(routine.linkedActivityId!.trim(), sessions, now, dayStartMin: dayStartMin) ~/ per;
}

/// Plusieurs routines sont liées à l'activité [activityId] : celles à proposer à l'arrêt du chrono (« ce temps,
/// c'était pour quelle routine ? »). Seulement celles qui ont une durée d'une fois, qui ne sont ni réglées à la
/// main (elles se cochent déjà toutes seules) ni éteintes, et à qui [minutes] de chrono donnent au moins une
/// coche. Vide quand l'activité n'a qu'une routine (elle se coche d'office) ou aucune.
List<Activity> routinesToAsk(String activityId, Iterable<Activity> all, int minutes) {
  final same = [for (final x in all) if (x.isHabit && !x.deleted && (x.linkedActivityId ?? '').trim() == activityId) x];
  if (same.length < 2) return const [];
  final out = [
    for (final r in same)
      if ((r.minPerHit ?? 0) <= 0 && !r.chronoOff && r.onceMin != null && minutes >= r.onceMin!) r,
  ];
  out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return out;
}

/// Coches que [minutes] de chrono donnent à la routine choisie.
int askedHits(Activity routine, int minutes) => routine.onceMin == null ? 0 : minutes ~/ routine.onceMin!;

/// Id d'une coche donnée par la question de l'arrêt : une session ne coche une routine qu'une fois.
String askedHitId(String habitId, String sessionId, int k) => 'ask-$habitId-$sessionId-$k';

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
