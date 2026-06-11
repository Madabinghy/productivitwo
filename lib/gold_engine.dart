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
    netDelta += earned - state.goldTodayGain;
    state.goldTodayGain = earned;
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
      key == 'epee' ? '🗡️' : (key == 'arc' ? '🏹' : '🩴');
  String weaponName(String key) =>
      key == 'epee' ? 'épée' : (key == 'arc' ? 'arc' : 'sandale');

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

  /// Armes DISPONIBLES = gagnées − dépensées, bornées à [0, weaponStockCap].
  /// Le plafond évite le stock infini : au-delà, l'or (crédité par action) prend
  /// le relais.
  int weaponsAvailable(String key) {
    final a = weaponsEarned(key) - (state.weaponsSpent[key] ?? 0);
    if (a < 0) return 0;
    return a > GoldEconomy.weaponStockCap ? GoldEconomy.weaponStockCap : a;
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

  // ── Engagement de combat : armes globales → épingler dans Combats en cours ──
  String _engageKey(String type, String itemId) => '$type~$itemId';

  bool isEngaged(String type, String itemId) =>
      state.engagedEnemies.contains(_engageKey(type, itemId));

  int engageCost(String type) => GoldEconomy.engageCost;

  bool canEngage(String type) =>
      weaponsAvailable(GoldEconomy.weaponForPest(type)) >= engageCost(type);

  /// Engage (épingle) un ennemi : dépense des armes globales adaptées, l'ajoute
  /// aux combats en cours. false si pas assez d'armes ou déjà engagé.
  bool engageEnemy(String type, String itemId, FirestoreSync sync) {
    if (isEngaged(type, itemId)) return false;
    final w = GoldEconomy.weaponForPest(type);
    if (weaponsAvailable(w) < engageCost(type)) return false;
    state.weaponsSpent[w] = (state.weaponsSpent[w] ?? 0) + engageCost(type);
    state.engagedEnemies.add(_engageKey(type, itemId));
    sync.setCombatStats(state.weaponsSpent, state.pestKills);
    sync.setEngagedEnemies(state.engagedEnemies);
    onChange();
    return true;
  }

  void unengageEnemy(String type, String itemId, FirestoreSync sync) {
    if (state.engagedEnemies.remove(_engageKey(type, itemId))) {
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
      final id = key.substring(i + 1);
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
      if (i < 0) {
        dead.add(key);
        continue;
      }
      if (enemyHp(key.substring(0, i), key.substring(i + 1)) <= 0) {
        dead.add(key);
      }
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
