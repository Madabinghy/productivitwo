import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/widgets/sniper_screen.dart';

void main() {
  testWidgets('Sniper : sans enjeu, le viseur le dit et rien ne se lance', (tester) async {
    tester.view.physicalSize = const Size(780, 1700);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final st = AppState(domains: [], activities: [], sessions: [], habitProgress: []);
    final logic = AppLogic(st, () {})..dayStartMin = 0;
    await tester.pumpWidget(MaterialApp(home: SniperScreen(logic: logic)));
    await tester.pump();
    await tester.pump();
    expect(find.text('Chaque minute, pile où elle compte'), findsOneWidget);
    expect(find.text('Rien à viser'), findsOneWidget);
    expect(find.textContaining('Rien en jeu pour l’instant'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(hours: 1));
  });
}
