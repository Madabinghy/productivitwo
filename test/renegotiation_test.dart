import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/renegotiation.dart';

ScheduleBlock _b({
  required String startTime,
  int durationMin = 60,
  String status = 'pending',
  String title = 'Bloc',
  String? taskId,
  String? skipReason,
  String kind = 'normal',
}) =>
    ScheduleBlock(
      startTime: startTime,
      durationMin: durationMin,
      title: title,
      status: status,
      taskId: taskId,
      skipReason: skipReason,
      kind: kind,
    );

void main() {
  group('findLastFreeSlot', () {
    test('journée vide → dernier créneau avant 22 h', () {
      final now = DateTime(2026, 7, 9, 15, 0);
      expect(findLastFreeSlot(now, [], 60), '21:00');
      expect(findLastFreeSlot(now, [], 90), '20:30');
    });

    test('évite les blocs pending restants — prend le trou le plus tardif', () {
      final now = DateTime(2026, 7, 9, 15, 0);
      final blocks = [
        _b(startTime: '18:00', durationMin: 120), // 18:00-20:00 occupé
      ];
      // Trou 20:00-22:00 → au plus tard : 21:00 pour 60 min.
      expect(findLastFreeSlot(now, blocks, 60), '21:00');
    });

    test('fin de journée pleine → créneau AVANT le bloc du soir', () {
      final now = DateTime(2026, 7, 9, 15, 0);
      final blocks = [
        _b(startTime: '19:00', durationMin: 180), // 19:00-22:00 occupé
      ];
      // Trou 15:00-19:00 → au plus tard 18:00 pour 60 min.
      expect(findLastFreeSlot(now, blocks, 60), '18:00');
    });

    test('plus rien ne rentre → null', () {
      final now = DateTime(2026, 7, 9, 21, 30);
      expect(findLastFreeSlot(now, [], 60), isNull);
    });

    test('les blocs done/skipped et preps ne bloquent pas', () {
      final now = DateTime(2026, 7, 9, 15, 0);
      final blocks = [
        _b(startTime: '20:00', durationMin: 120, status: 'done'),
        _b(startTime: '21:45', durationMin: 5, kind: 'prep'),
      ];
      expect(findLastFreeSlot(now, blocks, 60), '21:00');
    });

    test('le bloc renégocié lui-même est exclu des occupations', () {
      final now = DateTime(2026, 7, 9, 15, 0);
      final self = _b(startTime: '20:00', durationMin: 120);
      expect(
          findLastFreeSlot(now, [self], 60, excludeBlockId: self.id), '21:00');
    });
  });

  group('weeklyReportCount', () {
    test('compte les reports du même engagement uniquement', () {
      final target = _b(startTime: '14:00', title: 'Relances', taskId: 't1');
      final week = [
        _b(startTime: '14:00', title: 'Relances', taskId: 't1',
            status: 'skipped', skipReason: 'reporte'),
        _b(startTime: '14:00', title: 'Relances', taskId: 't1',
            status: 'skipped', skipReason: 'imprevu'), // pas un report
        _b(startTime: '09:00', title: 'Autre', taskId: 't2',
            status: 'skipped', skipReason: 'reporte'), // autre engagement
      ];
      expect(weeklyReportCount(target, week), 1);
    });
  });

  group('usefulMinutesLeft', () {
    test('15 h → 7 h utiles jusqu\'à 22 h', () {
      expect(usefulMinutesLeft(DateTime(2026, 7, 9, 15, 0)), 420);
    });
    test('après 22 h → 0', () {
      expect(usefulMinutesLeft(DateTime(2026, 7, 9, 22, 30)), 0);
    });
  });
}
