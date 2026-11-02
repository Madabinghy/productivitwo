import 'package:productivitwo_v1/utils/finances.dart' show Expense, Finances, monthOf;
import 'package:productivitwo_v1/utils/meal_plan.dart' show ShoppingLine;

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
  const GroceryItem({
    required this.id,
    required this.label,
    this.qty = '',
    this.domainId,
    this.projectId,
    this.store = kMenuStore,
    this.source = 'hand',
    this.inBasket = false,
  });

  GroceryItem copyWith({String? label, String? qty, String? domainId, String? projectId, String? store, bool? inBasket, bool clearProject = false, bool clearDomain = false}) => GroceryItem(
        id: id,
        label: label ?? this.label,
        qty: qty ?? this.qty,
        domainId: clearDomain ? null : (domainId ?? this.domainId),
        projectId: clearProject ? null : (projectId ?? this.projectId),
        store: store ?? this.store,
        source: source,
        inBasket: inBasket ?? this.inBasket,
      );

  Map<String, dynamic> toJson() => {
        'label': label,
        if (qty.isNotEmpty) 'qty': qty,
        if (domainId != null) 'domainId': domainId,
        if (projectId != null) 'projectId': projectId,
        'store': store,
        if (source != 'hand') 'source': source,
        if (inBasket) 'inBasket': true,
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
    );
  }
}

/// Ce que l'app retient d'un mot : son domaine, son projet, son endroit, son prix.
class GroceryMemory {
  final String? domainId;
  final String? projectId;
  final String? store;
  final int? price;
  const GroceryMemory({this.domainId, this.projectId, this.store, this.price});

  GroceryMemory merge({String? domainId, String? projectId, String? store, int? price}) => GroceryMemory(
        domainId: domainId ?? this.domainId,
        projectId: projectId ?? this.projectId,
        store: store ?? this.store,
        price: price ?? this.price,
      );

  Map<String, dynamic> toJson() => {
        if (domainId != null) 'domainId': domainId,
        if (projectId != null) 'projectId': projectId,
        if (store != null) 'store': store,
        if (price != null) 'price': price,
      };

  static GroceryMemory from(Object? raw) {
    if (raw is! Map) return const GroceryMemory();
    return GroceryMemory(
      domainId: raw['domainId'] as String?,
      projectId: raw['projectId'] as String?,
      store: raw['store'] as String?,
      price: (raw['price'] as num?)?.toInt(),
    );
  }
}

class Groceries {
  final Map<String, GroceryItem> items;
  final Map<String, GroceryMemory> memory;
  final List<String> stores;
  /// Ingrédients du menu déjà passés en caisse, par lundi : ils quittent la liste.
  final Map<String, Set<String>> boughtMenu;
  const Groceries({this.items = const {}, this.memory = const {}, this.stores = kDefaultStores, this.boughtMenu = const {}});

  Groceries copyWith({Map<String, GroceryItem>? items, Map<String, GroceryMemory>? memory, List<String>? stores, Map<String, Set<String>>? boughtMenu}) =>
      Groceries(items: items ?? this.items, memory: memory ?? this.memory, stores: stores ?? this.stores, boughtMenu: boughtMenu ?? this.boughtMenu);

  Map<String, dynamic> toJson() => {
        'items': {for (final x in items.values) x.id: x.toJson()},
        'memory': memory.map((k, v) => MapEntry(k, v.toJson())),
        'stores': stores,
        'bought': boughtMenu.map((k, v) => MapEntry(k, v.toList()..sort())),
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
  return Groceries(items: items, memory: memory, stores: stores.isEmpty ? kDefaultStores : stores, boughtMenu: bought);
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
  });
  String get key => itemId ?? 'menu:$menuKey';
}

/// Fond les ingrédients du menu de la semaine ([menuLines], cochés dans
/// [menuChecked]) et les lignes à la main. Un ingrédient prend le domaine
/// retenu pour son mot, sinon [menuDomainId] ; son endroit retenu, sinon le
/// supermarché. Un mot à la main qui est aussi un ingrédient du menu n'est
/// montré qu'une fois (la ligne du menu, qui dit d'où il vient).
List<GroceryRow> groceryRows({
  required List<ShoppingLine> menuLines,
  required Set<String> menuChecked,
  required Groceries g,
  String? menuDomainId,
  String? monday,
}) {
  final out = <GroceryRow>[];
  final menuWords = <String>{};
  final bought = monday == null ? const <String>{} : (g.boughtMenu[monday] ?? const <String>{});
  for (final l in menuLines) {
    if (bought.contains(l.key)) {
      menuWords.add(normLabel(l.label));
      continue;
    }
    final m = g.memory[normLabel(l.label)];
    menuWords.add(normLabel(l.label));
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
    ));
  }
  return out;
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
