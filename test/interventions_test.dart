import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/interventions.dart';

TaskAction _a(String title, {List<String>? ctx, bool done = false}) =>
    TaskAction(title: title, contexts: ctx, done: done);

ProjectTask _t(String id, String title, String start,
        {String? end, String? group, bool milestone = false, List<TaskAction> actions = const [],
        String status = 'pending'}) =>
    ProjectTask(
        id: id,
        title: title,
        startDate: DateTime.parse(start),
        endDate: end == null ? null : DateTime.parse(end),
        groupLabel: group,
        isMilestone: milestone,
        actions: List.of(actions),
        status: status);

Project _p(String id, List<ProjectTask> tasks, {String? desc, String? parent, bool paused = false}) =>
    Project(
        id: id,
        title: id,
        description: desc,
        startDate: DateTime(2026, 9, 1),
        createdBy: 'u',
        tasks: tasks,
        parentProjectId: parent,
        paused: paused);

void main() {
  final today = DateTime(2026, 10, 7);
  final cm = _p('CM', desc: 'Lundi 13h15–15h00, CM1-CM2.', [
    _t('prep5', '📝 Préparer — Séance du 5 oct', '2026-10-02', end: '2026-10-04', group: 'Séance — 5 oct',
        status: 'done', actions: [_a('Fiche', done: true), _a('Imprimer', ctx: ['@impression'])]),
    _t('m5', '🎯 Lun 5 oct — Kahoot', '2026-10-05', end: '2026-10-05', group: 'Séance — 5 oct',
        milestone: true, status: 'done', actions: [_a('Dérouler la séance (13h15–15h00)', done: true)]),
    _t('close5', '✅ Clôturer — Séance du 5 oct', '2026-10-05', end: '2026-10-06', group: 'Séance — 5 oct',
        actions: [_a('Fiche de séquence'), _a('Kahoot maison')]),
    _t('prep12', '📝 Préparer — Séance du 12 oct', '2026-10-06', end: '2026-10-11', group: 'Séance — 12 oct',
        actions: [
          _a('Contrôle', done: true),
          _a('Kahoot images', done: true),
          _a('Imprimer à l\'école', ctx: ['@impression']),
        ]),
    _t('m12', '🏁 Lun 12 oct — Contrôle', '2026-10-12', end: '2026-10-12', group: 'Séance — 12 oct',
        actions: [_a('Dérouler la séance (13h15–15h00)')]),
    _t('close12', '✅ Clôturer — Séance du 12 oct', '2026-10-12', end: '2026-10-13', group: 'Séance — 12 oct',
        actions: [_a('Fiche de séquence')]),
    _t('corr', '✍️ Corriger', '2026-10-12', group: 'Séance — 12 oct', actions: [_a('Copies')]),
    _t('m9nov', '🎯 Lun 9 nov — Soustractions', '2026-11-09', end: '2026-11-09', group: 'Séance — 9 nov',
        milestone: true),
    _t('skipped', '🎯 annulé', '2026-10-08', group: 'x', milestone: true, status: 'skipped'),
  ]);

  test('interventionsOf : un jalon = une intervention, prépa / clôture par groupLabel, triées', () {
    final list = interventionsOf(cm);
    expect(list.map((i) => i.milestone.id).toList(), ['m5', 'm12', 'm9nov']);
    expect(list[0].prep?.id, 'prep5');
    expect(list[0].closure?.id, 'close5');
    expect(list[1].prep?.id, 'prep12');
    expect(list[2].prep, isNull);
    expect(list[1].date, DateTime(2026, 10, 12));
  });

  test('timeRange : lu dans l\'action du jalon, sinon la description du projet', () {
    final list = interventionsOf(cm);
    expect(list[1].timeRange, '13h15–15h00');
    expect(list[2].timeRange, '13h15–15h00');
  });

  test('prepState : prête à imprimer quand il ne reste que l\'impression', () {
    final list = interventionsOf(cm);
    expect(list[1].prepState, PrepState.readyToPrint);
    expect(list[0].prepState, PrepState.done);
    expect(list[2].prepState, PrepState.none);
  });

  test('next / previous : jalon fait → suivant ; clôture précédente à faire', () {
    final next = nextInterventionOf(cm, today)!;
    expect(next.milestone.id, 'm12');
    final prev = previousInterventionOf(cm, today, next: next)!;
    expect(prev.milestone.id, 'm5');
    expect(prev.closureState, ClosureState.todo);
    expect(prev.closureOpen, 2);
  });

  test('jalon passé non coché reste le prochain (en retard)', () {
    final late = _p('L', [
      _t('m', '🎯 Séance', '2026-10-01', end: '2026-10-01', milestone: true, actions: [_a('Dérouler')]),
    ]);
    final r = weekRadar([late], today).single;
    expect(r.next!.milestone.id, 'm');
    expect(r.daysTo(today), -6);
    expect(r.isQuiet(today), isFalse);
  });

  test('natif d\'abord : date, créneau et titre de l\'objet ; tâches par rôle ; annulée ignorée', () {
    final p = _p('N', [
      _t('prep', '📝 Préparer — S', '2026-10-05', end: '2026-10-11', group: 'S')
        ..interventionId = 'i1'
        ..interventionRole = 'prep',
      _t('sess', '🎯 Lun 12 oct. — S', '2026-10-12', end: '2026-10-12', group: 'S', milestone: true)
        ..interventionId = 'i1'
        ..interventionRole = 'session',
      _t('close', '✅ Clôturer — S', '2026-10-12', end: '2026-10-14', group: 'S')
        ..interventionId = 'i1'
        ..interventionRole = 'closure',
      _t('old', '🎯 Ancien', '2026-10-02', end: '2026-10-02', group: 'Ancien', milestone: true, status: 'done'),
      _t('cancelled', '🎯 Annulée', '2026-10-30', group: 'A', milestone: true)
        ..interventionId = 'i2'
        ..interventionRole = 'session',
    ]);
    p.interventions.addAll([
      ProjectIntervention(
          id: 'i1', title: 'Séance 12', date: DateTime(2026, 10, 13), startTime: '08:00', endTime: '12:00'),
      ProjectIntervention(
          id: 'i2', title: 'Annulée', date: DateTime(2026, 10, 30), startTime: '08:00', endTime: '09:00',
          status: 'cancelled'),
    ]);
    final list = interventionsOf(p);
    expect(list.map((i) => i.milestone.id).toList(), ['old', 'sess']);
    final n = list[1];
    expect(n.title, 'Séance 12');
    expect(n.date, DateTime(2026, 10, 13));
    expect(n.timeRange, '8h00–12h00');
    expect(n.prep?.id, 'prep');
    expect(n.closure?.id, 'close');
    expect(n.native?.slotMin, 240);
  });

  test('modèle : interventions et tags survivent au round-trip toJson / from', () {
    final p = _p('R', [_t('t', 'x', '2026-10-01')..interventionId = 'i'..interventionRole = 'prep']);
    p.interventions.add(ProjectIntervention(
        id: 'i', title: 'S', date: DateTime(2026, 10, 12), startTime: '13:15', endTime: '15:00',
        place: 'École', debriefText: 'ok', carryOver: [ChecklistItem(title: 'Reprendre')]));
    final back = Project.from(p.toJson());
    expect(back.interventions.single.ymd, '2026-10-12');
    expect(back.interventions.single.place, 'École');
    expect(back.interventions.single.carryOver.single.title, 'Reprendre');
    expect(back.tasks.single.interventionRole, 'prep');
  });

  test('weekRadar : dossiers et projets en pause exclus, tri par date, calme > 14 j', () {
    final folder = _p('Dossier', []);
    final child = _p('Enfant', parent: 'Dossier', [
      _t('m', '🎯 Séance', '2026-10-30', end: '2026-10-30', milestone: true),
    ]);
    final paused = _p('Pause', paused: true, [
      _t('m', '🎯 Séance', '2026-10-08', milestone: true),
    ]);
    final none = _p('Sans jalon', [_t('t', 'Tâche', '2026-10-01')]);
    final radar = weekRadar([none, paused, child, cm, folder], today);
    expect(radar.map((r) => r.project.id).toList(), ['CM', 'Enfant']);
    expect(radar[1].isQuiet(today), isTrue);
    expect(radar[0].isQuiet(today), isFalse);
  });
}
