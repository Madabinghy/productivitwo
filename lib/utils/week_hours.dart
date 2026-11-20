import 'dart:math' as math;

import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/recharge.dart' show isBasicNeedName, isSleepName;

/// Les 7 derniers jours glissants (maquette validée 2026-11-11 « Jauge des 168 heures ») : la fenêtre est
/// toujours maintenant − 168 h → maintenant, minute par minute. Une minute n'est comptée qu'une fois :
/// sommeil d'abord, puis besoins de base (repas, sieste), puis détente (2026-11-18 : les activités des
/// domaines de nature Détente), puis actif ; ce qui n'est couvert par aucun chrono est « dans le flou ».
const kWeekHoursMin = 168 * 60;

/// « À fond » : 24 h actives d'ici demain à la même heure.
const kFullDayMin = 24 * 60;

class WeekHours {
  final int activeMin, basicMin, sleepMin;
  /// Temps de détente (loisirs, jeux, repos choisi) : jamais compté comme actif.
  final int leisureMin;
  /// Heures actives des 168 h d'avant (maintenant − 336 h → maintenant − 168 h).
  final int prevActiveMin;
  final int prevLeisureMin;
  /// Heures actives des 24 premières heures de la fenêtre : elles en sortent d'ici demain à la même heure.
  final int leavingMin;
  /// Minutes actives par jour calendaire, du plus ancien (en partie dans la fenêtre) à aujourd'hui.
  final List<int> dayActive;
  /// Minutes de détente par jour calendaire, mêmes jours que [dayActive].
  final List<int> dayLeisure;
  final List<DateTime> days;
  /// Ce qui tourne maintenant (l'aiguille) et ce qui tournait il y a 7 jours à la même minute (le triangle) :
  /// la minute qui sort de la fenêtre, et celle qui la remplace.
  final HoursKind nowKind, pastKind;
  final String? nowName, pastName;
  const WeekHours({
    required this.activeMin,
    required this.basicMin,
    required this.sleepMin,
    required this.prevActiveMin,
    required this.leavingMin,
    required this.dayActive,
    required this.days,
    this.leisureMin = 0,
    this.prevLeisureMin = 0,
    this.dayLeisure = const [],
    this.nowKind = HoursKind.free,
    this.pastKind = HoursKind.free,
    this.nowName,
    this.pastName,
  });
  int get trackedMin => activeMin + leisureMin + basicMin + sleepMin;
  int get untrackedMin => (kWeekHoursMin - trackedMin).clamp(0, kWeekHoursMin);
  int get deltaMin => activeMin - prevActiveMin;
  /// Les heures actives demain à la même heure si rien n'est fait d'ici là : les 24 premières heures de la fenêtre
  /// sont sorties. C'est là que se pose l'aiguille quand aucun chrono ne tourne (maquette validée 2026-11-19).
  int get tomorrowActiveMin => (activeMin - leavingMin).clamp(0, activeMin);
  /// La part du vert qui reste demain (0 = tout sort, 1 = rien ne sort) : la position de l'aiguille dans le vert.
  double get tomorrowShare => activeMin <= 0 ? 1 : tomorrowActiveMin / activeMin;
  /// Les heures actives demain à la même heure en y allant à fond (maquette validée 2026-11-20, choix user : 24 h
  /// sans arrêt, un plafond) : les 24 premières heures de la fenêtre sont sorties, 24 h actives sont entrées.
  int get fullTomorrowActiveMin => math.min(kWeekHoursMin, tomorrowActiveMin + kFullDayMin);
  /// Ce que le vert gagne d'ici demain à fond (jamais négatif : il sort au plus 24 h).
  int get fullGainMin => math.max(0, fullTomorrowActiveMin - activeMin);
  /// Moyenne d'heures actives par jour sur la fenêtre.
  double get perDayMin => activeMin / 7;
  /// Le jour le plus actif de la fenêtre (index dans [days]), -1 si rien.
  int get bestDay {
    var best = -1;
    for (var i = 0; i < dayActive.length; i++) {
      if (dayActive[i] > 0 && (best < 0 || dayActive[i] > dayActive[best])) best = i;
    }
    return best;
  }
}

