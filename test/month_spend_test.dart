import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/finances.dart';
import 'package:productivitwo_v1/utils/month_spend.dart';
import 'package:productivitwo_v1/utils/receipts.dart';
import 'package:productivitwo_v1/widgets/money_month_card.dart';

const _r = Receipt(
  id: 'tk',
  ymd: '2026-11-03',
  store: 'Lidl',
  ref: '4521',
  total: 1300,
  envelopeId: 'courses',
  lines: [
    ReceiptLine(label: 'PATES', name: 'Pâtes', price: 250, domainId: 's'),
    ReceiptLine(label: 'LESSIVE', name: 'Lessive', price: 1050, domainId: 'm'),
  ],
);

Finances _f() => Finances(
      receipts: {'tk': _r},
      expenses: {
        ...receiptExpenses(_r),
        'e1': const Expense(id: 'e1', ymd: '2026-11-02', amount: 1200, envelopeId: 'sorties', note: 'Cinéma', domainId: 's'),
        'e2': const Expense(id: 'e2', ymd: '2026-11-01', amount: 4600, envelopeId: 'maison', note: 'Castorama', domainId: 'm'),
        'old': const Expense(id: 'old', ymd: '2026-10-28', amount: 999, envelopeId: 'courses', note: 'Courses · Leclerc'),
      },
      recurring: const [Recurring(id: 'loyer', name: 'Loyer', amount: 52000, day: 1), Recurring(id: 'sal', name: 'Salaire', amount: 200000, income: true)],
      paid: const {
        '2026-11': {'loyer': Paid(52000, '2026-11-01'), 'sal': Paid(200000, '2026-11-01')},
      },
    );

void main() {
  test('les sorties du mois, par domaine, enveloppe, magasin', () {
    final f = _f();
    final items = monthSpends(f, '2026-11', '2026-11-03');
    expect(items.length, 5); // 2 parts du ticket, 2 dépenses, le loyer (pas le salaire)
    expect(items.fold<int>(0, (s, i) => s + i.amount), 1300 + 1200 + 4600 + 52000);
    final dom = monthCategories(items, MonthBy.domain, f, domainNames: {'s': 'Santé', 'm': 'Maison'});
    expect(dom.map((c) => c.name), ['Maison', 'Santé', 'Fixes']);
    expect(dom.first.total, 1050 + 4600);
    expect(categoryHint(dom.first, MonthBy.domain, f), '1 ticket · Maison, Courses');
    final stores = monthCategories(items, MonthBy.store, f);
    expect(stores.map((c) => c.name).toSet(), {'Lidl', 'Cinéma', 'Castorama', 'Fixes'});
    expect(monthSpends(f, '2026-10', '2026-11-03').single.store, 'Leclerc');
    final env = monthCategories(items, MonthBy.envelope, f);
    expect(env.last.id, kFixedKey);
    expect(breakdown(dom.first, MonthBy.domain, f).map((c) => c.name), ['Maison', 'Courses']);
    expect(shiftMonth('2026-01', -1), '2025-12');
    expect(shiftMonth('2026-12', 1), '2027-01');
  });

  testWidgets('carte du mois : trois vues, page d\'une catégorie, ticket', (tester) async {
    tester.view.physicalSize = const Size(800, 4000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final logic = AppLogic(AppState(domains: [Domain(id: 's', name: 'Santé'), Domain(id: 'm', name: 'Maison')], activities: [], sessions: [], habitProgress: []), () {});
    logic.finances = _f();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: MoneyMonthCard(logic: logic, todayYmd: '2026-11-03')))));
    await tester.pumpAndSettle();
    expect(find.text('OÙ VA MON ARGENT · NOVEMBRE'), findsOneWidget);
    expect(find.textContaining('en 1 ticket lu par Claude'), findsOneWidget);
    await tester.tap(find.text('Magasins'));
    await tester.pumpAndSettle();
    expect(find.text('Lidl'), findsOneWidget);
    await tester.tap(find.text('Domaines'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Maison').first);
    await tester.pumpAndSettle();
    expect(find.text('PAR ENVELOPPE'), findsOneWidget);
    expect(find.textContaining('ticket 4521'), findsOneWidget);
    expect(find.textContaining('sur 13'), findsOneWidget);
    await tester.tap(find.textContaining('ticket 4521'));
    await tester.pumpAndSettle();
    expect(find.text('Ticket 4521'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
