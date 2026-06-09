import 'package:productivitwo_v1/app_logic.dart';
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
    if (delta > 0) state.goldLifetime += delta; // lifetime monotone
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
    onChange();
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

  /// Matérialise gains/pertes pour chaque jour CLOS non encore traité
  /// (strictement entre le curseur et aujourd'hui). Idempotent : ids déterministes
  /// + curseur → un jour n'est jamais compté deux fois.
  void materializeGoldUpTo(FirestoreSync sync, DateTime today) {
    final cursor = state.goldLastProcessedDay;
    if (cursor == null) {
      seedGoldIfNeeded(sync);
      return;
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

    // ── Gains du jour ─────────────────────────────────────────────────────────
    final hours = totalForDay(d).inMinutes ~/ 60;
    if (hours > 0) {
      out.add(GoldLedgerEntry(
          id: 'time_$ymd', delta: hours * GoldEconomy.timePerHour,
          category: 'gain', reasonCode: 'time_logged',
          label: '$hours h de temps loggué'));
    }
    final challenges = state.challengeWinsByDay[ymd] ?? 0;
    if (challenges > 0) {
      out.add(GoldLedgerEntry(
          id: 'chal_$ymd', delta: challenges * GoldEconomy.challengeDone,
          category: 'gain', reasonCode: 'challenge',
          label: '$challenges défi(s) relevé(s)'));
    }
    final gantt = state.ganttActionsByDay[ymd] ?? 0;
    if (gantt > 0) {
      out.add(GoldLedgerEntry(
          id: 'gantt_$ymd', delta: gantt * GoldEconomy.ganttAction,
          category: 'gain', reasonCode: 'gantt_action',
          label: '$gantt action(s) Gantt'));
    }

    // ── Routines : gain (faite) ou perte (manquée, si lancée & non gelée) ──────
    for (final a in state.activeActivities.where((x) => x.isHabit)) {
      final tgt = activeHabitTarget(a);
      if (tgt <= 0) continue;
      final met = habitValueOn(a.id, d) >= tgt;
      if (met) {
        out.add(GoldLedgerEntry(
            id: 'rmet_${a.id}_$ymd', delta: GoldEconomy.routineMet,
            category: 'gain', reasonCode: 'routine_met',
            label: 'Routine « ${a.name} » faite',
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
      if (p.status == 'archived') continue;
      for (final t in p.tasks) {
        if (t.status == 'done' || t.status == 'skipped') continue;
        if (t.endDate != null && t.endDate!.isBefore(dMid)) {
          out.add(GoldLedgerEntry(
              id: 'late_${t.id}_$ymd', delta: -GoldEconomy.lateTaskPerDay,
              category: 'loss', reasonCode: 'late_task',
              label: 'Retard : « ${t.title} »',
              refType: 'task', refId: t.id));
        }
      }
    }
    return out;
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

  // ── Prévisualisation des coûts (Phase B) ────────────────────────────────────

  int previewDeleteActionCost() => GoldEconomy.deleteAction;
  int previewDeleteRoutineCost() => GoldEconomy.deleteRoutine;
  int previewDeadlinePushCost() => GoldEconomy.deadlinePush;

  int previewDeleteProjectCost(Project p) {
    final actions = p.tasks.fold<int>(0, (s, t) => s + t.actions.length);
    return GoldEconomy.deleteProjectCost(p.tasks.length, actions);
  }

  // ── Risques & provisoire (Phase C) ──────────────────────────────────────────

  /// Or provisoire gagné aujourd'hui (gains seuls, sans pénalité — jour non clos).
  int provisionalGoldToday() {
    final d = DateTime.now();
    final ymd = yyyymmdd(d);
    var g = (totalForDay(d).inMinutes ~/ 60) * GoldEconomy.timePerHour;
    g += (state.challengeWinsByDay[ymd] ?? 0) * GoldEconomy.challengeDone;
    g += (state.ganttActionsByDay[ymd] ?? 0) * GoldEconomy.ganttAction;
    for (final a in state.activeActivities.where((x) => x.isHabit)) {
      final tgt = activeHabitTarget(a);
      if (tgt > 0 && habitValueOn(a.id, d) >= tgt) g += GoldEconomy.routineMet;
    }
    return g;
  }

  /// Routines lancées mais NON faites aujourd'hui (saignent −1/j), avec l'or
  /// approximatif déjà rapporté (nb de jours faits × routineMet).
  List<({Activity activity, int earned})> bleedingRoutines() {
    final today = DateTime.now();
    final out = <({Activity activity, int earned})>[];
    for (final a in state.activeActivities.where((x) => x.isHabit)) {
      final tgt = activeHabitTarget(a);
      if (tgt <= 0) continue;
      if (habitValueOn(a.id, today) >= tgt) continue; // faite aujourd'hui
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
    final out = <({Project project, ProjectTask task, int daysLate})>[];
    for (final p in currentProjects) {
      if (p.status == 'archived') continue;
      for (final t in p.tasks) {
        if (t.status == 'done' || t.status == 'skipped') continue;
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
