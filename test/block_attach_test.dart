import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/today_logic.dart';

void main() {
  final t0 = DateTime(2026, 10, 2, 13, 55);
  ScheduleBlock blk(String start,
          {String? projectId, String? taskId, String? actionId, String? activityId,
          String status = 'pending'}) =>
      ScheduleBlock(
          startTime: start, durationMin: 60, title: 'b',
          projectId: projectId, taskId: taskId, actionId: actionId,
          activityId: activityId, status: status);

  group('blockToAttachAt', () {
    test('bloc en cours prioritaire', () {
      final cur = blk('13:00');
      final soon = blk('14:00');
      final r = blockToAttachAt([soon, cur], 13 * 60 + 55);
      expect(r?.block, same(cur));
      expect(r?.current, isTrue);
    });

    test('13 h 55 → le cours de 14 h est proposé (pas encore en cours)', () {
      final soon = blk('14:00');
      final r = blockToAttachAt([blk('16:00'), soon], 13 * 60 + 55);
      expect(r?.block, same(soon));
      expect(r?.current, isFalse);
    });

    test('au-delà de la fenêtre, ou bloc déjà fait : rien', () {
      expect(blockToAttachAt([blk('14:20')], 13 * 60 + 55), isNull);
      expect(blockToAttachAt([blk('14:00', status: 'done')], 13 * 60 + 55), isNull);
      expect(blockToAttachAt([blk('14:00')], 13 * 60 + 55, lookaheadMin: 3), isNull);
    });
  });

  group('attachSessionToBlock', () {
    test('bloc de tâche : la session porte la tâche et l\'action du bloc, et correspond', () {
      final s = Session(activityId: 'productivite', startAt: t0, actionId: 'autre');
      final b = blk('14:00', projectId: 'p', taskId: 't', actionId: 'a');
      expect(attachSessionToBlock(s, b), isTrue);
      expect(s.taskId, 't');
      expect(s.actionId, 'a');
      expect(s.activityId, 'productivite');
      expect(sessionMatchesBlock(s, b), isTrue);
    });

    test('bloc projet sans tâche : bascule sur l\'activité liée du projet', () {
      final s = Session(activityId: 'productivite', startAt: t0, taskId: 'vieux');
      final b = blk('14:00', projectId: 'p');
      final p = Project(
          id: 'p', title: 'P', startDate: DateTime(2026, 10, 1), createdBy: 'test', linkedActivityId: 'cours');
      expect(attachSessionToBlock(s, b, project: p), isTrue);
      expect(s.activityId, 'cours');
      expect(s.taskId, isNull);
      expect(sessionMatchesBlock(s, b, projectLinkedActivityId: p.linkedActivityId), isTrue);
    });

    test('bloc d\'activité-temps : bascule dessus ; routine : sur son activité liée', () {
      final time = Activity(id: 'cours', name: 'Cours', type: 'time', domainId: 'd');
      final s = Session(activityId: 'productivite', startAt: t0);
      expect(attachSessionToBlock(s, blk('14:00', activityId: 'cours'), blockActivity: time), isTrue);
      expect(s.activityId, 'cours');

      final routine = Activity(
          id: 'r', name: 'Lecture', type: 'habit', domainId: 'd', linkedActivityId: 'lire');
      final s2 = Session(activityId: 'productivite', startAt: t0);
      final rb = blk('14:00', activityId: 'r');
      expect(attachSessionToBlock(s2, rb, blockActivity: routine), isTrue);
      expect(s2.activityId, 'lire');
      expect(sessionMatchesBlock(s2, rb, activityLinkedActivityId: routine.linkedActivityId), isTrue);
    });

    test('bloc libre (agenda Google) : c\'est le BLOC qui prend l\'activité du chrono', () {
      final s = Session(activityId: 'enseignement', startAt: t0, actionId: 'propre');
      final gcal = blk('14:00');
      expect(attachTargetFor(gcal), AttachTarget.block);
      expect(attachBlockToSession(gcal, s), isTrue);
      expect(gcal.activityId, 'enseignement');
      expect(gcal.actionId, 'propre');
      expect(sessionMatchesBlock(s, gcal), isTrue);
      // Session sur une tâche : l'action (de tâche) n'est pas copiée sur le bloc.
      final s2 = Session(activityId: 'dev', startAt: t0, taskId: 't', actionId: 'a');
      final b2 = blk('15:00');
      expect(attachBlockToSession(b2, s2), isTrue);
      expect(b2.actionId, isNull);
    });

    test('cible du rattachement : session si le bloc a une source, bloc si libre, rien pour une routine orpheline', () {
      final time = Activity(id: 'cours', name: 'Cours', type: 'time', domainId: 'd');
      expect(attachTargetFor(blk('14:00', projectId: 'p', taskId: 't')), AttachTarget.session);
      expect(attachTargetFor(blk('14:00', activityId: 'cours'), blockActivity: time), AttachTarget.session);
      final p = Project(
          id: 'p', title: 'P', startDate: DateTime(2026, 10, 1), createdBy: 'test');
      expect(attachTargetFor(blk('14:00', projectId: 'p'), project: p), AttachTarget.block);
      final routine = Activity(id: 'r', name: 'R', type: 'habit', domainId: 'd');
      expect(attachTargetFor(blk('14:00', activityId: 'r'), blockActivity: routine), isNull);
      expect(attachBlockToSession(blk('14:00', activityId: 'r'), Session(activityId: 'x', startAt: t0)), isFalse);
    });

    test('bloc libre ou routine sans activité liée : non rattachable, session intacte', () {
      final s = Session(activityId: 'productivite', startAt: t0, taskId: 't');
      expect(canAttachSessionToBlock(blk('14:00')), isFalse);
      expect(attachSessionToBlock(s, blk('14:00')), isFalse);
      final routine = Activity(id: 'r', name: 'R', type: 'habit', domainId: 'd');
      expect(attachSessionToBlock(s, blk('14:00', activityId: 'r'), blockActivity: routine), isFalse);
      expect(s.taskId, 't');
      expect(s.activityId, 'productivite');
    });
  });
}
