import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/groceries.dart';
import 'package:productivitwo_v1/utils/meal_compose.dart';
import 'package:productivitwo_v1/utils/meal_day.dart';
import 'package:productivitwo_v1/utils/meal_families.dart';
import 'package:productivitwo_v1/utils/meal_plan.dart';
import 'package:productivitwo_v1/widgets/meal_compose_sheet.dart';

PantryItem _p(String label, String aisle, {PantryState state = PantryState.have, String? boughtAt}) =>
    PantryItem(key: normLabel(label), label: label, aisle: aisle, state: state, boughtAt: boughtAt);

Groceries _pantry(List<PantryItem> items) => Groceries(pantry: {for (final p in items) p.key: p});

void main() {
  test('petit-déj : créneau, moment d\'un instant, sérialisation d\'un repas composé', () {
    expect(kMealMoments, ['petit-dej', 'midi', 'soir']);
    expect(momentOfMeal(DateTime(2026, 11, 4, 8)), 'petit-dej');
    expect(momentOfMeal(DateTime(2026, 11, 4, 10, 45)), 'midi');
    expect(momentOfMeal(DateTime(2026, 11, 4, 19)), 'soir');
    expect(currentMealMoment(DateTime(2026, 11, 4, 7)), 'petit-dej');
    const meal = PlannedMeal(title: 'Lardons · Pâtes', components: [
      MealComponent('Lardons', [kProteines]),
      MealComponent('Pâtes', [kFeculents]),
    ]);
    final back = PlannedMeal.from(meal.toJson())!;
    expect(back.isComposed, isTrue);
    expect(back.components, meal.components);
    expect(back.withAte('ok').components, meal.components);
    expect(back.withPortions(3).components, meal.components);
  });

  test('la grille compte midi et soir ; le petit-déj s\'affiche sans compter', () {
    final days = ['2026-11-02', '2026-11-03', '2026-11-04', '2026-11-05', '2026-11-06', '2026-11-07', '2026-11-08'];
    final week = MealWeek(slots: {mealKey('2026-11-04', 'petit-dej'): const PlannedMeal(title: 'Œufs · Pain').withAte('ok')});
    final v = mealWeekView(days: days, week: week, activities: const [], hits: const [], sessions: const [], now: DateTime(2026, 11, 4, 12), dayStartMin: 0);
    expect(v.cells[mealKey('2026-11-04', 'petit-dej')], MealCell.ok);
    expect(v.cells[mealKey('2026-11-03', 'petit-dej')], MealCell.none);
    expect(v.balanced, 0);
    expect(v.counted, 4); // lun., mar. midi et soir (le midi de mer. est en cours, vide)
  });

  test('isValidMeal, composedTitle, sidesOf', () {
    const cs = [
      MealComponent('Champignons', [kFibres]),
      MealComponent('Ail', [kAccompagnement]),
      MealComponent('Lardons', [kProteines]),
    ];
    expect(isValidMeal(cs), isTrue);
    expect(isValidMeal(const [MealComponent('Lardons', [kProteines]), MealComponent('Ail', [kAccompagnement])]), isFalse);
    expect(isValidMeal(const [MealComponent('Lentilles', [kFeculents, kProteines])]), isTrue);
    expect(composedTitle(cs), 'Lardons · Champignons');
    expect(sidesOf(cs), ['Ail']);
  });

  test('optionsFor : au petit-déj, seulement ce qui va le matin (ou appris)', () {
    final g = _pantry([
      _p('Pain de mie', 'Épicerie'),
      _p('Œufs', 'Frais'),
      _p('Côte de porc', 'Frais'),
      _p('Banane', 'Fruits et légumes'),
      _p('Haricots verts', 'Fruits et légumes'),
    ]);
    final lunch = optionsFor(g, 'midi');
    expect([for (final c in lunch[kProteines]!) c.label], ['Côte de porc', 'Œufs']);
    final bk = optionsFor(g, kBreakfast);
    expect([for (final c in bk[kProteines]!) c.label], ['Œufs']);
    expect([for (final c in bk[kFeculents]!) c.label], ['Pain de mie']);
    expect([for (final c in bk[kFibres]!) c.label], ['Banane']);
    final learned = optionsFor(g, kBreakfast, learned: {'côte de porc'});
    expect([for (final c in learned[kProteines]!) c.label], ['Côte de porc', 'Œufs']);
  });

  test('suggestMeals : 3 familles, produit frais à finir, pas la même protéine qu\'au repas d\'avant', () {
    final g = _pantry([
      _p('Lardons', 'Frais', boughtAt: '2026-10-30'),
      _p('Côte de porc', 'Frais', boughtAt: '2026-11-04'),
      _p('Pâtes', 'Épicerie'),
      _p('Champignons', 'Épicerie', state: PantryState.low),
      _p('Ail', 'Épicerie'),
    ]);
    final ideas = suggestMeals(g: g, ymd: '2026-11-04', moment: 'soir', history: const []);
    expect(ideas.first.title, 'Lardons · Pâtes · Champignons');
    expect(ideas.first.reasons, containsAll(['lardons à finir', 'champignons à finir']));
    expect(ideas.length, 3);
    // Lardons au midi : le soir propose une autre protéine en tête.
    final history = [const ComposedMeal('2026-11-04', 'midi', [MealComponent('Lardons', [kProteines]), MealComponent('Pâtes', [kFeculents])])];
    final evening = suggestMeals(g: g, ymd: '2026-11-04', moment: 'soir', history: history);
    expect(evening.first.title, isNot(startsWith('Lardons · Pâtes')));
  });

  testWidgets('Composer un repas : deux familles, Valider pose le repas du créneau', (tester) async {
    tester.view.physicalSize = const Size(780, 3200);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final st = AppState(domains: [Domain(id: 'd', name: 'Santé')], activities: [], sessions: [], habitProgress: []);
    final logic = AppLogic(st, () {})..dayStartMin = 0;
    logic.groceries = _pantry([_p('Côte de porc', 'Frais'), _p('Riz', 'Épicerie')]);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: MealComposeSheet(logic: logic, monday: '2026-11-02', ymd: '2026-11-04', moment: 'soir'))));
    await tester.pump();
    expect(find.text('Composer un repas'), findsOneWidget);
    expect(find.byKey(const Key('compose-idea')), findsOneWidget);
    await tester.tap(find.byKey(const Key('compose-proteines-côte de porc')));
    await tester.pump();
    expect(tester.widget<FilledButton>(find.byKey(const Key('compose-save'))).onPressed, isNull);
    await tester.tap(find.byKey(const Key('compose-feculents-riz')));
    await tester.pump();
    expect(find.text('Valider · 2 familles sur 3'), findsOneWidget);
    await tester.tap(find.byKey(const Key('compose-save')));
    await tester.pump();
    final slot = logic.mealWeek('2026-11-02').slots[mealKey('2026-11-04', 'soir')]!;
    expect(slot.title, 'Côte de porc · Riz');
    expect(slot.components.length, 2);
  });

  testWidgets('« Autre » : la brique tapée va au placard, s\'affiche choisie dans sa rangée', (tester) async {
    tester.view.physicalSize = const Size(780, 3200);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final st = AppState(domains: [Domain(id: 'd', name: 'Santé')], activities: [], sessions: [], habitProgress: []);
    final logic = AppLogic(st, () {})..dayStartMin = 0;
    logic.groceries = _pantry([_p('Lardons', 'Frais'), _p('Riz', 'Épicerie')]);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: MealComposeSheet(logic: logic, monday: '2026-11-02', ymd: '2026-11-04', moment: 'soir'))));
    await tester.pump();
    await tester.tap(find.byKey(const Key('compose-other-proteines')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('compose-other-text')), 'Côtes de porc');
    await tester.tap(find.text('Ajouter'));
    await tester.pumpAndSettle();
    expect(logic.groceries.pantry['côtes de porc']?.state, PantryState.have);
    expect(find.byKey(const Key('compose-proteines-côtes de porc')), findsOneWidget);
    expect(tester.widget<FilterChip>(find.byKey(const Key('compose-proteines-côtes de porc'))).selected, isTrue);
    await tester.tap(find.byKey(const Key('compose-feculents-riz')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('compose-save')));
    await tester.pump();
    expect(logic.mealWeek('2026-11-02').slots[mealKey('2026-11-04', 'soir')]!.title, 'Côtes de porc · Riz');
  });
}
