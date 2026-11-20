import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/widgets/activity_fab.dart';

void main() {
  Future<List<String>> pump(WidgetTester t, String? running) async {
    final log = <String>[];
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            floatingActionButton: ActivityFab(runningName: running, onLaunch: () => log.add('launch'), onStop: () => log.add('stop')))));
    return log;
  }

  testWidgets('aucun chrono : ▶ ouvre le lanceur, pas de ■', (t) async {
    final log = await pump(t, null);
    expect(find.byKey(const ValueKey('fab-stop-activity')), findsNothing);
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('fab-launch-activity')));
    expect(log, ['launch']);
  });

  testWidgets('un chrono tourne : ▶ ouvre toujours le lanceur, un petit ■ au-dessus arrête', (t) async {
    final log = await pump(t, 'Lecture');
    final launch = find.byKey(const ValueKey('fab-launch-activity')), stop = find.byKey(const ValueKey('fab-stop-activity'));
    expect(launch, findsOneWidget);
    expect(stop, findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Arrêter Lecture')), findsWidgets);
    // Le ■ est au-dessus du ▶, plus petit, centré sur lui.
    expect(t.getBottomLeft(stop).dy, lessThan(t.getTopLeft(launch).dy));
    expect(t.getSize(stop).width, lessThan(t.getSize(launch).width));
    expect(t.getCenter(stop).dx, closeTo(t.getCenter(launch).dx, .5));
    // Voir ses activités n'arrête rien.
    await t.tap(launch);
    expect(log, ['launch']);
    await t.tap(stop);
    expect(log, ['launch', 'stop']);
    // Le chrono arrêté, le ■ disparaît.
    await pump(t, null);
    expect(stop, findsNothing);
    expect(launch, findsOneWidget);
  });
}