/// « 30 min » sous une heure, « 3 h » au-delà (arrondi à l'heure) : une petite
/// durée ne s'affiche jamais « 0 h » ni « 1 h ».
String spanLabel(int min) => min <= 0 ? '0 h' : (min < 60 ? '$min min' : '${(min / 60).round()} h');

/// Une durée à la minute : « 45 min », « 12 h », « 12 h 27 ».
String spanExact(int min) {
  if (min < 60) return '${min < 0 ? 0 : min} min';
  final m = min % 60;
  return m == 0 ? '${min ~/ 60} h' : '${min ~/ 60} h ${m.toString().padLeft(2, '0')}';
}

/// « 55 h · −12 h 27 » : où sera le vert demain à la même heure si rien n'est fait, et ce qui sort d'ici là.
String hoursTomorrowLabel(WeekHours h) =>
    h.leavingMin > 0 ? '${spanLabel(h.tomorrowActiveMin)} · −${spanExact(h.leavingMin)}' : '${spanLabel(h.activeMin)} · rien ne sort';

/// « 79 h · +11 h 33 » : où sera le vert demain à la même heure en y allant à fond, et ce qu'il gagne d'ici là.
String hoursFullLabel(WeekHours h) => '${spanLabel(h.fullTomorrowActiveMin)} · +${spanExact(h.fullGainMin)}';

/// Les morceaux du compteur en part du cadran : actif · détente · besoins de
/// base · sommeil · libre. Un morceau non nul n'est jamais dessiné plus petit
/// que [minFrac] (3° sur 240) ; le temps libre absorbe la différence. Seul le
/// dessin a un plancher : les totaux affichés restent exacts.
List<double> gaugeFractions(WeekHours h, {double minFrac = 3 / 240}) {
  final out = [
    for (final m in [h.activeMin, h.leisureMin, h.basicMin, h.sleepMin])
      m <= 0 ? 0.0 : (m / kWeekHoursMin < minFrac ? minFrac : m / kWeekHoursMin),
  ];
  final used = out.fold<double>(0, (a, b) => a + b);
  if (used >= 1) return [for (final f in out) f / used, 0.0];
  return [...out, 1 - used];
}

/// Le cadran : un arc de 240° qui part en bas à gauche (angles en radians, sens des aiguilles d'une montre).
const kGaugeStart = 150 * math.pi / 180;
const kGaugeSweep = 240 * math.pi / 180;
const _gaugeGap = 1.3 * math.pi / 180;

/// Un morceau plein du cadran : sa catégorie, son début, sa longueur dessinée ([len], joint retiré) et sa part ([sweep]).
class GaugeArc {
  final HoursKind kind;
  final double start, len, sweep;
  const GaugeArc(this.kind, this.start, this.len, this.sweep);
}

/// Où tout se pose sur le cadran. [marks] : la place d'un repère (aiguille, triangle) par catégorie —
/// sommeil, détente, besoins : au bout de leur morceau ; rien de tracé : [idleAt], dans le vert, là où il
/// s'arrêtera demain si rien n'est fait ; actif : [fullAt], dans le temps libre, là où il arrivera demain à fond.
class GaugeLayout {
  /// Dans l'ordre du cadran : besoins de base, sommeil, détente, actif (les morceaux vides sont absents).
  final List<GaugeArc> arcs;
  final double activeStart, activeLen, trackedEnd, idleAt, fullAt;
  final Map<HoursKind, double> marks;
  const GaugeLayout({
    required this.arcs,
    required this.activeStart,
    required this.activeLen,
    required this.trackedEnd,
    required this.idleAt,
    required this.fullAt,
    required this.marks,
  });
  double get end => kGaugeStart + kGaugeSweep;
  double get activeEnd => activeStart + activeLen;
}

