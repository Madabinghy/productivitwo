import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/engagement_stats.dart' show ymdOf;
import 'package:productivitwo_v1/utils/meal_plan.dart';
import 'package:productivitwo_v1/widgets/meal_week_sheet.dart';

void main() {
  testWidgets('Repas de la semaine : restes et courses', (tester) async {
    tester.view.physicalSize = const Size(720, 4000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final st = AppState(domains: [], activities: [], sessions: [], habitProgress: []);
    final logic = AppLogic(st, () {})..dayStartMin = 0;
    final t = logic.livedToday;
    final monday = DateTime(t.year, t.month, t.day - (t.weekday - 1));
    final bolo = Recipe(title: 'Bolognaise', portions: 2, ingredients: [ShoppingItem(label: 'Pâtes', qty: '500 g')]);
    await logic.setMeal(ymdOf(monday), mealKey(ymdOf(monday), 'soir'), PlannedMeal(recipeId: bolo.id, title: bolo.title, portions: 2));
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: MealWeekSheet(logic: logic, sync: FirestoreSync(), recipes: Stream.value([bolo])))));
    await tester.pump();
    expect(find.text('Bolognaise'), findsOneWidget);
    expect(find.text('↳ les restes · Bolognaise'), findsOneWidget);
    expect(find.text('Liste de courses · 1 à prendre'), findsOneWidget);

    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ShoppingSheet(logic: logic, monday: ymdOf(monday), recipes: [bolo]))));
    expect(find.text('Pâtes'), findsOneWidget);
    expect(find.text('500 g'), findsOneWidget);
    await tester.tap(find.byType(Checkbox).first);
    await tester.pump();
    expect(find.text('DANS LE PANIER · 1'), findsOneWidget);
  });
}
