import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/energy_state.dart';

AppState _st({
  List<Domain>? domains,
  List<Activity>? activities,
  List<Session>? sessions,
  List<HabitHit>? hits,
}) =>
    AppState(
      domains: domains ?? [],
      activities: activities ?? [],
      sessions: sessions ?? [],
      habitProgress: [],
    )..habitHits = hits ?? [];

Activity _routine(String name, {int? timerMin, int order = 0}) => Activity(
      domainId: 'd1',
      name: name,
      type: 'habit',
      habitFreq: HabitFreq.daily,
      timerMin: timerMin,
      order: order,
    );

ScheduleBlock _block({
  required String startTime,
  int durationMin = 30,
  String title = 'Bloc',
  String category = 'personal',
  String status = 'pending',
  String? activityId,
  String? projectId,
  String kind = 'normal',
}) =>
    ScheduleBlock(
      startTime: startTime,
      durationMin: durationMin,
      title: title,
      category: category,
      status: status,
      activityId: activityId,
      projectId: projectId,
      taskId: projectId != null ? 't1' : null,
      kind: kind,
    );

void main() {
  final now = DateTime(2026, 7, 9, 15, 12);

  group('energyStateActive — TTL 3 h ou jusqu\'au check-in', () {
    test('actif dans la fenêtre', () {
      final s = EnergyState(
          level: 'low', at: now.subtract(const Duration(hours: 1)));
      expect(energyStateActive(s, now), isTrue);
    });

    test('expiré après 3 h', () {
      final s = EnergyState(
          level: 'low', at: now.subtract(const Duration(hours: 3)));
      expect(energyStateActive(s, now), isFalse);
    });

    test('un check-in postérieur referme la parenthèse', () {
      final s = EnergyState(
          level: 'full', at: now.subtract(const Duration(hours: 1)));
      expect(
          energyStateActive(s, now,
              reviewedAt: now.subtract(const Duration(minutes: 10))),
          isFalse);
      // Check-in ANTÉRIEUR à la déclaration : l'état tient.
      expect(
          energyStateActive(s, now,
              reviewedAt: now.subtract(const Duration(hours: 2))),
          isTrue);
    });

    test('null = inactif', () {
      expect(energyStateActive(null, now), isFalse);
    });
  });

  group('sérialisation EnergyState', () {
    test('aller-retour JSON', () {
      final s = EnergyState(level: 'low', at: now, note: 'grosse nuit');
      final back = EnergyState.from(s.toJson());
      expect(back!.level, 'low');
      expect(back.at, now);
      expect(back.note, 'grosse nuit');
    });

    test('niveau inconnu ou non-map → null (rétrocompat)', () {
      expect(EnergyState.from({'level': 'turbo', 'at': '2026-07-09'}), isNull);
      expect(EnergyState.from(null), isNull);
      expect(EnergyState.from('low'), isNull);
    });

    test('le doc du jour transporte energyState', () {
      final sched = DailySchedule(
          date: '2026-07-09',
          energyState: EnergyState(level: 'full', at: now));
      final back = DailySchedule.from(sched.toJson());
      expect(back.energyState!.level, 'full');
      // Ancien doc sans le champ : inchangé.
      final legacy = DailySchedule.from({'date': '2026-07-09'});
      expect(legacy.energyState, isNull);
    });
  });

  group('idleOpenCount — ouvertures sans action', () {
    test('compte les ouvertures des 90 dernières minutes', () {
      final opens = [
        now.subtract(const Duration(minutes: 120)), // trop vieille
        now.subtract(const Duration(minutes: 70)),
        now.subtract(const Duration(minutes: 40)),
        now.subtract(const Duration(minutes: 5)),
      ];
      expect(idleOpenCount(now, opens, null), 3);
    });

    test('une action réelle remet le compteur à zéro', () {
      final opens = [
        now.subtract(const Duration(minutes: 70)),
        now.subtract(const Duration(minutes: 40)),
        now.subtract(const Duration(minutes: 5)),
      ];
      final action = now.subtract(const Duration(minutes: 20));
      expect(idleOpenCount(now, opens, action), 1);
    });
  });

  group('lastActionAt', () {
    test('max des sessions, blocs cochés et routines du jour', () {
      final st = _st(
        sessions: [
          Session(
              activityId: 'a1',
              startAt: now.subtract(const Duration(hours: 2)),
              endAt: now.subtract(const Duration(minutes: 50))),
        ],
        hits: [HabitHit(habitId: 'h1', ts: now.subtract(const Duration(minutes: 30)))],
      );
      final blocks = [
        ScheduleBlock(
            startTime: '09:00',
            durationMin: 30,
            title: 'x',
            status: 'done',
            doneAt: now.subtract(const Duration(minutes: 10))),
      ];
      expect(lastActionAt(now, st, blocks),
          now.subtract(const Duration(minutes: 10)));
    });

    test('hier ne compte pas', () {
      final st = _st(sessions: [
        Session(
            activityId: 'a1',
            startAt: now.subtract(const Duration(days: 1)),
            endAt: now.subtract(const Duration(days: 1))),
      ]);
      expect(lastActionAt(now, st, const []), isNull);
    });
  });

  group('energyAskTrigger — les 3 déclencheurs', () {
    test('≥ 3 ouvertures sans action → idle', () {
      expect(energyAskTrigger(now, state: null, idleOpens: 3),
          EnergyAskTrigger.idle);
      expect(energyAskTrigger(now, state: null, idleOpens: 2), isNull);
    });

    test('dérive → la question remplace la carte dérive', () {
      final drifting = _block(startTime: '14:00', activityId: 'a1');
      expect(energyAskTrigger(now, state: null, drifting: drifting),
          EnergyAskTrigger.drift);
    });

    test('tap volontaire → manual, même avec un état actif', () {
      final active = EnergyState(
          level: 'low', at: now.subtract(const Duration(minutes: 30)));
      expect(energyAskTrigger(now, state: active, requested: true),
          EnergyAskTrigger.manual);
    });

    test('état actif < 3 h → jamais redemandé', () {
      final active = EnergyState(
          level: 'ok', at: now.subtract(const Duration(minutes: 30)));
      expect(
          energyAskTrigger(now,
              state: active,
              idleOpens: 5,
              drifting: _block(startTime: '13:00', activityId: 'a1')),
          isNull);
    });

    test('état expiré → la question peut revenir', () {
      final expired = EnergyState(
          level: 'low', at: now.subtract(const Duration(hours: 4)));
      expect(energyAskTrigger(now, state: expired, idleOpens: 3),
          EnergyAskTrigger.idle);
    });

    test('hors fenêtre de jour (22 h) → silence, sauf tap volontaire', () {
      final night = DateTime(2026, 7, 9, 22, 0);
      expect(energyAskTrigger(night, state: null, idleOpens: 5), isNull);
      expect(energyAskTrigger(night, state: null, requested: true),
          EnergyAskTrigger.manual);
    });
  });

  group('lowModeQueue — une chose, petite, routines d\'abord', () {
    test('routines (la plus courte d\'abord) avant les blocs', () {
      final st = _st(activities: [
        _routine('Ranger le bureau', timerMin: 15, order: 1),
        _routine('Boire de l\'eau', order: 0), // sans minuteur = la plus facile
      ]);
      final blocks = [
        _block(
            startTime: '15:30',
            durationMin: 20,
            title: 'Relances',
            activityId: 'x'),
      ];
      final q = lowModeQueue(now, st, blocks);
      expect(q[0].title, 'Boire de l\'eau');
      expect(q[1].title, 'Ranger le bureau');
      expect(q[2].title, 'Relances');
      expect(q[2].reduced, isFalse);
    });

    test('routine déjà tenue aujourd\'hui écartée', () {
      final r = _routine('Ranger', timerMin: 10);
      final st = _st(
          activities: [r],
          hits: [HabitHit(habitId: r.id, ts: now.subtract(const Duration(hours: 1)))]);
      expect(lowModeQueue(now, st, const []), isEmpty);
    });

    test('bloc long dans l\'heure → version 25 min ; au-delà de 60 min → hors horizon', () {
      final st = _st();
      final blocks = [
        _block(
            startTime: '15:30',
            durationMin: 90,
            title: 'Formation IA — suite'),
        _block(startTime: '17:00', durationMin: 20, title: 'Trop loin'),
      ];
      final q = lowModeQueue(now, st, blocks);
      expect(q.length, 1);
      expect(q.first.reduced, isTrue);
      expect(q.first.subtitle, contains('25 min'));
    });

    test('en attente : tout le pending sauf la proposition courante', () {
      final blocks = [
        _block(startTime: '14:00', title: 'A'),
        _block(startTime: '16:00', title: 'B'),
        _block(startTime: '18:00', title: 'C', status: 'done'),
      ];
      final q = lowModeQueue(now, _st(), blocks);
      expect(lowModeWaitingCount(blocks, q.first), 1);
      expect(lowModeNext(now, blocks, q.first)!.title, 'B');
    });
  });

  group('fullModeTargets — l\'intention n° 1 d\'abord', () {
    test('rang de domaine puis projet puis heure', () {
      final d1 = Domain(
          name: 'Business',
          definitionStatus: 'active',
          intention: 'Décrocher 2 clients d\'ici fin juillet');
      final d2 = Domain(name: 'Santé', definitionStatus: 'active');
      final actB = Activity(domainId: d1.id, name: 'Deck');
      final actS = Activity(domainId: d2.id, name: 'Sport');
      final st = _st(domains: [d1, d2], activities: [actB, actS]);
      final blocks = [
        _block(startTime: '14:00', title: 'Séance', activityId: actS.id),
        _block(startTime: '16:00', title: 'Pitch deck', activityId: actB.id),
        _block(startTime: '15:00', title: 'Sans lien'),
      ];
      final targets = fullModeTargets(now, st, blocks, const []);
      expect(targets.first.block.title, 'Pitch deck');
      expect(targets.first.rank, 1);
      expect(targets.first.intention,
          'Décrocher 2 clients d\'ici fin juillet');
      expect(targets[1].block.title, 'Séance');
      // Le bloc sans lien n'est pas lançable → absent.
      expect(targets.length, 2);
    });

    test('projet relié au domaine via Project.domainId', () {
      final d1 = Domain(
          name: 'Business',
          definitionStatus: 'active',
          intention: 'vivre de mon activité');
      final p = Project(
          title: 'Formation IA',
          domainId: d1.id,
          startDate: DateTime(2026, 7, 1),
          createdBy: 'user');
      final st = _st(domains: [d1]);
      final blocks = [
        ScheduleBlock(
            startTime: '15:30',
            durationMin: 60,
            title: 'Formation',
            category: 'project',
            projectId: p.id,
            taskId: 't1'),
      ];
      final targets = fullModeTargets(now, st, blocks, [p]);
      expect(targets.single.rank, 1);
      expect(targets.single.domainName, 'Business');
    });
  });

  group('deepWorkShifts — glissements affichés avant de valider', () {
    test('les blocs pris dans le créneau glissent après, en chaîne', () {
      final target = _block(startTime: '15:30', title: 'Deck', activityId: 'a');
      final blocks = [
        target,
        _block(startTime: '15:45', durationMin: 30, title: 'Relances'),
        _block(startTime: '16:30', durationMin: 30, title: 'Mails'),
        _block(startTime: '18:30', durationMin: 20, title: 'Déjà après'),
      ];
      // 15:12 + 2 h → créneau jusqu'à 17:12.
      final shifts = deepWorkShifts(now, blocks, target, 120);
      expect(shifts.length, 2);
      expect(shifts[0].block.title, 'Relances');
      expect(shifts[0].newStart, '17:12');
      expect(shifts[1].block.title, 'Mails');
      expect(shifts[1].newStart, '17:42');
    });

    test('la soirée off ne bouge pas : pas de glissement vers ≥ 19 h', () {
      final target = _block(startTime: '17:00', title: 'Deck', activityId: 'a');
      final lateNow = DateTime(2026, 7, 9, 17, 30);
      final blocks = [
        target,
        _block(startTime: '18:00', durationMin: 45, title: 'Relances'),
      ];
      // 17:30 + 2 h → glissement à 19:30 : interdit, le bloc reste en place.
      expect(deepWorkShifts(lateNow, blocks, target, 120), isEmpty);
    });
  });

  group('templates — chiffres réels, jamais inventés', () {
    test('question idle : compte et heure du premier passage', () {
      final msg = energyAskMessage(EnergyAskTrigger.idle,
          idleOpens: 3, firstOpen: DateTime(2026, 7, 9, 14, 0));
      expect(msg, contains('3 passages'));
      expect(msg, contains('14 h'));
      expect(msg, contains('4ᵉ fois'));
    });

    test('question dérive : cite le bloc réel', () {
      final msg = energyAskMessage(EnergyAskTrigger.drift,
          drifting: _block(startTime: '14:00', title: 'Relancer 3 prospects'));
      expect(msg, contains('Relancer 3 prospects'));
      expect(msg, contains('14 h'));
    });

    test('message à plat : nomme le gros bloc, sinon omet la phrase', () {
      final withBig = lowModeMessage(
          [_block(startTime: '16:00', durationMin: 90, title: 'Formation IA')]);
      expect(withBig, contains('Formation IA'));
      expect(withBig, contains('séquencement, pas de la paresse'));
      final without = lowModeMessage(const []);
      expect(without, isNot(contains('attendra')));
      expect(without, contains('séquencement'));
    });
  });
}
