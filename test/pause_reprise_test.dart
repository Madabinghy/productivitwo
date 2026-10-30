import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/badges_logic.dart';
import 'package:productivitwo_v1/utils/embers.dart';
import 'package:productivitwo_v1/utils/reprise.dart';
import 'package:productivitwo_v1/utils/rest_periods.dart';

Set<String> octDays(Iterable<int> days) => {for (final d in days) '2026-10-${d.toString().padLeft(2, '0')}'};

void main() {
  group('périodes de veille', () {
    test('poser, prolonger, lever', () {
      var p = withRestSet(const [], 'sante', '2026-10-20', '2026-10-26');
      expect(p.single.from, '2026-10-20');
      p = withRestSet(p, 'sante', '2026-10-22', '2026-10-30');
      expect(p.single.from, '2026-10-20');
      expect(p.single.to, '2026-10-30');
      p = withRestLifted(p, 'sante', '2026-10-24');
      expect(p.single.to, '2026-10-23');
      expect(withRestLifted(withRestSet(const [], 'x', '2026-10-24', '2026-10-30'), 'x', '2026-10-24'), isEmpty);
    });

    test('jamais rétroactive, jours gelés jusqu’à aujourd’hui', () {
      expect(withRestSet(const [], 'sante', '2026-10-20', '2026-10-19'), isEmpty);
      final p = [const RestPeriod(domainId: 'sante', from: '2026-10-20', to: '2026-10-30')];
      expect(frozenDaysOf('sante', p, const {}, '2026-10-22'), octDays([20, 21, 22]));
      expect(frozenDaysOf('travail', p, const {}, '2026-10-22'), isEmpty);
    });

    test('une veille sans période gèle aujourd’hui', () {
      expect(frozenDaysOf('sante', const [], {'sante': '2026-10-30'}, '2026-10-22'), {'2026-10-22'});
      expect(frozenDaysOf('sante', const [], {'sante': '2026-10-20'}, '2026-10-22'), isEmpty);
    });

    test('aller-retour JSON', () {
      final p = parseRestPeriods([
        {'domainId': 'a', 'from': '2026-10-01', 'to': '2026-10-03'},
        {'domainId': 'b', 'from': '2026-10-05', 'to': '2026-10-01'},
        'n’importe quoi',
      ]);
      expect(p.length, 1);
      expect(p.single.toJson(), {'domainId': 'a', 'from': '2026-10-01', 'to': '2026-10-03'});
    });
  });

  group('séries gelées', () {
    final a = Activity(id: 'p', name: 'Pompes', domainId: 'sante', type: 'habit', habitFreq: HabitFreq.daily, habitTarget: 1, createdAt: DateTime(2026, 10, 1));
    List<HabitHit> hits(Iterable<int> days) => [for (final d in days) HabitHit(habitId: 'p', ts: DateTime(2026, 10, d, 9))];

    test('un jour gelé ne casse rien et ne compte pas', () {
      final s = routineSeries(a, hits([10, 11, 12, 16, 17]), DateTime(2026, 10, 17, 20), frozen: octDays([13, 14, 15]));
      expect(s.current, 5);
      expect(s.longest, 5);
      final sans = routineSeries(a, hits([10, 11, 12, 16, 17]), DateTime(2026, 10, 17, 20));
      expect(sans.current, 2);
    });

    test('une routine faite pendant la veille compte', () {
      final s = routineSeries(a, hits([10, 11, 13, 16]), DateTime(2026, 10, 16, 20), frozen: octDays([12, 13, 14, 15]));
      expect(s.current, 4);
    });

    test('la bande des 30 jours montre les jours gelés', () {
      final b = routineBadge(a, hits([10, 11, 16]), DateTime(2026, 10, 16, 20), frozen: octDays([12, 13, 14, 15]));
      expect(b.track!.cells.where((c) => c == TrackCell.frozen).length, 4);
      expect(b.value, 3);
    });

    test('hier gelé : rien de perdu', () {
      final l = lostYesterday(
        routines: const [('p', 'Pompes')],
        reached: {'p': octDays([25, 26, 27])},
        ledger: EmberLedger.empty,
        todayYmd: '2026-10-29',
        frozen: {'p': octDays([28])},
      );
      expect(l, isEmpty);
    });
  });

  group('record', () {
    test('lignes', () {
      expect(recordLine(16, 21), 'Encore 5 j pour égaler ton record (21 j)');
      expect(recordLine(21, 21), 'Record en cours · 21 j');
      expect(recordLine(0, 21), isNull);
      expect(recordLine(2, 2), isNull);
    });
  });

  group('reprise', () {
    test('2 jours manqués puis 3 tenus = une reprise', () {
      final h = reprisesOf(octDays([1, 2, 3, 6, 7, 8]), const {}, '2026-10-10');
      expect(h.events.single.ymd, '2026-10-08');
      expect(h.events.single.gap, 2);
      expect(h.now, isNull);
    });

    test('un seul jour manqué relève des braises', () {
      final h = reprisesOf(octDays([1, 2, 4, 5, 6]), const {}, '2026-10-06');
      expect(h.events, isEmpty);
      expect(h.now, isNull);
    });

    test('les jours gelés ne comptent pas comme manqués', () {
      final h = reprisesOf(octDays([1, 2, 6, 7, 8]), octDays([3, 4, 5]), '2026-10-08');
      expect(h.events, isEmpty);
    });

    test('reprise possible, en cours, ce soir, faite aujourd’hui', () {
      final possible = reprisesOf(octDays([1, 2]), const {}, '2026-10-05').now!;
      expect(possible.held, 0);
      expect(possible.gap, 2);
      final going = reprisesOf(octDays([1, 2, 6]), const {}, '2026-10-07').now!;
      expect(going.held, 1);
      expect(going.tonight, isFalse);
      final tonight = reprisesOf(octDays([1, 2, 6, 7]), const {}, '2026-10-08').now!;
      expect(tonight.tonight, isTrue);
      expect(tonight.afterToday, 3);
      final done = reprisesOf(octDays([1, 2, 6, 7, 8]), const {}, '2026-10-08');
      expect(done.now!.completedToday, isTrue);
      expect(done.events.length, 1);
    });

    test('une seule reprise par coupure', () {
      final h = reprisesOf(octDays([1, 4, 5, 6, 7, 8, 9]), const {}, '2026-10-12');
      expect(h.events.length, 1);
    });

    test('le badge compte les reprises de toutes les routines', () {
      final acts = [
        Activity(id: 'p', name: 'Pompes', domainId: 'sante', type: 'habit', habitFreq: HabitFreq.daily, habitTarget: 1, createdAt: DateTime(2026, 9, 1)),
        Activity(id: 'l', name: 'Lecture', domainId: 'perso', type: 'habit', habitFreq: HabitFreq.daily, habitTarget: 1, createdAt: DateTime(2026, 9, 1)),
      ];
      final hits = [
        for (final d in [1, 2, 5, 6]) HabitHit(habitId: 'p', ts: DateTime(2026, 10, d, 9)),
        for (final d in [1, 5, 6]) HabitHit(habitId: 'l', ts: DateTime(2026, 10, d, 9)),
      ];
      final deck = computeBadges(
        activities: acts,
        habitHits: hits,
        schedules: const [],
        projects: const [],
        objectives: const [],
        sessions: const [],
        now: DateTime(2026, 10, 7, 20),
      );
      final b = deck.byId('reprise')!;
      expect(b.value, 0);
      expect(deck.reprises['p']!.tonight, isTrue);
      expect(deck.reprises['l']!.held, 2);
      final later = computeBadges(
        activities: acts,
        habitHits: [...hits, HabitHit(habitId: 'p', ts: DateTime(2026, 10, 7, 9)), HabitHit(habitId: 'l', ts: DateTime(2026, 10, 7, 9))],
        schedules: const [],
        projects: const [],
        objectives: const [],
        sessions: const [],
        now: DateTime(2026, 10, 9, 20),
      );
      expect(later.byId('reprise')!.value, 2);
      expect(later.byId('reprise')!.level, 1);
    });
  });
}
