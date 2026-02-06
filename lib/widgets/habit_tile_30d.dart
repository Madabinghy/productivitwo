import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart' show AppLogic;
import 'package:productivitwo_v1/models.dart'
    show HabitFreq, AppState, Activity;
import 'tiny_bar.dart'; // adapte le chemin
// import tes modèles
// import '.../app_logic.dart';
// import '.../app_state.dart';

class NowHabit30dBar extends StatelessWidget {
  final AppLogic logic;
  final AppState st;
  final String habitId; // id de l'Activity (habit)
  final DateTime day;

  const NowHabit30dBar({
    super.key,
    required this.logic,
    required this.st,
    required this.habitId,
    required this.day,
  });

  int _sumOverDays(String habitId, DateTime endInclusive, int days) {
    int total = 0;
    final end =
        DateTime(endInclusive.year, endInclusive.month, endInclusive.day);
    for (int i = 0; i < days; i++) {
      final d = end.subtract(Duration(days: i));
      total += this.logic.habitValueOn(habitId, d);
    }
    return total;
  }

  (int days, int target, String label) _windowAndTarget(Activity act) {
    final freq = this.logic.effectiveHabitFreq(act);
    final quota = this.logic.dayQuotaFor(act); // quota “par jour”

    switch (freq) {
      case HabitFreq.daily:
        return (1, quota, "Aujourd’hui");
      case HabitFreq.weekly:
        // si ta cible “hebdo” est act.habitTarget, utilise-la.
        // sinon fallback quota*7
        final tgt = (act.habitTarget != null && act.habitTarget! > 0)
            ? act.habitTarget!
            : quota * 7;
        return (7, tgt, "7 j");
      case HabitFreq.monthly:
        final tgt = (act.habitTarget != null && act.habitTarget! > 0)
            ? act.habitTarget!
            : quota * 30;
        return (30, tgt, "30 j");
      default:
        // fallback safe
        return (30, (act.habitTarget ?? 30), "30 j");
    }
  }

  @override
  Widget build(BuildContext context) {
    final act = st.activities.firstWhere((a) => a.id == habitId);

    final d0 = DateTime(day.year, day.month, day.day);
    final doneToday = logic.habitValueOn(habitId, d0);
    final quota = logic.dayQuotaFor(act);

// fenêtre principale (selon freq)
    final (daysWin, targetWin, labelWin) = _windowAndTarget(act);

// done fenêtre (calendaire)
    final doneWin = _sumOverDays(habitId, d0, daysWin);
    final ratioWin = targetWin > 0 ? (doneWin / targetWin) : 0.0;

// label sans doublon
    final label = (daysWin == 1)
        ? "Aujourd’hui : $doneToday / $quota"
        : "$labelWin : $doneWin / $targetWin   •   Aujourd’hui : $doneToday / $quota";

    return TinyBar(
      ratio: ratioWin,
      labelLeft: label,
      padding: const EdgeInsets.only(top: 6),
    );
  }
}

