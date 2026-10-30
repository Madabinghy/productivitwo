import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/lived_day.dart' show livedDayStart;
import 'package:productivitwo_v1/utils/recharge.dart' show isSleepName;

/// Les dernières nuits (barres de sommeil de la barre du haut, 2026-10-30) :
/// une valeur par nuit, la plus ancienne d'abord — minutes de chrono d'une
/// activité de sommeil (`isSleepName`) commencé de 10 h avant à 7 h après la
/// bascule de journée vécue de cette nuit (19 h → 12 h avec une bascule à 5 h :
/// une sieste d'après-midi n'est pas une nuit),
/// null sans chrono. La dernière case est la nuit qui vient dès qu'un chrono
/// de sommeil y a commencé, sinon la nuit passée. Un chrono qui tourne compte
/// jusqu'à [now].
List<int?> sleepNights({required List<Session> sessions, required List<Activity> activities, required DateTime now, required int dayStartMin, int nights = 7}) {
  final ids = {for (final a in activities) if (!a.deleted && isSleepName(a.name)) a.id};
  final pivot = livedDayStart(now, dayStartMin);
  final next = _night(sessions, ids, pivot.add(const Duration(days: 1)), now);
  final last = next != null ? pivot.add(const Duration(days: 1)) : pivot;
  return [for (var k = nights - 1; k >= 0; k--) _night(sessions, ids, last.subtract(Duration(days: k)), now)];
}

/// Un chrono de sommeil tourne en ce moment.
bool sleepRunning(List<Session> sessions, List<Activity> activities) {
  final ids = {for (final a in activities) if (!a.deleted && isSleepName(a.name)) a.id};
  return sessions.any((s) => !s.deleted && s.endAt == null && ids.contains(s.activityId));
}

int? _night(List<Session> sessions, Set<String> ids, DateTime pivot, DateTime now) {
  if (ids.isEmpty) return null;
  final from = pivot.subtract(const Duration(hours: 10));
  final to = pivot.add(const Duration(hours: 7));
  var min = 0;
  var any = false;
  for (final s in sessions) {
    if (s.deleted || !ids.contains(s.activityId)) continue;
    if (s.startAt.isBefore(from) || !s.startAt.isBefore(to) || s.startAt.isAfter(now)) continue;
    any = true;
    final d = (s.endAt ?? now).difference(s.startAt).inMinutes;
    if (d > 0) min += d;
  }
  return any ? min : null;
}

/// « 7 h 12 » / « 45 min ».
String fmtSleep(int min) => min < 60 ? '$min min' : '${min ~/ 60} h ${(min % 60).toString().padLeft(2, '0')}';
