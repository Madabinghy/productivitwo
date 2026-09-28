import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';

void main() {
  test('TaskAction sans checklist : liste vide, JSON vide, compteurs à 0', () {
    final a = TaskAction.from({'title': 'x'});
    expect(a.checklist, isEmpty);
    expect(a.checklistTotal, 0);
    expect(a.toJson()['checklist'], isEmpty);
  });

  test('aller-retour toJson/from, id et done préservés', () {
    final a = TaskAction(title: 'Préparer la séance', checklist: [
      ChecklistItem(id: 'c1', title: 'Relire le brief', done: true, doneAt: DateTime(2026, 9, 28, 10)),
      ChecklistItem(id: 'c2', title: 'Imprimer le support'),
    ]);
    final back = TaskAction.from(a.toJson());
    expect(back.checklist.map((c) => c.id).toList(), ['c1', 'c2']);
    expect(back.checklist.first.done, isTrue);
    expect(back.checklist.first.doneAt, DateTime(2026, 9, 28, 10));
    expect(back.checklistDone, 1);
    expect(back.checklistTotal, 2);
  });

  test('items réduits à un titre (string) et items mal formés tolérés', () {
    final a = TaskAction.from({
      'title': 'x',
      'checklist': ['Appeler', {'title': 'Envoyer', 'done': 'oui'}, {'id': 'k'}],
    });
    expect(a.checklist.length, 3);
    expect(a.checklist[0].title, 'Appeler');
    expect(a.checklist[0].done, isFalse);
    expect(a.checklist[1].done, isFalse); // 'oui' n'est pas true
    expect(a.checklist[2].title, '');
    expect(a.checklist[0].id, isNotEmpty);
  });

  test('ProjectTask embarque les checklists de ses actions', () {
    final t = ProjectTask.from({
      'title': 'T',
      'startDate': '2026-09-28',
      'actions': [
        {'title': 'a', 'checklist': ['i1', 'i2']},
      ],
    });
    expect(t.actions.single.checklistTotal, 2);
    expect(ProjectTask.from(t.toJson()).actions.single.checklist[1].title, 'i2');
  });
}
