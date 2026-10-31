import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/day_settle.dart';
import 'package:productivitwo_v1/utils/planning.dart';
import 'package:productivitwo_v1/utils/today_logic.dart';

void main() {
  test('blocs de temps pour un budget', () {
    final w = timeBlockWants(330);
    expect(w.map((x) => '${timeKindOf(x.activityId)}:${x.minutes}').toList(), ['deep:120', 'small:45', 'deep:90', 'buffer:45']);
    expect(timeBlockWants(60).map((x) => timeKindOf(x.activityId)).toList(), ['small']);
    expect(timeBlockWants(600).where((x) => timeKindOf(x.activityId) == 'deep').length, 3);
    expect(timeKindOf('abc'), isNull);
  });

  test('bloc du programme d\'un bloc de temps', () {
    final b = planOrTimeBlockOf(PlannedBlock(PlanWant(activityId: timeWantId('deep', 1), title: 'Deep work', minutes: 120, reason: ''), 540, 120));
    expect(b.timeBlock, 'deep');
    expect(b.activityId, isNull);
    expect(b.startTime, '09:00');
    expect(ScheduleBlock.from(b.toJson()).timeBlock, 'deep');
  });

  test('tout chrono compte pour un bloc de temps, dans son créneau', () {
    final b = ScheduleBlock(startTime: '09:00', durationMin: 100, title: 'Deep work', category: 'project', timeBlock: 'deep');
    final day = DateTime(2026, 11, 2);
    final sessions = [
      Session(activityId: 'a', startAt: day.add(const Duration(hours: 9)), endAt: day.add(const Duration(hours: 9, minutes: 40))),
      Session(activityId: 'b', startAt: day.add(const Duration(hours: 9, minutes: 45)), endAt: day.add(const Duration(hours: 10, minutes: 10))),
      Session(activityId: 'c', startAt: day.add(const Duration(hours: 14)), endAt: day.add(const Duration(hours: 15))),
    ];
    expect(loggedMinForBlock(b, sessions, day.add(const Duration(hours: 9)), day.add(const Duration(hours: 10, minutes: 40))), 65);
    expect(sessionMatchesBlock(sessions.first, b), isTrue);
    expect(blocksSettledByChrono(blocks: [b], sessions: sessions, date: day, now: day.add(const Duration(days: 1))), [b]);
    expect(freeBlockToClaim([b], 9 * 60 + 30), isNull);
  });
}
