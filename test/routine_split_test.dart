import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/routine_moments.dart';

Activity _r(String id, int target, List<String> split) => Activity(
    id: id, domainId: 'd', name: id, role: ActivityRole.generic, type: 'habit', goalMin: 1,
    habitFreq: HabitFreq.daily, habitTarget: target, createdAt: DateTime(2026, 1, 1), splitMoments: split);

void main() {
  int h(int hh, [int mm = 0]) => hh * 60 + mm;

  test('20 pompes matin + soir : 10 et 10, le reste glisse au soir', () {
    final p = _r('pompes', 20, [kMomentEvening, kMomentMorning]);
    expect(splitMomentsOf(p), [kMomentMorning, kMomentEvening]);
    var s = momentShareOf(p, dayDone: 7, dayTarget: 20, nowMin: h(9))!;
    expect((s.moment, s.done, s.target), (kMomentMorning, 7, 10));
    expect(s.label, '7 / 10 ce matin');
    s = momentShareOf(p, dayDone: 10, dayTarget: 20, nowMin: h(9))!;
    expect((s.moment, s.done, s.target), (kMomentEvening, 0, 10));
    s = momentShareOf(p, dayDone: 15, dayTarget: 20, nowMin: h(9))!;
    expect((s.moment, s.done, s.target), (kMomentEvening, 5, 10));
    // Matin fini sans sa part : tout le reste ce soir.
    s = momentShareOf(p, dayDone: 4, dayTarget: 20, nowMin: h(12))!;
    expect((s.moment, s.done, s.target), (kMomentEvening, 0, 16));
    expect(momentShareOf(p, dayDone: 20, dayTarget: 20, nowMin: h(21)), isNull);
  });

  test('Repas 2 midi + soir, 3 sur 2 moments, cible < moments, un seul moment', () {
    final repas = _r('repas', 2, [kMomentMidday, kMomentEvening]);
    expect(momentShareOf(repas, dayDone: 0, dayTarget: 2, nowMin: h(12, 30))!.moment, kMomentMidday);
    expect(momentShareOf(repas, dayDone: 1, dayTarget: 2, nowMin: h(12, 30))!.moment, kMomentEvening);
    final trois = _r('x', 3, [kMomentMorning, kMomentEvening]);
    expect(momentShareOf(trois, dayDone: 0, dayTarget: 3, nowMin: h(8))!.target, 2);
    expect(momentShareOf(trois, dayDone: 2, dayTarget: 3, nowMin: h(8))!.target, 1);
    final un = _r('y', 1, [kMomentMorning, kMomentEvening]);
    expect(momentShareOf(un, dayDone: 0, dayTarget: 1, nowMin: h(20))!.moment, kMomentMorning);
    expect(momentShareOf(_r('z', 4, [kMomentMorning]), dayDone: 0, dayTarget: 4, nowMin: h(8)), isNull);
  });

  test('buildRoutineDay : la routine répartie change de moment après sa part', () {
    final repas = _r('repas', 2, [kMomentMidday, kMomentEvening]);
    final now = DateTime(2026, 10, 30, 12, 45);
    var day = buildRoutineDay(activities: [repas], hits: const [], now: now);
    expect(day.slots.single.moment, kMomentMidday);
    day = buildRoutineDay(activities: [repas], hits: [HabitHit(habitId: 'repas', ts: DateTime(2026, 10, 30, 12, 30))], now: now);
    expect(day.slots.single.moment, kMomentEvening);
    expect(day.slots.single.pushed, isFalse);
    expect(day.queue, isEmpty);
  });
}
