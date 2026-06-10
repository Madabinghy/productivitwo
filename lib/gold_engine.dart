import 'dart:convert';

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

    // ── Nuisibles vivants sur la carte d'expédition (drain journalier fixe) ────
    out.addAll(_pestDrainForDay(ymd));
    return out;
  }

  /// Entrées de drain des nuisibles vivants le jour [ymd] (idempotent, id stable).
  List<GoldLedgerEntry> _pestDrainForDay(String ymd) {
    final out = <GoldLedgerEntry>[];
    for (final e in state.expeditionEntities) {
      final ent = decodeEntity(e);
      if (!isPestType(ent.type) || ent.meta.isEmpty) continue;
      final spawn = ent.meta;
      final life = GoldEconomy.pestLifespanDays(ent.type);
      final diff = _parseYmd(ymd).difference(_parseYmd(spawn)).inDays;
      if (diff >= 0 && diff < life) {
        out.add(GoldLedgerEntry(
            id: 'pestdrain_${ent.type}_${ent.tile}_$ymd',
            delta: -GoldEconomy.pestCost(ent.type),
            category: 'loss',
            reasonCode: 'pest_drain',
            label: '${pestName(ent.type)} sur la carte'));
      }
    }
    return out;
  }

  /// Drain provisoire des nuisibles vivants AUJOURD'HUI (pour le net projeté).
  int pestDrainToday() => _pestDrainForDay(yyyymmdd(DateTime.now()))
      .fold(0, (s, e) => s + e.delta);

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
      switch (type) {
        case 'task':
          final done = _taskIsDone(refId);
          out.add((
            label: label, type: type,
            target: 1, progress: done ? 1 : 0, done: done,
          ));
          break;
        case 'routine':
          final p = _routineMetDays(refId).clamp(0, tgt);
          out.add((
            label: label, type: type,
            target: tgt, progress: p, done: p >= tgt,
          ));
          break;
        case 'time':
          final p = _activityLoggedMinutes(refId).clamp(0, tgt);
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

  int _routineMetDays(String activityId) {
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
      if (hp.activityId == activityId && hp.value >= tgt) days++;
    }
    return days;
  }

  int _activityLoggedMinutes(String activityId) {
    var min = 0;
    for (final s in state.sessions) {
      if (s.activityId == activityId) min += s.duration.inMinutes;
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
    final mult = state.goldBoostDays.contains(ymd) ? 2 : 1; // ×2 du jour
    var g = GoldEconomy.goldForMinutes(totalForDay(d).inMinutes, effectiveLevel());
    g += (state.challengeWinsByDay[ymd] ?? 0) * GoldEconomy.challengeDone;
    g += (state.ganttActionsByDay[ymd] ?? 0) * GoldEconomy.ganttAction;
    for (final a in state.activeActivities.where((x) => x.isHabit)) {
      final tgt = activeHabitTarget(a);
      if (tgt > 0 && habitValueOn(a.id, d) >= tgt) {
        g += GoldEconomy.routineGain(habitStreakEndingOn(a.id, d));
      }
    }
    return g * mult;
  }

  /// Or provisoire gagné aujourd'hui (gains seuls, sans pénalité — jour non clos).
  int provisionalGoldToday() => goldGainForDay(DateTime.now());

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
    return provisionalGoldToday() - losses + pestDrainToday();
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
