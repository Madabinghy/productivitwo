import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/sniper.dart';
import 'package:productivitwo_v1/utils/sniper_block.dart';

void main() {
  final d0 = DateTime(2026, 11, 21);
  final kingdom = Activity(id: 'kin', domainId: 'd', name: 'Kingdom', goalMin: 30);
  final pompes = Activity(id: 'pom', domainId: 'd', name: 'Pompes', type: 'habit', habitFreq: HabitFreq.daily, habitTarget: 1);
  final manger = Activity(id: 'man', domainId: 'd', name: 'Manger', goalMin: 0);
  TaskAction act(String id, String title, int est, {bool done = false}) => TaskAction(id: id, title: title, estimatedMin: est, done: done);
  Project project({String? linked}) => Project(
        id: 'p',
        title: 'Maths 6e',
        startDate: d0,
        createdBy: 'u',
        linkedActivityId: linked,
        tasks: [
          ProjectTask(id: 't', title: 'Préparer la séance', startDate: d0, actions: [
            act('a1', 'Relire le chapitre', 10),
            act('a2', 'Faire les fiches', 15),
            act('a3', 'Déjà fait', 5, done: true),
            act('a4', 'Imprimer', 5),
          ]),
        ],
      );
  ScheduleBlock block({String start = '14:00', int dur = 60, String? projectId = 'p', String? taskId = 't', String? actionId, String? activityId, String? gcal, String? timeBlock, String title = 'Préparer la séance'}) {
    final b = ScheduleBlock(id: 'b', startTime: start, durationMin: dur, title: title, projectId: projectId, taskId: taskId, actionId: actionId, activityId: activityId);
    b.gcalEventId = gcal;
    b.timeBlock = timeBlock;
    return b;
  }

  ScheduleBlock? find(ScheduleBlock b, int nowMin, {List<Project>? projects}) =>
      sniperBlockOf(blocks: [b], nowMin: nowMin, activities: [kingdom, pompes, manger], projects: projects ?? [project()]);

  group('sniperBlockOf', () {
    test('un bloc de tâche commencé se vise', () {
      expect(find(block(), 14 * 60 + 20), isNotNull);
    });
    test('pas avant son début, ni dans ses 5 dernières minutes', () {
      expect(find(block(), 13 * 60 + 50), isNull);
      expect(find(block(), 14 * 60 + 56), isNull);
    });
    test('jamais un rendez-vous d’agenda, un bloc de temps ou un besoin de base', () {
      expect(find(block(gcal: 'ev'), 14 * 60 + 20), isNull);
      expect(find(block(timeBlock: 'deep'), 14 * 60 + 20), isNull);
      expect(find(block(projectId: null, taskId: null, activityId: 'man', title: 'Déjeuner'), 14 * 60 + 20), isNull);
    });
    test('un bloc d’activité-temps se vise, pas un bloc de routine', () {
      expect(find(block(projectId: null, taskId: null, activityId: 'kin', title: 'Kingdom'), 14 * 60 + 20), isNotNull);
      expect(find(block(projectId: null, taskId: null, activityId: 'pom', title: 'Pompes'), 14 * 60 + 20), isNull);
    });
    test('un bloc de séance (tâche 🎯) a son écran : pas de Sniper', () {
      final p = project();
      p.tasks.first.title = '🎯 Séance du 24';
      p.tasks.first.interventionRole = 'session';
      expect(find(block(), 14 * 60 + 20, projects: [p]), isNull);
    });
  });

  test('bloc de tâche : l’action visée d’abord, puis les autres ouvertes, dans l’ordre', () {
    final s = blockSniperStakes(block: block(actionId: 'a2'), projects: [project()], activities: [kingdom], today: d0);
    expect([for (final x in s) x.gesture.title], ['Faire les fiches', 'Relire le chapitre', 'Imprimer']);
    expect(s.first.gesture.costMin, 15);
  });

  test('le facteur réel / estimé corrige les durées, au multiple de 5', () {
    final s = blockSniperStakes(block: block(), projects: [project()], activities: [kingdom], today: d0, factor: 1.4);
    expect([for (final x in s) x.gesture.costMin], [15, 25, 10]);
  });

  test('le plan garde l’ordre du bloc et laisse hors de portée ce qui ne tient pas', () {
    final s = blockSniperStakes(block: block(), projects: [project()], activities: [kingdom], today: d0);
    final plan = planBlockSniper(stakes: s, budgetMin: 30, untilMin: 15 * 60);
    expect([for (final t in plan.aimed) t.title], ['Relire le chapitre', 'Faire les fiches']);
    expect(plan.outOfReach.single.reason, 'ne tient plus avant 15:00');
  });

  test('une première action plus longue que le bloc prend tout le temps qui reste', () {
    final p = project();
    p.tasks.first.actions.first.estimatedMin = 90;
    final s = blockSniperStakes(block: block(), projects: [p], activities: [kingdom], today: d0);
    final plan = planBlockSniper(stakes: s, budgetMin: 38, untilMin: 15 * 60);
    expect(plan.aimed.single.minutes, 38);
  });

  test('bloc d’activité : UNE cible, l’activité, qui contient ses actions et le temps libre', () {
    final b = block(projectId: null, taskId: null, activityId: 'kin', title: 'Kingdom');
    final s = blockSniperStakes(block: b, projects: [project(linked: 'kin')], activities: [kingdom], today: d0);
    expect([for (final x in s) x.gesture.title], ['Relire le chapitre']);
    final plan = planBlockSniper(stakes: s, budgetMin: 38, untilMin: 15 * 60, fill: kingdom, block: b);
    expect(plan.aimed, hasLength(1));
    final t = plan.aimed.single;
    expect(t.title, 'Kingdom');
    expect(t.kind, SniperKind.timed);
    expect(t.minutes, 38);
    expect([for (final x in t.steps) x.title], ['Relire le chapitre']);
    expect(t.freeMin, 28);
  });
}
