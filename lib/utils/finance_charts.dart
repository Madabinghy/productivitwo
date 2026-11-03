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
