import 'package:productivitwo_v1/utils/finances.dart';

/// Les finances en courbes (maquette validée 2026-11-03 « Finances, en
/// courbes ») — logique pure. Rien de stocké : tout se recalcule depuis
/// `data/meta.finances`.

String _ymd(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Un jour de la courbe « 30 jours ».
class DayFlow {
  final String ymd;
  /// Rentrées (ponctuelles + revenus cochés) et sorties (dépenses + fixes passés), en centimes.
  final int inCents;
  final int outCents;
  /// Solde en fin de journée, d'après le dernier solde recopié jusqu'à ce jour ;
  /// null avant le premier solde (la courbe n'est pas tracée).
  final int? balance;
  /// Un solde a été recopié ce jour-là (point sur la courbe).
  final bool checked;
  /// Ce qui a bougé, pour le détail du jour : « Courses », « Loyer », « + Client X ».
  final List<String> labels;
  const DayFlow({required this.ymd, this.inCents = 0, this.outCents = 0, this.balance, this.checked = false, this.labels = const []});
}

/// Les [days] derniers jours jusqu'à [todayYmd] compris, du plus ancien au plus récent.
List<DayFlow> flowSeries(Finances f, String todayYmd, {int days = 30}) {
  final end = DateTime.parse(todayYmd);
  final byId = {for (final r in f.recurring) r.id: r};
  final ins = <String, int>{}, outs = <String, int>{};
  final labels = <String, List<String>>{};
  void add(Map<String, int> m, String ymd, int v, String label) {
    m[ymd] = (m[ymd] ?? 0) + v;
    labels.putIfAbsent(ymd, () => []).add(label);
  }

  for (final x in f.expenses.values) {
    final note = x.note?.trim();
    add(outs, x.ymd, x.amount, note != null && note.isNotEmpty ? note : (f.envelopeOf(x.envelopeId)?.name ?? 'Dépense'));
  }
  for (final x in f.incomes.values) {
    add(ins, x.ymd, x.amount, '+ ${x.from?.trim().isNotEmpty == true ? x.from!.trim() : 'Rentrée'}');
  }
  for (final month in f.paid.values) {
    for (final e in month.entries) {
      final r = byId[e.key];
      if (r == null) continue;
      r.income ? add(ins, e.value.ymd, e.value.amount, '+ ${r.name}') : add(outs, e.value.ymd, e.value.amount, r.name);
    }
  }
  return [
    for (var i = days - 1; i >= 0; i--)
      () {
        final ymd = _ymd(DateTime(end.year, end.month, end.day - i));
        return DayFlow(
          ymd: ymd,
          inCents: ins[ymd] ?? 0,
          outCents: outs[ymd] ?? 0,
          balance: accountNow(f, ymd)?.balance,
          checked: f.checks.containsKey(ymd),
          labels: labels[ymd] ?? const [],
        );
      }(),
  ];
}

class FlowTotals {
  final int inCents;
  final int outCents;
  const FlowTotals(this.inCents, this.outCents);
  int get net => inCents - outCents;
}

FlowTotals flowTotals(List<DayFlow> s) =>
    FlowTotals(s.fold<int>(0, (a, d) => a + d.inCents), s.fold<int>(0, (a, d) => a + d.outCents));

// ── Mon année (lot 2) ───────────────────────────────────────────────────────

/// Une catégorie sur l'année : enveloppe, domaine de vie ou fixe.
class CategoryYear {
  final String id;
  final String name;
  /// Sorties par mois (janvier = 0), en centimes.
  final List<int> months;
  /// Plafond mensuel (enveloppes), 0 = aucun.
  final int cap;
  const CategoryYear(this.id, this.name, this.months, {this.cap = 0});
  int get total => months.fold<int>(0, (a, b) => a + b);
}

enum YearBy { envelope, domain, fixed }

class YearSummary {
  final int year;
  /// Mois couverts : du premier mois suivi de l'année au mois en cours (1 → 12).
  final int firstMonth;
  final int lastMonth;
  final List<int> income;
  final List<int> spent;
  const YearSummary(this.year, this.firstMonth, this.lastMonth, this.income, this.spent);
  int get incomeTotal => income.fold<int>(0, (a, b) => a + b);
  int get spentTotal => spent.fold<int>(0, (a, b) => a + b);
  int get kept => incomeTotal - spentTotal;
  int get monthCount => lastMonth - firstMonth + 1;
  int get perMonth => monthCount <= 0 ? 0 : (spentTotal / monthCount).round();
}

int? _monthIn(String ymd, int year) => ymd.length >= 7 && ymd.startsWith('$year-') ? int.tryParse(ymd.substring(5, 7)) : null;

/// Années où quelque chose est noté, de la plus récente à la plus ancienne (au moins [currentYear]).
List<int> financeYears(Finances f, int currentYear) {
  final ys = <int>{currentYear};
  for (final x in f.expenses.values) {
    ys.add(int.tryParse(x.ymd.substring(0, 4)) ?? currentYear);
  }
  for (final x in f.incomes.values) {
    ys.add(int.tryParse(x.ymd.substring(0, 4)) ?? currentYear);
  }
  for (final m in f.paid.keys) {
    ys.add(int.tryParse(m.substring(0, 4)) ?? currentYear);
  }
  return ys.toList()..sort((a, b) => b.compareTo(a));
}

/// Rentré et sorti par mois sur [year] (sorties = dépenses + fixes passés).
YearSummary yearSummary(Finances f, int year, String todayYmd) {
  final income = List.filled(12, 0), spent = List.filled(12, 0);
  final byId = {for (final r in f.recurring) r.id: r};
  var first = 13;
  void mark(int m) => first = m < first ? m : first;
  for (final x in f.expenses.values) {
    final m = _monthIn(x.ymd, year);
    if (m == null) continue;
    spent[m - 1] += x.amount;
    mark(m);
  }
  for (final d in f.nothing) {
    final m = _monthIn(d, year);
    if (m != null) mark(m);
  }
  for (final x in f.incomes.values) {
    final m = _monthIn(x.ymd, year);
    if (m == null) continue;
    income[m - 1] += x.amount;
    mark(m);
  }
  for (final month in f.paid.values) {
    for (final e in month.entries) {
      final m = _monthIn(e.value.ymd, year);
      if (m == null) continue;
      byId[e.key]?.income == true ? income[m - 1] += e.value.amount : spent[m - 1] += e.value.amount;
      mark(m);
    }
  }
  final today = DateTime.parse(todayYmd);
  final last = today.year == year ? today.month : (today.year > year ? 12 : 0);
  return YearSummary(year, first > 12 ? last : first, last, income, spent);
}

/// Les sorties de [year] rangées par enveloppe, par domaine ou par fixe ;
/// [domainNames] = nom de chaque domaine (« Sans domaine » pour '').
List<CategoryYear> yearCategories(Finances f, int year, YearBy by, {Map<String, String> domainNames = const {}}) {
  final rows = <String, List<int>>{};
  void add(String id, String ymd, int v) {
    final m = _monthIn(ymd, year);
    if (m == null) return;
    rows.putIfAbsent(id, () => List.filled(12, 0))[m - 1] += v;
  }

  switch (by) {
    case YearBy.envelope:
      for (final x in f.expenses.values) {
        add(x.envelopeId, x.ymd, x.amount);
      }
      return [
        for (final e in f.envelopes)
          if (rows[e.id] != null) CategoryYear(e.id, e.name, rows[e.id]!, cap: e.monthly),
        for (final k in rows.keys)
          if (f.envelopeOf(k) == null) CategoryYear(k, 'Autre', rows[k]!),
      ];
    case YearBy.domain:
      for (final x in f.expenses.values) {
        add(x.domainId ?? '', x.ymd, x.amount);
      }
      final l = [for (final e in rows.entries) CategoryYear(e.key, e.key.isEmpty ? 'Sans domaine' : (domainNames[e.key] ?? 'Domaine'), e.value)];
      return l..sort((a, b) => a.id.isEmpty ? 1 : (b.id.isEmpty ? -1 : b.total.compareTo(a.total)));
    case YearBy.fixed:
      final byId = {for (final r in f.recurring) r.id: r};
      for (final month in f.paid.values) {
        for (final e in month.entries) {
          if (byId[e.key]?.income == true) continue;
          add(e.key, e.value.ymd, e.value.amount);
        }
      }
      final l = [for (final e in rows.entries) CategoryYear(e.key, byId[e.key]?.name ?? 'Fixe retiré', e.value)];
      return l..sort((a, b) => b.total.compareTo(a.total));
  }
}

/// Écart des 3 derniers mois CLOS (avant [lastMonth]) aux 3 d'avant, en % ;
/// null sans 6 mois clos ou sans rien avant.
int? trend3(List<int> months, int lastMonth, {int firstMonth = 1}) {
  final end = lastMonth - 1; // dernier mois clos (1 → 12)
  if (end - 5 < firstMonth) return null;
  int sum(int from, int to) => [for (var m = from; m <= to; m++) months[m - 1]].fold<int>(0, (a, b) => a + b);
  final recent = sum(end - 2, end), before = sum(end - 5, end - 3);
  if (before == 0) return null;
  return ((recent - before) / before * 100).round();
}

/// Les plus grosses dépenses d'une enveloppe sur [year].
List<Expense> biggestOf(Finances f, String envelopeId, int year, {int n = 3}) {
  final l = f.expenses.values.where((x) => x.envelopeId == envelopeId && _monthIn(x.ymd, year) != null).toList()
    ..sort((a, b) => b.amount.compareTo(a.amount));
  return l.take(n).toList();
}

/// Mois (jusqu'à [lastMonth]) où l'enveloppe a dépassé son plafond.
int monthsOverCap(CategoryYear c, int lastMonth) =>
    c.cap <= 0 ? 0 : [for (var m = 1; m <= lastMonth; m++) c.months[m - 1]].where((v) => v > c.cap).length;
