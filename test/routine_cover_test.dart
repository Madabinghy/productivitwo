import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/badge_today.dart' show TodayFacts;
import 'package:productivitwo_v1/utils/badges_logic.dart';
import 'package:productivitwo_v1/utils/routine_cover.dart';
import 'package:productivitwo_v1/utils/routine_moments.dart';
import 'package:productivitwo_v1/utils/routines_today.dart';
import 'package:productivitwo_v1/utils/today_facts.dart';

void main() {
  // Jeudi 19 nov. 2026, midi.
  final now = DateTime(2026, 11, 19, 12);

  Activity pompes({bool rolling = true, int target = 10}) => Activity(
        id: 'pompes',
        domainId: 'sport',
        name: 'Pompes',
        type: 'habit',
        habitFreq: HabitFreq.daily,
        habitTarget: target,
        rolling: rolling,
        createdAt: DateTime(2026, 1, 1),
      );

  /// [perDay] : coches du jour J-n … jusqu'à aujourd'hui (dernier élément).
  List<HabitHit> hits(List<int> perDay, {String id = 'pompes'}) => [
        for (var i = 0; i < perDay.length; i++)
          for (var k = 0; k < perDay[i]; k++)
            HabitHit(habitId: id, ts: DateTime(2026, 11, 19 - (perDay.length - 1 - i), 9, k)),
      ];

  group('part du jour', () {
    test('sans avance : la cible normale', () {
      expect(rollingDayTarget(10, 60), 10);
    });
    test('l\'avance la réduit, jusqu\'à zéro', () {
      expect(rollingDayTarget(10, 65), 5);
      expect(rollingDayTarget(10, 80), 0);
    });
    test('le retard ne s\'accumule pas', () {
      expect(rollingDayTarget(10, 0), 10);
      expect(rollingDayTarget(10, 40), 10);
    });
  });

  group('routineCover', () {
    test('semaine régulière, rien aujourd\'hui : reste la cible', () {
      final c = routineCover(pompes(), hits([10, 10, 10, 10, 10, 10, 0]), now);
      expect(c.dayTarget, 10);
      expect(c.held, isFalse);
      expect(c.left, 10);
      expect(c.aheadDays, 0);
      expect(c.heldLabel, isNull);
    });

    test('la cible faite : tenue ce soir, demain redemande 10 → prendre de l\'avance', () {
      final c = routineCover(pompes(), hits([10, 10, 10, 10, 10, 10, 10]), now);
      expect(c.held, isTrue);
      expect(c.aheadDays, 0);
      expect(c.tomorrowTarget, 10);
      expect(c.canGetAhead, isTrue);
      expect(c.toFreeTomorrow, 10);
      expect(c.heldLabel, isNull);
    });

    test('semaine à trous : libérer demain demande plus que la cible', () {
      // Deux jours ratés dans la fenêtre, la cible faite aujourd'hui.
      final c = routineCover(pompes(), hits([10, 0, 10, 0, 10, 10, 10]), now);
      expect(c.held, isTrue);
      expect(c.tomorrowTarget, 10);
      expect(c.toFreeTomorrow, 30);
    });

    test('demain déjà couvert : rien à ajouter', () {
      final c = routineCover(pompes(), hits([10, 10, 10, 10, 10, 10, 30]), now);
      expect(c.toFreeTomorrow, 0);
    });

    test('30 aujourd\'hui : deux jours d\'avance, couverte jusqu\'à samedi', () {
      final c = routineCover(pompes(), hits([10, 10, 10, 10, 10, 10, 30]), now);
      expect(c.held, isTrue);
      expect(c.aheadDays, 2);
      expect(c.tomorrowTarget, 0);
      expect(c.canGetAhead, isFalse);
      expect(c.heldLabel, 'couverte jusqu\'à samedi');
    });

    test('30 hier, rien aujourd\'hui : la journée est tenue par l\'avance', () {
      final c = routineCover(pompes(), hits([10, 10, 10, 10, 10, 30, 0]), now);
      expect(c.dayTarget, 0);
      expect(c.coveredByAdvance, isTrue);
      expect(c.held, isTrue);
      expect(c.aheadDays, 1);
      expect(c.heldLabel, 'couverte jusqu\'à demain soir');
    });

    test('une avance partielle réduit la part du jour', () {
      final c = routineCover(pompes(), hits([10, 10, 10, 10, 10, 15, 0]), now);
      expect(c.dayTarget, 5);
      expect(c.left, 5);
    });

    test('un jour raté ne double pas le lendemain', () {
      final c = routineCover(pompes(), hits([10, 10, 10, 10, 10, 0, 0]), now);
      expect(c.dayTarget, 10);
    });

    test('la journée vécue : une coche à 2 h compte pour la veille', () {
      final a = pompes(target: 1);
      final c = routineCover(a, [HabitHit(habitId: 'pompes', ts: DateTime(2026, 11, 19, 2))], now);
      expect(c.todayDone, 0);
      expect(c.pastDone, 1);
    });
  });

  group('jours tenus', () {
    test('l\'avance tient les jours sans coche, puis s\'épuise', () {
      // 6 jours à 10, puis 30, puis trois jours sans rien (jusqu'à aujourd'hui).
      final h = hits([10, 10, 10, 10, 10, 10, 30, 0, 0, 0]);
      final held = rollingHeldDays(pompes(), h, now);
      expect(held.contains('2026-11-16'), isTrue); // le jour des 30
      expect(held.contains('2026-11-17'), isTrue); // couvert
      expect(held.contains('2026-11-18'), isTrue); // couvert
      expect(held.contains('2026-11-19'), isFalse); // l'avance est épuisée
    });

    test('jamais de jour à venir', () {
      final held = rollingHeldDays(pompes(), hits([70]), now);
      expect(held, {'2026-11-19'});
    });

    test('routineReachedDays suit le réglage de la routine', () {
      final h = hits([10, 10, 10, 10, 10, 30, 0]);
      expect(routineReachedDays(pompes(rolling: false), h, now: now).contains('2026-11-19'), isFalse);
      expect(routineReachedDays(pompes(), h, now: now).contains('2026-11-19'), isTrue);
    });

    test('la série continue un jour couvert par l\'avance', () {
      final h = hits([10, 10, 10, 10, 10, 30, 0]);
      expect(routineSeries(pompes(), h, now).current, 7);
      // « Chaque jour » : aujourd'hui n'est pas encore fait, la série s'arrête à hier.
      expect(routineSeries(pompes(rolling: false), h, now).current, 6);
    });

    test('un soir non couvert arrête la série', () {
      final h = hits([10, 10, 10, 0, 10, 10, 10]);
      expect(routineSeries(pompes(), h, now).current, 3);
    });
  });

  group('aujourd\'hui', () {
    test('routinesForToday : couverte = atteinte, avec son avance', () {
      final t = routinesForToday([pompes()], hits([10, 10, 10, 10, 10, 30, 0]), now).single;
      expect(t.reached, isTrue);
      expect(t.cover!.heldLabel, 'couverte jusqu\'à demain soir');
    });

    test('routinesForToday : la part du jour quand l\'avance en couvre un bout', () {
      final t = routinesForToday([pompes()], hits([10, 10, 10, 10, 10, 15, 0]), now).single;
      expect(t.reached, isFalse);
      expect(t.dayTarget, 5);
      expect(t.progressLabel, '0 / 5 aujourd\'hui');
    });

    test('routinesForToday : une routine « chaque jour » ne change pas', () {
      final t = routinesForToday([pompes(rolling: false)], hits([10, 10, 10, 10, 10, 30, 0]), now).single;
      expect(t.reached, isFalse);
      expect(t.dayTarget, 10);
      expect(t.cover, isNull);
    });

    test('une routine répartie couverte n\'a plus de part à faire', () {
      final a = pompes()..splitMoments = ['morning', 'evening'];
      final day = buildRoutineDay(activities: [a], hits: hits([10, 10, 10, 10, 10, 30, 0]), now: now);
      expect(day.slots.single.reached, isTrue);
      expect(day.slots.single.share, isNull);
    });

    TodayFacts facts(List<HabitHit> h, {bool rolling = true}) => composeTodayFacts(
          ymd: '2026-11-19',
          now: now,
          dayStartMin: 300,
          activities: [pompes(rolling: rolling)],
          hits: h,
          sessions: const [],
          moodMarks: const [],
          objectives: const [],
          projects: const [],
        );

    test('faits du jour : la journée couverte ne réclame plus la routine', () {
      final r = facts(hits([10, 10, 10, 10, 10, 30, 0])).routines.single;
      expect(r.target, 0);
      expect(r.reached, isTrue);
    });

    test('faits du jour : sans avance, la cible normale', () {
      final r = facts(hits([10, 10, 10, 10, 10, 10, 0])).routines.single;
      expect(r.target, 10);
      expect(r.reached, isFalse);
    });

    test('faits du jour : « chaque jour » réclame toujours', () {
      final r = facts(hits([10, 10, 10, 10, 10, 30, 0]), rolling: false).routines.single;
      expect(r.target, 10);
      expect(r.reached, isFalse);
    });
  });

  test('le réglage survit à l\'enregistrement', () {
    expect(Activity.from(pompes().toJson()).rolling, isTrue);
    expect(Activity.from(pompes(rolling: false).toJson()).rolling, isFalse);
    expect(Activity.from({'id': 'x', 'name': 'X', 'type': 'habit'}).rolling, isFalse);
  });
}
