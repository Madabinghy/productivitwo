import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/miracle_morning.dart';
import 'package:productivitwo_v1/utils/routine_moments.dart';
import 'package:productivitwo_v1/widgets/miracle_passage.dart';

/// Le passage (2026-11-21) : les étapes de l'ancien Miracle Morning deviennent des routines du moment Miracle
/// Morning, dans leur ordre ; l'écran d'avant n'existe plus.
void main() {
  Activity routine(String id, String name, {String? ctx, int? timer, int target = 1, List<String> split = const [], String domain = 'd'}) => Activity(
        id: id,
        domainId: domain,
        name: name,
        type: 'habit',
        habitFreq: HabitFreq.daily,
        habitTarget: target,
        timeContext: ctx,
        timerMin: timer,
        splitMoments: split,
        createdAt: DateTime(2026),
      );

  MiracleMorning steps() => const MiracleMorning([
        MiracleStep(id: 's1', name: 'Verre d’eau', routineId: 'eau', minutes: 1),
        MiracleStep(id: 's2', name: 'Louanges', routineId: 'lou', minutes: 15),
        MiracleStep(id: 's3', name: 'Silence', minutes: 5),
        MiracleStep(id: 's4', name: 'Pompes', routineId: 'pom', minutes: 3),
        MiracleStep(id: 's5', name: 'Visualisation', minutes: 5),
        MiracleStep(id: 's6', name: 'Partie', routineId: 'gone', minutes: 4),
        MiracleStep(id: 's7', name: 'Louanges encore', routineId: 'lou', minutes: 2),
      ]);

  List<Activity> acts() => [
        routine('eau', 'Verre d’eau', target: 8, split: const [kMomentMorning, kMomentMidday, kMomentAfternoon, kMomentEvening]),
        routine('lou', 'Louanges', ctx: kMomentMorning),
        routine('pom', 'Pompes', ctx: kMomentMorning, target: 10),
      ];

  test('les étapes se lisent encore, et une étape sans nom est ignorée', () {
    final m = MiracleMorning.from({
      'steps': [
        {'id': 'a', 'name': 'Silence', 'minutes': 5},
        {'id': 'b', 'name': '  '},
        {'id': 'c', 'name': 'Lire', 'routineId': 'r', 'minutes': 500},
      ]
    })!;
    expect(m.steps.map((s) => s.name), ['Silence', 'Lire']);
    expect(m.steps.last.minutes, 120);
    expect(m.totalMin, 125);
    expect(MiracleMorning.from(null), isNull);
  });

  test('le passage, étape par étape : routine déplacée, routine répartie, étape libre', () {
    final lines = miraclePassage(steps(), acts());
    expect([for (final l in lines) (l.step.id, l.kind)], [
      ('s1', PassageKind.shared),
      ('s2', PassageKind.moved),
      ('s3', PassageKind.created),
      ('s4', PassageKind.moved),
      ('s5', PassageKind.created),
      // Sa routine n'existe plus : une étape libre. La seconde « Louanges » ne compte pas deux fois.
      ('s6', PassageKind.created),
    ]);
    expect(lines[0].before, 'routine répartie');
    expect(lines[1].before, 'routine · matin');
    expect(lines[1].after, 'passe au moment Miracle Morning');
    expect(lines[2].before, 'étape libre · 5 min');
    expect(lines[2].after, 'devient une routine de 5 min, chaque jour');
  });

  test('appliquer : moments, parts, ordre, durées ; une étape libre écartée ne crée rien', () {
    final all = acts();
    final r = applyMiraclePassage(miraclePassage(steps(), all), dropped: {'s5', 's6'}, domainId: 'd');
    final eau = all[0], lou = all[1], pom = all[2];
    // L'eau garde ses moments et prend une part au Miracle Morning, prise sur la plus grosse.
    expect(eau.splitMoments, [kMomentMiracle, kMomentMorning, kMomentMidday, kMomentAfternoon, kMomentEvening]);
    expect(eau.momentShares, {kMomentMiracle: 1, kMomentMorning: 1, kMomentMidday: 2, kMomentAfternoon: 2, kMomentEvening: 2});
    expect(eau.momentShares.values.fold<int>(0, (s, x) => s + x), 8);
    // Une routine à faire une fois, sans durée, prend celle de l'étape ; une routine à répétitions non.
    expect((lou.timeContext, lou.timerMin, lou.routineOrder), (kMomentMiracle, 15, 1));
    expect((pom.timeContext, pom.timerMin, pom.routineOrder), (kMomentMiracle, null, 3));
    expect(eau.routineOrder, 0);
    // « Silence » gardée devient une routine quotidienne du moment, à sa place dans l'ordre.
    expect(r.created.length, 1);
    final sil = r.created.single;
    expect((sil.name, sil.isHabit, sil.habitFreq, sil.habitTarget, sil.timeContext, sil.timerMin, sil.routineOrder, sil.domainId),
        ('Silence', true, HabitFreq.daily, 1, kMomentMiracle, 5, 2, 'd'));
    expect(r.changed.map((a) => a.id), ['eau', 'lou', 'pom']);
  });

  test('la fin du moment : le temps des étapes plus un quart d’heure, une heure au moins', () {
    expect(miracleEndFor(const MiracleMorning([MiracleStep(id: 'a', name: 'A', minutes: 10)]), 300), 360);
    expect(miracleEndFor(steps(), 180), 180 + 60); // 35 min d'étapes
    expect(miracleEndFor(const MiracleMorning([MiracleStep(id: 'a', name: 'A', minutes: 80)]), 300), 300 + 120);
    // Le matin commence quand le Miracle Morning finit ; jamais au-delà du matin.
    final w = withMiracleWindow({kMomentMorning: (330, 660)}, dayStartMin: 300, endMin: 390);
    expect(w, {kMomentMiracle: (300, 390), kMomentMorning: (390, 660)});
    expect(withMiracleWindow(const {}, dayStartMin: 300, endMin: 900)[kMomentMiracle], (300, 630));
  });

  testWidgets('la carte puis la feuille : « Faire le passage » allume le moment et range les routines', (tester) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final st = AppState(domains: [Domain(id: 'd', name: 'Vie')], activities: acts(), sessions: [], habitProgress: []);
    final logic = AppLogic(st, () {})
      ..dayStartMin = 180
      ..metaLoaded = true
      ..miracleMorning = steps();
    expect(logic.miraclePassageDue, isTrue);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: MiraclePassageCard(logic: logic))));
    expect(find.text('Ton Miracle Morning devient un moment de la journée'), findsOneWidget);
    await tester.tap(find.byKey(const Key('miracle-passage-open')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Silence', findRichText: true), findsOneWidget);
    expect(find.textContaining('3 h → 4 h'), findsOneWidget);
    // « Visualisation » n'est pas gardée.
    await tester.ensureVisible(find.byKey(const Key('miracle-passage-keep-s5')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('miracle-passage-keep-s5')));
    await tester.pump();
    expect(find.text('ne sera pas gardée'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('miracle-passage-run')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('miracle-passage-run')));
    await tester.pumpAndSettle();
    expect(logic.miracleMigrated, isTrue);
    expect(logic.miraclePassageDue, isFalse);
    expect(logic.moments.first.key, kMomentMiracle);
    expect((logic.moments.first.startMin, logic.moments.first.endMin), (180, 240));
    expect(st.activities.map((a) => a.name), containsAll(['Silence', 'Partie']));
    expect(st.activities.any((a) => a.name == 'Visualisation'), isFalse);
    expect(st.activities.firstWhere((a) => a.id == 'lou').timeContext, kMomentMiracle);
    // La carte a disparu.
    expect(find.byKey(const Key('miracle-passage-card')), findsNothing);
    await tester.pump(const Duration(seconds: 7));
  });
}
