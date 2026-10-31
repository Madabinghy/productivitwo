import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/planning.dart';
import 'package:productivitwo_v1/utils/week_capacity.dart';

ScheduleBlock b(String start, int min, {String status = 'pending', String? gcal}) =>
    ScheduleBlock(startTime: start, durationMin: min, title: 'x', status: status, gcalEventId: gcal);

void main() {
  test('créneaux libres de la fenêtre, hors blocs posés', () {
    final gaps = freeGaps([b('06:30', 120), b('12:00', 60), b('18:00', 90)], const DayWindow(8 * 60, 22 * 60));
    expect([for (final g in gaps) (g.startMin, g.endMin)], [(510, 720), (780, 1080), (1170, 1320)]);
    expect(freeMinutes(gaps), 210 + 300 + 150);
  });

  test('un bloc supprimé ou sauté ne prend pas de place', () {
    final gaps = freeGaps([b('09:00', 60, status: 'skipped')], const DayWindow(8 * 60, 12 * 60));
    expect(gaps.single.minutes, 240);
  });

  test('proposer : premier créneau qui tient, budget respecté, quart d\'heure', () {
    final gaps = [const PlanGap(510, 600), const PlanGap(780, 1080)];
    final wants = [
      const PlanWant(activityId: 'a', title: 'Formation', minutes: 90, reason: 'objectif'),
      const PlanWant(activityId: 'b', title: 'Courir', minutes: 45, reason: 'montre'),
      const PlanWant(activityId: 'c', title: 'Chérubins', minutes: 120, reason: 'plan'),
    ];
    final p = proposeDay(gaps, wants, 200);
    expect([for (final x in p) (x.want.activityId, x.startMin, x.minutes)], [('a', 510, 90), ('b', 780, 45), ('c', 840, 60)]);
    expect(p.fold<int>(0, (s, x) => s + x.minutes), lessThanOrEqualTo(200));
  });

  test('Cap tenu : posé la veille et tenu à 70 %', () {
    DailySchedule s(List<ScheduleBlock> blocks, {DateTime? at, String by = 'plan'}) =>
        DailySchedule(date: '2026-11-01', generatedBy: by, plannedAt: at ?? DateTime(2026, 10, 31, 21), blocks: blocks);
    final held = [b('09:00', 60, status: 'done'), b('11:00', 60, status: 'done'), b('14:00', 60, status: 'done'), b('16:00', 60)];
    expect(capHeld(s(held)), isTrue);
    expect(capHeld(s(held, at: DateTime(2026, 11, 1, 7))), isFalse);
    expect(capHeld(s(held, by: 'claude')), isFalse);
    expect(capHeld(s([b('09:00', 60, status: 'done'), b('11:00', 60), b('13:00', 60, gcal: 'g', status: 'done')])), isFalse);
    expect(capHeldCount([s(held)], '2026-11-01'), 0);
    expect(capHeldCount([s(held)], '2026-11-02'), 1);
  });
}
