import 'package:productivitwo_v1/models.dart';

// ─── CORRESPONDANCE BLOC ↔ ROUTINE PAR TITRE ────────────────────────────────
//
// Un bloc de programme sans activityId (proposition LLM qui a omis le lien,
// bloc posé à la main « Vitamines ») doit quand même valider la routine du
// même nom quand on le coche. Correspondance déterministe : UNIQUE, insensible
// à la casse et aux accents — zéro ou plusieurs candidates = pas de lien
// deviné (jamais d'incrément dans le doute).

/// Repli casse + accents — partagé avec le catalogue de contextes horaires.
String foldName(String s) => _fold(s);

String _fold(String s) {
  const map = {
    'à': 'a', 'â': 'a', 'ä': 'a',
    'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
    'î': 'i', 'ï': 'i',
    'ô': 'o', 'ö': 'o',
    'ù': 'u', 'û': 'u', 'ü': 'u',
    'ç': 'c',
  };
  final sb = StringBuffer();
  for (final ch in s.toLowerCase().runes) {
    final c = String.fromCharCode(ch);
    sb.write(map[c] ?? c);
  }
  return sb.toString();
}

/// La routine dont le nom apparaît dans [title] — null si aucune ou plusieurs.
Activity? routineForBlockTitle(String title, Iterable<Activity> activities) {
  final t = _fold(title);
  final matches = <Activity>[
    for (final a in activities)
      if (!a.deleted && a.isHabit && a.name.trim().length >= 3 &&
          t.contains(_fold(a.name.trim())))
        a,
  ];
  return matches.length == 1 ? matches.first : null;
}
