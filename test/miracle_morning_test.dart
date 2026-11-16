import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/coup_alarm.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/miracle_morning.dart';
import 'package:productivitwo_v1/widgets/miracle_morning_screen.dart';

void main() {
  Activity routine(String id, String name, {String? ctx, int? timer}) => Activity(
        id: id,
        domainId: 'd',
        name: name,
        role: ActivityRole.generic,
        type: 'habit',
        habitFreq: HabitFreq.daily,
        habitTarget: 1,
        timeContext: ctx,
        timerMin: timer,
        createdAt: DateTime(2026),
      );

  test('au départ : les routines du matin, avec leur minuteur', () {
    final m = defaultMiracle([routine('a', 'Méditer', ctx: 'morning', timer: 10), routine('b', 'Lire', ctx: 'evening'), routine('c', 'Prier', ctx: 'morning')]);
    expect(m.steps.map((s) => s.name), ['Méditer', 'Prier']);
    expect(m.steps.first.minutes, 10);
    expect(m.steps.last.minutes, 5);
    expect(m.totalMin, 15);
  });

  test('relecture et écriture', () {
    const m = MiracleMorning([MiracleStep(id: '1', name: 'Silence', minutes: 5), MiracleStep(id: '2', name: 'Pompes', routineId: 'p', minutes: 7, note: '20')]);
    final back = MiracleMorning.from(m.toJson())!;
    expect(back.steps.length, 2);
    expect(back.steps[1].routineId, 'p');
    expect(back.steps[1].note, '20');
    expect(MiracleMorning.from(null), isNull);
    expect(MiracleMorning.from({'steps': [{'id': 'x'}, 3]})!.steps, isEmpty);
    expect(miracleNames(const MiracleMorning([MiracleStep(id: '1', name: 'A'), MiracleStep(id: '2', name: 'B'), MiracleStep(id: '3', name: 'C'), MiracleStep(id: '4', name: 'D')])), 'A · B · C · +1');
  });

  test('fait aujourd’hui = une ChainRun miracle du jour vécu', () {
    final run = ChainRun(date: '2026-11-16', startedAt: DateTime(2026, 11, 16, 7), endedAt: DateTime(2026, 11, 16, 7, 40), doneCount: 4, total: 5, completed: true, kind: kMiracleKind);
    expect(miracleDoneOn([run], '2026-11-16'), isNotNull);
    expect(miracleDoneOn([run], '2026-11-17'), isNull);
  });

  testWidgets('une étape à la fois : fait = +1 de la routine, passer = rien, puis le bilan', (t) async {
    t.view.physicalSize = const Size(1400, 2400);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    CoupAlarm.enabled = false;
    addTearDown(() => CoupAlarm.enabled = true);
    final p = routine('p', 'Prier', ctx: 'morning');
    final st = AppState(domains: [Domain(id: 'd', name: 'Foi')], activities: [p], sessions: [], habitProgress: []);
    final logic = AppLogic(st, () {})
      ..dayStartMin = 0
      ..miracleMorning = const MiracleMorning([
        MiracleStep(id: '1', name: 'Prière', routineId: 'p', minutes: 5),
        MiracleStep(id: '2', name: 'Visualisation', minutes: 3),
      ]);
    await t.pumpWidget(MaterialApp(home: MiracleMorningScreen(logic: logic)));
    await t.pump();
    expect(find.text('MIRACLE MORNING · 1 / 2'), findsOneWidget);
    expect(find.text('Prière'), findsOneWidget);
    expect(find.textContaining('Visualisation'), findsOneWidget); // ENSUITE
    await t.tap(find.byKey(const ValueKey('miracle-done')));
    await t.pump();
    expect(st.habitHits.where((h) => h.habitId == 'p').length, 1);
    expect(find.text('MIRACLE MORNING · 2 / 2'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('miracle-skip')));
    await t.pump();
    expect(find.text('MIRACLE MORNING · FAIT'), findsOneWidget);
    expect(find.textContaining('1 sur 2'), findsOneWidget);
    expect(find.text('passée'), findsOneWidget);
    expect(logic.miracleToday, isNotNull);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 30));
  });
}
