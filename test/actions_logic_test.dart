import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/actions_logic.dart';
import 'package:productivitwo_v1/utils/mode.dart';

TaskAction _a(String title, {List<String>? ctx, int? est, bool done = false, String? linked, DateTime? due}) =>
    TaskAction(title: title, contexts: ctx, estimatedMin: est, done: done, linkedActivityId: linked, dueDate: due);

ProjectTask _t(String id, String start, List<TaskAction> actions, {String status = 'pending'}) =>
    ProjectTask(id: id, title: id, startDate: DateTime.parse(start), actions: actions, status: status);

Project _p(String id, List<ProjectTask> tasks,
        {DateTime? end, String? domainId, bool paused = false, String? linked}) =>
    Project(
        id: id,
        title: id,
        startDate: DateTime(2026, 9, 1),
        endDate: end,
        createdBy: 'u',
        tasks: tasks,
        domainId: domainId,
        paused: paused,
        linkedActivityId: linked);

bool _all(TaskAction _) => true;

void main() {
  test('passesContexts : vide = tout, sans contexte = passe, sinon intersection', () {
    expect(passesContexts(_a('x', ctx: ['@maison']), {}), isTrue);
    expect(passesContexts(_a('x'), {'@bureau'}), isTrue);
    expect(passesContexts(_a('x', ctx: ['@maison']), {'@bureau'}), isFalse);
    expect(passesContexts(_a('x', ctx: ['@maison', '@bureau']), {'@bureau'}), isTrue);
  });

  test('passesTime : sans estimation passe ; seuils 15 / 60 / plus', () {
    expect(passesTime(_a('x'), TimeBucket.quarter), isTrue);
    expect(passesTime(_a('x', est: 15), TimeBucket.quarter), isTrue);
    expect(passesTime(_a('x', est: 20), TimeBucket.quarter), isFalse);
    expect(passesTime(_a('x', est: 60), TimeBucket.hour), isTrue);
    expect(passesTime(_a('x', est: 90), TimeBucket.hour), isFalse);
    expect(passesTime(_a('x', est: 90), TimeBucket.more), isTrue);
    expect(passesTime(_a('x', est: 30), null), isTrue);
  });

  test('sortedByEstimate : estimées de la plus courte à la plus longue, non estimées après, stable', () {
    final l = [_a('sans1'), _a('long', est: 90), _a('court', est: 10), _a('sans2'), _a('moyen', est: 10)];
    expect(sortedByEstimate(l, (a) => a.estimatedMin).map((a) => a.title).toList(),
        ['court', 'moyen', 'long', 'sans1', 'sans2']);
  });

  test('nearestOutsideBucket : la plus courte au-delà du créneau, la plus longue en deçà pour « plus »', () {
    final l = [_a('sans'), _a('20', est: 20), _a('45', est: 45), _a('90', est: 90), _a('10', est: 10)];
    expect(nearestOutsideBucket(l, TimeBucket.quarter)?.action.title, '20');
    expect(nearestOutsideBucket(l, TimeBucket.hour)?.action.title, '90');
    expect(nearestOutsideBucket(l, TimeBucket.more)?.action.title, '45');
    expect(nearestOutsideBucket([_a('sans'), _a('10', est: 10)], TimeBucket.quarter), isNull);
  });

  test('matchesQuery : accents et casse ignorés, tous les mots, sur n\'importe quel champ', () {
    expect(matchesQuery('', ['x']), isTrue);
    expect(matchesQuery('  ', ['x']), isTrue);
    expect(matchesQuery('Dévis', ['Relire le devis', null]), isTrue);
    expect(matchesQuery('devis dupont', ['Relire le devis', 'Dossier Dupont']), isTrue);
    expect(matchesQuery('devis martin', ['Relire le devis', 'Dossier Dupont']), isFalse);
    expect(matchesQuery('ecole', ['6e — École des Mathématiques']), isTrue);
    expect(matchesQuery('oeuvre', ['Œuvre']), isTrue);
  });

  group('Échéance par action (dueDate, 2026-10)', () {
    final today = DateTime(2026, 10, 16);
    final t = ProjectTask(id: 't', title: 't', startDate: DateTime(2026, 10, 1), endDate: DateTime(2026, 10, 20, 23, 59));

    test('effectiveDueDate : la sienne, sinon celle de la tâche, jour seul ; sans rien = null', () {
      expect(effectiveDueDate(_a('x', due: DateTime(2026, 10, 10, 15)), t), DateTime(2026, 10, 10));
      expect(effectiveDueDate(_a('x'), t), DateTime(2026, 10, 20));
      expect(effectiveDueDate(_a('x'), ProjectTask(id: 'u', title: 'u', startDate: DateTime(2026, 10, 1))), isNull);
      expect(effectiveDueDate(_a('x'), null), isNull);
    });

    test('isOverdueAction : échéance propre passée dans une tâche encore dans les temps', () {
      expect(isOverdueAction(_a('x', due: DateTime(2026, 10, 15)), t, today), isTrue);
      expect(isOverdueAction(_a('x', due: DateTime(2026, 10, 16)), t, today), isFalse);
      expect(isOverdueAction(_a('x'), t, today), isFalse);
      expect(isOverdueAction(_a('x', due: DateTime(2026, 10, 15), done: true), t, today), isFalse);
      final late = ProjectTask(id: 'l', title: 'l', startDate: DateTime(2026, 10, 1), endDate: DateTime(2026, 10, 10));
      expect(isOverdueAction(_a('x'), late, today), isTrue);
      // Une échéance propre plus tard que la tâche repousse le retard.
      expect(isOverdueAction(_a('x', due: DateTime(2026, 10, 30)), late, today), isFalse);
      expect(isOverdueAction(_a('x'), ProjectTask(id: 'd', title: 'd', startDate: DateTime(2026, 10, 1),
          endDate: DateTime(2026, 10, 10), status: 'done'), today), isFalse);
    });

    test('overdueActionCount : par action, pas par tâche', () {
      final p = _p('p', [
        _t('ok', '2026-10-01', [_a('a', due: DateTime(2026, 10, 10)), _a('b')]),
      ]);
      expect(overdueActionCount([p], today), 1);
    });

    test('projectActionGroups entryFilter : « En retard » par action', () {
      final p = _p('p', [
        _t('t', '2026-10-01', [_a('late', due: DateTime(2026, 10, 10)), _a('ok')]),
      ]);
      final g = projectActionGroups([p],
          filter: _all, entryFilter: (t, a) => isOverdueAction(a, t, today));
      expect(g.single.entries.map((e) => e.action.title).toList(), ['late']);
    });

    test('actionDueLabel / shortDateFr', () {
      expect(actionDueLabel(DateTime(2026, 10, 13), today), '−3 j');
      expect(actionDueLabel(DateTime(2026, 10, 16, 9), today), "aujourd'hui");
      expect(actionDueLabel(DateTime(2026, 10, 17), today), 'demain');
      expect(actionDueLabel(DateTime(2026, 10, 25), today), 'éch. 25 oct.');
      expect(shortDateFr(DateTime(2027, 1, 3), today: today), '3 janv. 2027');
    });

    test('toJson / from : dueDate en YYYY-MM-DD, null conservé', () {
      final a = _a('x', due: DateTime(2026, 10, 5, 18, 30));
      expect(a.toJson()['dueDate'], '2026-10-05');
      expect(TaskAction.from(a.toJson()).dueDate, DateTime(2026, 10, 5));
      expect(TaskAction.from(_a('y').toJson()).dueDate, isNull);
    });
  });

  test('flowTaskOf : créée une fois, réactivée si close', () {
    final p = _p('p', [_t('t', '2026-10-01', [])]);
    final f = flowTaskOf(p);
    expect(f.id, kFlowTaskId);
    expect(p.tasks.length, 2);
    f.status = 'done';
    expect(identical(flowTaskOf(p), f), isTrue);
    expect(f.status, 'pending');
    expect(p.tasks.length, 2);
  });

  test('timeBucketLabel', () {
    expect(timeBucketLabel(TimeBucket.quarter), '15 min');
    expect(timeBucketLabel(TimeBucket.more), "plus d'1 h");
  });

  test('knownContexts : défauts puis contextes rencontrés, triés, sans doublon', () {
    final projects = [_p('p', [_t('t', '2026-09-01', [_a('a', ctx: ['@zoo', '@maison'])])])];
    final acts = [
      Activity(name: 'Lecture', domainId: 'd', type: 'time', ownActions: [_a('o', ctx: ['@bib'])])
    ];
    final k = knownContexts(projects, acts);
    expect(k.take(kDefaultGtdContexts.length).toList(), kDefaultGtdContexts);
    expect(k.skip(kDefaultGtdContexts.length).toList(), ['@bib', '@zoo']);
  });

  group('projectActionGroups', () {
    final projects = [
      _p('b', [
        _t('t2', '2026-09-10', [_a('b-later')]),
        _t('t1', '2026-09-05', [_a('b-done', done: true), _a('b-next'), _a('b-second')]),
      ], end: DateTime(2026, 10, 20), domainId: 'sante'),
      _p('a', [_t('t', '2026-09-01', [_a('a-next')])], end: DateTime(2026, 10, 1), domainId: 'travail'),
      _p('paused', [_t('t', '2026-09-01', [_a('x')])], paused: true),
    ];
    test('prochaine action en tête, puis ordre Gantt ; projets en pause exclus', () {
      final g = projectActionGroups(projects, filter: _all);
      expect(g.map((x) => x.project.id).toList(), ['a', 'b']); // par échéance
      final b = g[1];
      expect(b.entries.map((e) => e.action.title).toList(), ['b-next', 'b-second', 'b-later']);
    });
    test('tri alphabétique et par domaine', () {
      expect(projectActionGroups(projects, filter: _all, sort: ActionsSort.alpha).map((x) => x.project.id).toList(),
          ['a', 'b']);
      expect(
          projectActionGroups(projects,
                  filter: _all, sort: ActionsSort.domain, domainOrder: ['sante', 'travail'])
              .map((x) => x.project.id)
              .toList(),
          ['b', 'a']);
    });
    test('filtre actif : seuls les projets avec une action qui passe ; les autres comptés', () {
      final g = projectActionGroups(projects, filter: (a) => a.title == 'b-second');
      final v = visibleProjectGroups(g, filtering: true);
      expect(v.shown.map((x) => x.project.id).toList(), ['b']);
      expect(v.hidden, g.length - 1);
      final all = visibleProjectGroups(g, filtering: false);
      expect(all.shown.length, g.length);
      expect(all.hidden, 0);
    });
    test('le filtre s\'applique aux actions, le projet reste listé (vide)', () {
      final g = projectActionGroups(projects, filter: (a) => a.title == 'b-second');
      expect(g.firstWhere((x) => x.project.id == 'b').entries.single.action.title, 'b-second');
      expect(g.firstWhere((x) => x.project.id == 'a').entries, isEmpty);
    });
  });

  test('possibleNow : lien propre, lien du projet, action simple', () {
    final projects = [
      _p('p1', [_t('t', '2026-09-01', [_a('own-link', linked: 'act'), _a('no')])]),
      _p('p2', [_t('t', '2026-09-01', [_a('via-project')])], linked: 'act'),
    ];
    final acts = [
      Activity(id: 'act', name: 'Deep work', domainId: 'd', type: 'time', ownActions: [_a('simple')]),
      Activity(id: 'other', name: 'Autre', domainId: 'd', type: 'time', ownActions: [_a('nope')]),
    ];
    final r = possibleNow(projects, acts, 'act', filter: _all);
    expect(r.map((e) => e.action.title).toList(), ['own-link', 'via-project', 'simple']);
  });

  test('ownActionGroups : activités avec au moins une action ouverte filtrée', () {
    final acts = [
      Activity(id: 'a', name: 'A', domainId: 'd', type: 'time', ownActions: [_a('x', done: true)]),
      Activity(id: 'b', name: 'B', domainId: 'd', type: 'time', ownActions: [_a('y'), _a('z', done: true)]),
    ];
    final g = ownActionGroups(acts, filter: _all);
    expect(g.single.activity.id, 'b');
    expect(g.single.actions.single.title, 'y');
  });

  test('tri milestone : prochaine séance la plus proche d\'abord, sans séance en dernier', () {
    final a = _p('A', [_t('ta', '2026-10-01', [_a('x')])], end: DateTime(2026, 12, 1));
    final b = _p('B', [_t('tb', '2026-10-01', [_a('y')])], end: DateTime(2026, 10, 20));
    final c = _p('C', [_t('tc', '2026-10-01', [_a('z')])]);
    final urgency = {'A': DateTime(2026, 10, 12), 'B': DateTime(2026, 10, 30)};
    final groups = projectActionGroups([c, b, a],
        filter: _all, sort: ActionsSort.milestone, urgencyOf: (p) => urgency[p.id]);
    expect(groups.map((g) => g.project.id).toList(), ['A', 'B', 'C']);
  });

  test('overdueActionCount : actions ouvertes des tâches échues, projets vivants seulement', () {
    final today = DateTime(2026, 10, 7);
    ProjectTask task(String id, String end, List<TaskAction> actions, {String status = 'pending'}) =>
        ProjectTask(id: id, title: id, startDate: DateTime(2026, 10, 1), endDate: DateTime.parse(end),
            actions: actions, status: status);
    final live = _p('live', [
      task('late', '2026-10-05', [_a('a'), _a('b', done: true)]),
      task('today', '2026-10-07', [_a('c')]),
      task('future', '2026-10-20', [_a('d')]),
      task('doneLate', '2026-10-01', [_a('e')], status: 'done'),
    ]);
    final paused = _p('paused', [task('late', '2026-10-05', [_a('x')])], paused: true);
    final noDue = _p('noDue', [_t('t', '2026-09-01', [_a('y')])]);
    expect(overdueActionCount([live, paused, noDue], today), 1);
    expect(overdueActionCount([], today), 0);
  });

  group('clients (projets racines)', () {
    Project proj(String id, {String? parent, List<ProjectTask>? tasks, bool paused = false}) => Project(
        id: id,
        title: id,
        startDate: DateTime(2026, 9, 1),
        createdBy: 'u',
        tasks: tasks ?? [_t('t$id', '2026-09-01', [_a('x')])],
        parentProjectId: parent,
        paused: paused);
    final cherubins = proj('Chérubins', tasks: []);
    final cm = proj('CM', parent: 'Chérubins');
    final sixieme = proj('6e', parent: 'Chérubins');
    final sof = proj('SOF');
    final orphan = proj('orphelin', parent: 'disparu');
    final pausedChild = proj('pause', parent: 'Vide', paused: true);
    final vide = proj('Vide', tasks: []);
    final all = [cherubins, cm, sixieme, sof, orphan, pausedChild, vide];

    test('rootProjectOf remonte jusqu\'à la racine ; parent inconnu = racine', () {
      expect(rootProjectOf(cm, all).id, 'Chérubins');
      expect(rootProjectOf(sof, all).id, 'SOF');
      expect(rootProjectOf(orphan, all).id, 'orphelin');
    });
    test('clientRoots : racines ayant un projet vivant dessous, triées', () {
      expect(clientRoots(all).map((p) => p.id).toList(), ['Chérubins', 'orphelin', 'SOF']);
    });
    ProjectTask due(String id, String end, List<TaskAction> actions, {String status = 'pending'}) =>
        ProjectTask(
            id: id, title: id, startDate: DateTime(2026, 9, 1), endDate: DateTime.parse(end),
            actions: actions, status: status);
    test('isOverdueTask : échéance avant aujourd\'hui, tâche ouverte seulement', () {
      final today = DateTime(2026, 10, 8, 15);
      expect(isOverdueTask(due('a', '2026-10-07', [_a('x')]), today), isTrue);
      expect(isOverdueTask(due('b', '2026-10-08', [_a('x')]), today), isFalse);
      expect(isOverdueTask(due('c', '2026-10-01', [_a('x')], status: 'done'), today), isFalse);
      expect(isOverdueTask(_t('d', '2026-09-01', [_a('x')]), today), isFalse);
    });
    test('projectActionGroups taskFilter : ne garde que les actions des tâches retenues', () {
      final p = proj('P', tasks: [
        due('late', '2026-10-01', [_a('l1'), _a('l2')]),
        due('soon', '2026-10-20', [_a('s1')]),
      ]);
      final g = projectActionGroups([p],
          filter: (_) => true, taskFilter: (t) => isOverdueTask(t, DateTime(2026, 10, 8)));
      expect(g.single.entries.map((e) => e.action.title).toList(), ['l1', 'l2']);
    });
    test('inClient : un client = ses projets seulement ; Perso = les actions sans projet', () {
      expect(inClient(null, cm, all), isTrue);
      expect(inClient(null, null, all), isTrue);
      expect(inClient('Chérubins', cm, all), isTrue);
      expect(inClient('Chérubins', sof, all), isFalse);
      // La démarche carte grise (action d'activité) n'apparaît plus sous Chérubins.
      expect(inClient('Chérubins', null, all), isFalse);
      expect(inClient(kPersoClientId, null, all), isTrue);
      expect(inClient(kPersoClientId, cm, all), isFalse);
    });
    test('isFolderProject : sans tâche et avec des enfants', () {
      expect(isFolderProject(cherubins, all), isTrue);
      expect(isFolderProject(vide, all), isTrue);
      expect(isFolderProject(sof, all), isFalse);
      expect(isFolderProject(cm, all), isFalse);
    });
    test('groupByFolder : enfants sous leur dossier, ordre d\'apparition, dossier jamais listé', () {
      final groups = groupByFolder([sof, cm, cherubins, orphan, sixieme, vide], all);
      expect(groups.map((g) => g.folder?.id).toList(), [null, 'Chérubins', null]);
      expect(groups[0].projects.map((p) => p.id).toList(), ['SOF']);
      expect(groups[1].projects.map((p) => p.id).toList(), ['CM', '6e']);
      expect(groups[2].projects.map((p) => p.id).toList(), ['orphelin']);
    });
    test('groupByRoot : une famille sous sa racine, même si la racine a ses propres tâches', () {
      final conseil = proj('Conseil');
      final lam4 = proj('LAM4', parent: 'Conseil');
      final everyone = [...all, conseil, lam4];
      final groups = groupByRoot([lam4, sof, cm, conseil, sixieme, vide], everyone);
      expect(groups.map((g) => g.folder?.id).toList(), ['Conseil', null, 'Chérubins']);
      // La racine qui a des tâches vient en tête de sa famille.
      expect(groups[0].projects.map((p) => p.id).toList(), ['Conseil', 'LAM4']);
      expect(groups[1].projects.map((p) => p.id).toList(), ['SOF']);
      expect(groups[2].projects.map((p) => p.id).toList(), ['CM', '6e']);
      // Un enfant seul affiché garde l'en-tête de sa famille.
      expect(groupByRoot([lam4], everyone).single.folder?.id, 'Conseil');
      // Une racine seule reste une carte simple.
      expect(groupByRoot([conseil], everyone).single.folder, isNull);
    });
  });

  group('À venir (date de début de la tâche)', () {
    final today = DateTime(2026, 10, 11, 21);
    ProjectTask task(String id, DateTime start, {String status = 'pending', bool done = false}) => ProjectTask(
        id: id, title: id, startDate: start, status: status,
        actions: [TaskAction(id: 'a-$id', title: 'action $id', done: done)]);
    final p = Project(
        id: 'p', title: 'P', startDate: DateTime(2026, 9, 1), createdBy: 'u',
        tasks: [
          task('nov', DateTime(2026, 11, 2)),
          task('auj', DateTime(2026, 10, 11)),
          task('demain', DateTime(2026, 10, 12)),
          task('jeudi', DateTime(2026, 10, 15)),
          task('faite', DateTime(2026, 10, 13), status: 'done'),
        ]);

    test('isUpcomingTask : début strictement après aujourd\'hui', () {
      expect(isUpcomingTask(p.tasks[1], today), isFalse);
      expect(isUpcomingTask(p.tasks[2], today), isTrue);
    });

    test('upcomingActions : tâches à venir ouvertes, par date de début', () {
      final ids = upcomingActions([p], filter: (_) => true, today: today).map((e) => e.task.id).toList();
      expect(ids, ['demain', 'jeudi', 'nov']);
    });

    test('startsToday : seulement le jour même du début', () {
      expect(startsToday(p.tasks[1], today), isTrue);
      expect(startsToday(p.tasks[2], today), isFalse);
      expect(startsToday(task('hier', DateTime(2026, 10, 10)), today), isFalse);
    });

    test('upcomingLabel : demain, jour de la semaine, puis date', () {
      expect(upcomingLabel(DateTime(2026, 10, 12), today), 'dès demain');
      expect(upcomingLabel(DateTime(2026, 10, 15), today), 'dès jeu. 15 oct.');
      expect(upcomingLabel(DateTime(2026, 11, 2), today), 'dès le 2 nov.');
    });
  });

  test('stopTargetCandidates : programme du jour d\'abord, puis échéance, jamais à venir', () {
    final today = DateTime(2026, 10, 11, 20);
    ProjectTask t(String id, DateTime start, DateTime end) => ProjectTask(
        id: id, title: id, startDate: start, endDate: end,
        actions: [TaskAction(id: 'a-$id', title: id, linkedActivityId: 'contenu')]);
    final p = Project(id: 'p', title: 'P', startDate: DateTime(2026, 9, 1), createdBy: 'u', tasks: [
      t('loin', DateTime(2026, 10, 1), DateTime(2026, 10, 30)),
      t('proche', DateTime(2026, 10, 1), DateTime(2026, 10, 12)),
      t('avenir', DateTime(2026, 10, 14), DateTime(2026, 10, 15)),
      t('prevu', DateTime(2026, 10, 1), DateTime(2026, 11, 2)),
    ]);
    final c = stopTargetCandidates([p], const [], 'contenu', today: today, plannedIds: {'a-prevu'});
    expect(c.map((x) => x.action.id).toList(), ['a-prevu', 'a-proche', 'a-loin']);
  });

  test('pickActionMoment : chrono → bloc en cours → retard → programme → prochain bloc → semaine → première', () {
    final today = DateTime(2026, 10, 27);
    ActionEntry en(TaskAction a, ProjectTask t) => (action: a, project: null, task: t, activity: null);
    final late = _a('Retard', due: DateTime(2026, 10, 24));
    final soon = _a('Bientôt', due: DateTime(2026, 10, 30));
    final plain = _a('Sans date');
    final prog = _a('Au programme');
    final t = _t('t', '2026-10-01', [plain, soon, late, prog]);
    final entries = [en(plain, t), en(soon, t), en(late, t), en(prog, t)];
    ScheduleBlock b(String id, String start, int dur, {String? actionId}) =>
        ScheduleBlock(id: id, startTime: start, durationMin: dur, title: id, category: 'project', actionId: actionId);
    // Chrono en cours sur une action.
    expect(pickActionMoment(entries, blocks: const [], nowMin: 600, today: today, runningActionId: prog.id)!.kind, ActionMomentKind.running);
    // Bloc en cours qui vise une action.
    final m1 = pickActionMoment(entries, blocks: [b('k', '09:30', 60, actionId: prog.id)], nowMin: 600, today: today)!;
    expect((m1.kind, m1.entry.action.title), (ActionMomentKind.block, 'Au programme'));
    // Sinon la plus en retard.
    final m2 = pickActionMoment(entries, blocks: [b('k', '14:00', 60, actionId: prog.id)], nowMin: 600, today: today)!;
    expect((m2.kind, m2.entry.action.title), (ActionMomentKind.late, 'Retard'));
    // Sans retard : au programme du jour avant la semaine.
    final noLate = entries.where((e) => e.action != late).toList();
    final m3 = pickActionMoment(noLate, blocks: [b('k', '14:00', 60, actionId: prog.id)], nowMin: 600, today: today)!;
    expect((m3.kind, m3.entry.action.title), (ActionMomentKind.today, 'Au programme'));
    final m4 = pickActionMoment(noLate, blocks: const [], nowMin: 600, today: today)!;
    expect((m4.kind, m4.entry.action.title), (ActionMomentKind.week, 'Bientôt'));
    final m5 = pickActionMoment([en(plain, t)], blocks: const [], nowMin: 600, today: today)!;
    expect(m5.kind, ActionMomentKind.rest);
    expect(pickActionMoment(const [], blocks: const [], nowMin: 600, today: today), isNull);
  });

  test('pickActionMoment par mode : Flemme = la plus courte (étapes d\'abord), En forme = la plus longue du projet en retard ; le bloc en cours gagne', () {
    final today = DateTime(2026, 10, 27);
    final pA = Project(id: 'A', title: 'A', startDate: DateTime(2026, 9, 1), createdBy: 'u');
    final pB = Project(id: 'B', title: 'B', startDate: DateTime(2026, 9, 1), createdBy: 'u');
    ActionEntry en(TaskAction a, Project p) => (action: a, project: p, task: null, activity: null);
    final longA = _a('Longue A', est: 120);
    final shortA = _a('Courte A', est: 10);
    final stepsB = TaskAction(title: 'Étapes B', estimatedMin: 15, checklist: [ChecklistItem(id: 'c', title: 'c')]);
    final longB = _a('Longue B', est: 90);
    final none = _a('Sans estimation');
    final entries = [en(none, pA), en(longA, pA), en(shortA, pA), en(stepsB, pB), en(longB, pB)];
    final low = pickActionMoment(entries, blocks: const [], nowMin: 600, today: today, mode: DayMode.low)!;
    expect((low.kind, low.entry.action.title), (ActionMomentKind.short, 'Étapes B'));
    final high = pickActionMoment(entries, blocks: const [], nowMin: 600, today: today, mode: DayMode.high, focusProjectId: 'B')!;
    expect((high.kind, high.entry.action.title), (ActionMomentKind.deep, 'Longue B'));
    final highAll = pickActionMoment(entries, blocks: const [], nowMin: 600, today: today, mode: DayMode.high)!;
    expect(highAll.entry.action.title, 'Longue A');
    final cur = ScheduleBlock(id: 'k', startTime: '09:30', durationMin: 60, title: 'k', category: 'project', actionId: none.id);
    expect(pickActionMoment(entries, blocks: [cur], nowMin: 600, today: today, mode: DayMode.low)!.kind, ActionMomentKind.block);
    expect(pickActionMoment(entries, blocks: const [], nowMin: 600, today: today, runningActionId: longA.id, mode: DayMode.low)!.kind, ActionMomentKind.running);
  });
}
