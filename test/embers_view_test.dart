import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/badge_today.dart';
import 'package:productivitwo_v1/utils/embers.dart';
import 'package:productivitwo_v1/utils/evening_ledger.dart';
import 'package:productivitwo_v1/utils/stakes.dart';
import 'package:productivitwo_v1/widgets/embers_view.dart';

Widget _wrap(Widget w) => MaterialApp(home: Scaffold(body: SingleChildScrollView(child: w)));

void main() {
  testWidgets('ligne « Perdu hier » : rallumable, en attente, indisponible', (t) async {
    var rekindled = false, cancelled = false;
    await t.pumpWidget(_wrap(Column(children: [
      LostSeriesRow(lost: const LostSeries(activityId: 'p', name: 'Pompes', length: 4, nextTier: 7), onRekindle: () => rekindled = true),
      LostSeriesRow(lost: const LostSeries(activityId: 'l', name: 'Lecture', length: 2, pending: true), todayCount: 0, target: 1, onCancel: () => cancelled = true),
      const LostSeriesRow(lost: LostSeries(activityId: 't', name: 'Tractions', length: 2, blocked: 'déjà rallumée le 17 oct. · une fois par mois')),
    ])));
    expect(find.text('Pompes · série de 4 j cassée'), findsOneWidget);
    expect(find.text('palier 7 j dans 3 j · rattrapable jusqu’à ce soir'), findsOneWidget);
    await t.tap(find.text('Rallumer · 🔥1'));
    expect(rekindled, isTrue);
    expect(find.text('rallumée · fais Lecture aujourd’hui (0 / 1) pour garder la série'), findsOneWidget);
    expect(find.text('+1'), findsNothing);
    await t.tap(find.byTooltip('Annuler le rallumage'));
    expect(cancelled, isTrue);
    expect(find.text('Indisponible'), findsOneWidget);
    expect(find.text('déjà rallumée le 17 oct. · une fois par mois'), findsOneWidget);
  });

  testWidgets('bloc Braises : réserve et historique', (t) async {
    const ledger = EmberLedger(stock: 2, history: [
      EmberEvent(EmberEventKind.spent, '2026-10-29', activityId: 'p'),
      EmberEvent(EmberEventKind.earned, '2026-10-28'),
    ]);
    await t.pumpWidget(_wrap(const EmberLedgerPanel(ledger: ledger, names: {'p': 'Pompes'})));
    expect(find.text('2 sur 3'), findsOneWidget);
    expect(find.text('Pompes rallumée'), findsOneWidget);
    expect(find.text('Journée parfaite'), findsOneWidget);
    expect(find.text('prochaine : une journée parfaite'), findsOneWidget);
  });

  test('bilan du soir : journée parfaite = une braise à la bascule', () {
    final r = Activity(id: 'r', name: 'R', domainId: 'd', type: 'habit');
    final perfect = TodayFacts(ymd: '2026-10-29', now: DateTime(2026, 10, 29, 21), routines: [RoutineToday(r, 1, 1)]);
    final partial = TodayFacts(ymd: '2026-10-29', now: DateTime(2026, 10, 29, 21), routines: [RoutineToday(r, 0, 1)]);
    expect(isPerfectSoFar(perfect), isTrue);
    expect(isPerfectSoFar(partial), isFalse);
    expect(isPerfectSoFar(TodayFacts(ymd: '2026-10-29', now: DateTime(2026, 10, 29))), isFalse);
    final l = buildEveningLedger(
      board: StakeBoard.empty, deck: null, projects: const [], activities: const [], sessions: const [], objectiveDays: const [],
      dayStart: DateTime(2026, 10, 29, 5), now: DateTime(2026, 10, 29, 21), perfectToday: true, emberStock: 1);
    expect(l.advanced.first.title, 'Journée parfaite · une braise');
    expect(l.advanced.first.sub, 'acquise à la bascule · 2 sur 3 en réserve');
  });
}
