part of '../gold_engine.dart';

extension GoldEngineWeapons on AppLogic {
  // ── Armes : modèle STOCK / MUNITIONS ────────────────────────────────────────
  // L'arme se GAGNE par la productivité (dérivé des données) et se DÉPENSE au
  // kill. Permet de préparer un arsenal et d'enchaîner les captures en chasse.
  String weaponEmoji(String key) =>
      key == 'epee' ? '🗡️' : (key == 'arc' ? '🏹' : '🔪');
  String weaponName(String key) =>
      key == 'epee' ? 'épée' : (key == 'arc' ? 'arc' : 'couteau');

  /// Armes GAGNÉES (cumul) : épée = total des actions de projet cochées ;
  /// arc = heures de temps loggué (1 h = 1 flèche) ; sandale = chaque jour où
  /// une routine quotidienne a atteint sa cible.
  int weaponsEarned(String key) {
    if (key == 'epee') {
      // 1 épée = 1 action de tâche Gantt réalisée. Dérivé des vraies données
      // (peu importe l'écran qui coche) et conservé même tâche/projet terminés
      // — seul le mode planification (draft) est hors économie.
      var n = 0;
      for (final p in currentProjects) {
        if (p.status == 'draft') continue;
        for (final t in p.tasks) {
          if (t.status == 'skipped') continue;
          for (final act in t.actions) {
            if (act.done) n++;
          }
        }
      }
      return n;
    }
    if (key == 'arc') {
      final mins =
          state.sessions.fold<int>(0, (s, x) => s + x.duration.inMinutes);
      return mins ~/ GoldEconomy.minutesPerArrow;
    }
    final targets = <String, int>{};
    for (final a in state.activities) {
      if (a.isHabit) targets[a.id] = activeHabitTarget(a);
    }
    var n = 0;
    for (final hp in state.habitProgress) {
      final tgt = targets[hp.activityId];
      if (tgt != null && tgt > 0 && hp.value >= tgt) n++;
    }
    return n;
  }

  /// Armes DISPONIBLES = gagnées + pickups − dépensées (plancher 0, plus de
  /// plafond : on accumule un vrai arsenal qui reflète toute la productivité).
  int weaponsAvailable(String key) {
    final pickups = state.weaponPickups[key] ?? 0;
    final a = weaponsEarned(key) + pickups - (state.weaponsSpent[key] ?? 0);
    return a < 0 ? 0 : a;
  }

  int pestKillCount(String type) => state.pestKills[type] ?? 0;

  /// Progression d'une recette : (accompli, total) sur l'ensemble des types.
  ({int done, int total}) recipeProgress(Map<String, int> recipe) {
    var done = 0, total = 0;
    recipe.forEach((t, n) {
      total += n;
      final k = state.pestKills[t] ?? 0;
      done += k < n ? k : n;
    });
    return (done: done, total: total);
  }

  /// Enregistre une capture : dépense l'arme requise + incrémente le compteur,
  /// débloque les recettes satisfaites, puis persiste. Renvoie les créatures
  /// nouvellement débloquées (pour les célébrer).
  List<({String id, String emoji, String name})> recordKill(
      String type, FirestoreSync sync, {bool spendWeapon = true}) {
    // Kill « vrai item » (modèle PV) : le travail réel EST l'attaque → pas d'arme
    // dépensée. Kill générique de chasse : on consomme une munition.
    if (spendWeapon) {
      final w = GoldEconomy.weaponForPest(type);
      state.weaponsSpent[w] = (state.weaponsSpent[w] ?? 0) + 1;
    }
    state.pestKills[type] = (state.pestKills[type] ?? 0) + 1;

    final unlocked = <({String id, String emoji, String name})>[];
    for (final r in GoldEconomy.bestiaryRecipes) {
      if (state.collection.contains(r.id)) continue;
      var ok = true;
      r.recipe.forEach((t, n) {
        if ((state.pestKills[t] ?? 0) < n) ok = false;
      });
      if (ok) {
        state.collection.add(r.id);
        state.collectionMeta[r.id] =
            '${yyyymmdd(DateTime.now())}|recette de chasse';
        unlocked.add((id: r.id, emoji: r.emoji, name: r.name));
      }
    }

    sync.setCombatStats(state.weaponsSpent, state.pestKills);
    if (unlocked.isNotEmpty) {
      sync.setCollectionMeta(state.collectionMeta);
      for (final u in unlocked) {
        sync.expeditionWrite(collectionAdd: u.id);
      }
    }
    return unlocked;
  }