GaugeLayout gaugeLayout(WeekHours h) {
  final f = gaugeFractions(h);
  const kinds = [HoursKind.active, HoursKind.leisure, HoursKind.basic, HoursKind.sleep];
  final arcs = <GaugeArc>[];
  final marks = <HoursKind, double>{};
  var a = kGaugeStart;
  var activeStart = kGaugeStart, activeLen = 0.0;
  // Le socle d'abord : besoins de base, sommeil, détente, puis l'actif.
  for (final i in const [2, 3, 1, 0]) {
    final sweep = kGaugeSweep * f[i];
    if (sweep <= 0) {
      marks[kinds[i]] = a;
      continue;
    }
    final len = sweep > _gaugeGap * 2.3 ? sweep - _gaugeGap : sweep;
    marks[kinds[i]] = a + len;
    arcs.add(GaugeArc(kinds[i], a, len, sweep));
    if (i == 0) {
      activeStart = a;
      activeLen = len;
    }
    a += sweep;
  }
  final trackedEnd = a;
  if (f[0] <= 0) activeStart = trackedEnd;
  const end = kGaugeStart + kGaugeSweep;
  final idleAt = activeStart + activeLen * h.tomorrowShare;
  final fullAt = math.min(end, activeStart + activeLen + kGaugeSweep * h.fullGainMin / kWeekHoursMin);
  marks[HoursKind.free] = idleAt;
  marks[HoursKind.active] = fullAt;
  return GaugeLayout(arcs: arcs, activeStart: activeStart, activeLen: activeLen, trackedEnd: trackedEnd, idleAt: idleAt, fullAt: fullAt, marks: marks);
}

/// Ce qu'une minute contient, du plus faible au plus fort : une minute couverte par deux chronos prend le plus fort.
enum HoursKind { free, active, leisure, basic, sleep }

int _rank(HoursKind k) => HoursKind.values.indexOf(k);

HoursKind _kindOf(Session s, Map<String, Activity> byId, Set<String> leisureIds) {
  final name = byId[s.activityId]?.name;
  return isSleepName(name)
      ? HoursKind.sleep
      : (isBasicNeedName(name) ? HoursKind.basic : (leisureIds.contains(s.activityId) ? HoursKind.leisure : HoursKind.active));
}

/// Ce qui tourne à l'instant [at] : la catégorie la plus forte parmi les chronos qui le couvrent, et son activité.
/// [running] : seul un chrono encore ouvert compte (ce qu'on fait maintenant).
(HoursKind, String?) _momentAt(DateTime at, List<Session> sessions, Map<String, Activity> byId, Set<String> leisureIds, DateTime now,
    {bool running = false}) {
  var kind = HoursKind.free;
  String? name;
  for (final s in sessions) {
    if (s.deleted || s.startAt.isAfter(at)) continue;
    if (running ? s.endAt != null : !(s.endAt ?? now).isAfter(at)) continue;
    final k = _kindOf(s, byId, leisureIds);
    if (_rank(k) > _rank(kind)) {
      kind = k;
      name = byId[s.activityId]?.name;
    }
  }
  return (kind, name);
}

const _kindLabels = {
  HoursKind.free: 'Rien de tracé',
  HoursKind.active: 'Actif',
  HoursKind.leisure: 'Détente',
  HoursKind.basic: 'Besoins de base',
  HoursKind.sleep: 'Sommeil',
};

String hoursKindLabel(HoursKind k) => _kindLabels[k]!;

/// « Détente · Jeux vidéo » ; le nom de l'activité n'est pas répété quand il dit la même chose (« Sommeil »).
String hoursMomentLabel(HoursKind k, String? name, {bool now = false}) {
  if (k == HoursKind.free) return now ? 'aucun chrono' : 'rien de tracé';
  final label = hoursKindLabel(k);
  final n = name?.trim() ?? '';
  return n.isEmpty || n.toLowerCase() == label.toLowerCase() ? label : '$label · $n';
}

const _kindNames = {
  HoursKind.free: 'ton temps libre',
  HoursKind.active: 'le vert',
  HoursKind.leisure: 'la détente',
  HoursKind.basic: 'les besoins de base',
  HoursKind.sleep: 'le sommeil',
};

