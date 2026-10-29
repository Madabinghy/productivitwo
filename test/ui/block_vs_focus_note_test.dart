import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/widgets/block_vs_focus_note.dart';

void main() {
  testWidgets('BlockVsFocusNote : une ligne, tap = la comparaison', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: BlockVsFocusNote(side: BlockVsFocusSide.block))));
    expect(find.textContaining('engagement'), findsOneWidget);
    expect(find.text('Jour visé'), findsNothing);
    await tester.tap(find.byType(InkWell));
    await tester.pump();
    expect(find.text('Bloc dans le programme'), findsOneWidget);
    expect(find.text('Jour visé'), findsOneWidget);
    expect(find.text('ce que tu fais'), findsOneWidget);
  });
}
