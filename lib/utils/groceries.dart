import 'package:productivitwo_v1/utils/finances.dart' show Expense, Finances, monthOf;
import 'package:productivitwo_v1/utils/meal_plan.dart' show ShoppingLine;
import 'package:productivitwo_v1/utils/pantry.dart' show aisleFor, pantryNeeds;

/// Courses générales (maquette validée 2026-11-02 « Courses générales ») —
/// logique pure. UNE liste : les ingrédients du menu de la semaine (dérivés,
/// voir `shoppingFor`) + les lignes ajoutées à la main ou par Claude, chacune
/// avec un domaine de vie, parfois un projet, et un endroit où l'acheter. À la
/// caisse, un total est réparti par domaine (et projet) en dépenses Finances.
///
/// Stockage `data/meta.groceries` : `{items: {<id>: {label, qty?, domainId?,
/// projectId?, store, source?, inBasket?}}, memory: {<mot>: {domainId?,
/// projectId?, store?, price?}}, stores: [..]}`. Prix en CENTIMES.

const kDefaultStores = ['Supermarché', 'Bricolage', 'Pharmacie', 'Marché'];
const kMenuStore = 'Supermarché';

String normLabel(String s) => s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

class GroceryItem {
  final String id;
  final String label;
  final String qty;
  final String? domainId;
  final String? projectId;
  final String store;
  /// `hand` (à la main) · `claude` (via le connecteur).
  final String source;
  final bool inBasket;
  /// Rayon (Épicerie, Frais…) ; null = deviné à l'affichage (`aisleFor`).
  final String? aisle;
  const GroceryItem({
    required this.id,
    required this.label,
    this.qty = '',
    this.domainId,
    this.projectId,
    this.store = kMenuStore,
    this.source = 'hand',
    this.inBasket = false,
    this.aisle,
  });

  GroceryItem copyWith({String? label, String? qty, String? domainId, String? projectId, String? store, bool? inBasket, String? aisle, bool clearProject = false, bool clearDomain = false}) => GroceryItem(
        id: id,
        label: label ?? this.label,
        qty: qty ?? this.qty,
        domainId: clearDomain ? null : (domainId ?? this.domainId),
        projectId: clearProject ? null : (projectId ?? this.projectId),
        store: store ?? this.store,
        source: source,
        inBasket: inBasket ?? this.inBasket,
        aisle: aisle ?? this.aisle,
      );

  Map<String, dynamic> toJson() => {
        'label': label,
        if (qty.isNotEmpty) 'qty': qty,
        if (domainId != null) 'domainId': domainId,
        if (projectId != null) 'projectId': projectId,
        'store': store,
        if (source != 'hand') 'source': source,
        if (inBasket) 'inBasket': true,
        if (aisle != null) 'aisle': aisle,
      };

  static GroceryItem? from(String id, Object? raw) {
    if (raw is! Map || raw['label'] == null) return null;
    return GroceryItem(
      id: id,
      label: '${raw['label']}',
      qty: '${raw['qty'] ?? ''}',
      domainId: raw['domainId'] as String?,
      projectId: raw['projectId'] as String?,
      store: (raw['store'] as String?) ?? kMenuStore,
      source: (raw['source'] as String?) ?? 'hand',
      inBasket: raw['inBasket'] == true,
      aisle: raw['aisle'] as String?,
    );
  }
}

/// Ce que l'app retient d'un mot : son domaine, son projet, son endroit, son prix.
class GroceryMemory {
  final String? domainId;
  final String? projectId;
  final String? store;
  final int? price;
  /// Rayon retenu pour ce mot (placards, 2026-11-03).
  final String? aisle;
  const GroceryMemory({this.domainId, this.projectId, this.store, this.price, this.aisle});

  GroceryMemory merge({String? domainId, String? projectId, String? store, int? price, String? aisle}) => GroceryMemory(
        domainId: domainId ?? this.domainId,
        projectId: projectId ?? this.projectId,
        store: store ?? this.store,
        price: price ?? this.price,
        aisle: aisle ?? this.aisle,
      );

  Map<String, dynamic> toJson() => {
        if (domainId != null) 'domainId': domainId,
        if (projectId != null) 'projectId': projectId,
        if (store != null) 'store': store,
        if (price != null) 'price': price,
        if (aisle != null) 'aisle': aisle,
      };

