import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/launcher_tab_store.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/routine_cover.dart';
import 'package:productivitwo_v1/widgets/routine_launcher_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Activity routine(String id, String name, {int target = 10, bool rolling = true, HabitFreq freq = HabitFreq.daily}) => Activity(
        id: id,
        domainId: 'd',
        name: name,
        type: 'habit',
        habitFreq: freq,
        habitTarget: target,
        rolling: rolling,
        createdAt: DateTime(2026, 1, 1),
      );

  testWidgets('Focus en trois étages : à faire, prendre de l\'avance, couvertes', (t) async {
    SharedPreferences.setMockInitialValues({});
    LauncherTabStore.resetForTest();
    t.view.physicalSize = const Size(900, 3600);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);

    final logic = AppLogic(AppState(domains: [], activities: [], sessions: [], habitProgress: []), () {});
    final today = logic.livedToday;
    // [perDay] : coches d'il y a 6 jours … jusqu'à aujourd'hui.
    List<HabitHit> hits(String id, List<int> perDay) => [
          for (var i = 0; i < perDay.length; i++)
            for (var k = 0; k < perDay[i]; k++)
              HabitHit(habitId: id, ts: DateTime(today.year, today.month, today.day - (perDay.length - 1 - i), 5, 1 + k)),
        ];
    logic.state.activities.addAll([
      routine('pompes', 'Pompes'),
      routine('abdos', 'Abdos'),
      routine('gainage', 'Gainage', target: 1),
      routine('eau', 'Boire de l\'eau', target: 1, rolling: false),
    ]);
    logic.state.habitHits.addAll([
      ...hits('pompes', [10, 10, 10, 10, 10, 10, 0]),
      ...hits('abdos', [10, 10, 10, 10, 10, 10, 10]),
      ...hits('gainage', [1, 1, 1, 1, 1, 3, 0]),
    ]);

    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: RoutineLauncher(logic: logic, sync: FirestoreSync(), onNew: () {}, onChrono: (_) {}, onTimer: (_) {}))));
    await t.pump();

    // À faire : la part du jour, et la jauge de ce que les coches du jour achètent.
    expect(find.textContaining('0 / 10 aujourd\'hui', findRichText: true), findsOneWidget);
    final gauge = find.byKey(const ValueKey('launcher-cover-bar-pompes'));
    expect(gauge, findsOneWidget);
    expect(find.descendant(of: gauge, matching: find.text('ce soir')), findsOneWidget);
    expect(find.descendant(of: gauge, matching: find.text('demain')), findsOneWidget);
    // Une routine « chaque jour » n'a pas de jauge des 7 jours.
    expect(find.text('Boire de l\'eau'), findsOneWidget);
    expect(find.byKey(const ValueKey('launcher-cover-bar-eau')), findsNothing);

    // Prendre de l'avance : tenue ce soir, demain demandera 10.
    expect(find.byKey(const ValueKey('launcher-ahead')), findsOneWidget);
    expect(find.text('Abdos'), findsOneWidget);
    expect(find.textContaining('encore 10 = demain libre', findRichText: true), findsOneWidget);
    expect(t.getTopLeft(find.text('Abdos')).dy, greaterThan(t.getTopLeft(find.byKey(const ValueKey('launcher-ahead'))).dy));
    expect(t.getTopLeft(find.text('Pompes')).dy, lessThan(t.getTopLeft(find.byKey(const ValueKey('launcher-ahead'))).dy));

    // Couvertes : repliées sur une ligne, pas de ligne à elles en Focus.
    expect(find.text('Gainage'), findsNothing);
    final covered = find.byKey(const ValueKey('launcher-covered'));
    expect(covered, findsOneWidget);
    expect(find.descendant(of: covered, matching: find.textContaining('1 couverte · Gainage jusqu\'à demain soir', findRichText: true)), findsOneWidget);

    // La ligne des couvertes ouvre « Tout », où la routine dit jusqu'où elle est tranquille.
    await t.tap(covered);
    await t.pump();
    expect(find.text('Gainage'), findsOneWidget);
    expect(find.textContaining('✓ couverte jusqu\'à demain soir', findRichText: true), findsOneWidget);
    // En « Tout », une couverte garde sa jauge : ce soir et demain déjà acquis.
    expect(find.descendant(of: find.byKey(const ValueKey('launcher-cover-bar-gainage')), matching: find.text('ce soir + dem.')), findsOneWidget);
    expect(find.byKey(const ValueKey('launcher-ahead')), findsNothing);
    expect(t.takeException(), isNull);
  });

  test('une hebdomadaire atteinte : couverte tant que sa coche reste dans la fenêtre', () {
    final now = DateTime(2026, 11, 19, 12); // jeudi
    final a = routine('aspi', 'Aspirateur', target: 1, rolling: false, freq: HabitFreq.weekly);
    // Faite samedi dernier à 10 h : elle sort de la fenêtre samedi prochain à 10 h.
    final h = [HabitHit(habitId: 'aspi', ts: DateTime(2026, 11, 14, 10))];
    expect(weeklyAheadDays(a, h, now), 1); // couverte jusqu'à vendredi soir
    expect(coveredUntilLabel(DateTime(2026, 11, 19), 1), 'demain soir');
    // Pas faite : pas couverte.
    expect(weeklyAheadDays(a, const [], now), isNull);
    // 3 fois par semaine, 3 coches : c'est la plus ancienne qui fait revenir la routine.
    final b = routine('footing', 'Footing', target: 3, rolling: false, freq: HabitFreq.weekly);
    final hb = [
      HabitHit(habitId: 'footing', ts: DateTime(2026, 11, 16, 10)),
      HabitHit(habitId: 'footing', ts: DateTime(2026, 11, 17, 10)),
      HabitHit(habitId: 'footing', ts: DateTime(2026, 11, 18, 10)),
    ];
    expect(weeklyAheadDays(b, hb, now), 3); // jusqu'à dimanche, revient lundi
    expect(coveredUntilLabel(DateTime(2026, 11, 19), 3), 'dimanche');
    // Une routine quotidienne n'est pas concernée.
    expect(weeklyAheadDays(routine('p', 'P'), const [], now), isNull);
  });
}
