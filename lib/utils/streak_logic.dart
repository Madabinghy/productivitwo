/// Séries de routines « qui pardonnent » (audit lot 2, PR B) : une routine
/// quotidienne a UN joker par semaine glissante. Un jour sous la cible le
/// consomme automatiquement : la série continue. Deux jours ratés à moins de
/// 7 jours d'écart cassent la série. Aujourd'hui n'est jamais jugé (la
/// journée n'est pas finie). Logique pure, testée.

class StreakInfo {
  final int streak;
  /// Dernier jour raté couvert par un joker dans les 6 derniers jours (pour
  /// l'étiquette « joker mar. ») ; null sinon.
  final DateTime? jokerDay;
  /// Un joker est disponible pour aujourd'hui (aucun consommé depuis 6 jours).
  final bool jokerAvailable;
  const StreakInfo({required this.streak, required this.jokerDay, required this.jokerAvailable});
}

StreakInfo computeStreak({
  required DateTime today,
  required bool Function(DateTime day) reached,
  bool Function(DateTime day)? frozen,
  int maxDays = 3650,
}) {
  final t = DateTime(today.year, today.month, today.day);
  var d = t;
  if (!reached(t)) d = t.subtract(const Duration(days: 1));
  final covered = <DateTime>[];
  bool canCover(DateTime day) =>
      !covered.any((c) => c.difference(day).inDays.abs() <= 6);
  var streak = 0;
  var guard = 0;
  while (guard++ < maxDays) {
    if (reached(d)) {
      streak++;
    } else if (frozen != null && frozen(d)) {
      // Jour gelé (ancien « Gel de série ») : enjambé.
    } else if (canCover(d)) {
      covered.add(d);
    } else {
      break;
    }
    d = d.subtract(const Duration(days: 1));
  }
  // Un joker « en tête » sans aucun jour réussi derrière ne couvre rien.
  if (streak == 0) covered.clear();
  final recent = covered.where((c) => t.difference(c).inDays <= 6).toList();
  return StreakInfo(
    streak: streak,
    jokerDay: recent.isEmpty ? null : recent.first,
    jokerAvailable: recent.isEmpty,
  );
}
