import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/widgets/moment_item.dart';

void main() {
  test('OpenItem : le premier par défaut, puis le choix de l\'utilisateur, y compris rien', () {
    final o = OpenItem();
    expect(o.current('a'), 'a');
    expect(o.isOpen('a', 'a'), isTrue);
    o.toggle('b', 'a');
    expect(o.current('a'), 'b');
    o.toggle('b', 'a'); // retoucher le bloc ouvert le referme
    expect(o.current('a'), isNull);
    o.toggle('a', 'a');
    expect(o.current('a'), 'a');
  });

  testWidgets('MomentItem : tap = ouvre / referme à sa place, appui long remonté', (tester) async {
    var open = false;
    var long = 0;
    await tester.pumpWidget(MaterialApp(
      home: StatefulBuilder(builder: (ctx, setState) {
        return Scaffold(
          body: ListView(children: [
            MomentItem(
              open: open,
              collapsed: const SizedBox(height: 40, child: Text('ligne')),
              expanded: const SizedBox(height: 200, child: Text('bloc')),
              onToggle: () => setState(() => open = !open),
              onLongPress: () => long++,
            ),
          ]),
        );
      }),
    ));
    expect(find.text('ligne'), findsOneWidget);
    await tester.tap(find.text('ligne'));
    await tester.pumpAndSettle();
    expect(find.text('bloc'), findsOneWidget);
    await tester.tap(find.text('bloc'));
    await tester.pumpAndSettle();
    expect(find.text('ligne'), findsOneWidget);
    await tester.longPress(find.text('ligne'));
    expect(long, 1);
    expect(tester.takeException(), isNull);
  });
}
