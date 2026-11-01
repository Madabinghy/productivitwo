import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/week_review.dart';
import 'package:productivitwo_v1/widgets/week_review_screen.dart';

void main() {
  testWidgets('Revue du dimanche : quatre étapes, la phrase est gardée', (tester) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final st = AppState(domains: [Domain(id: 'd', name: 'Travail')], activities: [], sessions: [], habitProgress: []);
    final logic = AppLogic(st, () {})..dayStartMin = 0;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (ctx) => Scaffold(body: Center(child: TextButton(onPressed: () => showWeekReviewScreen(ctx, logic), child: const Text('ouvrir'))))),
    ));
    await tester.tap(find.text('ouvrir'));
    await tester.pumpAndSettle();
    expect(find.text('TES JEUX'), findsOneWidget);
    await tester.tap(find.text('Suivant'));
    await tester.pumpAndSettle();
    expect(find.text('TES PROJETS'), findsOneWidget);
    await tester.tap(find.text('Suivant'));
    await tester.pumpAndSettle();
    expect(find.text('Rien à trancher cette semaine'), findsOneWidget);
    await tester.tap(find.text('Suivant'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Finir la maquette');
    await tester.tap(find.text('Terminer la revue'));
    await tester.pumpAndSettle();
    final monday = reviewedMonday(DateTime.now(), 0);
    expect(logic.weekReviews[monday]?.intention, 'Finir la maquette');
    expect(find.text('ouvrir'), findsOneWidget);
  });
}
