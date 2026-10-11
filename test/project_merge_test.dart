import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/project_merge.dart';

void main() {
  Map<String, dynamic> t(String id, String title) => {'id': id, 'title': title};

  test('mergeTaskLists : seule la tâche modifiée ici remplace celle du serveur', () {
    final server = [t('a', 'A (changé ailleurs)'), t('b', 'B'), t('c', 'C (ajoutée ailleurs)')];
    final local = [t('a', 'A'), t('b', 'B modifié ici')];
    final out = mergeTaskLists(
        server: server, local: local, changed: (id) => id == 'b', known: {'a', 'b'});
    expect(out.map((x) => x['title']).toList(), ['A (changé ailleurs)', 'B modifié ici', 'C (ajoutée ailleurs)']);
  });

  test('mergeTaskLists : supprimée ici → retirée ; supprimée ailleurs → pas ressuscitée', () {
    final server = [t('a', 'A'), t('b', 'B')];
    // 'a' supprimée ici ; 'x' (connue, inchangée) supprimée ailleurs.
    final local = [t('b', 'B'), t('x', 'X')];
    final out = mergeTaskLists(
        server: server, local: local, changed: (_) => false, known: {'a', 'b', 'x'});
    expect(out.map((x) => x['id']).toList(), ['b']);
  });

  test('mergeTaskLists : tâche créée ici ajoutée, ordre local respecté', () {
    final out = mergeTaskLists(
        server: [t('a', 'A'), t('b', 'B')],
        local: [t('b', 'B'), t('n', 'Nouvelle'), t('a', 'A')],
        changed: (id) => id == 'n',
        known: {'a', 'b'});
    expect(out.map((x) => x['id']).toList(), ['b', 'n', 'a']);
  });

  test('mergeTaskLists : sans ids connus, comportement historique (la liste locale fait foi)', () {
    final out = mergeTaskLists(
        server: [t('a', 'A serveur'), t('z', 'Z')], local: [t('a', 'A local')], changed: (_) => false);
    expect(out, [t('a', 'A local')]);
  });

  test('mergeProjectFields : champ modifié ici → local, sinon serveur', () {
    final out = mergeProjectFields(
      server: {'id': 'p', 'title': 'Titre serveur', 'status': 'active', 'tasks': []},
      local: {'id': 'p', 'title': 'Ancien titre', 'status': 'done'},
      base: {'id': '"p"', 'title': '"Ancien titre"', 'status': '"active"'},
    );
    expect(out['title'], 'Titre serveur');
    expect(out['status'], 'done');
  });

  test('empreintes : une tâche chargée puis modifiée est détectée, une copie hérite', () {
    final p = Project.from({
      'id': 'p',
      'title': 'P',
      'startDate': '2026-10-01',
      'tasks': [
        {'id': 't1', 'title': 'T1', 'startDate': '2026-10-01'},
        {'id': 't2', 'title': 'T2', 'startDate': '2026-10-01'},
      ],
    });
    markProjectLoaded(p);
    expect(taskChangedLocally(p.tasks[0]), isFalse);
    p.tasks[1].title = 'T2 modifié';
    expect(taskChangedLocally(p.tasks[1]), isTrue);
    expect(knownTaskIdsOf(p.tasks), {'t1', 't2'});
    final copy = ProjectTask.from(p.tasks[0].toJson());
    expect(taskChangedLocally(copy), isTrue);
    copyTaskBase(p.tasks[0], copy);
    expect(taskChangedLocally(copy), isFalse);
  });
}
