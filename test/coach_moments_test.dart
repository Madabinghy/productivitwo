import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/coach_moments.dart';

// Coach ÉVÉNEMENTIEL (refonte 2026-09) : l'état normal est l'ABSENCE de carte.
// Seuls deux événements en produisent une : fin de chrono (« Et ensuite ? »)
// et dérive d'un bloc posé. Tout le reste du moteur a été supprimé.

AppState _st(List<Session> sessions) => AppState(
      domains: [
        Domain(
            name: 'Santé',
            definitionStatus: 'active',
            intention: 'tenir le rythme'),
      ],
      activities: [],
      sessions: sessions,
      habitProgress: [],
    );

DailySchedule _sched(String date, List<ScheduleBlock> blocks) =>
    DailySchedule(date: date, blocks: blocks);

ScheduleBlock _block({
  required String startTime,
  int durationMin = 30,
  String title = 'Bloc',
  String category = 'personal',
  String status = 'pending',
  String? activityId,
  String? projectId,
  String? taskId,
  DateTime? doneAt,
  String kind = 'normal',
  String? prepForDate,
  String? prepForBlockId,
}) =>
    ScheduleBlock(
      startTime: startTime,
      durationMin: durationMin,
      title: title,
      category: category,
      status: status,
      activityId: activityId,
      projectId: projectId,
      taskId: taskId,
      doneAt: doneAt,
      kind: kind,
      prepForDate: prepForDate,
      prepForBlockId: prepForBlockId,
    );

