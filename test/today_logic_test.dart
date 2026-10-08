import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/today_logic.dart';

ScheduleBlock _b(String id, String start, int dur,
        {String status = 'pending', String category = 'project'}) =>
    ScheduleBlock(
        id: id,
        startTime: start,
        durationMin: dur,
        title: id,
        status: status,
        category: category);

void main() {
  final blocks = [
    _b('a', '09:00', 60, status: 'done'),
    _b('b', '10:30', 90),
    _b('c', '14:00', 30),
    _b('d', '15:00', 45, status: 'skipped'),
  ];

  test('blockStartMin : HH:mm → minutes, format invalide → 0', () {
    expect(blockStartMin(_b('x', '10:30', 1)), 630);
    expect(blockStartMin(_b('x', 'oops', 1)), 0);
    expect(blockEndMin(_b('x', '23:30', 60)), 24 * 60 + 30);
  });

  group('focusBlock', () {
    test('créneau courant en priorité', () {
      final f = focusBlock(blocks, 11 * 60)!;
      expect(f.block.id, 'b');
      expect(f.current, isTrue);
    });
    test('sinon le prochain à venir, même si désordonné', () {
      final f = focusBlock([blocks[2], blocks[1]], 10 * 60)!;
      expect(f.block.id, 'b');
      expect(f.current, isFalse);
    });
    test('les blocs faits ou sautés ne comptent pas ; plus rien → null', () {
      expect(focusBlock(blocks, 9 * 60 + 30)!.block.id, 'b');
      expect(focusBlock(blocks, 15 * 60 + 10), isNull);
    });
  });

  test('nextBlockAfter : premier pending qui commence à la fin ou après', () {
    expect(nextBlockAfter(blocks, blocks[1])!.id, 'c');
    expect(nextBlockAfter(blocks, blocks[2]), isNull);
  });

  test('remainingPlannedMin : pending seulement, tronqué à maintenant', () {
    expect(remainingPlannedMin(blocks, 8 * 60), 120);
    expect(remainingPlannedMin(blocks, 11 * 60), 60 + 30);
    expect(remainingPlannedMin(blocks, 16 * 60), 0);
  });

  test('timelineHours : heures pleines, englobe maintenant, plafond 24 h', () {
    expect(timelineHours(blocks, 12 * 60), (startH: 9, endH: 16));
    expect(timelineHours(blocks, 7 * 60 + 15), (startH: 7, endH: 16));
    expect(timelineHours(blocks, 20 * 60), (startH: 9, endH: 21));
    expect(timelineHours([_b('n', '23:30', 90)], 23 * 60 + 50),
        (startH: 23, endH: 24));
    expect(timelineHours([], 10 * 60), (startH: 10, endH: 11));
  });

  test('timelinePxPerMin : remplit la hauteur, jamais sous 0,75', () {
    expect(timelinePxPerMin(600, 300), 2.0);
    expect(timelinePxPerMin(100, 600), 0.75);
    expect(timelinePxPerMin(100, 0), 0.75);
  });

  test('minutesByCategory : ordre fixe, catégories vides omises', () {
    final r = minutesByCategory([
      _b('1', '09:00', 30, category: 'break'),
      _b('2', '10:00', 60),
      _b('3', '11:00', 15, category: 'break'),
    ]);
    expect(r, [(category: 'project', min: 60), (category: 'break', min: 45)]);
  });

  test('foldEarlierBlocks : blocs finis repliés sauf les 2 derniers ; rien si peu de passé', () {
    ScheduleBlock b(String id, String start, int dur) =>
        ScheduleBlock(id: id, startTime: start, durationMin: dur, title: id);
    final blocks = [
      b('a', '08:00', 60),
      b('b', '09:00', 60),
      b('c', '10:00', 60),
      b('cur', '13:00', 120),
      b('d', '16:00', 60),
    ];
    final r = foldEarlierBlocks(blocks, 14 * 60);
    expect(r.folded.map((x) => x.id).toList(), ['a']);
    expect(r.shown.map((x) => x.id).toList(), ['b', 'c', 'cur', 'd']);
    final early = foldEarlierBlocks(blocks, 9 * 60 + 30);
    expect(early.folded, isEmpty);
    expect(early.shown.length, 5);
  });

  test('asideBlocks / asideLabel : sautés et déplacés hors de la vue, compteur de pied', () {
    ScheduleBlock b(String id, String status, {String? reason, Map<String, dynamic>? movedTo}) =>
        ScheduleBlock(id: id, startTime: '10:00', durationMin: 30, title: id, status: status,
            skipReason: reason, movedTo: movedTo);
    final a = asideBlocks([
      b('ok', 'pending'),
      b('fait', 'done'),
      b('rep', 'skipped', reason: 'reporte'),
      b('mv', 'skipped', movedTo: {'date': '2026-10-09', 'startTime': '09:00'}),
      b('sk', 'skipped', reason: 'energie'),
      b('del', 'deleted'),
    ]);
    expect(a.moved.map((x) => x.id).toList(), ['rep', 'mv']);
    expect(a.skipped.map((x) => x.id).toList(), ['sk']);
    expect(asideLabel(a), '2 blocs déplacés · 1 sauté');
    expect(asideLabel(asideBlocks([b('sk', 'skipped')])), '1 bloc sauté');
    expect(asideLabel(asideBlocks([b('ok', 'pending')])), isNull);
    expect(asideDetail(a.moved[1]), '→ 2026-10-09 09:00');
    expect(asideDetail(a.skipped[0]), 'sauté · energie');
  });
}
