import 'package:productivitwo_v1/utils/groceries.dart';

/// Mes placards (maquette validée 2026-11-03 « Mes placards ») — logique pure.
/// Ce qu'on a chez soi, rangé par rayon, en trois états (J'en ai · Bientôt
/// fini · Plus rien) ; un ticket ou la caisse repasse les produits achetés en
/// « J'en ai ». `guessAisle` est aligné sur `functions/src/pantry.ts`
/// (**garder alignés**, mêmes mots-clés, même ordre).

/// Mots-clés par rayon, dans l'ordre de test : un rayon plus spécifique passe
/// avant (« sauce tomate » = Épicerie, pas Fruits et légumes ; « jus
/// d'orange » = Boissons). Un mot-clé de plusieurs mots doit se suivre.
const List<(String, List<String>)> kAisleKeywords = [
  ('Ménager', [
    'lessive', 'vaisselle', 'eponge', 'essuie tout', 'sopalin', 'papier toilette', 'sac poubelle', 'poubelle', 'javel',
    'nettoyant', 'detergent', 'adoucissant', 'lave vaisselle', 'desinfectant', 'serpillere', 'allumette', 'ampoule', 'pile',
    'aluminium', 'film alimentaire', 'sac congelation',
  ]),
  ('Hygiène', [
    'dentifrice', 'brosse a dents', 'shampoing', 'shampooing', 'apres shampoing', 'gel douche', 'savon', 'deodorant', 'coton',
    'rasoir', 'mouchoir', 'serviette hygienique', 'tampon', 'creme hydratante', 'creme solaire', 'couche', 'lingette', 'parfum',
    'fil dentaire', 'bain de bouche',
  ]),
  ('Surgelés', ['surgele', 'surgeles', 'glace', 'glacon', 'pizza surgelee', 'frites']),
  ('Boissons', ['eau', 'jus', 'soda', 'coca', 'limonade', 'biere', 'vin', 'sirop', 'cidre', 'champagne', 'tisane']),
  ('Épicerie', [
    'sauce', 'conserve', 'boite', 'compote', 'lait de coco', 'concentre de tomate', 'puree', 'soupe', 'bouillon',
  ]),
  ('Frais', [
    'lait', 'yaourt', 'yogourt', 'beurre', 'creme', 'creme fraiche', 'fromage', 'oeuf', 'jambon', 'lardon', 'poulet', 'boeuf',
    'steak', 'viande', 'hache', 'poisson', 'saumon', 'dinde', 'porc', 'saucisse', 'emmental', 'mozzarella', 'skyr', 'feta',
    'chevre', 'comte', 'gruyere', 'parmesan', 'ricotta', 'tofu', 'pate feuilletee', 'pate brisee', 'cabillaud', 'crevette',
    'escalope', 'merguez', 'chorizo',
    'ribs', 'travers', 'cote', 'bacon', 'filet', 'roti', 'cuisse', 'aiguillette', 'nugget', 'cordon bleu',
    'veau', 'agneau', 'canard', 'gigot', 'blanc de poulet', 'escargot',
  ]),
  ('Fruits et légumes', [
    'banane', 'pomme', 'poire', 'orange', 'citron', 'tomate', 'salade', 'carotte', 'oignon', 'ail', 'pomme de terre', 'patate',
    'courgette', 'poivron', 'champignon', 'avocat', 'fraise', 'raisin', 'legume', 'fruit', 'echalote', 'concombre', 'poireau',
    'epinard', 'brocoli', 'chou', 'kiwi', 'melon', 'persil', 'basilic', 'coriandre', 'aubergine', 'clementine', 'mandarine',
    'peche', 'abricot', 'ananas', 'mangue', 'radis', 'navet', 'betterave', 'haricot vert', 'petit pois', 'mache', 'roquette',
    'gingembre', 'menthe', 'framboise', 'myrtille', 'cerise', 'prune',
  ]),
  ('Épicerie', [
    'pate', 'pates', 'riz', 'farine', 'sucre', 'sel', 'poivre', 'huile', 'vinaigre', 'thon', 'sardine', 'cafe', 'the',
    'cereale', 'biscuit', 'chocolat', 'confiture', 'miel', 'pain', 'lentille', 'semoule', 'epice', 'moutarde', 'ketchup',
    'mayonnaise', 'gateau', 'chips', 'quinoa', 'boulgour', 'pois chiche', 'haricot', 'flocon', 'avoine', 'muesli', 'levure',
    'cacao', 'noix', 'amande', 'noisette', 'olive', 'cornichon', 'bonbon', 'nouille', 'spaghetti', 'tagliatelle', 'farfalle',
    'penne', 'coquillette', 'vermicelle', 'couscous', 'galette', 'cracker', 'tortilla', 'brioche', 'madeleine', 'croquette',
  ]),
];

