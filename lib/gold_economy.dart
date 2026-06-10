/// Économie d'Or — constantes & formules PURES (aucune dépendance plateforme).
/// Partagé par le moteur mobile (`gold_engine.dart`) ET l'app web, pour que les
/// deux puissent calculer un coût et l'appliquer via `FirestoreSync.applyGold`.
class GoldEconomy {
  // Gains (créditent le solde ET le lifetime → niveau)
  static const int routineMet = 2; // gain de base par jour
  // Bonus de série : +1 or tous les N jours de streak, plafonné. Faire une
  // routine rapporte d'autant plus que la série est longue.
  static const int routineStreakBonusStep = 3;
  static const int routineStreakBonusCap = 13;

  /// Or gagné en faisant une routine, selon la longueur de série atteinte.
  static int routineGain(int streakDays) {
    final bonus = (streakDays ~/ routineStreakBonusStep);
    return routineMet + (bonus > routineStreakBonusCap ? routineStreakBonusCap : bonus);
  }

  static const int timePerHour = 1;
  static const int challengeDone = 5;
  static const int ganttAction = 1;
  static const int taskDone = 3;

  // Pertes / coûts (débitent le solde seul, plancher 0)
  static const int routineMissed = 1; // par jour, après 1ʳᵉ complétion
  static const int lateTaskPerDay = 1; // par tâche, par jour de retard
  static const int deadlinePush = 3;
  static const int deleteAction = 1;
  static const int deleteTaskBase = 2; // + 1 par action contenue
  static const int deleteRoutine = 5;
  static const int deleteProjectPerTask = 3;
  static const int deleteProjectPerAction = 1;
  static const int deleteProjectMin = 5;

  // Boutique (dépense d'or)
  static const int shopGel = 15;
  static const int shopSursis = 20;
  static const int shopJoker = 25;
  static const int shopShield = 20; // bouclier anti-retard
  static const int shopBoost = 45; // multiplicateur ×2 (pouvoir multi-jours)
  static const int shopRepair = 40; // réparation de série (jour passé)
  static const int shieldDaysPerUse = 7; // durée du bouclier anti-retard
  static const int boostDaysPerUse = 3; // durée du multiplicateur ×2 (jours)

  /// Coût de suppression d'un projet : proportionnel à son contenu (min plancher).
  static int deleteProjectCost(int tasksCount, int actionsCount) {
    final c = deleteProjectPerTask * tasksCount + deleteProjectPerAction * actionsCount;
    return c < deleteProjectMin ? deleteProjectMin : c;
  }

  /// Coût de suppression d'une tâche : base + 1 par action contenue.
  static int deleteTaskCost(int actionsCount) => deleteTaskBase + actionsCount;

  // ── Révélation de niveau (gate de progression payant) ──────────────────────
  // L'XP (goldLifetime) rend un niveau ÉLIGIBLE ; il faut PAYER (depuis le solde
  // dépensable) pour révéler son titre et débloquer le niveau. Coût croissant.
  static const int revealBase = 15; // coût pour révéler le niveau 2
  static const double revealGrowth = 1.55;

  /// Coût en or pour révéler [level] (niveau 1 gratuit). Croît géométriquement,
  /// arrondi à la dizaine pour des prix lisibles.
  static int revealCost(int level) {
    if (level <= 1) return 0;
    var c = revealBase.toDouble();
    for (int i = 2; i < level; i++) {
      c *= revealGrowth;
    }
    final rounded = (c / 10).round() * 10;
    return rounded < 10 ? 10 : rounded;
  }

  // ── Boutique : items par paliers + prix croissants ─────────────────────────
  /// Niveau minimum (débloqué) requis pour acheter chaque consommable.
  static const Map<String, int> itemMinLevel = {
    'gel': 1,
    'sursis': 2,
    'joker': 3,
    'shield': 5,
    'boost': 7,
    'repair': 9,
  };

  /// Inflation des prix : +12 % du prix de base par niveau débloqué au-delà de 1.
  static const double priceInflationPerLevel = 0.12;

  /// Prix effectif d'un item selon le niveau débloqué (arrondi à l'entier).
  static int scaledPrice(int basePrice, int unlockedLevel) {
    final lvl = unlockedLevel < 1 ? 1 : unlockedLevel;
    final p = basePrice * (1 + priceInflationPerLevel * (lvl - 1));
    return p.round();
  }

  // ── Outils d'expédition (mini-carte de déblocage de niveau) ────────────────
  // Achetés en boutique (toujours dispo : sinon impossible d'avancer), prix scalé
  // par niveau via scaledPrice → expédition plus chère/longue au fil des niveaux.
  static const int toolPas = 4; // 🥾 franchir un pas ordinaire
  static const int toolPioche = 10; // ⛏️ casser un rocher
  static const int toolCle = 10; // 🔑 ouvrir une grille
  static const int toolPelle = 10; // 🪏 combler un trou

