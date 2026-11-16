import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/engagement_stats.dart' show ymdOf;
import 'package:productivitwo_v1/utils/week_capacity.dart';
import 'package:productivitwo_v1/utils/week_planner.dart' show weekStart;
import 'package:productivitwo_v1/web/views/week_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeSync extends FirestoreSync {
  final Map<String, DailySchedule> docs;
  final upserts = <ScheduleBlock>[];
  _FakeSync(this.docs);

  @override
  String? get uid => 'u';
  @override
  Stream<DailySchedule?> streamDailySchedule(String date) => Stream.value(docs[date]);
  @override
  Stream<List<Session>> streamSessions() => Stream.value(const []);
  @override
  Stream<List<HabitHit>> streamHabitHits() => Stream.value(const []);
  @override
  Future<Map<String, int>> fetchWeekCapacity() async => {};
  @override
  Future<DayWindow> fetchDayWindow() async => const DayWindow(8 * 60, 22 * 60);
  @override
  Future<ApiToken> ensureWidgetToken() async => throw StateError('hors ligne');
  @override
  Future<void> upsertScheduleBlock(String date, ScheduleBlock block, {bool rememberMirror = true}) async =>
      upserts.add(ScheduleBlock.from(block.toJson()));
}

void main() {
  testWidgets('une activité glissée sur un Deep work s’y ajoute, sans créer de bloc', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1700, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // Dimanche de la semaine affichée : jamais un jour passé.
    final sunday = weekStart(DateTime.now()).add(const Duration(days: 6));
    final key = ymdOf(sunday);
    final deep = ScheduleBlock(
        id: 'deep1', startTime: '23:00', durationMin: 59, title: 'Deep work', category: 'project', timeBlock: 'deep');
    final sync = _FakeSync({key: DailySchedule(date: key, generatedBy: 'user', blocks: [deep])});
    final activities = [Activity(id: 'a1', domainId: 'd1', name: 'Interventions', goalMin: 120)];

    await tester.pumpWidget(MaterialApp(
      // La police de test est plus haute que la vraie : texte réduit pour
      // garder la mise en page de l'écran.
      builder: (ctx, child) =>
          MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: const TextScaler.linear(.7)), child: child!),
      home: Scaffold(
        body: WeekView(
          projects: const [],
          domains: [Domain(id: 'd1', name: 'Travail')],
          sync: sync,
          onOpenProject: (p, {taskId}) {},
          dayStartMin: 0,
          activities: activities,
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    final row = find.byKey(const ValueKey('week-place-watch:a1'));
    final block = find.byKey(const ValueKey('week-block-deep1'));
    expect(row, findsOneWidget);
    await tester.ensureVisible(block);
    await tester.pump(const Duration(milliseconds: 50));

    final g = await tester.startGesture(tester.getCenter(row));
    await tester.pump(const Duration(milliseconds: 20));
    await g.moveBy(const Offset(30, 10));
    await tester.pump(const Duration(milliseconds: 20));
    await g.moveTo(tester.getCenter(block));
    await tester.pump(const Duration(milliseconds: 20));
    // Le bloc survolé annonce ce qu'il va recevoir.
    expect(find.byKey(const ValueKey('week-stack-deep1')), findsOneWidget);
    await g.up();
    await tester.pump(const Duration(milliseconds: 50));

    expect(sync.upserts, hasLength(1));
    final saved = sync.upserts.single;
    expect(saved.id, 'deep1');
    expect(saved.timeBlock, 'deep');
    expect(saved.activityId, 'a1');
    expect(saved.title, 'Deep work · Interventions');

    // Le message « ajouté à … · Annuler » se ferme, puis la vue est retirée.
    expect(find.textContaining('ajouté à « Deep work »'), findsOneWidget);
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(seconds: 3));
    }
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
  testWidgets('une deuxième tâche glissée sur un bloc de tâche s’ajoute aux cibles', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1700, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final sunday = weekStart(DateTime.now()).add(const Duration(days: 6));
    final key = ymdOf(sunday);
    final project = Project(id: 'p1', title: 'Maths 6e', startDate: sunday, createdBy: 'user', tasks: [
      ProjectTask(id: 't1', title: 'Préparer la séance', startDate: sunday),
      ProjectTask(id: 't2', title: 'Corriger les copies', startDate: sunday, endDate: sunday),
    ]);
    final block = ScheduleBlock(
        id: 'b1', startTime: '23:00', durationMin: 59, title: 'Préparer la séance', category: 'project', projectId: 'p1', taskId: 't1');
    final sync = _FakeSync({key: DailySchedule(date: key, generatedBy: 'user', blocks: [block])});

    await tester.pumpWidget(MaterialApp(
      builder: (ctx, child) =>
          MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: const TextScaler.linear(.7)), child: child!),
      home: Scaffold(
        body: WeekView(
          projects: [project],
          domains: const [],
          sync: sync,
          onOpenProject: (p, {taskId}) {},
          dayStartMin: 0,
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    // t1 a son bloc : seule t2 reste « à placer ».
    final row = find.byKey(const ValueKey('week-place-due:t2'));
    final target = find.byKey(const ValueKey('week-block-b1'));
    expect(row, findsOneWidget);
    expect(find.byKey(const ValueKey('week-place-due:t1')), findsNothing);
    await tester.ensureVisible(target);
    await tester.pump(const Duration(milliseconds: 50));

    final g = await tester.startGesture(tester.getCenter(row));
    await tester.pump(const Duration(milliseconds: 20));
    await g.moveBy(const Offset(30, 10));
    await tester.pump(const Duration(milliseconds: 20));
    await g.moveTo(tester.getCenter(target));
    await tester.pump(const Duration(milliseconds: 20));
    await g.up();
    await tester.pump(const Duration(milliseconds: 50));

    final saved = sync.upserts.single;
    expect((saved.projectId, saved.taskId), ('p1', 't1'));
    expect(saved.extraTargets, [const BlockTarget(projectId: 'p1', taskId: 't2')]);
    expect(saved.title, 'Préparer la séance + 1');
    // Posée dans le bloc, t2 n'est plus « à placer ».
    expect(find.byKey(const ValueKey('week-place-due:t2')), findsNothing);

    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(seconds: 3));
    }
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}