  // ── Combat « vrai backlog » : ennemi = item réel, PV = travail restant ──────
  // type ↔ item : spider=routine (coups), scorpion=activité-temps (5 min/PV),
  // snake=tâche (actions). PV calculés EN DIRECT → faire le vrai travail blesse.

  /// PV d'un ennemi lié à l'item [itemId]. 0 = item rattrapé (l'ennemi meurt).
  int enemyHp(String type, String itemId) {
    final today = DateTime.now();
    if (type == 'snake') {
      for (final p in currentProjects) {
        for (final t in p.tasks) {
          if (t.id == itemId) {
            return t.actions.where((a) => !a.done).length;
          }
        }
      }
      return 0;
    }
    Activity? a;
    for (final x in state.activities) {
      if (x.id == itemId) {
        a = x;
        break;
      }
    }
    if (a == null) return 0;
    if (type == 'spider') {
      // Routine MINUTÉE (timer + activité liée) → PV en chunks de 5 min (on
      // chipote au minuteur). Sinon → coups restants (cible − fait).
      final tm = a.timerMin ?? 0;
      final lid = (a.linkedActivityId ?? '').trim();
      if (tm > 0 && lid.isNotEmpty) {
        if (habitValueOn(a.id, today) >= activeHabitTarget(a)) return 0;
        final full = (tm / 5).ceil();
        final done = _activityLoggedMinutes(lid, yyyymmdd(today)) ~/ 5;
        final hp = full - done;
        return hp < 0 ? 0 : hp;
      }
      final hp = activeHabitTarget(a) - habitValueOn(a.id, today);
      return hp < 0 ? 0 : hp;
    }
    // scorpion : retard de temps du jour / 5 min (arrondi haut).
    final retard = a.goalMin - _activityLoggedMinutes(a.id, yyyymmdd(today));
    return retard <= 0 ? 0 : (retard / 5).ceil();
  }

  /// Nom lisible de l'item d'un ennemi (écran de combat).
  String enemyItemName(String type, String itemId) {
    if (type == 'snake') {
      for (final p in currentProjects) {
        for (final t in p.tasks) {
          if (t.id == itemId) return t.title;
        }
      }
      return 'Tâche';
    }
    for (final x in state.activities) {
      if (x.id == itemId) return x.name;
    }
    return type == 'spider' ? 'Routine' : 'Activité';
  }

  /// Vrais items négligés à transformer en nuisibles, triés par PV décroissant
  /// (les plus nécessiteux d'abord). [(type, id, hp)].
  List<({String type, String id, int hp})> backlogEnemies() {
    final out = <({String type, String id, int hp})>[];
    final nowSnooze = DateTime.now();
    for (final a in state.activeActivities) {
      // Activité DÉSACTIVÉE jusqu'à une date (snooze) → aucun nuisible.
      if (isActivitySnoozed(a.id, nowSnooze)) continue;
      if (a.isHabit) {
        // Routine déjà planifiée dans les 30 j à venir → pas d'ennemi (elle a
        // déjà sa place dans le programme du jour).
        if (plannedActivityIds.contains(a.id)) continue;
        final hp = enemyHp('spider', a.id);
        if (hp > 0) out.add((type: 'spider', id: a.id, hp: hp));
      } else if (a.goalMin > 0) {
        final hp = enemyHp('scorpion', a.id);
        if (hp > 0) out.add((type: 'scorpion', id: a.id, hp: hp));
      }
    }
    final now = DateTime.now();
    final todayYmd = DateTime(now.year, now.month, now.day);
    for (final p in currentProjects) {
      if (p.status == 'archived' || p.status == 'done') continue;
      for (final t in p.tasks) {
        if (t.status == 'done' || t.status == 'skipped') continue;
        // Tâche = serpent dans le jardin SEULEMENT si en retard. Échéance
        // EFFECTIVE : celle de la tâche, sinon celle de sa phase, sinon celle du
        // projet (les tâches Gantt portent souvent la date sur la phase).
        DateTime? due = t.endDate;
        if (due == null && t.phaseId != null) {
          for (final ph in p.phases) {
            if (ph.id == t.phaseId) {
              due = ph.endDate;
              break;
            }
          }
        }
        due ??= p.endDate;
        if (due == null) continue;
        if (!DateTime(due.year, due.month, due.day).isBefore(todayYmd)) continue;
        final hp = enemyHp('snake', t.id);
        if (hp > 0) out.add((type: 'snake', id: t.id, hp: hp));
      }
    }
    out.sort((a, b) => b.hp.compareTo(a.hp));
    return out;
  }

