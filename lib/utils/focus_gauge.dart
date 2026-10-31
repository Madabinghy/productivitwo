import 'package:productivitwo_v1/utils/duration_fmt.dart';
import 'package:productivitwo_v1/utils/half_days.dart' show ActivityPace;

/// Le tuto de la jauge Focus (retour user 2026-10-31) : chaque partie de la
/// jauge expliquée avec les chiffres d'une vraie activité de l'utilisateur.
class FocusGaugeStory {
  final String name;
  final int goalMin, pastMin, todayMin, expectedMin, targetMin, missingMin;
  final bool sample; // exemple fictif : aucune activité à couvrir
  const FocusGaugeStory({
    required this.name,
    required this.goalMin,
    required this.pastMin,
    required this.todayMin,
    required this.expectedMin,
    required this.targetMin,
    required this.missingMin,
    this.sample = false,
  });

  factory FocusGaugeStory.of(ActivityPace p) {
    final goal = p.activity.goalMin;
    return FocusGaugeStory(
      name: p.activity.name,
      goalMin: goal,
      pastMin: p.pastMin,
      todayMin: p.todayMin,
      expectedMin: p.expectedMin,
      targetMin: p.dayTargetMin,
      missingMin: p.missingMin,
    );
  }

  static const sampleStory = FocusGaugeStory(
      name: 'Lecture', goalMin: 10, pastMin: 26, todayMin: 23, expectedMin: 70, targetMin: 44, missingMin: 21, sample: true);

  int get doneMin => pastMin + todayMin;
  int get days => goalMin <= 0 ? 7 : (expectedMin / goalMin).round();
  int get ringPct => targetMin <= 0 ? 100 : (todayMin * 100 / targetMin).round().clamp(0, 100);
  /// Retard pris sur les 6 jours passés (attendu à hier − fait).
  int get lateMin {
    final l = expectedMin - goalMin - pastMin;
    return l > 0 ? l : 0;
  }

  String get endLine => 'Le bout de la jauge = ${fmtMin(expectedMin)}, ce que la Montre suisse demande sur 7 jours '
      '($days × ${fmtMin(goalMin)} de minimum). C’est le chiffre de droite après « / ».';
  String get fillLine => 'La couleur = tout ce que tu as fait sur ces 7 jours : ${fmtMin(doneMin)}.';
  String get tickLine => pastMin == 0
      ? 'Le trait blanc = ce que tu as fait les 6 jours passés. Ici rien encore : il est tout à gauche.'
      : 'Le trait blanc = ce que tu as fait les 6 jours passés : ${fmtMin(pastMin)}. Plus tu es régulier, plus il avance vers la droite.';
  String get targetLine => lateMin > 0
      ? 'Du trait au bout = ta cible du jour : ${fmtMin(targetMin)}. D’habitude c’est ${fmtMin(goalMin)}, '
          'mais il y a ${fmtMin(lateMin)} de retard à rattraper.'
      : 'Du trait au bout = ta cible du jour : ${fmtMin(targetMin)}. En retard elle grandit, en avance elle rétrécit.';
  String get ringLine => 'L’anneau = ta cible du jour : ${fmtMin(todayMin)} sur ${fmtMin(targetMin)} ($ringPct %). '
      'Plein ✓ quand la Montre suisse est couverte ce soir.';
  String get verdict => missingMin <= 0
      ? 'En clair : tes 7 jours sont couverts.'
      : todayMin == 0
          ? 'En clair : fais ${fmtMin(missingMin)} aujourd’hui et la Montre suisse est couverte ce soir.'
          : 'En clair : encore ${fmtMin(missingMin)} aujourd’hui et la Montre suisse est couverte ce soir.';
}

/// L'activité qui illustre le mieux la jauge : on préfère un trait déjà
/// avancé et un peu de temps aujourd'hui, pour que chaque partie se voie.
ActivityPace? pickGaugeExample(Iterable<ActivityPace> toReach) {
  ActivityPace? best;
  var bestScore = -1;
  for (final p in toReach) {
    if (p.onPace || p.expectedMin <= 0) continue;
    final score = (p.pastMin > 0 ? 2 : 0) + (p.todayMin > 0 ? 1 : 0);
    if (score > bestScore) {
      best = p;
      bestScore = score;
    }
  }
  return best;
}
