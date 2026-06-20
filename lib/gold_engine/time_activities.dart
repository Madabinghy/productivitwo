part of '../gold_engine.dart';

extension GoldEngineTime on AppLogic {
  // ── ACTIVITÉS TEMPS (type=time) — même tapis mais en minutes vs objectif ──
  int _minutesOnDay(String activityId, DateTime date) {
    final ds = DateTime(date.year, date.month, date.day);
    return totalForRangeByActivity(activityId, ds, ds.add(const Duration(days: 1)))
        .inMinutes;
  }

  /// Minutes du jour + crédits de RECONQUÊTE (minutes virtuelles imputées à ce
  /// jour). Réservé aux consommateurs JARDIN (tapis, château) — l'économie d'or
  /// lit `_minutesOnDay` brut : la reconquête ne génère JAMAIS d'or ni ne touche
  /// le rapport temps factuel.
  int _minutesOnDayGarden(String activityId, DateTime date) =>
      _minutesOnDay(activityId, date) +
      redemptionCreditsOn(activityId, yyyymmdd(date), 'time');

  /// Hits du jour + crédits de RECONQUÊTE (hits virtuels). Même règle que
  /// [_minutesOnDayGarden] : jardin oui, or non.
  int _habitValueOnGarden(String activityId, DateTime date) =>
      habitValueOn(activityId, date) +
      redemptionCreditsOn(activityId, yyyymmdd(date), 'habit');

  /// Tokens du tapis pour une activité TEMPS : par jour, minutes vs `goalMin`.
  /// 'flame' (≥2j à l'objectif) · 'leaf' (objectif atteint) · 'spider' (PV =
  /// minutes restantes pour l'objectif).
  List<({String type, int hp})> activityTimeTokens(String activityId) {
    Activity? a;
    for (final x in state.activeActivities) {
      if (x.id == activityId) {
        a = x;
        break;
      }
    }
    if (a == null || a.isHabit) return const [];
    final goal = a.goalMin;
    if (goal <= 0) return const [];
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // Cible HEBDO (fenêtre 7 jours glissants). Un jour SANS travail n'est un
    // nuisible 🦂 que si, sur la fenêtre 7j FINISSANT ce jour-là, tu étais EN
    // RETARD (total < cible). Si la cible était tenue → « satisfait » (vide) :
    // pas besoin d'y toucher ce jour. Un jour travaillé = flamme/feuille.
    final weekTarget = timeSliding(a.id, 7).targetMin;
    final target7 = weekTarget > 0 ? weekTarget : goal * 7;
    final out = <({String type, int hp})>[];
    for (var i = 0; i < 7; i++) {
      final date = today.subtract(Duration(days: 6 - i));
      final mins = _minutesOnDayGarden(a.id, date);
      if (mins >= goal) {
        var run = 0;
        var d = date;
        while (_minutesOnDayGarden(a.id, d) >= goal) {
          run++;
          if (run >= 2) break;
          d = d.subtract(const Duration(days: 1));
        }
        out.add((type: run >= 2 ? 'flame' : 'leaf', hp: 0));
        continue;
      }
      // Pas (assez) travaillé ce jour → en retard sur la fenêtre 7j glissante ?
      var trailing7 = 0;
      for (var k = 0; k < 7; k++) {
        trailing7 += _minutesOnDayGarden(a.id, date.subtract(Duration(days: k)));
      }
      if (trailing7 < target7) {
        out.add((type: 'spider', hp: (target7 - trailing7).clamp(1, 1 << 30)));
      } else {
        out.add((type: 'empty', hp: 0));
      }
    }
    return out;
  }

