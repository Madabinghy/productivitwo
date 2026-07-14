import 'package:productivitwo_v1/models.dart';

// ─── PROGRESSION PAR PALIERS (routines quotidiennes) ─────────────────────────
//
// « Mon programme cible 50 pompes/jour. Commence à me challenger sur 3/j,
// regarde comment j'évolue et ajuste. » Le cap est déclaré (`finalTarget`),
// `habitTarget` est le PALIER courant, et l'ajustement est HEBDOMADAIRE et
// DÉTERMINISTE — jamais de morale, jamais de LLM : seuls les hits réels de la
// semaine écoulée décident. Une évaluation par semaine, tracée dans
// `stepUpdatedWeek` (le lundi de la semaine évaluante).
//
// Règle : palier tenu ≥ 5 j/7  → palier suivant (× 1,5 arrondi, min +1,
//         plafonné au cap) ;
//         tenu ≤ 1 j/7 et palier > 1 → palier précédent (÷ 1,5 arrondi) ;
//         sinon → on garde (une semaine moyenne ne change rien).

/// Palier suivant : ×1,5 arrondi, au moins +1, jamais au-delà du cap.
/// 3 → 5 → 8 → 12 → 18 → 27 → 41 → 50.
int nextStepUp(int current, int cap) {
  final up = (current * 1.5).round();
  final next = up > current ? up : current + 1;
  return next > cap ? cap : next;
}

/// Palier précédent : ÷1,5 arrondi, plancher 1.
int nextStepDown(int current) {
  final down = (current / 1.5).round();
  final v = down >= current ? current - 1 : down;
  return v < 1 ? 1 : v;
}

String _ymdOf(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Lundi de la semaine de [now] (minuit).
DateTime mondayOf(DateTime now) {
  final d = DateTime(now.year, now.month, now.day);
  return d.subtract(Duration(days: d.weekday - 1));
}

/// Décision hebdo pour une routine à progression. Null = rien à faire
/// (pas de cap, pas quotidienne, déjà évaluée cette semaine, ou routine trop
/// jeune — pas une semaine complète de données). Sinon : le nouveau palier
/// (qui peut être identique — « tenue moyenne, on garde ») + les faits qui
/// ont décidé, à citer tels quels.
({int newTarget, int daysMet, String verdict})? weeklyStepDecision(
    Activity a, List<HabitHit> hits, DateTime now) {
  final cap = a.finalTarget;
  if (cap == null || cap <= 0) return null;
  if (!a.isHabit || a.effHabitFreq != HabitFreq.daily) return null;

  final monday = mondayOf(now);
  final mondayYmd = _ymdOf(monday);
  if (a.stepUpdatedWeek == mondayYmd) return null; // déjà évaluée

  final prevMonday = monday.subtract(const Duration(days: 7));
  // Routine créée en cours de semaine écoulée : pas une semaine complète de
  // données — on n'ajuste pas sur un échantillon partiel.
  if (a.createdAt.isAfter(prevMonday)) return null;

  final palier = a.effHabitTarget;
  // Hits par jour de la semaine écoulée (lundi → dimanche), journée vécue :
  // un hit nocturne (< 5 h) compte pour la veille, comme partout.
  final byDay = <String, int>{};
  for (final h in hits) {
    if (h.habitId != a.id) continue;
    final t = h.ts.hour * 60 + h.ts.minute < 5 * 60
        ? h.ts.subtract(const Duration(days: 1))
        : h.ts;
    final day = DateTime(t.year, t.month, t.day);
    if (day.isBefore(prevMonday) || !day.isBefore(monday)) continue;
    final k = _ymdOf(day);
    byDay[k] = (byDay[k] ?? 0) + 1;
  }
  final daysMet = byDay.values.where((v) => v >= palier).length;

  if (daysMet >= 5 && palier < cap) {
    return (newTarget: nextStepUp(palier, cap), daysMet: daysMet, verdict: 'up');
  }
  if (daysMet <= 1 && palier > 1) {
    return (
      newTarget: nextStepDown(palier),
      daysMet: daysMet,
      verdict: 'down'
    );
  }
  return (newTarget: palier, daysMet: daysMet, verdict: 'hold');
}

/// Fragment de fait à citer sur la carte / fiche : « Palier : 3/j — cap 50 ».
String palierLabel(Activity a) {
  final cap = a.finalTarget;
  if (cap == null || !a.isHabit) return '';
  final unit = (a.unit ?? '').trim();
  final u = unit.isEmpty ? '' : ' $unit';
  return 'Palier : ${a.effHabitTarget}$u/j — cap $cap';
}
