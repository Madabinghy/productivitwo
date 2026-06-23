part of '../gold_engine.dart';

/// « Mise du jour » — commitment device honnête (sink d'or quotidien).
///
/// Tu mises de l'or sur ta journée ; le règlement dépend du travail RÉEL
/// (routines quotidiennes tenues, hits BRUTS — pas la reconquête) → impossible de
/// gagner sa mise sans faire le travail. Ne touche jamais `goldLifetime`.
extension GoldEngineDailyStake on AppLogic {
  /// Routines QUOTIDIENNES dues ce jour + combien sont tenues (travail brut).
  ({int due, int met}) dailyRoutineTally(DateTime day) {
    var due = 0, met = 0;
    for (final a in state.activeActivities) {
      if (!a.isHabit) continue;
      if (effectiveHabitFreq(a) != HabitFreq.daily) continue;
      final quota = dayQuotaFor(a);
      if (quota <= 0) continue;
      due++;
      if (habitValueOn(a.id, day) >= quota) met++;
    }
    return (due: due, met: met);
  }

  /// Ratio de complétion des routines du jour (0..1), ou -1 si aucune routine due.
  double dailyRoutineRatio(DateTime day) {
    final t = dailyRoutineTally(day);
    if (t.due == 0) return -1;
    return t.met / t.due;
  }

  int stakeOn(String ymd) => state.dailyStakeByDay[ymd] ?? 0;

  int stakeAmountToday() => stakeOn(yyyymmdd(DateTime.now()));

  bool stakePlacedToday() =>
      state.dailyStakeByDay.containsKey(yyyymmdd(DateTime.now()));

  /// Peut-on miser aujourd'hui ? (pas déjà misé ET au moins une routine due)
  bool canStakeToday() {
    if (stakePlacedToday()) return false;
    return dailyRoutineTally(DateTime.now()).due > 0;
  }

  /// Place la mise du jour : optimiste local + transaction autoritative.
  Future<bool> placeStakeToday(FirestoreSync sync, int amount) async {
    final ymd = yyyymmdd(DateTime.now());
    final amt = amount < 1
        ? 1
        : (amount > GoldEconomy.stakeMaxPerDay
            ? GoldEconomy.stakeMaxPerDay
            : amount);
    if (state.dailyStakeByDay.containsKey(ymd)) return false;
    if (state.gold < amt) return false;
    state.gold -= amt; // optimiste
    state.dailyStakeByDay[ymd] = amt;
    onChange();
    final ok = await sync.placeDailyStake(ymd: ymd, amount: amt);
    if (!ok) {
      state.gold += amt; // rollback si refus serveur
      state.dailyStakeByDay.remove(ymd);
      onChange();
    }
    return ok;
  }

  /// Règle toutes les mises des jours PASSÉS non encore réglées (à l'ouverture),
  /// sur le travail réel de chaque jour. Renvoie les règlements (pour un toast).
  Future<List<({String ymd, int amount, double ratio, int payout})>>
      settleDueStakes(FirestoreSync sync) async {
    final results = <({String ymd, int amount, double ratio, int payout})>[];
    final todayYmd = yyyymmdd(DateTime.now());
    final pending = state.dailyStakeByDay.entries
        .where((e) =>
            e.key != todayYmd && !state.dailyStakeSettledDays.contains(e.key))
        .toList();
    for (final e in pending) {
      final ymd = e.key;
      final amount = e.value;
      final day = _dayFromYmd(ymd);
      int payout;
      double ratioForUi;
      if (day == null) {
        payout = amount; // ymd illisible → remboursement simple, sans bonus
        ratioForUi = 1.0;
      } else {
        final t = dailyRoutineTally(day);
        if (t.due == 0) {
          payout = amount; // aucune routine due ce jour → remboursé (pas de bonus)
          ratioForUi = 1.0;
        } else {
          ratioForUi = t.met / t.due;
          payout = GoldEconomy.stakePayout(amount, ratioForUi);
        }
      }
      state.gold += payout; // optimiste local
      state.dailyStakeSettledDays.add(ymd);
      onChange();
      final ok = await sync.settleDailyStake(ymd: ymd, payout: payout);
      if (!ok) {
        state.gold -= payout; // déjà réglé ailleurs → annule le crédit local
        onChange();
      } else {
        results.add(
            (ymd: ymd, amount: amount, ratio: ratioForUi, payout: payout));
      }
    }
    return results;
  }

  DateTime? _dayFromYmd(String ymd) {
    if (ymd.length != 8) return null;
    final y = int.tryParse(ymd.substring(0, 4));
    final m = int.tryParse(ymd.substring(4, 6));
    final d = int.tryParse(ymd.substring(6, 8));
    if (y == null || m == null || d == null) return null;
    return DateTime(y, m, d);
  }
}
