import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/block_stack.dart';

ScheduleBlock _b({String? timeBlock, String? activityId, String? projectId, String? taskId, String? actionId}) => ScheduleBlock(
    startTime: '06:00',
    durationMin: 120,
    title: 'Deep work',
    timeBlock: timeBlock,
    activityId: activityId,
    projectId: projectId,
    taskId: taskId,
    actionId: actionId);

void main() {
  group('stackLayers', () {
    test('une activité sur un Deep work : les deux restent', () {
      final r = stackLayers(const BlockLayers(timeBlock: 'deep'), const BlockLayers(activityId: 'a1'));
      expect(r, const BlockLayers(timeBlock: 'deep', activityId: 'a1'));
    });

    test('une tâche par-dessus : mode et activité gardés, la cible vient entière', () {
      final base = const BlockLayers(timeBlock: 'deep', activityId: 'a1', projectId: 'p0', taskId: 't0', actionId: 'x0');
      final r = stackLayers(base, const BlockLayers(projectId: 'p1', taskId: 't1'));
      expect(r, const BlockLayers(timeBlock: 'deep', activityId: 'a1', projectId: 'p1', taskId: 't1'));
    });

    test('changer de mode ne touche ni l’activité ni la cible', () {
      final base = const BlockLayers(timeBlock: 'deep', activityId: 'a1', projectId: 'p1', taskId: 't1', actionId: 'x1');
      final r = stackLayers(base, const BlockLayers(timeBlock: 'small'));
      expect(r, const BlockLayers(timeBlock: 'small', activityId: 'a1', projectId: 'p1', taskId: 't1', actionId: 'x1'));
    });

    test('changer d’activité lâche son action propre, pas l’action d’un projet', () {
      expect(stackLayers(const BlockLayers(activityId: 'a1', actionId: 'own'), const BlockLayers(activityId: 'a2')),
          const BlockLayers(activityId: 'a2'));
      expect(
          stackLayers(const BlockLayers(activityId: 'a1', projectId: 'p', taskId: 't', actionId: 'x'),
              const BlockLayers(activityId: 'a2')),
          const BlockLayers(activityId: 'a2', projectId: 'p', taskId: 't', actionId: 'x'));
    });
  });

  group('retirer une couche', () {
    const full = BlockLayers(timeBlock: 'deep', activityId: 'a1', projectId: 'p1', taskId: 't1', actionId: 'x1');
    test('mode, activité, cible', () {
      expect(full.withoutMode(), const BlockLayers(activityId: 'a1', projectId: 'p1', taskId: 't1', actionId: 'x1'));
      expect(full.withoutActivity(), const BlockLayers(timeBlock: 'deep', projectId: 'p1', taskId: 't1', actionId: 'x1'));
      expect(full.withoutTarget(), const BlockLayers(timeBlock: 'deep', activityId: 'a1'));
      expect(const BlockLayers(activityId: 'a1', actionId: 'own').withoutActivity(), const BlockLayers());
    });

    test('applyTo écrit toutes les couches, vides comprises', () {
      final b = _b(timeBlock: 'deep', activityId: 'a1', projectId: 'p1', taskId: 't1', actionId: 'x1');
      const BlockLayers(activityId: 'a2').applyTo(b);
      expect(BlockLayers.of(b), const BlockLayers(activityId: 'a2'));
    });
  });

  group('stackRefusal', () {
    test('un bloc à faire reçoit une couche nouvelle', () {
      expect(stackRefusal(_b(timeBlock: 'deep'), const BlockLayers(activityId: 'a1')), isNull);
    });

    test('rien de neuf, bloc fait, pause : refusé', () {
      expect(stackRefusal(_b(timeBlock: 'deep'), const BlockLayers(timeBlock: 'deep')), isNotNull);
      expect(stackRefusal(_b()..status = 'done', const BlockLayers(activityId: 'a1')), isNotNull);
      expect(stackRefusal(_b()..category = 'break', const BlockLayers(activityId: 'a1')), isNotNull);
      expect(stackRefusal(_b(), const BlockLayers()), isNotNull);
    });

    test('un rendez-vous d’agenda ne reçoit qu’une activité', () {
      final mirror = _b()..gcalEventId = 'g1';
      expect(stackRefusal(mirror, const BlockLayers(activityId: 'a1')), isNull);
      expect(stackRefusal(mirror, const BlockLayers(timeBlock: 'deep')), isNotNull);
      expect(stackRefusal(mirror, const BlockLayers(projectId: 'p1', taskId: 't1')), isNotNull);
    });
  });

  group('titres', () {
    test('layersTitle : le mode puis la cible la plus précise', () {
      expect(layersTitle(timeBlock: 'deep'), 'Deep work');
      expect(layersTitle(timeBlock: 'deep', activity: 'Interventions'), 'Deep work · Interventions');
      expect(layersTitle(timeBlock: 'small', activity: 'Interventions', project: 'Maths 6e', task: 'Préparer la séance'),
          'Petites choses · Préparer la séance');
      expect(layersTitle(activity: 'Interventions', project: 'Maths 6e'), 'Maths 6e');
      expect(layersTitle(), '');
    });

    test('retitled : un titre de l’app suit, un titre à la main reste', () {
      expect(retitled('Deep work', 'Deep work', 'Deep work · Interventions'), 'Deep work · Interventions');
      expect(retitled('Mon créneau du matin', 'Deep work', 'Deep work · Interventions'), 'Mon créneau du matin');
      expect(retitled('', 'Deep work', 'Interventions'), 'Interventions');
      expect(retitled('Deep work', 'Deep work', ''), 'Deep work');
    });

    test('layersLine : sans ce que le titre dit déjà', () {
      expect(
          layersLine(
              timeBlock: 'deep',
              activity: 'Interventions',
              project: 'Maths 6e',
              task: 'Préparer la séance',
              title: 'Deep work · Préparer la séance'),
          'Interventions · Maths 6e');
      expect(layersLine(activity: 'Interventions', title: 'Interventions'), '');
      expect(layersLine(timeBlock: 'small', project: 'Maths 6e', task: 'Corriger', title: 'Créneau'),
          'Petites choses · Maths 6e › Corriger');
    });
  });
}
