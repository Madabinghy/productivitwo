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

  group('jauge du jour', () {
    test('semaine régulière : une case par jour, au prix de la cible', () {
      final c = routineCover(pompes(), hits([10, 10, 10, 10, 10, 10, 4]), now);
      expect(c.thresholds.take(4), [10, 20, 30, 40]);
      final slots = coverSlots(c);
      expect([for (final s in slots) s.cost], [10, 10, 10, 10]);
      expect(slots.first.fill, closeTo(.4, 1e-9));
      expect(slots.first.left, 6);
      expect(slots[1].fill, 0);
      expect([for (final s in slots) coverSlotLabel(c.today, s)], ['ce soir', 'demain', 'sam.', 'dim.']);
    });

    test('les coches en plus remplissent le jour suivant', () {
      final slots = coverSlots(routineCover(pompes(), hits([10, 10, 10, 10, 10, 10, 25]), now));
      expect(slots[0].full, isTrue);
      expect(slots[1].full, isTrue);
      expect(slots[2].fill, closeTo(.5, 1e-9));
      expect(slots[2].left, 5);
      expect(slots[3].full, isFalse);
    });

    test('semaine à trous : les jours ratés à rattraper d\'abord, demain au même prix qu\'avant', () {
      final c = routineCover(pompes(), hits([10, 0, 10, 0, 10, 10, 0]), now);
      final slots = coverSlots(c);
      expect([for (final s in slots) coverSlotLabel(c.today, s)], ['ce soir', 'lun. 16', 'sam. 14', 'demain']);
      expect([for (final s in slots) s.cost], [10, 10, 10, 10]);
      // 10 ce soir + 20 de rattrapage + 10 : demain est libre à 40, comme la règle des 7 jours.
      expect((slots.last.hi, c.toFreeTomorrow), (40, 40));
    });

    test('avance d\'hier : ce soir et demain déjà acquis', () {
      final c = routineCover(pompes(), hits([10, 10, 10, 10, 10, 30, 0]), now);
      final slots = coverSlots(c);
      expect(slots.first.cost, 0);
      expect(slots.first.full, isTrue);
      expect(coverSlotLabel(c.today, slots.first), 'ce soir + dem.');
      expect([for (final s in slots.skip(1)) s.cost], [10, 10]);
    });

    test('trois jours ratés : trois cases de rattrapage, puis demain', () {
      final c = routineCover(pompes(), hits([10, 0, 0, 0, 10, 10, 0]), now);
      final slots = coverSlots(c);
      expect([for (final s in slots) coverSlotLabel(c.today, s)], ['ce soir', 'lun. 16', 'dim. 15', 'sam. 14', 'demain']);
    });

    test('plusieurs jours déjà couverts : « ce soir → dim. »', () {
      final c = routineCover(pompes(), hits([10, 10, 10, 10, 10, 50, 0]), now);
      expect(coverSlotLabel(c.today, coverSlots(c).first), 'ce soir → dim.');
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

  group('rattraper un jour raté', () {
    // Vaisselle : 1 fois par jour. now = jeudi 19 ; mardi 17 et mercredi 18 ratés.
    Activity vaisselle({bool catchUp = true, bool rolling = false}) => Activity(
          id: 'v', domainId: 'd', name: 'Vaisselle', type: 'habit', habitFreq: HabitFreq.daily, habitTarget: 1, catchUp: catchUp, rolling: rolling, createdAt: DateTime(2026, 1, 1));
    List<HabitHit> h(List<int> perDay) => hits(perDay, id: 'v');

    test('« Chaque jour » : rien ne se rattrape', () {
      final c = catchUpOf(vaisselle(catchUp: false), h([1, 1, 1, 1, 0, 0, 3]), now);
      expect(c.repaired, isEmpty);
      expect(c.open, isEmpty);
    });

    test('« Rattrapable » : ce qui est fait en plus comble le jour raté le plus récent d\'abord', () {
      final a = vaisselle();
      // 1 aujourd'hui : tenue, les deux trous attendent.
      var c = catchUpOf(a, h([1, 1, 1, 1, 0, 0, 1]), now);
      expect(c.repaired, isEmpty);
      expect([for (final x in c.open) x.day.day], [18, 17]);
      // 2 : mercredi rattrapé, mardi attend encore.
      c = catchUpOf(a, h([1, 1, 1, 1, 0, 0, 2]), now);
      expect(c.repaired, {'2026-11-18'});
      // 3 : les deux.
      c = catchUpOf(a, h([1, 1, 1, 1, 0, 0, 3]), now);
      expect(c.repaired, {'2026-11-18', '2026-11-17'});
    });

    test('au-delà de 7 jours, un jour raté ne se rattrape plus', () {
      // Raté il y a 7 jours (jeudi 12), puis 6 jours tenus : aujourd'hui, il est sorti de la fenêtre.
      final c = catchUpOf(vaisselle(), h([1, 0, 1, 1, 1, 1, 1, 1, 3]), now);
      expect(c.repaired, isEmpty);
      // Raté il y a 6 jours (vendredi 13) : encore rattrapable.
      expect(catchUpOf(vaisselle(), h([1, 0, 1, 1, 1, 1, 1, 2]), now).repaired, {'2026-11-13'});
    });

    test('un jour gelé n\'est pas un trou', () {
      final c = catchUpOf(vaisselle(), h([1, 1, 1, 1, 0, 0, 1]), now, frozen: {'2026-11-18'});
      expect([for (final x in c.open) x.day.day], [17]);
    });

    test('rattrapé un autre jour que le lendemain, et à moitié puis en entier', () {
      // Cible 10 : lundi 16 à 4 (il manque 6), mardi 13 (3 de trop), mercredi 13 (3 de trop) → comblé mercredi.
      final a = Activity(id: 'p', domainId: 'd', name: 'Pompes', type: 'habit', habitFreq: HabitFreq.daily, habitTarget: 10, catchUp: true, createdAt: DateTime(2026, 1, 1));
      expect(catchUpOf(a, hits([10, 4, 13, 10, 0], id: 'p'), now).repaired, isEmpty);
      expect(catchUpOf(a, hits([10, 4, 13, 13, 0], id: 'p'), now).repaired, {'2026-11-16'});
    });

    test('la série recolle par un jour rattrapé, sans devenir un jour atteint', () {
      final a = vaisselle();
      final all = h([1, 1, 1, 1, 0, 0, 3]);
      final fixed = catchUpOf(a, all, now).repaired;
      // Les jours atteints ne changent pas : mardi et mercredi restent non atteints (pas de journée parfaite après coup).
      expect(routineReachedDays(a, all, now: now).contains('2026-11-18'), isFalse);
      expect(routineSeries(a, all, now).current, 1);
      expect(routineSeries(a, all, now, bridged: fixed).current, 7);
    });

    test('la jauge : ce soir, puis les jours à rattraper, sans avance en « Rattrapable »', () {
      final c = routineCover(vaisselle(), h([1, 1, 1, 1, 0, 0, 2]), now);
      expect((c.advance, c.dayTarget, c.held, c.canGetAhead), (false, 1, true, false));
      expect(c.holeThresholds, [2, 3]);
      expect((c.holesFilled, c.holesLeft, c.canCatchUp, c.toNextHole), (1, 1, true, 1));
      expect(holeDayLabel(c.today, c.nextHole!.day), 'mardi');
      final slots = coverSlots(c);
      expect([for (final s in slots) coverSlotLabel(c.today, s)], ['ce soir', 'hier', 'mar. 17']);
      expect([for (final s in slots) s.full], [true, true, false]);
    });

    test('« Sur 7 jours » : les jours à rattraper passent avant l\'avance', () {
      final c = routineCover(vaisselle(catchUp: false, rolling: true), h([1, 1, 1, 1, 0, 0, 1]), now);
      final slots = coverSlots(c);
      expect([for (final s in slots) coverSlotLabel(c.today, s)].take(4).toList(), ['ce soir', 'hier', 'mar. 17', 'demain']);
      // 1 ce soir + 2 trous + 1 = demain libre, comme la règle des 7 jours.
      expect((slots[3].hi, c.toFreeTomorrow), (4, 3));
      expect(c.canCatchUp, isTrue);
    });

    test('le réglage survit à l\'enregistrement', () {
      expect(Activity.from(vaisselle().toJson()).catchUp, isTrue);
      expect(Activity.from({'id': 'x', 'name': 'X', 'type': 'habit'}).catchUp, isFalse);
    });
  });

  group('jauge du jour : cases', () {
    final lundi = DateTime(2026, 11, 16), samedi = DateTime(2026, 11, 14);

    test('une case sans prix après des jours à rattraper n\'est pleine que si son seuil est atteint', () {
      // « Motivation », vendredi 20 : ce soir fait (1), lundi et samedi à rattraper (seuils 2 et 3), demain gagné
      // au même seuil que samedi. Avec 1 coche, demain n'est PAS acquis.
      const demain = CoverSlot(from: 1, to: 1, lo: 3, hi: 3, done: 1);
      expect(demain.cost, 0);
      expect(demain.full, isFalse);
      expect(demain.fill, 0);
      // À 3 coches, les deux jours sont rattrapés et demain est acquis.
      expect(const CoverSlot(from: 1, to: 1, lo: 3, hi: 3, done: 3).fill, 1);
      // Une case déjà acquise par l'avance des jours passés reste pleine.
      expect(const CoverSlot(from: 1, to: 1, lo: 0, hi: 0, done: 0).fill, 1);
    });

    test('les cases qui ne tiennent pas sont retirées : les jours ratés les plus anciens d\'abord, « ce soir » reste', () {
      final slots = [
        const CoverSlot(from: 0, to: 0, lo: 0, hi: 1, done: 0),
        CoverSlot(from: 0, to: 0, lo: 1, hi: 2, done: 0, hole: DateTime(2026, 11, 19)),
        CoverSlot(from: 0, to: 0, lo: 2, hi: 3, done: 0, hole: DateTime(2026, 11, 18)),
        CoverSlot(from: 0, to: 0, lo: 3, hi: 4, done: 0, hole: DateTime(2026, 11, 17)),
        const CoverSlot(from: 1, to: 1, lo: 4, hi: 5, done: 0),
        const CoverSlot(from: 2, to: 2, lo: 5, hi: 6, done: 0),
      ];
      final w = List.filled(slots.length, 40.0);
      String names(List<CoverSlot> l) => l.map((s) => coverSlotLabel(DateTime(2026, 11, 20), s)).join(' | ');
      // Tout tient.
      expect(fitCoverSlots(slots, w, 300).length, 6);
      // 4 cases : les deux jours ratés les plus anciens partent.
      expect(names(fitCoverSlots(slots, w, 175)), 'ce soir | hier | demain | dim.');
      // 3 cases : puis le jour à venir le plus lointain.
      expect(names(fitCoverSlots(slots, w, 130)), 'ce soir | hier | demain');
      // 2 cases : puis le dernier jour raté.
      expect(names(fitCoverSlots(slots, w, 90)), 'ce soir | demain');
      expect(names(fitCoverSlots(slots, w, 10)), 'ce soir');
      // À l'écran, les cases sont rangées comme un calendrier : le passé à gauche, ce soir, puis l'avenir.
      expect([for (final i in calendarOrder(slots)) coverSlotLabel(DateTime(2026, 11, 20), slots[i])].join(' | '), 'mar. 17 | mer. 18 | hier | ce soir | demain | dim.');
      expect(calendarOrder(slots.sublist(0, 1)), [0]);
      expect(calendarOrder(const []), isEmpty);
      // Les dates d'un jour raté sont celles du passé : lundi 16 et samedi 14 vus du vendredi 20.
      expect(names([CoverSlot(from: 0, to: 0, lo: 1, hi: 2, done: 0, hole: lundi), CoverSlot(from: 0, to: 0, lo: 2, hi: 3, done: 0, hole: samedi)]), 'lun. 16 | sam. 14');
    });
  });
}
