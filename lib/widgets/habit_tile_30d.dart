import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart' show AppLogic;
import 'package:productivitwo_v1/models.dart' show HabitFreq, AppState;
import 'tiny_bar.dart'; // adapte le chemin
// import tes modèles
// import '.../app_logic.dart';
// import '.../app_state.dart';

class NowHabit30dBar extends StatelessWidget {
  final AppLogic logic;
  final AppState st;
  final String habitId;   // id de l'Activity (habit)
  final DateTime day;

  const NowHabit30dBar({
    super.key,
    required this.logic,
    required this.st,
    required this.habitId,
    required this.day,
  });

  @override
  Widget build(BuildContext context) {
    final act = st.activities.firstWhere((a) => a.id == habitId);

    // ✅ done aujourd’hui
    final d0 = DateTime(day.year, day.month, day.day);
    final doneToday = logic.habitValueOn(habitId, d0);

    // ✅ target “aujourd’hui” (quota)
    final quota = logic.dayQuotaFor(act); // int
    final todayRatio = quota > 0 ? (doneToday / quota) : 0.0;

    // ✅ 30 jours: je te mets une version "simple" basée sur tes hits
    // Si tu as déjà une fonction 30j plus précise, remplace ces 10 lignes.
    final now = DateTime.now();
    final cutoff = now.subtract(const Duration(days: 30));
    final hits30 = st.habitHits.where((h) =>
        h.habitId == habitId && h.ts.isAfter(cutoff)).length;

    // cible 30j : quota * 30 (si daily)
    // sinon fallback sur habitTarget si présent
    final freq = logic.effectiveHabitFreq(act);
    final target30 = (freq == HabitFreq.daily && quota > 0)
        ? quota * 30
        : (act.habitTarget ?? 30);

    final ratio30 = target30 > 0 ? (hits30 / target30) : 0.0;

    return TinyBar(
      ratio: ratio30,
      labelLeft: "30 j : $hits30 / $target30   •   Aujourd’hui : $doneToday / $quota",
      padding: const EdgeInsets.only(top: 6),
    );
  }
}