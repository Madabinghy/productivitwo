import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/widgets/finance_flow_card.dart';
import 'package:productivitwo_v1/widgets/finance_year_sheet.dart';
import 'package:productivitwo_v1/utils/finance_charts.dart';
import 'package:productivitwo_v1/utils/finances.dart';

void main() {
  test('30 jours : solde à partir du premier solde recopié, rentrées et sorties par jour', () {
    final f = Finances(
      checks: const {'2026-11-01': 100000},
      checksAt: const {'2026-11-01': 1000},
      recurring: const [Recurring(id: 'loyer', name: 'Loyer', amount: 70000, day: 2)],
      paid: const {'2026-11': {'loyer': Paid(70000, '2026-11-02', at: 5000)}},
      expenses: const {
        'a': Expense(id: 'a', ymd: '2026-11-02', amount: 4280, envelopeId: 'courses', at: 6000),
        'b': Expense(id: 'b', ymd: '2026-11-03', amount: 13500, envelopeId: 'imprevus', note: 'Amende', at: 7000),
        'c': Expense(id: 'c', ymd: '2026-10-30', amount: 2000, envelopeId: 'courses'),
      },
      incomes: const {'i': Income(id: 'i', ymd: '2026-11-03', amount: 55000, from: 'Client X', at: 8000)},
    );
    final s = flowSeries(f, '2026-11-03', days: 5);
    expect(s.map((d) => d.ymd), ['2026-10-30', '2026-10-31', '2026-11-01', '2026-11-02', '2026-11-03']);
    expect(s[0].balance, isNull);
    expect(s[0].outCents, 2000);
    expect(s[2].balance, 100000);
    expect(s[2].checked, isTrue);
    expect(s[3].balance, 100000 - 70000 - 4280);
    expect(s[3].labels, containsAll(['Courses', 'Loyer']));
    expect(s[4].balance, 100000 - 70000 - 4280 - 13500 + 55000);
    expect(s[4].inCents, 55000);
    expect(s[4].labels, containsAll(['Amende', '+ Client X']));
    final t = flowTotals(s);
    expect(t.outCents, 2000 + 70000 + 4280 + 13500);
    expect(t.net, 55000 - t.outCents);
  });

  testWidgets('la carte 30 jours se dessine sans débordement, sans solde comme avec', (t) async {
    for (final f in [
      const Finances(),
      Finances(checks: const {'2026-11-01': 184260}, expenses: const {'a': Expense(id: 'a', ymd: '2026-11-02', amount: 4280, envelopeId: 'courses')}),
    ]) {
      await t.pumpWidget(MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(body: SizedBox(width: 340, child: SingleChildScrollView(child: FinanceFlowCard(finances: f, todayYmd: '2026-11-03', accent: Colors.teal)))),
      ));
      await t.tap(find.text('90 j'));
      await t.pump();
      await t.tapAt(t.getCenter(find.byType(CustomPaint).last));
      await t.pump();
      expect(t.takeException(), isNull);
    }
  });

  test('Mon année : par mois, par enveloppe, par domaine, par fixe', () {
    final f = Finances(
      envelopes: const [Envelope(id: 'courses', name: 'Courses', monthly: 45000), Envelope(id: 'sorties', name: 'Sorties', monthly: 15000)],
      recurring: const [Recurring(id: 'loyer', name: 'Loyer', amount: 70000), Recurring(id: 'sal', name: 'Salaire', amount: 200000, income: true)],
      paid: const {
        '2026-10': {'loyer': Paid(70000, '2026-10-02'), 'sal': Paid(200000, '2026-10-28')},
        '2026-11': {'loyer': Paid(70000, '2026-11-02')},
      },
      expenses: const {
        'a': Expense(id: 'a', ymd: '2026-10-05', amount: 20000, envelopeId: 'sorties', domainId: 'd1'),
        'b': Expense(id: 'b', ymd: '2026-11-02', amount: 4280, envelopeId: 'courses'),
        'c': Expense(id: 'c', ymd: '2025-12-30', amount: 999, envelopeId: 'courses'),
      },
    );
    final y = yearSummary(f, 2026, '2026-11-03');
    expect(y.firstMonth, 10);
    expect(y.lastMonth, 11);
    expect(y.spent[9], 90000);
    expect(y.spent[10], 74280);
    expect(y.incomeTotal, 200000);
    expect(y.kept, 200000 - 164280);
    expect(y.perMonth, 82140);
    expect(financeYears(f, 2026), [2026, 2025]);
    final env = yearCategories(f, 2026, YearBy.envelope);
    expect(env.map((c) => c.name), ['Courses', 'Sorties']);
    expect(monthsOverCap(env[1], 11), 1);
    final dom = yearCategories(f, 2026, YearBy.domain, domainNames: const {'d1': 'Famille'});
    expect(dom.map((c) => c.name), ['Famille', 'Sans domaine']);
    final fx = yearCategories(f, 2026, YearBy.fixed);
    expect(fx.single.total, 140000);
    expect(biggestOf(f, 'courses', 2026).single.id, 'b');
  });

  test('tendance : 3 derniers mois clos contre les 3 d’avant', () {
    final m = [0, 0, 0, 100, 100, 100, 80, 80, 80, 0, 0, 0];
    expect(trend3(m, 10), -20);
    expect(trend3(m, 10, firstMonth: 6), isNull);
    expect(trend3(m, 5), isNull);
  });

  testWidgets('Mon année et la page d’une enveloppe se dessinent', (t) async {
    final logic = AppLogic(AppState(domains: [], activities: [], sessions: [], habitProgress: []), () {})..dayStartMin = 0;
    final today = logic.livedTodayYmd;
    logic.finances = Finances(
      envelopes: const [Envelope(id: 'courses', name: 'Courses', monthly: 45000)],
      expenses: {'a': Expense(id: 'a', ymd: today, amount: 4280, envelopeId: 'courses', note: 'Marché')},
    );
    await t.pumpWidget(MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(body: Builder(builder: (c) => TextButton(onPressed: () => showFinanceYearSheet(c, logic: logic), child: const Text('ouvrir')))),
    ));
    await t.tap(find.text('ouvrir'));
    await t.pumpAndSettle();
    expect(find.text('Mon année'), findsOneWidget);
    await t.tap(find.text('Par domaine'));
    await t.pump();
    await t.tap(find.text('Fixes'));
    await t.pump();
    await t.tap(find.text('Par enveloppe'));
    await t.pump();
    await t.tap(find.text('Courses'));
    await t.pumpAndSettle();
    expect(find.text('CE QUE ÇA DIT'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
