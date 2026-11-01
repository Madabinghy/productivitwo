import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/widgets/meal_sheet.dart';

void main() {
  testWidgets('Feuille Repas : le repas qui vient et « Mangé, équilibré »', (tester) async {
    tester.view.physicalSize = const Size(720, 4000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final rep = Activity(id: 'r', domainId: 'd', name: 'Repas équilibré', role: ActivityRole.generic, type: 'habit', goalMin: 1, habitFreq: HabitFreq.daily, habitTarget: 2, createdAt: DateTime(2026));
    final st = AppState(domains: [Domain(id: 'd', name: 'Santé')], activities: [rep], sessions: [], habitProgress: []);
    final logic = AppLogic(st, () {})..dayStartMin = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: MealSheet(logic: logic, sync: FirestoreSync(), recipes: Stream.value(const [])))));
    await tester.pump();
    expect(find.text('Rien de prévu'), findsOneWidget);
    expect(find.text('CETTE SEMAINE'), findsOneWidget);
    await tester.tap(find.text('✓ Mangé, équilibré'));
    await tester.pump();
    expect(st.habitHits.where((h) => h.habitId == 'r').length, 1);
    expect(find.text('✓ Mangé, équilibré'), findsOneWidget);
  });
}
