import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/widgets/sport_sheet.dart';

void main() {
  testWidgets('Feuille Sport : la semaine, les répétitions, le lancement', (tester) async {
    tester.view.physicalSize = const Size(720, 7000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final now = DateTime.now();
    final run = Activity(id: 'courir', domainId: 'sp', name: 'Courir', role: ActivityRole.generic, type: 'time', goalMin: 7, createdAt: DateTime(2026, 1, 1));
    final pompes = Activity(
        id: 'pompes', domainId: 'sp', name: 'Pompes', role: ActivityRole.generic, type: 'habit', goalMin: 1, habitFreq: HabitFreq.daily, habitTarget: 20, createdAt: DateTime(2026, 1, 1));
    final st = AppState(
      domains: [Domain(id: 'sp', name: 'Sport')],
      activities: [run, pompes],
      sessions: [Session(activityId: 'courir', startAt: now.subtract(const Duration(minutes: 40)), endAt: now.subtract(const Duration(minutes: 5)))],
      habitProgress: [],
    );
    st.habitHits.addAll([for (var i = 0; i < 12; i++) HabitHit(habitId: 'pompes', ts: now.subtract(Duration(minutes: 30 - i)))]);
    final logic = AppLogic(st, () {})..dayStartMin = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SportSheet(logic: logic, sync: FirestoreSync()))));
    await tester.pump();
    expect(find.text('1 séance cette semaine'), findsOneWidget);
    expect(find.text('35 min actives'), findsOneWidget);
    expect(find.text('Pompes'), findsOneWidget);
    expect(find.textContaining('12 / 140'), findsOneWidget);
    expect(find.text('Lancer une séance'), findsOneWidget);
  });
}
