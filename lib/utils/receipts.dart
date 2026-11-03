import 'package:productivitwo_v1/utils/finances.dart';

/// Tickets de caisse conservés (maquette validée 2026-11-03 « Où va mon
/// argent ») — logique pure. Un ticket lu par Claude garde chaque ligne avec
/// son prix, son domaine et son rayon ; ses dépenses (une par domaine et
/// projet) se recalculent quand on change le domaine d'un article.

/// Une part du ticket : un domaine (et projet), son montant, ses articles.
class ReceiptPart {
  final String? domainId;
  final String? projectId;
  final int amount;
  final List<String> labels;
  final Map<String, int> byAisle;
  const ReceiptPart({this.domainId, this.projectId, required this.amount, required this.labels, required this.byAisle});
  String get key => '${domainId ?? ''}|${projectId ?? ''}';
}

/// Les parts du ticket, du plus gros au plus petit. Si la somme des lignes
/// diffère du total (remise), l'écart va au prorata.
List<ReceiptPart> receiptParts(Receipt r) {
  final sum = r.lines.fold<int>(0, (a, l) => a + l.price);
  final paid = (sum == r.total || sum <= 0) ? [for (final l in r.lines) l.price] : _apportion(r.total, [for (final l in r.lines) l.price]);
  final by = <String, ({String? domainId, String? projectId, int amount, List<String> labels, Map<String, int> byAisle})>{};
  for (var i = 0; i < r.lines.length; i++) {
    final l = r.lines[i];
    final k = '${l.domainId ?? ''}|${l.projectId ?? ''}';
    final g = by[k] ?? (domainId: l.domainId, projectId: l.projectId, amount: 0, labels: <String>[], byAisle: <String, int>{});
    g.labels.add(l.name);
    if (l.aisle != null) g.byAisle[l.aisle!] = (g.byAisle[l.aisle!] ?? 0) + paid[i];
    by[k] = (domainId: g.domainId, projectId: g.projectId, amount: g.amount + paid[i], labels: g.labels, byAisle: g.byAisle);
  }
  final out = [for (final g in by.values) ReceiptPart(domainId: g.domainId, projectId: g.projectId, amount: g.amount, labels: g.labels, byAisle: g.byAisle)];
  out.sort((a, b) => b.amount.compareTo(a.amount));
  return out;
}

List<int> _apportion(int total, List<int> weights) {
  final sum = weights.fold<int>(0, (a, b) => a + b);
  final raw = [for (final w in weights) total * w / sum];
  final parts = [for (final x in raw) x.floor()];
  var left = total - parts.fold<int>(0, (a, b) => a + b);
  final order = List.generate(raw.length, (i) => i)..sort((a, b) => (raw[b] - parts[b]).compareTo(raw[a] - parts[a]));
  for (var k = 0; left > 0 && order.isNotEmpty; k = (k + 1) % order.length, left--) {
    parts[order[k]]++;
  }
  return parts;
}

/// Les dépenses d'un ticket : une par part, ids stables `<ticket>-<n>`.
Map<String, Expense> receiptExpenses(Receipt r) {
  final note = r.store == null ? 'Courses' : 'Courses · ${r.store}';
  final parts = receiptParts(r);
  return {
    for (var i = 0; i < parts.length; i++)
      if (parts[i].amount > 0)
        '${r.id}-$i': Expense(
          id: '${r.id}-$i',
          ymd: r.ymd,
          amount: parts[i].amount,
          envelopeId: r.envelopeId,
          note: note,
          domainId: parts[i].domainId,
          projectId: parts[i].projectId,
          items: parts[i].labels,
          at: r.at,
          byAisle: parts[i].byAisle,
          receiptId: r.id,
        ),
  };
}

/// Le ticket avec une ligne passée dans un autre domaine (null = sans).
Receipt withReceiptLineDomain(Receipt r, int index, String? domainId) {
  if (index < 0 || index >= r.lines.length) return r;
  final l = [...r.lines];
  l[index] = l[index].withDomain(domainId);
  return r.withLines(l);
}

/// Les dépenses déjà rattachées à un ticket.
List<Expense> expensesOfReceipt(Finances f, String receiptId) => [for (final x in f.expenses.values) if (x.receiptId == receiptId) x];

/// Le ticket d'une dépense, s'il a été conservé.
Receipt? receiptOf(Finances f, Expense x) => x.receiptId == null ? null : f.receipts[x.receiptId];
