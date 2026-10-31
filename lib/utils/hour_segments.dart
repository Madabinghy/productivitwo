/// Barres horaires empilées (2026-10-31) : les tranches d'une heure, une par
/// domaine, dans l'ORDRE des domaines (même empilement d'une barre à l'autre).
/// [mergeBelow] > 0 : une tranche plus courte se fond dans la plus grosse de
/// l'heure (pilule de l'app bar, trop petite pour des tranches de 2 px).
List<(String, int)> hourSegments(Map<String, int> minutes, List<String> order, {int mergeBelow = 0}) {
  final m = {for (final e in minutes.entries) if (e.value > 0) e.key: e.value};
  if (m.isEmpty) return const [];
  if (mergeBelow > 0 && m.length > 1) {
    final top = m.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
    for (final k in m.keys.toList()) {
      if (k != top && m[k]! < mergeBelow) {
        m[top] = m[top]! + m.remove(k)!;
      }
    }
  }
  int rank(String k) {
    final i = order.indexOf(k);
    return i < 0 ? order.length : i;
  }

  final keys = m.keys.toList()..sort((a, b) => rank(a).compareTo(rank(b)));
  return [for (final k in keys) (k, m[k]!)];
}