  static int toolBasePrice(String key) {
    switch (key) {
      case 'pas':
        return toolPas;
      case 'pioche':
        return toolPioche;
      case 'cle':
        return toolCle;
      case 'pelle':
        return toolPelle;
      default:
        return 5;
    }
  }

  // ── Overworld (carte 2D explorable) ────────────────────────────────────────
  static const int stepCost = 1; // déplacement sur case éclairée
  static const int torchCost = 5; // éclairer une case en brouillard (révèle radius 1)
  static const int lootGoldMin = 4; // butin (collectible rare) → petit or
  static const int lootGoldMax = 12;

  // ── Écosystème de carte (lié au % hebdo) ───────────────────────────────────
  static const int trendSpawnCapPct = 40; // proba de spawn plafonnée
  static const int maxLivePests = 4; // nuisibles simultanés max
  static const int bonusGoldMin = 5; // bonus d'or (tendance positive)
  static const int bonusGoldMax = 15;

  /// Coût/jour de drain ET durée de vie (en jours) d'un nuisible (= son coût).
  static int pestCost(String type) {
    switch (type) {
      case 'spider':
        return 2;
      case 'scorpion':
        return 3;
      case 'snake':
        return 5;
      default:
        return 0;
    }
  }

  static int pestLifespanDays(String type) => pestCost(type);

  /// Arme requise pour tuer un nuisible : épée pour le serpent, sandale sinon.
  static String weaponForPest(String type) => type == 'snake' ? 'epee' : 'sandale';

  static const int weaponEpee = 8; // tue un serpent (consommable)
  static const int weaponSandale = 5; // tue araignée/scorpion (consommable)

  static int weaponBasePrice(String key) =>
      key == 'epee' ? weaponEpee : weaponSandale;

  // ── Niveaux & plafond d'XP (source de vérité partagée) ─────────────────────
  // Seuils d'or-à-vie pour atteindre chaque niveau (1-15), puis prestige par
  // crans de [prestigeStep]. Déplacés ici depuis app_logic pour être partagés
  // par le moteur, les transactions Firestore et le web.
  static const List<int> levelThresholds = [
    0, 30, 80, 200, 450, 800, 1500, 2500, 4000, 7000,
    11000, 16000, 23000, 32000, 45000,
  ];
  static const int prestigeStep = 8000;

  /// Seuil d'or-à-vie requis pour atteindre [level] (gère le prestige).
  static int thresholdForLevel(int level) {
    if (level <= 1) return 0;
    if (level <= levelThresholds.length) return levelThresholds[level - 1];
    return levelThresholds.last +
        (level - levelThresholds.length) * prestigeStep;
  }

  /// Part d'un gain qui alimente l'XP (or-à-vie), PLAFONNÉE au seuil du prochain
  /// niveau tant qu'il n'est pas débloqué. Le surplus déborde en or seul (la
  /// soupape anti-famine) : `goldLifetime += cappedLifetimeAdd(...)`, mais le
  /// solde `gold` reçoit toujours le gain plein.
  static int cappedLifetimeAdd(int gain, int currentLifetime, int unlockedLevel) {
    if (gain <= 0) return 0;
    final cap = thresholdForLevel((unlockedLevel < 1 ? 1 : unlockedLevel) + 1);
    final room = cap - currentLifetime;
    if (room <= 0) return 0;
    return gain < room ? gain : room;
  }

  // ── Valeur du temps par niveau ──────────────────────────────────────────────
  // Plus on monte, plus l'or se mérite : niv.1 → 1 min = 1 or ; niv.5 → 5 min ;
  // niv.10 → 10 min. Généreux au début (anti-famine), avare ensuite (compensé
  // par les pouvoirs multi-jours). Principal knob de tuning de l'économie.
  static int minutesPerGold(int level) => level < 1 ? 1 : level;

  /// Or gagné pour [minutes] de temps loggué au niveau [level] (arrondi bas).
  static int goldForMinutes(int minutes, int level) =>
      minutes ~/ minutesPerGold(level);

  // ── Difficulté des défis du donjon (scaling par niveau visé) ───────────────
  // Rapide au début (le user doit SENTIR qu'il progresse), plus exigeant ensuite.
  // Niveaux 2-3 : routine « aujourd'hui » (1 j) → déblocable en une journée.
  // Puis +1 jour tous les 3 niveaux, plafonné à 5.
  static int challengeRoutineDays(int level) =>
      ((level - 1) ~/ 3 + 1).clamp(1, 5);

  /// Minutes de temps à logger pour le défi de temps, scalées comme la routine.
  static int challengeTimeMinutes(int level) =>
      30 + (challengeRoutineDays(level) - 1) * 15; // 30,45,60,75,90
}
