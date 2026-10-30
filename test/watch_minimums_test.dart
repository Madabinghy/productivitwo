import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/watch_minimums.dart';

Session _s(String act, DateTime start, int min) => Session(activityId: act, startAt: start, endAt: start.add(Duration(minutes: min)));

void main() {
  final now = DateTime(2026, 10, 30, 18);
  Activity act(String id, int goal) => Activity(id: id, name: id, domainId: 'd', type: 'time', goalMin: goal, createdAt: DateTime(2026, 8, 1));

  test('une activité jamais au rythme bloque ; une activité tenue non', () {
    final courses = act('Courses', 6);
    final lecture = act('Lecture', 10);
    final sessions = [
      // Courses : 20 min tous les 10 jours (≈ 2 min / j) ; Lecture : 15 min chaque jour.
      for (var i = 1; i <= 40; i += 10) _s('Courses', DateTime(2026, 10, 30 - i, 9), 20),
      for (var i = 1; i <= 40; i++) _s('Lecture', DateTime(2026, 10, 30 - i, 21), 15),
    ];
    final b = watchBlockers(activities: [courses, lecture], sessions: sessions, now: now);
    expect(b.map((x) => x.activity.id), ['Courses']);
    expect(b.single.avgMin, 2);
    expect(b.single.suggestedMin, 2);
    expect(b.single.lostDays, greaterThanOrEqualTo(kBlockerLostDays));
  });

  test('« Garder » récent : la question ne revient pas ; plus de 30 j : elle revient', () {
    final courses = act('Courses', 6);
    expect(watchBlockers(activities: [courses], sessions: const [], now: now, keptYmd: {'Courses': '2026-10-20'}), isEmpty);
    expect(watchBlockers(activities: [courses], sessions: const [], now: now, keptYmd: {'Courses': '2026-09-01'}).length, 1);
  });

  test('rien fait : pas de « Baisser », seulement « Pas de minimum »', () {
    final b = watchBlockers(activities: [act('Voiture', 3)], sessions: const [], now: now).single;
    expect((b.avgMin, b.suggestedMin), (0, null));
  });

  test('sans minimum ou routine : jamais proposée', () {
    final r = Activity(id: 'r', name: 'r', domainId: 'd', type: 'habit', habitFreq: HabitFreq.daily, habitTarget: 1, createdAt: DateTime(2026, 8, 1));
    expect(watchBlockers(activities: [act('Zéro', 0), r], sessions: const [], now: now), isEmpty);
  });
}
