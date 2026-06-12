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

  /// Plafond du drain horaire par visite (un ennemi négligé ne coûte jamais plus
  /// de [pestDrainCapHours] × sa force). Abaissé de 12 à 6 h : avec le revenu temps
  /// plafonné à 80/j, 12 h de drain mangeaient presque une journée entière.
  static const int pestDrainCapHours = 6;

  /// Butin GARANTI à la mise à mort : couvre au moins une session de drain
  /// complète (force × plafond) → un ennemi tué est toujours net-positif. Doublé
  /// pour le gardien. L'appelant y ajoute un petit aléa.
  static int pestLootBase(String type, bool guardian) =>
      pestCost(type) * pestDrainCapHours * (guardian ? 2 : 1);

  /// Arme requise pour tuer le CŒUR d'un nuisible (phase 2).
  // araignée→🔪 couteau · scorpion→🔪 couteau · serpent→🗡️ épée.
  static String weaponForPest(String type) {
    switch (type) {
      case 'snake':
        return 'epee';
      default:
        return 'couteau'; // spider et scorpion → couteau
    }
  }

  /// Arme requise pour tuer les SBIRES (phase 1 avant le cœur). Mapping
  /// THÉMATIQUE : chaque arme se gagne par un type d'effort et sert contre
  /// l'ennemi du même domaine → les 3 armes ont une source ET un débouché.
  /// 🕷️ araignée (routine) → 🔪 couteau (gagné par routines)
  /// 🦂 scorpion (activité temps) → 🏹 arc (gagné par heures loggées)
  /// 🐍 serpent (tâche) → 🗡️ épée (gagné par actions de projet)
  /// snake sbires nécessitent aussi ninja skin (voir minionNeedsNinja).
  static String minionWeaponForPest(String type) {
    switch (type) {
      case 'snake': return 'epee';
      case 'scorpion': return 'arc';
      default: return 'couteau'; // spider (routine) → couteau
    }
  }

  static bool minionNeedsNinja(String type) => type == 'snake';

  /// Plafond de sbires : la garde scale avec la SÉVÉRITÉ de la négligence
  /// (jours en déficit / actions accumulées), mais reste bornée. Voir
  /// `AppLogic.enemySbires`.
  static const int maxSbires = 10;

  /// Fenêtre (jours) sur laquelle on compte la négligence d'une routine/activité.
  static const int neglectWindowDays = 14;

  /// Prix de revente d'une arme (liquidation du surplus). Volontairement bas :
  /// décrassage, pas une source de revenu (l'arme vient déjà d'un gain d'or).
  static const int weaponSellPrice = 2;

  // ── Social « Le Monde » ────────────────────────────────────────────────────
  /// Captures (kills de ton backlog) requises pour gagner 1 jeton de relâche.
  static const int capturesPerReleaseToken = 10;

  /// PV (difficulté) d'un nuisible relâché, dérivé de la série/niveau de
  /// l'émetteur : plus il est régulier, plus son nuisible est dur à battre
  /// (prestige à le suivre). Le récepteur le combat à l'arme.
  static int worldNuisibleHp(int streak, int level) =>
      (3 + streak ~/ 2 + level).clamp(3, 30);

  // ── Bataille de nuisibles ──────────────────────────────────────────────────
  // Équité : la force d'une armée = effort RÉEL (temps), pas le nombre de
  // routines. 1 capture de routine minte sa masse = effort-minutes (plancher 5).
  // On dépense la masse en déployant un palier de nuisible.
  static const int masseSpider = 5; // 🕷️ araignée = unité de base (~5 min)
  static const int masseScorpion = 10; // 🦂 = 2 araignées
  static const int masseSerpent = 15; // 🐍 = 3 araignées
  static const int masseFloor = masseSpider; // routine sans temps → 1 araignée
  // Anti-déluge : masse max déployable par tick (= 1 serpent, ou 1 scorpion +
  // 1 araignée, ou 3 araignées). La réserve = endurance, pas un one-shot.
  static const int masseBudgetPerTick = masseSerpent; // 15
  // Durée de vie d'un nuisible dans le deck : fenêtre glissante. Le deck = effort
  // des N derniers jours → frais + équitable pour les nouveaux joueurs.
  static const int battleDeckWindowDays = 7;

  /// Masse mintée à la capture d'une routine de `effortMin` minutes (plancher).
  static int battleMasseForMinutes(int effortMin) =>
      effortMin < masseFloor ? masseFloor : effortMin;

  /// Coût en masse d'un palier déployé.
  static int masseCost(String tier) => switch (tier) {
        'serpent' => masseSerpent,
        'scorpion' => masseScorpion,
        _ => masseSpider,
      };

  /// Force d'un palier (résolution des collisions) : serpent > scorpion >
  /// araignée. Égalité → les deux meurent ; sinon le plus fort survit dégradé.
  static int tierStrength(String tier) => switch (tier) {
        'serpent' => 3,
        'scorpion' => 2,
        _ => 1,
      };

  /// Palier juste en dessous (dégradation après avoir mangé un plus faible).
  static String? tierBelow(String tier) => switch (tier) {
        'serpent' => 'scorpion',
        'scorpion' => 'spider',
        _ => null, // une araignée vainqueur n'arrive jamais (égalité = double mort)
      };

  static const int minutesPerArrow = 60; // 1 h de temps loggé = 1 flèche

  /// Coût en armes globales (du type adapté) pour ENGAGER un nuisible (l'épingler
  /// dans « Combats en cours »). Donne un rôle aux armes globales ; ne blesse pas
  /// (la blessure se fait au travail spécifique). Tunable.
  static const int engageCost = 2;

  // ── Invasion / Territoires ─────────────────────────────────────────────────
  // On CRAFTE des nuisibles ROUGES (asset offensif persistant) en sacrifiant des
  // captures du TYPE correspondant. Le roster de rouges DISPONIBLES = la puissance
  // de deck du ladder (un rouge déployé est immobilisé → retiré de la puissance).
  static const int redCraftCost = 10; // nuisibles d'un palier → 1 rouge du palier
  static const int redUpgradeCost = 6; // nuisibles du palier pour monter un rouge

  /// Palier juste AU-DESSUS (montée en gamme d'un rouge nourri).
  static String? tierAbove(String tier) => switch (tier) {
        'spider' => 'scorpion',
        'scorpion' => 'serpent',
        _ => null,
      };

  /// Poids d'un rouge dans la puissance de deck (ladder).
  static int redPower(String tier) => tierStrength(tier);

  // ── Boss PvE (mode Territoires solo) ───────────────────────────────────────
  /// Or gagné en repoussant un boss réel (récompense de défense).
  static const int bossWinReward = 30;
  /// Plafond de dégât au deck par invasion-boss (par palier), pour garder la
  /// perte récupérable — jamais une brûlure massive du deck.
  static const int bossDeckDamageCap = 3;

  // ── Bestiaire : créatures débloquées par RECETTES de captures ───────────────
  // Le BUT du farm : capturer X nuisibles d'un (ou plusieurs) type(s) débloque
  // une créature dans la Collection. Progression naturelle araignée→scorpion→
  // serpent→dragon (les recettes mixtes exigent des cartes de niveau supérieur).
  static const List<
          ({String id, String emoji, String name, Map<String, int> recipe})>
      bestiaryRecipes = [
    (id: 'b_mouse', emoji: '🐭', name: 'Souris', recipe: {'spider': 3}),
    (id: 'b_frog', emoji: '🐸', name: 'Grenouille', recipe: {'spider': 8}),
    (id: 'b_cat', emoji: '🐈', name: 'Chat', recipe: {'scorpion': 4}),
    (id: 'b_lizard', emoji: '🦎', name: 'Lézard',
        recipe: {'spider': 5, 'scorpion': 2}),
    (id: 'b_eagle', emoji: '🦅', name: 'Aigle', recipe: {'snake': 3}),
    (id: 'b_wolf', emoji: '🐺', name: 'Loup',
        recipe: {'scorpion': 6, 'snake': 2}),
    (id: 'b_dragon', emoji: '🐲', name: 'Dragon',
        recipe: {'spider': 10, 'scorpion': 5, 'snake': 3}),
  ];

  static const int weaponEpee = 8; // tue un serpent (consommable)
  static const int weaponCouteau = 5; // tue araignée/scorpion — cœur (consommable)

  static int weaponBasePrice(String key) =>
      key == 'epee' ? weaponEpee : weaponCouteau;

  // ── Skins d'avatar (cosmétiques, puits d'or) ───────────────────────────────
  // Possédés via cosmeticsOwned ('avatar_<id>') ; activeAvatar stocke l'emoji.
  static const List<({String id, String emoji, String name, int price})>
      avatarSkins = [
    (id: 'default', emoji: '🧍', name: 'Aventurier', price: 0),
    (id: 'mage', emoji: '🧙', name: 'Mage', price: 30),
    (id: 'cowboy', emoji: '🤠', name: 'Cowboy', price: 50),
    (id: 'ninja', emoji: '🥷', name: 'Ninja', price: 70),
    (id: 'hero', emoji: '🦸', name: 'Héros', price: 100),
    (id: 'wizard', emoji: '🧚', name: 'Fée', price: 120),
    (id: 'robot', emoji: '🤖', name: 'Robot', price: 150),
  ];

  /// Type d'ennemi qui apparaît selon le niveau (force croissante) : araignée
  /// (niv.1-2), scorpion (3-4), serpent (5+). Le serpent exige l'épée (tâche).
  static String pestTypeForLevel(int level) {
    if (level <= 2) return 'spider';
    if (level <= 4) return 'scorpion';
    return 'snake';
  }

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

  // ── Valeur du temps ─────────────────────────────────────────────────────────
  // Taux PLAT : 1 or / 15 min loggué, quel que soit le niveau. Choisi plutôt que
  // le dégressif car le temps loggué INCLUT le sommeil — pénaliser les grosses
  // journées punirait injustement qui logue ses nuits. Plafond naturel : 20 h/j
  // (max physique) → 80 or/jour sur le temps. [level] gardé pour pouvoir réactiver
  // un scaling plus tard sans toucher les appelants.
  static const int flatMinutesPerGold = 15;

  static int minutesPerGold(int level) => flatMinutesPerGold;

  /// Or gagné pour [minutes] de temps loggué (arrondi bas). Plat : minutes / 15.
  static int goldForMinutes(int minutes, int level) =>
      minutes <= 0 ? 0 : minutes ~/ flatMinutesPerGold;

  // ── Quête du jour + coffre (motiver à en faire plus) ───────────────────────
  static const int dailyQuestTarget = 3; // actions à accomplir aujourd'hui
  static const int questChestGoldMin = 10; // récompense variable du coffre
  static const int questChestGoldMax = 25;
  static const int questChestCollectibleChancePct = 30; // % de chance d'un butin

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