/// La minute d'il y a 7 jours sort de la fenêtre, celle de maintenant y entre : ce qui avance, ce qui recule.
String hoursMoveSentence(HoursKind now, HoursKind past) {
  if (now == past) return 'Tu fais comme il y a 7 jours : la minute qui sort est remplacée par la même, la jauge ne bouge pas.';
  final gain = _kindNames[now]!;
  return '${gain[0].toUpperCase()}${gain.substring(1)} avance, ${_kindNames[past]} recule.';
}

/// Remplit [cells] (une case par minute depuis [from]) avec la catégorie la plus forte de chaque minute.
void _paint(List<HoursKind> cells, DateTime from, List<Session> sessions, Map<String, Activity> byId, Set<String> leisureIds, DateTime now) {
  final to = from.add(Duration(minutes: cells.length));
  for (final s in sessions) {
    if (s.deleted) continue;
    final end = s.endAt ?? now;
    if (!end.isAfter(from) || !s.startAt.isBefore(to)) continue;
    final kind = _kindOf(s, byId, leisureIds);
    final i0 = s.startAt.isBefore(from) ? 0 : s.startAt.difference(from).inMinutes;
    final i1 = (end.isAfter(to) ? cells.length : end.difference(from).inMinutes).clamp(0, cells.length);
    for (var i = i0; i < i1; i++) {
      if (_rank(kind) > _rank(cells[i])) cells[i] = kind;
    }
  }
}

/// [leisureIds] = les activités de détente (`leisureActivityIds`, `utils/leisure.dart`).
WeekHours weekHours({
  required List<Session> sessions,
  required List<Activity> activities,
  required DateTime now,
  Set<String> leisureIds = const {},
}) {
  final byId = {for (final a in activities) a.id: a};
  final nowMin = DateTime(now.year, now.month, now.day, now.hour, now.minute);
  final start = nowMin.subtract(const Duration(minutes: kWeekHoursMin));
  final prevStart = start.subtract(const Duration(minutes: kWeekHoursMin));
  final cells = List<HoursKind>.filled(kWeekHoursMin * 2, HoursKind.free);
  _paint(cells, prevStart, sessions, byId, leisureIds, now);
  var active = 0, leisure = 0, basic = 0, sleep = 0, prev = 0, prevLeisure = 0, leaving = 0;
  for (var i = 0; i < kWeekHoursMin; i++) {
    if (cells[i] == HoursKind.active) prev++;
    if (cells[i] == HoursKind.leisure) prevLeisure++;
  }
  final today = DateTime(now.year, now.month, now.day);
  final days = [for (var i = 7; i >= 0; i--) DateTime(today.year, today.month, today.day - i)];
  final dayActive = List<int>.filled(days.length, 0);
  final dayLeisure = List<int>.filled(days.length, 0);
  for (var i = 0; i < kWeekHoursMin; i++) {
    final k = cells[kWeekHoursMin + i];
    if (k == HoursKind.free) continue;
    if (k == HoursKind.sleep) {
      sleep++;
    } else if (k == HoursKind.basic) {
      basic++;
    } else {
      final t = start.add(Duration(minutes: i));
      final d = DateTime(t.year, t.month, t.day);
      final idx = days.indexWhere((x) => x == d);
      if (k == HoursKind.leisure) {
        leisure++;
        if (idx >= 0) dayLeisure[idx]++;
      } else {
        active++;
        if (i < 24 * 60) leaving++;
        if (idx >= 0) dayActive[idx]++;
      }
    }
  }
  final (nowKind, nowName) = _momentAt(now, sessions, byId, leisureIds, now, running: true);
  final (pastKind, pastName) = _momentAt(now.subtract(const Duration(minutes: kWeekHoursMin)), sessions, byId, leisureIds, now);
  return WeekHours(
    nowKind: nowKind,
    nowName: nowName,
    pastKind: pastKind,
    pastName: pastName,
    activeMin: active,
    basicMin: basic,
    sleepMin: sleep,
    prevActiveMin: prev,
    leavingMin: leaving,
    dayActive: dayActive,
    days: days,
    leisureMin: leisure,
    prevLeisureMin: prevLeisure,
    dayLeisure: dayLeisure,
  );
}
