import 'package:productivitwo_v1/utils/groceries.dart';
import 'package:productivitwo_v1/utils/pantry.dart' show foldWords, aisleFor;

/// Repas en 3 familles (spec 2026-11-04, `docs/specs/repas-3-familles-2026-11/README.md`)
/// — lot 1 : la famille de chaque produit. Un repas se compose de briques
/// prises dans trois familles (protéines · féculents · fibres) ; deux sur
/// trois suffisent. Ce qui n'est dans aucune (ail, oignon, sauces, épices…)
/// est un ACCOMPAGNEMENT : affiché, jamais compté.
///
/// La famille se règle comme le rayon : retenue pour le mot
/// (`data/meta.groceries.families.<mot>`, réglée par l'utilisateur ou donnée
/// par Claude au ticket), sinon devinée par mots-clés, sinon accompagnement.
/// `guessFamilies` est aligné sur `functions/src/meal_families.ts`
/// (**garder alignés** : mêmes mots-clés, même ordre, même règle).

const kProteines = 'proteines';
const kFeculents = 'feculents';
const kFibres = 'fibres';
const kAccompagnement = 'accompagnement';

/// Les trois familles qui comptent, dans l'ordre d'affichage.
const kMealFamilies = [kProteines, kFeculents, kFibres];

const kFamilyLabels = {
  kProteines: 'Protéines',
  kFeculents: 'Féculents',
  kFibres: 'Fibres',
  kAccompagnement: 'Accompagnements',
};

String familyLabel(String f) => kFamilyLabels[f] ?? f;

/// Rayons qui ne se mangent pas (ou se boivent) : jamais dans un repas.
const kNonFoodAisles = {'Ménager', 'Hygiène', 'Boissons'};

/// Mots-clés par famille. Le mot-clé le plus LONG (en mots) qui se trouve dans
/// le libellé gagne (« pomme de terre » bat « pomme », « haricot vert » bat
/// « haricot ») ; à égalité, la première famille de cette liste (« sauce
/// tomate » = accompagnement). Une entrée peut porter deux familles
/// (légumineuses : féculent ET protéine).
const List<(List<String>, List<String>)> kFamilyKeywords = [
  ([kAccompagnement], [
    'sauce', 'concentre de tomate', 'coulis', 'moutarde', 'ketchup', 'mayonnaise', 'vinaigrette', 'pesto', 'epice', 'curry',
    'colombo', 'paprika', 'sel', 'poivre', 'huile', 'vinaigre', 'bouillon', 'ail', 'oignon', 'echalote', 'cive', 'persil',
    'basilic', 'coriandre', 'menthe', 'thym', 'laurier', 'gingembre', 'piment', 'herbe', 'beurre', 'creme', 'creme fraiche',
    'lait de coco', 'sucre', 'farine', 'levure', 'confiture', 'miel', 'pate a tartiner', 'cornichon', 'olive', 'capre', 'chocolat',
    'cacao', 'cafe', 'the', 'gateau', 'tartelette', 'biscuit', 'madeleine', 'bonbon', 'chips', 'glace', 'dessert',
  ]),
  ([kFeculents, kProteines], [
    'lentille', 'pois chiche', 'haricot rouge', 'haricot blanc', 'pois rouge', 'pois d angole', 'feve', 'flageolet',
  ]),
  ([kFeculents], [
    'pomme de terre', 'patate', 'patate douce', 'igname', 'dachine', 'madere', 'manioc', 'banane plantain', 'plantain',
    'fruit a pain', 'riz', 'pate', 'pates', 'spaghetti', 'tagliatelle', 'farfalle', 'penne', 'coquillette',
    'fusilli', 'macaroni', 'lasagne', 'nouille', 'vermicelle', 'gnocchi', 'semoule', 'couscous', 'quinoa', 'boulgour', 'ble',
    'polenta', 'pain', 'baguette', 'biscotte', 'brioche', 'tortilla', 'wrap', 'galette', 'cracker', 'cereale', 'flocon',
    'avoine', 'muesli', 'frites', 'puree', 'farine de manioc', 'cassave', 'dombre',
  ]),
  ([kProteines], [
    'oeuf', 'jambon', 'lardon', 'bacon', 'poulet', 'blanc de poulet', 'dinde', 'canard', 'boeuf', 'veau', 'agneau', 'gigot',
    'porc', 'cote', 'cote de porc', 'ribs', 'travers', 'roti', 'filet', 'cuisse', 'aiguillette', 'escalope', 'steak', 'viande',
    'hache', 'saucisse', 'merguez', 'chorizo', 'boudin', 'nugget', 'cordon bleu', 'poisson', 'saumon', 'thon', 'sardine',
    'maquereau', 'cabillaud', 'morue', 'colin', 'merlu', 'crevette', 'calamar', 'escargot', 'lambi', 'chatrou', 'ouassou',
    'tofu', 'tempeh', 'seitan', 'fromage', 'emmental', 'mozzarella', 'feta', 'chevre', 'comte', 'gruyere', 'parmesan', 'ricotta',
    'yaourt', 'yogourt', 'skyr', 'fromage blanc', 'lait',
  ]),
  ([kFibres], [
    'legume', 'haricot vert', 'petit pois', 'salade', 'mache', 'roquette', 'carotte', 'tomate', 'courgette', 'poivron',
    'champignon', 'brocoli', 'chou', 'chou fleur', 'epinard', 'concombre', 'aubergine', 'poireau', 'radis', 'navet',
    'betterave', 'christophine', 'giraumon', 'potiron', 'citrouille', 'gombo', 'avocat', 'crudite', 'ratatouille', 'soupe',
    'fruit', 'banane', 'pomme', 'poire', 'orange', 'citron', 'clementine', 'mandarine', 'kiwi', 'fraise', 'framboise',
    'myrtille', 'cerise', 'raisin', 'melon', 'pasteque', 'ananas', 'mangue', 'papaye', 'goyave', 'peche', 'abricot', 'prune',
    'compote',
  ]),
];

