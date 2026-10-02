import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/today_logic.dart';

void main() {
  final t0 = DateTime(2026, 10, 2, 13, 40);
  ScheduleBlock blk(String id, String start, {String? activityId}) => ScheduleBlock(
      id: id, startTime: start, durationMin: 60, title: id, activityId: activityId);
  bool byActivity(Session s, ScheduleBlock b) => s.activityId == b.activityId;

  test('état initial jamais signalé ; le bloc qui devient courant l\'est, une fois', () {
    final w = BlockTransitionWatcher();
    final cours = blk('cours', '14:00', activityId: 'cours');
    final open = Session(activityId: 'productivite', startAt: t0);
    // 13:40 : programme chargé, rien en cours → amorçage.
    expect(w.tick(blocks: [cours], nowMin: 13 * 60 + 40, open: open, matches: byActivity), isNull);
    // 14:00 : le cours devient courant, le chrono est sur autre chose → signalé.
    expect(w.tick(blocks: [cours], nowMin: 14 * 60, open: open, matches: byActivity), same(cours));
    // 14:01 : même bloc → silence.
    expect(w.tick(blocks: [cours], nowMin: 14 * 60 + 1, open: open, matches: byActivity), isNull);
  });

  test('ouverture de l\'app pendant un bloc déjà en cours : pas de question', () {
    final w = BlockTransitionWatcher();
    final cours = blk('cours', '14:00', activityId: 'cours');
    final open = Session(activityId: 'productivite', startAt: t0);
    expect(w.tick(blocks: [cours], nowMin: 14 * 60 + 10, open: open, matches: byActivity), isNull);
    expect(w.tick(blocks: [cours], nowMin: 14 * 60 + 11, open: open, matches: byActivity), isNull);
  });

  test('programme vide au premier tick : on n\'amorce qu\'une fois les blocs arrivés', () {
    final w = BlockTransitionWatcher();
    final cours = blk('cours', '14:00', activityId: 'cours');
    final open = Session(activityId: 'productivite', startAt: t0);
    expect(w.tick(blocks: const [], nowMin: 14 * 60 + 5, open: open, matches: byActivity), isNull);
    // Le stream livre le programme : le bloc est déjà en cours → état initial.
    expect(w.tick(blocks: [cours], nowMin: 14 * 60 + 5, open: open, matches: byActivity), isNull);
  });

  test('chrono déjà sur la source du bloc, ou pas de chrono : silence', () {
    final w = BlockTransitionWatcher();
    final cours = blk('cours', '14:00', activityId: 'cours');
    final onIt = Session(activityId: 'cours', startAt: t0);
    w.tick(blocks: [cours], nowMin: 13 * 60 + 59, open: onIt, matches: byActivity);
    expect(w.tick(blocks: [cours], nowMin: 14 * 60, open: onIt, matches: byActivity), isNull);

    final w2 = BlockTransitionWatcher();
    w2.tick(blocks: [cours], nowMin: 13 * 60 + 59, open: null, matches: byActivity);
    expect(w2.tick(blocks: [cours], nowMin: 14 * 60, open: null, matches: byActivity), isNull);
  });

  test('déjà demandé au démarrage (anticipation) : pas de seconde question à l\'heure', () {
    final w = BlockTransitionWatcher();
    final cours = blk('cours', '14:00', activityId: 'cours');
    final open = Session(activityId: 'productivite', startAt: t0);
    w.tick(blocks: [cours], nowMin: 13 * 60 + 55, open: open, matches: byActivity);
    w.markAsked(open, cours);
    expect(w.tick(blocks: [cours], nowMin: 14 * 60, open: open, matches: byActivity), isNull);
    // Un AUTRE chrono lancé ensuite, toujours à côté → nouvelle question.
    final other = Session(activityId: 'mails', startAt: DateTime(2026, 10, 2, 14, 30));
    final suite = blk('suite', '15:00', activityId: 'cours');
    w.tick(blocks: [cours, suite], nowMin: 14 * 60 + 31, open: other, matches: byActivity);
    expect(w.tick(blocks: [cours, suite], nowMin: 15 * 60, open: other, matches: byActivity), same(suite));
  });
}