  static GroceryMemory from(Object? raw) {
    if (raw is! Map) return const GroceryMemory();
    return GroceryMemory(
      domainId: raw['domainId'] as String?,
      projectId: raw['projectId'] as String?,
      store: raw['store'] as String?,
      price: (raw['price'] as num?)?.toInt(),
      aisle: raw['aisle'] as String?,
    );
  }
}

/// Rayons par défaut (placards, maquette validée 2026-11-03). Ordre = ordre
/// d'affichage ; « Autre » reçoit ce qu'aucun rayon ne reconnaît.
const kDefaultAisles = ['Épicerie', 'Frais', 'Fruits et légumes', 'Surgelés', 'Boissons', 'Ménager', 'Hygiène', 'Autre'];
const kOtherAisle = 'Autre';

/// État d'un produit au placard : trois seulement, jamais de quantité.
enum PantryState { have, low, out }

PantryState pantryStateFrom(Object? raw) => switch (raw) {
      'low' => PantryState.low,
      'out' => PantryState.out,
      _ => PantryState.have,
    };

/// Un produit de « Mes placards », clé = `normLabel(label)`.
class PantryItem {
  final String key;
  final String label;
  final String aisle;
  final PantryState state;
  /// Produit habituel : revient sur la liste dès qu'il n'y en a plus.
  final bool staple;
  /// Dernier achat (YYYY-MM-DD), posé par un ticket ou la caisse.
  final String? boughtAt;
  const PantryItem({required this.key, required this.label, required this.aisle, this.state = PantryState.have, this.staple = false, this.boughtAt});

  PantryItem copyWith({String? label, String? aisle, PantryState? state, bool? staple, String? boughtAt}) => PantryItem(
        key: key,
        label: label ?? this.label,
        aisle: aisle ?? this.aisle,
        state: state ?? this.state,
        staple: staple ?? this.staple,
        boughtAt: boughtAt ?? this.boughtAt,
      );

  Map<String, dynamic> toJson() => {
        'label': label,
        'aisle': aisle,
        'state': state.name,
        if (staple) 'staple': true,
        if (boughtAt != null) 'boughtAt': boughtAt,
      };

  static PantryItem? from(String key, Object? raw) {
    if (raw is! Map || raw['label'] == null) return null;
    return PantryItem(
      key: key,
      label: '${raw['label']}',
      aisle: (raw['aisle'] as String?) ?? kOtherAisle,
      state: pantryStateFrom(raw['state']),
      staple: raw['staple'] == true,
      boughtAt: raw['boughtAt'] as String?,
    );
  }
}

class Groceries {
  final Map<String, GroceryItem> items;
  final Map<String, GroceryMemory> memory;
  final List<String> stores;
  /// Ingrédients du menu déjà passés en caisse, par lundi : ils quittent la liste.
  final Map<String, Set<String>> boughtMenu;
  /// Ingrédients du menu retirés de la liste (ou détachés en ligne libre), par lundi (2026-11-03).
  final Map<String, Set<String>> skippedMenu;
  /// Mes placards (2026-11-03) : ce qu'on a chez soi, par `normLabel`.
  final Map<String, PantryItem> pantry;
  /// Rayons, dans l'ordre d'affichage.
  final List<String> aisles;
  /// Repas en 3 familles (2026-11-04) : familles retenues par mot
  /// (`"proteines"`, `"feculents,proteines"`…) — `utils/meal_families.dart`.
  final Map<String, String> families;
  const Groceries({
    this.items = const {},
    this.memory = const {},
    this.stores = kDefaultStores,
    this.boughtMenu = const {},
    this.skippedMenu = const {},
    this.pantry = const {},
    this.aisles = kDefaultAisles,
    this.families = const {},
  });

  Groceries copyWith({
    Map<String, GroceryItem>? items,
    Map<String, GroceryMemory>? memory,
    List<String>? stores,
    Map<String, Set<String>>? boughtMenu,
    Map<String, Set<String>>? skippedMenu,
    Map<String, PantryItem>? pantry,
    List<String>? aisles,
    Map<String, String>? families,
  }) =>
      Groceries(
        items: items ?? this.items,
        memory: memory ?? this.memory,
        stores: stores ?? this.stores,
        boughtMenu: boughtMenu ?? this.boughtMenu,
        skippedMenu: skippedMenu ?? this.skippedMenu,
        pantry: pantry ?? this.pantry,
        aisles: aisles ?? this.aisles,
        families: families ?? this.families,
      );

