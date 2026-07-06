// Tests des invariants de sérialisation des modèles Gantt (pur Dart, sans
// Firebase). Remplace le stub du template Flutter (compteur jamais monté).

import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';

void main() {
  group('ProjectTask.from — compat actions string[] et TaskAction maps', () {
    test('actions au format legacy string[] → TaskAction non faites', () {
      final t = ProjectTask.from({
        'title': 'Tâche legacy',
        'startDate': '2026-07-01',
        'actions': ['Étape A', 'Étape B'],
      });
      expect(t.actions.length, 2);
      expect(t.actions[0].title, 'Étape A');
      expect(t.actions[0].done, isFalse);
      expect(t.actions[0].id, isNotEmpty);
    });

    test('actions au format map → champs préservés', () {
      final t = ProjectTask.from({
        'id': 'task-1',
        'title': 'Tâche moderne',
        'startDate': '2026-07-01',
        'status': 'pending',
        'actions': [
          {
            'id': 'a1',
            'title': 'Faite',
            'done': true,
            'doneAt': '2026-07-02T10:00:00.000',
            'linkedActivityId': 'act-9',
          },
          {'id': 'a2', 'title': 'À faire'},
        ],
      });
      expect(t.actions[0].id, 'a1');
      expect(t.actions[0].done, isTrue);
      expect(t.actions[0].doneAt, isNotNull);
      expect(t.actions[0].linkedActivityId, 'act-9');
      expect(t.actions[1].done, isFalse);
    });

    test('done déduit de doneAt quand le bool manque (docs anciens)', () {
      final a = TaskAction.from({
        'title': 'Implicite',
        'doneAt': '2026-07-02T10:00:00.000',
      });
      expect(a.done, isTrue);
    });

    test('round-trip toJson → from sans perte', () {
      final t = ProjectTask(
        title: 'Round-trip',
        startDate: DateTime(2026, 7, 1),
        endDate: DateTime(2026, 7, 15),
        status: 'done',
        todayFlag: true,
        actions: [TaskAction(title: 'x', done: true, doneAt: DateTime(2026, 7, 3))],
      );
      final back = ProjectTask.from(t.toJson());
      expect(back.id, t.id);
      expect(back.title, t.title);
      expect(back.status, 'done');
      expect(back.todayFlag, isTrue);
      expect(back.endDate, DateTime(2026, 7, 15));
      expect(back.actions.single.done, isTrue);
      expect(back.actions.single.id, t.actions.single.id);
    });

    test('actions absentes ou vides → liste vide, pas de crash', () {
      expect(
          ProjectTask.from({'title': 't', 'startDate': '2026-07-01'})
              .actions,
          isEmpty);
      expect(
          ProjectTask.from(
              {'title': 't', 'startDate': '2026-07-01', 'actions': []}).actions,
          isEmpty);
    });
  });
}
