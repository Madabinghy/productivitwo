import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/coach_signals.dart';

void main() {
  final now = DateTime(2026, 11, 1, 10);
  const dayStart = 5 * 60;

  test('7 jours clos, du plus ancien à hier', () {
    expect(signalDays(now, dayStart), ['2026-10-25', '2026-10-26', '2026-10-27', '2026-10-28', '2026-10-29', '2026-10-30', '2026-10-31']);
  });

  test('posé la veille : tenu, posé, pas posé', () {
    DailySchedule s(String status, {bool sameDay = false, DateTime? at}) => DailySchedule(
          date: '2026-10-31',
          generatedBy: 'plan',
          plannedAt: at ?? DateTime(2026, 10, 30, 21),
          plannedSameDay: sameDay,
          blocks: [ScheduleBlock(startTime: '09:00', durationMin: 60, title: 'Contenu', status: status)],
        );
    expect(capStateOf(s('done')), 'held');
    expect(capStateOf(s('pending')), 'posed');
    expect(capStateOf(s('done', sameDay: true)), isNull);
    expect(capStateOf(s('done', at: DateTime(2026, 10, 31, 8))), isNull);
    expect(capStateOf(DailySchedule(date: '2026-10-31')), isNull);
  });

  test('montre perdue : l’activité qui coince est nommée avec son domaine ; sommeil résumé', () {
    final work = Activity(id: 'w', domainId: 'travail', name: 'Courses', type: 'time', goalMin: 20, createdAt: DateTime(2026, 9, 1));
    final sleep = Activity(id: 's', domainId: 'sante', name: 'Sommeil', type: 'time', goalMin: 450, createdAt: DateTime(2026, 9, 1));
    final sessions = [
      for (var k = 1; k <= 7; k++) Session(activityId: 's', startAt: DateTime(2026, 11, 1 - k, 23), endAt: DateTime(2026, 11, 2 - k, 6)),
    ];
    final sig = coachSignals(now: now, dayStartMin: dayStart, activities: [work, sleep], sessions: sessions, hits: const [], schedules: const []);
    final watch = sig['watch'] as Map;
    expect((watch['days'] as List).every((d) => d == false), isTrue);
    expect((watch['blockers'] as List).first['name'], 'Courses');
    expect((watch['blockers'] as List).first['domainId'], 'travail');
    final sl = sig['sleep'] as Map;
    expect((sl['nights'] as List).whereType<int>().every((m) => m == 420), isTrue);
    expect(sl['avgMin'], 420);
    expect(sl['targetMin'], 450);
    expect((sig['parole'] as Map)['days'], List.filled(7, null));
    expect((sig['metronome'] as Map)['days'], List.filled(7, null));
  });
}
