/// « Journée gagnée » (audit ergonomie, lot 2) : UNE condition par jour —
/// R routines atteintes + B blocs terminés — une série de journées gagnées,
/// et un seuil qui s'adapte seul. Logique pure, testée ; l'UI et la
/// persistance vivent dans AppLogic / TodayView.

class DayGoal {
  final int routines;
  final int blocks;
  const DayGoal(this.routines, this.blocks);

  /// Paliers, du plus doux au plafond. Départ = 1 + 1 (décision user).
  static const levels = [
    DayGoal(1, 1),
    DayGoal(2, 1),
    DayGoal(2, 2),
    DayGoal(3, 2),
    DayGoal(3, 3),
  ];

  int get level {
    for (var i = 0; i < levels.length; i++) {
      if (levels[i].routines == routines && levels[i].blocks == blocks) return i;
    }
    return 0;
  }

  bool get isMax => level >= levels.length - 1;
  bool get isMin => level <= 0;
  DayGoal up() => isMax ? this : levels[level + 1];
  DayGoal down() => isMin ? this : levels[level - 1];

  /// « 1 routine + 1 bloc terminé ».
  String get label =>
      '$routines routine${routines > 1 ? 's' : ''} + $blocks bloc${blocks > 1 ? 's' : ''} terminé${blocks > 1 ? 's' : ''}';

  @override
  bool operator ==(Object o) => o is DayGoal && o.routines == routines && o.blocks == blocks;
  @override
  int get hashCode => Object.hash(routines, blocks);
  @override
  String toString() => 'DayGoal($routines+$blocks)';
}

class DayWinProgress {
  final DayGoal goal;
  final int routinesDone;
  final int blocksDone;
  const DayWinProgress({required this.goal, required this.routinesDone, required this.blocksDone});

  int get routinesLeft => (goal.routines - routinesDone).clamp(0, goal.routines);
  int get blocksLeft => (goal.blocks - blocksDone).clamp(0, goal.blocks);
  bool get won => routinesLeft == 0 && blocksLeft == 0;
  int get total => goal.routines + goal.blocks;
  int get done => total - routinesLeft - blocksLeft;
  double get ratio => total == 0 ? 0 : done / total;

  /// Ce qui manque, dans les mots de la carte : « Plus qu'un bloc »,
  /// « Encore 1 routine et 2 blocs ». Null quand c'est gagné.
  String? get missingLabel {
    if (won) return null;
    final parts = <String>[
      if (routinesLeft > 0) '$routinesLeft routine${routinesLeft > 1 ? 's' : ''}',
      if (blocksLeft > 0) '$blocksLeft bloc${blocksLeft > 1 ? 's' : ''}',
    ];
    if (parts.length == 1 && (routinesLeft + blocksLeft) == 1) {
      return routinesLeft == 1 ? 'Plus qu\'une routine' : 'Plus qu\'un bloc';
    }
    return 'Encore ${parts.join(' et ')}';
  }
}

String ymdKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Série de journées gagnées : on compte à rebours depuis aujourd'hui (si
/// gagné) ou hier. Un jour « au repos » (`isIdle` : aucune trace d'usage un
/// week-end, vacances) est enjambé sans casser ; un jour perdu casse.
int wonStreak({
  required Set<String> wonDays,
  required DateTime today,
  required bool Function(DateTime day) isIdle,
}) {
  var d = DateTime(today.year, today.month, today.day);
  if (!wonDays.contains(ymdKey(d))) d = d.subtract(const Duration(days: 1));
  var streak = 0;
  var guard = 0;
  while (guard++ < 3650) {
    final k = ymdKey(d);
    if (wonDays.contains(k)) {
      streak++;
    } else if (!isIdle(d)) {
      break;
    }
    d = d.subtract(const Duration(days: 1));
  }
  return streak;
}

/// Seuil adaptatif, côté descente (la montée est PROPOSÉE par le coach, lot
/// 3) : deux journées perdues d'affilée (hors jours au repos), toutes deux
/// après la dernière modification du seuil → un cran de moins. Retourne le
/// nouveau seuil, ou null si rien ne change.
DayGoal? stepDownIfNeeded({
  required DayGoal goal,
  required DateTime today,
  required Set<String> wonDays,
  required bool Function(DateTime day) isIdle,
  String? since, // YYYY-MM-DD du dernier changement de seuil
}) {
  if (goal.isMin) return null;
  var d = DateTime(today.year, today.month, today.day).subtract(const Duration(days: 1));
  var lost = 0;
  var guard = 0;
  while (guard++ < 14 && lost < 2) {
    final k = ymdKey(d);
    if (since != null && k.compareTo(since) < 0) return null; // avant le dernier changement
    if (wonDays.contains(k)) return null; // la chaîne de pertes est rompue
    if (!isIdle(d)) lost++;
    d = d.subtract(const Duration(days: 1));
  }
  return lost >= 2 ? goal.down() : null;
}

/// Montée possible (proposée, jamais imposée) : 7 journées gagnées d'affilée
/// et un palier au-dessus.
bool canStepUp({required DayGoal goal, required int streak}) => !goal.isMax && streak >= 7;
