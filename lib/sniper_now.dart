import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/badge_center.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/parole.dart' show kParoleMin, paroleIndex, paroleOfDay;
import 'package:productivitwo_v1/utils/routine_moments.dart';
import 'package:productivitwo_v1/utils/sniper.dart';
import 'package:productivitwo_v1/utils/stakes.dart';
import 'package:productivitwo_v1/utils/time_spent.dart' show estimateFactor, spentByAction;

/// Ce que le Sniper viserait là, maintenant : partagé par le viseur de l'écran
/// Sniper et par la miniature de la tuile du mode d'Aujourd'hui, pour qu'ils
/// disent la même chose.
typedef SniperBudget = ({int minutes, int untilMin, ScheduleBlock? until});

/// Les enjeux du jour vus par le Sniper (sans coupe) et les coches qui restent
/// aux routines. Sans deck de badges : rien.
({List<Stake> stakes, Map<String, int> routineLeft}) sniperStakesNow(AppLogic logic, BadgeCenter? bc) {
  if (bc == null) return (stakes: const [], routineLeft: const {});
  try {
    final st = logic.state;
    final facts = bc.todayFacts();
    final left = {for (final r in facts.routines) r.activity.id: r.target - r.done};
    final pd = paroleOfDay(logic.paroles, paroleIndex(logic.currentProjects, st.activeActivities), logic.livedTodayYmd, logic.dayStartMin);
    final board = buildStakeBoard(
      deck: bc.deck,
      facts: facts,
      hunts: logic.badgeHunts,
      projects: logic.currentProjects,
      activities: st.activeActivities,
      dayStartMin: logic.dayStartMin,
      parole: pd == null || pd.ids.length < kParoleMin ? null : pd,
      top: 1 << 20,
      familyCap: 1 << 20,
    );
    return (stakes: [...board.top, ...board.rest], routineLeft: left);
  } catch (_) {
    return (stakes: const [], routineLeft: const {});
  }
}

/// Réel / estimé des actions (1 quand rien n'est mesuré).
double sniperFactorNow(AppLogic logic) => estimateFactor(logic.currentProjects, spentByAction(logic.state.sessions)) ?? 1;

/// Le moment vu par le Sniper, là, maintenant : les routines du moment, ce qui reste des moments d'avant, ce qui
/// attend plus tard. À moins d'un quart d'heure de la fin d'un moment, c'est déjà le suivant.
SniperScope? sniperScopeNow(AppLogic logic) {
  try {
    final ms = logic.moments;
    final shift = sniperMomentShift(logic.livedNowMinNow, ms);
    final ymd = logic.livedYmdNow;
    return sniperScopeOf(buildRoutineDay(
      activities: logic.state.activeActivities,
      hits: logic.state.habitHits,
      now: DateTime.now().add(Duration(minutes: shift)),
      pushed: logic.routinePushed(ymd),
      deferred: logic.state.nowSkippedByYmd[ymd] ?? const [],
      dismissed: logic.nowDoneSet(ymd),
      dayStartMin: logic.dayStartMin,
      moments: ms,
    ));
  } catch (_) {
    return null;
  }
}

/// Le temps libre jusqu'au prochain bloc à faire, sinon la fin de la journée
/// active [endMin] (au moins une heure et demie quand elle est presque finie).
/// Avec un [scope], la lunette s'arrête aussi à la fin du moment : ce qui ne
/// tient pas passe au moment suivant.
SniperBudget sniperBudgetNow(AppLogic logic, {int endMin = 22 * 60, SniperScope? scope}) {
  final nowMin = logic.livedNowMinNow;
  var end = nowMin >= endMin - 15 ? nowMin + 90 : endMin;
  final momentEnd = scope?.moment.endMin;
  if (momentEnd != null && momentEnd > nowMin && momentEnd < end) end = momentEnd;
  return sniperBudget(blocks: logic.todayBlocks, nowMin: nowMin, endMin: end);
}

/// Le plan que le viseur proposerait à l'ouverture.
({SniperPlan plan, SniperBudget budget, SniperScope? scope}) sniperPlanNow(AppLogic logic, BadgeCenter? bc, {int endMin = 22 * 60}) {
  final s = sniperStakesNow(logic, bc);
  final scope = sniperScopeNow(logic);
  final budget = sniperBudgetNow(logic, endMin: endMin, scope: scope);
  final plan = planSniper(stakes: s.stakes, budgetMin: budget.minutes, untilMin: budget.untilMin, routineLeft: s.routineLeft, factor: sniperFactorNow(logic), scope: scope);
  return (plan: plan, budget: budget, scope: scope);
}
