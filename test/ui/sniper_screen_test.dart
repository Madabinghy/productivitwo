import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/coup_alarm.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/run_session_store.dart';
import 'package:productivitwo_v1/utils/run_session.dart';
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
    // Une Lecture courte : le soir, il ne reste parfois qu'un quart d'heure avant la fin de la journée active (22 h),
    // les quatre cibles doivent y tenir quelle que soit l'heure du test.
    final shortLecture = Stake(
      StakeGesture(key: 'activity:lec', kind: StakeGestureKind.activity, title: 'Lecture', costMin: 5, activity: lecture),
      [const StakeGain(kind: StakeGainKind.halfDay, label: 'Montre suisse · 3 / 4', weight: 10)],
    );
    await tester.pumpWidget(MaterialApp(home: SniperScreen(logic: logic, stakes: [shortLecture, stakes()[1], plain(dents), plain(marche)], scope: scope)));
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

  testWidgets('bilan : une cible faite ailleurs ne compte ni sur le carton ni dans la précision, et l’écran le dit', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final st = AppState(domains: [Domain(id: 'd', name: 'Vie')], activities: [lecture, pompes], sessions: [], habitProgress: []);
    final logic = AppLogic(st, () {})..dayStartMin = 0;
    final now = DateTime.now();
    // Pompes est tombée hors du Sniper : touchée, sans temps de tir.
    final p = PendingRun(
      kind: kSniperKind,
      runId: 'r1',
      date: '2026-01-01',
      startedAt: now.subtract(const Duration(minutes: 5)),
      lastActiveAt: now,
      done: 1,
      extra: const {
        'aimed': ['routine:pom', 'activity:lec'],
        'hit': ['routine:pom'],
        'skipped': <String>[],
        'fired': <String, int>{},
        'total': 2,
      },
    );
    await tester.pumpWidget(MaterialApp(home: SniperScreen(logic: logic, stakes: stakes(), resume: p)));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text('Tirer · Lecture'));
    await tester.pump();
    await tester.tap(find.text('Fait plus tôt · suivant'));
    await tester.pump();
    await tester.tap(find.text('Voir le bilan'));
    await tester.pump();
    expect(find.text('2 / 2 cibles touchées'), findsOneWidget);
    expect(find.text('Pompes faite ailleurs · hors carton'), findsOneWidget);
    expect(find.text('sur 1 tir'), findsOneWidget);
    expect(find.text('précision'), findsNothing);
    expect(find.text('faite ailleurs'), findsOneWidget);
    // Seule Lecture compte dans les minutes visées.
    expect(find.text('12 min'), findsOneWidget);
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

  testWidgets('Sniper dans le bloc en cours : la lunette couvre le bloc, ses actions dans son ordre ; « Après le bloc » attend sa fin', (tester) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final now = DateTime.now();
    var start = now.hour * 60 + now.minute - 10;
    if (start < 0) start = 0;
    String hm(int m) => '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
    final d0 = DateTime(now.year, now.month, now.day);
    final p = Project(id: 'p', title: 'Maths 6e', startDate: d0, createdBy: 'u', tasks: [
      ProjectTask(id: 't', title: 'Préparer la séance', startDate: d0, actions: [
        TaskAction(id: 'a1', title: 'Relire le chapitre', estimatedMin: 10),
        TaskAction(id: 'a2', title: 'Faire les fiches', estimatedMin: 15),
      ]),
    ]);
    final st = AppState(domains: [Domain(id: 'd', name: 'Vie')], activities: [lecture], sessions: [], habitProgress: []);
    final logic = AppLogic(st, () {})..dayStartMin = 0;
    logic.currentProjects = [p];
    logic.todayBlocks = [ScheduleBlock(id: 'b', startTime: hm(start), durationMin: 60, title: 'Préparer la séance', category: 'project', projectId: 'p', taskId: 't', actionId: 'a2')];
    await tester.pumpWidget(MaterialApp(home: SniperScreen(logic: logic)));
    await tester.pump();
    await tester.pump();
    expect(find.text('SNIPER · BLOC EN COURS'), findsOneWidget);
    expect(find.byKey(const Key('sniper-block-card')), findsOneWidget);
    expect(find.text('DANS LE BLOC · DANS SON ORDRE'), findsOneWidget);
    // L'action visée par le bloc passe devant.
    final y1 = tester.getTopLeft(find.text('Faire les fiches')).dy;
    final y2 = tester.getTopLeft(find.text('Relire le chapitre')).dy;
    expect(y1 < y2, isTrue);
    expect(find.text('Tirer · 2 cibles · 27 min'), findsOneWidget);

    // Après le bloc : rien d'autre en jeu, et les tirs attendraient sa fin.
    await tester.tap(find.byKey(const Key('sniper-after-block')));
    await tester.pump();
    expect(find.byKey(const Key('sniper-after-line')), findsOneWidget);
    expect(find.byKey(const Key('sniper-block-card')), findsNothing);

    await tester.tap(find.byKey(const Key('sniper-in-block')));
    await tester.pump();
    await tester.tap(find.text('Tirer · 2 cibles · 27 min'));
    await tester.pump();
    expect(find.text('TIR 1 / 2'), findsOneWidget);
    expect(find.text('Faire les fiches'), findsWidgets);
    // La session retient le bloc : rouverte, elle le retrouve.
    expect(RunSessionStore.current?.extra['block'], 'b');
    await close(tester);
    await RunSessionStore.clear();
  });

  testWidgets('l’activité comme contenant : ses actions dans la même cible, une après l’autre dans le tir', (tester) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final ecrire = TaskAction(id: 'e1', title: 'Écrire la page', estimatedMin: 10);
    final kingdom = Activity(id: 'kin', domainId: 'd', name: 'Kingdom', goalMin: 30, ownActions: [ecrire]);
    final st = AppState(domains: [Domain(id: 'd', name: 'Vie')], activities: [kingdom], sessions: [], habitProgress: []);
    final logic = AppLogic(st, () {})..dayStartMin = 0;
    final stakes = [
      Stake(
        StakeGesture(key: 'activity:kin', kind: StakeGestureKind.activity, title: 'Kingdom', costMin: 12, activity: kingdom),
        [const StakeGain(kind: StakeGainKind.halfDay, label: 'Montre suisse · 3 / 4', weight: 10)],
      ),
      Stake(
        StakeGesture(key: 'action:e1', kind: StakeGestureKind.action, title: 'Écrire la page', costMin: 10, action: ecrire, owner: kingdom),
        [const StakeGain(kind: StakeGainKind.focus, label: 'Visée aujourd’hui', weight: 20)],
      ),
    ];
    await tester.pumpWidget(MaterialApp(home: SniperScreen(logic: logic, stakes: stakes)));
    await tester.pump();
    await tester.pump();
    // Une seule cible : Kingdom contient l'action, le reste est du temps libre.
    expect(find.byKey(const Key('sniper-container-activity:kin')), findsOneWidget);
    expect(find.text('visée aujourd’hui'), findsOneWidget);
    expect(find.text('Temps libre sur Kingdom'), findsOneWidget);
    expect(find.text('Changer les actions ›'), findsOneWidget);
    expect(find.textContaining('Tirer · 1 cible ·'), findsOneWidget);

    await tester.tap(find.textContaining('Tirer · 1 cible ·'));
    await tester.pump();
    expect(find.text('KINGDOM · ACTION 1 SUR 1'), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('sniper-shot-title'))).data, 'Écrire la page');
    await tester.tap(find.byKey(const Key('sniper-step-done')));
    await tester.pump();
    expect(ecrire.done, isTrue);
    expect(find.text('KINGDOM · TEMPS LIBRE'), findsOneWidget);
    expect(RunSessionStore.current?.extra['stepDone'], {'activity:kin': ['action:e1']});
    // La SnackBar « Annuler » se referme d'elle-même avant qu'on démonte l'écran.
    await tester.pump(const Duration(seconds: 6));
    await tester.pump(const Duration(seconds: 1));
    await close(tester);
    await RunSessionStore.clear();
  });
}