/// Minuscules, sans accents, « œ » → « oe », mots séparés par un espace.
String foldWords(String s) {
  const from = 'àâäáãåçéèêëíìîïñóòôöõúùûüýÿ';
  const to = 'aaaaaaceeeeiiiinooooouuuuyy';
  final b = StringBuffer();
  for (final ch in s.toLowerCase().replaceAll('œ', 'oe').replaceAll('æ', 'ae').split('')) {
    final i = from.indexOf(ch);
    b.write(i >= 0 ? to[i] : ch);
  }
  return b.toString().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
}

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

/// Le rayon deviné d'un produit par ses mots ; null si rien ne le reconnaît.
String? guessAisle(String label) {
  final tokens = foldWords(label).split(' ').where((t) => t.isNotEmpty).toList();
  if (tokens.isEmpty) return null;
  for (final (aisle, words) in kAisleKeywords) {
    for (final w in words) {
      if (_hasPhrase(tokens, w.split(' '))) return aisle;
    }
  }
  return null;
}

/// Le rayon d'un produit : retenu pour son mot, sinon celui du placard, sinon
/// deviné, sinon « Autre ».
String aisleFor(Groceries g, String label) {
  final k = normLabel(label);
  return g.memory[k]?.aisle ?? g.pantry[k]?.aisle ?? guessAisle(label) ?? kOtherAisle;
}

PantryState nextPantryState(PantryState s) => switch (s) {
      PantryState.have => PantryState.low,
      PantryState.low => PantryState.out,
      PantryState.out => PantryState.have,
    };

String pantryStateLabel(PantryState s) => switch (s) {
      PantryState.have => 'J\'en ai',
      PantryState.low => 'Bientôt fini',
      PantryState.out => 'Plus rien',
    };

/// Pose l'état d'un produit (le crée au besoin, dans son rayon).
Groceries withPantryState(Groceries g, String label, PantryState state, {String? aisle}) {
  final k = normLabel(label);
  if (k.isEmpty) return g;
  final old = g.pantry[k];
  final p = old?.copyWith(state: state, aisle: aisle) ??
      PantryItem(key: k, label: label.trim(), aisle: aisle ?? aisleFor(g, label), state: state);
  return g.copyWith(pantry: {...g.pantry, k: p});
}

/// Après un achat (ticket ou caisse) : chaque produit passe « J'en ai », daté.
Groceries afterPurchase(Groceries g, Iterable<String> labels, String ymd, {Map<String, String> aisles = const {}}) {
  final pantry = {...g.pantry};
  for (final l in labels) {
    final k = normLabel(l);
    if (k.isEmpty) continue;
    final aisle = aisles[k];
    final old = pantry[k];
    pantry[k] = old?.copyWith(state: PantryState.have, boughtAt: ymd, aisle: aisle) ??
        PantryItem(key: k, label: l.trim(), aisle: aisle ?? aisleFor(g, l), boughtAt: ymd);
  }
  return g.copyWith(pantry: pantry);
}

/// Les produits du placard rangés par rayon, dans l'ordre des rayons (puis
/// les rayons inconnus) ; dans un rayon, par libellé.
List<MapEntry<String, List<PantryItem>>> pantryByAisle(Groceries g, {bool Function(PantryItem)? where}) {
  final by = <String, List<PantryItem>>{};
  for (final p in g.pantry.values) {
    if (where != null && !where(p)) continue;
    by.putIfAbsent(p.aisle, () => []).add(p);
  }
  for (final l in by.values) {
    l.sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
  }
  final order = [...g.aisles.where(by.containsKey), ...by.keys.where((k) => !g.aisles.contains(k))];
  return [for (final k in order) MapEntry(k, by[k]!)];
}

/// Ce que le placard demande de racheter : « Plus rien » et « Bientôt fini »,
/// hors produits déjà sur la liste (à prendre ou au panier).
/// Ce que le placard remet tout seul sur la liste : les produits HABITUELS
/// bientôt finis ou épuisés (2026-11-04, retour user : un produit ordinaire à
/// « Plus rien » reste noté au placard sans s'imposer dans les courses).
List<PantryItem> pantryNeeds(Groceries g) {
  final listed = {for (final x in g.items.values) normLabel(x.label)};
  return [
    for (final p in g.pantry.values)
      if (p.staple && p.state != PantryState.have && !listed.contains(p.key)) p,
  ]..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
}

/// L'état d'un produit au placard (null = inconnu, donc pas chez soi).
PantryState? pantryStateOf(Groceries g, String label) => g.pantry[normLabel(label)]?.state;

// ── Rayons ──────────────────────────────────────────────────────────────────

/// Ajoute un rayon (avant « Autre ») ; ignoré s'il existe déjà.
Groceries withAisleAdded(Groceries g, String name) {
  final n = name.trim();
  if (n.isEmpty || g.aisles.any((a) => foldWords(a) == foldWords(n))) return g;
  final list = [...g.aisles];
  final other = list.indexOf(kOtherAisle);
  other < 0 ? list.add(n) : list.insert(other, n);
  return g.copyWith(aisles: list);
}

