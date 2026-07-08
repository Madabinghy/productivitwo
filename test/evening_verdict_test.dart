import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/evening_verdict.dart';

ScheduleBlock _block({
  required String title,
  String startTime = '09:00',
  String status = 'pending',
  String category = 'project',
  String? taskId,
  String? activityId,
  String? skipReason,
  String kind = 'normal',
}) =>
    ScheduleBlock(
      startTime: startTime,
      durationMin: 45,
      title: title,
      category: category,
      status: status,
      taskId: taskId,
      activityId: activityId,
      skipReason: skipReason,
      kind: kind,
    );

void main() {
  group('buildEveningVerdict', () {
    test('tout tenu → verdict positif avec le vrai compte', () {
      final v = buildEveningVerdict(todayBlocks: [
        _block(title: 'Séance', status: 'done'),
        _block(title: 'Formation IA', status: 'done'),
      ], weekBlocks: []);
      expect(v, contains('2/2'));
      expect(v, contains('tenus'));
    });

    test('1 rompu avec récurrence : compte + cause dominante', () {
      final today = [
        _block(
            title: 'Relancer 3 prospects',
            taskId: 't1',
            startTime: '14:00',
            skipReason: 'imprevu'),
        _block(title: 'Séance', status: 'done'),
        _block(title: 'Formation IA', status: 'done'),
      ];
      final week = [
        _block(
            title: 'Relancer 3 prospects',
            taskId: 't1',
            skipReason: 'imprevu'),
      ];
      final v = buildEveningVerdict(todayBlocks: today, weekBlocks: week);
      expect(v, contains('sauté 2 fois cette semaine'));
      expect(v, contains('imprévu client'));
      expect(v, contains('Demain je le pose'));
      expect(v, contains('Séance et Formation IA'));
      expect(v, contains('la base qui compte'));
    });

    test('1ʳᵉ fois : pas de « n fois cette semaine »', () {
      final v = buildEveningVerdict(todayBlocks: [
        _block(title: 'Lecture', skipReason: 'evite'),
      ], weekBlocks: []);
      expect(v, contains('a sauté aujourd\'hui'));
      expect(v, isNot(contains('cette semaine')));
    });

    test('3+ rompus : cause globale, dayReason irrealiste allège demain', () {
      final today = [
        _block(title: 'A'),
        _block(title: 'B'),
        _block(title: 'C'),
        _block(title: 'D', status: 'done'),
      ];
      final v = buildEveningVerdict(
          todayBlocks: today, weekBlocks: [], dayReason: 'irrealiste');
      expect(v, contains('La journée a déraillé'));
      expect(v, contains('3 engagements sur 4'));
      expect(v, contains('programme irréaliste'));
      expect(v, contains('plus court, volontairement'));
    });

    test('les preps et pauses ne comptent pas comme engagements', () {
      final v = buildEveningVerdict(todayBlocks: [
        _block(title: 'Préparer le sac', kind: 'prep'),
        _block(title: 'Pause', category: 'break'),
        _block(title: 'Séance', status: 'done'),
      ], weekBlocks: []);
      expect(v, contains('1/1'));
    });

    test('bloc du matin rompu → reproposé à son heure ; aprem → 9 h', () {
      final morning = buildEveningVerdict(todayBlocks: [
        _block(title: 'Séance', startTime: '07:15'),
      ], weekBlocks: []);
      expect(morning, contains('7 h 15'));
      final afternoon = buildEveningVerdict(todayBlocks: [
        _block(title: 'Relances', startTime: '15:00'),
      ], weekBlocks: []);
      expect(afternoon, contains('9 h'));
    });
  });
}
