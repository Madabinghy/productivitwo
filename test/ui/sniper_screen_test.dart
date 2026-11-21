import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/coup_alarm.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/run_session_store.dart';
import 'package:productivitwo_v1/utils/routine_moments.dart';
import 'package:productivitwo_v1/utils/sniper.dart';
import 'package:productivitwo_v1/utils/sniper_scope.dart';
import 'package:productivitwo_v1/utils/stakes.dart';
import 'package:productivitwo_v1/widgets/sniper_scope.dart';
import 'package:productivitwo_v1/widgets/sniper_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    CoupAlarm.enabled = false;
  });
  tearDown(() => CoupAlarm.enabled = true);

  final lecture = Activity(id: 'lec', domainId: 'd', name: 'Lecture', goalMin: 30);
  final pompes = Activity(id: 'pom', domainId: 'd', name: 'Pompes', type: 'habit', habitFreq: HabitFreq.daily, habitTarget: 1);

  List<Stake> stakes() => [
        Stake(
          StakeGesture(key: 'activity:lec', kind: StakeGestureKind.activity, title: 'Lecture', costMin: 12, activity: lecture),
          [const StakeGain(kind: StakeGainKind.halfDay, label: 'Montre suisse · 3 / 4', weight: 10)],
        ),
        Stake(
          StakeGesture(key: 'routine:pom', kind: StakeGestureKind.routine, title: 'Pompes', costMin: 5, activity: pompes),
          [const StakeGain(kind: StakeGainKind.seriesTonight, label: 'Série de 12 j', weight: 30, losesTonight: true)],
        ),
      ];

  Future<AppLogic> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final st = AppState(domains: [Domain(id: 'd', name: 'Vie')], activities: [lecture, pompes], sessions: [], habitProgress: []);
    final logic = AppLogic(st, () {})..dayStartMin = 0;
    await tester.pumpWidget(MaterialApp(home: SniperScreen(logic: logic, stakes: stakes())));
    await tester.pump();
    await tester.pump();
    return logic;
  }

  /// Le minuteur d'un tir tourne chaque seconde : on démonte l'écran avant la fin du test.
  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  }

  testWidgets('Sniper : sans enjeu, le viseur le dit et rien ne se lance', (tester) async {
    tester.view.physicalSize = const Size(780, 1700);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final st = AppState(domains: [], activities: [], sessions: [], habitProgress: []);
    final logic = AppLogic(st, () {})..dayStartMin = 0;
    await tester.pumpWidget(MaterialApp(home: SniperScreen(logic: logic)));
    await tester.pump();
    await tester.pump();
    // La lunette est là, vide : tout le tour est de l'air.
    expect(find.byKey(const Key('sniper-aim-scope')), findsOneWidget);
    expect(find.textContaining('Aucune cible', findRichText: true), findsOneWidget);
    expect(find.text('Rien à viser'), findsOneWidget);
    expect(find.textContaining('Rien en jeu pour l’instant'), findsOneWidget);
    await close(tester);
  });

  testWidgets('Sniper par moment : ce qui reste d’avant, le moment, le reste, et « Plus tard » à ajouter', (tester) async {
    tester.view.physicalSize = const Size(800, 2200);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final dents = Activity(id: 'den', domainId: 'd', name: 'Dents', type: 'habit', habitFreq: HabitFreq.daily, habitTarget: 1);
    final marche = Activity(id: 'mar', domainId: 'd', name: 'Marche', type: 'habit', habitFreq: HabitFreq.daily, habitTarget: 1);
    Stake plain(Activity a) => Stake(
          StakeGesture(key: 'routine:${a.id}', kind: StakeGestureKind.routine, title: a.name, costMin: 5, activity: a),
          [const StakeGain(kind: StakeGainKind.routine, label: '0 / 1 aujourd’hui', weight: 4)],
        );
    final st = AppState(domains: [Domain(id: 'd', name: 'Vie')], activities: [lecture, pompes, dents, marche], sessions: [], habitProgress: []);
    final logic = AppLogic(st, () {})..dayStartMin = 0;
    // Le dernier moment de la journée : sa fin ne raccourcit pas la lunette, quelle que soit l'heure du test.
    final scope = SniperScope(
      moment: kMoments.firstWhere((m) => m.key == kMomentEvening),
      section: const {'routine:pom': kSniperSecLeft, 'routine:den': kSniperSecMoment},
      later: const {'routine:mar': 'demain matin'},
      laterOrder: const ['demain matin'],
      leftLabel: 'RESTE DE L’APRÈS-MIDI',
    );
    await tester.pumpWidget(MaterialApp(home: SniperScreen(logic: logic, stakes: [...stakes(), plain(dents), plain(marche)], scope: scope)));
    await tester.pump();
    await tester.pump();
    expect(find.text('SNIPER · CE SOIR'), findsOneWidget);
    expect(find.text('RESTE DE L’APRÈS-MIDI · 1'), findsOneWidget);
    expect(find.text('CE SOIR · 1'), findsOneWidget);
    expect(find.text('AUSSI EN JEU · 1'), findsOneWidget);
    // L'ordre : Pompes (restée), Dents (ce soir, même sans autre enjeu), Lecture (le reste).
    double y(String t) => tester.getTopLeft(find.text(t)).dy;
    expect(y('Pompes'), lessThan(y('Dents')));
    expect(y('Dents'), lessThan(y('Lecture')));
    expect(find.text('Marche'), findsNothing);
    expect(find.textContaining('3 cibles', findRichText: true), findsWidgets);
    // « Plus tard » : une ligne, qui s'ouvre ; toucher la routine l'ajoute au viseur.
    expect(find.text('Plus tard · 1 demain matin'), findsOneWidget);
    await tester.tap(find.byKey(const Key('sniper-later')));
    await tester.pump();
    expect(find.text('plus tard · demain matin'), findsOneWidget);
    await tester.tap(find.text('Marche'));
    await tester.pump();
    expect(find.textContaining('4 cibles', findRichText: true), findsWidgets);
    expect(find.byKey(const Key('sniper-later')), findsNothing);
    await close(tester);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('viseur : la lunette, les cibles numérotées dans l’ordre des tirs', (tester) async {
    await open(tester);
    expect(find.byKey(const Key('sniper-aim-scope')), findsOneWidget);
    expect(find.textContaining('LIBRE JUSQU’À'), findsOneWidget);
    expect(find.textContaining('2 cibles', findRichText: true), findsWidgets);
    // Ce qui se perd ce soir d'abord : Pompes porte le 1, Lecture le 2.
    final one = tester.getTopLeft(find.text('1')).dy, two = tester.getTopLeft(find.text('2')).dy;
    expect(tester.getTopLeft(find.text('Pompes')).dy, closeTo(one, 12));
    expect(tester.getTopLeft(find.text('Lecture')).dy, closeTo(two, 12));
    expect(find.textContaining('Tirer · 2 cibles'), findsOneWidget);
    // Toucher une cible l'écarte : son numéro part, l'autre devient la première.
    await tester.tap(find.text('Pompes'));
    await tester.pump();
    expect(find.textContaining('Tirer · 1 cible ·'), findsOneWidget);
    expect(find.text('2'), findsNothing);
    await close(tester);
  });

  testWidgets('tir, impact, le tir suivant attend « Tirer », puis le carton', (tester) async {
    final logic = await open(tester);
    await tester.tap(find.textContaining('Tirer · 2 cibles'));
    await tester.pump();
    expect(find.text('TIR 1 / 2'), findsOneWidget);
    expect(find.byType(SniperMagazine), findsOneWidget);
    // Premier tir : la routine, un geste sans minuteur.
    await tester.tap(find.text('+1 · touché'));
    await tester.pump();
    expect(find.text('TOUCHÉ'), findsOneWidget);
    expect(find.byType(SniperImpactScope), findsOneWidget);
    expect(find.text('TIR 2 · QUAND TU VEUX'), findsOneWidget);
    expect(logic.state.habitHits.where((h) => h.habitId == 'pom').length, 1);
    // Au bout de l'impact, rien ne s'enchaîne : le tir suivant attend « Tirer ».
    await tester.pump(kSniperImpact * 2);
    await tester.pump();
    expect(find.text('TOUCHÉ'), findsOneWidget);
    expect(logic.runningActivity(), isNull);
    // Toucher l'écran ne lance rien non plus.
    await tester.tap(find.byKey(const Key('sniper-impact')));
    await tester.pump();
    expect(find.text('TOUCHÉ'), findsOneWidget);
    await tester.tap(find.text('Tirer · Lecture'));
    await tester.pump();
    expect(find.text('TOUCHÉ'), findsNothing);
    expect(find.text('TIR 2 / 2'), findsOneWidget);
    expect(find.byKey(const Key('sniper-shot-scope')), findsOneWidget);
    expect(logic.runningActivity()?.id, 'lec');
    // Dernier tir : l'impact propose le bilan.
    await tester.tap(find.text('Fait plus tôt · suivant'));
    await tester.pump();
    expect(find.text('TOUCHÉ'), findsOneWidget);
    await tester.tap(find.text('Voir le bilan'));
    await tester.pump();
    expect(find.text('2 / 2 cibles touchées'), findsOneWidget);
    expect(find.byKey(const Key('sniper-card')), findsOneWidget);
    expect(find.text('précision'), findsOneWidget);
    await close(tester);
  });

  testWidgets('tir de routine liée à une activité : le chrono se lance d’ici, le tir qui tombe l’arrête', (tester) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final cafeAct = Activity(id: 'cafa', domainId: 'd', name: 'Pause café');
    final cafe = Activity(id: 'caf', domainId: 'd', name: 'Café', type: 'habit', habitFreq: HabitFreq.daily, habitTarget: 1, linkedActivityId: 'cafa');
    final st = AppState(domains: [Domain(id: 'd', name: 'Vie')], activities: [cafeAct, cafe, lecture], sessions: [], habitProgress: []);
    final logic = AppLogic(st, () {})..dayStartMin = 0;
    final s = [
      Stake(StakeGesture(key: 'routine:caf', kind: StakeGestureKind.routine, title: 'Café', costMin: 5, activity: cafe),
          [const StakeGain(kind: StakeGainKind.seriesTonight, label: 'Série de 4 j', weight: 30, losesTonight: true)]),
      Stake(StakeGesture(key: 'activity:lec', kind: StakeGestureKind.activity, title: 'Lecture', costMin: 12, activity: lecture),
          [const StakeGain(kind: StakeGainKind.halfDay, label: 'Montre suisse · 3 / 4', weight: 10)]),
    ];
    await tester.pumpWidget(MaterialApp(home: SniperScreen(logic: logic, stakes: s)));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.textContaining('Tirer · 2 cibles'));
    await tester.pump();
    expect(find.text('TIR 1 / 2'), findsOneWidget);
    expect(find.text('▶ Chrono · Pause café'), findsOneWidget);
    await tester.tap(find.byKey(const Key('sniper-routine-chrono')));
    await tester.pump();
    expect(logic.runningActivity()?.id, 'cafa');
    expect(find.text('■ Arrêter le chrono'), findsOneWidget);
    expect(find.textContaining('chrono sur Pause café'), findsOneWidget);
    await tester.tap(find.text('+1 · touché'));
    await tester.pump();
    expect(logic.state.habitHits.where((h) => h.habitId == 'caf').length, 1);
    expect(logic.runningActivity(), isNull);
    await tester.tap(find.byKey(const Key('sniper-next')));
    await tester.pump();
    // Un tir minuté a déjà son chrono : pas de bouton en plus.
    expect(find.text('TIR 2 / 2'), findsOneWidget);
    expect(find.byKey(const Key('sniper-routine-chrono')), findsNothing);
    await close(tester);
    await RunSessionStore.clear();
  });

  testWidgets('refermé puis rouvert : une cible déjà touchée garde sa place, le compteur ne rétrécit pas', (tester) async {
    final logic = await open(tester);
    await tester.tap(find.textContaining('Tirer · 2 cibles'));
    await tester.pump();
    await tester.tap(find.text('+1 · touché'));
    await tester.pump();
    expect(find.text('TOUCHÉ'), findsOneWidget);
    await close(tester);
    final p = RunSessionStore.current!;
    expect(p.strings('hit'), ['routine:pom']);

    // Pompes est atteinte : elle n'est plus dans les enjeux du jour.
    for (var i = 0; i < 2; i++) {
      await tester.pumpWidget(MaterialApp(home: SniperScreen(logic: logic, stakes: [stakes().first], resume: RunSessionStore.current)));
      await tester.pump();
      await tester.pump();
      expect(find.text('TIR 1 / 2'), findsOneWidget);
      expect(find.text('Tirer · Lecture'), findsOneWidget);
      await close(tester);
    }
    await tester.pumpWidget(MaterialApp(home: SniperScreen(logic: logic, stakes: [stakes().first], resume: RunSessionStore.current)));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text('Tirer · Lecture'));
    await tester.pump();
    expect(find.text('TIR 2 / 2'), findsOneWidget);
    await close(tester);
    await RunSessionStore.clear();
  });

  testWidgets('viseur retouché puis refermé : le Sniper est prêt, rien n’est lancé, la sélection revient à la réouverture', (tester) async {
    final logic = await open(tester);
    // Rien de retouché : pas de « Je m'arrête », et refermer ne garde rien.
    expect(find.byKey(const Key('sniper-drop')), findsNothing);
    await close(tester);
    expect(RunSessionStore.current, isNull);

    await tester.pumpWidget(MaterialApp(home: SniperScreen(logic: logic, stakes: stakes())));
    await tester.pump();
    await tester.pump();
    // Lecture est écartée : il ne reste que Pompes.
    await tester.tap(find.text('Lecture'));
    await tester.pump();
    expect(find.textContaining('1 cible', findRichText: true), findsWidgets);
    expect(find.byKey(const Key('sniper-drop')), findsOneWidget);
    await close(tester);
    final p = RunSessionStore.current!;
    expect(p.prepared, isTrue);
    expect(p.strings('aimed'), ['routine:pom']);
    expect(p.done, 0);
    expect(logic.state.sessions, isEmpty);
    // Il attend toute la journée vécue, pas seulement 45 minutes.
    expect(p.isLive(DateTime.now().add(const Duration(hours: 3)), p.date), isTrue);

    // Rouvert : « SNIPER PRÊT », la même sélection, toujours rien de lancé.
    await tester.pumpWidget(MaterialApp(home: SniperScreen(logic: logic, stakes: stakes(), resume: p)));
    await tester.pump();
    await tester.pump();
    expect(find.text('SNIPER PRÊT'), findsOneWidget);
    expect(find.byKey(const Key('sniper-aim-scope')), findsOneWidget);
    expect(find.textContaining('1 cible', findRichText: true), findsWidgets);
    expect(logic.state.sessions, isEmpty);

    // « Je m'arrête » : le Sniper préparé est abandonné, l'ordre conseillé revient.
    await tester.tap(find.byKey(const Key('sniper-drop')));
    await tester.pump();
    expect(RunSessionStore.current, isNull);
    expect(find.text('SNIPER PRÊT'), findsNothing);
    expect(find.textContaining('2 cibles', findRichText: true), findsWidgets);
    // Le message « Sniper abandonné » se referme tout seul.
    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(seconds: 1));
    await close(tester);
    expect(RunSessionStore.current, isNull);
  });

  testWidgets('Sniper prêt puis « Tirer » : la session démarre et n’est plus seulement préparée', (tester) async {
    final logic = await open(tester);
    await tester.tap(find.text('Lecture'));
    await tester.pump();
    await close(tester);
    final p = RunSessionStore.current!;
    await tester.pumpWidget(MaterialApp(home: SniperScreen(logic: logic, stakes: stakes(), resume: p)));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.textContaining('Tirer · 1 cible'));
    await tester.pump();
    expect(RunSessionStore.current?.prepared, isFalse);
    expect(RunSessionStore.current?.runId, p.runId);
    await RunSessionStore.clear();
    await close(tester);
  });

  testWidgets('le Sniper s’ouvre en feuille, sans croix', (tester) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final st = AppState(domains: [], activities: [], sessions: [], habitProgress: []);
    final logic = AppLogic(st, () {})..dayStartMin = 0;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (ctx) => Scaffold(body: Center(child: TextButton(onPressed: () => showSniperScreen(ctx, logic), child: const Text('ouvrir'))))),
    ));
    await tester.tap(find.text('ouvrir'));
    await tester.pumpAndSettle();
    expect(find.byType(DraggableScrollableSheet), findsOneWidget);
    expect(find.byKey(const Key('sniper-sheet-handle')), findsOneWidget);
    expect(find.byKey(const Key('sniper-aim-scope')), findsOneWidget);
    expect(find.byTooltip('Fermer'), findsNothing);
    expect(find.byIcon(Icons.close), findsNothing);
    // Toucher au-dessus de la feuille la referme.
    await tester.tapAt(const Offset(200, 10));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('sniper-aim-scope')), findsNothing);
    expect(find.text('ouvrir'), findsOneWidget);
  });

  testWidgets('refermée pendant un tir, la feuille n’arrête rien : le chrono continue, la session attend', (tester) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final st = AppState(domains: [Domain(id: 'd', name: 'Vie')], activities: [lecture, pompes], sessions: [], habitProgress: []);
    final logic = AppLogic(st, () {})..dayStartMin = 0;
    await tester.pumpWidget(MaterialApp(home: SniperScreen(logic: logic, stakes: [stakes().first])));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.textContaining('Tirer · 1 cible'));
    await tester.pump();
    expect(find.byKey(const Key('sniper-shot-scope')), findsOneWidget);
    expect(logic.runningActivity()?.id, 'lec');
    await close(tester);
    expect(logic.runningActivity()?.id, 'lec');
    expect(RunSessionStore.current?.extra['cur'], 'activity:lec');
    expect(RunSessionStore.current?.extra['endsAt'], isNotNull);
    await tester.pump(const Duration(seconds: 5));
    await RunSessionStore.clear();
    logic.stopActive(notify: false);
  });
}
