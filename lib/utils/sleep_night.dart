import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/lived_day.dart' show livedDayStart;
import 'package:productivitwo_v1/utils/recharge.dart' show isSleepName;

/// La dernière nuit (pastille sommeil de la barre du haut, 2026-10-30) : les
/// chronos d'une activité de sommeil (`isSleepName` : Sommeil, Dormir, Nuit…)
/// qui commencent dans la fenêtre d'une nuit, de 10 h avant une bascule de
/// journée vécue à 10 h après (19 h → 15 h avec une bascule à 5 h). La nuit qui
/// vient prime dès qu'un chrono y a commencé (on dort, ou on vient de se
/// coucher après minuit) ; sinon la nuit passée. Un chrono qui tourne compte
/// jusqu'à [now]. Null = aucun chrono de sommeil.
class SleepNight {
  final int minutes;
  final bool running;
  const SleepNight(this.minutes, {this.running = false});
}

SleepNight? lastNightSleep({required List<Session> sessions, required List<Activity> activities, required DateTime now, required int dayStartMin}) {
  final sleepIds = {for (final a in activities) if (!a.deleted && isSleepName(a.name)) a.id};
  if (sleepIds.isEmpty) return null;
  final pivot = livedDayStart(now, dayStartMin);
  return _night(sessions, sleepIds, pivot.add(const Duration(days: 1)), now) ?? _night(sessions, sleepIds, pivot, now);
}

SleepNight? _night(List<Session> sessions, Set<String> sleepIds, DateTime pivot, DateTime now) {
  final from = pivot.subtract(const Duration(hours: 10));
  final to = pivot.add(const Duration(hours: 10));
  var min = 0;
  var running = false;
  var any = false;
  for (final s in sessions) {
    if (s.deleted || !sleepIds.contains(s.activityId)) continue;
    if (s.startAt.isBefore(from) || !s.startAt.isBefore(to) || s.startAt.isAfter(now)) continue;
    final end = s.endAt ?? now;
    if (s.endAt == null) running = true;
    any = true;
    final d = end.difference(s.startAt).inMinutes;
    if (d > 0) min += d;
  }
  return any ? SleepNight(min, running: running) : null;
}

/// « 7 h 12 » / « 45 min ».
String fmtSleep(int min) => min < 60 ? '$min min' : '${min ~/ 60} h ${(min % 60).toString().padLeft(2, '0')}';
