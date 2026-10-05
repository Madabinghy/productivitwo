import 'package:productivitwo_v1/models.dart';

/// Temps réellement passé sur une action = somme des sessions de chrono
/// CIBLÉES sur elle (`Session.actionId`). Même règle que le serveur
/// (`functions/src/estimates.ts`) : session ouverte ou de plus de 12 h
/// (chrono oublié) ignorée ; les blocs cochés sans chrono ne comptent pas.

const int kMaxSessionMin = 12 * 60;

/// Minutes d'une session fermée ; 0 si ouverte ou > 12 h.
int closedSessionMin(Session s) {
  final end = s.endAt;
  if (end == null || !end.isAfter(s.startAt)) return 0;
  final m = (end.difference(s.startAt).inSeconds / 60).round();
  return m > kMaxSessionMin ? 0 : m;
}

/// Minutes passées par action (`actionId` → minutes).
Map<String, int> spentByAction(Iterable<Session> sessions) {
  final out = <String, int>{};
  for (final s in sessions) {
    final id = s.actionId;
    if (id == null || id.isEmpty) continue;
    final m = closedSessionMin(s);
    if (m > 0) out[id] = (out[id] ?? 0) + m;
  }
  return out;
}

/// « 35 min passées » + dépassement éventuel de l'estimation.
({String label, bool over})? spentLabel(int spentMin, int? estimatedMin, String Function(int) fmt) {
  if (spentMin <= 0) return null;
  final over = estimatedMin != null && spentMin > estimatedMin;
  return (label: '⏱ ${fmt(spentMin)} passée${spentMin >= 2 ? 's' : ''}', over: over);
}
