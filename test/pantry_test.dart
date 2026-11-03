import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/utils/groceries.dart';
import 'package:productivitwo_v1/utils/pantry.dart';

void main() {
  test('guessAisle : le rayon par les mots, le plus spécifique d\'abord', () {
    expect(guessAisle('Pâtes farfalle 500g'), 'Épicerie');
    expect(guessAisle('Sauce tomate'), 'Épicerie');
    expect(guessAisle('Tomates cerises'), 'Fruits et légumes');
    expect(guessAisle('Jus d\'orange'), 'Boissons');
    expect(guessAisle('Gâteau au chocolat'), 'Épicerie'); // « eau » n'est pas un mot de « gâteau »
    expect(guessAisle('Œufs bio x6'), 'Frais');
    expect(guessAisle('Crème hydratante'), 'Hygiène');
    expect(guessAisle('Crème fraîche'), 'Frais');
    expect(guessAisle('Liquide vaisselle'), 'Ménager');
    expect(guessAisle('Petits pois'), 'Fruits et légumes');
    expect(guessAisle('Lait de coco'), 'Épicerie');
    expect(guessAisle('Vinaigre balsamique'), 'Épicerie');
    expect(guessAisle('Truc inconnu'), isNull);
  });

  test('aisleFor : mot retenu, puis placard, puis deviné, puis Autre', () {
    const g = Groceries(
      memory: {'pâtes': GroceryMemory(aisle: 'Vrac')},
      pantry: {'tofu fumé': PantryItem(key: 'tofu fumé', label: 'Tofu fumé', aisle: 'Bio')},
    );
    expect(aisleFor(g, 'Pâtes'), 'Vrac');
    expect(aisleFor(g, 'tofu fumé'), 'Bio');
    expect(aisleFor(g, 'Riz'), 'Épicerie');
    expect(aisleFor(g, 'Truc'), kOtherAisle);
  });

  test('états, achat, besoins', () {
    var g = const Groceries();
    g = withPantryState(g, 'Riz', PantryState.low);
    g = withPantryState(g, 'Huile d\'olive', PantryState.out);
    g = withPantryState(g, 'Café', PantryState.have);
    expect(g.pantry['riz']!.aisle, 'Épicerie');
    expect(nextPantryState(PantryState.out), PantryState.have);
    expect(pantryNeeds(g).map((p) => p.label), ['Huile d\'olive', 'Riz']);
    g = g.copyWith(items: {'a': const GroceryItem(id: 'a', label: 'riz')});
    expect(pantryNeeds(g).map((p) => p.label), ['Huile d\'olive']); // déjà sur la liste
    g = afterPurchase(g, ['Huile d\'olive', 'Bananes'], '2026-11-03');
    expect(g.pantry['huile d\'olive']!.state, PantryState.have);
    expect(g.pantry['bananes']!.aisle, 'Fruits et légumes');
    expect(g.pantry['bananes']!.boughtAt, '2026-11-03');
    expect(pantryByAisle(g).map((e) => e.key), ['Épicerie', 'Fruits et légumes']);
  });

  test('rayons : ajouter avant Autre, renommer partout, fusionner, retirer', () {
    var g = withPantryState(const Groceries(), 'Riz', PantryState.have);
    g = g.copyWith(
      items: {'a': const GroceryItem(id: 'a', label: 'Pâtes', aisle: 'Épicerie')},
      memory: {'pâtes': const GroceryMemory(aisle: 'Épicerie', price: 120)},
    );
    g = withAisleAdded(g, 'Bébé');
    expect(g.aisles.sublist(g.aisles.length - 2), ['Bébé', 'Autre']);
    expect(withAisleAdded(g, 'bebe').aisles.length, g.aisles.length);
    g = withAisleRenamed(g, 'Épicerie', 'Épicerie salée');
    expect(g.aisles.first, 'Épicerie salée');
    expect(g.pantry['riz']!.aisle, 'Épicerie salée');
    expect(g.items['a']!.aisle, 'Épicerie salée');
    expect(g.memory['pâtes']!.aisle, 'Épicerie salée');
    expect(g.memory['pâtes']!.price, 120);
    final merged = withAisleRenamed(g, 'Épicerie salée', 'Frais');
    expect(merged.aisles.contains('Épicerie salée'), isFalse);
    expect(merged.pantry['riz']!.aisle, 'Frais');
    final removed = withAisleRemoved(g, 'Épicerie salée');
    expect(removed.pantry['riz']!.aisle, kOtherAisle);
    expect(withAisleRemoved(g, kOtherAisle).aisles, g.aisles);
  });

  test('aisleSplit : au poids des prix, somme juste', () {
    final split = aisleSplit(1000, ['Pâtes', 'Lessive', 'Riz'], {'pâtes': 200, 'lessive': 600, 'riz': 200}, const Groceries());
    expect(split, {'Épicerie': 400, 'Ménager': 600});
    final odd = aisleSplit(100, ['Riz', 'Lait', 'Savon'], const {}, const Groceries());
    expect(odd.values.fold<int>(0, (a, b) => a + b), 100);
  });

  test('aller-retour JSON', () {
    var g = withPantryState(const Groceries(), 'Café', PantryState.low);
    g = g.copyWith(pantry: {'café': g.pantry['café']!.copyWith(staple: true, boughtAt: '2026-11-01')});
    g = withAisleAdded(g, 'Bébé');
    final back = parseGroceries(g.toJson());
    expect(back.pantry['café']!.staple, isTrue);
    expect(back.pantry['café']!.state, PantryState.low);
    expect(back.aisles.contains('Bébé'), isTrue);
    expect(parseGroceries({}).aisles, kDefaultAisles);
  });
}
