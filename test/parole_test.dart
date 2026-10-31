import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/parole.dart';

TaskAction act(String id, String focus, DateTime setAt, {DateTime? doneAt}) {
  final p = focus.split('-').map(int.parse).toList();
  return TaskAction(id: id, title: id, focusDate: DateTime(p[0], p[1], p[2]), focusSetAt: setAt, done: doneAt != null, doneAt: doneAt);
}

void main() {
  test('setter : poser le jour visé note quand', () {
    final a = TaskAction(title: 'x');
    expect(a.focusSetAt, isNull);
    a.focusDate = DateTime(2026, 11, 2);
    expect(a.focusSetAt, isNotNull);
    final first = a.focusSetAt;
    a.focusDate = DateTime(2026, 11, 2, 10); // même jour : inchangé
    expect(a.focusSetAt, first);
    a.focusDate = null;
    expect(a.focusSetAt, isNull);
    final back = TaskAction.from(act('y', '2026-11-02', DateTime(2026, 11, 1, 21)).toJson());
    expect(back.focusSetAt, DateTime(2026, 11, 1, 21));
  });

  test('candidates : seulement visées avant le début du jour', () {
    final eve = DateTime(2026, 11, 1, 21, 40);
    final morning = DateTime(2026, 11, 2, 9);
    final early = DateTime(2026, 11, 2, 4); // avant la bascule de 5 h
    final activity = Activity(id: 'a', domainId: 'd', name: 'A', ownActions: [
      act('1', '2026-11-02', eve),
      act('2', '2026-11-02', morning),
      act('3', '2026-11-02', early),
      act('4', '2026-11-03', eve),
    ]);
    final idx = paroleIndex(const [], [activity]);
    expect(paroleCandidates(idx, '2026-11-02', 300)..sort(), ['1', '3']);
  });

  test('tenue, pas tenue, déplacée, moins de 3', () {
    final eve = DateTime(2026, 11, 1, 21);
    final a1 = act('1', '2026-11-02', eve, doneAt: DateTime(2026, 11, 2, 10));
    final a2 = act('2', '2026-11-02', eve, doneAt: DateTime(2026, 11, 3, 1)); // avant la bascule de 5 h
    final a3 = act('3', '2026-11-02', eve, doneAt: DateTime(2026, 11, 2, 18));
    final idx = paroleIndex(const [], [Activity(id: 'a', domainId: 'd', name: 'A', ownActions: [a1, a2, a3])]);
    var paroles = freezeParole(const {}, '2026-11-02', paroleCandidates(idx, '2026-11-02', 300));
    expect(paroleOutcome(paroles['2026-11-02']!, idx, 300).held, isTrue);
    // L'une est déplacée au lendemain après le gel : elle reste dans la parole.
    a3
      ..done = false
      ..doneAt = null
      ..focusDate = DateTime(2026, 11, 3);
    expect(paroleOutcome(paroles['2026-11-02']!, idx, 300).held, isFalse);
    final stats = paroleStats(paroles, idx, 300, '2026-11-04');
    expect(stats.given, 1);
    expect(stats.held, 0);
    // Deux actions seulement : la journée ne compte pas.
    paroles = {'2026-11-05': const ParoleDay('2026-11-05', ['1', '2'])};
    expect(paroleStats(paroles, idx, 300, '2026-11-06').given, 0);
  });

  test('record d\'affilée et persistance', () {
    final eve = DateTime(2026, 10, 1);
    final acts = <TaskAction>[];
    final paroles = <String, ParoleDay>{};
    for (final d in ['2026-11-02', '2026-11-03', '2026-11-05']) {
      final ids = <String>[];
      for (var i = 0; i < 3; i++) {
        final a = act('$d-$i', d, eve, doneAt: DateTime.parse('${d}T12:00:00'));
        acts.add(a);
        ids.add(a.id);
      }
      paroles[d] = ParoleDay(d, ids);
    }
    final idx = paroleIndex(const [], [Activity(id: 'a', domainId: 'd', name: 'A', ownActions: acts)]);
    final s = paroleStats(paroles, idx, 300, '2026-11-06');
    expect(s.held, 3);
    expect(s.bestRun, 2);
    final round = parseParoles(parolesToJson(paroles));
    expect(round.keys.toSet(), paroles.keys.toSet());
  });

  test('propositions : pas faites aujourd\'hui, à re-viser, puis projets en retard', () {
    final setAt = DateTime(2026, 10, 1);
    final today = act('t', '2026-11-02', setAt);
    final old = act('o', '2026-10-30', setAt);
    final done = act('d', '2026-11-02', setAt, doneAt: DateTime(2026, 11, 2, 9));
    final late = TaskAction(id: 'p', title: 'p');
    final task = ProjectTask(id: 'k', title: 'Tâche', startDate: DateTime(2026, 10, 1), actions: [late]);
    final proj = Project(id: 'P', title: 'Projet', createdBy: 'user', startDate: DateTime(2026, 10, 1), tasks: [task]);
    final idx = paroleIndex([proj], [Activity(id: 'a', domainId: 'd', name: 'A', ownActions: [today, old, done])]);
    final props = paroleProposals(
      index: idx,
      projects: [proj],
      today: DateTime(2026, 11, 2),
      chosen: const {},
      nextActionOf: (p) => (task: task, action: late),
      isLive: (_) => true,
      isOverdue: (_, __) => true,
    );
    expect(props.map((p) => p.item.action.id).toList(), ['t', 'o', 'p']);
    expect(props.first.reason, 'pas faite aujourd\'hui');
    expect(props[1].reason, 'visée il y a 3 j · à re-viser');
  });
}
