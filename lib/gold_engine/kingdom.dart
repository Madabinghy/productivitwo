part of '../gold_engine.dart';

/// Modèle « Royaume » — chaque DOMAINE de vie est une PROVINCE. Tout est DÉRIVÉ
/// (aucun champ persistant) : niveau = standards atteints, prospérité = château
/// (feuilles − toiles), menace = régression hebdo. Reflète le vrai travail.
extension GoldEngineKingdom on AppLogic {
  List<Activity> _domainActivities(String domainId) =>
      state.activeActivities.where((a) => a.domainId == domainId).toList();

  /// Cran de [target] sur l'échelle de standard (kStandardLadder), +1/15 au-delà.
  int _ladderRung(int target) {
    if (target <= 0) return 0;
    if (target > kStandardLadder.last) {
      return kStandardLadder.length + ((target - kStandardLadder.last) ~/ 15);
    }
    var rung = 0;
    for (var i = 0; i < kStandardLadder.length; i++) {
      if (target >= kStandardLadder[i]) rung = i + 1;
    }
    return rung;
  }

  /// Niveau de PROVINCE = 1 + moyenne des crans de standard de ses activités
  /// (cibles montées par `maybeLevelUpStandard` quand tu tiens 7/7). Domaine vide → 1.
  int provinceLevel(String domainId) {
    final acts = _domainActivities(domainId);
    if (acts.isEmpty) return 1;
    var sum = 0;
    for (final a in acts) {
      sum += _ladderRung(a.isHabit ? (a.habitTarget ?? 1) : a.goalMin);
    }
    return 1 + (sum / acts.length).round();
  }

  /// Prospérité = feuilles − toiles cumulées des activités du domaine (château).
  ({int leaves, int webs}) provinceProsperity(String domainId) {
    var leaves = 0, webs = 0;
    for (final a in _domainActivities(domainId)) {
      final f =
          a.isHabit ? routineChateauFill(a.id) : activityTimeChateauFill(a.id);
      leaves += f.leaves;
      webs += f.webs;
    }
    return (leaves: leaves, webs: webs);
  }

  /// Menace = régression hebdo du domaine (jours lâchés d'une semaine à l'autre).
  int provinceThreat(String domainId) => domainRegression(domainId);

  int provinceActivityCount(String domainId) =>
      _domainActivities(domainId).length;

  int kingdomLevel() => effectiveLevel();
}
