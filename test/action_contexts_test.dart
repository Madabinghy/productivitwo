import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';

void main() {
  test('action MCP (contexts seul) : context et primaryContext se déduisent', () {
    final a = TaskAction.from({'title': 'Fiche géométrie', 'contexts': ['@ordinateur']});
    expect(a.context, '@ordinateur');
    expect(a.contexts, ['@ordinateur']);
    expect(a.primaryContext, '@ordinateur');
    expect(a.allContexts, {'@ordinateur'});
  });

  test('action ancienne (context seul) : contexts se remplit — rien ne se perd', () {
    final a = TaskAction.from({'title': 'x', 'context': '@maison'});
    expect(a.contexts, ['@maison']);
    expect(a.primaryContext, '@maison');
    expect(a.toJson()['contexts'], ['@maison']);
  });

  test('les deux champs : le multi prime, sans doublon', () {
    final a = TaskAction.from({'title': 'x', 'context': '@bureau', 'contexts': ['@ordinateur', '@bureau']});
    expect(a.primaryContext, '@ordinateur');
    expect(a.allContexts, {'@ordinateur', '@bureau'});
  });

  test('sans contexte : null partout', () {
    final a = TaskAction.from({'title': 'x', 'context': '', 'contexts': []});
    expect(a.primaryContext, isNull);
    expect(a.allContexts, isEmpty);
  });
}
