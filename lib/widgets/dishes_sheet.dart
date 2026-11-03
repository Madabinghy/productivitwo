import 'package:productivitwo_v1/widgets/undo_snack.dart' show ClosingSnackBar;
import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/utils/groceries.dart' show PantryState, normLabel;
import 'package:productivitwo_v1/utils/pantry.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/duration_fmt.dart' show fmtMin;
import 'package:productivitwo_v1/utils/meals.dart';
import 'package:productivitwo_v1/widgets/fiche.dart' show showFiche;

const kMealAccent = Color(0xFF7CC96A);

/// « Mes plats » (maquette validée 2026-11-01 « Repas et menu », écran 4) :
/// la bibliothèque, les plus faits d'abord, puis ceux pas faits depuis
/// longtemps ; « + Nouveau » ; tap = la fiche du plat.
Future<void> showDishesSheet(BuildContext context, {required FirestoreSync sync, AppLogic? logic}) {
  return showFiche<void>(context, builder: (ctx, scroll) => DishesSheet(sync: sync, scroll: scroll, logic: logic));
}

class DishesSheet extends StatefulWidget {
  final FirestoreSync sync;
  final ScrollController? scroll;
  /// Recevoir les plats sans Firestore (tests).
  final Stream<List<Recipe>>? recipes;
  /// Placards (2026-11-03) : « Avec ce que tu as » ; null = sans placard.
  final AppLogic? logic;
  const DishesSheet({super.key, required this.sync, this.scroll, this.recipes, this.logic});

  @override
  State<DishesSheet> createState() => _DishesSheetState();
}

class _DishesSheetState extends State<DishesSheet> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final mute = cs.onSurface.withValues(alpha: .55);
    return StreamBuilder<List<Recipe>>(
      stream: widget.recipes ?? widget.sync.streamRecipes(),
      builder: (ctx, snap) {
        final all = snap.data ?? const <Recipe>[];
        final now = DateTime.now();
        final q = _q.trim().toLowerCase();
        final shown = q.isEmpty ? all : all.where((r) => r.title.toLowerCase().contains(q) || r.ingredients.any((i) => i.label.toLowerCase().contains(q))).toList();
        final s = sortDishes(shown, now);
        Widget section(String t, List<Recipe> list) => list.isEmpty
            ? const SizedBox.shrink()
            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Padding(
                  padding: const EdgeInsets.only(top: 18, bottom: 6),
                  child: Text(t, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: .8, color: mute)),
                ),
                Material(
                  color: cs.surfaceContainerHighest.withValues(alpha: .35),
                  borderRadius: BorderRadius.circular(16),
                  clipBehavior: Clip.antiAlias,
                  child: Column(children: [
                    for (final (i, r) in list.indexed) ...[
                      if (i > 0) Divider(height: 1, color: cs.onSurface.withValues(alpha: .07)),
                      ListTile(
                        title: Text(r.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text(
                          [
                            '${r.portions} portion${r.portions > 1 ? 's' : ''}',
                            if (r.minutes != null) fmtMin(r.minutes!),
                            '${r.ingredients.length} ingrédient${r.ingredients.length > 1 ? 's' : ''}',
                            if (r.lastCookedAt != null && now.difference(r.lastCookedAt!).inDays >= kStaleDishDays) sinceLabel(r.lastCookedAt!, now),
                          ].join(' · '),
                          style: TextStyle(fontSize: 12, color: mute),
                        ),
                        trailing: r.timesCooked > 0 ? Text('×${r.timesCooked}', style: TextStyle(color: mute, fontWeight: FontWeight.w700)) : null,
                        onTap: () => showDishSheet(context, sync: widget.sync, recipe: r, all: all, logic: widget.logic),
                      ),
                    ],
                  ]),
                ),
              ]);
        return ListView(controller: widget.scroll, padding: const EdgeInsets.fromLTRB(20, 8, 20, 32), children: [
          Row(children: [
            const Expanded(child: Text('Mes plats', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900))),
            FilledButton.tonalIcon(
              onPressed: () => showDishSheet(context, sync: widget.sync, all: all, logic: widget.logic),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Nouveau'),
            ),
          ]),
          const SizedBox(height: 4),
          Text('Ta bibliothèque : ce que tu cuisines vraiment. Un plat se saisit une fois, ses ingrédients feront les courses.',
              style: TextStyle(fontSize: 13, color: mute)),
          const SizedBox(height: 10),
          TextField(
            onChanged: (v) => setState(() => _q = v),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search_rounded),
              hintText: 'Chercher un plat ou un ingrédient',
              isDense: true,
              filled: true,
              fillColor: cs.surfaceContainerHighest.withValues(alpha: .35),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
          ),
          if (all.isEmpty && snap.connectionState != ConnectionState.waiting)
            Padding(
              padding: const EdgeInsets.only(top: 24),
              child: Text('Aucun plat pour l’instant. Commence par ceux que tu fais le plus souvent.', textAlign: TextAlign.center, style: TextStyle(color: mute)),
            ),
          ..._withWhatYouHave(cs, mute, shown, all),
          section('LES PLUS FAITS', s.often),
          section('PAS FAITS DEPUIS LONGTEMPS', s.stale),
          section(s.often.isEmpty && s.stale.isEmpty ? 'TES PLATS' : 'PAS ENCORE CUISINÉS', s.fresh),
        ]);
      },
    );
  }
}

