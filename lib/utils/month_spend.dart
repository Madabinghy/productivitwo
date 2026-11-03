import 'package:productivitwo_v1/utils/finances.dart';

/// « Où va mon argent » (maquette validée 2026-11-03) — logique pure. Les
/// sorties d'un mois (dépenses notées, parts de tickets, fixes passés),
/// regroupées par domaine, par enveloppe ou par magasin ; chaque catégorie
/// garde ses sorties pour la page qui les liste.

enum MonthBy { domain, envelope, store }

/// Les fixes passés n'ont ni domaine ni enveloppe : ils vont dans « Fixes ».
const kFixedKey = '~fixes';
const kFixedName = 'Fixes';

/// Une sortie du mois.
class SpendItem {
  final String id;
  final String ymd;
  final int amount;
  final bool fixed;
  /// Dépense notée / part de ticket ; null pour un fixe.
  final Expense? expense;
  final Receipt? receipt;
  /// Nom du fixe, ou note de la dépense.
  final String label;
  const SpendItem({required this.id, required this.ymd, required this.amount, this.fixed = false, this.expense, this.receipt, required this.label});

  String? get domainId => expense?.domainId;
  String get envelopeId => fixed ? kFixedKey : (expense?.envelopeId ?? '');
  int? get at => expense?.at;

  /// Le magasin : celui du ticket, sinon « Courses · Lidl » → Lidl, sinon la note.
  String get store {
    if (fixed) return kFixedName;
    final s = receipt?.store?.trim();
    if (s != null && s.isNotEmpty) return s;
    final note = expense?.note?.trim() ?? '';
    final i = note.indexOf(' · ');
    if (note.startsWith('Courses') && i > 0) return note.substring(i + 3).trim();
    return note.isEmpty ? 'Sans magasin' : note;
  }
}

/// Les sorties du mois [month] (`YYYY-MM`) jusqu'à [todayYmd], les plus récentes d'abord.
List<SpendItem> monthSpends(Finances f, String month, String todayYmd) {
  final out = <SpendItem>[
    for (final x in f.expenses.values)
      if (monthOf(x.ymd) == month && x.ymd.compareTo(todayYmd) <= 0)
        SpendItem(id: x.id, ymd: x.ymd, amount: x.amount, expense: x, receipt: x.receiptId == null ? null : f.receipts[x.receiptId], label: x.note ?? ''),
  ];
  final byId = {for (final r in f.recurring) r.id: r};
  for (final e in (f.paid[month] ?? const <String, Paid>{}).entries) {
    final r = byId[e.key];
    if (r?.income == true || e.value.ymd.compareTo(todayYmd) > 0) continue;
    out.add(SpendItem(id: 'fixe:${e.key}', ymd: e.value.ymd, amount: e.value.amount, fixed: true, label: r?.name ?? 'Fixe retiré'));
  }
  out.sort((a, b) {
    final c = b.ymd.compareTo(a.ymd);
    return c != 0 ? c : (b.at ?? 0).compareTo(a.at ?? 0);
  });
  return out;
}

class SpendCategory {
  final String id;
  final String name;
  final int total;
  final List<SpendItem> items;
  const SpendCategory({required this.id, required this.name, required this.total, required this.items});

  /// Nombre de tickets distincts.
  int get tickets => items.map((i) => i.receipt?.id).whereType<String>().toSet().length;
}

/// La clé d'une sortie selon le regroupement.
String spendKey(SpendItem i, MonthBy by) => switch (by) {
      MonthBy.domain => i.fixed ? kFixedKey : (i.domainId ?? ''),
      MonthBy.envelope => i.envelopeId,
      MonthBy.store => i.fixed ? kFixedKey : i.store,
    };

