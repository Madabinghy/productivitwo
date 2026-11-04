import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/utils/groceries.dart';
import 'package:productivitwo_v1/utils/meal_families.dart';

void main() {
  test('guessFamilies : le mot-clé le plus long gagne (mêmes réponses que meal_families.test.mjs)', () {
    final cases = <String, List<String>>{
      'Côte de porc': [kProteines],
      'Lardons fumés': [kProteines],
      'Œufs bio x6': [kProteines],
      'Pâtes farfalle 500g': [kFeculents],
      'Riz basmati': [kFeculents],
      'Pommes de terre 1,35 kg': [kFeculents],
      'Banane plantain': [kFeculents],
      'Fruit à pain': [kFeculents],
      'Haricots verts': [kFibres],
      'Champignons de Paris émincés': [kFibres],
      'Pommes Golden': [kFibres],
      'Banane': [kFibres],
      'Lentilles corail': [kFeculents, kProteines],
      'Haricots rouges': [kFeculents, kProteines],
      'Sauce bolognaise 420G': [kAccompagnement],
      'Concentré de tomate tube': [kAccompagnement],
      'Ail violet': [kAccompagnement],
      'Oignon jaune': [kAccompagnement],
      'Moutarde bocal': [kAccompagnement],
      'Lait de coco': [kAccompagnement],
      'Tartelettes fraise': [kAccompagnement],
    };
    for (final e in cases.entries) {
      expect(guessFamilies(e.key), e.value, reason: e.key);
    }
    expect(guessFamilies('Truc inconnu'), isEmpty);
  });

  test('familiesFor : retenue, devinée, hors alimentaire, accompagnement par défaut', () {
    const g = Groceries(
      families: {'tofu fumé': 'proteines', 'galettes': 'feculents,proteines'},
      pantry: {'gel wc': PantryItem(key: 'gel wc', label: 'Gel WC', aisle: 'Ménager')},
    );
    expect(familiesFor(g, 'Tofu fumé'), [kProteines]);
    expect(familiesFor(g, 'Galettes'), [kFeculents, kProteines]);
    expect(familiesFor(g, 'Gel WC'), isEmpty);
    expect(familiesFor(g, 'Eau de source'), isEmpty); // rayon Boissons
    expect(familiesFor(g, 'Steak haché'), [kProteines]);
    expect(familiesFor(g, 'Truc inconnu'), [kAccompagnement]);
  });

  test('parseFamilies / formatFamilies : propre, accompagnement exclusif', () {
    expect(parseFamilies('feculents,proteines'), [kFeculents, kProteines]);
    expect(parseFamilies(['fibres', 'bidon', 'fibres']), [kFibres]);
    expect(parseFamilies('accompagnement,proteines'), [kProteines]);
    expect(formatFamilies([kAccompagnement]), 'accompagnement');
    expect(parseFamilies(null), isEmpty);
  });

  test('pantryByFamily : ce qu\'on a, par famille, deux familles = deux places', () {
    const g = Groceries(pantry: {
      'lardons': PantryItem(key: 'lardons', label: 'Lardons', aisle: 'Frais'),
      'riz': PantryItem(key: 'riz', label: 'Riz', aisle: 'Épicerie'),
      'lentilles': PantryItem(key: 'lentilles', label: 'Lentilles', aisle: 'Épicerie'),
      'champignons': PantryItem(key: 'champignons', label: 'Champignons', aisle: 'Épicerie', state: PantryState.low),
      'pâtes': PantryItem(key: 'pâtes', label: 'Pâtes', aisle: 'Épicerie', state: PantryState.out),
      'ail': PantryItem(key: 'ail', label: 'Ail', aisle: 'Épicerie'),
      'lessive': PantryItem(key: 'lessive', label: 'Lessive', aisle: 'Ménager'),
    });
    final by = pantryByFamily(g);
    List<String> labels(String f) => [for (final p in by[f]!) p.label];
    expect(labels(kProteines), ['Lardons', 'Lentilles']);
    expect(labels(kFeculents), ['Lentilles', 'Riz']); // Pâtes : plus rien
    expect(labels(kFibres), ['Champignons']); // bientôt fini compte
    expect(labels(kAccompagnement), ['Ail']);
  });

  test('withFamilies : retient, vide = revient à l\'automatique ; aller-retour JSON', () {
    var g = withFamilies(const Groceries(), 'Tartelettes fraise', [kFibres]);
    expect(familiesFor(g, 'tartelettes fraise'), [kFibres]);
    final back = parseGroceries(g.toJson());
    expect(back.families, {'tartelettes fraise': 'fibres'});
    g = withFamilies(g, 'Tartelettes fraise', const []);
    expect(g.families, isEmpty);
    expect(familiesFor(g, 'Tartelettes fraise'), [kAccompagnement]);
  });
}
