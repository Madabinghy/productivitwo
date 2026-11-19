import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/launcher_tab_store.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/widgets/routine_launcher_sheet.dart';
import 'package:productivitwo_v1/widgets/routines_day_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Une routine à durée réglée : le bouton de sa ligne lance le minuteur à cette durée, pas un chrono sans fin.
void main() {
  AppLogic build() {
    final logic = AppLogic(AppState(domains: [], activities: [], sessions: [], habitProgress: []), () {});
    logic.state.activities.addAll([
      Activity(id: 'etudes', domainId: 'd', name: 'Études', createdAt: DateTime(2026, 1, 1)),
      // Durée réglée ET activité liée : le minuteur passe devant.
      Activity(id: 'bible', domainId: 'd', name: 'Lire la Bible', type: 'habit', habitFreq: HabitFreq.daily, habitTarget: 1, timerMin: 25, timeContext: 'day', linkedActivityId: 'etudes', createdAt: DateTime(2026, 1, 1)),
      // Activité liée sans durée : le chrono, comme avant.
      Activity(id: 'revoir', domainId: 'd', name: 'Revoir mes notes', type: 'habit', habitFreq: HabitFreq.daily, habitTarget: 1, timeContext: 'day', linkedActivityId: 'etudes', createdAt: DateTime(2026, 1, 1)),
    ]);
    return logic;
  }

  testWidgets('Journée parfaite : ⏱ lance le minuteur réglé, ▶ reste pour une routine sans durée', (t) async {
    t.view.physicalSize = const Size(900, 3600);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    final logic = build();
    final timed = <(String, int)>[];
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: RoutinesDayView(logic: logic, onlyMissing: true, onStartTimed: (a, m) => timed.add((a.id, m)))))));
    await t.pump();
    final timer = find.byKey(const ValueKey('routine-timer-bible'));
    expect(timer, findsOneWidget);
    expect(find.descendant(of: timer, matching: find.byIcon(Icons.timer_outlined)), findsOneWidget);
    expect(find.byKey(const ValueKey('routine-timer-revoir')), findsNothing);
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    await t.tap(timer);
    expect(timed, [('bible', 25)]);
    // Le minuteur ne lance pas lui-même un chrono sans fin : c'est l'appelant qui démarre l'activité et le décompte.
    expect(logic.runningActivity(), isNull);
  });

  testWidgets('lanceur de routines : même règle', (t) async {
    SharedPreferences.setMockInitialValues({});
    LauncherTabStore.resetForTest();
    t.view.physicalSize = const Size(900, 3600);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    final logic = build();
    final log = <String>[];
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: RoutineLauncher(
                logic: logic, sync: FirestoreSync(), onNew: () {}, onChrono: (a) => log.add('chrono:${a.id}'), onTimer: (a) => log.add('timer:${a.id}')))));
    await t.pump();
    expect(find.byTooltip('Minuteur 25 min'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('launcher-timer-bible')));
    await t.tap(find.byKey(const ValueKey('launcher-go-revoir')));
    expect(log, ['timer:bible', 'chrono:etudes']);
    expect(find.textContaining('25 min', findRichText: true), findsOneWidget);
  });
}
