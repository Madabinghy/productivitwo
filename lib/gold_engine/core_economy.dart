part of '../gold_engine.dart';

/// Moteur d'Or branché sur AppLogic (côté mobile).
///
/// **Source de vérité = Firestore** : tout solde/ledger est écrit par transaction
/// (`FirestoreSync.applyGoldBatch`), partagée avec le web. Ici on fait en plus une
/// mise à jour OPTIMISTE de `state` pour un retour UI instantané ; la transaction
/// reconverge (mêmes deltas) et le prochain pull rafraîchit `state` depuis le meta.
extension GoldEngineCore on AppLogic {
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
}
