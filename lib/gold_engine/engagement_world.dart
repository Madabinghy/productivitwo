part of '../gold_engine.dart';

extension GoldEngineEngagement on AppLogic {
  // ── Engagement de combat : armes globales → épingler dans Combats en cours ──

  /// Nombre de sbires restants pour un ennemi engagé.
  /// Format clé engagée : "type~id~sbiresLeft"
  int sbiresLeft(String type, String itemId) {
    final prefix = '$type~$itemId~';
    for (final k in state.engagedEnemies) {
      if (k.startsWith(prefix)) {
        return int.tryParse(k.substring(prefix.length)) ?? 0;
      }
    }
    return 0;
  }

  /// Nombre de sbires d'un ennemi = SÉVÉRITÉ de la négligence (≥1, plafonné à
  /// [GoldEconomy.maxSbires]) → plus tu as laissé pourrir, plus la garde est
  /// épaisse, plus ça coûte d'armes à percer. Le vrai travail réduit le déficit
  /// (donc la garde) en parallèle.
  /// - routine 🕷️ / activité 🦂 : jours en déficit sur la fenêtre de négligence
  /// - tâche 🐍 : actions non faites accumulées
  int enemySbires(String type, String itemId) {
    const cap = GoldEconomy.maxSbires;
    if (type == 'snake') {
      return enemyHp('snake', itemId).clamp(1, cap);
    }
    Activity? found;
    for (final x in state.activities) {
      if (x.id == itemId) {
        found = x;
        break;
      }
    }
    if (found == null) return 1;
    final a = found;
    final base = DateTime.now();
    final today = DateTime(base.year, base.month, base.day);
    var missed = 0;
    for (var i = 0; i < GoldEconomy.neglectWindowDays; i++) {
      final d = today.subtract(Duration(days: i));
      if (type == 'spider') {
        final tgt = activeHabitTarget(a);
        if (tgt > 0 && habitValueOn(a.id, d) < tgt) missed++;
      } else {
        // scorpion
        if (a.goalMin > 0 && _loggedMinutesOnDay(a.id, yyyymmdd(d)) < a.goalMin) {
          missed++;
        }
      }
    }
    return missed.clamp(1, cap);
  }

  // ── Social « Le Monde » : jetons de relâche ─────────────────────────────────
  /// Total des captures (kills de backlog, tous types).
  int get totalCaptures =>
      state.pestKills.values.fold(0, (s, v) => s + v);

  /// Jetons de relâche gagnés à vie (1 par tranche de captures).
  int get releaseTokensEarned =>
      totalCaptures ~/ GoldEconomy.capturesPerReleaseToken;

  /// Jetons de relâche disponibles (gagnés − déjà consommés).
  int get releaseTokensAvailable {
    final a = releaseTokensEarned - state.releaseTokensUsed;
    return a < 0 ? 0 : a;
  }

  /// Consomme 1 jeton (appelé par une relâche réussie). false si aucun dispo.
  bool consumeReleaseToken(FirestoreSync sync) {
    if (releaseTokensAvailable <= 0) return false;
    state.releaseTokensUsed += 1;
    sync.setReleaseTokensUsed(state.releaseTokensUsed);
    onChange();
    return true;
  }

  // ── Invasion / Territoires : arsenal de nuisibles rouges ────────────────────
  /// Rouges DISPONIBLES (non déployés) d'un palier.
  int redCount(String tier) => state.redRoster[tier] ?? 0;

  /// Puissance de deck offensive = somme pondérée des rouges dispo (rang ladder).
  int get invasionDeckPower {
    var p = 0;
    state.redRoster.forEach((tier, n) => p += GoldEconomy.redPower(tier) * n);
    return p;
  }

  /// Crafte 1 rouge d'un palier en sacrifiant `redCraftCost` nuisibles du MÊME
  /// palier (deck lifetime). false si nuisibles insuffisants. Trust-client v1.
  bool craftRed(String tier, FirestoreSync sync) {
    if (redCraftable(tier) < GoldEconomy.redCraftCost) return false;
    state.craftSpent[tier] =
        (state.craftSpent[tier] ?? 0) + GoldEconomy.redCraftCost;
    state.redRoster[tier] = (state.redRoster[tier] ?? 0) + 1;
    sync.setInvasionArsenal(state.redRoster, state.craftSpent);
    onChange();
    return true;
  }

