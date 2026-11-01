import 'package:productivitwo_v1/models.dart';

/// Repas et menu — lot 2 (maquette validée 2026-11-01) : poser les plats sur la
/// semaine et en tirer la liste de courses. Stocké dans `data/meta.meals`
/// `{plans: {<lundi>: {<ymd|midi|soir>: {recipeId?, title, portions, out?}}},
/// shopping: {<lundi>: {checked: [clés], extra: [{label, qty}]}}}`.

const kMealMoments = ['midi', 'soir'];

String mealKey(String ymd, String moment) => '$ymd|$moment';

class PlannedMeal {
  final String? recipeId;
  final String title;
  final int portions;
  final bool out; // dehors / libre
  const PlannedMeal({this.recipeId, required this.title, this.portions = 1, this.out = false});

  Map<String, dynamic> toJson() => {
        if (recipeId != null) 'recipeId': recipeId,
        'title': title,
        'portions': portions,
        if (out) 'out': true,
      };

  static PlannedMeal? from(Object? raw) {
    if (raw is! Map) return null;
    return PlannedMeal(
      recipeId: raw['recipeId'] as String?,
      title: (raw['title'] as String?) ?? '',
      portions: ((raw['portions'] as num?)?.toInt() ?? 1).clamp(1, 12),
      out: raw['out'] == true,
    );
  }
}

class MealWeek {
  final Map<String, PlannedMeal> slots;
  final Set<String> checked;
  final List<ShoppingItem> extra;
  const MealWeek({this.slots = const {}, this.checked = const {}, this.extra = const []});
}

/// `data/meta.meals` → semaine par lundi.
Map<String, MealWeek> parseMeals(Object? raw) {
  if (raw is! Map) return const {};
  final plans = raw['plans'] is Map ? raw['plans'] as Map : const {};
  final shopping = raw['shopping'] is Map ? raw['shopping'] as Map : const {};
  final mondays = {...plans.keys.map((k) => '$k'), ...shopping.keys.map((k) => '$k')};
  return {
    for (final m in mondays)
      m: MealWeek(
        slots: {
          if (plans[m] is Map)
            for (final e in (plans[m] as Map).entries)
              if (PlannedMeal.from(e.value) != null) '${e.key}': PlannedMeal.from(e.value)!,
        },
        checked: {
          if (shopping[m] is Map && (shopping[m] as Map)['checked'] is List)
            for (final k in (shopping[m] as Map)['checked'] as List) '$k',
        },
        extra: [
          if (shopping[m] is Map && (shopping[m] as Map)['extra'] is List)
            for (final x in (shopping[m] as Map)['extra'] as List)
              if (x is Map) ShoppingItem.from(x),
        ],
      ),
  };
}

/// Les restes : un plat de n portions posé sur un repas remplit les n − 1
/// midis suivants restés vides. Clé du repas
/// rempli → clé du repas qui cuisine.
Map<String, String> leftoversOf(Map<String, PlannedMeal> slots, List<String> days) {
  final order = [for (final d in days) for (final m in kMealMoments) mealKey(d, m)];
  final out = <String, String>{};
  for (var i = 0; i < order.length; i++) {
    final p = slots[order[i]];
    if (p == null || p.out || p.portions <= 1) continue;
    var left = p.portions - 1;
    // Les restes vont aux midis suivants (ils s'emportent), jamais sur un
    // repas déjà occupé.
    for (var j = i + 1; j < order.length && left > 0; j++) {
      final k = order[j];
      if (!k.endsWith('|midi') || slots[k] != null || out.containsKey(k)) continue;
      out[k] = order[i];
      left--;
    }
  }
  return out;
}

class ShoppingLine {
  final String key; // libellé en minuscules
  final String label;
  final String qty;
  final List<String> from; // plats d'où vient la ligne
  final bool manual;
  const ShoppingLine(this.key, this.label, this.qty, this.from, {this.manual = false});
}

final _num = RegExp(r'^(\d+(?:[.,]\d+)?)\s*(.*)$');

/// « 500 g » + « 500 g » = « 1 kg » ; « 2 » + « 1 » = « 3 » ; unités
/// différentes : « 500 g + 1 boîte ».
String sumQty(List<String> qtys) {
  final byUnit = <String, double>{};
  final others = <String>[];
  for (final q in qtys.map((q) => q.trim()).where((q) => q.isNotEmpty)) {
    final m = _num.firstMatch(q);
    if (m == null) {
      if (!others.contains(q)) others.add(q);
      continue;
    }
    var v = double.parse(m.group(1)!.replaceAll(',', '.'));
    var u = m.group(2)!.trim().toLowerCase();
    if (u == 'kg') {
      v *= 1000;
      u = 'g';
    } else if (u == 'l') {
      v *= 100;
      u = 'cl';
    } else if (u == 'ml') {
      v /= 10;
      u = 'cl';
    }
    byUnit[u] = (byUnit[u] ?? 0) + v;
  }
  String fmt(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1).replaceAll('.', ',');
  final parts = <String>[
    for (final e in byUnit.entries)
      if (e.key == 'g' && e.value >= 1000)
        '${fmt(e.value / 1000)} kg'
      else if (e.key == 'cl' && e.value >= 100)
        '${fmt(e.value / 100)} l'
      else
        [fmt(e.value), if (e.key.isNotEmpty) e.key].join(' '),
    ...others,
  ];
  return parts.join(' + ');
}

/// La liste de courses de la semaine : les ingrédients de chaque plat posé
/// (une fois par plat posé, les restes n'ajoutent rien), additionnés, avec
/// les plats d'où ils viennent ; puis les ajouts à la main.
List<ShoppingLine> shoppingFor(MealWeek week, List<Recipe> recipes) {
  final byId = {for (final r in recipes) r.id: r};
  final byTitle = {for (final r in recipes) r.title.toLowerCase(): r};
  final qty = <String, List<String>>{};
  final label = <String, String>{};
  final from = <String, List<String>>{};
  for (final p in week.slots.values) {
    if (p.out) continue;
    final r = (p.recipeId != null ? byId[p.recipeId] : null) ?? byTitle[p.title.toLowerCase()];
    if (r == null || r.deleted) continue;
    for (final i in r.ingredients) {
      final k = i.label.trim().toLowerCase();
      if (k.isEmpty) continue;
      label[k] ??= i.label.trim();
      (qty[k] ??= []).add(i.qty);
      final f = from[k] ??= [];
      if (!f.contains(r.title)) f.add(r.title);
    }
  }
  final keys = label.keys.toList()..sort((a, b) => a.compareTo(b));
  return [
    for (final k in keys) ShoppingLine(k, label[k]!, sumQty(qty[k]!), from[k]!),
    for (final x in week.extra) ShoppingLine('+${x.label.trim().toLowerCase()}', x.label, x.qty, const [], manual: true),
  ];
}
