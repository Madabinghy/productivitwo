import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/utils/day_win.dart';

void main() {
  final fri = DateTime(2026, 10, 2); // vendredi
  bool neverIdle(DateTime _) => false;
  bool weekendIdle(DateTime d) => d.weekday >= 6;

  test('paliers : 1+1 → 2+1 → … → 3+3, bornés', () {
    const g = DayGoal(1, 1);
    expect(g.up(), const DayGoal(2, 1));
    expect(g.down(), g);
    expect(const DayGoal(3, 3).up(), const DayGoal(3, 3));
    expect(const DayGoal(2, 2).level, 2);
    expect(g.label, '1 routine + 1 bloc terminé');
    expect(const DayGoal(2, 2).label, '2 routines + 2 blocs terminés');
  });

  test('progression : manque, gagné, ratio', () {
    const p0 = DayWinProgress(goal: DayGoal(1, 1), routinesDone: 0, blocksDone: 0);
    expect(p0.won, isFalse);
    expect(p0.missingLabel, 'Encore 1 routine et 1 bloc');
    const p1 = DayWinProgress(goal: DayGoal(1, 1), routinesDone: 1, blocksDone: 0);
    expect(p1.missingLabel, 'Plus qu\'un bloc');
    expect(p1.ratio, .5);
    const p2 = DayWinProgress(goal: DayGoal(1, 1), routinesDone: 3, blocksDone: 2);
    expect(p2.won, isTrue);
    expect(p2.missingLabel, isNull);
    const p3 = DayWinProgress(goal: DayGoal(2, 2), routinesDone: 1, blocksDone: 0);
    expect(p3.missingLabel, 'Encore 1 routine et 2 blocs');
  });

  test('série : compte à rebours, aujourd\'hui compte si gagné, un jour perdu casse', () {
    final won = {'2026-09-30', '2026-10-01', '2026-10-02'};
    expect(wonStreak(wonDays: won, today: fri, isIdle: neverIdle), 3);
    expect(wonStreak(wonDays: {'2026-09-30', '2026-10-01'}, today: fri, isIdle: neverIdle), 2);
    expect(wonStreak(wonDays: {'2026-09-29', '2026-10-01'}, today: fri, isIdle: neverIdle), 1);
    expect(wonStreak(wonDays: {}, today: fri, isIdle: neverIdle), 0);
  });

  test('série : un week-end au repos est enjambé, pas cassé', () {
    // ven. 25, puis sam./dim. sans usage, puis lun. 28 → mar. 29 → … ven. 2
    final won = {'2026-09-25', '2026-09-28', '2026-09-29', '2026-09-30', '2026-10-01', '2026-10-02'};
    expect(wonStreak(wonDays: won, today: fri, isIdle: weekendIdle), 6);
    expect(wonStreak(wonDays: won, today: fri, isIdle: neverIdle), 5);
  });

  test('descente : 2 journées perdues d\'affilée après le dernier changement', () {
    const g = DayGoal(2, 1);
    // mer. 30 et jeu. 1 perdus → descend
    expect(stepDownIfNeeded(goal: g, today: fri, wonDays: {'2026-09-29'}, isIdle: neverIdle),
        const DayGoal(1, 1));
    // jeu. gagné → rien
    expect(stepDownIfNeeded(goal: g, today: fri, wonDays: {'2026-10-01'}, isIdle: neverIdle), isNull);
    // seuil changé jeudi → la perte de mercredi ne compte pas → rien
    expect(stepDownIfNeeded(goal: g, today: fri, wonDays: {}, isIdle: neverIdle, since: '2026-10-01'),
        isNull);
    // déjà au minimum → rien
    expect(stepDownIfNeeded(goal: const DayGoal(1, 1), today: fri, wonDays: {}, isIdle: neverIdle),
        isNull);
    // week-end au repos enjambé : lun. 28 (today) après sam./dim. idle et jeu./ven. perdus
    expect(stepDownIfNeeded(goal: g, today: DateTime(2026, 9, 28), wonDays: {}, isIdle: weekendIdle),
        const DayGoal(1, 1));
  });

  test('montée proposée à 7 d\'affilée, jamais au plafond', () {
    expect(canStepUp(goal: const DayGoal(1, 1), streak: 7), isTrue);
    expect(canStepUp(goal: const DayGoal(1, 1), streak: 6), isFalse);
    expect(canStepUp(goal: const DayGoal(3, 3), streak: 30), isFalse);
  });
}
