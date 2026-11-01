import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/sleep_stats.dart';

void main() {
  final sleep = Activity(id: 's', domainId: 'd', name: 'Sommeil', type: 'time', goalMin: 450);
  Session ses(DateTime a, DateTime? b) => Session(activityId: 's', startAt: a, endAt: b);
  const dayStart = 5 * 60;

  test('une nuit = ses chronos, le réveil ne compte pas, doublons fusionnés', () {
    final n = sleepNightList(
      sessions: [
        ses(DateTime(2026, 10, 31, 0, 20), DateTime(2026, 10, 31, 3, 5)),
        ses(DateTime(2026, 10, 31, 3, 25), DateTime(2026, 10, 31, 6, 30)),
        ses(DateTime(2026, 10, 31, 3, 30), DateTime(2026, 10, 31, 4)), // doublon
        ses(DateTime(2026, 10, 29, 23), DateTime(2026, 10, 30, 6, 30)),
      ],
      activities: [sleep],
      now: DateTime(2026, 10, 31, 9),
      dayStartMin: dayStart,
      nights: 3,
    );
    expect(n.length, 3);
    expect(n[0], isNull);
    expect(n[1]!.minutes, 450);
    final last = n[2]!;
    expect(last.minutes, 165 + 185);
    expect(last.awakeMin, 20);
    expect(clockOf(bedClockMin(last.bed)), '00:20');
    expect(last.nextYmd, '2026-10-31');
    expect(fmtNight(last.minutes), '5 h 50');
  });

  test('cible, dette, coucher moyen de part et d’autre de minuit, régularité', () {
    final a = SleepNight(DateTime(2026, 10, 30, 5), [(start: DateTime(2026, 10, 29, 23, 40), end: DateTime(2026, 10, 30, 7))]);
    final b = SleepNight(DateTime(2026, 10, 31, 5), [(start: DateTime(2026, 10, 31, 0, 20), end: DateTime(2026, 10, 31, 6, 30))]);
    final st = sleepStats([a, null, b], 450);
    expect(st.nights, 2);
    expect(st.avgMin, (440 + 370) ~/ 2);
    expect(st.debtMin, 10 + 80);
    expect(clockOf(st.avgBed!), '00:00');
    expect(st.spreadMin, 20);
    expect(sleepTargetMin(sleep), 450);
    expect(sleepTargetMin(Activity(id: 'x', domainId: 'd', name: 'Sommeil', type: 'time', goalMin: 30)), kSleepDefaultTargetMin);
  });

  test('bloc Sommeil prévu : le plus récent, autour de minuit', () {
    final s1 = DailySchedule(date: '2026-10-29', blocks: [ScheduleBlock(startTime: '22:30', durationMin: 480, title: 'Sommeil')]);
    final s2 = DailySchedule(date: '2026-10-30', blocks: [
      ScheduleBlock(startTime: '09:00', durationMin: 60, title: 'Contenu'),
      ScheduleBlock(startTime: '23:00', durationMin: 450, title: 'Dodo', activityId: 's'),
    ]);
    final p = plannedSleep([s1, s2], {'s'});
    expect(clockOf(p!.bed), '23:00');
    expect(p.durationMin, 450);
    expect(plannedSleep([DailySchedule(date: '2026-10-30')], {'s'}), isNull);
  });

  test('nuits longues contre courtes : il faut 5 nuits de chaque côté', () {
    SleepNight night(int day, int min) =>
        SleepNight(DateTime(2026, 10, day, 5), [(start: DateTime(2026, 10, day, 5).subtract(Duration(minutes: min + 30)), end: DateTime(2026, 10, day, 4, 30))]);
    final nights = [for (var d = 1; d <= 5; d++) night(d, 460), for (var d = 6; d <= 10; d++) night(d, 340), night(11, 400)];
    final next = {
      for (var d = 1; d <= 5; d++) '2026-10-${d.toString().padLeft(2, '0')}': const SleepNextDay(elan: 3.4, lowShare: 0.18, actions: 6, perfect: true),
      for (var d = 6; d <= 10; d++) '2026-10-${d.toString().padLeft(2, '0')}': const SleepNextDay(elan: 2.3, lowShare: 0.41, actions: 3),
    };
    final imp = sleepImpact(nights, next, 450, '2026-10-31');
    expect(imp.enough, isTrue);
    expect(imp.long.days, 5);
    expect(imp.short.days, 5);
    expect(imp.long.perfect, 5);
    expect(imp.short.actions, 3);
    expect(imp.sentence, 'Une nuit courte, et ta flemme double le lendemain.');
    final few = sleepImpact(nights.take(7), next, 450, '2026-10-31');
    expect(few.enough, isFalse);
    expect(few.sentence, isNull);
  });
}
