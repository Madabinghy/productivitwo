import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/utils/progress_bricks.dart';
import 'package:productivitwo_v1/widgets/progress_bricks.dart';

void main() {
  testWidgets('ProgressBricks : rendu de chaque état et tap sur la bonne brique', (tester) async {
    const row = BrickRow(bricks: [
      Brick(id: 'a', title: 'a', state: BrickState.done, fill: 1),
      Brick(id: 'b', title: 'b', state: BrickState.started, fill: .5),
      Brick(id: 'c', title: 'c', state: BrickState.late, fill: .25),
      Brick(id: 'd', title: 'd', state: BrickState.running, fill: .4),
      Brick(id: 'e', title: 'e', state: BrickState.todo, fill: 0),
      Brick(id: 'f', title: 'f', state: BrickState.upcoming, fill: 0),
    ], expected: 3);
    int? tapped;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(width: 300, child: ProgressBricks(row: row, onBrick: (i) => tapped = i)),
      ),
    ));
    final box = tester.getRect(find.byType(ProgressBricks));
    await tester.tapAt(Offset(box.left + box.width * (4.5 / 6), box.center.dy));
    expect(tapped, 4);
    await tester.tapAt(Offset(box.left + 2, box.center.dy));
    expect(tapped, 0);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: StepDots(done: 2, total: 5))));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: ProgressBricks(row: BrickRow(bricks: [], expected: 0)))));
    expect(tester.takeException(), isNull);
  });
}
