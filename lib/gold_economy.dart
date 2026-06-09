/// Économie d'Or — constantes & formules PURES (aucune dépendance plateforme).
/// Partagé par le moteur mobile (`gold_engine.dart`) ET l'app web, pour que les
/// deux puissent calculer un coût et l'appliquer via `FirestoreSync.applyGold`.
class GoldEconomy {
  // Gains (créditent le solde ET le lifetime → niveau)
  static const int routineMet = 2; // par jour
  static const int timePerHour = 1;
  static const int challengeDone = 5;
  static const int ganttAction = 1;
  static const int taskDone = 3;

  // Pertes / coûts (débitent le solde seul, plancher 0)
  static const int routineMissed = 1; // par jour, après 1ʳᵉ complétion
  static const int lateTaskPerDay = 1; // par tâche, par jour de retard
  static const int deadlinePush = 3;
  static const int deleteAction = 1;
  static const int deleteRoutine = 5;
  static const int deleteProjectPerTask = 3;
  static const int deleteProjectPerAction = 1;
  static const int deleteProjectMin = 5;

  // Boutique (dépense d'or)
  static const int shopGel = 15;
  static const int shopSursis = 20;
  static const int shopJoker = 25;

  /// Coût de suppression d'un projet : proportionnel à son contenu (min plancher).
  static int deleteProjectCost(int tasksCount, int actionsCount) {
    final c = deleteProjectPerTask * tasksCount + deleteProjectPerAction * actionsCount;
    return c < deleteProjectMin ? deleteProjectMin : c;
  }
}
