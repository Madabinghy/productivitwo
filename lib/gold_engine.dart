import 'dart:convert';
import 'dart:math';

import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/expedition.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/gold_economy.dart';
import 'package:productivitwo_v1/models.dart';

export 'package:productivitwo_v1/gold_economy.dart';

/// Moteur d'Or branché sur AppLogic (côté mobile).
///
/// **Source de vérité = Firestore** : tout solde/ledger est écrit par transaction
/// (`FirestoreSync.applyGoldBatch`), partagée avec le web. Ici on fait en plus une
/// mise à jour OPTIMISTE de `state` pour un retour UI instantané ; la transaction
/// reconverge (mêmes deltas) et le prochain pull rafraîchit `state` depuis le meta.
extension GoldEngine on AppLogic {
  int get gold => state.gold;
  int get goldLifetime => state.goldLifetime;

  /// Met à jour le solde local (UI) sans toucher Firestore.
  void _localApply(int delta) {
    final next = state.gold + delta;
    state.gold = next < 0 ? 0 : next; // plancher pardonnant
    // L'XP (lifetime) est PLAFONNÉE au seuil du prochain niveau ; le surplus
    // déborde en or seul (le solde a déjà reçu le gain plein ci-dessus).
    if (delta > 0) {
      state.goldLifetime +=
          GoldEconomy.cappedLifetimeAdd(delta, state.goldLifetime, effectiveLevel());
    }
  }

  /// Ajoute des gains au lifetime en respectant le plafond du niveau (overflow
  /// → or seul). Utilisé par les sites qui créditent l'XP hors `_localApply`
  /// (ex. butin de carte d'expédition).
  void addLifetimeCapped(int gain) {
    if (gain <= 0) return;
    state.goldLifetime +=
        GoldEconomy.cappedLifetimeAdd(gain, state.goldLifetime, effectiveLevel());
  }

  /// Applique un delta d'or ponctuel (gain/perte/dépense) : optimiste local +
  /// transaction Firestore autoritative.
  void applyGold(
    FirestoreSync sync,
    int delta, {
    required String category,
    required String reasonCode,
    required String label,
    String? refType,
    String? refId,
  }) {
    if (delta == 0) return;
    final entry = GoldLedgerEntry(
      delta: delta, category: category, reasonCode: reasonCode,
      label: label, refType: refType, refId: refId,
    );
    _localApply(delta);
    onChange();
    sync.applyGold(entry); // fire-and-forget (autoritatif)
  }

  // ── Migration one-shot ──────────────────────────────────────────────────────

  /// Initialise l'or depuis l'XP dérivé actuel (le user ne perd pas sa progression).
  /// Écrit un événement « solde initial » ; curseur = aujourd'hui (pertes forward-only).
  void seedGoldIfNeeded(FirestoreSync sync) {
    if (state.goldLastProcessedDay != null) return; // déjà initialisé
    final xp = legacyDerivedXp();
    final todayYmd = yyyymmdd(DateTime.now());
    state.gold = xp;
    state.goldLifetime = xp;
    state.goldLastProcessedDay = todayYmd;
    // On accorde d'emblée le rang déjà acquis (le gate ne s'applique qu'au futur).
    state.unlockedLevel = earnedLevelFromXp();
    onChange();
    sync.setUnlockedLevel(state.unlockedLevel);
    sync.applyGoldBatch(
      [
        if (xp > 0)
          GoldLedgerEntry(
            id: 'migration_seed',
            delta: xp,
            category: 'gain',
            reasonCode: 'migration',
            label: 'Solde initial (migration XP → or)',
          ),
      ],
      newCursor: todayYmd,
    );
  }

  // ── Rattrapage idempotent ───────────────────────────────────────────────────

  DateTime _parseYmd(String ymd) => DateTime(
        int.parse(ymd.substring(0, 4)),
        int.parse(ymd.substring(4, 6)),
        int.parse(ymd.substring(6, 8)),
      );