  /// Nourrit un rouge pour le faire monter d'un cran : consomme 1 rouge du palier
  /// `fromTier` + `redUpgradeCost` nuisibles du MÊME palier. false si impossible
  /// (palier max, aucun rouge, nuisibles insuffisants).
  bool upgradeRed(String fromTier, FirestoreSync sync) {
    final to = GoldEconomy.tierAbove(fromTier);
    if (to == null) return false;
    if (redCount(fromTier) <= 0) return false;
    if (redCraftable(fromTier) < GoldEconomy.redUpgradeCost) return false;
    state.craftSpent[fromTier] =
        (state.craftSpent[fromTier] ?? 0) + GoldEconomy.redUpgradeCost;
    state.redRoster[fromTier] = (state.redRoster[fromTier] ?? 0) - 1;
    state.redRoster[to] = (state.redRoster[to] ?? 0) + 1;
    sync.setInvasionArsenal(state.redRoster, state.craftSpent);
    onChange();
    return true;
  }

  /// Consomme 1 rouge (ticket d'invasion) du roster DISPONIBLE au lancement d'une
  /// invasion : le ticket est immobilisé → sort de la puissance de deck (mécanique
  /// d'auto-équilibrage #6). À appeler APRÈS le succès serveur de `releaseInvasion`.
  /// Le retour downgradé au repel arrive plus tard par le ledger `red_returns`.
  bool releaseRed(String tier, FirestoreSync sync) {
    if (redCount(tier) <= 0) return false;
    state.redRoster[tier] = redCount(tier) - 1;
    sync.setInvasionArsenal(state.redRoster, state.craftSpent);
    onChange();
    return true;
  }

  /// Combat « Le Monde » : dépense 1 arme pour frapper un nuisible public
  /// (1 arme = 1 PV). Sink social pur — pas de butin local, pas de capture.
  /// `key` ∈ {couteau, arc, epee}. false si l'arsenal est vide.
  bool spendWeaponForWorld(String key, FirestoreSync sync) {
    if (weaponsAvailable(key) <= 0) return false;
    state.weaponsSpent[key] = (state.weaponsSpent[key] ?? 0) + 1;
    sync.setCombatStats(state.weaponsSpent, state.pestKills);
    onChange();
    return true;
  }

  // ── Bataille de nuisibles : masse d'armée ───────────────────────────────────
  /// Effort-minutes estimé d'une capture de routine : minuteur dédié, sinon
  /// objectif de l'activité-temps liée, sinon plancher (routine sans temps).
  int routineEffortMinutes(Activity a) {
    if (a.timerMin != null && a.timerMin! > 0) return a.timerMin!;
    final linked = a.linkedActivityId;
    if (linked != null) {
      for (final x in state.activities) {
        if (x.id == linked && x.goalMin > 0) return x.goalMin;
      }
    }
    return GoldEconomy.masseFloor;
  }

  /// Les N derniers jours (fenêtre glissante du deck) en `yyyymmdd`.
  Set<String> _recentDays() {
    final now = DateTime.now();
    return {
      for (int i = 0; i < GoldEconomy.battleDeckWindowDays; i++)
        yyyymmdd(now.subtract(Duration(days: i)))
    };
  }

  /// Captures de routine de la FENÊTRE (7 j glissants) : une entrée par
  /// (routine, jour complété) avec son effort en masse. DÉRIVÉ des données
  /// réelles → aucun historique stocké, un nuisible « vit » 7 j puis sort.
  /// « Complétée un jour » = MÊME condition que le combat : tick habit ≥ cible
  /// OU (routine minutée) temps loggué sur l'activité liée ≥ timerMin ce jour.
  List<({String ymd, int effort})> _windowCaptures() =>
      _capturesForDays(_recentDays());

  /// Toutes les captures de routine de l'historique chargé (AUCUNE fenêtre) —
  /// source LIFETIME de l'arsenal d'invasion (les rouges sont permanents, donc
  /// alimentés par une source permanente, pas par la fenêtre 7 j de la Bataille).
  List<({String ymd, int effort})> _allCaptures() => _capturesForDays(null);

