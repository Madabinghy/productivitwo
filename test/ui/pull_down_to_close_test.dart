import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/widgets/pull_down_to_close.dart';

void main() {
  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (ctx) => TextButton(
          onPressed: () => Navigator.of(ctx).push(MaterialPageRoute<void>(
            fullscreenDialog: true,
            builder: (_) => PullDownToClose(
              child: Scaffold(
                appBar: AppBar(title: const Text('Page')),
                body: ListView(children: [for (var i = 0; i < 40; i++) ListTile(title: Text('ligne $i'))]),
              ),
            ),
          )),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('tirer vers le bas depuis le haut ferme la page', (tester) async {
    await open(tester);
    await tester.drag(find.text('Page'), const Offset(0, 300));
    await tester.pumpAndSettle();
    expect(find.text('Page'), findsNothing);
  });

  testWidgets('iOS (rebond) : tirer depuis la liste ferme', (tester) async {
    await open(tester);
    await tester.drag(find.text('ligne 2'), const Offset(0, 400));
    await tester.pumpAndSettle();
    expect(find.text('Page'), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('tirer depuis la liste en haut ferme ; un petit geste revient', (tester) async {
    await open(tester);
    await tester.drag(find.text('ligne 2'), const Offset(0, 40));
    await tester.pumpAndSettle();
    expect(find.text('Page'), findsOneWidget);
    await tester.drag(find.text('ligne 2'), const Offset(0, 400));
    await tester.pumpAndSettle();
    expect(find.text('Page'), findsNothing);
  });
}
