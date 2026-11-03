import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/landing.dart';

ScheduleBlock b(String start, String title, {String? gcal, String? task, String? time, String status = 'pending'}) =>
    ScheduleBlock(startTime: start, durationMin: 60, title: title, gcalEventId: gcal, taskId: task, timeBlock: time, status: status);

void main() {
  final now = DateTime(2026, 11, 3, 12, 55);

  test('le prochain rendez-vous daté, pas les blocs souples', () {
    final blocks = [
      b('13:30', 'Petites choses', time: 'small'),
      b('13:40', 'Lecture'),
      b('14:00', 'Cours 6e', gcal: 'e1'),
      b('15:00', 'Séance', task: 't1'),
    ];
    final n = nextFixed(blocks, now, 300, sessionTaskIds: {'t1'})!;
    expect(n.block.title, 'Cours 6e');
    expect(n.inMin, 65);
    expect(n.landingAt, DateTime(2026, 11, 3, 13, 50));
    expect(inLabel(n.inMin), 'dans 1 h 05');
  });

  test('une séance compte, un rendez-vous passé ou fait non', () {
    final blocks = [
      b('12:00', 'Réunion', gcal: 'e0'),
      b('13:15', 'Cours', gcal: 'e1', status: 'done'),
      b('16:00', 'Séance 5e', task: 't1'),
    ];
    expect(nextFixed(blocks, now, 300, sessionTaskIds: {'t1'})!.block.title, 'Séance 5e');
    expect(nextFixed(blocks, now, 300), isNull);
  });

  test('sommeil et repas ne sonnent pas', () {
    expect(nextFixed([b('13:00', 'Déjeuner', gcal: 'e'), b('22:30', 'Sommeil', gcal: 'f')], now, 300), isNull);
  });

  test('libellés', () {
    expect(inLabel(0), 'maintenant');
    expect(inLabel(35), 'dans 35 min');
    expect(inLabel(120), 'dans 2 h');
  });

  test('point d’étape : prochains blocs, datés ou souples', () {
    final l = upcomingBlocks([
      b('16:00', 'Petites choses', time: 'small'),
      b('14:00', 'Cours 6e', gcal: 'e1'),
      b('12:00', 'Passé'),
      b('13:00', 'Déjeuner'),
    ], now, 300);
    expect(l.map((x) => x.block.title), ['Cours 6e', 'Petites choses']);
    expect(l.first.fixed, isTrue);
    expect(l.last.fixed, isFalse);
  });

  test('séries qui se perdent ce soir', () {
    final l = seriesAtRisk(const [
      SeriesAtRisk('Pompes', 0, 20, 12),
      SeriesAtRisk('Eau', 6, 6, 30),
      SeriesAtRisk('Lecture', 0, 1, 1),
      SeriesAtRisk('Prière', 0, 1, 4),
    ]);
    expect(l.map((r) => r.name), ['Pompes', 'Prière']);
  });

  test('fin du bloc Deep work : continuer décale le souple, jamais le daté', () {
    final deep = ScheduleBlock(startTime: '13:30', durationMin: 120, title: 'Deep work', timeBlock: 'deep');
    final small = b('16:00', 'Petites choses', time: 'small');
    final lecture = b('17:00', 'Lecture');
    final reunion = b('18:30', 'Réunion parents', gcal: 'e');
    final apres = b('20:00', 'Rangement');
    final blocks = [deep, small, lecture, reunion, apres];
    expect(currentDeepBlock(blocks, DateTime(2026, 11, 3, 15, 0), 300), same(deep));
    expect(softFollowing(blocks, deep).map((x) => x.title), ['Petites choses', 'Lecture']);
    expect(continueRoom(blocks, deep), 30);
    final changed = extendDeep(blocks, deep, 30);
    expect(changed.length, 3);
    expect(deep.durationMin, 150);
    expect(small.startTime, '16:30');
    expect(lecture.startTime, '17:30');
    expect(reunion.startTime, '18:30');
    expect(apres.startTime, '20:00');
  });

  test('continuer : pas plus que ce que laisse le prochain rendez-vous', () {
    final deep = ScheduleBlock(startTime: '13:30', durationMin: 120, title: 'Deep work', timeBlock: 'deep');
    expect(continueRoom([deep, b('15:50', 'Cours', gcal: 'e')], deep), 10);
    expect(continueRoom([deep, b('15:45', 'Cours', gcal: 'e')], deep), 0);
  });

  test('reprise : ce qui est passé pendant qu’on était dedans', () {
    final l = missedWhileAway([
      b('15:00', 'Avant'),
      b('16:00', 'Petites choses'),
      b('16:30', 'Appel', gcal: 'e'),
      b('17:00', 'Pas fini'),
      ScheduleBlock(startTime: '15:30', durationMin: 60, title: 'Deep work', timeBlock: 'deep'),
    ], DateTime(2026, 11, 3, 16, 10), DateTime(2026, 11, 3, 17, 40), 300);
    expect(l.map((x) => x.title), ['Petites choses', 'Appel']);
  });
}
