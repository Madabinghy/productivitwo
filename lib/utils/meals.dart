import 'package:productivitwo_v1/models.dart';

/// Repas et menu (maquette validée 2026-11-01 « Repas et menu ») — lot 1 :
/// la bibliothèque de plats. Un plat = nom, portions, temps, ingrédients avec
/// leurs quantités ; c'est la seule chose à saisir, une fois.

const _units = ['kg', 'g', 'mg', 'l', 'cl', 'ml', 'boîte', 'boîtes', 'boite', 'boites', 'sachet', 'sachets', 'tranche', 'tranches', 'pot', 'pots', 'botte', 'bottes', 'c.', 'cs', 'cc', 'gousse', 'gousses', 'pincée', 'paquet', 'paquets'];

String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// « 2 oignons » → (Oignons, 2) ; « 1 kg pâtes » → (Pâtes, 1 kg) ;
/// « Bœuf haché 500 g » → (Bœuf haché, 500 g) ; « sel » → (Sel, '').
ShoppingItem parseIngredientLine(String line) {
  final t = line.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (t.isEmpty) return ShoppingItem(label: '');
  final lead = RegExp(r'^(\d+(?:[.,]\d+)?)\s*([^\s\d]+)?\s*(?:de |d\x27|d’)?(.*)$').firstMatch(t);
  if (lead != null && lead.group(3) != null) {
    final n = lead.group(1)!;
    final u = lead.group(2);
    final rest = lead.group(3)!.trim();
    if (u != null && _units.contains(u.toLowerCase()) && rest.isNotEmpty) {
      return ShoppingItem(label: _cap(rest.replaceFirst(RegExp(r'^(de |d\x27|d’)'), '')), qty: '$n $u');
    }
    final label = [if (u != null) u, if (rest.isNotEmpty) rest].join(' ').trim();
    if (label.isNotEmpty) return ShoppingItem(label: _cap(label.replaceFirst(RegExp(r'^(de |d\x27|d’)'), '')), qty: n);
  }
  final tail = RegExp(r'^(.*?)\s+(\d+(?:[.,]\d+)?\s*[^\s\d]*)$').firstMatch(t);
  if (tail != null && tail.group(1)!.isNotEmpty) {
    final q = tail.group(2)!.trim();
    final unit = q.replaceFirst(RegExp(r'^\d+(?:[.,]\d+)?\s*'), '');
    if (unit.isEmpty || _units.contains(unit.toLowerCase())) return ShoppingItem(label: _cap(tail.group(1)!), qty: q);
  }
  return ShoppingItem(label: _cap(t));
}

/// Plusieurs ingrédients sur une ligne : « 2 oignons, 1 kg pâtes ».
List<ShoppingItem> parseIngredients(String text) =>
    [for (final part in text.split(RegExp(r'[,;\n]'))) parseIngredientLine(part)].where((i) => i.label.isNotEmpty).toList();

String _key(String label) => label.trim().toLowerCase();

/// Ingrédients des autres plats, du plus fréquent au moins, absents de [current].
List<String> ingredientSuggestions(List<Recipe> recipes, List<ShoppingItem> current, {String? excludeId, int max = 6}) {
  final have = {for (final i in current) _key(i.label)};
  final count = <String, int>{};
  final label = <String, String>{};
  for (final r in recipes) {
    if (r.id == excludeId || r.deleted) continue;
    for (final i in r.ingredients) {
      final k = _key(i.label);
      if (k.isEmpty || have.contains(k)) continue;
      count[k] = (count[k] ?? 0) + 1;
      label[k] ??= i.label;
    }
  }
  final keys = count.keys.toList()..sort((a, b) => count[b]!.compareTo(count[a]!));
  return [for (final k in keys.take(max)) label[k]!];
}

const kStaleDishDays = 14;

/// Mes plats : les plus faits d'abord ; « pas faits depuis longtemps » =
/// déjà cuisinés, mais pas depuis [kStaleDishDays] jours.
({List<Recipe> often, List<Recipe> stale, List<Recipe> fresh}) sortDishes(List<Recipe> recipes, DateTime now) {
  final live = recipes.where((r) => !r.deleted).toList();
  bool isStale(Recipe r) => r.lastCookedAt != null && now.difference(r.lastCookedAt!).inDays >= kStaleDishDays;
  final stale = live.where(isStale).toList()..sort((a, b) => a.lastCookedAt!.compareTo(b.lastCookedAt!));
  final often = live.where((r) => !isStale(r) && r.timesCooked > 0).toList()..sort((a, b) => b.timesCooked.compareTo(a.timesCooked));
  final fresh = live.where((r) => !isStale(r) && r.timesCooked == 0).toList()..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
  return (often: often, stale: stale, fresh: fresh);
}

/// « il y a 3 semaines » / « il y a 16 j ».
String sinceLabel(DateTime at, DateTime now) {
  final d = now.difference(at).inDays;
  if (d < 1) return 'aujourd’hui';
  if (d < 21) return 'il y a $d j';
  return 'il y a ${d ~/ 7} semaines';
}
