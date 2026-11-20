import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/engagement_stats.dart' show ymdOf;
import 'package:productivitwo_v1/utils/lived_day.dart';

/// Cible automatique d'une routine quotidienne (2026-11-20, demande user : « quand on atteint 120 %, on augmente
/// un petit peu le standard, et il redescend si on descend trop bas ») : la cible suit ce qui est vraiment fait.
/// Règle fixe, jamais d'IA : on regarde les 7 derniers jours CLOS (hier compris, pas aujourd'hui).
///   fait ≥ 120 % du demandé → un cran de plus, sans jamais dépasser la moyenne réellement faite ;
///   fait < 50 % du demandé → un cran de moins (plancher 1) ;
///   sinon rien. Un cran = 10 % de la cible, 1 au moins. Un seul changement par semaine.
/// Un jour gelé (veille, gel, Le minimum, journée difficile) ne compte ni dans le fait ni dans le demandé ;
/// il faut au moins [kAutoMinDays] jours comptés pour décider.

const double kAutoRaiseRatio = 1.20;
const double kAutoLowerRatio = 0.50;
const double kAutoStepPct = 0.10;
const int kAutoWindowDays = 7;
const int kAutoMinDays = 5;

/// La cible automatique ne concerne qu'une routine quotidienne sans cap (une routine à cap progresse déjà par
/// paliers, `utils/progression.dart`).
bool canAutoTarget(Activity a) =>
    a.isHabit && !a.deleted && a.habitFreq == HabitFreq.daily && (a.finalTarget ?? 0) <= 0;

/// Un cran : 10 % de la cible, 1 au moins.
int autoStep(int target) {
  final s = (target * kAutoStepPct).round();
  return s < 1 ? 1 : s;
}

class AutoTargetDecision {
  final int from;
  final int to;

  /// Coches faites et demandées sur les jours comptés.
  final int done;
  final int asked;
  final int days;
  const AutoTargetDecision({required this.from, required this.to, required this.done, required this.asked, required this.days});

  bool get up => to > from;
  int get pct => asked <= 0 ? 0 : (done * 100 / asked).round();

  /// « Pompes : cible 20 → 22 par jour (130 % sur 7 jours) ».
  String note(String name) => '$name : cible $from → $to par jour ($pct % sur $days jours)';
}

/// La décision du jour pour [a], ou null (rien à changer, pas concernée, trop tôt).
AutoTargetDecision? autoTargetDecision(Activity a, List<HabitHit> hits, DateTime now,
    {int dayStartMin = kDefaultDayStartMin, Set<String> frozen = const {}}) {
  if (!a.autoTarget || !canAutoTarget(a)) return null;
  final today = livedDate(now, dayStartMin);
  DateTime back(int n) => DateTime(today.year, today.month, today.day - n);
  final first = back(kAutoWindowDays);
  DateTime dayOf(DateTime t) {
    final d = livedDate(t, dayStartMin);
    return DateTime(d.year, d.month, d.day);
  }

  // Une semaine pleine à la cible actuelle : ni routine trop jeune, ni cible changée depuis.
  if (dayOf(a.createdAt).isAfter(first)) return null;
  final tuned = a.lastTuneAt;
  if (tuned != null && dayOf(tuned).isAfter(first)) return null;

  final days = [
    for (var i = kAutoWindowDays; i >= 1; i--)
      if (!frozen.contains(ymdOf(back(i)))) ymdOf(back(i))
  ];
  if (days.length < kAutoMinDays) return null;
  final wanted = days.toSet();
  var done = 0;
  for (final h in hits) {
    if (h.habitId != a.id) continue;
    if (wanted.contains(ymdOf(livedDate(h.ts, dayStartMin)))) done++;
  }
  final t = a.effHabitTarget < 1 ? 1 : a.effHabitTarget;
  final asked = t * days.length;
  final ratio = done / asked;
  final step = autoStep(t);

  if (ratio >= kAutoRaiseRatio) {
    // Jamais au-dessus de ce qui est vraiment fait en moyenne : la nouvelle cible est déjà tenue.
    final mean = done ~/ days.length;
    var to = t + step;
    if (to > mean) to = mean;
    if (to <= t) return null;
    return AutoTargetDecision(from: t, to: to, done: done, asked: asked, days: days.length);
  }
  if (ratio < kAutoLowerRatio && t > 1) {
    final to = t - step < 1 ? 1 : t - step;
    return AutoTargetDecision(from: t, to: to, done: done, asked: asked, days: days.length);
  }
  return null;
}

/// Ce que dit la fiche sous l'interrupteur : le dernier changement connu, ou rien.
String? lastTargetChangeLabel(Activity a) {
  if (a.targetLog.isEmpty) return null;
  final last = a.targetLog.last;
  final d = DateTime.tryParse(last.until);
  if (d == null || last.target == a.effHabitTarget) return null;
  final day = DateTime(d.year, d.month, d.day + 1);
  const months = ['janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'];
  return '${last.target} → ${a.effHabitTarget} depuis le ${day.day} ${months[day.month - 1]}';
}