bool _sameWord(String token, String kw) => token == kw || token == '${kw}s' || token == '${kw}x';

bool _hasPhrase(List<String> tokens, List<String> kw) {
  for (var i = 0; i + kw.length <= tokens.length; i++) {
    var ok = true;
    for (var j = 0; j < kw.length && ok; j++) {
      ok = _sameWord(tokens[i + j], kw[j]);
    }
    if (ok) return true;
  }
  return false;
}

/// Les familles devinées d'un produit par ses mots : `[accompagnement]`,
/// une famille, ou deux (légumineuses) ; vide si rien ne le reconnaît.
List<String> guessFamilies(String label) {
  final tokens = foldWords(label).split(' ').where((t) => t.isNotEmpty).toList();
  if (tokens.isEmpty) return const [];
  List<String> best = const [];
  var bestLen = 0;
  for (final (fams, words) in kFamilyKeywords) {
    for (final w in words) {
      final kw = w.split(' ');
      if (kw.length > bestLen && _hasPhrase(tokens, kw)) {
        best = fams;
        bestLen = kw.length;
      }
    }
  }
  return best;
}

/// `"feculents,proteines"` ↔ liste ; ignore ce qui n'est pas une famille.
List<String> parseFamilies(Object? raw) {
  final parts = raw is List ? raw.map((e) => '$e') : '${raw ?? ''}'.split(',');
  final out = <String>[];
  for (final p in parts.map((s) => s.trim())) {
    if ((kMealFamilies.contains(p) || p == kAccompagnement) && !out.contains(p)) out.add(p);
  }
  // Accompagnement exclut les autres.
  if (out.contains(kAccompagnement) && out.length > 1) out.remove(kAccompagnement);
  return out;
}

String formatFamilies(List<String> fams) => parseFamilies(fams).join(',');

/// Les familles d'un produit : retenues pour son mot, sinon devinées ; un
/// produit d'un rayon non alimentaire n'en a aucune (liste vide) ; un produit
/// inconnu est un accompagnement.
List<String> familiesFor(Groceries g, String label, {String? aisle}) {
  final k = normLabel(label);
  final set = parseFamilies(g.families[k]);
  if (set.isNotEmpty) return set;
  final a = aisle ?? g.pantry[k]?.aisle ?? aisleFor(g, label);
  if (kNonFoodAisles.contains(a)) return const [];
  final guessed = guessFamilies(label);
  return guessed.isEmpty ? const [kAccompagnement] : guessed;
}

/// Le produit compte-t-il dans un repas (au moins une des trois familles) ?
bool countsInMeal(List<String> fams) => fams.any(kMealFamilies.contains);

/// Les produits du placard qu'on a (J'en ai ou Bientôt fini), rangés par
/// famille dans l'ordre protéines · féculents · fibres · accompagnements ; un
/// produit à deux familles apparaît dans les deux. Hors alimentaire exclu.
Map<String, List<PantryItem>> pantryByFamily(Groceries g) {
  final out = {for (final f in [...kMealFamilies, kAccompagnement]) f: <PantryItem>[]};
  for (final p in g.pantry.values) {
    if (p.state == PantryState.out) continue;
    for (final f in familiesFor(g, p.label, aisle: p.aisle)) {
      out[f]?.add(p);
    }
  }
  for (final l in out.values) {
    l.sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
  }
  return out;
}

/// Retient la famille d'un mot (vide = revenir à l'automatique).
Groceries withFamilies(Groceries g, String label, List<String> fams) {
  final k = normLabel(label);
  if (k.isEmpty) return g;
  final next = {...g.families};
  final v = formatFamilies(fams);
  if (v.isEmpty) {
    next.remove(k);
  } else {
    next[k] = v;
  }
  return g.copyWith(families: next);
}
