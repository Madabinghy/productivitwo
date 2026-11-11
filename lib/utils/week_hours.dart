import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/recharge.dart' show isBasicNeedName, isSleepName;

/// Les 7 derniers jours glissants (maquette validée 2026-11-11 « Jauge des 168 heures ») : la fenêtre est
/// toujours maintenant − 168 h → maintenant, minute par minute. Une minute n'est comptée qu'une fois :
/// sommeil d'abord, puis besoins de base (repas, sieste), puis actif ; ce qui n'est couvert par aucun
/// chrono est « dans le flou ».
const kWeekHoursMin = 168 * 60;

class WeekHours {
  final int activeMin, basicMin, sleepMin;
  /// Heures actives des 168 h d'avant (maintenant − 336 h → maintenant − 168 h).
  final int prevActiveMin;
  /// Heures actives des 24 premières heures de la fenêtre : elles en sortent d'ici demain à la même heure.
  final int leavingMin;
  /// Minutes actives par jour calendaire, du plus ancien (en partie dans la fenêtre) à aujourd'hui.
  final List<int> dayActive;
  final List<DateTime> days;
  const WeekHours({
    required this.activeMin,
    required this.basicMin,
    required this.sleepMin,
    required this.prevActiveMin,
    required this.leavingMin,
    required this.dayActive,
    required this.days,
  });
  int get trackedMin => activeMin + basicMin + sleepMin;
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

enum _Kind { none, active, basic, sleep }

int _rank(_Kind k) => switch (k) { _Kind.sleep => 3, _Kind.basic => 2, _Kind.active => 1, _Kind.none => 0 };

/// Remplit [cells] (une case par minute depuis [from]) avec la catégorie la plus forte de chaque minute.
void _paint(List<_Kind> cells, DateTime from, List<Session> sessions, Map<String, Activity> byId, DateTime now) {
  final to = from.add(Duration(minutes: cells.length));
  for (final s in sessions) {
    if (s.deleted) continue;
    final end = s.endAt ?? now;
    if (!end.isAfter(from) || !s.startAt.isBefore(to)) continue;
    final a = byId[s.activityId];
    final name = a?.name;
    final kind = isSleepName(name) ? _Kind.sleep : (isBasicNeedName(name) ? _Kind.basic : _Kind.active);
    final i0 = s.startAt.isBefore(from) ? 0 : s.startAt.difference(from).inMinutes;
    final i1 = (end.isAfter(to) ? cells.length : end.difference(from).inMinutes).clamp(0, cells.length);
    for (var i = i0; i < i1; i++) {
      if (_rank(kind) > _rank(cells[i])) cells[i] = kind;
    }
  }
}

WeekHours weekHours({required List<Session> sessions, required List<Activity> activities, required DateTime now}) {
  final byId = {for (final a in activities) a.id: a};
  final nowMin = DateTime(now.year, now.month, now.day, now.hour, now.minute);
  final start = nowMin.subtract(const Duration(minutes: kWeekHoursMin));
  final prevStart = start.subtract(const Duration(minutes: kWeekHoursMin));
  final cells = List<_Kind>.filled(kWeekHoursMin * 2, _Kind.none);
  _paint(cells, prevStart, sessions, byId, now);
  var active = 0, basic = 0, sleep = 0, prev = 0, leaving = 0;
  for (var i = 0; i < kWeekHoursMin; i++) {
    if (cells[i] == _Kind.active) prev++;
  }
  final today = DateTime(now.year, now.month, now.day);
  final days = [for (var i = 7; i >= 0; i--) DateTime(today.year, today.month, today.day - i)];
  final dayActive = List<int>.filled(days.length, 0);
  for (var i = 0; i < kWeekHoursMin; i++) {
    final k = cells[kWeekHoursMin + i];
    if (k == _Kind.none) continue;
    if (k == _Kind.sleep) {
      sleep++;
    } else if (k == _Kind.basic) {
      basic++;
    } else {
      active++;
      if (i < 24 * 60) leaving++;
      final t = start.add(Duration(minutes: i));
      final d = DateTime(t.year, t.month, t.day);
      final idx = days.indexWhere((x) => x == d);
      if (idx >= 0) dayActive[idx]++;
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
  );
}