  Map<String, dynamic> toJson() => {
        'items': {for (final x in items.values) x.id: x.toJson()},
        'memory': memory.map((k, v) => MapEntry(k, v.toJson())),
        'stores': stores,
        'bought': boughtMenu.map((k, v) => MapEntry(k, v.toList()..sort())),
        'skipped': skippedMenu.map((k, v) => MapEntry(k, v.toList()..sort())),
        'pantry': {for (final p in pantry.values) p.key: p.toJson()},
        'aisles': aisles,
        if (families.isNotEmpty) 'families': families,
      };
}

Groceries parseGroceries(Object? raw) {
  if (raw is! Map) return const Groceries();
  final items = <String, GroceryItem>{};
  if (raw['items'] is Map) {
    for (final e in (raw['items'] as Map).entries) {
      final x = GroceryItem.from('${e.key}', e.value);
      if (x != null) items[x.id] = x;
    }
  }
  final memory = <String, GroceryMemory>{};
  if (raw['memory'] is Map) {
    for (final e in (raw['memory'] as Map).entries) {
      memory['${e.key}'] = GroceryMemory.from(e.value);
    }
  }
  final stores = raw['stores'] is List ? [for (final s in raw['stores'] as List) '$s'] : const <String>[];
  final bought = <String, Set<String>>{};
  if (raw['bought'] is Map) {
    for (final e in (raw['bought'] as Map).entries) {
      if (e.value is List) bought['${e.key}'] = {for (final k in e.value as List) '$k'};
    }
  }
  final skipped = <String, Set<String>>{};
  if (raw['skipped'] is Map) {
    for (final e in (raw['skipped'] as Map).entries) {
      if (e.value is List) skipped['${e.key}'] = {for (final k in e.value as List) '$k'};
    }
  }
  final pantry = <String, PantryItem>{};
  if (raw['pantry'] is Map) {
    for (final e in (raw['pantry'] as Map).entries) {
      final p = PantryItem.from('${e.key}', e.value);
      if (p != null) pantry[p.key] = p;
    }
  }
  final aisles = raw['aisles'] is List ? [for (final s in raw['aisles'] as List) '$s'] : const <String>[];
  final families = <String, String>{
    if (raw['families'] is Map)
      for (final e in (raw['families'] as Map).entries)
        if (e.value is String && (e.value as String).isNotEmpty) '${e.key}': e.value as String,
  };
  return Groceries(
    items: items,
    memory: memory,
    stores: stores.isEmpty ? kDefaultStores : stores,
    boughtMenu: bought,
    skippedMenu: skipped,
    pantry: pantry,
    aisles: aisles.isEmpty ? kDefaultAisles : aisles,
    families: families,
  );
}

/// Les réglages proposés pour un mot tapé : ce que l'app en a retenu, sinon
/// le domaine du projet choisi, sinon le dernier domaine utilisé.
GroceryMemory guessFor(Groceries g, String label, {String? lastDomainId, String? projectDomainId}) {
  final m = g.memory[normLabel(label)];
  return GroceryMemory(
    domainId: m?.domainId ?? projectDomainId ?? lastDomainId,
    projectId: m?.projectId,
    store: m?.store ?? kMenuStore,
    price: m?.price,
  );
}

// ── La caisse ───────────────────────────────────────────────────────────────

/// Une ligne qui passe en caisse (à la main ou ingrédient du menu).
class CheckoutLine {
  final String label;
  final String? domainId;
  final String? projectId;
  /// Prix estimé (dernier vu), centimes ; null = inconnu.
  final int? price;
  /// Id de la ligne à la main (null pour un ingrédient du menu).
  final String? itemId;
  /// Clé de l'ingrédient du menu (null pour une ligne à la main).
  final String? menuKey;
  const CheckoutLine({required this.label, this.domainId, this.projectId, this.price, this.itemId, this.menuKey});
}

