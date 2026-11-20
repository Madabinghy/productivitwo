import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/routine_cover.dart';

void main() {
  Activity rangement({int? per = 5, String? linked = 'act'}) => Activity(
        id: 'rangement',
        domainId: 'd',
        name: 'Rangement',
        type: 'habit',
        habitFreq: HabitFreq.daily,
        habitTarget: 1,
        linkedActivityId: linked,
        minPerHit: per,
        createdAt: DateTime(2026, 1, 1),
      );

  group('calcul', () {
    final now = DateTime(2026, 11, 19, 12);
    Session s(DateTime from, DateTime? to, {String act = 'act', bool deleted = false}) =>
        Session(activityId: act, startAt: from, endAt: to)..deleted = deleted;

    test('la routine se coche par le chrono seulement avec une durée ET une activité liée', () {
      expect(hasTimeHits(rangement()), isTrue);
      expect(hasTimeHits(rangement(per: null)), isFalse);
      expect(hasTimeHits(rangement(per: 0)), isFalse);
      expect(hasTimeHits(rangement(linked: null)), isFalse);
      expect(hasTimeHits(rangement(linked: ' ')), isFalse);
    });

    test('15 min de chrono à 5 min la coche = 3 coches ; 14 min = 2', () {
      expect(timeHitsEarned(rangement(), [s(DateTime(2026, 11, 19, 10), DateTime(2026, 11, 19, 10, 15))], now), 3);
      expect(timeHitsEarned(rangement(), [s(DateTime(2026, 11, 19, 10), DateTime(2026, 11, 19, 10, 14))], now), 2);
    });

    test('plusieurs chronos du jour s\'additionnent, le chrono en cours compte jusqu\'à maintenant', () {
      final sessions = [
        s(DateTime(2026, 11, 19, 8), DateTime(2026, 11, 19, 8, 4)),
        s(DateTime(2026, 11, 19, 11, 53), null), // 7 min en cours
      ];
      expect(livedMinutesOn('act', sessions, now), 11);
      expect(timeHitsEarned(rangement(), sessions, now), 2);
    });

    test('seul le temps de la journée vécue et de l\'activité liée compte', () {
      final sessions = [
        s(DateTime(2026, 11, 18, 20), DateTime(2026, 11, 18, 21)), // hier
        s(DateTime(2026, 11, 19, 4, 50), DateTime(2026, 11, 19, 5, 6)), // à cheval sur la bascule de 5 h : 6 min
        s(DateTime(2026, 11, 19, 9), DateTime(2026, 11, 19, 10), act: 'autre'),
        s(DateTime(2026, 11, 19, 9), DateTime(2026, 11, 19, 10), deleted: true),
      ];
      expect(livedMinutesOn('act', sessions, now), 6);
      expect(timeHitsEarned(rangement(), sessions, now), 1);
    });

    test('le rang des coches déjà posées par le chrono', () {
      final hits = [
        HabitHit(id: timeHitId('rangement', '2026-11-19', 1), habitId: 'rangement', ts: now),
        HabitHit(id: timeHitId('rangement', '2026-11-19', 2), habitId: 'rangement', ts: now),
        HabitHit(id: timeHitId('rangement', '2026-11-18', 5), habitId: 'rangement', ts: now),
        HabitHit(habitId: 'rangement', ts: now), // à la main
      ];
      expect(timeHitsGiven('rangement', '2026-11-19', hits), 2);
      expect(timeHitsGiven('rangement', '2026-11-20', hits), 0);
    });

    test('le réglage survit à l\'enregistrement', () {
      expect(Activity.from(rangement().toJson()).minPerHit, 5);
      expect(Activity.from(rangement(per: null).toJson()).minPerHit, isNull);
    });
  });

  group('d\'office : une routine seule sur son activité', () {
    Activity routine(String id, {int? timer, int? per, String? linked = 'act', bool off = false, bool deleted = false}) => Activity(
          id: id,
          domainId: 'd',
          name: id,
          type: 'habit',
          habitFreq: HabitFreq.daily,
          habitTarget: 1,
          linkedActivityId: linked,
          timerMin: timer,
          minPerHit: per,
          chronoOff: off,
          createdAt: DateTime(2026, 1, 1),
        )..deleted = deleted;

    test('une durée, une activité liée, seule routine dessus : le chrono coche à la durée d\'une fois', () {
      final r = routine('motivation', timer: 15);
      expect(chronoHitMin(r, [r]), 15);
      expect(hasTimeHits(r, [r]), isTrue);
      // Sans la liste des activités, on ne sait pas si elle est seule : rien d'office.
      expect(chronoHitMin(r), isNull);
      // Sans durée, rien à compter.
      final plain = routine('motivation');
      expect(chronoHitMin(plain, [plain]), isNull);
      // Sans activité liée non plus.
      final loose = routine('motivation', timer: 15, linked: null);
      expect(chronoHitMin(loose, [loose]), isNull);
    });

    test('éteinte à la main, elle ne se coche plus d\'office ; rallumée, si', () {
      final r = routine('motivation', timer: 15);
      r.setChronoHits(false);
      expect(r.chronoOff, isTrue);
      expect(r.onceMin, 15); // la durée du ⏱ reste
      expect(chronoHitMin(r, [r]), isNull);
      expect(Activity.from(r.toJson()).chronoOff, isTrue);
      r.setChronoHits(true);
      expect(r.chronoOff, isFalse);
      expect(r.minPerHit, 15);
      expect(chronoHitMin(r, [r]), 15);
      // Éteindre un réglage posé à la main garde la durée d'une fois.
      final set = routine('lecture', per: 20)..setChronoHits(false);
      expect(set.minPerHit, isNull);
      expect(set.onceMin, 20);
    });

    test('plusieurs routines sur la même activité : rien d\'office, sauf celle réglée à la main', () {
      final lit = routine('Faire mon lit', timer: 5);
      final ranger = routine('Ranger', timer: 10);
      final all = [lit, ranger];
      expect(chronoHitMin(lit, all), isNull);
      expect(chronoHitMin(ranger, all), isNull);
      final forced = routine('Ranger', per: 10);
      expect(chronoHitMin(forced, [lit, forced]), 10);
      // Une routine supprimée ne compte pas : l'autre redevient seule.
      final gone = routine('Ranger', timer: 10, deleted: true);
      expect(chronoHitMin(lit, [lit, gone]), 5);
    });

    test('à l\'arrêt du chrono : les routines à proposer, et ce que chacune prendrait', () {
      final lit = routine('Faire mon lit', timer: 5);
      final ranger = routine('Ranger', timer: 10);
      final off = routine('Trier', timer: 5, off: true);
      final reps = routine('Pompes'); // pas de durée : le temps ne se traduit pas en coches
      final forced = routine('Balayer', per: 5); // se coche déjà toute seule
      final other = routine('Lire', timer: 5, linked: 'autre');
      final all = [ranger, lit, off, reps, forced, other];
      expect(routinesToAsk('act', all, 25).map((r) => r.name), ['Faire mon lit', 'Ranger']);
      // 7 minutes : seule la routine de 5 min y gagne une coche.
      expect(routinesToAsk('act', all, 7).map((r) => r.name), ['Faire mon lit']);
      expect(routinesToAsk('act', all, 3), isEmpty);
      // Une seule routine sur l'activité : pas de question, elle se coche d'office.
      expect(routinesToAsk('autre', all, 25), isEmpty);
      expect(askedHits(ranger, 25), 2);
      expect(askedHits(lit, 25), 5);
      expect(askedHitId('r', 's1', 2), 'ask-r-s1-2');
    });
  });

  group('dans l\'app', () {
    AppLogic app(Activity r, int chronoMin) {
      final now = DateTime.now();
      final logic = AppLogic(AppState(domains: [], activities: [], sessions: [], habitProgress: []), () {});
      // La bascule de journée à 12 h d'ici : le chrono du test est toujours dans la journée vécue.
      logic.dayStartMin = (now.hour * 60 + now.minute + 720) % 1440;
      logic.state.activities.addAll([Activity(id: 'act', domainId: 'd', name: 'Ranger', createdAt: DateTime(2026, 1, 1)), r]);
      logic.state.sessions.add(Session(activityId: 'act', startAt: now.subtract(Duration(minutes: chronoMin, seconds: 20))));
      return logic;
    }

    int count(AppLogic l) => l.state.habitHits.where((h) => h.habitId == 'rangement').length;

    test('16 min de chrono posent 3 coches, une seule fois, et l\'annoncent', () {
      final logic = app(rangement(), 16);
      final said = <(int, int)>[];
      logic.onTimeHits = (r, added, minutes) => said.add((added, minutes));
      logic.checkTimeHits();
      expect(count(logic), 3);
      expect(said, [(3, 15)]);
      logic.checkTimeHits();
      expect(count(logic), 3);
      expect(said.length, 1);
      // Les ids sont fixes : un autre appareil ne les pose pas en double.
      expect(logic.state.habitHits.map((h) => h.id).toSet(), {
        for (var k = 1; k <= 3; k++) timeHitId('rangement', logic.livedTodayYmd, k),
      });
    });

    test('les coches du chrono s\'ajoutent à celles posées à la main', () {
      final logic = app(rangement(), 6);
      logic.incHabit('rangement', 1, logic.livedToday);
      logic.checkTimeHits();
      expect(count(logic), 2);
    });

    test('une coche annulée ne revient pas', () {
      final logic = app(rangement(), 11);
      logic.checkTimeHits();
      expect(count(logic), 2);
      logic.incHabit('rangement', -1, logic.livedToday);
      logic.checkTimeHits();
      expect(count(logic), 1);
    });

    test('sans réglage, le chrono ne coche rien', () {
      final logic = app(rangement(per: null), 30);
      logic.checkTimeHits();
      expect(count(logic), 0);
    });

    test('seule routine de son activité, avec une durée : le chrono la coche sans réglage (25 min à 15 min = 1 coche)', () {
      final r = Activity(
        id: 'rangement',
        domainId: 'd',
        name: 'Rangement',
        type: 'habit',
        habitFreq: HabitFreq.daily,
        habitTarget: 1,
        linkedActivityId: 'act',
        timerMin: 15,
        createdAt: DateTime(2026, 1, 1),
      );
      final logic = app(r, 25);
      final said = <(int, int)>[];
      logic.onTimeHits = (r, added, minutes) => said.add((added, minutes));
      logic.checkTimeHits();
      expect(count(logic), 1);
      expect(said, [(1, 15)]);
      // Une deuxième routine liée à la même activité : plus rien d'office.
      final two = app(r, 25);
      two.state.activities.add(Activity(id: 'lit', domainId: 'd', name: 'Faire mon lit', type: 'habit', linkedActivityId: 'act', timerMin: 5, createdAt: DateTime(2026, 1, 1)));
      two.checkTimeHits();
      expect(count(two), 0);
    });

    test('arrêter le chrono pose les coches tout de suite', () {
      final logic = app(rangement(per: 10), 21);
      logic.stopActive(notify: false);
      expect(count(logic), 2);
    });
  });
}