  /// Auto-heal : un reset (ou seed) a pu poser le curseur sur un jour dont les
  /// gains n'ont JAMAIS été matérialisés (la boucle ne traite que les jours
  /// strictement après le curseur → ce jour-là est sauté à jamais).
  ///
  /// On détecte le cas via les ids déterministes du ledger : si le jour du
  /// curseur produit des gains mais qu'AUCUN de ses docs ledger n'existe, le
  /// curseur est « empoisonné » → on le recule d'un jour pour que
  /// `materializeGoldUpTo` recompte ce jour. Idempotent et sans double-comptage
  /// (un jour réellement crédité a ses docs → on ne touche à rien).
  /// À appeler AVANT `materializeGoldUpTo`.
  Future<void> healGoldCursorIfNeeded(FirestoreSync sync) async {
    final cursor = state.goldLastProcessedDay;
    if (cursor == null) return; // pas encore initialisé (le seed s'en charge)
    final cursorDay = _parseYmd(cursor);
    final gains = _collectGoldDayEntries(cursorDay)
        .where((e) => e.delta > 0)
        .toList();
    if (gains.isEmpty) return; // rien à récupérer ce jour-là
    final materialized = await sync.ledgerHasAny(gains.map((e) => e.id).toList());
    if (materialized) return; // jour déjà crédité → curseur sain
    final rewound = yyyymmdd(cursorDay.subtract(const Duration(days: 1)));
    state.goldLastProcessedDay = rewound;
    onChange();
    await sync.applyGoldBatch(const [], newCursor: rewound);
  }

  /// Crédite EN TEMPS RÉEL les gains du jour sur le SOLDE dépensable (pas l'XP,
  /// qui reste en clôture — son affichage est déjà live via le provisoire).
  /// Idempotent : `goldTodayGain` suit le flottant déjà crédité, on n'ajoute que
  /// le delta. Au changement de jour, on retire l'ancien flottant — le jour clos
  /// sera recrédité par `materializeGoldUpTo`. À appeler à l'ouverture des écrans
  /// d'or / avant une dépense / au démarrage / au resume.
  void reconcileLiveGold(FirestoreSync sync) {
    final ymd = yyyymmdd(DateTime.now());
    final earned = goldGainForDay(DateTime.now());
    // Reflet local optimiste (UI réactive) à partir du flottant LOCAL.
    var netDelta = 0;
    if (state.goldTodayGainYmd != ymd) {
      netDelta -= state.goldTodayGain; // retire le flottant de la veille
      state.goldTodayGain = 0;
      state.goldTodayGainYmd = ymd;
    }
    // N'ajoute que si earned > ce qu'on a déjà crédité (donnée fraîche seulement).
    // Si earned est inférieur (données périmées côté web p.ex.), on n'écrit rien
    // localement : la transaction AUTORITATIVE corrigera via auth.
    final toAdd = earned - state.goldTodayGain;
    if (toAdd > 0) {
      netDelta += toAdd;
      state.goldTodayGain = earned;
    }
    if (netDelta != 0) {
      state.gold += netDelta;
      if (state.gold < 0) state.gold = 0;
      onChange();
    }
    // Réconciliation AUTORITATIVE : la transaction recalcule le delta depuis le
    // flottant SERVEUR (juste en multi-appareil) et renvoie le solde vrai, qui
    // corrige le solde local si l'autre appareil avait déjà crédité le jour.
    sync.reconcileLiveGoldTx(earned, ymd).then((auth) {
      if (auth != null && auth != state.gold) {
        state.gold = auth;
        onChange();
      }
    });
  }

  /// Matérialise gains/pertes pour chaque jour CLOS non encore traité
  /// (strictement entre le curseur et aujourd'hui). Idempotent : ids déterministes
  /// + curseur → un jour n'est jamais compté deux fois.
  void materializeGoldUpTo(FirestoreSync sync, DateTime today) {
    final cursor = state.goldLastProcessedDay;
    if (cursor == null) {
      seedGoldIfNeeded(sync);
      return;
    }
    // Backfill one-shot du gate de niveau : un doc antérieur n'a pas `unlockedLevel`
    // (lu à 0) → on accorde le rang déjà acquis pour ne rétrograder personne.
    if (state.unlockedLevel == 0) {
      state.unlockedLevel = earnedLevelFromXp();
      onChange();
      sync.setUnlockedLevel(state.unlockedLevel);
    }
    final todayMid = DateTime(today.year, today.month, today.day);
    final entries = <GoldLedgerEntry>[];
    var d = _parseYmd(cursor).add(const Duration(days: 1));
    while (d.isBefore(todayMid)) {
      entries.addAll(_collectGoldDayEntries(d));
      d = d.add(const Duration(days: 1));
    }
    final newCursor = yyyymmdd(todayMid.subtract(const Duration(days: 1)));
    if (entries.isEmpty && newCursor == cursor) return;

    for (final e in entries) {
      _localApply(e.delta);
    }
    state.goldLastProcessedDay = newCursor;
    onChange();
    sync.applyGoldBatch(entries, newCursor: newCursor);
  }

