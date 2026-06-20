part of '../gold_engine.dart';

/// Échelle des paliers de STANDARD quotidien (minutes/jour ; pour les routines,
/// hits/jour — « 1 hit = 1 min »). Courbe douce au début, façon *atomic habits*.
/// Au-delà de 60, on continue par pas de +15.
const List<int> kStandardLadder = [1, 2, 5, 10, 15, 20, 30, 45, 60];

extension GoldEngineStandard on AppLogic {
  /// Palier juste AU-DESSUS de [current] sur l'échelle (ou +15 au-delà de 60).
  int nextStandardRung(int current) {
    for (final r in kStandardLadder) {
      if (r > current) return r;
    }
    return current + 15;
  }

  /// Les 7 cases de la fenêtre sont-elles toutes TENUES (leaf/flame) ? = le
  /// standard a été atteint CHAQUE jour (reconquête comprise — les tokens lisent
  /// déjà les crédits). Une araignée OU une case vide (jour sans effort, non
  /// rattrapé) → false. Sert de condition « 7 cases propres → +1 palier ».
  bool standardWindowClean(String activityId) {
    Activity? a;
    for (final x in state.activeActivities) {
      if (x.id == activityId) {
        a = x;
        break;
      }
    }
    if (a == null) return false;
    final toks =
        a.isHabit ? routineWeekTokens(activityId) : activityTimeTokens(activityId);
    if (toks.length < 7) return false;
    return toks.every((t) => t.type == 'leaf' || t.type == 'flame');
  }

  /// Montée SEULE (jamais de descente auto) : si la fenêtre est pleine (7/7
  /// tenues) et que la cible n'est pas épinglée par l'utilisateur, élève le
  /// standard d'UN cran (`goalMin` pour le temps, `habitTarget` pour une routine
  /// quotidienne). Élever le plancher re-salit mécaniquement les vieilles cases
  /// (pas d'emballement). Renvoie le nouveau palier si montée, sinon `null`.
  ///
  /// Hors périmètre v1 : cibles épinglées (`manualTarget`/`targetSource=='user'`)
  /// et routines hebdo/mensuelles (modèle de grâce différent).
  int? maybeLevelUpStandard(String activityId) {
    Activity? a;
    for (final x in state.activeActivities) {
      if (x.id == activityId) {
        a = x;
        break;
      }
    }
    if (a == null) return null;
    if (a.manualTarget || a.targetSource == 'user') return null; // épinglé
    if (a.isHabit && effectiveHabitFreq(a) != HabitFreq.daily) return null;
    if (!standardWindowClean(activityId)) return null;
    final current = a.isHabit ? (a.habitTarget ?? 1) : a.goalMin;
    final next = nextStandardRung(current);
    if (next <= current) return null;
    if (a.isHabit) {
      a.habitTarget = next;
    } else {
      a.goalMin = next;
    }
    onChange();
    return next;
  }
}
