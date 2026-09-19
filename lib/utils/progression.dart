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
// Règle (pas kaizen, 2026-09 — l'ancien ×1,5 faisait des marches brutales) :
//   palier tenu ≥ 5 j/7 → +1, MAIS si le réel de la semaine est déjà bien
//   au-dessus (médiane des jours ≥ palier), le palier RATTRAPE le réel à
//   ~80 % de cette médiane (sinon une cible retombée à 1 mettrait des mois
//   à rejoindre les 12 tractions réellement faites) ; plafonné au cap.
//   Tenu ≤ 1 j/7 et palier > 1 → −1 (plancher 1).
//   Sinon → on garde (une semaine moyenne ne change rien).

/// Palier suivant : +1, ou ~80 % de la médiane vécue si elle est plus haute
/// (le palier suit le réel, jamais l'inverse) ; jamais au-delà du cap.
int nextStepUp(int current, int cap, {int? medianReal}) {
  var next = current + 1;
  if (medianReal != null) {
    final catchUp = (medianReal * 0.8).round();
    if (catchUp > next) next = catchUp;
  }
  return next > cap ? cap : next;
}

/// Palier précédent : −1, plancher 1.
int nextStepDown(int current) {
  final v = current - 1;
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
    // Médiane des jours qui ont tenu le palier : le réel vécu de la semaine.
    final met = byDay.values.where((v) => v >= palier).toList()..sort();
    final medianReal = met[met.length ~/ 2];
    return (
      newTarget: nextStepUp(palier, cap, medianReal: medianReal),
      daysMet: daysMet,
      verdict: 'up'
    );
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
