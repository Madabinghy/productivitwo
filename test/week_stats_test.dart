import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/week_stats.dart';

void main() {
  final now = DateTime(2026, 10, 28, 12); // mercredi → 3 jours écoulés
  Activity time(String id, String dom, int goal) =>
      Activity(id: id, domainId: dom, name: id, role: ActivityRole.generic, type: 'time', goalMin: goal, createdAt: DateTime(2026, 1, 1));
  Activity habit(String id, String dom) => Activity(
      id: id, domainId: dom, name: id, role: ActivityRole.generic, type: 'habit', goalMin: 0, habitFreq: HabitFreq.daily, habitTarget: 1, createdAt: DateTime(2026, 1, 1));
  final sante = Domain(id: 's', name: 'Santé');
  final maison = Domain(id: 'm', name: 'Maison', autoGoal: false, goalMinDay: 20);
  final acts = [time('muscu', 's', 30), time('course', 's', 10), habit('pompes', 's'), time('rangement', 'm', 0)];
  final sessions = [
    Session(activityId: 'muscu', startAt: DateTime(2026, 10, 26, 18), endAt: DateTime(2026, 10, 26, 19)), // lundi 60
    Session(activityId: 'muscu', startAt: DateTime(2026, 10, 25, 18), endAt: DateTime(2026, 10, 25, 19)), // dimanche : hors semaine
    Session(activityId: 'course', startAt: DateTime(2026, 10, 28, 11, 30)), // ouverte 30 min
    Session(activityId: 'rangement', startAt: DateTime(2026, 10, 27, 9), endAt: DateTime(2026, 10, 27, 9, 10)),
  ];
  final hits = [for (var d = 26; d <= 28; d++) HabitHit(habitId: 'pompes', ts: DateTime(2026, 10, d, 8))];

  test('minutesByActivity : depuis lundi, session ouverte jusqu\'à maintenant, dimanche exclu', () {
    final m = minutesByActivity(sessions, DateTime(2026, 10, 26), now);
    expect(m, {'muscu': 60, 'course': 30, 'rangement': 10});
  });

  test('domainWeeks : fait / minimum × jours écoulés, routines tenues, tri par retard', () {
    final rows = domainWeeks(domains: [maison, sante], activities: acts, sessions: sessions, hits: hits, now: now);
    final s = rows.firstWhere((r) => r.domain.id == 's');
    expect((s.doneMin, s.goalMinDay, s.expectedMin, s.weekMin), (90, 40, 120, 280));
    expect(s.pctInt, 75);
    expect(s.deltaMin, -30);
    expect((s.routinesReached, s.routinesTotal), (0, 1)); // 3 / 7 < 80 %
    final m = rows.firstWhere((r) => r.domain.id == 'm');
    expect((m.doneMin, m.goalMinDay, m.expectedMin), (10, 20, 60)); // minimum réglé à la main
    expect(m.pctInt, 17);
    expect(rows.first.domain.id, 'm'); // le plus en retard d'abord
  });

  test('weekSummary : engagements des objectifs seulement quand il y en a, chrono de la semaine', () {
    final o = StrategicObjective(title: 'Forme', routineCommitments: [ObjectiveRoutineCommitment(activityId: 'pompes')]);
    final w = weekSummary(activities: acts, hits: hits, sessions: sessions, objectives: [o], now: now);
    expect(w.fromObjectives, isTrue);
    expect(w.engagements.single.label, 'pompes');
    expect(w.pct, 43); // 3 / 7
    expect(w.chronoMin, 100);
    final all = weekSummary(activities: acts, hits: hits, sessions: sessions, objectives: const [], now: now);
    expect(all.fromObjectives, isFalse);
    expect(all.engagements.length, 1);
  });
}