  List<GoldLedgerEntry> _collectGoldDayEntries(DateTime d) {
    final ymd = yyyymmdd(d);
    final out = <GoldLedgerEntry>[];
    // Multiplicateur ×2 du jour (item boutique « boost »).
    final mult = state.goldBoostDays.contains(ymd) ? 2 : 1;
    final boostSfx = mult == 2 ? ' ×2' : '';

    // ── Gains du jour ─────────────────────────────────────────────────────────
    // Valeur du temps scalée par niveau (inclut le temps des routines minutées,
    // loggué via leur activité liée).
    final minutes = totalForDay(d).inMinutes;
    final timeGold = GoldEconomy.goldForMinutes(minutes, effectiveLevel());
    if (timeGold > 0) {
      final h = minutes ~/ 60, m = minutes % 60;
      final dur = h > 0 ? '${h}h${m > 0 ? '${m.toString().padLeft(2, '0')}' : ''}' : '${m}min';
      out.add(GoldLedgerEntry(
          id: 'time_$ymd', delta: timeGold * mult,
          category: 'gain', reasonCode: 'time_logged',
          label: '$dur de temps loggué$boostSfx'));
    }
    final challenges = state.challengeWinsByDay[ymd] ?? 0;
    if (challenges > 0) {
      out.add(GoldLedgerEntry(
          id: 'chal_$ymd', delta: challenges * GoldEconomy.challengeDone * mult,
          category: 'gain', reasonCode: 'challenge',
          label: '$challenges défi(s) relevé(s)$boostSfx'));
    }
    final gantt = state.ganttActionsByDay[ymd] ?? 0;
    if (gantt > 0) {
      out.add(GoldLedgerEntry(
          id: 'gantt_$ymd', delta: gantt * GoldEconomy.ganttAction * mult,
          category: 'gain', reasonCode: 'gantt_action',
          label: '$gantt action(s) Gantt$boostSfx'));
    }

    // ── Routines : gain (faite) ou perte (manquée, si lancée & non gelée) ──────
    for (final a in state.activeActivities.where((x) => x.isHabit)) {
      final tgt = activeHabitTarget(a);
      if (tgt <= 0) continue;
      final met = habitValueOn(a.id, d) >= tgt;
      if (met) {
        final gain = GoldEconomy.routineGain(habitStreakEndingOn(a.id, d));
        out.add(GoldLedgerEntry(
            id: 'rmet_${a.id}_$ymd', delta: gain * mult,
            category: 'gain', reasonCode: 'routine_met',
            label: 'Routine « ${a.name} » faite$boostSfx',
            refType: 'activity', refId: a.id));
      } else {
        if (state.goldGelDays.contains('${a.id}_$ymd')) continue; // jour gelé
        if (_routineLaunchedBy(a, d)) {
          out.add(GoldLedgerEntry(
              id: 'rmiss_${a.id}_$ymd', delta: -GoldEconomy.routineMissed,
              category: 'loss', reasonCode: 'routine_missed',
              label: 'Routine « ${a.name} » manquée',
              refType: 'activity', refId: a.id));
        }
      }
    }

    // ── Tâches Gantt en retard (au jour d, encore non terminées) ───────────────
    final dMid = DateTime(d.year, d.month, d.day);
    for (final p in currentProjects) {
      if (p.status != 'active') continue; // skip draft + archived (hors économie)
      for (final t in p.tasks) {
        if (t.status == 'done' || t.status == 'skipped') continue;
        // Bouclier anti-retard : ce jour-là, pas de pénalité de retard.
        if (state.goldTaskShieldDays.contains('${t.id}_$ymd')) continue;
        if (t.endDate != null && t.endDate!.isBefore(dMid)) {
          out.add(GoldLedgerEntry(
              id: 'late_${t.id}_$ymd', delta: -GoldEconomy.lateTaskPerDay,
              category: 'loss', reasonCode: 'late_task',
              label: 'Retard : « ${t.title} »',
              refType: 'task', refId: t.id));
        }
      }
    }

    // (Le drain des nuisibles est désormais HORAIRE — voir drainPestsHourly.)
    return out;
  }

