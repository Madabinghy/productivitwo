import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';

void main() {
  group('ProjectTask.estimatedMin', () {
    test('absent → null, plannedMin retombe sur 45', () {
      final t = ProjectTask.from({
        'id': 't1',
        'title': 'Tâche',
        'startDate': '2026-09-28',
      });
      expect(t.estimatedMin, isNull);
      expect(t.plannedMin, kDefaultTaskEstimatedMin);
      expect(t.toJson()['estimatedMin'], isNull);
    });

    test('aller-retour toJson/from', () {
      final t = ProjectTask(
        title: 'Tâche',
        startDate: DateTime(2026, 9, 28),
        estimatedMin: 90,
      );
      final back = ProjectTask.from(t.toJson());
      expect(back.estimatedMin, 90);
      expect(back.plannedMin, 90);
    });

    test('valeurs invalides ignorées (0, négatif, texte)', () {
      for (final raw in [0, -10, 'abc', 12.0]) {
        final t = ProjectTask.from({
          'title': 'x',
          'startDate': '2026-09-28',
          'estimatedMin': raw,
        });
        expect(t.estimatedMin, raw == 12.0 ? 12 : isNull, reason: '$raw');
      }
    });
  });

  group('TaskAction.estimatedMin', () {
    test('absent → null ; aller-retour', () {
      expect(TaskAction.from({'title': 'a'}).estimatedMin, isNull);
      final a = TaskAction(title: 'a', estimatedMin: 15);
      expect(TaskAction.from(a.toJson()).estimatedMin, 15);
    });

    test('action legacy en string dans une tâche → pas d\'estimation', () {
      final t = ProjectTask.from({
        'title': 'x',
        'startDate': '2026-09-28',
        'actions': ['faire', {'title': 'écrire', 'estimatedMin': 30}],
      });
      expect(t.actions[0].estimatedMin, isNull);
      expect(t.actions[1].estimatedMin, 30);
    });
  });
}