/// La part d'un ticket pour un domaine (et un projet).
class TicketShare {
  final String? domainId;
  final String? projectId;
  final int amount;
  final List<String> labels;
  const TicketShare({this.domainId, this.projectId, required this.amount, required this.labels});
  TicketShare withAmount(int a) => TicketShare(domainId: domainId, projectId: projectId, amount: a, labels: labels);
  String get key => '${domainId ?? ''}|${projectId ?? ''}';
}

/// Poids de chaque ligne : son prix estimé, sinon la moyenne des prix connus,
/// sinon 1 (parts égales).
List<double> _weights(List<CheckoutLine> lines) {
  final known = [for (final l in lines) if (l.price != null && l.price! > 0) l.price!];
  final avg = known.isEmpty ? 1.0 : known.reduce((a, b) => a + b) / known.length;
  return [for (final l in lines) (l.price != null && l.price! > 0) ? l.price!.toDouble() : avg];
}

/// Répartit [total] entre les montants proportionnels à [weights], la somme
/// tombant juste au centime (plus forts restes).
List<int> _apportion(int total, List<double> weights) {
  final sum = weights.fold<double>(0, (s, w) => s + w);
  if (weights.isEmpty) return const [];
  if (sum <= 0) return _apportion(total, [for (final _ in weights) 1.0]);
  final raw = [for (final w in weights) total * w / sum];
  final out = [for (final r in raw) r.floor()];
  var left = total - out.fold<int>(0, (s, v) => s + v);
  final order = List.generate(weights.length, (i) => i)..sort((a, b) => (raw[b] - out[b]).compareTo(raw[a] - out[a]));
  for (var i = 0; left > 0; i = (i + 1) % order.length, left--) {
    out[order[i]]++;
  }
  return out;
}

/// Le ticket réparti par (domaine, projet), dans l'ordre du plus gros au plus petit.
List<TicketShare> splitTicket(int total, List<CheckoutLine> lines) {
  if (lines.isEmpty || total <= 0) return const [];
  final w = _weights(lines);
  final groups = <String, List<int>>{};
  for (var i = 0; i < lines.length; i++) {
    groups.putIfAbsent('${lines[i].domainId ?? ''}|${lines[i].projectId ?? ''}', () => []).add(i);
  }
  final keys = groups.keys.toList();
  final amounts = _apportion(total, [for (final k in keys) groups[k]!.fold<double>(0, (s, i) => s + w[i])]);
  final out = [
    for (var j = 0; j < keys.length; j++)
      TicketShare(
        domainId: lines[groups[keys[j]]!.first].domainId,
        projectId: lines[groups[keys[j]]!.first].projectId,
        amount: amounts[j],
        labels: [for (final i in groups[keys[j]]!) lines[i].label],
      ),
  ];
  out.sort((a, b) => b.amount.compareTo(a.amount));
  return out;
}

/// Corrige la part [index] à [amount] ; les autres se répartissent le reste
/// au prorata de ce qu'elles avaient (le total ne bouge pas).
List<TicketShare> adjustShare(List<TicketShare> shares, int index, int amount) {
  final total = shares.fold<int>(0, (s, x) => s + x.amount);
  final a = amount.clamp(0, total);
  final others = [for (var i = 0; i < shares.length; i++) if (i != index) i];
  if (others.isEmpty) return [shares[index].withAmount(total)];
  final rest = _apportion(total - a, [for (final i in others) shares[i].amount.toDouble() + .0001]);
  final out = [...shares];
  out[index] = shares[index].withAmount(a);
  for (var k = 0; k < others.length; k++) {
    out[others[k]] = shares[others[k]].withAmount(rest[k]);
  }
  return out;
}

/// Prix appris de chaque ligne : sa part dans la part de son groupe, au
/// prorata de son poids. Mot normalisé → centimes. Un prix déjà connu fait la
/// moyenne avec le nouveau (ça s'affine sans sauter).
Map<String, int> learnedPrices(List<CheckoutLine> lines, List<TicketShare> shares, Map<String, GroceryMemory> memory) {
  final w = _weights(lines);
  final out = <String, int>{};
  for (final s in shares) {
    final idx = [for (var i = 0; i < lines.length; i++) if (lines[i].domainId == s.domainId && lines[i].projectId == s.projectId) i];
    if (idx.isEmpty) continue;
    final parts = _apportion(s.amount, [for (final i in idx) w[i]]);
    for (var k = 0; k < idx.length; k++) {
      final key = normLabel(lines[idx[k]].label);
      final old = memory[key]?.price;
      out[key] = old == null ? parts[k] : ((old + parts[k]) / 2).round();
    }
  }
  return out;
}

