import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/engagement_stats.dart';
import 'package:productivitwo_v1/utils/objective_progress.dart';

void main() {
  Activity habit(String id, int target, {HabitFreq freq = HabitFreq.daily}) => Activity(
        id: id,
        domainId: 'd',
        name: id,
        role: ActivityRole.generic,
        type: 'habit',
        goalMin: 1,
        habitFreq: freq,
        habitTarget: target,
        createdAt: DateTime(2026, 1, 1),
      );

  test('crédit partiel : 38 pompes sur 56 pèsent 0,68 et ne sont pas « tenues » ; 46 sur 56 le sont', () {
    final a = EngagementStat(id: 'p', domainId: 'd', label: 'Pompes', target: 56, done: 38);
    expect(a.ratio, closeTo(.68, .01));
    expect(a.kept, isFalse);
    final b = EngagementStat(id: 'p', domainId: 'd', label: 'Pompes', target: 56, done: 46);
    expect(b.kept, isTrue, reason: '82 % ≥ 80 %');
    final full = EngagementStat(id: 'e', domainId: 'd', label: 'Eau', target: 42, done: 50);
    expect(full.ratio, 1);
    expect(engagementPct([a, b, full]), 83); // (0,68 + 0,82 + 1) / 3
    expect(engagementPct(const []), 0);
  });

  test('tendance : moyenne des parts faites, plus la part des engagements tenus', () {
    final now = DateTime.now();
    final hits = <HabitHit>[
      for (var d = 0; d < 7; d++)
        for (var k = 0; k < 4; k++) HabitHit(habitId: 'p', ts: now.subtract(Duration(days: d, hours: 1, minutes: k))),
    ];
    final trend = fourWeekTrend(activities: [habit('p', 8)], hits: hits);
    expect(trend.last.label, '7 j');
    expect(trend.last.pct, 50, reason: '28 hits sur 56 = 50 %, au lieu de 0 % en tout ou rien');
  });

  test('objectif : le pourcentage hebdo se rapporte à l\'attendu à ce jour', () {
    final o = StrategicObjective(title: 'Courir', timeCommitments: [ObjectiveTimeCommitment(activityId: 'run', weeklyMin: 140)]);
    final monday = DateTime(2026, 10, 26, 10); // lundi
    final run = Activity(id: 'run', domainId: 'd', name: 'Courir', role: ActivityRole.generic, type: 'time', goalMin: 20, createdAt: DateTime(2026, 1, 1));
    final sessions = [Session(activityId: 'run', startAt: DateTime(2026, 10, 26, 7), endAt: DateTime(2026, 10, 26, 7, 20))];
    final p = computeObjectiveProgress(o, [run], sessions, const [], monday);
    expect(p.weekElapsed, closeTo(1 / 7, 1e-9));
    expect(p.weekPercent, closeTo(1.0, 1e-9), reason: '20 min faites, 20 attendues lundi (140 / 7)');
    final wed = computeObjectiveProgress(o, [run], sessions, const [], DateTime(2026, 10, 28, 10));
    expect(wed.weekPercent, closeTo(20 / 60, 1e-9), reason: 'mercredi : 60 min attendues');
  });
}
