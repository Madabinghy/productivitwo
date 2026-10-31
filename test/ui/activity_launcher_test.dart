import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/widgets/activity_launcher_sheet.dart';

/// Lanceur d'activités : chrono en cours en tête, ▶ lance, dormantes repliées.
void main() {
  testWidgets('ActivityLauncher : focus par défaut, en cours, ▶ lance, peu utilisées repliées', (tester) async {
    final now = DateTime.now();
    final prod = Activity(id: 'prod', domainId: 'b', name: 'Productivitwo', goalMin: 10);
    final reseau = Activity(id: 'reseau', domainId: 'b', name: 'Réseau', goalMin: 1);
    final reno = Activity(id: 'reno', domainId: 'b', name: 'Rénovation', goalMin: 1);
    final st = AppState(
      domains: [Domain(id: 'b', name: 'Business')],
      activities: [prod, reseau, reno],
      sessions: [
        Session(activityId: 'prod', startAt: now.subtract(const Duration(minutes: 5))),
        Session(activityId: 'reseau', startAt: now.subtract(const Duration(days: 2, minutes: 30)), endAt: now.subtract(const Duration(days: 2))),
      ],
      habitProgress: [],
    );
    final logic = AppLogic(st, () {})..dayStartMin = 0;
    Activity? started;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ActivityLauncher(
          logic: logic,
          onStart: (a) => started = a,
          onStartTimed: (_, __) {},
          onDeepWork: (_) {},
          onOpenFiche: (_) async {},
          onStop: () async {},
          onNew: () {},
        ),
      ),
    ));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('EN COURS'), findsOneWidget);
    // Focus par défaut : seule la cible du jour non atteinte (Productivitwo, 5 / 10 min).
    expect(find.text('Focus · 1'), findsOneWidget);
    expect(find.text('Réseau'), findsNothing);
    expect(find.text('Peu utilisées · 1'), findsNothing);
    await tester.enterText(find.byType(TextField), 'rés');
    await tester.pump();
    expect(find.text('Réseau'), findsOneWidget); // la recherche cherche dans toutes
    await tester.enterText(find.byType(TextField), '');
    await tester.tap(find.text('Tout'));
    await tester.pump();
    expect(find.text('Peu utilisées · 1'), findsOneWidget);
    expect(find.text('Rénovation'), findsOneWidget); // aperçu du repli seulement
    await tester.tap(find.byIcon(Icons.play_arrow_rounded).first);
    expect(started?.id, 'reseau');
    await tester.pumpWidget(const SizedBox());
  });
}
