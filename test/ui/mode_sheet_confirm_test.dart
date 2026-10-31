import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/mode.dart';
import 'package:productivitwo_v1/widgets/mode_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Feuille du mode : un tap sur un mode l'explique, seul le bouton le change.
void main() {
  testWidgets('toucher un mode explique, « Passer en … » change', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final logic = AppLogic(AppState(domains: [], activities: [], sessions: [], habitProgress: []), () {});
    await tester.binding.setSurfaceSize(const Size(900, 1600));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Builder(builder: (c) => TextButton(onPressed: () => showModeSheet(c, logic), child: const Text('ouvrir')))),
    ));
    await tester.tap(find.text('ouvrir'));
    await tester.pumpAndSettle();
    final before = logic.mode;
    await tester.tap(find.text('En forme').first);
    await tester.pump();
    expect(find.text('Passer en En forme ?'), findsOneWidget);
    expect(logic.mode, before);
    await tester.tap(find.text('Pas maintenant'));
    await tester.pump();
    expect(find.text('Passer en En forme ?'), findsNothing);
    expect(logic.mode, before);
    await tester.tap(find.text('En forme').first);
    await tester.pump();
    await tester.tap(find.text('Passer en En forme'));
    await tester.pump();
    expect(logic.mode, DayMode.high);
    expect(find.text('Passer en En forme ?'), findsNothing);
    await tester.binding.setSurfaceSize(null);
  });
}