/// Les catégories du mois, de la plus grosse à la plus petite ; « Sans
/// domaine » et « Fixes » ferment la marche en vue domaine.
List<SpendCategory> monthCategories(List<SpendItem> items, MonthBy by, Finances f, {Map<String, String> domainNames = const {}}) {
  final groups = <String, List<SpendItem>>{};
  for (final i in items) {
    groups.putIfAbsent(spendKey(i, by), () => []).add(i);
  }
  String name(String k) {
    if (k == kFixedKey) return kFixedName;
    return switch (by) {
      MonthBy.domain => k.isEmpty ? 'Sans domaine' : (domainNames[k] ?? 'Domaine retiré'),
      MonthBy.envelope => f.envelopeOf(k)?.name ?? 'Autre',
      MonthBy.store => k,
    };
  }

  final out = [
    for (final e in groups.entries) SpendCategory(id: e.key, name: name(e.key), total: e.value.fold<int>(0, (s, i) => s + i.amount), items: e.value),
  ];
  int rank(SpendCategory c) => c.id == kFixedKey ? 2 : (by == MonthBy.domain && c.id.isEmpty ? 1 : 0);
  out.sort((a, b) {
    final r = rank(a).compareTo(rank(b));
    return r != 0 ? r : b.total.compareTo(a.total);
  });
  return out;
}

/// Ce que contient une catégorie, en quelques mots : « 4 tickets · Courses, Maison ».
String categoryHint(SpendCategory c, MonthBy by, Finances f, {Map<String, String> domainNames = const {}}) {
  if (c.id == kFixedKey) return c.items.map((i) => i.label).toSet().take(3).join(', ');
  final parts = <String>[];
  final t = c.tickets;
  if (t > 0) parts.add('$t ticket${t > 1 ? 's' : ''}');
  final notes = c.items.length - c.items.where((i) => i.receipt != null).length;
  if (t == 0 && notes > 0) parts.add('$notes dépense${notes > 1 ? 's' : ''}');
  final sub = <String, int>{};
  for (final i in c.items) {
    final k = switch (by) {
      MonthBy.domain => f.envelopeOf(i.envelopeId)?.name ?? 'Autre',
      MonthBy.envelope => i.domainId == null ? 'sans domaine' : (domainNames[i.domainId] ?? 'domaine retiré'),
      MonthBy.store => f.envelopeOf(i.envelopeId)?.name ?? 'Autre',
    };
    sub[k] = (sub[k] ?? 0) + i.amount;
  }
  final top = sub.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  if (top.isNotEmpty) parts.add(top.take(2).map((e) => e.key).join(', '));
  return parts.join(' · ');
}

/// Le détail d'une catégorie par un autre regroupement (domaine → enveloppes,
/// enveloppe / magasin → domaines).
List<SpendCategory> breakdown(SpendCategory c, MonthBy by, Finances f, {Map<String, String> domainNames = const {}}) =>
    monthCategories(c.items, by == MonthBy.domain ? MonthBy.envelope : MonthBy.domain, f, domainNames: domainNames);

/// `YYYY-MM` du mois d'avant / d'après.
String shiftMonth(String month, int delta) {
  final y = int.parse(month.substring(0, 4));
  final m = int.parse(month.substring(5, 7)) - 1 + delta;
  final yy = y + (m >= 0 ? m ~/ 12 : -((-m + 11) ~/ 12));
  final mm = ((m % 12) + 12) % 12 + 1;
  return '${yy.toString().padLeft(4, '0')}-${mm.toString().padLeft(2, '0')}';
}

const kMonthNames = ['janvier', 'février', 'mars', 'avril', 'mai', 'juin', 'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre'];
String monthName(String month) => kMonthNames[(int.parse(month.substring(5, 7)) - 1).clamp(0, 11)];

/// Les courses d'une catégorie par rayon (dépenses d'un ticket ou d'une caisse
/// qui portent `byAisle`), du plus gros au plus petit ; vide sinon.
List<MapEntry<String, int>> aislesOf(List<SpendItem> items) {
  final by = <String, int>{};
  for (final i in items) {
    for (final e in (i.expense?.byAisle ?? const <String, int>{}).entries) {
      by[e.key] = (by[e.key] ?? 0) + e.value;
    }
  }
  return by.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
}