  /// Progression de la « forge » d'une arme par l'ACTION RÉELLE (pas par l'or) :
  /// 🗡️ épée = 3 actions de projet cochées aujourd'hui (priorité au travail) ;
  /// 🩴 sandale = 3 routines validées aujourd'hui. Prête → on peut frapper.
  /// Compte BRUT (non plafonné) de l'effort de forge du jour pour une arme :
  /// actions de projet cochées (épée) ou routines quotidiennes accomplies
  /// (sandale). Sert de baseline « à la rencontre » du nuisible.
  int weaponRawCount(String weaponKey) {
    final today = DateTime.now();
    if (weaponKey == 'epee') {
      return state.ganttActionsByDay[yyyymmdd(today)] ?? 0;
    }
    var done = 0;
    for (final a in state.activeActivities) {
      if (!a.isHabit) continue;
      final tgt = activeHabitTarget(a);
      if (tgt > 0 && habitValueOn(a.id, today) >= tgt) done++;
    }
    return done;
  }

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
    for (final a in state.activeActivities) {
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
    for (final p in currentProjects) {
      if (p.status == 'archived' || p.status == 'done') continue;
      for (final t in p.tasks) {
        if (t.status == 'done' || t.status == 'skipped') continue;
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

  /// Jours (0-6, lun→dim) de CETTE semaine où la routine est MANQUÉE (jours passés
  /// ou aujourd'hui seulement) = les nuisibles de sa ligne dans le calendrier.
  List<int> routineMissedThisWeek(String routineId) {
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
    final mon = today.subtract(Duration(days: today.weekday - 1));
    final out = <int>[];
    for (var d = 0; d < 7; d++) {
      final date = mon.add(Duration(days: d));
      if (date.isAfter(today)) break; // jour futur → pas encore jouable
      if (habitValueOn(a.id, date) < quota) out.add(d);
    }
    return out;
  }

  /// Remplissage du CHÂTEAU d'une ligne de routine = bilan des jours PASSÉS
  /// (au-delà des 7 jours visibles, fenêtre ~3 semaines) : chaque jour manqué = +1
  /// toile, chaque jour fait RETIRE une toile d'abord (net). Net > 0 → toiles ;
  /// net < 0 (en avance) → feuilles. Plafonné à la largeur du château (9).
  ({int webs, int leaves}) routineChateauFill(String routineId) {
    Activity? a;
    for (final x in state.activeActivities) {
      if (x.id == routineId) {
        a = x;
        break;
      }
    }
    if (a == null || !a.isHabit) return (webs: 0, leaves: 0);
    final quota = dayQuotaFor(a);
    if (quota <= 0) return (webs: 0, leaves: 0);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final freq = effectiveHabitFreq(a);
    final period =
        freq == HabitFreq.weekly ? 7 : (freq == HabitFreq.monthly ? 30 : 1);
    var misses = 0, dones = 0;
    for (var k = 7; k < 28; k++) {
      final date = today.subtract(Duration(days: k));
      if (habitValueOn(a.id, date) >= quota) {
        dones++;
        continue;
      }
      if (freq == HabitFreq.daily) {
        misses++;
        continue;
      }
      // Non-daily : ce jour compte comme retard SEULEMENT si rien fait dans la
      // période (grâce). Sinon ni toile ni rien.
      var doneInPeriod = false;
      for (var p = 0; p < period; p++) {
        if (habitValueOn(a.id, date.subtract(Duration(days: p))) >= quota) {
          doneInPeriod = true;
          break;
        }
      }
      if (!doneInPeriod) misses++;
    }
    final net = misses - dones;
    final webs = net > 9 ? 9 : (net < 0 ? 0 : net);
    final leaves = net < 0 ? (-net > 9 ? 9 : -net) : 0;
    return (webs: webs, leaves: leaves);
  }

  /// PV d'une araignée de cette routine = la CIBLE quotidienne (quota) : grosse
  /// routine (boire 10 verres) = araignée à 10 PV.
  int routineTarget(String routineId) {
    for (final x in state.activeActivities) {
      if (x.id == routineId) return x.isHabit ? dayQuotaFor(x) : 0;
    }
    return 0;
  }

  // ── ACTIVITÉS TEMPS (type=time) — même tapis mais en minutes vs objectif ──
  int _minutesOnDay(String activityId, DateTime date) {
    final ds = DateTime(date.year, date.month, date.day);
    return totalForRangeByActivity(activityId, ds, ds.add(const Duration(days: 1)))
        .inMinutes;
  }

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
    final out = <({String type, int hp})>[];
    for (var i = 0; i < 7; i++) {
      final date = today.subtract(Duration(days: 6 - i));
      final mins = _minutesOnDay(a.id, date);
      if (mins < goal) {
        out.add((type: 'spider', hp: goal - mins));
        continue;
      }
      var run = 0;
      var d = date;
      while (_minutesOnDay(a.id, d) >= goal) {
        run++;
        if (run >= 2) break;
        d = d.subtract(const Duration(days: 1));
      }
      out.add((type: run >= 2 ? 'flame' : 'leaf', hp: 0));
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
      if (_minutesOnDay(a.id, today.subtract(Duration(days: k))) >= goal) {
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
        if (habitValueOn(a.id, date) >= quota) {
          out.add((type: 'leaf', hp: 0));
          continue;
        }
        var doneInPeriod = false;
        for (var k = 0; k < period; k++) {
          if (habitValueOn(a.id, date.subtract(Duration(days: k))) >= quota) {
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
      final value = habitValueOn(a.id, date);
      if (value < quota) {
        out.add((type: 'spider', hp: quota - value)); // PV restants
        continue;
      }
      var run = 0;
      var d = date;
      while (habitValueOn(a.id, d) >= quota) {
        run++;
        if (run >= 2) break;
        d = d.subtract(const Duration(days: 1));
      }
      out.add((type: run >= 2 ? 'flame' : 'leaf', hp: 0));
    }
    return out;
  }

  /// CHARGEUR de défense d'une routine = ses complétions la SEMAINE PASSÉE (0..7).
  /// Ce que tu as tenu te défend, même si le streak du jour est cassé (le coussin).
  int routineDefenseCharger(String routineId) {
    Activity? a;
    for (final x in state.activeActivities) {
      if (x.id == routineId) {
        a = x;
        break;
      }
    }
    if (a == null || !a.isHabit) return 0;
    final (lastMon, _) = _completeWeekMondays();
    return _routineWeekDone(a, lastMon);
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

  // ── Défis du donjon (préparés par Orion, auto-validés) ──────────────────────

  /// Statut auto-validé des défis Orion pour le niveau VISÉ (`effectiveLevel+1`),
  /// dérivé des vraies données (routines / tâches / temps). Aucun écrit ici.
  List<({String label, String type, int target, int progress, bool done})>
      expeditionChallengeStatuses() {
    final target = effectiveLevel() + 1;
    final out =
        <({String label, String type, int target, int progress, bool done})>[];
    for (final raw in state.expeditionChallenges) {
      Map<String, dynamic> m;
      try {
        m = jsonDecode(raw) as Map<String, dynamic>;
      } catch (_) {
        continue;
      }
      if ((m['level'] as num?)?.toInt() != target) continue;
      final type = m['type'] as String? ?? '';
      final refId = m['refId'] as String? ?? '';
      final tgt = (m['target'] as num?)?.toInt() ?? 1;
      final label = m['label'] as String? ?? '';
      final since = m['createdYmd'] as String?; // ne compte qu'À PARTIR d'ici
      switch (type) {
        case 'task':
          final done = _taskIsDone(refId);
          out.add((
            label: label, type: type,
            target: 1, progress: done ? 1 : 0, done: done,
          ));
          break;
        case 'routine':
          final p = _routineMetDays(refId, since).clamp(0, tgt);
          out.add((
            label: label, type: type,
            target: tgt, progress: p, done: p >= tgt,
          ));
          break;
        case 'time':
          final p = _activityLoggedMinutes(refId, since).clamp(0, tgt);
          out.add((
            label: label, type: type,
            target: tgt, progress: p, done: p >= tgt,
          ));
          break;
        default:
          out.add((
            label: label, type: type,
            target: 1, progress: 0, done: false,
          ));
      }
    }
    return out;
  }

  /// Génère les défis du donjon CÔTÉ APP (instantané, sans Orion) si aucun
  /// n'existe pour le niveau visé. Pioche des objectifs réels et pertinents :
  /// 1 routine active (3 j), 1 tâche ouverte à deadline proche, 30 min de temps.
  /// Cibles de départ raisonnables (réglables). À appeler à l'ouverture du donjon.
  void ensureExpeditionChallenges(FirestoreSync sync) {
    final target = effectiveLevel() + 1;
    final already = state.expeditionChallenges.any((raw) {
      try {
        return (jsonDecode(raw)['level'] as num?)?.toInt() == target;
      } catch (_) {
        return false;
      }
    });
    if (already) return;
    final built = _buildChallengesForLevel(target);
    if (built.isEmpty) return; // pas de données → l'UI invite à créer routine/tâche
    state.expeditionChallenges = built;
    onChange();
    sync.setExpeditionChallenges(built);
  }

  List<String> _buildChallengesForLevel(int target) {
    final out = <String>[];
    final days = GoldEconomy.challengeRoutineDays(target);
    final mins = GoldEconomy.challengeTimeMinutes(target);
    final created = yyyymmdd(DateTime.now()); // défi compté À PARTIR d'ici

    // 1 routine active (habitude mesurable) — difficulté scalée par niveau.
    for (final a in state.activeActivities) {
      if (a.isHabit && activeHabitTarget(a) > 0) {
        out.add(jsonEncode({
          'level': target, 'type': 'routine', 'refId': a.id, 'target': days,
          'createdYmd': created,
          'label': days == 1
              ? 'Fais la routine « ${a.name} » aujourd\'hui'
              : 'Fais la routine « ${a.name} » pendant $days jours',
        }));
        break;
      }
    }

    // 1 tâche ouverte à l'échéance la plus proche (la plus pertinente).
    ProjectTask? bestTask;
    DateTime? bestEnd;
    for (final p in currentProjects) {
      if (p.status != 'active') continue;
      for (final t in p.tasks) {
        if (t.status == 'done' || t.status == 'skipped') continue;
        final d = t.endDate;
        final better = bestTask == null ||
            (d != null && (bestEnd == null || d.isBefore(bestEnd)));
        if (better) {
          bestTask = t;
          if (d != null) bestEnd = d;
        }
      }
    }
    if (bestTask != null) {
      out.add(jsonEncode({
        'level': target, 'type': 'task', 'refId': bestTask.id, 'target': 1,
        'createdYmd': created,
        'label': 'Termine la tâche « ${bestTask.title} »',
      }));
    }

    // 1 activité temps : minutes scalées par niveau.
    for (final a in state.activeActivities) {
      if (!a.isHabit) {
        out.add(jsonEncode({
          'level': target, 'type': 'time', 'refId': a.id, 'target': mins,
          'createdYmd': created,
          'label': 'Logue $mins min sur « ${a.name} »',
        }));
        break;
      }
    }

    return out;
  }

  /// Vrai si le donjon du niveau visé a déjà été ouvert → on y entre direct
  /// (sinon on passe par l'overworld pour trouver le château).
  bool get donjonAlreadyEntered =>
      state.expeditionDonjonLevel == effectiveLevel() + 1;

  /// Tous les défis du niveau visé sont accomplis (→ donjon franchissable).
  bool expeditionChallengesAllDone() {
    final st = expeditionChallengeStatuses();
    return st.isNotEmpty && st.every((c) => c.done);
  }

  bool _taskIsDone(String taskId) {
    for (final p in currentProjects) {
      for (final t in p.tasks) {
        if (t.id == taskId) return t.status == 'done';
      }
    }
    return false;
  }

  int _routineMetDays(String activityId, [String? since]) {
    Activity? a;
    for (final x in state.activities) {
      if (x.id == activityId) {
        a = x;
        break;
      }
    }
    if (a == null) return 0;
    final tgt = activeHabitTarget(a);
    if (tgt <= 0) return 0;
    var days = 0;
    for (final hp in state.habitProgress) {
      if (hp.activityId != activityId || hp.value < tgt) continue;
      if (since != null && hp.yyyymmdd.compareTo(since) < 0) continue;
      days++;
    }
    return days;
  }

  int _activityLoggedMinutes(String activityId, [String? since]) {
    var min = 0;
    for (final s in state.sessions) {
      if (s.activityId != activityId) continue;
      if (since != null && yyyymmdd(s.startAt).compareTo(since) < 0) continue;
      min += s.duration.inMinutes;
    }
    return min;
  }

  /// Minutes loggées sur UN jour précis (pour la sévérité par jour).
  int _loggedMinutesOnDay(String activityId, String ymd) {
    var min = 0;
    for (final s in state.sessions) {
      if (s.activityId != activityId) continue;
      if (yyyymmdd(s.startAt) != ymd) continue;
      min += s.duration.inMinutes;
    }
    return min;
  }

  // ── Prévisualisation des coûts (Phase B) ────────────────────────────────────

  int previewDeleteActionCost() => GoldEconomy.deleteAction;
  int previewDeleteRoutineCost() => GoldEconomy.deleteRoutine;
  int previewDeadlinePushCost() => GoldEconomy.deadlinePush;

  int previewDeleteProjectCost(Project p) {
    final actions = p.tasks.fold<int>(0, (s, t) => s + t.actions.length);
    return GoldEconomy.deleteProjectCost(p.tasks.length, actions);
  }

  // ── Risques & provisoire (Phase C) ──────────────────────────────────────────

  /// Or « gain » d'un jour donné (gains seuls, sans pénalité), cohérent avec la
  /// matérialisation. Sert au provisoire du jour ET à la courbe d'historique.
  int goldGainForDay(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    final ymd = yyyymmdd(d);
    // Jours AVANT l'epoch (reset) → ignorés : l'historique repart de zéro.
    final epoch = state.goldEpochYmd;
    if (epoch != null && ymd.compareTo(epoch) < 0) return 0;
    final mult = state.goldBoostDays.contains(ymd) ? 2 : 1; // ×2 du jour
    final cursed = pestsAlive; // un ennemi vivant maudit tes routines (gain ÷2)
    var g = GoldEconomy.goldForMinutes(totalForDay(d).inMinutes, effectiveLevel());
    g += (state.challengeWinsByDay[ymd] ?? 0) * GoldEconomy.challengeDone;
    g += (state.ganttActionsByDay[ymd] ?? 0) * GoldEconomy.ganttAction;
    for (final a in state.activeActivities.where((x) => x.isHabit)) {
      final tgt = activeHabitTarget(a);
      if (tgt > 0 && habitValueOn(a.id, d) >= tgt) {
        var rg = GoldEconomy.routineGain(habitStreakEndingOn(a.id, d));
        if (cursed) rg = (rg / 2).ceil(); // malus de combat
        g += rg;
      }
    }
    return g * mult;
  }

  /// Vrai si au moins un nuisible est vivant sur la carte (applique le malus).
  bool get pestsAlive =>
      state.expeditionEntities.any((e) => isPestType(decodeEntity(e).type));

  /// Drain HORAIRE des nuisibles : à chaque visite de la carte, on retire
  /// (somme des forces : 2/3/5 or/h) × heures écoulées (plafonné `pestDrainCapHours`).
  /// Remplace l'ancien drain quotidien. À appeler à l'ouverture de l'overworld.
  void drainPestsHourly(FirestoreSync sync) {
    final now = DateTime.now();
    final live = state.expeditionEntities
        .where((e) => isPestType(decodeEntity(e).type))
        .toList();
    if (live.isEmpty) {
      state.lastPestDrainAt = now.toIso8601String();
      return;
    }
    final last = state.lastPestDrainAt != null
        ? DateTime.tryParse(state.lastPestDrainAt!)
        : null;
    final hours = last == null
        ? 0
        : (now.difference(last).inMinutes ~/ 60)
            .clamp(0, GoldEconomy.pestDrainCapHours);
    state.lastPestDrainAt = now.toIso8601String();
    if (hours <= 0) {
      onChange();
      return;
    }
    final rate = live.fold<int>(
        0, (s, e) => s + GoldEconomy.pestCost(decodeEntity(e).type));
    final drain = rate * hours;
    if (drain <= 0) return;
    state.gold -= drain;
    if (state.gold < 0) state.gold = 0;
    onChange();
    sync.applyGold(GoldLedgerEntry(
      id: '${DateTime.now().microsecondsSinceEpoch}',
      delta: -drain,
      category: 'loss',
      reasonCode: 'pest_drain_hourly',
      label: 'Nuisibles (−$rate or/h × ${hours}h)',
    ));
  }

  /// Or provisoire gagné aujourd'hui (gains seuls, sans pénalité — jour non clos).
  int provisionalGoldToday() => goldGainForDay(DateTime.now());

  // ── Quête du jour + coffre quotidien ────────────────────────────────────────

  int get dailyQuestTarget => GoldEconomy.dailyQuestTarget;

  /// Nombre d'« actions » accomplies aujourd'hui (routines validées + actions de
  /// projet cochées + défis relevés) → plus tu en fais, plus la quête avance.
  int dailyQuestProgress() {
    final today = DateTime.now();
    final ymd = yyyymmdd(today);
    int n = 0;
    for (final a in state.activeActivities) {
      if (!a.isHabit) continue;
      final tgt = activeHabitTarget(a);
      if (tgt > 0 && habitValueOn(a.id, today) >= tgt) n++;
    }
    n += state.ganttActionsByDay[ymd] ?? 0;
    n += state.challengeWinsByDay[ymd] ?? 0;
    return n;
  }

  bool dailyQuestDone() => dailyQuestProgress() >= dailyQuestTarget;

  /// Coffre du jour disponible : quête remplie ET pas encore ouvert aujourd'hui.
  bool dailyChestClaimable() =>
      dailyQuestDone() &&
      state.lastQuestClaimedYmd != yyyymmdd(DateTime.now());

  /// Or de série affiché sur la carte (🔥 jours consécutifs de quête).
  int get questStreak => state.questStreak;

  /// Ouvre le coffre quotidien → récompense VARIABLE (or + bonus de série +
  /// palier + chance de butin). Optimiste local + persistance.
  ({int gold, String? emoji, String? name, int streak, int milestone})
      claimDailyChest(FirestoreSync sync) {
    final today = DateTime.now();
    final ymd = yyyymmdd(today);
    if (state.lastQuestClaimedYmd == ymd) {
      return (gold: 0, emoji: null, name: null, streak: state.questStreak, milestone: 0);
    }
    final yesterday = yyyymmdd(today.subtract(const Duration(days: 1)));
    final streak =
        (state.lastQuestClaimedYmd == yesterday) ? state.questStreak + 1 : 1;
    final rng = Random();
    var gold = GoldEconomy.questChestGoldMin +
        rng.nextInt(
            GoldEconomy.questChestGoldMax - GoldEconomy.questChestGoldMin + 1);
    gold += (streak - 1).clamp(0, 10); // bonus de série croissant (cap +10/j)
    // Paliers de série : grosse récompense aux jalons.
    int milestone = 0;
    if (streak == 3) {
      milestone = 15;
    } else if (streak == 7) {
      milestone = 40;
    } else if (streak == 14) {
      milestone = 75;
    } else if (streak >= 30 && streak % 30 == 0) {
      milestone = 200;
    }
    gold += milestone;
    String? cid, emoji, name;
    if (rng.nextInt(100) < GoldEconomy.questChestCollectibleChancePct) {
      final pool = overworldCollectibles
          .where((c) => !state.collection.contains(c.id))
          .toList();
      if (pool.isNotEmpty) {
        final c = pool[rng.nextInt(pool.length)];
        cid = c.id;
        emoji = c.emoji;
        name = c.name;
      }
    }
    state.gold += gold;
    addLifetimeCapped(gold);
    if (cid != null && !state.collection.contains(cid)) {
      state.collection.add(cid);
      state.collectionMeta[cid] = '$ymd|coffre de quête';
      sync.setCollectionMeta(state.collectionMeta);
    }
    state.lastQuestClaimedYmd = ymd;
    state.questStreak = streak;
    onChange();
    sync.claimDailyQuest(
        gold: gold, collectibleId: cid, ymd: ymd, questStreak: streak);
    return (gold: gold, emoji: emoji, name: name, streak: streak, milestone: milestone);
  }

  /// Or que rapporterait une routine si elle est validée aujourd'hui (gain de
  /// base + bonus de série projeté). Sert à l'affichage « +N or » de « Mon or ».
  int routineGainToday(Activity a) {
    final today = DateTime.now();
    final tgt = activeHabitTarget(a);
    final doneToday = tgt > 0 && habitValueOn(a.id, today) >= tgt;
    final streak = doneToday
        ? habitStreakEndingOn(a.id, today)
        : habitStreakEndingOn(a.id, today.subtract(const Duration(days: 1))) + 1;
    return GoldEconomy.routineGain(streak);
  }

  /// Net d'or projeté ce soir si rien ne change : gains provisoires du jour
  /// moins les pertes à venir (routines lancées non faites + tâches en retard).
  int projectedGoldNetToday() {
    final losses = bleedingRoutines().length * GoldEconomy.routineMissed +
        lateTasks().length * GoldEconomy.lateTaskPerDay;
    return provisionalGoldToday() - losses;
  }

  /// Routines lancées mais NON faites aujourd'hui (saignent −1/j), avec l'or
  /// approximatif déjà rapporté (nb de jours faits × routineMet).
  List<({Activity activity, int earned})> bleedingRoutines() {
    final today = DateTime.now();
    final out = <({Activity activity, int earned})>[];
    final todayYmd = yyyymmdd(today);
    for (final a in state.activeActivities.where((x) => x.isHabit)) {
      final tgt = activeHabitTarget(a);
      if (tgt <= 0) continue;
      if (habitValueOn(a.id, today) >= tgt) continue; // faite aujourd'hui
      if (state.goldGelDays.contains('${a.id}_$todayYmd')) continue; // gelée
      if (!_routineLaunchedBy(a, today)) continue; // jamais lancée
      var metDays = 0;
      for (final hp in state.habitProgress) {
        if (hp.activityId == a.id && hp.value >= tgt) metDays++;
      }
      out.add((activity: a, earned: metDays * GoldEconomy.routineMet));
    }
    return out;
  }

  /// Tâches Gantt en retard avec le nombre de jours de retard.
  List<({Project project, ProjectTask task, int daysLate})> lateTasks() {
    final today = DateTime.now();
    final todayMid = DateTime(today.year, today.month, today.day);
    final todayYmd = yyyymmdd(today);
    final out = <({Project project, ProjectTask task, int daysLate})>[];
    for (final p in currentProjects) {
      if (p.status != 'active') continue; // skip draft + archived (hors économie)
      for (final t in p.tasks) {
        if (t.status == 'done' || t.status == 'skipped') continue;
        if (state.goldTaskShieldDays.contains('${t.id}_$todayYmd')) {
          continue; // bouclier anti-retard actif aujourd'hui
        }
        if (t.endDate != null && t.endDate!.isBefore(todayMid)) {
          final days = todayMid
              .difference(DateTime(
                  t.endDate!.year, t.endDate!.month, t.endDate!.day))
              .inDays;
          out.add((project: p, task: t, daysLate: days));
        }
      }
    }
    return out;
  }
}
