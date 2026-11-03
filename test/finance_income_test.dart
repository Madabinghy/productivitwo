import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/finances.dart';
import 'package:productivitwo_v1/widgets/finance_sheet.dart';

void main() {
  test('le compte maintenant : solde, mouvements après lui, fixes à venir', () {
    const f = Finances(recurring: [
      Recurring(id: 'loyer', name: 'Loyer', amount: 65000),
      Recurring(id: 'tel', name: 'Forfait', amount: 2000),
      Recurring(id: 'sal', name: 'Vacations', amount: 30000, income: true),
    ]);
    final g = f.copyWith(
      checks: {'2026-11-02': 150000},
      checksAt: {'2026-11-02': 1000},
      expenses: {
        'avant': const Expense(id: 'avant', ymd: '2026-11-02', amount: 999, envelopeId: 'c', at: 500),
        'sans': const Expense(id: 'sans', ymd: '2026-11-02', amount: 999, envelopeId: 'c'),
        'apres': const Expense(id: 'apres', ymd: '2026-11-02', amount: 2000, envelopeId: 'c', at: 2000),
        'demain': const Expense(id: 'demain', ymd: '2026-11-03', amount: 1000, envelopeId: 'c'),
      },
      incomes: {'f1': const Income(id: 'f1', ymd: '2026-11-03', amount: 80000, from: 'Client A')},
      paid: {
        '2026-11': {'tel': const Paid(2000, '2026-11-03')}
      },
    );
    final a = accountNow(g, '2026-11-03')!;
    expect(a.sinceYmd, '2026-11-02');
    // « sans » (pas d'heure) est désormais compté après le solde ; « avant » reste dedans.
    expect(a.balance, 150000 - 999 - 2000 - 1000 - 2000 + 80000);
    expect(a.spentSince, 999 + 2000 + 1000);
    expect(a.before.map((x) => x.id), ['avant']);
    expect(a.sinceAt, 1000);
    expect(a.fixedLeft, 65000);
    expect(a.incomeLeft, 30000);
    expect(a.remaining, a.balance + 30000 - 65000);
    expect(accountNow(f, '2026-11-03'), isNull);
    // Les rentrées comptent dans le mois et dans le point de la semaine.
    expect(monthSummary(g, '2026-11-03').income, 30000 + 80000);
    expect(balanceCheck(g, '2026-11-03').paidInSince, 80000);
    expect(parseFinances(g.toJson()).incomes['f1']!.from, 'Client A');
    expect(parseFinances(g.toJson()).checksAt['2026-11-02'], 1000);
  });

  test('une dépense notée avant le solde : « pas encore dedans » la retranche', () async {
    final st = AppState(domains: [], activities: [], sessions: [], habitProgress: []);
    final logic = AppLogic(st, () {})..dayStartMin = 0;
    final today = logic.livedTodayYmd;
    final id = (await logic.logExpense(amount: 13500, envelopeId: 'imprevus'))!;
    final x = logic.finances.expenses[id]!;
    logic.finances = logic.finances.copyWith(
      expenses: {id: Expense(id: id, ymd: x.ymd, amount: x.amount, envelopeId: x.envelopeId, at: 1000)},
      checks: {today: 26263},
      checksAt: {today: 5000},
    );
    final before = accountNow(logic.finances, today)!;
    expect(before.balance, 26263);
    expect(before.before.single.id, id);
    await logic.expenseAfterBalance(id);
    final after = accountNow(logic.finances, today)!;
    expect(after.balance, 26263 - 13500);
    expect(after.before, isEmpty);
    expect(after.spentSince, 13500);
  });

  test('ancien solde sans heure : « pas encore dedans » le date et retranche', () async {
    final st = AppState(domains: [], activities: [], sessions: [], habitProgress: []);
    final logic = AppLogic(st, () {})..dayStartMin = 0;
    final today = logic.livedTodayYmd;
    final a = (await logic.logExpense(amount: 13500, envelopeId: 'imprevus'))!;
    final b = (await logic.logExpense(amount: 500, envelopeId: 'courses'))!;
    final xa = logic.finances.expenses[a]!, xb = logic.finances.expenses[b]!;
    logic.finances = logic.finances.copyWith(
      expenses: {
        a: Expense(id: a, ymd: xa.ymd, amount: xa.amount, envelopeId: xa.envelopeId, at: 3000),
        b: Expense(id: b, ymd: xb.ymd, amount: xb.amount, envelopeId: xb.envelopeId, at: 1000),
      },
      checks: {today: 26263},
    );
    expect(accountNow(logic.finances, today)!.balance, 26263);
    await logic.expenseAfterBalance(a);
    final after = accountNow(logic.finances, today)!;
    expect(after.balance, 26263 - 13500);
    expect(after.before.map((x) => x.id), [b]);
  });

  testWidgets('Finances : poser son solde, une rentrée, la mise à jour dit l\'écart', (tester) async {
    tester.view.physicalSize = const Size(800, 6000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final st = AppState(domains: [Domain(id: 'biz', name: 'Business')], activities: [], sessions: [], habitProgress: []);
    final logic = AppLogic(st, () {})..dayStartMin = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: FinanceSheet(logic: logic))));
    await tester.tap(find.text('Ton compte dit ? · Poser mon solde'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '1000');
    await tester.tap(find.text('C’est ça'));
    await tester.pumpAndSettle();
    expect(find.text(euros(100000)), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));

    await tester.tap(find.text('+ Rentrée'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '800');
    await tester.enterText(find.byType(TextField).at(1), 'Client A');
    await tester.pump();
    await tester.tap(find.text('Noter · + 800 €'));
    await tester.pumpAndSettle();
    expect(logic.finances.incomes.values.single.domainId, 'biz');
    expect(find.text(euros(180000)), findsOneWidget);
    expect(find.text('RENTRÉES CE MOIS'), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));

    await tester.tap(find.text('Mettre à jour le solde'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '1760');
    await tester.tap(find.text('C’est ça'));
    await tester.pumpAndSettle();
    expect(find.textContaining('écart de − 40 €'), findsOneWidget);
    expect(find.text(euros(176000)), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
  });
}