  /// Cœur commun fenêtre/lifetime : une entrée par (routine × jour complété) avec
  /// son effort en masse. `days` = filtre de jours (null = tout l'historique).
  List<({String ymd, int effort})> _capturesForDays(Set<String>? days,
      {String? domainId}) {
    final reset = state.deckResetYmd;
    final linkedIds = <String>{};
    for (final a in state.activities) {
      if (a.isHabit && (a.timerMin ?? 0) > 0) {
        final lid = (a.linkedActivityId ?? '').trim();
        if (lid.isNotEmpty) linkedIds.add(lid);
      }
    }
    final minByActDay = <String, Map<String, int>>{};
    if (linkedIds.isNotEmpty) {
      for (final s in state.sessions) {
        if (!linkedIds.contains(s.activityId)) continue;
        final ymd = yyyymmdd(s.startAt);
        if (days != null && !days.contains(ymd)) continue;
        (minByActDay[s.activityId] ??= {}).update(
            ymd, (v) => v + s.duration.inMinutes,
            ifAbsent: () => s.duration.inMinutes);
      }
    }
    final hpByAct = <String, List<HabitProgress>>{};
    for (final hp in state.habitProgress) {
      if (days != null && !days.contains(hp.yyyymmdd)) continue;
      (hpByAct[hp.activityId] ??= []).add(hp);
    }
    final out = <({String ymd, int effort})>[];
    for (final a in state.activities) {
      if (!a.isHabit) continue;
      if (domainId != null && a.domainId != domainId) continue;
      final target = activeHabitTarget(a);
      if (target <= 0) continue;
      final effort =
          GoldEconomy.battleMasseForMinutes(routineEffortMinutes(a));
      final done = <String>{};
      for (final hp in (hpByAct[a.id] ?? const <HabitProgress>[])) {
        if (hp.value >= target) done.add(hp.yyyymmdd);
      }
      final tm = a.timerMin ?? 0;
      final lid = (a.linkedActivityId ?? '').trim();
      if (tm > 0 && lid.isNotEmpty) {
        minByActDay[lid]?.forEach((ymd, mins) {
          if (mins >= tm) done.add(ymd);
        });
      }
      for (final ymd in done) {
        // Deck propre : on ignore les captures antérieures à la date de reset.
        if (reset.isNotEmpty && ymd.compareTo(reset) < 0) continue;
        out.add((ymd: ymd, effort: effort));
      }
    }
    return out;
  }

  /// Masse d'armée gagnée sur la fenêtre 7 j.
  int get battleMasseEarned =>
      _windowCaptures().fold(0, (s, c) => s + c.effort);

  /// Taille du DECK de défense = LIFETIME (Σ effort de routine cumulé, SANS fenêtre
  /// 7 j) — même source que le Dock vert. La défense de grotte engage une COPIE de ce
  /// deck qui se VIDE pendant la bataille (finie par combat → la taille compte), sans
  /// rien retirer du compte (le deck reste). Cf `_BotInvasionCtrl.defenseFromDeck`.
  int get lifetimeBattleMasse =>
      _allCaptures().fold(0, (s, c) => s + c.effort);

  /// Masse lifetime des captures de routines d'UN domaine (dérivée de
  /// `activity.domainId`, après `deckResetYmd`). Sert à amorcer le deck d'assaut
  /// de reconquête d'une grotte = ce domaine précis (« petit deck spécifique »).
  int lifetimeMasseForDomain(String domainId) =>
      _capturesForDays(null, domainId: domainId).fold(0, (s, c) => s + c.effort);

  // ── DÉFENSE DE DOMAINE (semaine passée) ───────────────────────────────────
  // Lundi de la dernière semaine COMPLÈTE (N-1) et de la précédente (N-2).
  (DateTime, DateTime) _completeWeekMondays() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final thisMon = today.subtract(Duration(days: today.weekday - 1));
    final lastMon = thisMon.subtract(const Duration(days: 7));
    return (lastMon, lastMon.subtract(const Duration(days: 7)));
  }

  // Jours (0..7) où la routine a atteint son quota sur la semaine du `monday`.
  int _routineWeekDone(Activity a, DateTime monday) {
    final quota = dayQuotaFor(a);
    if (quota <= 0) return 0;
    var n = 0;
    for (var i = 0; i < 7; i++) {
      if (habitValueOn(a.id, monday.add(Duration(days: i))) >= quota) n++;
    }
    return n;
  }
}
