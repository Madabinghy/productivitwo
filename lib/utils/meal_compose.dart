import 'package:productivitwo_v1/utils/groceries.dart';
import 'package:productivitwo_v1/utils/meal_families.dart';
import 'package:productivitwo_v1/utils/meal_plan.dart';
import 'package:productivitwo_v1/utils/pantry.dart' show foldWords;

/// Repas en 3 familles — lot 2 : composer un repas avec ce qu'on a, et les
/// suggestions (logique pure, `widgets/meal_compose_sheet.dart`).

/// Les familles couvertes par des briques (accompagnements exclus).
Set<String> coveredFamilies(Iterable<MealComponent> cs) => {
      for (final c in cs)
        for (final f in c.families)
          if (kMealFamilies.contains(f)) f,
    };

/// Un repas composé est valide dès 2 familles sur 3.
bool isValidMeal(Iterable<MealComponent> cs) => coveredFamilies(cs).length >= 2;

/// Titre d'un repas composé : les briques qui comptent, dans l'ordre
/// protéines · féculents · fibres (« Lardons · Pâtes · Champignons »).
String composedTitle(Iterable<MealComponent> cs) {
  int rank(MealComponent c) {
    final i = kMealFamilies.indexWhere(c.families.contains);
    return i < 0 ? 9 : i;
  }

  final main = cs.where((c) => countsInMeal(c.families)).toList()..sort((a, b) => rank(a).compareTo(rank(b)));
  return main.map((c) => c.label).join(' · ');
}

/// Les accompagnements d'un repas composé (« avec : oignon, ail »).
List<String> sidesOf(Iterable<MealComponent> cs) => [for (final c in cs) if (!countsInMeal(c.families)) c.label];

/// Mots d'un petit-déj « par défaut » (avant d'avoir appris ses habitudes).
const kBreakfastKeywords = [
  'pain', 'baguette', 'biscotte', 'brioche', 'cereale', 'muesli', 'flocon', 'avoine', 'galette', 'crepe',
  'oeuf', 'yaourt', 'yogourt', 'skyr', 'fromage blanc', 'lait', 'jambon', 'fromage',
  'fruit', 'banane', 'pomme', 'poire', 'orange', 'clementine', 'mandarine', 'kiwi', 'fraise', 'framboise', 'myrtille',
  'raisin', 'ananas', 'mangue', 'papaye', 'compote', 'jus',
  'beurre', 'confiture', 'miel', 'pate a tartiner',
];

bool _hasWords(String label, String kw) {
  final t = ' ${foldWords(label)} ';
  return kw.split(' ').length == 1
      ? RegExp(' ${RegExp.escape(kw)}[sx]? ').hasMatch(t)
      : t.contains(' $kw ');
}

/// Un produit va-t-il au petit-déj ? Appris (déjà pris un matin), sinon
/// reconnu par ses mots.
bool isBreakfastItem(String label, Set<String> learned) =>
    learned.contains(normLabel(label)) || kBreakfastKeywords.any((k) => _hasWords(label, k));

/// Un repas composé passé ou prévu, pour l'historique des suggestions.
class ComposedMeal {
  final String ymd;
  final String moment;
  final List<MealComponent> components;
  const ComposedMeal(this.ymd, this.moment, this.components);
  String get signature => ([for (final c in components) if (countsInMeal(c.families)) normLabel(c.label)]..sort()).join('+');
}

/// Tous les repas composés connus, du plus récent au plus ancien.
List<ComposedMeal> composedHistory(Map<String, MealWeek> weeks) {
  final out = <ComposedMeal>[];
  for (final w in weeks.values) {
    for (final e in w.slots.entries) {
      if (!e.value.isComposed) continue;
      final i = e.key.indexOf('|');
      if (i < 0) continue;
      out.add(ComposedMeal(e.key.substring(0, i), e.key.substring(i + 1), e.value.components));
    }
  }
  out.sort((a, b) {
    final c = b.ymd.compareTo(a.ymd);
    return c != 0 ? c : kMealMoments.indexOf(b.moment).compareTo(kMealMoments.indexOf(a.moment));
  });
  return out;
}

/// Ce qu'on a déjà pris au petit-déj (mots).
Set<String> learnedBreakfast(List<ComposedMeal> history) => {
      for (final m in history)
        if (m.moment == kBreakfast)
          for (final c in m.components) normLabel(c.label),
    };