extension on _DishesSheetState {
  /// « Avec ce que tu as » : les plats faisables avec le placard (tout est là,
  /// ou à un ingrédient près), 5 au plus.
  List<Widget> _withWhatYouHave(ColorScheme cs, Color mute, List<Recipe> shown, List<Recipe> all) {
    final logic = widget.logic;
    if (logic == null || logic.groceries.pantry.isEmpty) return const [];
    final doable = doableDishes<Recipe>(shown, (r) => [for (final i in r.ingredients) i.label], logic.groceries).take(5).toList();
    if (doable.isEmpty) return const [];
    return [
      Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 6),
        child: Text('AVEC CE QUE TU AS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: .8, color: mute)),
      ),
      Material(
        color: cs.surfaceContainerHighest.withValues(alpha: .35),
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          for (final (i, d) in doable.indexed) ...[
            if (i > 0) Divider(height: 1, color: cs.onSurface.withValues(alpha: .07)),
            ListTile(
              key: ValueKey('doable-${d.$1.id}'),
              title: Text(d.$1.title, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(
                d.$2.missing.isEmpty
                    ? 'tous les ingrédients au placard${d.$2.low.isNotEmpty ? ' · ${d.$2.low.first} bientôt fini' : ''}'
                    : 'il manque ${d.$2.missing.join(', ')}',
                style: TextStyle(fontSize: 12, color: mute),
              ),
              trailing: Text('${d.$2.have.length} / ${d.$2.total}',
                  style: TextStyle(fontWeight: FontWeight.w800, color: d.$2.missing.isEmpty ? kMealAccent : const Color(0xFFFAB219))),
              onTap: () => showDishSheet(context, sync: widget.sync, recipe: d.$1, all: all, logic: logic),
            ),
          ],
        ]),
      ),
    ];
  }
}

/// La fiche d'un plat (écran 5) : portions, temps, ingrédients avec leurs
/// quantités, suggestions tirées des autres plats. [recipe] null = nouveau.
Future<void> showDishSheet(BuildContext context, {required FirestoreSync sync, Recipe? recipe, List<Recipe> all = const [], AppLogic? logic}) {
  return showFiche<void>(context, builder: (ctx, scroll) => DishSheet(sync: sync, recipe: recipe, all: all, scroll: scroll, logic: logic));
}

class DishSheet extends StatefulWidget {
  final FirestoreSync sync;
  final Recipe? recipe;
  final List<Recipe> all;
  final ScrollController? scroll;
  /// Placards (2026-11-03) : chaque ingrédient face au placard ; null = sans.
  final AppLogic? logic;
  const DishSheet({super.key, required this.sync, this.recipe, this.all = const [], this.scroll, this.logic});

  @override
  State<DishSheet> createState() => _DishSheetState();
}

