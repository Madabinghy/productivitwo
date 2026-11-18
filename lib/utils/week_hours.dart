import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/recharge.dart' show isBasicNeedName, isSleepName;

/// Les 7 derniers jours glissants (maquette validée 2026-11-11 « Jauge des 168 heures ») : la fenêtre est
/// toujours maintenant − 168 h → maintenant, minute par minute. Une minute n'est comptée qu'une fois :
/// sommeil d'abord, puis besoins de base (repas, sieste), puis détente (2026-11-18 : les activités des
/// domaines de nature Détente), puis actif ; ce qui n'est couvert par aucun chrono est « dans le flou ».
const kWeekHoursMin = 168 * 60;

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
  });
  int get trackedMin => activeMin + leisureMin + basicMin + sleepMin;
  int get untrackedMin => (kWeekHoursMin - trackedMin).clamp(0, kWeekHoursMin);
  int get deltaMin => activeMin - prevActiveMin;
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

enum _Kind { none, active, leisure, basic, sleep }

int _rank(_Kind k) => _Kind.values.indexOf(k);

/// Remplit [cells] (une case par minute depuis [from]) avec la catégorie la plus forte de chaque minute.
void _paint(List<_Kind> cells, DateTime from, List<Session> sessions, Map<String, Activity> byId, Set<String> leisureIds, DateTime now) {
  final to = from.add(Duration(minutes: cells.length));
  for (final s in sessions) {
    if (s.deleted) continue;
    final end = s.endAt ?? now;
    if (!end.isAfter(from) || !s.startAt.isBefore(to)) continue;
    final a = byId[s.activityId];
    final name = a?.name;
    final kind = isSleepName(name)
        ? _Kind.sleep
        : (isBasicNeedName(name) ? _Kind.basic : (leisureIds.contains(s.activityId) ? _Kind.leisure : _Kind.active));
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
  final cells = List<_Kind>.filled(kWeekHoursMin * 2, _Kind.none);
  _paint(cells, prevStart, sessions, byId, leisureIds, now);
  var active = 0, leisure = 0, basic = 0, sleep = 0, prev = 0, prevLeisure = 0, leaving = 0;
  for (var i = 0; i < kWeekHoursMin; i++) {
    if (cells[i] == _Kind.active) prev++;
    if (cells[i] == _Kind.leisure) prevLeisure++;
  }
  final today = DateTime(now.year, now.month, now.day);
  final days = [for (var i = 7; i >= 0; i--) DateTime(today.year, today.month, today.day - i)];
  final dayActive = List<int>.filled(days.length, 0);
  final dayLeisure = List<int>.filled(days.length, 0);
  for (var i = 0; i < kWeekHoursMin; i++) {
    final k = cells[kWeekHoursMin + i];
    if (k == _Kind.none) continue;
    if (k == _Kind.sleep) {
      sleep++;
    } else if (k == _Kind.basic) {
      basic++;
    } else {
      final t = start.add(Duration(minutes: i));
      final d = DateTime(t.year, t.month, t.day);
      final idx = days.indexWhere((x) => x == d);
      if (k == _Kind.leisure) {
        leisure++;
        if (idx >= 0) dayLeisure[idx]++;
      } else {
        active++;
        if (i < 24 * 60) leaving++;
        if (idx >= 0) dayActive[idx]++;
      }
    }
  }
  return WeekHours(
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
