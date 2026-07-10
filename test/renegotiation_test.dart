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

  group('freeDaySlots (23a)', () {
    test('tous les trous du jour, pas seulement le dernier', () {
      final now = DateTime(2026, 7, 9, 15, 0);
      final blocks = [
        _b(startTime: '16:00', durationMin: 90), // 16:00-17:30
        _b(startTime: '19:00', durationMin: 60), // 19:00-20:00
      ];
      final slots = freeDaySlots(now, blocks);
      expect(slots.map((s) => s.start).toList(),
          ['15:00', '17:30', '20:00']);
      expect(slots[0].minutes, 60);
      expect(slots[1].minutes, 90);
      expect(slots[2].minutes, 120);
    });

    test('fin de journée réduite (soirée protégée → dayEndHour 18)', () {
      final now = DateTime(2026, 7, 9, 15, 0);
      final slots = freeDaySlots(now, [], dayEndHour: 18);
      expect(slots.single.start, '15:00');
      expect(slots.single.minutes, 180);
    });

    test('le bloc déplacé est exclu des occupations', () {
      final now = DateTime(2026, 7, 9, 15, 0);
      final self = _b(startTime: '16:00', durationMin: 360);
      expect(freeDaySlots(now, [self], excludeBlockId: self.id), hasLength(1));
    });
  });

  group('slotIsProtected (territoire défendu)', () {
    test('codes jour_partie et jour_day', () {
      // 2026-07-10 est un vendredi.
      const protected = {'fri_evening', 'sun_day'};
      expect(slotIsProtected('19:30', DateTime.friday, protected), isTrue);
      expect(slotIsProtected('15:00', DateTime.friday, protected), isFalse);
      expect(slotIsProtected('10:00', DateTime.sunday, protected), isTrue);
      expect(slotIsProtected('19:30', DateTime.monday, protected), isFalse);
    });

    test('slotPart : même découpage que le post-filtre de la proposition', () {
      expect(slotPart('08:00'), 'morning');
      expect(slotPart('14:00'), 'afternoon');
      expect(slotPart('18:00'), 'evening');
    });
  });

  group('diagnoseStructural', () {
    // Historique 14 j : « Séance jambes » (t1) sautée 2 fois à 18 h + le bloc
    // du jour = 3 échecs même tranche. Le matin tient (6/6, autres blocs).
    final today = _b(startTime: '18:00', title: 'Séance jambes', taskId: 't1');
    final history = [
      _b(startTime: '18:00', title: 'Séance jambes', taskId: 't1',
          status: 'skipped', skipReason: 'energie'),
      _b(startTime: '18:30', title: 'Séance jambes', taskId: 't1',
          status: 'skipped', skipReason: 'imprevu'),
      for (var i = 0; i < 6; i++)
        _b(startTime: '07:15', title: 'Deep work', taskId: 'dw',
            status: 'done'),
    ];

    test('3 échecs même tranche → déclenché, stats réelles', () {
      final d = diagnoseStructural(today, history);
      expect(d, isNotNull);
      expect(d!.fails, 3);
      expect(d.held, 0);
      expect(d.total, 3);
      expect(d.bucket, 'soir');
      expect(d.slotHm, '18:00'); // heure la plus fréquente des échecs
    });

    test('alternatives = tranches qui tiennent, heure typique des tenues', () {
      final d = diagnoseStructural(today, history)!;
      expect(d.alternatives, hasLength(1));
      expect(d.alternatives.first.bucket, 'matin');
      expect(d.alternatives.first.held, 6);
      expect(d.alternatives.first.total, 6);
      expect(d.alternatives.first.typicalTime, '07:15');
    });

    test('2 échecs seulement → pas de déclenchement', () {
      final d = diagnoseStructural(today, [history.first, ...history.skip(2)]);
      expect(d, isNull);
    });

    test('les échecs d\'un AUTRE engagement ne comptent pas', () {
      final d = diagnoseStructural(today, [
        _b(startTime: '18:00', title: 'Autre', taskId: 't2', status: 'skipped'),
        _b(startTime: '18:00', title: 'Autre', taskId: 't2', status: 'skipped'),
      ]);
      expect(d, isNull);
    });

    test('les échecs du même engagement sur une AUTRE tranche ne comptent pas',
        () {
      final d = diagnoseStructural(today, [
        _b(startTime: '09:00', title: 'Séance jambes', taskId: 't1',
            status: 'skipped'),
        _b(startTime: '09:00', title: 'Séance jambes', taskId: 't1',
            status: 'skipped'),
      ]);
      expect(d, isNull);
    });

    test('blocs deleted et preps ignorés partout', () {
      final d = diagnoseStructural(today, [
        _b(startTime: '18:00', title: 'Séance jambes', taskId: 't1',
            status: 'deleted'),
        _b(startTime: '18:00', title: 'Séance jambes', taskId: 't1',
            status: 'skipped'),
        _b(startTime: '07:00', durationMin: 5, status: 'done', kind: 'prep'),
      ]);
      expect(d, isNull); // 1 échec réel + aujourd'hui = 2 < 3
    });

    test('une tranche qui ne tient pas (<60%) n\'est pas une alternative', () {
      final d = diagnoseStructural(today, [
        ...history.take(2),
        _b(startTime: '12:30', title: 'Relances', status: 'done'),
        _b(startTime: '12:30', title: 'Relances', status: 'done'),
        _b(startTime: '12:30', title: 'Relances', status: 'skipped'),
        _b(startTime: '12:30', title: 'Relances', status: 'skipped'),
      ])!;
      expect(d.alternatives, isEmpty); // midi 2/4 = 50 % < 60 %
    });

    test('weeklyFreq depuis la fenêtre 7 jours quand fournie', () {
      final week = [
        _b(startTime: '18:00', title: 'Séance jambes', taskId: 't1',
            status: 'skipped'),
        _b(startTime: '18:00', title: 'Séance jambes', taskId: 't1',
            status: 'skipped'),
      ];
      final d = diagnoseStructural(today, history, weekBlocks: week)!;
      expect(d.weeklyFreq, 3); // 2 occurrences + le bloc du jour
    });
  });

  group('slotBucket', () {
    test('tranches de journée', () {
      expect(slotBucket('07:15'), 'matin');
      expect(slotBucket('11:59'), 'matin');
      expect(slotBucket('12:45'), 'midi');
      expect(slotBucket('15:00'), 'apres_midi');
      expect(slotBucket('18:00'), 'soir');
      expect(slotBucket('01:00'), 'soir');
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
