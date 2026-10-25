import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';

void main() {
  test('TaskAction.note : aller-retour JSON, vide = absent', () {
    final a = TaskAction(title: 'Imprimer', note: 'Fiche 01 recto verso ×19 · pas le dossier « Ancienne version »');
    final back = TaskAction.from(a.toJson());
    expect(back.note, a.note);
    expect(TaskAction(title: 'x', note: '  ').toJson().containsKey('note'), isFalse);
    expect(TaskAction.from({'id': 'i', 'title': 't', 'note': ''}).note, isNull);
    expect(TaskAction.from({'id': 'i', 'title': 't'}).note, isNull);
  });
}
