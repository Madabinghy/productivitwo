import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/workouts.dart';
import 'package:productivitwo_v1/widgets/workout_screens.dart';

AppLogic _logic() {
  final st = AppState(domains: [Domain(id: 'sp', name: 'Sport')], activities: [], sessions: [], habitProgress: []);
  final logic = AppLogic(st, () {})..dayStartMin = 0;
  logic.gym = const Gym(
    exercises: {'bench': Exercise(id: 'bench', name: 'Développé couché', gear: 'banc')},
    templates: {
      'haut': WorkoutTemplate(id: 'haut', name: 'Haut du corps', place: kPlaceHome, items: [TemplateItem(exerciseId: 'bench', sets: 2, reps: 10, weightKg: 40)]),
    },
  );
  logic.workouts = [
    const Workout(id: 'w0', templateId: 'haut', name: 'Haut du corps', ymd: '2026-10-30', startAt: 1000, endAt: 1000 + 40 * 60000, sets: [
      SetLog(exerciseId: 'bench', reps: 10, weightKg: 40, at: 2000),
      SetLog(exerciseId: 'bench', reps: 10, weightKg: 40, at: 3000),
    ]),
  ];
  return logic;
}

void main() {
  testWidgets('Ma séance : la séance type, la dernière fois, le poids proposé', (tester) async {
    tester.view.physicalSize = const Size(780, 2400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final logic = _logic();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: WorkoutHub(logic: logic))));
    await tester.pump();
    expect(find.text('Haut du corps'), findsWidgets);
    expect(find.text('Développé couché · banc'), findsOneWidget);
    expect(find.textContaining('dernière fois : 10 × 40 kg, 10 × 40 kg'), findsOneWidget);
    expect(find.textContaining('+2,5 kg proposé'), findsOneWidget);
    expect(find.textContaining('maison'), findsOneWidget);
  });

  testWidgets('Régler un exercice : le repos retenu', (tester) async {
    tester.view.physicalSize = const Size(780, 2400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final logic = _logic();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: WorkoutHub(logic: logic))));
    await tester.pump();
    await tester.tap(find.text('Développé couché · banc'));
    await tester.pumpAndSettle();
    expect(find.text('REPOS ENTRE DEUX SÉRIES'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('rest-120')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('ex-save')));
    await tester.pumpAndSettle();
    expect(logic.gym.exercises['bench']!.restSec, 120);
    expect(find.textContaining('repos 2 min'), findsOneWidget);
  });

  testWidgets('La séance : série, repos, bilan face à la fois d\'avant', (tester) async {
    tester.view.physicalSize = const Size(780, 1700);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final logic = _logic();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (ctx) => TextButton(
            onPressed: () => Navigator.of(ctx).push(MaterialPageRoute(
              builder: (_) => WorkoutPlayer(logic: logic, items: logic.gym.templates['haut']!.items, template: logic.gym.templates['haut'], sideEffects: false),
            )),
            child: const Text('go'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('go'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('SÉRIE 1 / 2'), findsOneWidget);
    expect(find.text('42,5 kg'), findsOneWidget);
    expect(find.textContaining('aujourd\'hui +2,5 kg'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('set-done')));
    await tester.pump();
    expect(find.text('REPOS · DÉVELOPPÉ COUCHÉ'), findsOneWidget);
    expect(find.text('1:30'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('rest-plus')));
    await tester.pump();
    expect(find.text('Garder 1 min 45 pour cet exercice'), findsOneWidget);
    await tester.tap(find.text('Garder 1 min 45 pour cet exercice'));
    await tester.pump();
    expect(logic.gym.exercises['bench']!.restSec, 105);
    await tester.tap(find.byKey(const ValueKey('rest-go')));
    await tester.pump();
    expect(find.text('SÉRIE 2 / 2'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('set-done')));
    await tester.pump();
    expect(find.text('Mieux que ven.'), findsOneWidget);
    expect(find.text('RECORD'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('workout-save')));
    await tester.pump();
    final saved = logic.workouts.firstWhere((w) => w.id != 'w0');
    expect(saved.sets.length, 2);
    expect(saved.sets.first.weightKg, 42.5);
    expect(saved.sets.last.restSec, isNotNull);
    expect(saved.endAt, isNotNull);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('Séance enregistrée · 2 séries'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });
}
