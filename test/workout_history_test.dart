import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/workouts.dart';
import 'package:productivitwo_v1/widgets/workout_history.dart';

AppLogic _logic() {
  final st = AppState(domains: [], activities: [], sessions: [], habitProgress: []);
  final logic = AppLogic(st, () {})..dayStartMin = 0;
  logic.gym = const Gym(exercises: {'bench': Exercise(id: 'bench', name: 'Développé couché', gear: 'banc')});
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day, 18);
  String ymd(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  final before = today.subtract(const Duration(days: 3));
  logic.workouts = [
    Workout(id: 'a', templateId: 'haut', name: 'Haut du corps', ymd: ymd(before), startAt: before.millisecondsSinceEpoch, endAt: before.millisecondsSinceEpoch + 50 * 60000, sets: [
      SetLog(exerciseId: 'bench', reps: 10, weightKg: 40, at: before.millisecondsSinceEpoch + 60000),
      SetLog(exerciseId: 'bench', reps: 9, weightKg: 40, restSec: 100, at: before.millisecondsSinceEpoch + 120000),
    ]),
    Workout(id: 'b', templateId: 'haut', name: 'Haut du corps', ymd: ymd(today), startAt: today.millisecondsSinceEpoch, endAt: today.millisecondsSinceEpoch + 52 * 60000, sets: [
      SetLog(exerciseId: 'bench', reps: 10, weightKg: 42.5, at: today.millisecondsSinceEpoch + 60000),
      SetLog(exerciseId: 'bench', reps: 10, weightKg: 42.5, restSec: 92, at: today.millisecondsSinceEpoch + 120000),
    ]),
  ];
  return logic;
}

void main() {
  setUp(() {});

  testWidgets('Mes séances : la semaine, les dernières séances avec l\'écart', (tester) async {
    tester.view.physicalSize = const Size(780, 2600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: WorkoutsView(logic: _logic()))));
    await tester.pump();
    expect(find.text('DERNIÈRES SÉANCES'), findsOneWidget);
    expect(find.byKey(const ValueKey('workout-b')), findsOneWidget);
    expect(find.text('+12 %'), findsOneWidget);
    await tester.tap(find.text('Mois'));
    await tester.pump();
    expect(find.textContaining('CE MOIS-CI'), findsOneWidget);
  });

  testWidgets('Une séance passée : le contenu série par série, le record', (tester) async {
    tester.view.physicalSize = const Size(780, 2600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final logic = _logic();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: WorkoutDetail(logic: logic, workout: logic.workouts.last))));
    await tester.pump();
    expect(find.text('LE CONTENU · SÉRIE PAR SÉRIE'), findsOneWidget);
    expect(find.text('RECORD'), findsOneWidget);
    expect(find.text('10 × 42,5'), findsNWidgets(2));
    expect(find.text('Refaire cette séance'), findsOneWidget);
  });

  testWidgets('Fiche d\'un exercice : record, depuis le début, dernières séances', (tester) async {
    tester.view.physicalSize = const Size(780, 2600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ExerciseFiche(logic: _logic(), exerciseId: 'bench'))));
    await tester.pump();
    expect(find.text('Développé couché'), findsOneWidget);
    expect(find.textContaining('2 séances'), findsOneWidget);
    expect(find.text('+2,5 kg'), findsOneWidget);
    expect(find.text('10, 10 à 42,5 kg'), findsOneWidget);
    expect(find.text('10, 9 à 40 kg'), findsOneWidget);
    await tester.tap(find.text('Repos'));
    await tester.pump();
  });
}
