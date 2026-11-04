import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/engagement_stats.dart' show ymdOf;
import 'package:productivitwo_v1/utils/freedom.dart';
import 'package:productivitwo_v1/widgets/freedom_screens.dart';

AppLogic _logic() => AppLogic(AppState(domains: [], activities: [], sessions: [], habitProgress: []), () {});

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('créer une liberté : nom libre, but, pourquoi', (t) async {
    t.view.physicalSize = const Size(800, 4000);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    final logic = _logic();
    await t.pumpWidget(_host(FreedomSetup(logic: logic)));
    expect(find.textContaining('arrêt brutal peut être dangereux'), findsOneWidget);
    await t.enterText(find.byKey(const ValueKey('freedom-name')), 'Ma pause');
    await t.enterText(find.byKey(const ValueKey('freedom-why')), 'Respirer mieux');
    await t.tap(find.text('Stress'));
    await t.ensureVisible(find.byKey(const ValueKey('freedom-save')));
    await t.tap(find.byKey(const ValueKey('freedom-save')));
    await t.pump();
    final p = logic.freedom.plan!;
    expect(p.name, 'Ma pause');
    expect(p.goal, FreedomGoal.stop);
    expect(p.why, 'Respirer mieux');
    expect(p.triggers, ['Stress']);
    expect(p.warned, isTrue);
  });

  testWidgets('la feuille : libre depuis, envies surmontées', (t) async {
    t.view.physicalSize = const Size(800, 4000);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    final logic = _logic();
    final now = DateTime.now();
    logic.freedom = Freedom(
      plan: FreedomPlan(name: 'Ma pause', goal: FreedomGoal.stop, startYmd: ymdOf(now.subtract(const Duration(days: 3))), why: 'Respirer'),
      urges: {'u1': FreedomUrge(id: 'u1', at: now.subtract(const Duration(hours: 5)).millisecondsSinceEpoch, intensity: 3)},
      slips: const {},
    );
    await t.pumpWidget(_host(FreedomView(logic: logic)));
    expect(find.text('Ma pause'), findsOneWidget);
    expect(find.text('LIBRE DEPUIS'), findsOneWidget);
    expect(find.textContaining('3 j'), findsWidgets);
    expect(find.text('1'), findsWidgets);
    expect(find.byKey(const ValueKey('freedom-urge')), findsOneWidget);
  });

  testWidgets("le moment de l'envie : passée = envie surmontée", (t) async {
    t.view.physicalSize = const Size(800, 4000);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    final logic = _logic();
    logic.freedom = Freedom(
      plan: FreedomPlan(name: 'Ma pause', goal: FreedomGoal.stop, startYmd: ymdOf(DateTime.now()), why: 'Respirer', parades: const ['Marcher 5 min']),
      urges: const {},
      slips: const {},
    );
    await t.pumpWidget(MaterialApp(home: Builder(builder: (ctx) => Scaffold(body: TextButton(onPressed: () => Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => UrgeScreen(logic: logic, ticking: false))), child: const Text('go'))))));
    await t.tap(find.text('go'));
    await t.pumpAndSettle();
    expect(find.textContaining('Respirer'), findsWidgets);
    await t.tap(find.byKey(const ValueKey('urge-4')));
    await t.tap(find.text('Marcher 5 min'));
    await t.ensureVisible(find.byKey(const ValueKey('urge-passed')));
    await t.tap(find.byKey(const ValueKey('urge-passed')));
    await t.pumpAndSettle();
    expect(urgesOvercome(logic.freedom), 1);
    final u = logic.freedom.urgeList.single;
    expect(u.intensity, 4);
    expect(u.parade, 'Marcher 5 min');
    expect(find.textContaining('Envie surmontée'), findsOneWidget);
    await t.pump(const Duration(seconds: 10));
    await t.pumpAndSettle();
  });

  testWidgets('après un écart : on repart, le compteur aussi', (t) async {
    t.view.physicalSize = const Size(800, 4000);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    final logic = _logic();
    logic.freedom = Freedom(
      plan: FreedomPlan(name: 'Ma pause', goal: FreedomGoal.stop, startYmd: ymdOf(DateTime.now().subtract(const Duration(days: 5))), why: ''),
      urges: const {},
      slips: const {},
    );
    await t.pumpWidget(_host(SlipView(logic: logic, trigger: 'Stress')));
    expect(find.text('Un écart, pas une rechute.'), findsOneWidget);
    await t.ensureVisible(find.byKey(const ValueKey('slip-save')));
    await t.tap(find.byKey(const ValueKey('slip-save')));
    await t.pump();
    final s = logic.freedom.slipList.single;
    expect(s.triggers, ['Stress']);
    expect(DateTime.now().difference(freeSince(logic.freedom)).inMinutes, lessThan(2));
  });
}
