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

  test('bloc annulé « pas disponible » : compté à part, rétablissable, jamais un miroir', () {
    ScheduleBlock b(String id, String status, {String? reason, String? gcal}) => ScheduleBlock(
        id: id, startTime: '10:00', durationMin: 30, title: id, status: status,
        skipReason: reason, gcalEventId: gcal);
    final a = asideBlocks([
      b('an', 'skipped', reason: kSkipUnavailable),
      b('rep', 'skipped', reason: 'reporte'),
      b('sk', 'skipped'),
    ]);
    expect(a.cancelled.map((x) => x.id).toList(), ['an']);
    expect(a.skipped.map((x) => x.id).toList(), ['sk']);
    expect(asideLabel(a), '1 bloc déplacé · 1 annulé · 1 sauté');
    expect(asideLabel(asideBlocks([b('an', 'skipped', reason: kSkipUnavailable)])), '1 bloc annulé');
    expect(asideDetail(a.cancelled[0]), 'annulé · pas disponible');
    expect(canCancelBlock(b('p', 'pending')), isTrue);
    expect(canCancelBlock(b('d', 'done')), isFalse);
    expect(canCancelBlock(b('m', 'pending', gcal: 'evt')), isFalse);
  });

  test('nowLineBlock : bloc en cours, le dernier commencé si chevauchement, null dans un trou', () {
    ScheduleBlock b(String id, String start, int dur, {String status = 'pending'}) =>
        ScheduleBlock(id: id, startTime: start, durationMin: dur, title: id, status: status);
    final blocks = [b('a', '09:00', 120), b('b', '10:00', 30), b('done', '10:00', 60, status: 'done')];
    expect(nowLineBlock(blocks, 9 * 60 + 30)?.id, 'a');
    expect(nowLineBlock(blocks, 10 * 60 + 10)?.id, 'b', reason: 'chevauchement : le dernier commencé');
    expect(nowLineBlock(blocks, 10 * 60 + 45)?.id, 'a');
    expect(nowLineBlock(blocks, 11 * 60 + 30), isNull, reason: 'trou : trait entre les blocs');
  });

  test('blocksToCarry / showCarryCard : passés non faits, hors miroirs, le soir et à partir de 2', () {
    ScheduleBlock b(String id, String start, int dur, {String status = 'pending', String? gcal}) =>
        ScheduleBlock(id: id, startTime: start, durationMin: dur, title: id, status: status, gcalEventId: gcal);
    final blocks = [
      b('matin', '06:00', 60),
      b('fait', '08:00', 60, status: 'done'),
      b('agenda', '09:00', 60, gcal: 'evt'),
      b('aprem', '17:20', 30),
      b('soir', '21:00', 60),
    ];
    final carry = blocksToCarry(blocks, 21 * 60 + 10);
    expect(carry.map((x) => x.id).toList(), ['matin', 'aprem']);
    expect(showCarryCard(carry, 21 * 60 + 10), isTrue);
    expect(showCarryCard(carry, 17 * 60), isFalse);
    expect(showCarryCard(carry.take(1).toList(), 21 * 60), isFalse);
  });

  test('applyMirrorMemory : miroir libre relié par son titre, jamais un bloc déjà relié', () {
    ScheduleBlock m(String id, String title, {String? activityId, String? projectId, String? gcal = 'evt'}) =>
        ScheduleBlock(id: id, startTime: '19:00', durationMin: 120, title: title,
            gcalEventId: gcal, activityId: activityId, projectId: projectId);
    final blocks = [
      m('gds', '  GDS '),
      m('seance', 'GDS', projectId: 'p'),
      m('deja', 'GDS', activityId: 'autre'),
      m('perso', 'GDS', gcal: null),
      m('inconnu', 'Dentiste'),
    ];
    expect(mirrorKey('  Cléa   Numérique - LAM4 '), 'cléa numérique - lam4');
    expect(applyMirrorMemory(blocks, {'gds': 'act-gds'}), 1);
    expect(blocks[0].activityId, 'act-gds');
    expect(blocks[1].activityId, isNull);
    expect(blocks[2].activityId, 'autre');
    expect(blocks[3].activityId, isNull);
    expect(blocks[4].activityId, isNull);
  });

  test('settleBlocksByWork : le bloc suit l\'action visée, sinon sa tâche', () {
    final blocks = <Map<String, dynamic>>[
      {'id': 'a', 'status': 'pending', 'taskId': 't1', 'actionId': 'x'},
      {'id': 'b', 'status': 'pending', 'taskId': 't2'},
      {'id': 'c', 'status': 'pending', 'actionId': 'x', 'noAutoWin': true},
      {'id': 'd', 'status': 'pending', 'taskId': 't1', 'actionId': 'y'},
      {'id': 'e', 'status': 'skipped', 'actionId': 'x'},
    ];
    expect(settleBlocksByWork(blocks,
        actions: {'x': true, 'y': false}, tasks: {'t1': false, 't2': true}, nowIso: 'N'), isTrue);
    expect(blocks.map((b) => b['status']).toList(), ['done', 'done', 'pending', 'pending', 'skipped']);
    expect(blocks[0]['doneBy'], 'action');
    // Rouvrir l'action décoche le bloc coché par elle, pas un bloc coché à la main.
    blocks.add({'id': 'f', 'status': 'done', 'actionId': 'x'});
    expect(settleBlocksByWork(blocks, actions: {'x': false}, nowIso: 'N'), isTrue);
    expect(blocks[0]['status'], 'pending');
    expect(blocks[0].containsKey('doneBy'), isFalse);
    expect(blocks.last['status'], 'done');
    expect(settleBlocksByWork(blocks, actions: {'x': false}, nowIso: 'N'), isFalse);
  });

  test('overlapColumns : chevauchements côte à côte, groupes indépendants', () {
    ScheduleBlock b(String id, String start, int dur) =>
        ScheduleBlock(id: id, startTime: start, durationMin: dur, title: id);
    final c = overlapColumns([
      b('a', '09:00', 60),
      b('b', '09:30', 60),
      b('c', '10:00', 30), // a fini à 10:00 : reprend la colonne 0
      b('d', '12:00', 30), // seul
    ]);
    expect(c['a'], (col: 0, cols: 2));
    expect(c['b'], (col: 1, cols: 2));
    expect(c['c'], (col: 0, cols: 2));
    expect(c['d'], (col: 0, cols: 1));
  });

  test('freeBlockToClaim / claimFreeBlock : bloc libre en cours, jamais une pause, un bloc lié, ni plus de 3 h', () {
    ScheduleBlock blk(String id, String start, int dur, {String cat = 'personal', String? act, String? proj, String kind = 'normal', String status = 'pending'}) =>
        ScheduleBlock(id: id, startTime: start, durationMin: dur, title: id, category: cat, activityId: act, projectId: proj, kind: kind, status: status);
    final now = 10 * 60 + 15; // 10:15
    expect(freeBlockToClaim([blk('rdv', '10:00', 60)], now)?.id, 'rdv');
    expect(freeBlockToClaim([blk('futur', '10:30', 60)], now), isNull); // pas encore commencé
    expect(freeBlockToClaim([blk('pause', '10:00', 30, cat: 'break')], now), isNull);
    expect(freeBlockToClaim([blk('lie', '10:00', 60, act: 'a')], now), isNull);
    expect(freeBlockToClaim([blk('projet', '10:00', 60, proj: 'p')], now), isNull);
    expect(freeBlockToClaim([blk('prep', '10:00', 60, kind: 'prep')], now), isNull);
    expect(freeBlockToClaim([blk('fait', '10:00', 60, status: 'done')], now), isNull);
    expect(freeBlockToClaim([blk('sommeil', '06:00', 420)], now), isNull); // > 3 h
    final b = blk('rdv', '10:00', 60);
    final s = Session(activityId: 'contenu', startAt: DateTime(2026, 10, 30, 10, 15), taskId: 't1', actionId: 'a1');
    claimFreeBlock(b, s);
    expect(b.activityId, 'contenu');
    expect(b.actionId, isNull); // action de tâche : reste sur la session
    expect((s.taskId, s.actionId), ('t1', 'a1'));
    final own = Session(activityId: 'contenu', startAt: DateTime(2026, 10, 30, 10, 15), actionId: 'own1');
    final b2 = blk('perso', '10:00', 60);
    claimFreeBlock(b2, own);
    expect(b2.actionId, 'own1');
  });
}
