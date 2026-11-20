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

  testWidgets('aucun chrono : ▶ ouvre le lanceur', (t) async {
    final log = await pump(t, null);
    expect(find.byKey(const ValueKey('fab-stop-activity')), findsNothing);
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('fab-launch-activity')));
    expect(log, ['launch']);
  });

  testWidgets('un chrono tourne : ■ l\'arrête, appui long = le lanceur quand même', (t) async {
    final log = await pump(t, 'Lecture');
    expect(find.byKey(const ValueKey('fab-launch-activity')), findsNothing);
    expect(find.byIcon(Icons.stop_rounded), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Arrêter Lecture')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('fab-stop-activity')));
    expect(log, ['stop']);
    await t.longPress(find.byKey(const ValueKey('fab-stop-activity')));
    expect(log, ['stop', 'launch']);
    // Le chrono arrêté, le bouton redevient ▶.
    await pump(t, null);
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
  });
}
