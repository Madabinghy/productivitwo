import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/now_pick.dart';
import 'package:productivitwo_v1/utils/stakes.dart';

void main() {
  // 14:00 un vendredi, journée vécue à 5 h.
  final now = DateTime(2026, 11, 6, 14, 0);
  const nowMin = 14 * 60;

  ScheduleBlock blk(String id, String start, int dur, {String? gcal, String title = 'Bloc'}) =>
      ScheduleBlock(id: id, startTime: start, durationMin: dur, title: title, gcalEventId: gcal);

  Stake stake(String title, StakeGain g) =>
      Stake(StakeGesture(key: 'routine:$title', kind: StakeGestureKind.routine, title: title, costMin: 5), [g]);

  const series = StakeGain(kind: StakeGainKind.seriesTonight, label: 'série 12 j → se perd ce soir', losesTonight: true, weight: 30);
  const parole = StakeGain(kind: StakeGainKind.focus, label: 'Parole tenue · encore 2', weight: 24);
  const focus = StakeGain(kind: StakeGainKind.focus, label: 'visée aujourd’hui', weight: 8);

  test('un rendez-vous dans 15 min passe devant le chrono', () {
    final p = pickNow(blocks: [blk('c', '14:10', 60, gcal: 'g')], now: now, nowMin: nowMin, dayStartMin: 300, runningName: 'Contenu');
    expect(p.kind, NowPickKind.fixedSoon);
    expect(p.block!.id, 'c');
  });

  test('le chrono qui tourne passe avant le bloc en cours', () {
    final p = pickNow(blocks: [blk('a', '13:30', 90)], now: now, nowMin: nowMin, dayStartMin: 300, runningName: 'Contenu');
    expect(p.kind, NowPickKind.running);
    expect(p.why, contains('Contenu'));
  });

  test('bloc en cours, puis enjeux, puis prochain bloc', () {
    final board = StakeBoard(top: [stake('Lecture', focus), stake('Louanges', series), stake('Rapport', parole)]);
    expect(pickNow(blocks: [blk('a', '13:30', 90)], now: now, nowMin: nowMin, dayStartMin: 300, board: board).kind, NowPickKind.block);
    final p = pickNow(blocks: [blk('b', '16:00', 60)], now: now, nowMin: nowMin, dayStartMin: 300, board: board);
    expect(p.kind, NowPickKind.losing);
    expect(p.stake!.gesture.title, 'Louanges');
    expect(p.why, contains('libre jusqu’à 16:00'));
  });

  test('parole avant les visées, et un prochain bloc trop proche reprend la main', () {
    final board = StakeBoard(top: [stake('Lecture', focus), stake('Rapport', parole)]);
    expect(pickNow(blocks: const [], now: now, nowMin: nowMin, dayStartMin: 300, board: board).kind, NowPickKind.parole);
    expect(pickNow(blocks: [blk('b', '14:10', 60)], now: now, nowMin: nowMin, dayStartMin: 300, board: board).kind, NowPickKind.next);
  });

  test('rien de posé : le mode, sinon rien', () {
    expect(pickNow(blocks: const [], now: now, nowMin: nowMin, dayStartMin: 300).kind, NowPickKind.mode);
    expect(pickNow(blocks: const [], now: now, nowMin: nowMin, dayStartMin: 300, modeAvailable: false).kind, NowPickKind.none);
  });

  test('autre chose : les trois suivantes, sans la chose montrée', () {
    final board = StakeBoard(top: [stake('Lecture', focus), stake('Louanges', series), stake('Rapport', parole), stake('Vaisselle', series)]);
    final blocks = [blk('b', '16:00', 60)];
    final shown = pickNow(blocks: blocks, now: now, nowMin: nowMin, dayStartMin: 300, board: board);
    expect(shown.stake!.gesture.title, 'Louanges');
    final alts = nowAlternatives(shown, blocks: blocks, nowMin: nowMin, board: board);
    expect(alts.map((a) => a.stake?.gesture.title ?? a.block!.id), ['Vaisselle', 'Rapport', 'Lecture']);
    final few = nowAlternatives(shown, blocks: blocks, nowMin: nowMin, board: StakeBoard(top: [stake('Louanges', series)]));
    expect(few.single.kind, NowPickKind.next);
  });
}
