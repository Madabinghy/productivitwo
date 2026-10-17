import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/chain.dart';

ScheduleBlock _b(String id, String start, int dur,
        {String? projectId, String? taskId, String? actionId, String? activityId, String? gcal, String status = 'pending'}) =>
    ScheduleBlock(
        id: id,
        startTime: start,
        durationMin: dur,
        title: id,
        projectId: projectId,
        taskId: taskId,
        actionId: actionId,
        activityId: activityId,
        gcalEventId: gcal,
        status: status);

void main() {
  final now = DateTime(2026, 10, 16, 9, 10);
  final project = Project(id: 'p', title: '6e', startDate: DateTime(2026, 9, 1), createdBy: 'u', tasks: [
    ProjectTask(id: 't', title: 'DM', startDate: DateTime(2026, 10, 1), actions: [
      TaskAction(id: 'a1', title: 'Adapter', checklist: [
        ChecklistItem(id: 'c1', title: 'Fiche', done: true),
        ChecklistItem(id: 'c2', title: 'Kahoot'),
        ChecklistItem(id: 'c3', title: 'Reporté'),
      ]),
      TaskAction(id: 'a2', title: 'Rédiger'),
      TaskAction(id: 'a3', title: 'Relire', done: true),
    ]),
  ]);
  final water = Activity(id: 'w', domainId: 'd', name: 'Eau', type: 'habit', habitFreq: HabitFreq.daily, habitTarget: 6);
  final lit = Activity(id: 'l', domainId: 'd', name: 'Lit', type: 'habit', habitFreq: HabitFreq.daily, habitTarget: 1);

  test('buildChain : blocs à venir dans l\'ordre, étapes ouvertes puis actions, routines, blocs libres', () {
    final blocks = [
      _b('late', '07:00', 60, projectId: 'p', taskId: 't'), // fini : hors file
      _b('b1', '09:00', 90, projectId: 'p', taskId: 't', actionId: 'a1'), // en cours
      _b('b2', '11:00', 20, activityId: 'w'),
      _b('b3', '12:00', 30, gcal: 'g'),
      _b('b4', '13:00', 10, activityId: 'l'),
      _b('done', '14:00', 30, status: 'done'),
    ];
    final hits = [HabitHit(habitId: 'l', ts: DateTime(2026, 10, 16, 7))];
    final chain = buildChain(blocks: blocks, projects: [project], activities: [water, lit], hits: hits, now: now);
    expect(chain.map((i) => '${i.kind.name}:${i.title}').toList(), [
      'step:Kahoot', 'step:Reporté', 'action:Rédiger', 'routine:Eau', 'block:b3',
    ]);
    expect(chain[0].index, 1);
    expect(chain[0].total, 2);
    expect(chain[0].context, 'Adapter');
    expect(chain[2].context, 'DM');
    expect(chain[3].timed, isFalse);
    expect(chain[4].timed, isFalse);
    expect(chainEndMin(chain), 12 * 60 + 30);
  });

  test('orderChain : écartés retirés, reportés en fin dans l\'ordre du report', () {
    final blocks = [_b('b1', '09:00', 90, projectId: 'p', taskId: 't', actionId: 'a1'), _b('b2', '11:00', 20, activityId: 'w')];
    final chain = buildChain(blocks: blocks, projects: [project], activities: [water], hits: const [], now: now);
    final k = chain.map((i) => i.key).toList();
    final o = orderChain(chain, deferred: [k[1], k[0]], dismissed: {k[3]});
    expect(o.map((i) => i.title).toList(), ['Rédiger', 'Reporté', 'Kahoot']);
  });

  test('overrunMin / shiftFollowing : quart d\'heure, jamais un miroir agenda', () {
    final cur = _b('b1', '09:00', 60);
    expect(overrunMin(cur, 9 * 60 + 50), 0);
    expect(overrunMin(cur, 10 * 60 + 4), 15);
    expect(overrunMin(cur, 10 * 60 + 16), 30);
    final blocks = [cur, _b('b2', '10:00', 30), _b('g', '10:30', 30, gcal: 'x'), _b('b3', '11:00', 30), _b('d', '11:30', 30, status: 'done'), _b('early', '08:00', 30)];
    final changed = shiftFollowing(blocks, cur, 15);
    expect(changed.map((b) => '${b.id}@${b.startTime}').toList(), ['b2@10:15', 'b3@11:15']);
  });

  test('routines accrochées : moment courant en tête, moments suivants à l\'entrée, toute la journée après un bloc de travail', () {
    Activity h(String id, String name, {String? ctx, int t = 1}) =>
        Activity(id: id, domainId: 'd', name: name, type: 'habit', habitFreq: HabitFreq.daily, habitTarget: t, timeContext: ctx);
    final acts = [
      h('lou', 'Louanges', ctx: 'morning'),
      h('rep', 'Repas', ctx: 'midday'),
      h('eau', 'Eau', ctx: 'allday', t: 6),
      h('pom', 'Pompes', ctx: 'allday'),
      h('soir', 'Hygiène du soir'), // archétype soir
    ];
    final blocks = [
      _b('b1', '09:00', 90, projectId: 'p', taskId: 't', actionId: 'a2'),
      _b('b2', '14:00', 60, projectId: 'p', taskId: 't', actionId: 'a2'),
      _b('g', '16:00', 30, gcal: 'x'),
    ];
    final chain = buildChain(blocks: blocks, projects: [project], activities: acts, hits: const [], now: now);
    expect(chain.map((i) => '${i.kind.name}:${i.title}').toList(), [
      'routine:Louanges',
      'action:Rédiger', 'step:Kahoot', 'step:Reporté', 'routine:Eau',
      'routine:Repas',
      'action:Rédiger', 'step:Kahoot', 'step:Reporté', 'routine:Pompes',
      'block:g',
      'routine:Hygiène du soir',
    ]);
    expect(chain.first.synthetic, isTrue);
    expect(chain.first.block.title, 'Routines du matin');
    expect(chain[4].block.title, 'Après « b1 »');
    // Routine déjà au programme → pas d'accroche en plus ; écartée → absente.
    final chain2 = buildChain(
        blocks: [...blocks, _b('r', '10:45', 10, activityId: 'rep')],
        projects: [project], activities: acts, hits: const [], now: now, dismissed: {'lou'});
    expect(chain2.where((i) => i.kind == ChainKind.routine && i.activity?.id == 'rep').length, 1);
    expect(chain2.any((i) => i.activity?.id == 'lou'), isFalse);
    // Sans accroche : seulement le programme.
    expect(buildChain(blocks: blocks, projects: [project], activities: acts, hits: const [], now: now, anchorRoutines: false).length, 7);
  });
}
