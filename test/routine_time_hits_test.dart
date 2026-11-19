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

    test('arrêter le chrono pose les coches tout de suite', () {
      final logic = app(rangement(per: 10), 21);
      logic.stopActive(notify: false);
      expect(count(logic), 2);
    });
  });
}