// ── Finances par domaine de vie ─────────────────────────────────────────────

/// Dépenses du mois de [todayYmd] (jusqu'à aujourd'hui) par domaine ; clé ''
/// = sans domaine. Triées du plus gros au plus petit.
List<MapEntry<String, int>> spentByDomain(Finances f, String todayYmd) {
  final month = monthOf(todayYmd);
  final by = <String, int>{};
  for (final x in f.expenses.values) {
    if (monthOf(x.ymd) != month || x.ymd.compareTo(todayYmd) > 0) continue;
    final k = x.domainId ?? '';
    by[k] = (by[k] ?? 0) + x.amount;
  }
  return by.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
}

/// Dépenses du mois par projet (seulement celles qui en portent un).
List<MapEntry<String, int>> spentByProject(Finances f, String todayYmd) {
  final month = monthOf(todayYmd);
  final by = <String, int>{};
  for (final Expense x in f.expenses.values) {
    if (x.projectId == null || monthOf(x.ymd) != month || x.ymd.compareTo(todayYmd) > 0) continue;
    by[x.projectId!] = (by[x.projectId!] ?? 0) + x.amount;
  }
  return by.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
}

/// Coût estimé d'un plat d'après les prix vus aux courses (null si aucun
/// ingrédient n'a de prix connu) ; [known] = ingrédients avec un prix.
({int cents, int known, int total})? dishCost(List<String> ingredientLabels, Map<String, GroceryMemory> memory) {
  var cents = 0, known = 0;
  for (final l in ingredientLabels) {
    final p = memory[normLabel(l)]?.price;
    if (p != null) {
      cents += p;
      known++;
    }
  }
  if (known == 0) return null;
  return (cents: cents, known: known, total: ingredientLabels.length);
}


// ── La liste affichée ───────────────────────────────────────────────────────

/// Une ligne de LA liste : un ingrédient du menu (`menuKey`) ou une ligne à la
/// main / via Claude (`itemId`).
class GroceryRow {
  final String label;
  final String qty;
  final String? domainId;
  final String? projectId;
  final String store;
  /// `menu` · `hand` · `claude`.
  final String source;
  /// Plats d'où vient un ingrédient du menu.
  final List<String> from;
  final bool inBasket;
  final String? itemId;
  final String? menuKey;
  /// Rayon (placards, 2026-11-03).
  final String aisle;
  /// Ligne proposée par le placard (bientôt fini / plus rien) : la clé du produit.
  final String? pantryKey;
  /// État au placard d'une ligne proposée par lui.
  final PantryState? pantryState;
  const GroceryRow({
    required this.label,
    this.qty = '',
    this.domainId,
    this.projectId,
    required this.store,
    required this.source,
    this.from = const [],
    this.inBasket = false,
    this.itemId,
    this.menuKey,
    this.aisle = kOtherAisle,
    this.pantryKey,
    this.pantryState,
  });
  String get key => itemId ?? (pantryKey != null ? 'pantry:$pantryKey' : 'menu:$menuKey');
}

