import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/recovery.dart';

AppState _st({List<Session>? sessions, List<HabitHit>? hits}) => AppState(
      domains: [],
      activities: [],
      sessions: sessions ?? [],
      habitProgress: [],
    )..habitHits = hits ?? [];

ScheduleBlock _block({
  String startTime = '09:00',
  String title = 'Bloc',
  String status = 'pending',
  String category = 'personal',
}) =>
    ScheduleBlock(
        startTime: startTime,
        durationMin: 30,
        title: title,
        status: status,
        category: category);

DailySchedule _sched(String date,
        {List<ScheduleBlock>? blocks,
        EnergyState? energy,
        DateTime? reviewedAt}) =>
    DailySchedule(
        date: date,
        blocks: blocks ?? [],
        energyState: energy,
        reviewedAt: reviewedAt);

void main() {
  final now = DateTime(2026, 7, 9, 9, 4); // jeudi matin (jour 3)
  final d1 = DateTime(2026, 7, 8); // mercredi
  final d2 = DateTime(2026, 7, 7); // mardi

  group('isFlatDay', () {
    test('low DÉCLARÉ → à plat, même avec du temps loggué', () {
      final s = _sched('2026-07-08',
          energy: EnergyState(level: 'low', at: d1.add(const Duration(hours: 15))));
      expect(isFlatDay(d1, s, const []), isTrue);
    });

    test('dérivé : < 30 min logguées ET 0 bloc non-routine done', () {
      final s = _sched('2026-07-08', blocks: [_block()]);
      expect(isFlatDay(d1, s, const []), isTrue);
      // 45 min logguées → pas à plat.
      final sessions = [
        Session(
            activityId: 'a',
            startAt: d1.add(const Duration(hours: 10)),
            endAt: d1.add(const Duration(hours: 10, minutes: 45))),
      ];
      expect(isFlatDay(d1, s, sessions), isFalse);
      // Un bloc non-routine done → pas à plat.
      final withDone = _sched('2026-07-08',
          blocks: [_block(status: 'done', category: 'project')]);
      expect(isFlatDay(d1, withDone, const []), isFalse);
    });

    test('routine done ne sauve pas la journée (non-routine seulement)', () {
      final s = _sched('2026-07-08',
          blocks: [_block(status: 'done', category: 'routine')]);
      expect(isFlatDay(d1, s, const []), isTrue);
    });

    test('jour sans système (pas de programme) ≠ jour à plat', () {
      expect(isFlatDay(d1, null, const []), isFalse);
      expect(isFlatDay(d1, _sched('2026-07-08'), const []), isFalse);
    });
  });

  group('recoveryTriggered — 2 jours consécutifs, matin du jour 3, 72 h', () {
    final flatY = _sched('2026-07-08',
        energy: EnergyState(level: 'low', at: d1.add(const Duration(hours: 15))));
    final flatB = _sched('2026-07-07',
        energy: EnergyState(level: 'low', at: d2.add(const Duration(hours: 14))));

    test('déclenche au matin du jour 3', () {
      expect(
          recoveryTriggered(now,
              yesterday: flatY, dayBefore: flatB, sessions: const []),
          isTrue);
    });

    test('un seul jour à plat → rien', () {
      expect(
          recoveryTriggered(now,
              yesterday: flatY,
              dayBefore: _sched('2026-07-07'),
              sessions: const []),
          isFalse);
    });

    test('jamais avant 8 h ni avant 72 h de la dernière séquence', () {
      final night = DateTime(2026, 7, 9, 6, 30);
      expect(
          recoveryTriggered(night,
              yesterday: flatY, dayBefore: flatB, sessions: const []),
          isFalse);
      expect(
          recoveryTriggered(now,
              yesterday: flatY,
              dayBefore: flatB,
              sessions: const [],
              lastRecoveryAt: now.subtract(const Duration(hours: 48))),
          isFalse);
      expect(
          recoveryTriggered(now,
              yesterday: flatY,
              dayBefore: flatB,
              sessions: const [],
              lastRecoveryAt: now.subtract(const Duration(hours: 80))),
          isTrue);
    });
  });

  group('heldFacts — uniquement des faits done, rangée omise si vide', () {
    test('check-ins + routines des 2 jours', () {
      final y = _sched('2026-07-08',
          reviewedAt: d1.add(const Duration(hours: 21)));
      final b = _sched('2026-07-07',
          reviewedAt: d2.add(const Duration(hours: 21)));
      final st = _st(hits: [
        HabitHit(habitId: 'h', ts: d1.add(const Duration(hours: 8))),
      ]);
      final facts = heldFacts(now, y, b, st);
      expect(facts, contains('les deux check-ins'));
      expect(facts, contains('des routines un jour sur deux'));
      expect(checkinsHeld(y, b), 2);
    });

    test('rien de tenu → liste vide', () {
      expect(heldFacts(now, _sched('2026-07-08'), null, _st()), isEmpty);
    });
  });

  group('copy — pools seedés, placeholders jamais remplis à vide', () {
    test('étape 1 sans faits tenus → seule V3 (sans placeholder) est tirable',
        () {
      final c = recoveryCopyStep1(now, const []);
      expect(c.variant, 2);
      expect(c.text, contains('0 sauté'));
    });

    test('étape 1 avec faits → les cite tels quels', () {
      final c = recoveryCopyStep1(now, const ['les deux check-ins']);
      if (c.variant < 2) {
        expect(c.text, contains('les deux check-ins'));
      }
    });

    test('la dernière variante servie n\'est jamais resservie', () {
      for (var v = 0; v < 3; v++) {
        final c = recoveryCopyStep2(now, lastVariant: v);
        expect(c.variant, isNot(v));
      }
    });

    test('sélection déterministe : même jour → même variante', () {
      expect(recoveryCopyStep2(now).variant, recoveryCopyStep2(now).variant);
    });

    test('étape 4 sans agrégats ni intention → le filet sans placeholder', () {
      final c = recoveryCopyStep4(now);
      expect(c.variant, 3);
      expect(c.text, contains('Une marche aujourd\'hui suffit'));
    });

    test('étape 4 : V2 exige l\'intention, V1/V3 exigent les agrégats', () {
      // Tirage parmi V2 + filet uniquement.
      final c = recoveryCopyStep4(now, hasIntention: true);
      expect([1, 3], contains(c.variant));
    });
  });

  group('recoveryAggregates — heures réelles, null si rien', () {
    test('somme 30 jours sur les activités du domaine', () {
      final d = Domain(name: 'Business');
      final act = Activity(domainId: d.id, name: 'Deck');
      final st = _st(sessions: [
        Session(
            activityId: act.id,
            startAt: now.subtract(const Duration(days: 3)),
            endAt: now
                .subtract(const Duration(days: 3))
                .add(const Duration(hours: 23))),
      ])
        ..activities.add(act);
      expect(recoveryAggregates(now, st, d), '23 h sur Business en 30 jours');
    });

    test('moins d\'une heure → null (la ligne saute)', () {
      expect(recoveryAggregates(now, _st(), Domain(name: 'X')), isNull);
    });
  });

  group('sérialisation RecoverySequence', () {
    test('aller-retour JSON avec contexte', () {
      final seq = RecoverySequence(
          step: 2,
          startedAt: now,
          declines: 2,
          declinedAt: now,
          recoveryContext: RecoveryContext(kind: 'physical', at: now));
      final back = RecoverySequence.from(seq.toJson())!;
      expect(back.step, 2);
      expect(back.declines, 2);
      expect(back.recoveryContext!.kind, 'physical');
      expect(back.active, isTrue);
      back.exitedAt = now;
      expect(back.active, isFalse);
    });

    test('doc du jour : transport + rétrocompat', () {
      final sched = DailySchedule(
          date: '2026-07-09',
          recoverySequence: RecoverySequence(step: 3, startedAt: now));
      expect(DailySchedule.from(sched.toJson()).recoverySequence!.step, 3);
      expect(DailySchedule.from({'date': '2026-07-09'}).recoverySequence,
          isNull);
      // Étape hors bornes / contexte inconnu → null, jamais de crash.
      expect(RecoverySequence.from({'step': 7}), isNull);
      expect(RecoveryContext.from({'kind': 'autre'}), isNull);
    });

    test('note 24a récente retrouvée avec son jour', () {
      final y = _sched('2026-07-08',
          energy: EnergyState(
              level: 'low',
              at: DateTime(2026, 7, 8, 15),
              note: 'la peur de relancer'));
      final r = recentEnergyNote(now, [null, y]);
      expect(r!.note, 'la peur de relancer');
      expect(r.day, 'mercredi');
    });
  });
}