/// Les briques possibles pour un créneau : ce qu'on a au placard, par
/// famille (accompagnements compris) ; au petit-déj, seulement ce qui y va
/// (si rien ne va dans une famille, la famille reste vide).
Map<String, List<MealComponent>> optionsFor(Groceries g, String moment, {Set<String> learned = const {}}) {
  final by = pantryByFamily(g);
  final out = <String, List<MealComponent>>{};
  for (final e in by.entries) {
    out[e.key] = [
      for (final p in e.value)
        if (moment != kBreakfast || isBreakfastItem(p.label, learned)) MealComponent(p.label, familiesFor(g, p.label, aisle: p.aisle)),
    ];
  }
  return out;
}

/// Une idée de repas et pourquoi.
class MealIdea {
  final List<MealComponent> components;
  final int score;
  final List<String> reasons; // « champignons à finir »…
  const MealIdea(this.components, this.score, this.reasons);
  String get title => composedTitle(components);
}

int _daysBetween(String a, String b) => DateTime.parse(b).difference(DateTime.parse(a)).inDays;

/// Les meilleures idées pour un créneau (3 au plus), calculées sans IA :
/// 3 familles +3 (2 familles +1) ; un produit Frais ou Fruits et légumes
/// acheté il y a plus de 3 jours +2 (« à finir ») ; combinaison déjà
/// composée +1 ; même protéine qu'au repas précédent −2 (hors petit-déj) ;
/// combinaison identique dans les 3 derniers jours −3.
List<MealIdea> suggestMeals({
  required Groceries g,
  required String ymd,
  required String moment,
  required List<ComposedMeal> history,
  int max = 3,
}) {
  final learned = learnedBreakfast(history);
  final opts = optionsFor(g, moment, learned: learned);
  List<MealComponent?> pool(String f) => [null, ...(opts[f] ?? const []).take(10)];
  // Le repas précédent (le plus récent avant ce créneau, hors petit-déj).
  final before = history.where((m) {
    final c = m.ymd.compareTo(ymd);
    return m.moment != kBreakfast && (c < 0 || (c == 0 && kMealMoments.indexOf(m.moment) < kMealMoments.indexOf(moment)));
  }).firstOrNull;
  final lastProteins = before == null
      ? const <String>{}
      : {for (final c in before.components) if (c.families.contains(kProteines)) normLabel(c.label)};
  final known = {for (final m in history) m.signature};
  final recent = {
    for (final m in history)
      if (m.ymd != ymd || m.moment != moment)
        if (_daysBetween(m.ymd, ymd).abs() <= 3) m.signature,
  };
  String? stale(MealComponent c) {
    final p = g.pantry[normLabel(c.label)];
    if (p == null) return null;
    final fresh = p.aisle == 'Frais' || p.aisle == 'Fruits et légumes';
    final old = p.boughtAt != null && _daysBetween(p.boughtAt!, ymd) > 3;
    if (p.state != PantryState.low && !(fresh && old)) return null;
    return '${c.label.toLowerCase()} à finir';
  }

  final seen = <String>{};
  final ideas = <MealIdea>[];
  for (final pr in pool(kProteines)) {
    for (final fe in pool(kFeculents)) {
      for (final fi in pool(kFibres)) {
        final cs = [pr, fe, fi].whereType<MealComponent>().toList();
        // Une brique à deux familles (lentilles) ne se prend qu'une fois.
        if (cs.map((c) => normLabel(c.label)).toSet().length != cs.length) continue;
        if (!isValidMeal(cs)) continue;
        final ideaSig = ([for (final c in cs) normLabel(c.label)]..sort()).join('+');
        if (!seen.add(ideaSig)) continue;
        var score = coveredFamilies(cs).length == 3 ? 3 : 1;
        final reasons = <String>[];
        for (final c in cs) {
          final s = stale(c);
          if (s != null) {
            score += 2;
            reasons.add(s);
          }
        }
        if (known.contains(ideaSig)) score += 1;
        if (moment != kBreakfast && cs.any((c) => c.families.contains(kProteines) && lastProteins.contains(normLabel(c.label)))) score -= 2;
        if (recent.contains(ideaSig)) score -= 3;
        ideas.add(MealIdea(cs, score, reasons));
      }
    }
  }
  ideas.sort((a, b) {
    final c = b.score.compareTo(a.score);
    return c != 0 ? c : a.title.compareTo(b.title);
  });
  return ideas.take(max).toList();
}
