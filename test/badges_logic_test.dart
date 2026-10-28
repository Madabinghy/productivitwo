import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/badges_logic.dart';

void main() {
  final now = DateTime(2026, 10, 26, 10); // lundi 26 oct., 10 h

  Activity routine(String id, {int target = 1}) => Activity(
        id: id,
        domainId: 'd',
        name: id,
        role: ActivityRole.generic,
        type: 'habit',
        goalMin: 1,
        habitFreq: HabitFreq.daily,
        habitTarget: target,
        createdAt: DateTime(2026, 1, 1),
      );

  /// `n` hits par jour, de `from` (inclus) sur `days` jours, à 8 h.
  List<HabitHit> hits(String id, DateTime from, int days, {int n = 1}) => [
        for (var d = 0; d < days; d++)
          for (var k = 0; k < n; k++)
            HabitHit(habitId: id, ts: DateTime(from.year, from.month, from.day + d, 8, k)),
      ];

  group('séries de routine', () {
    test('34 jours d\'affilée jusqu\'à aujourd\'hui = palier 3, 34 / 66', () {
      final a = routine('med');
      final s = routineSeries(a, hits('med', DateTime(2026, 9, 23), 34), now);
      expect(s.current, 34);
      expect(s.longest, 34);
      expect(s.tierDates[0], DateTime(2026, 9, 25)); // 3e jour
      expect(s.tierDates[2], DateTime(2026, 10, 13)); // 21e jour
      expect(s.tierDates[3], isNull);
    });

    test('la cible compte : 2 hits attendus, un seul jour sur deux l\'atteint', () {
      final a = routine('pompes', target: 2);
      final h = [
        ...hits('pompes', DateTime(2026, 10, 24), 1, n: 2),
        ...hits('pompes', DateTime(2026, 10, 25), 1, n: 1),
      ];
      final days = routineReachedDays(a, h);
      expect(days, {'2026-10-24'});
    });

    test('rien aujourd\'hui ne casse pas encore la série ; un trou la remet à zéro, le palier reste', () {
      final a = routine('lecture');
      final h = hits('lecture', DateTime(2026, 10, 16), 10); // 16 → 25 oct.
      final s = routineSeries(a, h, now);
      expect(s.current, 10);
      final broken = routineSeries(a, hits('lecture', DateTime(2026, 10, 1), 8), now); // 1 → 8 oct.
      expect(broken.current, 0);
      expect(broken.longest, 8);
      final deck = computeBadges(
        activities: [a],
        habitHits: hits('lecture', DateTime(2026, 10, 1), 8),
        schedules: const [],
        projects: const [],
        objectives: const [],
        sessions: const [],
        now: now,
      );
      final b = deck.byId('serie-lecture')!;
      expect(b.level, 2); // 7 jours atteints un jour, acquis pour toujours
      expect(b.value, 0);
      expect(b.nextTarget, 21);
    });

    test('un hit nocturne compte pour la journée vécue de la veille', () {
      final a = routine('eau');
      final h = [HabitHit(habitId: 'eau', ts: DateTime(2026, 10, 25, 2, 30))];
      expect(routineReachedDays(a, h), {'2026-10-24'});
    });
  });

  group('journées', () {
    DailySchedule sched(String ymd, List<String> statuses, {bool mirror = false}) => DailySchedule(
          date: ymd,
          generatedBy: 'claude',
          generatedAt: now,
          blocks: [
            for (final st in statuses)
              ScheduleBlock(
                id: '$ymd-$st-${statuses.indexOf(st)}',
                startTime: '09:00',
                durationMin: 60,
                title: 'b',
                category: 'project',
                status: st,
                gcalEventId: mirror ? 'ev' : null,
              ),
          ],
        );

    test('parfaite = toutes les routines dues et tous les blocs comptés ; sautés et miroirs ignorés', () {
      final a = routine('med');
      final reached = {'med': {'2026-10-25'}};
      final d = scoreDay(DateTime(2026, 10, 25),
          activities: [a], reachedDaysByRoutine: reached, schedule: sched('2026-10-25', ['done', 'skipped', 'deleted']));
      expect(d.blocks, 1);
      expect(d.perfect, isTrue);
      final m = scoreDay(DateTime(2026, 10, 25),
          activities: [a], reachedDaysByRoutine: reached, schedule: sched('2026-10-25', ['pending'], mirror: true));
      expect(m.blocks, 0, reason: 'un miroir d\'agenda ne compte pas');
      expect(m.perfect, isTrue);
    });

    test('une journée sans rien à tenir est neutre et n\'interrompt pas une semaine solide', () {
      final a = routine('med');
      final h = [
        ...hits('med', DateTime(2026, 10, 15), 4), // 15 → 18
        ...hits('med', DateTime(2026, 10, 20), 6), // 20 → 25 ; le 19 : routine due, pas atteinte
      ];
      final late = routine('tard')..habitFreq = HabitFreq.daily;
      final deck = computeBadges(
        activities: [a, late],
        habitHits: h,
        schedules: const [],
        projects: const [],
        objectives: const [],
        sessions: const [],
        now: now,
      );
      final week = deck.byId('semaine-solide')!;
      // « tard » est due tous les jours et jamais atteinte : 1 / 2 routines = 50 %, jamais solide.
      expect(week.level, 0);
      final deck2 = computeBadges(
        activities: [a],
        habitHits: h,
        schedules: const [],
        projects: const [],
        objectives: const [],
        sessions: const [],
        now: now,
      );
      final w2 = deck2.byId('semaine-solide')!;
      expect(w2.level, 0, reason: 'le 19 casse : 6 jours solides seulement');
      expect(w2.value, 6);
      final deck3 = computeBadges(
        activities: [a],
        habitHits: hits('med', DateTime(2026, 10, 18), 8), // 18 → 25
        schedules: const [],
        projects: const [],
        objectives: const [],
        sessions: const [],
        now: now,
      );
      final w3 = deck3.byId('semaine-solide')!;
      expect(w3.level, 1);
      expect(w3.obtained, DateTime(2026, 10, 24));
      expect(deck3.byId('journee-parfaite')!.level, 1);
    });
  });

  group('objectifs', () {
    test('relevé fidèle : 8 relevés hebdo sans trou ; un trou de 15 j repart', () {
      final o = StrategicObjective(
        title: 'Livre',
        metric: ObjectiveMetric(label: 'Chapitres', targetValue: 24),
        readings: [for (var i = 0; i < 9; i++) ObjectiveReading(date: '2026-${(8 + (i * 7) ~/ 30).toString().padLeft(2, '0')}-01', value: i.toDouble())],
      );
      // dates ci-dessus irrégulières : on reconstruit proprement
      o.readings
        ..clear()
        ..addAll([for (var i = 0; i < 9; i++) ObjectiveReading(date: _ymd(DateTime(2026, 8, 1 + 7 * i)), value: i.toDouble())]);
      final f = faithfulReadings(o);
      expect(f.longest, 9);
      expect(f.tierDates[0], DateTime(2026, 9, 19)); // 8e relevé
      o.readings.add(ObjectiveReading(date: _ymd(DateTime(2026, 10, 15)), value: 9)); // trou de 19 j après le 26 sept.
      expect(faithfulReadings(o).current, 1);
    });

    test('première cible et cible atteinte', () {
      final done = StrategicObjective(
        title: 'Poids',
        status: 'done',
        metric: ObjectiveMetric(label: 'kg', startValue: 82, targetValue: 75),
        readings: [ObjectiveReading(date: '2026-10-01', value: 74.5)],
        updatedAt: DateTime(2026, 10, 2),
      );
      final deck = computeBadges(
        activities: const [],
        habitHits: const [],
        schedules: const [],
        projects: const [],
        objectives: [done],
        sessions: const [],
        now: now,
      );
      expect(deck.byId('premiere-cible')!.level, 1);
      expect(deck.byId('premiere-cible')!.obtained, DateTime(2026, 10, 2));
      expect(deck.byId('cible-atteinte')!.level, 1, reason: 'métrique décroissante atteinte');
    });

    test('temps investi : 100 h franchies à la date de la session qui les franchit', () {
      final o = StrategicObjective(
        title: 'Livre',
        startDate: DateTime(2026, 6, 1),
        timeCommitments: [ObjectiveTimeCommitment(activityId: 'ecrire', weeklyMin: 300)],
      );
      final sessions = [
        for (var d = 0; d < 60; d++)
          Session(activityId: 'ecrire', startAt: DateTime(2026, 6, 1 + d, 9), endAt: DateTime(2026, 6, 1 + d, 11)),
      ];
      final h = investedHours(o, sessions, now);
      expect(h.hours, 120);
      expect(h.tierDates[0], DateTime(2026, 7, 20)); // 50e session de 2 h
      expect(h.tierDates[1], isNull);
    });
  });

  group('deck', () {
    test('actions accomplies et comptes du deck', () {
      final p = Project(
        id: 'p',
        title: 'P',
        createdBy: 'test',
        startDate: DateTime(2026, 1, 1),
        tasks: [
          ProjectTask(title: 't', startDate: DateTime(2026, 1, 1), actions: [
            for (var i = 0; i < 12; i++) TaskAction(title: 'a$i', done: true, doneAt: DateTime(2026, 10, 1 + i)),
            TaskAction(title: 'ouverte'),
          ]),
        ],
      );
      final deck = computeBadges(
        activities: const [],
        habitHits: const [],
        schedules: const [],
        projects: [p],
        objectives: const [],
        sessions: const [],
        now: now,
      );
      final a = deck.byId('actions')!;
      expect(a.level, 1);
      expect(a.value, 12);
      expect(a.obtained, DateTime(2026, 10, 10));
      expect(a.ribbonLabel, '10');
      expect(a.nextTarget, 50);
      // 1 + 3 + 2 + 1 (objectifs) + 1 + 1 + 1 (journées) + 3 + 1 + 1 + 3 + 3 (discipline, dont Deep work) + 3 + 1 (enchaîner) + 8 (actions)
      expect(deck.total, 33);
      expect(deck.acquired, 1);
      // Les séries de routine ne comptent pas dans « n sur N » : elles se montrent à part.
      final withRoutine = computeBadges(
        activities: [routine('med')],
        habitHits: hits('med', DateTime(2026, 10, 16), 10),
        schedules: const [],
        projects: [p],
        objectives: const [],
        sessions: const [],
        now: now,
      );
      expect(withRoutine.total, 33);
      // actions 1 + Journée parfaite 1 + Semaine solide 1 (10 jours de routine atteinte, sans bloc) ; la série (palier 2) ne compte pas
      expect(withRoutine.acquired, 3);
      expect(withRoutine.series.length, 1);
      expect(withRoutine.seriesRunning, 1);
      expect(withRoutine.seriesWithTier, 1);
      expect(deck.lastObtained?.def.id, 'actions');
      expect(deck.ofFamily(BadgeFamily.discipline).every((b) => b.def.measured), isTrue);
      expect(deck.ofFamily(BadgeFamily.chain).every((b) => b.def.measured), isTrue);
    });

    test('un badge simple n\'a pas de jauge, un badge à paliers en a une', () {
      const single = BadgeDef(id: 'x', family: BadgeFamily.days, name: 'x', symbol: 'sun', tiers: [1]);
      const tiered = BadgeDef(id: 'y', family: BadgeFamily.routines, name: 'y', symbol: 'flame', tiers: kRoutineTiers);
      expect(const BadgeState(def: single, level: 0, value: 0).showGauge, isFalse);
      final t = const BadgeState(def: tiered, level: 3, value: 34);
      expect(t.showGauge, isTrue);
      expect(t.progress, closeTo(34 / 66, 1e-9));
      expect(fmtInt(10000), '10 000');
    });
  });
}

String _ymd(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
