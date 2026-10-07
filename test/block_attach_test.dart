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

  group('attachSessionToBlock — le chrono fait foi', () {
    test('bloc de tâche : la session garde son activité, porte la tâche et l\'action du bloc', () {
      final s = Session(activityId: 'creation-contenu', startAt: t0, actionId: 'autre');
      final b = blk('14:00', projectId: 'p', taskId: 't', actionId: 'a', activityId: 'prepa');
      expect(attachSessionToBlock(s, b), AttachResult.session);
      expect(s.taskId, 't');
      expect(s.actionId, 'a');
      expect(s.activityId, 'creation-contenu');
      expect(b.activityId, 'prepa');
      expect(sessionMatchesBlock(s, b), isTrue);
    });

    test('bloc projet sans tâche, activité liée différente : le BLOC prend l\'activité du chrono', () {
      final s = Session(activityId: 'creation-contenu', startAt: t0, taskId: 'vieux');
      final b = blk('14:00', projectId: 'p');
      final p = Project(
          id: 'p', title: 'P', startDate: DateTime(2026, 10, 1), createdBy: 'test', linkedActivityId: 'cours');
      expect(attachSessionToBlock(s, b, project: p), AttachResult.sessionAndBlock);
      expect(s.activityId, 'creation-contenu');
      expect(s.taskId, isNull);
      expect(b.activityId, 'creation-contenu');
      expect(b.projectId, 'p');
      expect(sessionMatchesBlock(s, b), isTrue);
    });

    test('bloc projet sans tâche, même activité liée : session seule', () {
      final s = Session(activityId: 'cours', startAt: t0);
      final b = blk('14:00', projectId: 'p');
      final p = Project(
          id: 'p', title: 'P', startDate: DateTime(2026, 10, 1), createdBy: 'test', linkedActivityId: 'cours');
      expect(attachSessionToBlock(s, b, project: p), AttachResult.session);
      expect(b.activityId, isNull);
      expect(sessionMatchesBlock(s, b, projectLinkedActivityId: p.linkedActivityId), isTrue);
    });

    test('bloc d\'activité-temps différente : le bloc bascule sur le chrono (et son action propre)', () {
      final prepa = Activity(id: 'prepa', name: 'Préparation', type: 'time', domainId: 'd');
      final s = Session(activityId: 'creation-contenu', startAt: t0, actionId: 'propre');
      final b = blk('14:00', activityId: 'prepa', actionId: 'action-prepa');
      expect(attachSessionToBlock(s, b, blockActivity: prepa), AttachResult.sessionAndBlock);
      expect(s.activityId, 'creation-contenu');
      expect(s.actionId, 'propre');
      expect(b.activityId, 'creation-contenu');
      expect(b.actionId, 'propre');
      expect(sessionMatchesBlock(s, b), isTrue);
    });

    test('bloc de la même activité-temps : la session prend l\'action du bloc', () {
      final cours = Activity(id: 'cours', name: 'Cours', type: 'time', domainId: 'd');
      final s = Session(activityId: 'cours', startAt: t0, actionId: 'autre');
      final b = blk('14:00', activityId: 'cours', actionId: 'a');
      expect(attachSessionToBlock(s, b, blockActivity: cours), AttachResult.session);
      expect(s.actionId, 'a');
      expect(b.activityId, 'cours');
    });

    test('routine : exception, la session bascule sur l\'activité liée de la routine', () {
      final routine = Activity(
          id: 'r', name: 'Lecture', type: 'habit', domainId: 'd', linkedActivityId: 'lire');
      final s = Session(activityId: 'creation-contenu', startAt: t0);
      final rb = blk('14:00', activityId: 'r');
      expect(attachSessionToBlock(s, rb, blockActivity: routine), AttachResult.session);
      expect(s.activityId, 'lire');
      expect(rb.activityId, 'r');
      expect(sessionMatchesBlock(s, rb, activityLinkedActivityId: routine.linkedActivityId), isTrue);
    });

    test('bloc libre (agenda Google) : le bloc prend l\'activité du chrono', () {
      final s = Session(activityId: 'enseignement', startAt: t0, actionId: 'propre');
      final gcal = blk('14:00');
      expect(attachSessionToBlock(s, gcal), AttachResult.sessionAndBlock);
      expect(gcal.activityId, 'enseignement');
      expect(gcal.actionId, 'propre');
      expect(sessionMatchesBlock(s, gcal), isTrue);
      // Session sur une tâche : la tâche tombe (le bloc n'en a pas), l'action aussi.
      final s2 = Session(activityId: 'dev', startAt: t0, taskId: 't', actionId: 'a');
      final b2 = blk('15:00');
      expect(attachSessionToBlock(s2, b2), AttachResult.sessionAndBlock);
      expect(s2.taskId, isNull);
      expect(s2.actionId, isNull);
      expect(b2.actionId, isNull);
    });

    test('routine sans activité liée : non rattachable, session intacte', () {
      final s = Session(activityId: 'productivite', startAt: t0, taskId: 't');
      final routine = Activity(id: 'r', name: 'R', type: 'habit', domainId: 'd');
      expect(canAttachSessionToBlock(blk('14:00', activityId: 'r'), blockActivity: routine), isFalse);
      expect(attachSessionToBlock(s, blk('14:00', activityId: 'r'), blockActivity: routine),
          AttachResult.none);
      expect(s.taskId, 't');
      expect(s.activityId, 'productivite');
      expect(canAttachSessionToBlock(blk('14:00')), isTrue);
    });
  });
}
