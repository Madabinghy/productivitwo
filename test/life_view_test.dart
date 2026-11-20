import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:productivitwo_v1/utils/leisure.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/finances.dart' show euros;
import 'package:productivitwo_v1/widgets/life_view.dart';
import 'package:productivitwo_v1/widgets/week_hours_card.dart';
import 'package:productivitwo_v1/utils/week_hours.dart';
import 'package:productivitwo_v1/utils/modules.dart';

void main() {
  testWidgets('Organisation : tuiles par nature, sans modes', (tester) async {
    tester.view.physicalSize = const Size(720, 4000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final now = DateTime.now();
    final t0 = DateTime(now.year, now.month, now.day, 0, 1);
    final st = AppState(
      domains: [Domain(id: 'sl', name: 'Sommeil'), Domain(id: 'sp', name: 'Sport'), Domain(id: 'b', name: 'Business'), Domain(id: 'i', name: 'Intendance')],
      activities: [
        Activity(id: 'run', domainId: 'sp', name: 'Courir', role: ActivityRole.generic, type: 'time', goalMin: 7, createdAt: DateTime(2026)),
        Activity(id: 'w', domainId: 'b', name: 'Contenu', role: ActivityRole.generic, type: 'time', goalMin: 30, createdAt: DateTime(2026)),
      ],
      sessions: [Session(activityId: 'run', startAt: t0, endAt: t0.add(const Duration(minutes: 40)))],
      habitProgress: [],
    );
    final logic = AppLogic(st, () {})..dayStartMin = 0;
    var opened = '';
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: LifeView(
          logic: logic,
          sync: FirestoreSync(),
          projects: const [],
          onOpenDomain: (d) async {
            opened = d.name;
            return null;
          },
          onOpenSleep: () => opened = 'sleep',
          onManageDomains: () {},
        ),
      ),
    ));
    await tester.pump();
    expect(find.text('Organisation'), findsOneWidget);
    expect(find.text('Guérilla'), findsNothing);
    expect(find.text('MES MODES'), findsNothing);
    expect(find.byKey(const ValueKey('life-objectives')), findsOneWidget);
    await tester.scrollUntilVisible(find.byKey(const ValueKey('recul-day')), 300, scrollable: find.byType(Scrollable).first);
    expect(find.byKey(const ValueKey('recul-where')), findsOneWidget);
    expect(find.byKey(const ValueKey('week-hours-card')), findsOneWidget);
    expect(find.text('TES 7 DERNIERS JOURS'), findsOneWidget);
    expect(find.text('PAS DE SAISON EN COURS'), findsOneWidget);
    expect(find.text('SOMMEIL'), findsOneWidget);
    expect(find.text('SPORT'), findsOneWidget);
    expect(find.text('1 séance'), findsOneWidget);
    expect(find.text('BUSINESS'), findsOneWidget);
    await tester.tap(find.text('BUSINESS'));
    expect(opened, 'Business');
    await tester.tap(find.text('SOMMEIL'));
    expect(opened, 'sleep');
  });

  testWidgets('Modules éteints : plus de compteur des 168 h, de saison, ni de tuile Sommeil', (tester) async {
    tester.view.physicalSize = const Size(720, 4000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final st = AppState(domains: [Domain(id: 'sl', name: 'Sommeil'), Domain(id: 'b', name: 'Business')], activities: [], sessions: [], habitProgress: []);
    final logic = AppLogic(st, () {})
      ..dayStartMin = 0
      ..modules = const ModuleSettings.only({});
    var opened = '';
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: LifeView(
          logic: logic,
          sync: FirestoreSync(),
          projects: const [],
          onOpenDomain: (d) async {
            opened = d.name;
            return null;
          },
          onOpenSleep: () => opened = 'sleep',
          onManageDomains: () {},
        ),
      ),
    ));
    await tester.pump();
    expect(find.byKey(const ValueKey('week-hours-card')), findsNothing);
    expect(find.text('PAS DE SAISON EN COURS'), findsNothing);
    expect(find.text('BUSINESS'), findsOneWidget);
    // Le domaine Sommeil garde sa tuile, en domaine : il ouvre sa page, pas la feuille Sommeil.
    await tester.tap(find.text('SOMMEIL'));
    expect(opened, 'Sommeil');
  });

  testWidgets('Ma vie : la tuile Finances montre le solde du compte', (tester) async {
    tester.view.physicalSize = const Size(720, 4000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final st = AppState(domains: [Domain(id: 'f', name: 'Finances')], activities: [], sessions: [], habitProgress: []);
    final logic = AppLogic(st, () {})..dayStartMin = 0;
    await logic.recordBalance(184260);
    await logic.logExpense(amount: 1260, envelopeId: 'courses');
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: LifeView(logic: logic, sync: FirestoreSync(), projects: const [], onOpenDomain: (d) async => null, onOpenSleep: () {}, onManageDomains: () {}),
      ),
    ));
    await tester.pump();
    expect(find.text('FINANCES'), findsOneWidget);
    expect(find.text(euros(183000)), findsOneWidget);
    expect(find.textContaining('sur ton compte'), findsOneWidget);
  });

  for (final nature in ['money', 'work']) {
    testWidgets('changer la nature d\'un domaine ne fait pas disparaître sa tuile ($nature)', (tester) async {
      SharedPreferences.setMockInitialValues({'life_natures': '{"s":"$nature"}'});
      tester.view.physicalSize = const Size(720, 4000);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final now = DateTime.now();
      final t0 = DateTime(now.year, now.month, now.day, 0, 1);
      final st = AppState(
        domains: [Domain(id: 'f', name: 'Finances'), Domain(id: 's', name: 'Spiritualité')],
        activities: [Activity(id: 'g', domainId: 's', name: 'GDS', role: ActivityRole.generic, type: 'time', goalMin: 45, createdAt: DateTime(2026))],
        sessions: [Session(activityId: 'g', startAt: t0, endAt: t0.add(const Duration(minutes: 50)))],
        habitProgress: [],
      );
      final logic = AppLogic(st, () {})..dayStartMin = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: LifeView(logic: logic, sync: FirestoreSync(), projects: const [], onOpenDomain: (d) async => null, onOpenSleep: () {}, onManageDomains: () {})),
      ));
      await tester.pump();
      await tester.pump();
      expect(find.text('SPIRITUALITÉ'), findsOneWidget);
      expect(find.text('FINANCES'), findsOneWidget);
      if (nature == 'work') expect(find.textContaining('sur le rythme'), findsOneWidget);
    });
  }

  testWidgets('un domaine Chill : son temps est de la détente, à part dans la jauge des 7 jours', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(720, 4000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    addTearDown(() => leisureActivityIds = const {});
    final now = DateTime.now();
    final t0 = now.subtract(const Duration(hours: 30));
    final st = AppState(
      domains: [Domain(id: 'c', name: 'Chill'), Domain(id: 'b', name: 'Business')],
      activities: [
        Activity(id: 'jeu', domainId: 'c', name: 'Jeux vidéo', role: ActivityRole.generic, type: 'time', createdAt: DateTime(2026)),
        Activity(id: 'code', domainId: 'b', name: 'Coder', role: ActivityRole.generic, type: 'time', createdAt: DateTime(2026)),
      ],
      sessions: [
        Session(activityId: 'jeu', startAt: t0, endAt: t0.add(const Duration(hours: 3))),
        Session(activityId: 'code', startAt: t0.add(const Duration(hours: 4)), endAt: t0.add(const Duration(hours: 9))),
      ],
      habitProgress: [],
    );
    final logic = AppLogic(st, () {})..dayStartMin = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: LifeView(logic: logic, sync: FirestoreSync(), projects: const [], onOpenDomain: (d) async => null, onOpenSleep: () {}, onManageDomains: () {})),
    ));
    await tester.pump();
    await tester.pump();
    expect(leisureActivityIds, {'jeu'});
    expect(find.text('CHILL'), findsOneWidget);
    expect(find.text('3 h de détente'), findsOneWidget);
    expect(find.text('5 h actives', findRichText: true), findsOneWidget); // le jeu n'y est pas
    expect(find.textContaining('168 h tracées'), findsOneWidget);
    expect(find.textContaining('tracées ·'), findsNothing);
    expect(tester.widget<Text>(find.byKey(const ValueKey('week-hours-free'))).data, '160 h libres'); // à part, en menthe
    expect(tester.widget<Text>(find.byKey(const ValueKey('week-hours-free'))).style?.color, kHoursFree);
    // Rien de tracé en besoins de base ni en sommeil : leurs lignes ne s'affichent pas.
    expect(find.byKey(const ValueKey('week-hours-basic')), findsNothing);
    expect(find.byKey(const ValueKey('week-hours-sleep')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('week-hours-card')));
    await tester.pumpAndSettle();
    expect(find.text('Détente'), findsOneWidget);
    // La feuille est plus longue (la ligne « Demain à fond ») : le titre est plus bas, on y descend.
    await tester.scrollUntilVisible(find.text('JOUR PAR JOUR · ACTIF ET DÉTENTE'), 200, scrollable: find.byType(Scrollable).last);
    expect(find.text('JOUR PAR JOUR · ACTIF ET DÉTENTE'), findsOneWidget);
    expect(find.byKey(const ValueKey('week-hours-leisure-hint')), findsNothing);
    expect(find.text('Libre'), findsOneWidget);
    expect(find.textContaining('dans le flou'), findsNothing);
    expect(find.byKey(const ValueKey('week-hours-reading')), findsOneWidget);
    // Aucun chrono ne tourne, rien ne tournait il y a 7 jours : la feuille le dit.
    expect(find.byKey(const ValueKey('week-hours-sheet-now')), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const ValueKey('week-hours-move'))).data, contains('ne bouge pas'));
  });

  testWidgets('carte des 7 jours : besoins de base en jaune, sommeil en bleu, dans l\'ordre du cadran', (tester) async {
    final logic = AppLogic(AppState(domains: [], activities: [], sessions: [], habitProgress: []), () {});
    const h = WeekHours(activeMin: 62 * 60, basicMin: 30, sleepMin: 52 * 60, leisureMin: 5 * 60, prevActiveMin: 0, leavingMin: 0, dayActive: [], days: []);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SizedBox(width: 360, child: WeekHoursCard(logic: logic, hours: h)))));
    Text part(String key) => tester.widget<Text>(find.byKey(ValueKey(key)));
    expect(part('week-hours-basic').data, '30 min de besoins');
    expect(part('week-hours-basic').style?.color, kHoursBasic);
    expect(part('week-hours-sleep').data, '52 h de sommeil');
    expect(part('week-hours-sleep').style?.color, kHoursSleep);
    expect(part('week-hours-leisure').data, '5 h de détente');
    final wrap = tester.widget<Wrap>(find.ancestor(of: find.byKey(const ValueKey('week-hours-basic')), matching: find.byType(Wrap)));
    expect(wrap.children.map((w) => (w.key as ValueKey).value), ['week-hours-basic', 'week-hours-sleep', 'week-hours-leisure', 'week-hours-free']);
  });

  testWidgets('carte des 7 jours : sans chrono, une ligne dit où sera le vert demain si rien', (tester) async {
    final logic = AppLogic(AppState(domains: [], activities: [], sessions: [], habitProgress: []), () {});
    const idle = WeekHours(activeMin: 4075, basicMin: 465, sleepMin: 2912, leisureMin: 22, prevActiveMin: 3360, leavingMin: 747, dayActive: [], days: []);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SizedBox(width: 360, child: WeekHoursCard(logic: logic, hours: idle)))));
    Text inLine(String key) => tester.widgetList<Text>(find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(Text))).last;
    expect(find.descendant(of: find.byKey(const ValueKey('week-hours-tomorrow')), matching: find.text('Demain si rien')), findsOneWidget);
    expect(inLine('week-hours-tomorrow').data, '55 h · −12 h 27');
    expect(inLine('week-hours-tomorrow').style?.color, kHoursLoss);
    expect(tester.takeException(), isNull);
    // Rien ne sort : en vert.
    const keep = WeekHours(activeMin: 600, basicMin: 0, sleepMin: 0, prevActiveMin: 0, leavingMin: 0, dayActive: [], days: []);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SizedBox(width: 360, child: WeekHoursCard(logic: logic, hours: keep)))));
    expect(inLine('week-hours-tomorrow').data, '10 h · rien ne sort');
    expect(inLine('week-hours-tomorrow').style?.color, kHoursActive);
    // Sans chrono, l'autre bout aussi : demain à fond (24 h entrent, rien ne sort).
    expect(find.descendant(of: find.byKey(const ValueKey('week-hours-full')), matching: find.text('Demain à fond')), findsOneWidget);
    expect(inLine('week-hours-full').data, '34 h · +24 h');
    expect(inLine('week-hours-full').style?.color, kHoursActive);
    // Un chrono actif tourne : l'aiguille montre demain à fond, les deux lignes restent.
    const running = WeekHours(activeMin: 600, basicMin: 0, sleepMin: 0, prevActiveMin: 0, leavingMin: 120, dayActive: [], days: [], nowKind: HoursKind.active, nowName: 'Coder');
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SizedBox(width: 360, child: WeekHoursCard(logic: logic, hours: running)))));
    expect(inLine('week-hours-tomorrow').data, '8 h · −2 h');
    expect(inLine('week-hours-full').data, '32 h · +22 h');
    // Un autre chrono (sommeil) : l'aiguille le suit, les lignes de demain disparaissent.
    const asleep = WeekHours(activeMin: 600, basicMin: 0, sleepMin: 60, prevActiveMin: 0, leavingMin: 120, dayActive: [], days: [], nowKind: HoursKind.sleep, nowName: 'Sommeil');
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SizedBox(width: 360, child: WeekHoursCard(logic: logic, hours: asleep)))));
    expect(find.byKey(const ValueKey('week-hours-tomorrow')), findsNothing);
    expect(find.byKey(const ValueKey('week-hours-full')), findsNothing);
  });

  testWidgets('carte des 7 jours : deux lignes disent l\'aiguille (maintenant) et le triangle (il y a 7 jours)', (tester) async {
    final logic = AppLogic(AppState(domains: [], activities: [], sessions: [], habitProgress: []), () {});
    const h = WeekHours(
        activeMin: 62 * 60, basicMin: 120, sleepMin: 52 * 60, leisureMin: 5 * 60, prevActiveMin: 0, leavingMin: 0, dayActive: [], days: [],
        nowKind: HoursKind.leisure, nowName: 'Jeux vidéo', pastKind: HoursKind.active, pastName: 'Coder');
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SizedBox(width: 360, child: WeekHoursCard(logic: logic, hours: h)))));
    Text inLine(String key) => tester.widgetList<Text>(find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(Text))).last;
    expect(find.descendant(of: find.byKey(const ValueKey('week-hours-now')), matching: find.text('Maintenant')), findsOneWidget);
    expect(inLine('week-hours-now').data, 'Détente · Jeux vidéo');
    expect(inLine('week-hours-now').style?.color, kHoursLeisure);
    expect(find.descendant(of: find.byKey(const ValueKey('week-hours-past')), matching: find.text('Il y a 7 jours')), findsOneWidget);
    expect(inLine('week-hours-past').data, 'Actif · Coder');
    expect(inLine('week-hours-past').style?.color, kHoursActive);
    expect(tester.takeException(), isNull);
  });

  testWidgets('deux domaines de sport devinés : une seule tuile Sport', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(720, 4000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final st = AppState(domains: [Domain(id: 'm', name: 'Musculation'), Domain(id: 'sp', name: 'Sport')], activities: [], sessions: [], habitProgress: []);
    final logic = AppLogic(st, () {})..dayStartMin = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: LifeView(logic: logic, sync: FirestoreSync(), projects: const [], onOpenDomain: (d) async => null, onOpenSleep: () {}, onManageDomains: () {})),
    ));
    await tester.pump();
    await tester.pump();
    expect(find.text('SPORT'), findsOneWidget);
  });
}
