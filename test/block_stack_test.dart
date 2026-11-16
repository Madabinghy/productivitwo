import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/block_stack.dart';
import 'package:productivitwo_v1/utils/planning.dart' show timeBlockCategory, timeBlockDefaultMin, planOrTimeBlockOf, PlannedBlock, PlanWant, timeWantId;

ScheduleBlock _b({String? timeBlock, String? activityId, String? projectId, String? taskId, String? actionId}) => ScheduleBlock(
    startTime: '06:00',
    durationMin: 120,
    title: 'Deep work',
    timeBlock: timeBlock,
    activityId: activityId,
    projectId: projectId,
    taskId: taskId,
    actionId: actionId);

const _t1 = BlockTarget(projectId: 'p1', taskId: 't1', actionId: 'x1');
const _t2 = BlockTarget(projectId: 'p1', taskId: 't2');
const _t3 = BlockTarget(projectId: 'p2');

void main() {
  group('stackLayers', () {
    test('une activité sur un Deep work : les deux restent', () {
      final r = stackLayers(const BlockLayers(timeBlock: 'deep'), const BlockLayers(activityId: 'a1'));
      expect(r, const BlockLayers(timeBlock: 'deep', activityId: 'a1'));
    });

    test('une deuxième tâche S’AJOUTE : la première reste la principale', () {
      const base = BlockLayers(timeBlock: 'deep', activityId: 'a1', targets: [_t1]);
      final r = stackLayers(base, const BlockLayers(targets: [_t2]));
      expect(r, const BlockLayers(timeBlock: 'deep', activityId: 'a1', targets: [_t1, _t2]));
      expect(stackLayers(r, const BlockLayers(targets: [_t3])).targets, [_t1, _t2, _t3]);
    });

    test('une cible déjà portée n’est pas ajoutée deux fois', () {
      const base = BlockLayers(targets: [_t1, _t2]);
      // Même projet et même tâche, action de départ différente : c'est la même cible.
      final r = stackLayers(base, const BlockLayers(targets: [BlockTarget(projectId: 'p1', taskId: 't1', actionId: 'autre')]));
      expect(r, base);
    });

    test('jamais plus de kMaxBlockTargets cibles', () {
      var l = const BlockLayers();
      for (var i = 0; i < kMaxBlockTargets + 3; i++) {
        l = stackLayers(l, BlockLayers(targets: [BlockTarget(projectId: 'p', taskId: 't$i')]));
      }
      expect(l.targets, hasLength(kMaxBlockTargets));
    });

    test('changer de mode ne touche ni l’activité ni les cibles', () {
      const base = BlockLayers(timeBlock: 'deep', activityId: 'a1', targets: [_t1, _t2]);
      final r = stackLayers(base, const BlockLayers(timeBlock: 'small'));
      expect(r, const BlockLayers(timeBlock: 'small', activityId: 'a1', targets: [_t1, _t2]));
    });

    test('changer d’activité lâche son action propre, pas l’action d’un projet', () {
      expect(stackLayers(const BlockLayers(activityId: 'a1', ownActionId: 'own'), const BlockLayers(activityId: 'a2')),
          const BlockLayers(activityId: 'a2'));
      expect(stackLayers(const BlockLayers(activityId: 'a1', targets: [_t1]), const BlockLayers(activityId: 'a2')),
          const BlockLayers(activityId: 'a2', targets: [_t1]));
    });

    test('une cible posée sur un bloc d’activité prend la place de son action propre', () {
      final r = stackLayers(const BlockLayers(activityId: 'a1', ownActionId: 'own'), const BlockLayers(targets: [_t1]));
      expect(r, const BlockLayers(activityId: 'a1', targets: [_t1]));
    });
  });

  group('retirer ou changer une couche', () {
    const full = BlockLayers(timeBlock: 'deep', activityId: 'a1', targets: [_t1, _t2, _t3]);

    test('mode, activité', () {
      expect(full.withoutMode(), const BlockLayers(activityId: 'a1', targets: [_t1, _t2, _t3]));
      expect(full.withoutActivity(), const BlockLayers(timeBlock: 'deep', targets: [_t1, _t2, _t3]));
      expect(const BlockLayers(activityId: 'a1', ownActionId: 'own').withoutActivity(), const BlockLayers());
    });

    test('retirer la principale : la suivante prend sa place', () {
      expect(full.withoutTargetAt(0).targets, [_t2, _t3]);
      expect(full.withoutTargetAt(1).targets, [_t1, _t3]);
      expect(full.withoutTargetAt(9), full);
      expect(full.withoutTargets(), const BlockLayers(timeBlock: 'deep', activityId: 'a1'));
    });

    test('changer la tâche d’une cible, sans doublon', () {
      const other = BlockTarget(projectId: 'p2', taskId: 'u1');
      expect(full.withTargetAt(2, other).targets, [_t1, _t2, other]);
      // La cible 2 deviendrait la même que la 0 : refusé.
      expect(full.withTargetAt(1, const BlockTarget(projectId: 'p1', taskId: 't1')), full);
    });
  });

  group('BlockLayers ↔ ScheduleBlock', () {
    test('of lit la principale et les suivantes', () {
      final b = _b(timeBlock: 'deep', activityId: 'a1', projectId: 'p1', taskId: 't1', actionId: 'x1')..extraTargets = [_t2, _t3];
      expect(BlockLayers.of(b), const BlockLayers(timeBlock: 'deep', activityId: 'a1', targets: [_t1, _t2, _t3]));
      expect(BlockLayers.of(_b(activityId: 'a1', actionId: 'own')), const BlockLayers(activityId: 'a1', ownActionId: 'own'));
    });

    test('applyTo écrit toutes les couches, vides comprises', () {
      final b = _b(timeBlock: 'deep', activityId: 'a1', projectId: 'p1', taskId: 't1', actionId: 'x1')..extraTargets = [_t2];
      const BlockLayers(activityId: 'a2').applyTo(b);
      expect(BlockLayers.of(b), const BlockLayers(activityId: 'a2'));
      expect(b.projectId, isNull);
      expect(b.extraTargets, isEmpty);

      const BlockLayers(targets: [_t2, _t1]).applyTo(b);
      expect((b.projectId, b.taskId, b.actionId), ('p1', 't2', null));
      expect(b.extraTargets, [_t1]);
    });

    test('BlockLayers.single = une cible, ou une action propre sans projet', () {
      expect(BlockLayers.single(projectId: 'p1', taskId: 't1', actionId: 'x1'), const BlockLayers(targets: [_t1]));
      expect(BlockLayers.single(activityId: 'a1', actionId: 'own'), const BlockLayers(activityId: 'a1', ownActionId: 'own'));
    });
  });

  group('stackRefusal', () {
    test('un bloc à faire reçoit une couche nouvelle, une cible de plus aussi', () {
      expect(stackRefusal(_b(timeBlock: 'deep'), const BlockLayers(activityId: 'a1')), isNull);
      expect(stackRefusal(_b(projectId: 'p1', taskId: 't1'), const BlockLayers(targets: [_t2])), isNull);
    });

    test('rien de neuf, bloc fait, pause, bloc plein : refusé', () {
      expect(stackRefusal(_b(timeBlock: 'deep'), const BlockLayers(timeBlock: 'deep')), isNotNull);
      expect(stackRefusal(_b(projectId: 'p1', taskId: 't1'), const BlockLayers(targets: [_t1])), isNotNull);
      expect(stackRefusal(_b()..status = 'done', const BlockLayers(activityId: 'a1')), isNotNull);
      expect(stackRefusal(_b()..category = 'break', const BlockLayers(activityId: 'a1')), isNotNull);
      expect(stackRefusal(_b(), const BlockLayers()), isNotNull);
      final fullBlock = _b(projectId: 'p', taskId: 't0')
        ..extraTargets = [for (var i = 1; i < kMaxBlockTargets; i++) BlockTarget(projectId: 'p', taskId: 't$i')];
      expect(stackRefusal(fullBlock, const BlockLayers(targets: [_t3])), contains('$kMaxBlockTargets'));
    });

    test('un rendez-vous d’agenda ne reçoit qu’une activité', () {
      final mirror = _b()..gcalEventId = 'g1';
      expect(stackRefusal(mirror, const BlockLayers(activityId: 'a1')), isNull);
      expect(stackRefusal(mirror, const BlockLayers(timeBlock: 'deep')), isNotNull);
      expect(stackRefusal(mirror, const BlockLayers(targets: [_t1])), isNotNull);
    });
  });

  group('titres', () {
    const prep = (project: 'Maths 6e', task: 'Préparer la séance');
    const fix = (project: 'Maths 6e', task: 'Corriger les copies');
    const cm = (project: 'CM', task: null);

    test('layersTitle : le mode puis la première cible, « + n » pour les autres', () {
      expect(layersTitle(timeBlock: 'deep'), 'Deep work');
      expect(layersTitle(timeBlock: 'deep', activity: 'Interventions'), 'Deep work · Interventions');
      expect(layersTitle(timeBlock: 'small', activity: 'Interventions', targets: [prep]), 'Petites choses · Préparer la séance');
      expect(layersTitle(activity: 'Interventions', targets: [cm]), 'CM');
      expect(layersTitle(timeBlock: 'deep', targets: [prep, fix, cm]), 'Deep work · Préparer la séance + 2');
      expect(layersTitle(targets: [prep, fix]), 'Préparer la séance + 1');
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
          layersLine(timeBlock: 'deep', activity: 'Interventions', targets: [prep], title: 'Deep work · Préparer la séance'),
          'Interventions · Maths 6e');
      expect(layersLine(activity: 'Interventions', title: 'Interventions'), '');
      expect(layersLine(timeBlock: 'small', targets: [(project: 'Maths 6e', task: 'Corriger')], title: 'Créneau'),
          'Petites choses · Maths 6e › Corriger');
    });

    test('layersLine : plusieurs cibles sont toutes dites, le projet répété une fois', () {
      expect(
          layersLine(
              timeBlock: 'deep',
              activity: 'Interventions',
              targets: [prep, fix, cm],
              title: 'Deep work · Préparer la séance + 2'),
          'Interventions · Maths 6e › Préparer la séance + Corriger les copies + CM');
    });
  });
  group('Miracle morning', () {
    test('un mode comme les autres : libellé, durée, catégorie', () {
      expect(kTimeBlockLabels['morning'], 'Miracle morning');
      expect(layersTitle(timeBlock: 'morning'), 'Miracle morning');
      expect((timeBlockDefaultMin('morning'), timeBlockCategory('morning')), (60, 'routine'));
      expect((timeBlockDefaultMin('deep'), timeBlockCategory('deep')), (90, 'project'));
      expect((timeBlockDefaultMin('small'), timeBlockCategory('small')), (45, 'personal'));
    });

    test('posé par Planifier : un bloc de routine, sans source', () {
      final b = planOrTimeBlockOf(PlannedBlock(
          PlanWant(activityId: timeWantId('morning', 100), title: 'Miracle morning', minutes: 60, reason: ''), 5 * 60 + 30, 60));
      expect((b.timeBlock, b.title, b.category, b.startTime, b.durationMin), ('morning', 'Miracle morning', 'routine', '05:30', 60));
      expect(b.activityId, isNull);
    });

    test('il remplace le mode d’un bloc, et se pose sur un bloc libre', () {
      expect(stackLayers(const BlockLayers(timeBlock: 'deep', activityId: 'a1'), const BlockLayers(timeBlock: 'morning')),
          const BlockLayers(timeBlock: 'morning', activityId: 'a1'));
      expect(stackRefusal(_b(), const BlockLayers(timeBlock: 'morning')), isNull);
      expect(stackRefusal(_b()..gcalEventId = 'g', const BlockLayers(timeBlock: 'morning')), isNotNull);
    });
  });
}
