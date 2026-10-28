import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/palier_colors.dart' show comparePct;
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
    expect((s.routinesReached, s.routinesTotal), (1, 1)); // 3 faits / 3 attendus mercredi → au rythme
    final m = rows.firstWhere((r) => r.domain.id == 'm');
    expect((m.doneMin, m.goalMinDay, m.expectedMin), (10, 20, 60)); // minimum réglé à la main
    expect(m.pctInt, 17);
    expect(rows.first.domain.id, 's'); // sous 100 %, le plus proche de 100 d'abord (75 % avant 17 %)
  });

  test('weekSummary : engagements des objectifs seulement quand il y en a, chrono de la semaine', () {
    final o = StrategicObjective(title: 'Forme', routineCommitments: [ObjectiveRoutineCommitment(activityId: 'pompes')]);
    final w = weekSummary(activities: acts, hits: hits, sessions: sessions, objectives: [o], now: now);
    expect(w.fromObjectives, isTrue);
    expect(w.engagements.single.label, 'pompes');
    expect(w.pctWeek, 43); // 3 / 7 sur la semaine entière
    expect(w.pct, 100); // attendu à ce jour = 3 (mercredi) → au rythme
    expect(w.kept, 1);
    expect(w.keptWeek, 0);
    expect(w.chronoMin, 100);
    final all = weekSummary(activities: acts, hits: hits, sessions: sessions, objectives: const [], now: now);
    expect(all.fromObjectives, isFalse);
    expect(all.engagements.length, 1);
  });

  test('expectedToDate : prorata arrondi, borné à la cible', () {
    expect(expectedToDate(3, 1), 0); // lundi : rien d'attendu encore
    expect(expectedToDate(3, 3), 1);
    expect(expectedToDate(3, 7), 3);
    expect(expectedToDate(7, 1), 1); // quotidienne : 1 par jour
    expect(expectedToDate(7, 4), 4);
    expect(expectedToDate(1, 3), 0);
    expect(expectedToDate(1, 4), 1);
  });

  test('weekSummary : un lundi, rien d\'attendu → 100 % et au rythme', () {
    final monday = DateTime(2026, 10, 26, 9);
    final w = weekSummary(activities: acts, hits: const [], sessions: const [], objectives: const [], now: monday);
    // quotidienne cible 7 → attendu lundi = 1, rien de fait → 0 %
    expect(w.pct, 0);
    final weekly = Activity(
        id: 'yoga', domainId: 's', name: 'yoga', role: ActivityRole.generic, type: 'habit', goalMin: 0,
        habitFreq: HabitFreq.weekly, habitTarget: 3, createdAt: DateTime(2026, 1, 1));
    final w2 = weekSummary(activities: [weekly], hits: const [], sessions: const [], objectives: const [], now: monday);
    expect(w2.pct, 100);
    expect(w2.kept, 1);
    expect(w2.pctWeek, 0);
  });

  test('domainWeeks : sous 100 % décroissant, puis ≥ 100 % croissant, puis sans minimum, veille en fin', () {
    DomainWeek w(String id, int done, int goal, {bool rest = false}) => DomainWeek(
        domain: Domain(id: id, name: id), doneMin: done, goalMinDay: goal, daysElapsed: 1, routinesReached: 0, routinesTotal: 0, restUntil: rest ? '2026-12-31' : null);
    final rows = [w('a', 60, 60), w('b', 30, 60), w('c', 90, 60), w('d', 50, 60), w('e', 10, 0), w('f', 0, 0, rest: true)]..sort(compareDomainWeeks);
    expect(rows.map((r) => r.domain.id).toList(), ['d', 'b', 'a', 'c', 'e', 'f']); // 83 %, 50 %, 100 %, 150 %, sans minimum, veille
  });

  test('comparePct : sous 100 décroissant, puis 100 et plus croissant', () {
    final v = [120, 40, 100, 83, 0, 150]..sort(comparePct);
    expect(v, [83, 40, 0, 100, 120, 150]);
  });
}
