import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/budget_window.dart';
import 'package:productivitwo_v1/utils/week_stats.dart';

void main() {
  Activity time(String id, String dom) => Activity(id: id, domainId: dom, name: id, role: ActivityRole.generic, type: 'time', goalMin: 30, createdAt: DateTime(2026, 1, 1));

  test('fenêtre : 7 j = lundi ; 14 j = quinzaine à départ fixe (blocs de deux semaines depuis le 5 janv. 2026)', () {
    // 27 oct. 2026 = mardi ; lundi 26 oct. est 42 semaines après le 5 janv. → pair → début de quinzaine.
    expect(budgetWindowStart(DateTime(2026, 10, 27, 15), 7), DateTime(2026, 10, 26));
    expect(budgetWindowStart(DateTime(2026, 10, 27, 15), 14), DateTime(2026, 10, 26));
    expect(budgetDayIndex(DateTime(2026, 10, 27, 15), 14), 2);
    // Semaine suivante : impaire → la quinzaine a commencé le 26 oct.
    expect(budgetWindowStart(DateTime(2026, 11, 5), 14), DateTime(2026, 10, 26));
    expect(budgetDayIndex(DateTime(2026, 11, 5), 14), 11);
    expect(budgetWindowStart(DateTime(2026, 11, 9), 14), DateTime(2026, 11, 9));
    expect(budgetWindowLabel(DateTime(2026, 11, 5), 14), '14 j · jour 11 / 14');
    expect(budgetWindowLabel(DateTime(2026, 11, 5), 7), 'semaine · jour 4 / 7');
  });

  test('domainWeeks sur 14 j : attendu = minimum × jour de la quinzaine, total × 14', () {
    final d = Domain(id: 'd', name: 'Travail', autoGoal: false, goalMinDay: 60);
    final sessions = [
      Session(activityId: 'a', startAt: DateTime(2026, 10, 27, 9), endAt: DateTime(2026, 10, 27, 12)), // 180 (semaine 1 de la quinzaine)
      Session(activityId: 'a', startAt: DateTime(2026, 11, 3, 9), endAt: DateTime(2026, 11, 3, 10)), // 60
    ];
    final r = domainWeeks(domains: [d], activities: [time('a', 'd')], sessions: sessions, hits: const [], now: DateTime(2026, 11, 5, 12), windowDays: 14).single;
    expect((r.windowDays, r.daysElapsed, r.weekMin, r.expectedMin, r.doneMin), (14, 11, 840, 660, 240));
    final w7 = domainWeeks(domains: [d], activities: [time('a', 'd')], sessions: sessions, hits: const [], now: DateTime(2026, 11, 5, 12)).single;
    expect((w7.windowDays, w7.daysElapsed, w7.weekMin, w7.expectedMin, w7.doneMin), (7, 4, 420, 240, 60));
  });

  test('répartition par domaine et par jour, session coupée à minuit, jours futurs ignorés', () {
    final acts = [time('a', 'd1'), time('b', 'd2')];
    final sessions = [
      Session(activityId: 'a', startAt: DateTime(2026, 10, 26, 23), endAt: DateTime(2026, 10, 27, 1)), // 60 lundi + 60 mardi
      Session(activityId: 'b', startAt: DateTime(2026, 10, 27, 9), endAt: DateTime(2026, 10, 27, 9, 30)),
      Session(activityId: 'a', startAt: DateTime(2026, 10, 20, 9), endAt: DateTime(2026, 10, 20, 10)), // hors fenêtre
    ];
    final m = dailyMinutesByDomain(sessions, acts, DateTime(2026, 10, 26), 14, now: DateTime(2026, 10, 27, 12));
    expect(m['d1']!.sublist(0, 3), [60, 60, 0]);
    expect(m['d2']!.sublist(0, 3), [0, 30, 0]);
    expect(m['d1']!.length, 14);
  });
}
