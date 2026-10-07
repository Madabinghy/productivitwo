import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/utils/default_estimate.dart';

void main() {
  test('defaultEstimateFor : règles par verbe / objet, accents ignorés', () {
    expect(defaultEstimateFor('Imprimer à l\'école : contrôle + fiche de séquence'), 10);
    expect(defaultEstimateFor('Fiche de séquence Pages du 9 nov'), 15);
    expect(defaultEstimateFor('Corriger les copies des CM1-CM2'), 45);
    expect(defaultEstimateFor('Saisir notes et ligues dans le fichier de suivi'), 10);
    expect(defaultEstimateFor('Déposer la fiche sur Teams'), 5);
    expect(defaultEstimateFor('Importer les images dans le Kahoot'), 20);
    expect(defaultEstimateFor('Rédiger le quiz d\'évaluation'), 45);
    expect(defaultEstimateFor('Voir avec Aurélie'), isNull);
    expect(defaultEstimateFor('Supports', contexts: ['@impression']), 10);
    expect(defaultEstimateFor('Dérouler la séance (13h15–15h00)'), isNull);
    expect(defaultEstimateFor('  '), isNull);
  });
}
