import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/badges_logic.dart';
import 'package:productivitwo_v1/utils/elan_logic.dart';

void main() {
  BadgeState s(String id, List<int> tiers, int level) =>
      BadgeState(def: BadgeDef(id: id, family: BadgeFamily.routines, name: id, symbol: 'flame', tiers: tiers), level: level, value: 0);

  test('clés des paliers acquis et nouveautés par rapport au vu', () {
    final d = BadgeDeck([s('a', kRoutineTiers, 2), s('b', const [1], 1), s('c', const [1], 0)]);
    expect(acquiredTierKeys(d), {'a#1', 'a#2', 'b#1'});
    expect(newTierKeys(d, {'a#1', 'b#1'}), {'a#2'});
    expect(newTierKeys(d, acquiredTierKeys(d)), isEmpty);
  });

  test('élan d\'une routine : les fenêtres qui contiennent le hit atteignant la cible', () {
    final a = Activity(id: 'med', domainId: 'd', name: 'med', role: ActivityRole.generic, type: 'habit', goalMin: 1, habitFreq: HabitFreq.daily, habitTarget: 2, createdAt: DateTime(2026, 1, 1));
    MoodMark m(DateTime at, int v) => MoodMark(at: at, ymd: '2026-10-${at.day}', kind: kMoodElan, value: v, moment: elanBucket(at.hour * 60));
    final marks = [m(DateTime(2026, 10, 24, 8), 1), m(DateTime(2026, 10, 24, 14), 4), m(DateTime(2026, 10, 25, 8), 2)];
    final hits = [
      HabitHit(habitId: 'med', ts: DateTime(2026, 10, 24, 9)),
      HabitHit(habitId: 'med', ts: DateTime(2026, 10, 24, 15)), // 2e hit : cible atteinte dans la fenêtre « 4 »
      HabitHit(habitId: 'med', ts: DateTime(2026, 10, 25, 9)), // un seul hit : cible non atteinte
    ];
    final f = routineElanFacts(a, marks, hits);
    expect(f.count, 1);
    expect(f.mean, 4);
    expect(f.victories, 0);
  });

  test('élan d\'un objectif : le début des sessions sur ses activités engagées', () {
    final o = StrategicObjective(title: 'Livre', timeCommitments: [ObjectiveTimeCommitment(activityId: 'ecrire', weeklyMin: 60)]);
    final marks = [MoodMark(at: DateTime(2026, 10, 24, 8), ymd: '2026-10-24', kind: kMoodElan, value: 2, moment: 'matin')];
    final sessions = [
      Session(activityId: 'ecrire', startAt: DateTime(2026, 10, 24, 9), endAt: DateTime(2026, 10, 24, 10)),
      Session(activityId: 'autre', startAt: DateTime(2026, 10, 24, 11), endAt: DateTime(2026, 10, 24, 12)),
    ];
    final f = objectiveElanFacts(o, marks, sessions);
    expect(f.count, 1);
    expect(f.victories, 1);
  });
}
