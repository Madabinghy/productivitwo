import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/utils/game_rules.dart';
import 'package:productivitwo_v1/widgets/info_dot.dart';

void main() {
  testWidgets('InfoDot : ⓘ → cartes, Suivant puis Compris', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Center(child: InfoDot(kRuleBlockVsFocus)))));
    await tester.tap(find.byIcon(Icons.info_outline_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Un bloc est un engagement'), findsOneWidget);
    for (var i = 0; i < kRuleBlockVsFocus.cards.length - 1; i++) {
      await tester.tap(find.text('Suivant'));
      await tester.pumpAndSettle();
    }
    expect(find.text('Pas faite ? Pas grave'), findsOneWidget);
    await tester.tap(find.text('Compris'));
    await tester.pumpAndSettle();
    expect(find.text('Pas faite ? Pas grave'), findsNothing);
  });

  testWidgets('InfoDot : startAt ouvre sur la bonne carte', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Center(child: InfoDot(kRuleBlockVsFocus, startAt: 2)))));
    await tester.tap(find.byIcon(Icons.info_outline_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Viser un jour est une intention'), findsOneWidget);
  });
}