  /// Château d'une activité temps : net des jours passés (objectif manqué = toile).
  ({int webs, int leaves}) activityTimeChateauFill(String activityId) {
    Activity? a;
    for (final x in state.activeActivities) {
      if (x.id == activityId) {
        a = x;
        break;
      }
    }
    if (a == null || a.isHabit) return (webs: 0, leaves: 0);
    final goal = a.goalMin;
    if (goal <= 0) return (webs: 0, leaves: 0);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    var misses = 0, dones = 0;
    for (var k = 7; k < 28; k++) {
      if (_minutesOnDayGarden(a.id, today.subtract(Duration(days: k))) >= goal) {
        dones++;
      } else {
        misses++;
      }
    }
    final net = misses - dones;
    final webs = net > 9 ? 9 : (net < 0 ? 0 : net);
    final leaves = net < 0 ? (-net > 9 ? 9 : -net) : 0;
    return (webs: webs, leaves: leaves);
  }

  /// Minutes loggées sur 30j (pour trier les activités temps les plus actives).
  int activityTime30dMin(String activityId) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    var n = 0;
    for (var k = 0; k < 30; k++) {
      n += _minutesOnDay(activityId, today.subtract(Duration(days: k)));
    }
    return n;
  }

  /// Activité d'une routine sur 30 jours = nb de jours faits (pour trier les plus
  /// actives).
  int routine30dActive(String routineId) {
    Activity? a;
    for (final x in state.activeActivities) {
      if (x.id == routineId) {
        a = x;
        break;
      }
    }
    if (a == null || !a.isHabit) return 0;
    final quota = dayQuotaFor(a);
    if (quota <= 0) return 0;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    var n = 0;
    for (var k = 0; k < 30; k++) {
      if (habitValueOn(a.id, today.subtract(Duration(days: k))) >= quota) n++;
    }
    return n;
  }

  /// Tokens du COMBAT après « pardon de série » : une série de N élimine les N plus
  /// vieilles araignées (converties en 🍃) — récompense de régularité. N'affecte PAS
  /// l'économie de gold (routineWeekTokens reste la vérité brute) : sert à l'affichage
  /// du combat, au ciblage du canon, au rattrapage et au compteur de nuisibles.
  List<({String type, int hp})> routineWaveTokens(String routineId) {
    final toks = List<({String type, int hp})>.from(routineWeekTokens(routineId));
    var forgive = habitCurrentStreak(routineId);
    if (forgive <= 0) return toks;
    for (var j = 0; j < toks.length && forgive > 0; j++) {
      if (toks[j].type == 'spider') {
        toks[j] = (type: 'leaf', hp: 0);
        forgive--;
      }
    }
    return toks;
  }

  /// Index de la PREMIÈRE araignée (jour manqué le plus ANCIEN) restant APRÈS le
  /// pardon de série, ou -1 si aucune. (index 0 = il y a 6 jours … 6 = aujourd'hui.)
  int firstSpiderIndex(String routineId) {
    final toks = routineWaveTokens(routineId);
    for (var j = 0; j < toks.length; j++) {
      if (toks[j].type == 'spider') return j;
    }
    return -1;
  }

  /// Jour à créditer quand on « tue » la première araignée d'une routine en combat :
  /// le jour manqué le plus ANCIEN de la fenêtre 7j (rattrapage), ou aujourd'hui si
  /// aucune araignée. Tuer la 1ʳᵉ fait avancer la vague (le suivant devient la cible).
  DateTime routineCatchUpDay(String routineId) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final j = firstSpiderIndex(routineId);
    return j < 0 ? today : today.subtract(Duration(days: 6 - j));
  }

  /// Valide une routine en COMBAT — modèle « plus ancien d'abord, propre ».
  ///
  /// Le canon vise toujours la plus vieille araignée ([routineCatchUpDay]). On
  /// loggue TOUJOURS un vrai hit AUJOURD'HUI (relevé honnête, compte pour l'or du
  /// jour). Si la cible est un jour PASSÉ, on pose EN PLUS un crédit de RECONQUÊTE
  /// sur ce jour (couche jeu : nettoie l'araignée, mais PAS d'or et SANS falsifier
  /// le relevé de ce jour-là) au lieu de l'ancien `incHabit(jourPassé)`.
  ///
  /// Après l'effort, tente la MONTÉE de palier (« 7 cases propres → +1 ») et
  /// renvoie le nouveau palier si le standard a monté, sinon `null` (pour la
  /// célébration côté UI). [persist] persiste le crédit (ex. `sync.saveRedemption`) ;
  /// sur mobile le push de state s'en charge aussi.
  int? validateRoutineCombat(String routineId,
      {void Function(Redemption)? persist}) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = routineCatchUpDay(routineId);
    incHabit(routineId, 1, today); // effort réel du jour (appelle onChange)
    if (yyyymmdd(target) != yyyymmdd(today)) {
      final r = Redemption(
        activityId: routineId,
        type: 'habit',
        targetDate: yyyymmdd(target),
        amount: 1,
        sourceDate: yyyymmdd(today),
      );
      state.redemptions.add(r); // optimiste local → jardin à jour
      persist?.call(r);
      onChange();
    }
    return maybeLevelUpStandard(routineId);
  }

  /// Tokens du tapis roulant pour les 7 DERNIERS jours (index 0 = il y a 6 jours,
  /// 6 = AUJOURD'HUI à droite ; tourne tout seul chaque jour, pas de bouton).
  /// Chaque jour : `type` = 'spider' (manqué) · 'leaf' (fait, 1er jour repris) ·
  /// 'flame' (fait avec ≥ 2 jours d'affilée) ; `hp` = PV RESTANTS d'une araignée
  /// = cible − ce qui a été saisi ce jour (saisir 1 unité = −1 PV ; 0 PV = jour
  /// fait). On reste « araignée » tant qu'il reste ≥ 1 PV.
  List<({String type, int hp})> routineWeekTokens(String routineId) {
    Activity? a;
    for (final x in state.activeActivities) {
      if (x.id == routineId) {
        a = x;
        break;
      }
    }
    if (a == null || !a.isHabit) return const [];
    final quota = dayQuotaFor(a);
    if (quota <= 0) return const [];
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final freq = effectiveHabitFreq(a);
    if (freq != HabitFreq.daily) {
      // Hebdo/mensuelle : par jour — 🍃 feuille si faite CE jour ; vide pendant
      // la grâce (faite dans les `period` jours précédents) ; 🕷️ araignée si EN
      // RETARD (rien fait dans la période) → une araignée chaque jour tant que pas
      // faite.
      final period = freq == HabitFreq.weekly ? 7 : 30;
      final out = <({String type, int hp})>[];
      for (var i = 0; i < 7; i++) {
        final date = today.subtract(Duration(days: 6 - i));
        if (_habitValueOnGarden(a.id, date) >= quota) {
          out.add((type: 'leaf', hp: 0));
          continue;
        }
        var doneInPeriod = false;
        for (var k = 0; k < period; k++) {
          if (_habitValueOnGarden(a.id, date.subtract(Duration(days: k))) >= quota) {
            doneInPeriod = true;
            break;
          }
        }
        out.add(doneInPeriod
            ? (type: 'empty', hp: 0)
            : (type: 'spider', hp: quota));
      }
      return out;
    }
    final out = <({String type, int hp})>[];
    for (var i = 0; i < 7; i++) {
      final date = today.subtract(Duration(days: 6 - i));
      final value = _habitValueOnGarden(a.id, date);
      if (value < quota) {
        out.add((type: 'spider', hp: quota - value)); // PV restants
        continue;
      }
      var run = 0;
      var d = date;
      while (_habitValueOnGarden(a.id, d) >= quota) {
        run++;
        if (run >= 2) break;
        d = d.subtract(const Duration(days: 1));
      }
      out.add((type: run >= 2 ? 'flame' : 'leaf', hp: 0));
    }
    return out;
  }

  /// CHARGEUR de défense d'une routine = ses complétions sur les 7 DERNIERS JOURS
  /// GLISSANTS (0..7), même fenêtre que les tokens du jardin. Ce que tu as tenu te
  /// défend, même si le streak du jour est cassé (le coussin).
  int routineDefenseCharger(String routineId) {
    Activity? a;
    for (final x in state.activeActivities) {
      if (x.id == routineId) {
        a = x;
        break;
      }
    }
    if (a == null || !a.isHabit) return 0;
    final quota = dayQuotaFor(a);
    if (quota <= 0) return 0;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    var done = 0;
    for (var i = 0; i < 7; i++) {
      final date = today.subtract(Duration(days: 6 - i));
      if (habitValueOn(a.id, date) >= quota) done++;
    }
    return done;
  }

  /// ATTAQUE d'un domaine = RÉGRESSION N-2 → N-1 (en jours-complétions, ≥ 0) :
  /// ce que tu as lâché d'une semaine complète à l'autre. 0 = pas de chute = pas
  /// d'attaque. Même unité que la défense (jours) → équilibré.
  int domainRegression(String domainId) {
    final (lastMon, prevMon) = _completeWeekMondays();
    var last = 0, prev = 0;
    for (final a in state.activeActivities) {
      if (!a.isHabit || a.domainId != domainId) continue;
      last += _routineWeekDone(a, lastMon);
      prev += _routineWeekDone(a, prevMon);
    }
    final drop = prev - last;
    return drop < 0 ? 0 : drop;
  }

  /// Deck d'assaut amorcé pour reconquérir la grotte du domaine `domainId` =
  /// UNIQUEMENT la masse capturée de CE domaine (petit deck spécifique, cloisonné).
  /// Vide si rien capturé dans ce domaine depuis le reset → on FARME les nuisibles
  /// du domaine à l'intérieur pour le gonfler (pas de fallback global qui gonflerait
  /// artificiellement le deck — cf. north star pilier 5, deck cloisonné par domaine).
  int reconquestDeckForDomain(String domainId) => lifetimeMasseForDomain(domainId);

  /// Reset du deck d'invasion : pose la date de reset à AUJOURD'HUI (les captures
  /// antérieures ne comptent plus → deck à zéro, réversible, sans toucher à
  /// l'historique réel) et remet à zéro les captures de chasse (`pestKills`).
  void resetDeck(FirestoreSync sync) {
    final today = yyyymmdd(DateTime.now());
    state.deckResetYmd = today;
    state.pestKills.clear();
    sync.setDeckReset(today, state.pestKills);
    bumpRev();
  }

  /// Masse gagnée aujourd'hui (captures du jour dans la fenêtre).
  int get battleMasseEarnedToday {
    final today = yyyymmdd(DateTime.now());
    return _windowCaptures()
        .where((c) => c.ymd == today)
        .fold(0, (s, c) => s + c.effort);
  }

  /// Masse d'armée disponible (gagnée sur 7 j − dépensée), plancher 0.
  int get battleMasseAvailable {
    final a = battleMasseEarned - state.battleMasseUsed;
    return a < 0 ? 0 : a;
  }

  /// Deck par CAPTURE : chaque routine complétée sur la fenêtre est décomposée
  /// « telle quelle » (le plus gros d'abord) et accumulée par type. Conserve la
  /// variété : 3 petites routines = 3 araignées ; une routine de 20 min = 🐍+🕷️.
  ({int serpents, int scorpions, int spiders}) battleDeckByCapture() {
    var serp = 0, scor = 0, spid = 0;
    for (final c in _windowCaptures()) {
      var m = c.effort;
      serp += m ~/ GoldEconomy.masseSerpent;
      m %= GoldEconomy.masseSerpent;
      scor += m ~/ GoldEconomy.masseScorpion;
      m %= GoldEconomy.masseScorpion;
      spid += m ~/ GoldEconomy.masseSpider;
    }
    return (serpents: serp, scorpions: scor, spiders: spid);
  }

  /// Deck d'invasion LIFETIME par palier (source craftable des rouges). Même
  /// décomposition que le deck Bataille, mais sur TOUT l'historique. Indépendant
  /// de la masse Bataille : crafter un rouge ne dépense PAS ton deck défensif.
  ({int serpents, int scorpions, int spiders}) invasionDeckByCapture() {
    var serp = 0, scor = 0, spid = 0;
    for (final c in _allCaptures()) {
      var m = c.effort;
      serp += m ~/ GoldEconomy.masseSerpent;
      m %= GoldEconomy.masseSerpent;
      scor += m ~/ GoldEconomy.masseScorpion;
      m %= GoldEconomy.masseScorpion;
      spid += m ~/ GoldEconomy.masseSpider;
    }
    return (serpents: serp, scorpions: scor, spiders: spid);
  }

  /// Nuisibles d'un palier encore disponibles pour crafter/nourrir des rouges =
  /// deck lifetime − déjà dépensés au craft (`craftSpent`, par palier).
  int redCraftable(String tier) {
    final deck = invasionDeckByCapture();
    final have = switch (tier) {
      'serpent' => deck.serpents,
      'scorpion' => deck.scorpions,
      _ => deck.spiders,
    };
    final spent = state.craftSpent[tier] ?? 0;
    final damaged = state.deckDamage[tier] ?? 0; // grignoté par un boss franchi
    final a = have - spent - damaged;
    return a < 0 ? 0 : a;
  }

  /// Enregistre des dégâts au deck vert (boss PvE ayant atteint le cœur). Plafonné
  /// par palier (`bossDeckDamageCap`) et borné au deck restant → toujours
  /// RÉCUPÉRABLE en refarmant. Persiste. Trust-client v1.
  void applyBossDeckDamage(Map<String, int> byTier, FirestoreSync sync) {
    var changed = false;
    byTier.forEach((tier, n) {
      if (n <= 0) return;
      final capped =
          n > GoldEconomy.bossDeckDamageCap ? GoldEconomy.bossDeckDamageCap : n;
      final avail = redCraftable(tier); // tient déjà compte des dégâts existants
      final eff = capped > avail ? avail : capped;
      if (eff <= 0) return;
      state.deckDamage[tier] = (state.deckDamage[tier] ?? 0) + eff;
      changed = true;
    });
    if (changed) {
      sync.setDeckDamage(state.deckDamage);
      onChange();
    }
  }

  /// Dépense de la masse pour déployer un palier. false si masse insuffisante.
  /// Seul `battleMasseUsed` est stocké (le gagné est dérivé de habitProgress).
  bool spendBattleMasse(String tier, FirestoreSync sync) {
    final cost = GoldEconomy.masseCost(tier);
    if (battleMasseAvailable < cost) return false;
    state.battleMasseUsed += cost;
    sync.setBattleMasseUsed(state.battleMasseUsed);
    onChange();
    return true;
  }

  /// Revend 1 arme contre de l'or (liquidation du surplus). Incrémente le
  /// compteur de dépense (l'arme part de l'arsenal) + crédite l'or.
  bool sellWeapon(String key, FirestoreSync sync) {
    if (weaponsAvailable(key) <= 0) return false;
    state.weaponsSpent[key] = (state.weaponsSpent[key] ?? 0) + 1;
    sync.setCombatStats(state.weaponsSpent, state.pestKills);
    applyGold(sync, GoldEconomy.weaponSellPrice,
        category: 'gain', reasonCode: 'weapon_sell', label: 'Vente d\'arme');
    onChange();
    return true;
  }

  bool isHeartExposed(String type, String itemId) =>
      isEngaged(type, itemId) && sbiresLeft(type, itemId) <= 0;

  void killSbire(String type, String itemId, FirestoreSync sync) {
    final prefix = '$type~$itemId~';
    final idx =
        state.engagedEnemies.indexWhere((k) => k.startsWith(prefix));
    if (idx < 0) return;
    final cur = int.tryParse(
            state.engagedEnemies[idx].substring(prefix.length)) ??
        0;
    if (cur <= 0) return;
    state.engagedEnemies[idx] = '$prefix${cur - 1}';
    sync.setEngagedEnemies(state.engagedEnemies);
    onChange();
  }

  void addWeaponPickup(String key, int count, FirestoreSync sync) {
    state.weaponPickups[key] = (state.weaponPickups[key] ?? 0) + count;
    sync.setWeaponPickups(state.weaponPickups);
    onChange();
  }

  bool isEngaged(String type, String itemId) {
    final prefix = '$type~$itemId~';
    final exact = '$type~$itemId';
    return state.engagedEnemies.any((k) => k == exact || k.startsWith(prefix));
  }

  int engageCost(String type) => GoldEconomy.engageCost;

  bool canEngage(String type) =>
      weaponsAvailable(GoldEconomy.minionWeaponForPest(type)) >= engageCost(type);

  /// Engage (épingle) un ennemi : dépense des armes globales adaptées (arme sbires),
  /// l'ajoute aux combats en cours avec le compte de sbires encodé. false si pas
  /// assez d'armes ou déjà engagé.
  bool engageEnemy(String type, String itemId, FirestoreSync sync) {
    if (isEngaged(type, itemId)) return false;
    final w = GoldEconomy.minionWeaponForPest(type);
    if (weaponsAvailable(w) < GoldEconomy.engageCost) return false;
    state.weaponsSpent[w] = (state.weaponsSpent[w] ?? 0) + GoldEconomy.engageCost;
    final sbires = enemySbires(type, itemId);
    state.engagedEnemies.add('$type~$itemId~$sbires');
    sync.setCombatStats(state.weaponsSpent, state.pestKills);
    sync.setEngagedEnemies(state.engagedEnemies);
    onChange();
    return true;
  }

  void unengageEnemy(String type, String itemId, FirestoreSync sync) {
    final prefix = '$type~$itemId~';
    final exact = '$type~$itemId';
    final before = state.engagedEnemies.length;
    state.engagedEnemies.removeWhere((k) => k == exact || k.startsWith(prefix));
    if (state.engagedEnemies.length != before) {
      sync.setEngagedEnemies(state.engagedEnemies);
      onChange();
    }
  }

  /// Combats en cours = ennemis engagés encore vivants (PV>0). PUR (pour le build).
  List<({String type, String id, int hp, int maxHp})> combatsInProgress() {
    final out = <({String type, String id, int hp, int maxHp})>[];
    for (final key in state.engagedEnemies) {
      final i = key.indexOf('~');
      if (i < 0) continue;
      final type = key.substring(0, i);
      final rest = key.substring(i + 1);
      // nouveau format: id~sbiresLeft — on prend tout avant le dernier ~
      final lastTilde = rest.lastIndexOf('~');
      final id = lastTilde >= 0 ? rest.substring(0, lastTilde) : rest;
      final hp = enemyHp(type, id);
      if (hp <= 0) continue;
      out.add((type: type, id: id, hp: hp, maxHp: enemyMaxHp(type, id)));
    }
    out.sort((a, b) => a.hp.compareTo(b.hp));
    return out;
  }

  /// Purge les combats engagés rattrapés (PV 0) — à appeler hors build.
  void pruneEngaged(FirestoreSync sync) {
    final dead = <String>[];
    for (final key in state.engagedEnemies) {
      final i = key.indexOf('~');
      if (i < 0) { dead.add(key); continue; }
      final rest = key.substring(i + 1);
      final lastTilde = rest.lastIndexOf('~');
      final id = lastTilde >= 0 ? rest.substring(0, lastTilde) : rest;
      final type = key.substring(0, i);
      if (enemyHp(type, id) <= 0) dead.add(key);
    }
    if (dead.isNotEmpty) {
      state.engagedEnemies.removeWhere(dead.contains);
      sync.setEngagedEnemies(state.engagedEnemies);
    }
  }

  /// Domaine de l'item d'un ennemi (pour colorer sa case).
  String? enemyDomainId(String type, String itemId) {
    if (type == 'snake') {
      for (final p in currentProjects) {
        for (final t in p.tasks) {
          if (t.id == itemId) return p.domainId;
        }
      }
      return null;
    }
    for (final x in state.activities) {
      if (x.id == itemId) return x.domainId;
    }
    return null;
  }

  /// Une routine est « lancée » si elle a été complétée au moins une fois ≤ d.
  bool _routineLaunchedBy(Activity a, DateTime d) {
    final ymdD = yyyymmdd(d);
    final tgt = activeHabitTarget(a);
    for (final hp in state.habitProgress) {
      if (hp.activityId != a.id) continue;
      if (hp.yyyymmdd.compareTo(ymdD) <= 0 && hp.value >= tgt) return true;
    }
    return false;
  }
}
