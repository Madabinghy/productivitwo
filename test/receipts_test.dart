import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/finances.dart';
import 'package:productivitwo_v1/utils/receipts.dart';
import 'package:productivitwo_v1/widgets/receipt_sheet.dart';

const _r = Receipt(
  id: 'tk',
  ymd: '2026-11-03',
  time: '18:42',
  store: 'Lidl',
  place: 'Rennes Cléunay',
  ref: '4521',
  total: 1300,
  envelopeId: 'courses',
  lines: [
    ReceiptLine(label: 'PATES FARFALLE 500G', name: 'Pâtes', price: 150, domainId: 's', aisle: 'Épicerie'),
    ReceiptLine(label: 'LAIT DEMI ECR', name: 'Lait', price: 100, domainId: 's', aisle: 'Frais'),
    ReceiptLine(label: 'LESSIVE X30', name: 'Lessive', price: 1050, domainId: 'm', aisle: 'Ménager'),
  ],
);

void main() {
  test('parts et dépenses d\'un ticket', () {
    final parts = receiptParts(_r);
    expect(parts.map((p) => (p.domainId, p.amount)), [('m', 1050), ('s', 250)]);
    expect(parts[1].byAisle, {'Épicerie': 150, 'Frais': 100});
    final exp = receiptExpenses(_r);
    expect(exp.keys, ['tk-0', 'tk-1']);
    expect(exp['tk-1']!.receiptId, 'tk');
    expect(exp['tk-1']!.note, 'Courses · Lidl');
    expect(exp['tk-1']!.items, ['Pâtes', 'Lait']);
    final moved = withReceiptLineDomain(_r, 1, 'm');
    expect(receiptParts(moved).first.amount, 1150);
    // Remise : l'écart va au prorata, la somme reste le total.
    final promo = Receipt(id: 'p', ymd: '2026-11-03', total: 1200, envelopeId: 'courses', lines: _r.lines);
    expect(receiptParts(promo).fold<int>(0, (a, p) => a + p.amount), 1200);
    // Aller-retour JSON.
    final back = parseFinances(Finances(receipts: {'tk': _r}).toJson()).receipts['tk']!;
    expect(back.ref, '4521');
    expect(back.lines[0].name, 'Pâtes');
    expect(back.lines[2].label, 'LESSIVE X30');
  });

  testWidgets('fiche du ticket : papier, articles, changer le domaine d\'un article', (tester) async {
    final logic = AppLogic(
        AppState(domains: [Domain(id: 's', name: 'Santé'), Domain(id: 'm', name: 'Maison')], activities: [], sessions: [], habitProgress: []), () {});
    logic.finances = Finances(receipts: {'tk': _r}, expenses: receiptExpenses(_r));
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ReceiptSheet(logic: logic, receiptId: 'tk'))));
    await tester.pumpAndSettle();
    expect(find.text('Ticket 4521'), findsOneWidget);
    expect(find.text('LIDL · RENNES CLÉUNAY'), findsOneWidget);
    expect(find.text('Santé · Frais'), findsOneWidget);
    await tester.tap(find.text('Lait'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Maison').last);
    await tester.pumpAndSettle();
    expect(logic.finances.receipts['tk']!.lines[1].domainId, 'm');
    final exp = expensesOfReceipt(logic.finances, 'tk');
    expect(exp.map((x) => x.amount).toList()..sort(), [150, 1150]);
    expect(find.text('Maison · Frais'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
