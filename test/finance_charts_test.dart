import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/widgets/finance_flow_card.dart';
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
}