void main() {
  const today = '2026-07-07';

  group('computeCoachMoment — silence par défaut', () {
    test('aucun événement → aucune carte, à toute heure de la journée', () {
      // Un programme normal (bloc à venir), rien de fini, rien en dérive.
      final sched = _sched(today, [
        _block(startTime: '21:30', title: 'Hygiène', activityId: 'r1'),
      ]);
      for (final hm in [(7, 0), (10, 0), (12, 30), (16, 0), (20, 0)]) {
        final now = DateTime(2026, 7, 7, hm.$1, hm.$2);
        final m = computeCoachMoment(now, _st([]), sched, []);
        expect(m.hidden, isTrue, reason: 'à ${hm.$1}h${hm.$2}');
      }
    });

    test('journée vide (aucun programme) → silence aussi', () {
      final now = DateTime(2026, 7, 7, 8, 0);
      final m = computeCoachMoment(now, _st([]), null, []);
      expect(m.hidden, isTrue);
      expect(m.type, CoachMomentType.hidden);
    });

    test('nuit (avant 5 h) et couche-tard (0h30) → masquée', () {
      expect(
          computeCoachMoment(DateTime(2026, 7, 7, 3, 0), _st([]), null, [])
              .hidden,
          isTrue);
      expect(
          computeCoachMoment(DateTime(2026, 7, 8, 0, 30), _st([]), null, [])
              .hidden,
          isTrue);
    });

    test('soir (≥ 19 h) : même une dérive flagrante se tait', () {
      final now = DateTime(2026, 7, 7, 20, 0);
      final sched = _sched(today, [
        _block(startTime: '18:00', title: 'Relances', activityId: 'a'),
      ]);
      final m = computeCoachMoment(now, _st([]), sched, []);
      expect(m.hidden, isTrue);
    });

    test('pause active → AUCUNE carte, pas même la dérive', () {
      final now = DateTime(2026, 7, 11, 15, 0);
      final sched = DailySchedule(
        date: today,
        unavailableUntil: DateTime(2026, 7, 11, 18, 0),
        unavailableReason: 'pas_sur_place',
        blocks: [
          // Bloc en dérive flagrante (posé 14h, 0 min logguée) : silencieux.
          _block(startTime: '14:00', title: 'Relances', activityId: 'a'),
        ],
      );
      final m = computeCoachMoment(now, _st([]), sched, []);
      expect(m.hidden, isTrue);
    });

    test('fenêtre de pause expirée → les événements reprennent (dérive)', () {
      final now = DateTime(2026, 7, 11, 15, 0);
      final sched = DailySchedule(
        date: today,
        unavailableUntil: DateTime(2026, 7, 11, 14, 0),
        blocks: [
          _block(startTime: '13:00', title: 'Relances', activityId: 'a'),
        ],
      );
      final m = computeCoachMoment(now, _st([]), sched, []);
      expect(m.type, CoachMomentType.drift);
    });

    test('mode soirée (journée pliée tôt) → silence, même une dérive', () {
      final now = DateTime(2026, 7, 7, 16, 0);
      final sched = DailySchedule(date: today, dayMode: 'evening', blocks: [
        _block(startTime: '14:00', title: 'Relances', activityId: 'a'),
      ]);
      final m = computeCoachMoment(now, _st([]), sched, []);
      expect(m.hidden, isTrue);
    });

    test('rétrocompat : programme sans champ kind → calcul sans crash', () {
      final now = DateTime(2026, 7, 7, 10, 0);
      final legacy = ScheduleBlock.from({
        'id': 'b1',
        'startTime': '11:00',
        'durationMin': 30,
        'title': 'Legacy',
        'category': 'personal',
        'status': 'pending',
      });
      expect(legacy.kind, 'normal');
      expect(legacy.isPrep, isFalse);
      final m = computeCoachMoment(now, _st([]), _sched(today, [legacy]), []);
      expect(m.hidden, isTrue); // bloc à venir, rien à signaler
    });
  });

  group('événement dérive', () {
    test('bloc posé > 45 min, 0 min logguée → carte ambre Lancer/Renégocier/Ignorer',
        () {
      final now = DateTime(2026, 7, 7, 15, 0);
      final sched = _sched(today, [
        _block(
            startTime: '14:00',
            title: 'Formation IA',
            category: 'project',
            projectId: 'p',
            taskId: 't',
            activityId: 'a'),
      ]);
      final m = computeCoachMoment(now, _st([]), sched, []);
      expect(m.type, CoachMomentType.drift);
      expect(m.tone, CoachTone.alert);
      expect(m.message, contains('0 min logguée'));
      expect(m.actions.any((a) => a.kind == CoachActionKind.launchBlock),
          isTrue);
      expect(m.actions.any((a) => a.kind == CoachActionKind.renegotiate),
          isTrue);
      // « Ignorer » : la dérive peut se taire jusqu'à demain.
      expect(m.actions.any((a) => a.kind == CoachActionKind.dismiss), isTrue);
    });

    test('pas de dérive si du temps a été loggué sur le bloc', () {
      final now = DateTime(2026, 7, 7, 15, 0);
      final sched = _sched(today, [
        _block(
            startTime: '14:00',
            title: 'Formation IA',
            category: 'project',
            activityId: 'a'),
      ]);
      final sessions = [
        Session(
            activityId: 'a',
            startAt: DateTime(2026, 7, 7, 14, 10),
            endAt: DateTime(2026, 7, 7, 14, 40)),
      ];
      final m = computeCoachMoment(now, _st(sessions), sched, sessions);
      expect(m.type, isNot(CoachMomentType.drift));
    });

    test('le CTA s\'aligne sur la durée réelle du bloc (1 min)', () {
      final now = DateTime(2026, 7, 7, 15, 0);
      final sched = _sched(today, [
        _block(
            startTime: '05:30',
            durationMin: 1,
            title: 'Vitamines',
            activityId: 'r1'),
      ]);
      final m = computeCoachMoment(now, _st([]), sched, []);
      expect(m.type, CoachMomentType.drift);
      // Plus jamais « 25 min » pour un bloc d'une minute.
      expect(m.message, contains('1 minute suffit'));
      expect(m.actions.first.label, 'Lancer 1 min');
    });

    test('pas de relance avant 9 h (le petit-déjeuner n\'est pas une dérive)',
        () {
      final now = DateTime(2026, 7, 7, 8, 30);
      final sched = _sched(today, [
        _block(startTime: '07:00', title: 'Sport', activityId: 'a'),
      ]);
      final m = computeCoachMoment(now, _st([]), sched, []);
      expect(m.hidden, isTrue);
    });

    test(
        'routine en dérive : le temps sur l\'activité LIÉE compte, la coche '
        'du jour aussi', () {
      final now = DateTime(2026, 7, 7, 16, 0);
      final st = AppState(
        domains: [
          Domain(
              name: 'Spiritualité',
              definitionStatus: 'active',
              intention: 'tenir le rythme'),
        ],
        activities: [
          Activity(
              id: 'r1',
              name: 'Prier',
              domainId: 'd1',
              type: 'habit',
              habitFreq: HabitFreq.daily,
              linkedActivityId: 'a-priere'),
          Activity(id: 'a-priere', name: 'Prière', domainId: 'd1'),
        ],
        sessions: [],
        habitProgress: [],
      );
      final sched = _sched(today, [
        _block(
            startTime: '08:30',
            durationMin: 20,
            title: 'Prier',
            activityId: 'r1'),
      ]);
      // 9 min logguées sur l'activité-temps liée → PAS de dérive.
      final prayed = [
        Session(
            activityId: 'a-priere',
            startAt: DateTime(2026, 7, 7, 10, 55),
            endAt: DateTime(2026, 7, 7, 11, 4)),
      ];
      final m1 = computeCoachMoment(now, st, sched, prayed);
      expect(m1.type, isNot(CoachMomentType.drift));
      // Routine cochée aujourd'hui → pas de dérive non plus.
      st.habitHits
          .add(HabitHit(habitId: 'r1', ts: DateTime(2026, 7, 7, 9, 0)));
      final m2 = computeCoachMoment(now, st, sched, []);
      expect(m2.type, isNot(CoachMomentType.drift));
      // Rien du tout → la dérive reste légitime.
      st.habitHits.clear();
      final m3 = computeCoachMoment(now, st, sched, []);
      expect(m3.type, CoachMomentType.drift);
    });

    test('renégociation faite ou « Ignorer » → la dérive respire', () {
      final now = DateTime(2026, 7, 7, 16, 0);
      final sched = _sched(today, [
        _block(startTime: '08:30', durationMin: 20, title: 'Prier',
            activityId: 'a1'),
        _block(startTime: '09:00', durationMin: 30, title: 'Revue',
            activityId: 'a2'),
      ]);
      final normal = computeCoachMoment(now, _st([]), sched, []);
      expect(normal.type, CoachMomentType.drift);
      final snoozed = computeCoachMoment(now, _st([]), sched, [],
          driftSnoozed: true);
      expect(snoozed.hidden, isTrue);
    });
  });

  group('événement « Et ensuite ? » (fin de chrono)', () {
    // Domaine défini + 2 routines quotidiennes + 1 activité-temps Sport.
    AppState stFull(List<HabitHit> hits,
            {List<Session> sessions = const []}) =>
        AppState(
          domains: [
            Domain(
                id: 'd1',
                name: 'Santé',
                definitionStatus: 'active',
                intention: 'tenir le rythme'),
          ],
          activities: [
            Activity(
                id: 'r1',
                name: 'Méditation',
                domainId: 'd1',
                type: 'habit',
                habitFreq: HabitFreq.daily,
                timerMin: 10,
                order: 0),
            Activity(
                id: 'r2',
                name: 'Marche',
                domainId: 'd1',
                type: 'habit',
                habitFreq: HabitFreq.daily,
                timerMin: 30,
                order: 1),
            Activity(id: 'a1', name: 'Sport', domainId: 'd1', order: 2),
          ],
          sessions: sessions,
          habitProgress: [],
          habitHits: hits,
        );

    test('chrono terminé ≤ 10 min → carte chain', () {
      final now = DateTime(2026, 7, 7, 10, 0);
      final sessions = [
        Session(
            activityId: 'a1',
            startAt: DateTime(2026, 7, 7, 9, 30),
            endAt: DateTime(2026, 7, 7, 9, 55)),
      ];
      final m = computeCoachMoment(
          now, stFull([], sessions: sessions), _sched(today, []), sessions);
      expect(m.type, CoachMomentType.chain);
      expect(m.tagLabel, 'ORION · ET ENSUITE ?');
      expect(m.message, contains('Sport terminé — 25 min au compteur'));
      // La suite proposée : une routine qui tient dans le trou, en un tap.
      expect(
          m.actions.any((a) =>
              a.kind == CoachActionKind.launchBlock &&
              a.block?.activityId == 'r1'),
          isTrue);
      expect(m.tone, CoachTone.positive);
    });

    test('fenêtre expirée ou chrono en cours → silence', () {
      final now = DateTime(2026, 7, 7, 10, 0);
      // Terminé il y a 25 min : le moment est passé.
      final old = [
        Session(
            activityId: 'a1',
            startAt: DateTime(2026, 7, 7, 9, 0),
            endAt: DateTime(2026, 7, 7, 9, 35)),
      ];
      final m1 = computeCoachMoment(
          now, stFull([], sessions: old), _sched(today, []), old);
      expect(m1.hidden, isTrue);
      // Chrono en cours (endAt null) : rien à enchaîner, on n'interrompt pas.
      final running = [
        Session(
            activityId: 'a1',
            startAt: DateTime(2026, 7, 7, 9, 30),
            endAt: DateTime(2026, 7, 7, 9, 55)),
        Session(activityId: 'a1', startAt: DateTime(2026, 7, 7, 9, 58)),
      ];
      final m2 = computeCoachMoment(
          now, stFull([], sessions: running), _sched(today, []), running);
      expect(m2.hidden, isTrue);
    });

    test('la chain prime sur la dérive (on vient de finir, on enchaîne)', () {
      final now = DateTime(2026, 7, 7, 10, 0);
      final sessions = [
        Session(
            activityId: 'a1',
            startAt: DateTime(2026, 7, 7, 9, 30),
            endAt: DateTime(2026, 7, 7, 9, 55)),
      ];
      final sched = _sched(today, [
        // Bloc en dérive (posé 8h30, 0 min logguée dessus).
        _block(
            startTime: '08:30',
            durationMin: 20,
            title: 'Revue',
            activityId: 'x'),
      ]);
      final m = computeCoachMoment(
          now, stFull([], sessions: sessions), sched, sessions);
      expect(m.type, CoachMomentType.chain);
    });

    test('rien de réel à proposer → pas de carte', () {
      final now = DateTime(2026, 7, 7, 10, 0);
      final sessions = [
        Session(
            activityId: 'a1',
            startAt: DateTime(2026, 7, 7, 9, 30),
            endAt: DateTime(2026, 7, 7, 9, 55)),
      ];
      // Aucune routine, aucun bloc : rien à enchaîner — silence.
      final m = computeCoachMoment(now, _st(sessions), null, sessions);
      expect(m.hidden, isTrue);
    });

    test('le défi ORION est la suite — sauf sur l\'activité qu\'on vient de finir',
        () {
      ChallengeProposal chal(
              {String id = 'a1',
              String name = 'Sport',
              int minutes = 20,
              int targetMin = 60}) =>
          ChallengeProposal(
              activity: Activity(
                  id: id, name: name, domainId: 'd1', goalMin: targetMin),
              minutes: minutes,
              doneMin: 0,
              targetMin: targetMin);
      final now = DateTime(2026, 7, 7, 10, 0);
      final sessions = [
        Session(
            activityId: 'a1',
            startAt: DateTime(2026, 7, 7, 9, 30),
            endAt: DateTime(2026, 7, 7, 9, 55)),
      ];
      final st = stFull([], sessions: sessions);
      // Défi sur une AUTRE activité : il prend la place du combleur.
      final m1 = computeCoachMoment(now, st, _sched(today, []), sessions,
          challenge:
              chal(id: 'a2', name: 'Guitare', targetMin: 45, minutes: 25));
      expect(m1.type, CoachMomentType.chain);
      expect(m1.message, contains('ORION te défie : 25 min de « Guitare »'));
      expect(
          m1.actions.any((a) =>
              a.kind == CoachActionKind.challengeAccept &&
              a.label == 'Défi : Guitare — 25 min' &&
              a.block?.activityId == 'a2'),
          isTrue);
      // Défi sur l'activité qu'on vient de finir : non — le combleur reprend.
      final m2 = computeCoachMoment(now, st, _sched(today, []), sessions,
          challenge: chal());
      expect(m2.type, CoachMomentType.chain);
      expect(m2.message, isNot(contains('ORION te défie')));
      expect(m2.message, contains('Méditation'));
    });

    test('routine sans minuteur en suite : coche directe (✓), pas de durée '
        'inventée', () {
      final now = DateTime(2026, 7, 7, 10, 0);
      final st = AppState(
        domains: [
          Domain(
              name: 'Santé',
              definitionStatus: 'active',
              intention: 'tenir le rythme'),
        ],
        activities: [
          // « Boire de l'eau » : routine à cocher, aucun minuteur.
          Activity(
              id: 'r1',
              name: 'Boire de l\'eau',
              domainId: 'd1',
              type: 'habit',
              habitFreq: HabitFreq.daily,
              order: 0),
          Activity(id: 'a1', name: 'Sport', domainId: 'd1', order: 1),
        ],
        sessions: [
          Session(
              activityId: 'a1',
              startAt: DateTime(2026, 7, 7, 9, 30),
              endAt: DateTime(2026, 7, 7, 9, 55)),
        ],
        habitProgress: [],
        habitHits: [
          for (var i = 1; i <= 7; i++)
            HabitHit(habitId: 'r1', ts: DateTime(2026, 7, 7 - i, 9, 30)),
        ],
      );
      final m = computeCoachMoment(now, st, _sched(today, []), st.sessions);
      expect(m.type, CoachMomentType.chain);
      expect(m.message, contains('Boire de l\'eau'));
      expect(m.message, contains('7 jours d\'affilée, on continue ?'));
      expect(m.message, isNot(contains('20 min')));
      // Le CTA est une coche, pas un chrono.
      final check = m.actions
          .where((a) => a.kind == CoachActionKind.checkRoutine)
          .toList();
      expect(check, hasLength(1));
      expect(check.first.label, '✓ Boire de l\'eau');
      expect(check.first.block?.activityId, 'r1');
    });
  });

  group('heure habituelle + combleur de trous', () {
    List<HabitHit> hitsAt(String id, DateTime now,
            List<({int daysAgo, int h, int m})> specs) =>
        [
          for (final s in specs)
            HabitHit(
                habitId: id,
                ts: DateTime(
                    now.year, now.month, now.day - s.daysAgo, s.h, s.m)),
        ];

    AppState stRoutines(List<HabitHit> hits) => AppState(
          domains: [
            Domain(
                name: 'Santé',
                definitionStatus: 'active',
                intention: 'tenir le rythme'),
          ],
          activities: [
            Activity(
                id: 'r1',
                name: 'Méditation',
                domainId: 'd1',
                type: 'habit',
                habitFreq: HabitFreq.daily,
                timerMin: 10,
                order: 0),
            Activity(
                id: 'r2',
                name: 'Marche',
                domainId: 'd1',
                type: 'habit',
                habitFreq: HabitFreq.daily,
                timerMin: 30,
                order: 1),
          ],
          sessions: [],
          habitProgress: [],
          habitHits: hits,
        );

    test('typicalMinuteOf : médiane des hits réels', () {
      final now = DateTime(2026, 7, 7, 9, 30);
      final hits = hitsAt('r1', now, [
        (daysAgo: 1, h: 9, m: 0),
        (daysAgo: 2, h: 9, m: 25),
        (daysAgo: 3, h: 10, m: 0),
      ]);
      expect(typicalMinuteOf('r1', hits, now), 9 * 60 + 25);
    });

    test('typicalMinuteOf : moins de 3 hits → null (jamais inventé)', () {
      final now = DateTime(2026, 7, 7, 9, 30);
      final hits = hitsAt('r1', now, [
        (daysAgo: 1, h: 9, m: 0),
        (daysAgo: 2, h: 9, m: 30),
      ]);
      expect(typicalMinuteOf('r1', hits, now), isNull);
      // Les hits d'une AUTRE routine ne comptent pas.
      final other = hitsAt('r2', now,
          [for (var i = 1; i <= 5; i++) (daysAgo: i, h: 9, m: 0)]);
      expect(typicalMinuteOf('r1', [...hits, ...other], now), isNull);
    });

    test('typicalMinuteOf : hits nocturnes = fin de la journée vécue', () {
      final now = DateTime(2026, 7, 7, 22, 0);
      final hits = hitsAt('r1', now, [
        (daysAgo: 1, h: 23, m: 50),
        (daysAgo: 2, h: 0, m: 10), // 0h10 = fin de la veille, pas 0h du matin
        (daysAgo: 3, h: 23, m: 30),
      ]);
      expect(typicalMinuteOf('r1', hits, now), 23 * 60 + 50);
    });

    test('gapFillers : faite aujourd\'hui / trop longue / déjà posée = écartées',
        () {
      final now = DateTime(2026, 7, 7, 9, 30);
      // Méditation (10 min) faite ce matin → seule Marche (30 min) reste.
      final done = hitsAt('r1', now, [(daysAgo: 0, h: 8, m: 0)]);
      var fillers = gapFillers(now, stRoutines(done), 120);
      expect(fillers.map((f) => f.routine.id), ['r2']);
      // Trou de 30 min : Marche (30 + 10 de marge) ne tient plus.
      fillers = gapFillers(now, stRoutines(done), 30);
      expect(fillers, isEmpty);
      // Marche déjà posée en bloc pending → le programme la porte déjà.
      fillers = gapFillers(now, stRoutines(done), 120, blocks: [
        _block(startTime: '17:00', title: 'Marche', activityId: 'r2'),
      ]);
      expect(fillers, isEmpty);
    });

    test('gapFillers : l\'heure habituelle proche prime sur l\'ordre user', () {
      final now = DateTime(2026, 7, 7, 9, 30);
      // Marche (ordre 1) a une heure habituelle ≈ maintenant → passe devant.
      final hits = hitsAt('r2', now,
          [for (var i = 1; i <= 3; i++) (daysAgo: i, h: 9, m: 40)]);
      final fillers = gapFillers(now, stRoutines(hits), 120);
      expect(fillers.map((f) => f.routine.id), ['r2', 'r1']);
      expect(fillers.first.usualTime, isTrue);
      expect(fillers.first.typicalMinute, 9 * 60 + 40);
      // Méditation sans historique : proposée quand même, sans fait inventé.
      expect(fillers[1].typicalMinute, isNull);
      expect(fillers[1].usualTime, isFalse);
    });

    test('gapFillers : jamais faite autour de cette heure (> 4 h) = écartée',
        () {
      final now = DateTime(2026, 7, 7, 9, 30);
      // Marche toujours faite à 21 h → pas proposée à 9 h 30.
      final hits = hitsAt('r2', now,
          [for (var i = 1; i <= 3; i++) (daysAgo: i, h: 21, m: 0)]);
      final fillers = gapFillers(now, stRoutines(hits), 120);
      expect(fillers.map((f) => f.routine.id), ['r1']);
    });

    test('sans historique, le méta-contexte tranche : pas d\'« Hygiène du '
        'soir » en combleur du matin', () {
      final now = DateTime(2026, 7, 7, 9, 30);
      final st = AppState(
        domains: [
          Domain(
              name: 'Santé',
              definitionStatus: 'active',
              intention: 'tenir le rythme'),
        ],
        activities: [
          Activity(
              id: 'r1',
              name: 'Hygiène du soir',
              domainId: 'd1',
              type: 'habit',
              habitFreq: HabitFreq.daily,
              timerMin: 5,
              order: 0),
        ],
        sessions: [],
        habitProgress: [],
      );
      expect(gapFillers(now, st, 120), isEmpty); // fenêtre soir ≠ 9 h 30
      // Le soir, elle redevient un combleur légitime.
      final evening = DateTime(2026, 7, 7, 20, 0);
      expect(gapFillers(evening, st, 120).map((f) => f.routine.id), ['r1']);
      // L'heure MESURÉE bat le catalogue : tenue le matin 3 fois → proposée.
      st.habitHits.addAll([
        for (var i = 1; i <= 3; i++)
          HabitHit(habitId: 'r1', ts: DateTime(2026, 7, 7 - i, 9, 40)),
      ]);
      expect(gapFillers(now, st, 120).map((f) => f.routine.id), ['r1']);
    });

    test('streakOf : série en cours, cassée, journée vécue', () {
      final now = DateTime(2026, 7, 7, 10, 0);
      List<HabitHit> daily(int days) => [
            for (var i = 1; i <= days; i++)
              HabitHit(
                  habitId: 'r1',
                  ts: DateTime(now.year, now.month, now.day - i, 9, 0)),
          ];
      // 4 jours d'affilée jusqu'à hier — pas encore aujourd'hui : série vivante.
      expect(streakOf('r1', daily(4), now), 4);
      // Trou avant-hier → la série repart d'hier.
      final broken = [
        HabitHit(habitId: 'r1', ts: DateTime(2026, 7, 6, 9, 0)),
        HabitHit(habitId: 'r1', ts: DateTime(2026, 7, 4, 9, 0)),
      ];
      expect(streakOf('r1', broken, now), 1);
      // Hit fait aujourd'hui : compte dans la série.
      final withToday = [
        HabitHit(habitId: 'r1', ts: DateTime(2026, 7, 7, 8, 0)),
        ...daily(2),
      ];
      expect(streakOf('r1', withToday, now), 3);
      // Hit nocturne (0h30) = fin de la veille, pas un jour de plus.
      final night = [
        HabitHit(habitId: 'r1', ts: DateTime(2026, 7, 7, 0, 30)), // = 6 juil.
        HabitHit(habitId: 'r1', ts: DateTime(2026, 7, 5, 22, 0)),
      ];
      expect(streakOf('r1', night, now), 2);
      expect(streakOf('r1', const [], now), 0);
    });
  });

  group('Gantt invisible : micro-action de projet (« Où va-t-on »)', () {
    Project proj(String title, List<ProjectTask> tasks,
            {String status = 'active'}) =>
        Project(
            id: 'p-$title',
            title: title,
            startDate: DateTime(2026, 6, 1),
            status: status,
            createdBy: 'u1',
            tasks: tasks);
    ProjectTask task(String id, String title,
            {DateTime? deadline,
            String status = 'pending',
            List<TaskAction>? actions}) =>
        ProjectTask(
            id: id,
            title: title,
            startDate: DateTime(2026, 6, 10),
            endDate: deadline,
            status: status,
            actions: actions);

    test('la tâche à la deadline la plus proche gagne ; done/milestone exclus',
        () {
      final g = ganttMicroAction([
        proj('Site', [
          task('t1', 'Maquette', deadline: DateTime(2026, 7, 30)),
          task('t2', 'Contenu', deadline: DateTime(2026, 7, 20)),
          task('t3', 'Vieille', deadline: DateTime(2026, 7, 1), status: 'done'),
        ]),
        proj('Archivé', [task('t9', 'X', deadline: DateTime(2026, 7, 2))],
            status: 'archived'),
      ]);
      expect(g!.taskTitle, 'Contenu');
      expect(g.projectTitle, 'Site');
      expect(g.deadline, DateTime(2026, 7, 20));
    });

    test('needsSteps : étape définie ou non (GTD)', () {
      final withStep = ganttMicroAction([
        proj('Site', [
          task('t1', 'Maquette', deadline: DateTime(2026, 7, 20), actions: [
            TaskAction(id: 'a0', title: 'Cadrer le brief', done: true),
            TaskAction(id: 'a1', title: 'Choisir la palette'),
          ]),
        ]),
      ]);
      expect(withStep!.needsSteps, isFalse);
      expect(withStep.nextAction, 'Choisir la palette');
      expect(withStep.nextActionId, 'a1');
      final without = ganttMicroAction([
        proj('Site', [task('t1', 'Maquette')]),
      ]);
      expect(without!.needsSteps, isTrue);
    });

    test('tâche déjà portée par un bloc pending du jour → exclue', () {
      final g = ganttMicroAction([
        proj('Site', [task('t1', 'Maquette', deadline: DateTime(2026, 7, 20))]),
      ], blocks: [
        _block(startTime: '16:00', title: 'Maquette', taskId: 't1'),
      ]);
      expect(g, isNull);
    });

    test('étape déjà programmée (aujourd\'hui ou futur) → exclue aussi', () {
      final g = ganttMicroAction([
        proj('Site', [task('t1', 'Maquette')]),
      ], excludeTaskIds: {'t1'});
      expect(g, isNull);
    });
  });

  group('modèles : menu / rapport hebdo', () {
    test('shiftMenuOneDay : le futur glisse d\'un jour, le passé ne bouge pas',
        () {
      final menu = Artifact(
        kind: 'weekly_menu',
        domainId: 'd1',
        entries: [
          ArtifactEntry(date: '2026-07-07', time: '12:30', title: 'Passé'),
          ArtifactEntry(date: '2026-07-08', time: '12:30', title: 'Aujourd\'hui'),
          ArtifactEntry(date: '2026-07-09', time: '12:30', title: 'Demain'),
          ArtifactEntry(weekday: 'sun', time: '17:00', title: 'Batch'),
        ],
      );
      shiftMenuOneDay(menu, '2026-07-08');
      expect(menu.entries[0].date, '2026-07-07'); // passé intouché
      expect(menu.entries[1].date, '2026-07-09');
      expect(menu.entries[2].date, '2026-07-10');
      expect(menu.entries[3].weekday, 'sun'); // motif hebdo intouché
    });

    test('recaleArtifactOneWeek : la semaine se rejoue, le passé ne bouge pas',
        () {
      final plan = Artifact(
        kind: 'training_plan',
        domainId: 'd1',
        entries: [
          ArtifactEntry(date: '2026-07-09', time: '07:15', title: 'S1 passée'),
          ArtifactEntry(date: '2026-07-14', time: '07:15', title: 'S2 mardi'),
          ArtifactEntry(date: '2026-07-16', time: '07:15', title: 'S2 jeudi'),
          ArtifactEntry(weekday: 'sat', time: '09:30', title: 'Motif hebdo'),
        ],
      );
      recaleArtifactOneWeek(plan, '2026-07-13'); // lundi de la semaine à venir
      expect(plan.entries[0].date, '2026-07-09'); // passé intouché
      expect(plan.entries[1].date, '2026-07-21'); // S2 rejouée +7 j
      expect(plan.entries[2].date, '2026-07-23');
      expect(plan.entries[3].weekday, 'sat'); // motif hebdo intouché
    });

    test('WeeklyReport : round-trip toJson → from', () {
      final r = WeeklyReport(
        weekStart: '2026-07-06',
        weekEnd: '2026-07-12',
        isoWeek: 28,
        held: 11,
        total: 14,
        checkinsDone: 5,
        domains: [
          ReportDomainFact(domainId: 'd1', name: 'Santé', vitals: [
            ReportVital(label: '2 séances / sem', done: 2, target: 2),
          ]),
        ],
        motifs: [
          ReportMotif(
              cause: 'imprevu',
              count: 3,
              brokenTotal: 4,
              hours: ['14:00', '15:00', '16:00']),
        ],
        narrative: 'Meilleure semaine du mois.',
        question: 'On déplace les relances au matin ?',
        proposedDecision: WeeklyDecision(
            domainId: 'd2',
            domainName: 'Business',
            from: 'relances à 14h',
            to: 'relances à 9h',
            reason: '0/3 à 14h'),
        decisionStatus: 'pending',
      );
      final back = WeeklyReport.from(r.toJson());
      expect(back.held, 11);
      expect(back.total, 14);
      expect(back.isoWeek, 28);
      expect(back.domains.single.vitals.single.done, 2);
      expect(back.motifs.single.hoursLabel, 'toujours entre 14 h et 16 h');
      expect(back.proposedDecision?.to, 'relances à 9h');
      expect(back.decisionStatus, 'pending');
    });

    test('WeeklyReport court : parse minutesLogged/renegotiations/secondMinimal',
        () {
      final r = WeeklyReport.from({
        'weekStart': '2026-07-06',
        'kind': 'short',
        'secondMinimal': true,
        'weekModeChosen': null,
        'facts': {
          'engagements': {'held': 2, 'total': 12},
          'checkinsDone': 3,
          'minutesLogged': 3120, // 52 h
          'renegotiations': 1,
          'domains': [],
          'motifs': [],
        },
        'narrative': 'Une semaine comme ça n\'annule rien.',
        'question': null,
      });
      expect(r.kind, 'short');
      expect(r.minutesLogged, 3120);
      expect(r.renegotiations, 1);
      expect(r.secondMinimal, isTrue);
      expect(r.weekModeChosen, isNull);
      // Round-trip conserve les champs courts.
      final back = WeeklyReport.from(r.toJson());
      expect(back.minutesLogged, 3120);
      expect(back.secondMinimal, isTrue);
    });
  });
}
