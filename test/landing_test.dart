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
}
