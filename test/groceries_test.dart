import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/finances.dart';
import 'package:productivitwo_v1/utils/groceries.dart';

void main() {
  test('le ticket réparti par domaine, au centime près', () {
    const lines = [
      CheckoutLine(label: 'Pâtes', domainId: 'sante', price: 200),
      CheckoutLine(label: 'Bœuf', domainId: 'sante', price: 600),
      CheckoutLine(label: 'Lessive', domainId: 'int', price: 800),
      CheckoutLine(label: 'Tringle', domainId: 'int', projectId: 'dressing'),
    ];
    final s = splitTicket(6340, lines);
    expect(s.fold<int>(0, (a, x) => a + x.amount), 6340);
    expect(s.length, 3);
    final sante = s.firstWhere((x) => x.domainId == 'sante' && x.projectId == null);
    expect(sante.labels, ['Pâtes', 'Bœuf']);
    // Poids : 800 / 800 / 533 (moyenne pour la tringle sans prix).
    expect(sante.amount, closeTo(6340 * 800 / 2133.33, 2));
    // Sans aucun prix : parts égales.
    final eq = splitTicket(1000, const [CheckoutLine(label: 'a', domainId: 'x'), CheckoutLine(label: 'b', domainId: 'y')]);
    expect(eq.map((x) => x.amount), [500, 500]);
  });

  test('corriger une part garde le total', () {
    final s = splitTicket(1000, const [
      CheckoutLine(label: 'a', domainId: 'x'),
      CheckoutLine(label: 'b', domainId: 'y'),
      CheckoutLine(label: 'c', domainId: 'z'),
    ]);
    final t = adjustShare(s, 0, 600);
    expect(t[0].amount, 600);
    expect(t.fold<int>(0, (a, x) => a + x.amount), 1000);
  });

  test('les prix appris s\'affinent, coût d\'un plat', () {
    const lines = [CheckoutLine(label: 'Pâtes', domainId: 's'), CheckoutLine(label: 'Tomates', domainId: 's')];
    final shares = splitTicket(400, lines);
    final p = learnedPrices(lines, shares, const {'pâtes': GroceryMemory(price: 100)});
    expect(p['tomates'], 200);
    expect(p['pâtes'], 150);
    final c = dishCost(['Pâtes', 'Tomates', 'Basilic'], {'pâtes': const GroceryMemory(price: 150), 'tomates': const GroceryMemory(price: 200)});
    expect(c!.cents, 350);
    expect(c.known, 2);
    expect(c.total, 3);
  });

  test('aller-retour JSON et dépenses par domaine', () {
    final g = parseGroceries(const Groceries(
      items: {'1': GroceryItem(id: '1', label: 'Ampoules', qty: '×3', domainId: 'int', store: 'Bricolage', inBasket: true)},
      memory: {'ampoules': GroceryMemory(domainId: 'int', store: 'Bricolage', price: 899)},
    ).toJson());
    expect(g.items['1']!.store, 'Bricolage');
    expect(g.items['1']!.inBasket, isTrue);
    expect(g.memory['ampoules']!.price, 899);
    expect(g.stores, kDefaultStores);
    expect(guessFor(g, ' ampoules ').store, 'Bricolage');

    final f = const Finances().copyWith(expenses: {
      'a': const Expense(id: 'a', ymd: '2026-11-02', amount: 4120, envelopeId: 'courses', domainId: 'sante'),
      'b': const Expense(id: 'b', ymd: '2026-11-01', amount: 770, envelopeId: 'courses', domainId: 'int', projectId: 'dressing', items: ['Tringle']),
      'c': const Expense(id: 'c', ymd: '2026-11-01', amount: 800, envelopeId: 'sorties'),
    });
    expect(spentByDomain(f, '2026-11-02').map((e) => e.key), ['sante', '', 'int']);
    expect(spentByProject(f, '2026-11-02').single.value, 770);
    expect(parseFinances(f.toJson()).expenses['b']!.items, ['Tringle']);
  });

  test('ajouter sans doublon, passer en caisse : dépenses, liste vidée, prix retenus', () async {
    final st = AppState(domains: [], activities: [], sessions: [], habitProgress: []);
    final logic = AppLogic(st, () {})..dayStartMin = 0;
    final a = await logic.addGrocery(label: 'Lessive', domainId: 'int');
    final b = await logic.addGrocery(label: 'lessive ');
    expect(b.id, a.id);
    final c = await logic.addGrocery(label: 'Pâtes', domainId: 'sante');
    final lines = [
      CheckoutLine(label: a.label, domainId: a.domainId, itemId: a.id),
      CheckoutLine(label: c.label, domainId: c.domainId, itemId: c.id),
      const CheckoutLine(label: 'Tomates', domainId: 'sante'),
    ];
    final shares = splitTicket(3000, lines);
    final ids = await logic.checkoutGroceries(lines: lines, shares: shares, store: 'Supermarché');
    expect(ids.length, 2);
    expect(logic.groceries.items, isEmpty);
    expect(logic.finances.expenses.values.map((x) => x.domainId).toSet(), {'int', 'sante'});
    expect(logic.groceries.memory['lessive']!.price, 1000);
    expect(logic.groceries.memory['lessive']!.domainId, 'int');
    // La prochaine « lessive » reprend son domaine.
    final d = await logic.addGrocery(label: 'Lessive');
    expect(d.domainId, 'int');
  });
}