class _DishSheetState extends State<DishSheet> {
  late final TextEditingController _title = TextEditingController(text: widget.recipe?.title ?? '');
  final _add = TextEditingController();
  late int _portions = widget.recipe?.portions ?? 2;
  late int? _minutes = widget.recipe?.minutes;
  late final List<ShoppingItem> _ings = [for (final i in widget.recipe?.ingredients ?? const <ShoppingItem>[]) ShoppingItem(label: i.label, qty: i.qty)];
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _add.dispose();
    super.dispose();
  }

  void _addLine(String text) {
    final parsed = parseIngredients(text);
    if (parsed.isEmpty) return;
    setState(() {
      for (final p in parsed) {
        final i = _ings.indexWhere((x) => x.label.toLowerCase() == p.label.toLowerCase());
        if (i >= 0) {
          if (p.qty.isNotEmpty) _ings[i].qty = p.qty;
        } else {
          _ings.add(p);
        }
      }
      _add.clear();
    });
  }

  Future<void> _editQty(ShoppingItem i) async {
    final c = TextEditingController(text: i.qty);
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(i.label),
        content: TextField(controller: c, autofocus: true, decoration: const InputDecoration(hintText: 'Quantité (500 g, 2, 1 boîte…)'), onSubmitted: (v) => Navigator.pop(ctx, v)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('OK')),
        ],
      ),
    );
    if (v != null) setState(() => i.qty = v.trim());
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showClosingSnackBar(const SnackBar(content: Text('Donne un nom au plat.')));
      return;
    }
    if (_add.text.trim().isNotEmpty) _addLine(_add.text);
    setState(() => _saving = true);
    final r = widget.recipe ?? Recipe(title: title);
    r
      ..title = title
      ..portions = _portions
      ..minutes = _minutes
      ..ingredients = [..._ings];
    try {
      await widget.sync.saveRecipe(r);
    } catch (_) {}
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final r = widget.recipe;
    if (r == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Retirer « ${r.title} » ?'),
        content: const Text('Il disparaît de Mes plats.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Retirer')),
        ],
      ),
    );
    if (ok != true) return;
    r.deleted = true;
    try {
      await widget.sync.saveRecipe(r);
    } catch (_) {}
    if (mounted) Navigator.of(context).pop();
  }

  /// ✓ j'en ai · ! bientôt fini · ✕ manque (placards, 2026-11-03).
  Widget _pantryMark(String label) {
    final st = pantryStateOf(widget.logic!.groceries, label);
    final (t, c, tip) = switch (st) {
      PantryState.have => ('✓', kMealAccent, 'j\'en ai'),
      PantryState.low => ('!', const Color(0xFFFAB219), 'bientôt fini'),
      _ => ('✕', const Color(0xFFE66767), st == PantryState.out ? 'plus rien' : 'pas au placard'),
    };
    return Tooltip(
      message: tip,
      child: SizedBox(width: 22, child: Text(t, style: TextStyle(fontWeight: FontWeight.w900, color: c))),
    );
  }

  List<Widget> _missingButton() {
    final logic = widget.logic;
    if (logic == null || _ings.isEmpty || logic.groceries.pantry.isEmpty) return const [];
    final r = dishReadiness([for (final i in _ings) i.label], logic.groceries);
    final listed = {for (final x in logic.groceries.items.values) normLabel(x.label)};
    final toAdd = [for (final i in _ings) if (r.missing.contains(i.label) && !listed.contains(normLabel(i.label))) i];
    if (r.missing.isEmpty) {
      return [
        const SizedBox(height: 8),
        Text('Tout est au placard.', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: kMealAccent)),
      ];
    }
    if (toAdd.isEmpty) {
      return [
        const SizedBox(height: 8),
        Text('Ce qui manque est déjà sur la liste de courses.', style: TextStyle(fontSize: 12.5, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .55))),
      ];
    }
    return [
      const SizedBox(height: 8),
      OutlinedButton.icon(
        key: const Key('dish-add-missing'),
        onPressed: () async {
          for (final i in toAdd) {
            await logic.addGrocery(label: i.label, qty: i.qty);
          }
          if (!mounted) return;
          setState(() {});
          ScaffoldMessenger.of(context).showClosingSnackBar(SnackBar(
            content: Text('${toAdd.length == 1 ? toAdd.first.label : '${toAdd.length} ingrédients'} sur la liste de courses'),
            duration: const Duration(seconds: 3),
          ));
        },
        icon: const Icon(Icons.add_shopping_cart_rounded, size: 18),
        label: Text(toAdd.length == 1 ? 'Ajouter ${toAdd.first.label.toLowerCase()} à la liste' : 'Ajouter les ${toAdd.length} manquants à la liste'),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final mute = cs.onSurface.withValues(alpha: .55);
    final sugg = ingredientSuggestions(widget.all, _ings, excludeId: widget.recipe?.id);
    Widget label(String t, [String? right]) => Padding(
          padding: const EdgeInsets.only(top: 18, bottom: 6),
          child: Row(children: [
            Expanded(child: Text(t, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: .8, color: mute))),
            if (right != null) Text(right, style: TextStyle(fontSize: 11.5, color: mute)),
          ]),
        );
    final box = BoxDecoration(color: cs.surfaceContainerHighest.withValues(alpha: .35), borderRadius: BorderRadius.circular(14));
    return ListView(controller: widget.scroll, padding: const EdgeInsets.fromLTRB(20, 8, 20, 32), children: [
      TextField(
        controller: _title,
        autofocus: widget.recipe == null,
        textCapitalization: TextCapitalization.sentences,
        style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900),
        decoration: const InputDecoration(hintText: 'Nom du plat', border: InputBorder.none),
      ),
      Row(children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
            decoration: box,
            child: Row(children: [
              Text('PORTIONS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: mute)),
              const Spacer(),
              IconButton(visualDensity: VisualDensity.compact, onPressed: _portions > 1 ? () => setState(() => _portions--) : null, icon: const Icon(Icons.remove_rounded)),
              Text('$_portions', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              IconButton(visualDensity: VisualDensity.compact, onPressed: _portions < 12 ? () => setState(() => _portions++) : null, icon: const Icon(Icons.add_rounded)),
            ]),
          ),
        ),
      ]),
      label('TEMPS'),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final m in const [15, 20, 30, 45, 60, 90])
          ChoiceChip(label: Text(fmtMin(m)), selected: _minutes == m, onSelected: (on) => setState(() => _minutes = on ? m : null)),
      ]),
      label('INGRÉDIENTS', 'pour $_portions portion${_portions > 1 ? 's' : ''}'),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: box,
        child: Column(children: [
          for (final (k, i) in _ings.indexed) ...[
            if (k > 0) Divider(height: 1, color: cs.onSurface.withValues(alpha: .07)),
            Row(children: [
              if (widget.logic != null) _pantryMark(i.label),
              Expanded(child: Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(i.label, style: const TextStyle(fontSize: 14.5)))),
              InkWell(
                onTap: () => _editQty(i),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                  child: Text(i.qty.isEmpty ? 'quantité' : i.qty, style: TextStyle(color: i.qty.isEmpty ? mute.withValues(alpha: .4) : mute)),
                ),
              ),
              IconButton(visualDensity: VisualDensity.compact, icon: Icon(Icons.close_rounded, size: 18, color: mute), onPressed: () => setState(() => _ings.removeAt(k))),
            ]),
          ],
          if (_ings.isNotEmpty) Divider(height: 1, color: cs.onSurface.withValues(alpha: .07)),
          TextField(
            controller: _add,
            textInputAction: TextInputAction.done,
            onSubmitted: _addLine,
            decoration: InputDecoration(
              hintText: '+ ingrédient… (2 oignons, 1 kg pâtes)',
              border: InputBorder.none,
              suffixIcon: IconButton(icon: const Icon(Icons.add_circle_outline_rounded), onPressed: () => _addLine(_add.text)),
            ),
          ),
        ]),
      ),
      ..._missingButton(),
      if (sugg.isNotEmpty) ...[
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final s in sugg) ActionChip(label: Text('+ $s'), onPressed: () => setState(() => _ings.add(ShoppingItem(label: s)))),
        ]),
        const SizedBox(height: 4),
        Text('Proposés d’après tes autres plats.', style: TextStyle(fontSize: 12, color: mute)),
      ],
      const SizedBox(height: 18),
      FilledButton(
        style: FilledButton.styleFrom(backgroundColor: kMealAccent, foregroundColor: const Color(0xFF0F1A0C), minimumSize: const Size.fromHeight(50)),
        onPressed: _saving ? null : _save,
        child: Text(widget.recipe == null ? 'Créer le plat' : 'Enregistrer', style: const TextStyle(fontWeight: FontWeight.w800)),
      ),
      if (widget.recipe != null) ...[
        if (widget.recipe!.timesCooked > 0)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text('Cuisiné ${widget.recipe!.timesCooked} fois${widget.recipe!.lastCookedAt != null ? ' · dernière ${sinceLabel(widget.recipe!.lastCookedAt!, DateTime.now())}' : ''}',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, color: mute)),
          ),
        TextButton(onPressed: _delete, child: const Text('Retirer ce plat')),
      ],
    ]);
  }
}