/// Renomme un rayon partout (placard, liste, mots retenus) ; si le nouveau
/// nom existe déjà, les deux rayons fusionnent.
Groceries withAisleRenamed(Groceries g, String from, String to) {
  final n = to.trim();
  if (n.isEmpty || from == n || !g.aisles.contains(from)) return g;
  final exists = g.aisles.contains(n);
  final aisles = exists ? [for (final a in g.aisles) if (a != from) a] : [for (final a in g.aisles) a == from ? n : a];
  return _moveAisle(g.copyWith(aisles: aisles), from, n);
}

/// Retire un rayon : ses produits passent dans « Autre ». « Autre » reste.
Groceries withAisleRemoved(Groceries g, String name) {
  if (name == kOtherAisle || !g.aisles.contains(name)) return g;
  final aisles = [for (final a in g.aisles) if (a != name) a];
  if (!aisles.contains(kOtherAisle)) aisles.add(kOtherAisle);
  return _moveAisle(g.copyWith(aisles: aisles), name, kOtherAisle);
}

Groceries _moveAisle(Groceries g, String from, String to) => g.copyWith(
      pantry: g.pantry.map((k, p) => MapEntry(k, p.aisle == from ? p.copyWith(aisle: to) : p)),
      items: g.items.map((k, x) => MapEntry(k, x.aisle == from ? x.copyWith(aisle: to) : x)),
      memory: g.memory.map((k, m) => MapEntry(k, m.aisle == from ? GroceryMemory(domainId: m.domainId, projectId: m.projectId, store: m.store, price: m.price, aisle: to) : m)),
    );

// ── Courses par rayon (Finances) ────────────────────────────────────────────

/// Répartit le montant d'une part de ticket entre les rayons de ses lignes,
/// au poids du prix retenu de chaque mot (1 sinon) ; somme juste au centime.
Map<String, int> aisleSplit(int amount, List<String> labels, Map<String, int> prices, Groceries g) {
  if (amount <= 0 || labels.isEmpty) return const {};
  final weights = [for (final l in labels) (prices[normLabel(l)] ?? g.memory[normLabel(l)]?.price ?? 1).toDouble().clamp(1, double.infinity)];
  final sum = weights.fold<double>(0, (a, b) => a + b);
  final raw = [for (final w in weights) amount * w / sum];
  final parts = [for (final r in raw) r.floor()];
  var left = amount - parts.fold<int>(0, (a, b) => a + b);
  final order = List.generate(raw.length, (i) => i)..sort((a, b) => (raw[b] - parts[b]).compareTo(raw[a] - parts[a]));
  for (var k = 0; left > 0; k = (k + 1) % order.length, left--) {
    parts[order[k]]++;
  }
  final out = <String, int>{};
  for (var i = 0; i < labels.length; i++) {
    final a = aisleFor(g, labels[i]);
    out[a] = (out[a] ?? 0) + parts[i];
  }
  return out;
}

// ── Cuisiner avec ce qu'on a (lot 4) ────────────────────────────────────────

/// Un plat face au placard : ce qu'on a (J'en ai ou Bientôt fini), ce qui
/// est bientôt fini, ce qui manque (Plus rien ou inconnu).
class DishReadiness {
  final List<String> have;
  final List<String> low;
  final List<String> missing;
  const DishReadiness({required this.have, required this.low, required this.missing});
  int get total => have.length + missing.length;
  bool get ready => total > 0 && missing.isEmpty;
}

DishReadiness dishReadiness(List<String> ingredientLabels, Groceries g) {
  final have = <String>[], low = <String>[], missing = <String>[];
  for (final l in ingredientLabels) {
    switch (pantryStateOf(g, l)) {
      case PantryState.have:
        have.add(l);
      case PantryState.low:
        have.add(l);
        low.add(l);
      case PantryState.out:
      case null:
        missing.add(l);
    }
  }
  return DishReadiness(have: have, low: low, missing: missing);
}

/// Les plats faisables avec le placard : tout est là d'abord, puis ceux à un
/// ingrédient près ([maxMissing]) ; à égalité, ceux qui utilisent le plus de
/// produits du placard. Un plat sans ingrédient n'est jamais proposé.
List<(T, DishReadiness)> doableDishes<T>(List<T> dishes, List<String> Function(T) ingredientsOf, Groceries g, {int maxMissing = 1}) {
  final out = <(T, DishReadiness)>[];
  for (final d in dishes) {
    final ing = ingredientsOf(d);
    if (ing.isEmpty) continue;
    final r = dishReadiness(ing, g);
    if (r.have.isEmpty || r.missing.length > maxMissing) continue;
    out.add((d, r));
  }
  out.sort((a, b) {
    final m = a.$2.missing.length.compareTo(b.$2.missing.length);
    return m != 0 ? m : b.$2.have.length.compareTo(a.$2.have.length);
  });
  return out;
}

/// Après avoir mangé : les ingrédients du plat qu'on a au placard, à
/// proposer « Tu as fini quelque chose ? ».
List<String> finishCandidates(List<String> ingredientLabels, Groceries g) => [
      for (final l in ingredientLabels)
        if (pantryStateOf(g, l) case PantryState.have || PantryState.low) l,
    ];
