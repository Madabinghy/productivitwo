import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/utils/project_patch.dart';

void main() {
  // État SERVEUR : la tâche t2 a été modifiée ailleurs (titre, nouvelle action).
  List<Map<String, dynamic>> server() => [
        {
          'id': 't1',
          'title': 'Séance 6e',
          'actions': [
            {'id': 'a1', 'title': 'Préparer', 'done': false},
            {'id': 'a2', 'title': 'Imprimer', 'done': false},
          ],
        },
        {
          'id': 't2',
          'title': 'Titre changé par le MCP',
          'actions': [
            {'id': 'b1', 'title': 'Ajoutée ailleurs', 'done': false},
          ],
        },
      ];

  test('replaceActionIn : ne remplace que l\'action visée, le reste du serveur survit', () {
    final out = replaceActionIn(server(), 't1', {'id': 'a1', 'title': 'Préparer', 'done': true})!;
    expect((out[0]['actions'] as List)[0]['done'], isTrue);
    expect((out[0]['actions'] as List)[1]['title'], 'Imprimer');
    expect(out[1]['title'], 'Titre changé par le MCP');
    expect((out[1]['actions'] as List).single['title'], 'Ajoutée ailleurs');
  });

  test('replaceActionIn : action ancienne en texte reconnue par son titre ; inconnue ajoutée', () {
    final raw = [
      {'id': 't', 'title': 'T', 'actions': ['Appeler', 'Écrire']},
    ];
    final out = replaceActionIn(raw, 't', {'id': 'x', 'title': 'Écrire', 'done': true})!;
    expect((out[0]['actions'] as List)[1], {'id': 'x', 'title': 'Écrire', 'done': true});
    expect((out[0]['actions'] as List)[0], 'Appeler');
    final added = replaceActionIn(raw, 't', {'id': 'n', 'title': 'Nouvelle'})!;
    expect((added[0]['actions'] as List).length, 3);
  });

  test('replaceActionIn / patchTaskFieldsIn : tâche disparue côté serveur → null', () {
    expect(replaceActionIn(server(), 'absente', {'id': 'a1'}), isNull);
    expect(patchTaskFieldsIn(server(), 'absente', {'status': 'done'}), isNull);
  });

  test('patchTaskFieldsIn : seuls les champs donnés changent', () {
    final out = patchTaskFieldsIn(server(), 't2', {'status': 'done'})!;
    expect(out[1]['status'], 'done');
    expect(out[1]['title'], 'Titre changé par le MCP');
    expect((out[1]['actions'] as List).length, 1);
    expect(out[0], server()[0]);
  });
}
