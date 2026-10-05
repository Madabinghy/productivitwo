import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/actions_logic.dart';

TaskAction _a(String title, {List<String>? ctx, int? est, bool done = false, String? linked}) =>
    TaskAction(title: title, contexts: ctx, estimatedMin: est, done: done, linkedActivityId: linked);

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
}
