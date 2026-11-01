import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/meal_day.dart' show isBalancedMealRoutine, isCookActivity, isEatActivity;
import 'package:productivitwo_v1/utils/sport_stats.dart' show isSportDomainName;

/// Onglet « Ma vie » (maquette validée 2026-11-01) : chaque domaine a une
/// NATURE qui décide de sa tuile et de ce qui s'ouvre au tap. Devinée au
/// départ, changeable d'un tap (`life_natures` en SharedPreferences).

enum DomainNature { night, sessions, meals, work, practice, tracking, upkeep }

const kNatureLabels = {
  DomainNature.night: 'Nuit',
  DomainNature.sessions: 'Séances',
  DomainNature.meals: 'Repas',
  DomainNature.work: 'Travail',
  DomainNature.practice: 'Pratique',
  DomainNature.tracking: 'Suivi',
  DomainNature.upkeep: 'Entretien',
};

const kNatureHints = {
  DomainNature.night: 'feuille Sommeil · nuits, coucher, dette',
  DomainNature.sessions: 'feuille Sport · séances, repos, répétitions',
  DomainNature.meals: 'feuille Repas · menu, plats, courses',
  DomainNature.work: 'temps de la semaine, projets, objectifs',
  DomainNature.practice: 'jours tenus, routines, minimum',
  DomainNature.tracking: 'relevé, chiffre de l’objectif',
  DomainNature.upkeep: 'routines de la maison, choses à faire',
};

const kNatureEmoji = {
  DomainNature.night: '🌙',
  DomainNature.sessions: '🏃',
  DomainNature.meals: '🍽',
  DomainNature.work: '💼',
  DomainNature.practice: '🙏',
  DomainNature.tracking: '📏',
  DomainNature.upkeep: '🏠',
};

bool _has(String name, String pattern) => RegExp(pattern, caseSensitive: false).hasMatch(name);

/// La nature devinée d'un domaine : son nom d'abord, puis ce qu'il contient.
DomainNature guessNature(Domain d, List<Activity> activities) {
  final n = d.name;
  if (_has(n, r'sommeil|nuit|repos')) return DomainNature.night;
  if (isSportDomainName(n)) return DomainNature.sessions;
  if (_has(n, r'repas|nutrition|alimentation|cuisine|manger')) return DomainNature.meals;
  if (_has(n, r'business|travail|pro|boulot|carri|entreprise|job|études|etudes|formation')) return DomainNature.work;
  if (_has(n, r'financ|budget|argent|compta')) return DomainNature.tracking;
  if (_has(n, r'intendance|maison|ménage|menage|foyer|logement|organisation')) return DomainNature.upkeep;
  final mine = activities.where((a) => !a.deleted && a.domainId == d.id);
  if (mine.any((a) => isBalancedMealRoutine(a) || isCookActivity(a) || isEatActivity(a))) return DomainNature.meals;
  return DomainNature.practice;
}

Map<String, DomainNature> parseNatures(Map<String, dynamic>? raw) {
  if (raw == null) return const {};
  return {
    for (final e in raw.entries)
      if (DomainNature.values.any((x) => x.name == e.value)) e.key: DomainNature.values.firstWhere((x) => x.name == e.value),
  };
}

/// Ordre des tuiles : le corps (nuit, séances, repas), puis le travail, puis le reste.
int natureOrder(DomainNature n) => DomainNature.values.indexOf(n);
