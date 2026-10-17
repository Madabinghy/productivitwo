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

/// Facteur réel / estimé (médiane) sur les actions FAITES qui ont une
/// estimation et du temps chronométré — même règle que `estimate_accuracy`
/// côté serveur. Null sous [minSamples] actions (pas assez de recul).
double? estimateFactor(Iterable<Project> projects, Map<String, int> spent, {int minSamples = 3}) {
  final ratios = <double>[];
  for (final p in projects) {
    for (final t in p.tasks) {
      for (final a in t.actions) {
        final est = a.estimatedMin;
        final real = spent[a.id] ?? 0;
        if (!a.done || est == null || est <= 0 || real <= 0) continue;
        ratios.add(real / est);
      }
    }
  }
  if (ratios.length < minSamples) return null;
  ratios.sort();
  final mid = ratios.length ~/ 2;
  return ratios.length.isOdd ? ratios[mid] : (ratios[mid - 1] + ratios[mid]) / 2;
}

/// « Réel ≈ 1,3× l'estimé » ; null sans facteur.
String? estimateFactorLabel(double? factor) {
  if (factor == null) return null;
  final s = factor.toStringAsFixed(1).replaceAll('.', ',');
  return 'Réel ≈ $s× l\'estimé';
}

/// « 35 min passées » + dépassement éventuel de l'estimation.
({String label, bool over})? spentLabel(int spentMin, int? estimatedMin, String Function(int) fmt) {
  if (spentMin <= 0) return null;
  final over = estimatedMin != null && spentMin > estimatedMin;
  return (label: '⏱ ${fmt(spentMin)} passée${spentMin >= 2 ? 's' : ''}', over: over);
}