  /// PV « plein » d'un item (cible totale) — pour la jauge de vie de la case.
  int enemyMaxHp(String type, String itemId) {
    if (type == 'snake') {
      for (final p in currentProjects) {
        for (final t in p.tasks) {
          if (t.id == itemId) return t.actions.isEmpty ? 1 : t.actions.length;
        }
      }
      return 1;
    }
    Activity? a;
    for (final x in state.activities) {
      if (x.id == itemId) {
        a = x;
        break;
      }
    }
    if (a == null) return 1;
    if (type == 'spider') {
      final tm = a.timerMin ?? 0;
      final lid = (a.linkedActivityId ?? '').trim();
      if (tm > 0 && lid.isNotEmpty) {
        final m = (tm / 5).ceil();
        return m < 1 ? 1 : m;
      }
      final tgt = activeHabitTarget(a);
      return tgt < 1 ? 1 : tgt;
    }
    final m = (a.goalMin / 5).ceil();
    return m < 1 ? 1 : m;
  }

  // ── Gel / bouclier / boost : compteurs actifs et prix dynamiques ─────────

  /// Nombre d'entrées gel dont la date est >= aujourd'hui (= gels encore actifs).
  int activeGelCount() {
    final today = yyyymmdd(DateTime.now());
    return state.goldGelDays.where((e) => e.compareTo(e.split('_').last) >= 0 && e.split('_').last.compareTo(today) >= 0).length;
  }

  /// Jours de gel restants pour une routine donnée (date >= aujourd'hui).
  int routineFrozenDaysLeft(String activityId) {
    final today = yyyymmdd(DateTime.now());
    return state.goldGelDays.where((e) {
      final parts = e.split('_');
      if (parts.length < 2) return false;
      final id = parts.sublist(0, parts.length - 1).join('_');
      final ymd = parts.last;
      return id == activityId && ymd.compareTo(today) >= 0;
    }).length;
  }

  bool isRoutineFrozenToday(String activityId) {
    final today = yyyymmdd(DateTime.now());
    return state.goldGelDays.contains('${activityId}_$today');
  }

  /// Prix dynamique du gel : augmente de shopGel par gel actif déjà en place.
  int gelPriceDynamic() {
    final active = activeGelCount();
    return GoldEconomy.shopGel * (1 + active);
  }

  /// Prix dynamique du bouclier.
  int shieldPriceDynamic() {
    final today = yyyymmdd(DateTime.now());
    final active = state.goldTaskShieldDays
        .where((e) => e.split('_').last.compareTo(today) >= 0)
        .length;
    return GoldEconomy.shopShield * (1 + active ~/ GoldEconomy.shieldDaysPerUse);
  }

  /// Prix dynamique du boost.
  int boostPriceDynamic() {
    final today = yyyymmdd(DateTime.now());
    final active = state.goldBoostDays.where((d) => d.compareTo(today) >= 0).length;
    return GoldEconomy.shopBoost * (1 + active ~/ GoldEconomy.boostDaysPerUse);
  }
}
