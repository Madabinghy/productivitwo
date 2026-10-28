import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/routines_today.dart';

Activity _r(String id, HabitFreq f, {int target = 1, bool deleted = false}) => Activity(
    id: id, name: id, domainId: 'd', type: 'habit', habitFreq: f, habitTarget: target, deleted: deleted);

void main() {
  test('routinesForToday : un hit à 1 h du matin compte pour la journée vécue de la veille', () {
    final a = _r('p', HabitFreq.daily, target: 1);
    final hit = HabitHit(habitId: 'p', ts: DateTime(2026, 10, 17, 1, 0));
    // À 2 h, même journée vécue que le hit → 1/1.
    expect(routinesForToday([a], [hit], DateTime(2026, 10, 17, 2, 0)).single.dayDone, 1);
    // À 9 h, nouvelle journée vécue → 0/1 ; bascule à minuit → toujours 1/1.
    expect(routinesForToday([a], [hit], DateTime(2026, 10, 17, 9, 0)).single.dayDone, 0);
    expect(routinesForToday([a], [hit], DateTime(2026, 10, 17, 9, 0), dayStartMin: 0).single.dayDone, 1);
  });

  final now = DateTime(2026, 10, 5, 15);
  HabitHit hit(String id, DateTime ts) => HabitHit(habitId: id, ts: ts);

  test('quotidienne : cible du jour ; hebdo : cible sur 7 j ; mensuelle et supprimée exclues', () {
    final acts = [
      _r('eau', HabitFreq.daily, target: 2),
      _r('sport', HabitFreq.weekly, target: 3),
      _r('bilan', HabitFreq.monthly),
      _r('vieux', HabitFreq.daily, deleted: true),
    ];
    final hits = [
      hit('eau', DateTime(2026, 10, 5, 8)),
      hit('eau', DateTime(2026, 10, 4, 8)), // hier : compte sur 7 j, pas aujourd'hui
      hit('sport', DateTime(2026, 10, 2, 18)),
    ];
    final r = routinesForToday(acts, hits, now);
    expect(r.map((x) => x.activity.id).toList(), ['eau', 'sport']);
    final eau = r.first;
    expect(eau.dayDone, 1);
    expect(eau.dayTarget, 2);
    expect(eau.reached, isFalse);
    expect(eau.progressLabel, "1 / 2 aujourd'hui");
    expect(r[1].progressLabel, '1 / 3 sur 7 j');
  });

  test('atteintes en fin de liste ; non atteintes par avancement décroissant', () {
    final acts = [
      _r('a', HabitFreq.daily, target: 4),
      _r('b', HabitFreq.daily, target: 1),
      _r('c', HabitFreq.daily, target: 2),
    ];
    final hits = [
      hit('b', DateTime(2026, 10, 5, 7)), // atteinte
      hit('c', DateTime(2026, 10, 5, 7)), // 1/2
    ];
    final r = routinesForToday(acts, hits, now);
    expect(r.map((x) => x.activity.id).toList(), ['c', 'a', 'b']);
    expect(r.last.reached, isTrue);
  });

  group('todayMark', () {
    test('quotidienne → jamais (le compte du jour suffit)', () {
      expect(todayMark(HabitFreq.daily, 2), isNull);
    });
    test('hebdo sans +1 aujourd\'hui → rien', () {
      expect(todayMark(HabitFreq.weekly, 0), isNull);
    });
    test('hebdo validée une fois → « faite aujourd\'hui », plusieurs → « ×n »', () {
      expect(todayMark(HabitFreq.weekly, 1), '✓ faite aujourd\'hui');
      expect(todayMark(HabitFreq.monthly, 3), '✓ ×3 aujourd\'hui');
    });
  });
}
