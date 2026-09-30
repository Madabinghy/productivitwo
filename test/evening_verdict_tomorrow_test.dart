import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/evening_verdict.dart';

ScheduleBlock _b(String start, int dur, {String status = 'pending', String title = 'b'}) =>
    ScheduleBlock(startTime: start, durationMin: dur, title: title, status: status);

void main() {
  final today = [
    _b('14:00', 60, title: 'Kahoot'),
    _b('05:00', 30, status: 'done', title: 'Lire la Bible'),
  ];

  test('demain inconnu : pas d\'heure inventée', () {
    final v = buildEveningVerdict(todayBlocks: today, weekBlocks: const []);
    expect(v, contains('Demain je le pose tôt, tant que la journée'));
    expect(v, isNot(contains('9 h')));
  });

  test('demain avec un trou : premier créneau libre réel', () {
    final tomorrow = [_b('07:00', 60), _b('08:00', 120)]; // libre à partir de 10 h
    final v = buildEveningVerdict(todayBlocks: today, weekBlocks: const [], tomorrowBlocks: tomorrow);
    expect(v, contains('Demain je le pose à 10 h'));
  });

  test('demain plein : on le dit au lieu de promettre 9 h', () {
    final tomorrow = [_b('07:00', 14 * 60)];
    final v = buildEveningVerdict(todayBlocks: today, weekBlocks: const [], tomorrowBlocks: tomorrow);
    expect(v, contains('Demain est déjà plein'));
    expect(v, isNot(contains('9 h')));
  });

  test('demain vide : 7 h', () {
    final v = buildEveningVerdict(todayBlocks: today, weekBlocks: const [], tomorrowBlocks: const []);
    expect(v, contains('Demain je le pose à 7 h'));
  });
}
