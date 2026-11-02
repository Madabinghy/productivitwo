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
    // Ancré en début de journée : juste après minuit, « il y a 40 min » tombait la veille (autre semaine le lundi).
    final t0 = DateTime(now.year, now.month, now.day, 0, 1);
    final run = Activity(id: 'courir', domainId: 'sp', name: 'Courir', role: ActivityRole.generic, type: 'time', goalMin: 7, createdAt: DateTime(2026, 1, 1));
    final pompes = Activity(
        id: 'pompes', domainId: 'sp', name: 'Pompes', role: ActivityRole.generic, type: 'habit', goalMin: 1, habitFreq: HabitFreq.daily, habitTarget: 20, createdAt: DateTime(2026, 1, 1));
    final st = AppState(
      domains: [Domain(id: 'sp', name: 'Sport')],
      activities: [run, pompes],
      sessions: [Session(activityId: 'courir', startAt: t0, endAt: t0.add(const Duration(minutes: 35)))],
      habitProgress: [],
    );
    st.habitHits.addAll([for (var i = 0; i < 12; i++) HabitHit(habitId: 'pompes', ts: t0.add(Duration(minutes: i)))]);
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