/// Fond les ingrédients du menu de la semaine ([menuLines], cochés dans
/// [menuChecked]), les lignes à la main et ce que le placard demande de
/// racheter. Un ingrédient prend le domaine retenu pour son mot, sinon
/// [menuDomainId] ; son endroit retenu, sinon le supermarché. Un mot à la main
/// qui est aussi un ingrédient du menu n'est montré qu'une fois (la ligne du
/// menu). Placards (2026-11-03) : un ingrédient du menu qu'on a (« J'en ai »)
/// n'est pas listé (`menuCoveredByPantry`) ; un produit « Bientôt fini » ou
/// « Plus rien » qui n'est pas déjà sur la liste arrive (`source: pantry`).
List<GroceryRow> groceryRows({
  required List<ShoppingLine> menuLines,
  required Set<String> menuChecked,
  required Groceries g,
  String? menuDomainId,
  String? monday,
}) {
  final out = <GroceryRow>[];
  final menuWords = <String>{};
  final bought = monday == null
      ? const <String>{}
      : {...?g.boughtMenu[monday], ...?g.skippedMenu[monday]};
  for (final l in menuLines) {
    final w = normLabel(l.label);
    if (bought.contains(l.key)) {
      menuWords.add(w);
      continue;
    }
    if (g.pantry[w]?.state == PantryState.have && !menuChecked.contains(l.key)) {
      menuWords.add(w);
      continue;
    }
    final m = g.memory[w];
    menuWords.add(w);
    out.add(GroceryRow(
      label: l.label,
      qty: l.qty,
      domainId: m?.domainId ?? menuDomainId,
      projectId: m?.projectId,
      store: m?.store ?? kMenuStore,
      source: 'menu',
      from: l.from,
      inBasket: menuChecked.contains(l.key),
      menuKey: l.key,
      aisle: aisleFor(g, l.label),
      pantryState: g.pantry[w]?.state,
    ));
  }
  for (final x in g.items.values) {
    if (menuWords.contains(normLabel(x.label))) continue;
    out.add(GroceryRow(
      label: x.label,
      qty: x.qty,
      domainId: x.domainId,
      projectId: x.projectId,
      store: x.store,
      source: x.source,
      inBasket: x.inBasket,
      itemId: x.id,
      aisle: x.aisle ?? aisleFor(g, x.label),
      pantryState: g.pantry[normLabel(x.label)]?.state,
    ));
  }
  for (final p in pantryNeeds(g)) {
    if (menuWords.contains(p.key) || bought.contains(pantryRowKey(p.key))) continue;
    final m = g.memory[p.key];
    out.add(GroceryRow(
      label: p.label,
      domainId: m?.domainId,
      projectId: m?.projectId,
      store: m?.store ?? kMenuStore,
      source: 'pantry',
      aisle: p.aisle,
      pantryKey: p.key,
      pantryState: p.state,
    ));
  }
  return out;
}

/// Clé d'une ligne du placard écartée « pas cette semaine » (rangée avec les
/// lignes du menu écartées, `skippedMenu.<lundi>`).
String pantryRowKey(String key) => 'pantry:$key';

/// Les ingrédients du menu de la semaine qu'on a déjà au placard (« J'en ai »).
List<ShoppingLine> menuCoveredByPantry(List<ShoppingLine> menuLines, Groceries g, {Set<String> menuChecked = const {}}) => [
      for (final l in menuLines)
        if (g.pantry[normLabel(l.label)]?.state == PantryState.have && !menuChecked.contains(l.key)) l,
    ];

/// Les lignes d'un endroit groupées par rayon, dans l'ordre des rayons ; dans
/// un rayon, par libellé.
List<MapEntry<String, List<GroceryRow>>> rowsByAisle(List<GroceryRow> rows, List<String> aisles) {
  final by = <String, List<GroceryRow>>{};
  for (final r in rows) {
    by.putIfAbsent(r.aisle, () => []).add(r);
  }
  for (final l in by.values) {
    l.sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
  }
  final order = [...aisles.where(by.containsKey), ...by.keys.where((k) => !aisles.contains(k))];
  return [for (final k in order) MapEntry(k, by[k]!)];
}

/// Les lignes groupées par endroit, dans l'ordre des endroits connus, puis
/// les autres ; dans un endroit, par libellé.
List<MapEntry<String, List<GroceryRow>>> rowsByStore(List<GroceryRow> rows, List<String> stores) {
  final by = <String, List<GroceryRow>>{};
  for (final r in rows) {
    by.putIfAbsent(r.store, () => []).add(r);
  }
  for (final l in by.values) {
    l.sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
  }
  final order = [...stores.where(by.containsKey), ...by.keys.where((k) => !stores.contains(k))];
  return [for (final k in order) MapEntry(k, by[k]!)];
}

/// Lignes du panier → lignes de caisse (avec le prix retenu de chaque mot).
List<CheckoutLine> checkoutLinesOf(Iterable<GroceryRow> rows, Groceries g) => [
      for (final r in rows)
        if (r.inBasket) CheckoutLine(label: r.label, domainId: r.domainId, projectId: r.projectId, price: g.memory[normLabel(r.label)]?.price, itemId: r.itemId, menuKey: r.menuKey),
    ];
