import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/domain_colors.dart';
import 'package:productivitwo_v1/utils/engagement_stats.dart' show ymdOf;
import 'package:productivitwo_v1/utils/groceries.dart';
import 'package:productivitwo_v1/utils/pantry.dart' show aisleFor;
import 'package:productivitwo_v1/utils/meal_day.dart' show isBalancedMealRoutine, isCookActivity;
import 'package:productivitwo_v1/utils/meal_plan.dart';
import 'package:productivitwo_v1/widgets/fiche.dart' show showFiche;
import 'package:productivitwo_v1/widgets/grocery_shop_screen.dart' show showGroceryShop;
import 'package:productivitwo_v1/widgets/pantry_sheet.dart' show aisleColor, showPantryItemEditor, showPantrySheet;
import 'package:productivitwo_v1/widgets/undo_snack.dart' show ClosingSnackBar;

/// Feuille « Courses » (maquette validée 2026-11-02 « Courses générales »,
/// lot 2) : LA liste — ingrédients du menu de la semaine + lignes à la main /
/// via Claude, rangées par endroit, pastille du domaine de vie, étiquettes
/// « menu » / projet / « via Claude » ; ajout par le mot (retenu → direct).

const kGroceryAccent = Color(0xFF5FD4C4);
const kGroceryInk = Color(0xFF08140E);
const _kMenu = Color(0xFF9BE08A);
const _kProject = Color(0xFF9DB8FF);
const _kClaude = Color(0xFFFFD27A);

/// Domaine des ingrédients du menu : celui de la routine Repas équilibré,
/// sinon de l'activité Cuisiner, sinon un domaine « Santé ».
String? menuDomainOf(AppLogic logic) {
  final st = logic.state;
  final r = st.activities.where((a) => !a.deleted && isBalancedMealRoutine(a)).firstOrNull ??
      st.activities.where((a) => !a.deleted && isCookActivity(a)).firstOrNull;
  return r?.domainId ?? st.activeDomains.where((d) => d.name.toLowerCase().contains('santé')).firstOrNull?.id;
}

Future<void> showGroceriesSheet(BuildContext context, {required AppLogic logic, required FirestoreSync sync}) {
  return showFiche<void>(
    context,
    builder: (ctx, scroll) => GroceriesSheet(
      logic: logic,
      sync: sync,
      scroll: scroll,
      onShop: (store, recipes) => showGroceryShop(ctx, logic: logic, store: store, recipes: recipes),
    ),
  );
}

class GroceriesSheet extends StatefulWidget {
  final AppLogic logic;
  final FirestoreSync sync;
  final ScrollController? scroll;
  final Stream<List<Recipe>>? recipes;
  /// Ouvre le mode « en magasin » (lot 3) ; null = bouton absent.
  final void Function(String store, List<Recipe> recipes)? onShop;
  const GroceriesSheet({super.key, required this.logic, required this.sync, this.scroll, this.recipes, this.onShop});

  @override
  State<GroceriesSheet> createState() => _GroceriesSheetState();
}

class _GroceriesSheetState extends State<GroceriesSheet> {
  late final Stream<List<Recipe>> _recipes = widget.recipes ?? widget.sync.streamRecipes();
  List<Recipe> _all = const [];
  final _add = TextEditingController();
  bool _basketOpen = false;
  AppLogic get logic => widget.logic;

  @override
  void initState() {
    super.initState();
    logic.addListener(_onLogic);
  }

  @override
  void dispose() {
    logic.removeListener(_onLogic);
    _add.dispose();
    super.dispose();
  }

  void _onLogic() {
    if (mounted) setState(() {});
  }

  String get _monday {
    final t = logic.livedToday;
    return ymdOf(DateTime(t.year, t.month, t.day - (t.weekday - 1)));
  }

  Future<void> _submit() async {
    final t = _add.text.trim();
    if (t.isEmpty) return;
    _add.clear();
    final known = logic.groceries.memory[normLabel(t)];
    if (known != null && known.domainId != null) {
      final x = await logic.addGrocery(label: t);
      if (!mounted) return;
      final dom = logic.state.activeDomains.where((d) => d.id == x.domainId).firstOrNull?.name;
      ScaffoldMessenger.of(context).showClosingSnackBar(SnackBar(
        content: Text('${x.label} · ${[if (dom != null) dom, x.store].join(' · ')}'),
        duration: const Duration(seconds: 3),
        action: SnackBarAction(label: 'Modifier', onPressed: () => showGroceryEditor(context, logic: logic, item: logic.groceries.items[x.id])),
      ));
      return;
    }
    await showGroceryEditor(context, logic: logic, label: t);
  }

  void _toggle(GroceryRow r) {
    if (r.pantryKey != null) {
      logic.basketPantryRow(r);
      return;
    }
    if (r.itemId != null) {
      logic.setGroceryInBasket(r.itemId!, !r.inBasket);
      return;
    }
    final week = logic.mealWeek(_monday);
    final c = {...week.checked};
    c.contains(r.menuKey) ? c.remove(r.menuKey) : c.add(r.menuKey!);
    logic.setShoppingChecked(_monday, c);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final mute = cs.onSurface.withValues(alpha: .55);
    return StreamBuilder<List<Recipe>>(
      stream: _recipes,
      builder: (ctx, snap) {
        _all = snap.data ?? _all;
        final week = logic.mealWeek(_monday);
        final rows = groceryRows(menuLines: shoppingFor(week, _all), menuChecked: week.checked, g: logic.groceries, menuDomainId: menuDomainOf(logic), monday: _monday);
        final toBuy = rows.where((r) => !r.inBasket).toList();
        final basket = rows.where((r) => r.inBasket).toList();
        final menuCount = rows.where((r) => r.source == 'menu').length;
        final covered = menuCoveredByPantry(shoppingFor(week, _all), logic.groceries, menuChecked: week.checked);
        final groups = rowsByStore(toBuy, logic.groceries.stores);
        return ListView(controller: widget.scroll, padding: const EdgeInsets.fromLTRB(20, 8, 20, 32), children: [
          Row(children: [
            const Expanded(child: Text('Courses', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(color: kGroceryAccent.withValues(alpha: .16), borderRadius: BorderRadius.circular(20)),
              child: Text(toBuy.isEmpty ? 'rien à prendre' : '${toBuy.length} à prendre', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: kGroceryAccent)),
            ),
          ]),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const Key('open-pantry'),
              onPressed: () => showPantrySheet(context, logic: logic),
              icon: const Icon(Icons.kitchen_outlined, size: 18),
              label: Text(logic.groceries.pantry.isEmpty ? 'Mes placards ›' : 'Mes placards · ${logic.groceries.pantry.length} produits ›'),
              style: TextButton.styleFrom(foregroundColor: kGroceryAccent, padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
            ),
          ),
          TextField(
            controller: _add,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              hintText: 'Ajouter… lessive, ampoules',
              prefixIcon: const Icon(Icons.add),
              suffixIcon: IconButton(icon: const Icon(Icons.arrow_forward_rounded), onPressed: _submit),
              filled: true,
              fillColor: cs.surfaceContainerHighest.withValues(alpha: .35),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              isDense: true,
            ),
          ),
          if (menuCount > 0)
            Container(
              margin: const EdgeInsets.only(top: 10),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(color: _kMenu.withValues(alpha: .1), borderRadius: BorderRadius.circular(12)),
              child: Text.rich(TextSpan(children: [
                const TextSpan(text: 'Du menu de la semaine', style: TextStyle(fontWeight: FontWeight.w800)),
                TextSpan(text: ' · $menuCount ingrédient${menuCount > 1 ? 's' : ''} arrivé${menuCount > 1 ? 's' : ''} tout seuls'),
              ]), style: const TextStyle(fontSize: 12.5)),
            ),
          if (covered.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '${covered.length} ingrédient${covered.length > 1 ? 's' : ''} du menu déjà au placard : ${covered.take(4).map((l) => l.label).join(', ')}${covered.length > 4 ? '…' : ''}',
                style: TextStyle(fontSize: 12, color: mute),
              ),
            ),
          if (toBuy.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 18),
              child: Text('La liste est vide. Tape un mot au-dessus ; les ingrédients du menu de la semaine arrivent tout seuls.', style: TextStyle(fontSize: 13.5, color: mute)),
            ),
          for (final g in groups) ...[
            Padding(
              padding: const EdgeInsets.only(top: 16, bottom: 2),
              child: Row(children: [
                Expanded(child: Text('${g.key.toUpperCase()} · ${g.value.length}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: .8, color: mute))),
                if (widget.onShop != null)
                  TextButton(
                    style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                    onPressed: () => widget.onShop!(g.key, _all),
                    child: const Text('J’y vais'),
                  ),
              ]),
            ),
            for (final a in rowsByAisle(g.value, logic.groceries.aisles)) ...[
              Padding(
                padding: const EdgeInsets.only(top: 6, bottom: 2),
                child: Row(children: [
                  Container(width: 8, height: 8, decoration: BoxDecoration(color: aisleColor(logic.groceries.aisles, a.key), borderRadius: BorderRadius.circular(2))),
                  const SizedBox(width: 6),
                  Text('${a.key} · ${a.value.length}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: mute)),
                ]),
              ),
              for (final r in a.value) _row(cs, mute, r),
            ],
          ],
          if (basket.isNotEmpty) ...[
            InkWell(
              onTap: () => setState(() => _basketOpen = !_basketOpen),
              child: Padding(
                padding: const EdgeInsets.only(top: 16, bottom: 4),
                child: Row(children: [
                  Expanded(child: Text('DANS LE PANIER · ${basket.length}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: .8, color: mute))),
                  Icon(_basketOpen ? Icons.expand_less : Icons.expand_more, size: 18, color: mute),
                ]),
              ),
            ),
            if (_basketOpen) for (final r in basket) _row(cs, mute, r),
          ],
          if (widget.onShop != null && toBuy.isNotEmpty) ...[
            const SizedBox(height: 16),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: kGroceryAccent, foregroundColor: kGroceryInk, minimumSize: const Size.fromHeight(50)),
              onPressed: () => widget.onShop!(groups.first.key, _all),
              icon: const Icon(Icons.shopping_cart_outlined),
              label: const Text('Je pars faire les courses', style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ],
        ]);
      },
    );
  }

  Widget _row(ColorScheme cs, Color mute, GroceryRow r) {
    final st = logic.state;
    final dom = st.activeDomains.where((d) => d.id == r.domainId).firstOrNull;
    final color = domainColor(r.domainId, st.activeDomains) ?? mute;
    final project = r.projectId == null ? null : logic.currentProjects.where((p) => p.id == r.projectId).firstOrNull;
    Widget tag(String t, Color c) => Container(
          margin: const EdgeInsets.only(left: 5),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(color: c.withValues(alpha: .15), borderRadius: BorderRadius.circular(20)),
          child: Text(t, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: c)),
        );
    final sub = switch (r.source) {
      'menu' when r.itemId == null => 'pour ${r.from.join(', ')}${r.pantryState == PantryState.low ? ' · bientôt fini au placard' : ''}',
      'pantry' => r.pantryState == PantryState.out ? 'plus rien au placard' : 'bientôt fini au placard',
      _ => dom?.name ?? 'sans domaine',
    };
    final tile = InkWell(
      onTap: () => _toggle(r),
      onLongPress: r.itemId != null
          ? () => showGroceryEditor(context, logic: logic, item: logic.groceries.items[r.itemId], monday: _monday)
          : r.pantryKey != null && logic.groceries.pantry[r.pantryKey] != null
              ? () => showPantryItemEditor(context, logic: logic, item: logic.groceries.pantry[r.pantryKey]!)
          : r.menuKey != null
              ? () async {
                  final x = await logic.detachMenuRow(r, _monday);
                  if (mounted) await showGroceryEditor(context, logic: logic, item: x, monday: _monday);
                }
              : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 22,
            height: 22,
            margin: const EdgeInsets.only(top: 1),
            decoration: BoxDecoration(
              color: r.inBasket ? kGroceryAccent : null,
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: r.inBasket ? kGroceryAccent : mute, width: 2),
            ),
            child: r.inBasket ? const Icon(Icons.check, size: 14, color: kGroceryInk) : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(r.label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, decoration: r.inBasket ? TextDecoration.lineThrough : null, color: r.inBasket ? mute : null)),
                ),
              ]),
              const SizedBox(height: 2),
              Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text(sub, style: TextStyle(fontSize: 11.5, color: mute)),
                if (r.source == 'menu') tag('menu', _kMenu),
                if (project != null) tag(project.title.length > 22 ? '${project.title.substring(0, 21)}…' : project.title, _kProject),
                if (r.source == 'claude') tag('via Claude', _kClaude),
                if (r.source == 'pantry' && (logic.groceries.pantry[r.pantryKey]?.staple ?? false)) tag('habituel', kGroceryAccent),
              ]),
            ]),
          ),
          if (r.qty.isNotEmpty) Padding(padding: const EdgeInsets.only(left: 8, top: 2), child: Text(r.qty, style: TextStyle(fontSize: 12.5, color: mute))),
        ]),
      ),
    );
    if (r.itemId == null && r.menuKey != null) {
      // Ingrédient du menu (2026-11-03) : glisser = retiré de la liste cette
      // semaine ; appui long = devient une ligne libre qu'on modifie.
      return Dismissible(
        key: ValueKey('gm-${r.menuKey}'),
        direction: DismissDirection.endToStart,
        background: Container(alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 12), child: const Icon(Icons.delete_outline, color: Color(0xFFF07A6A))),
        onDismissed: (_) {
          final m = _monday;
          logic.skipMenuLine(m, r.menuKey!);
          ScaffoldMessenger.of(context).showClosingSnackBar(SnackBar(
            content: Text('${r.label} retiré de la liste'),
            duration: const Duration(seconds: 4),
            action: SnackBarAction(label: 'Annuler', onPressed: () => logic.skipMenuLine(m, r.menuKey!, skip: false)),
          ));
        },
        child: tile,
      );
    }
    if (r.itemId == null && r.pantryKey != null) {
      // Ligne du placard (2026-11-04) : glisser = pas cette semaine ; le placard
      // garde son état, la ligne revient lundi prochain si le produit manque.
      return Dismissible(
        key: ValueKey('gp-${r.pantryKey}'),
        direction: DismissDirection.endToStart,
        background: Container(alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 12), child: const Icon(Icons.event_busy_outlined, color: Color(0xFFF07A6A))),
        onDismissed: (_) {
          final m = _monday;
          final k = pantryRowKey(r.pantryKey!);
          logic.skipMenuLine(m, k);
          ScaffoldMessenger.of(context).showClosingSnackBar(SnackBar(
            content: Text('${r.label} · pas cette semaine'),
            duration: const Duration(seconds: 4),
            action: SnackBarAction(label: 'Annuler', onPressed: () => logic.skipMenuLine(m, k, skip: false)),
          ));
        },
        child: tile,
      );
    }
    if (r.itemId == null) return tile;
    return Dismissible(
      key: ValueKey('gr-${r.itemId}'),
      direction: DismissDirection.endToStart,
      background: Container(alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 12), child: const Icon(Icons.delete_outline, color: Color(0xFFF07A6A))),
      onDismissed: (_) {
        final x = logic.groceries.items[r.itemId!];
        logic.removeGrocery(r.itemId!);
        if (x == null) return;
        ScaffoldMessenger.of(context).showClosingSnackBar(SnackBar(
          content: Text('${x.label} retiré'),
          duration: const Duration(seconds: 4),
          action: SnackBarAction(label: 'Annuler', onPressed: () => logic.updateGrocery(x)),
        ));
      },
      child: tile,
    );
  }
}

/// Ajouter ou modifier une ligne : quantité, domaine, projet, endroit.
Future<void> showGroceryEditor(BuildContext context, {required AppLogic logic, String? label, GroceryItem? item, String? monday}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: _GroceryEditor(logic: logic, label: label ?? item?.label ?? '', item: item, monday: monday),
    ),
  );
}

class _GroceryEditor extends StatefulWidget {
  final AppLogic logic;
  final String label;
  final GroceryItem? item;
  final String? monday;
  const _GroceryEditor({required this.logic, required this.label, this.item, this.monday});

  @override
  State<_GroceryEditor> createState() => _GroceryEditorState();
}

class _GroceryEditorState extends State<_GroceryEditor> {
  late final _label = TextEditingController(text: widget.label);
  late final _qty = TextEditingController(text: widget.item?.qty ?? '');
  late GroceryMemory _guess = guessFor(widget.logic.groceries, widget.label, lastDomainId: widget.logic.lastGroceryDomainId);
  late String? _domain = widget.item?.domainId ?? _guess.domainId;
  late String? _project = widget.item?.projectId ?? _guess.projectId;
  late String _store = widget.item?.store ?? _guess.store ?? kMenuStore;
  late String _aisle = widget.item?.aisle ?? aisleFor(widget.logic.groceries, widget.label);

  @override
  void dispose() {
    _label.dispose();
    _qty.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l = _label.text.trim();
    if (l.isEmpty) return;
    final logic = widget.logic;
    final it = widget.item;
    if (it != null) {
      await logic.updateGrocery(GroceryItem(
        id: it.id,
        label: l,
        qty: _qty.text.trim(),
        domainId: _domain,
        projectId: _project,
        store: _store,
        source: it.source,
        inBasket: it.inBasket,
        aisle: _aisle,
      ));
    } else {
      await logic.addGrocery(label: l, qty: _qty.text, domainId: _domain, projectId: _project, store: _store, aisle: _aisle);
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _newStore() async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Un endroit'),
        content: TextField(controller: ctrl, autofocus: true, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(hintText: 'Animalerie, boulangerie…')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('OK')),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    await widget.logic.addGroceryStore(name);
    setState(() => _store = name);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final mute = cs.onSurface.withValues(alpha: .55);
    final logic = widget.logic;
    final domains = logic.state.activeDomains;
    final projects = logic.currentProjects.where((p) => p.status == 'active' && !p.paused).toList();
    Widget label(String t, [String? hint]) => Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 6),
          child: Text.rich(TextSpan(children: [
            TextSpan(text: t, style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: .8)),
            if (hint != null) TextSpan(text: '  $hint', style: const TextStyle(fontWeight: FontWeight.w500)),
          ]), style: TextStyle(fontSize: 11, color: mute)),
        );
    ChoiceChip chip(String t, bool on, VoidCallback tap, {Color? dot}) => ChoiceChip(
          avatar: dot == null ? null : CircleAvatar(backgroundColor: dot, radius: 5),
          label: Text(t),
          selected: on,
          selectedColor: kGroceryAccent,
          labelStyle: TextStyle(fontWeight: FontWeight.w700, color: on ? kGroceryInk : null),
          onSelected: (_) => tap(),
        );
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        TextField(
          controller: _label,
          textCapitalization: TextCapitalization.sentences,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
          decoration: const InputDecoration(border: InputBorder.none, hintText: 'Quoi ?'),
          onChanged: (v) {
            if (widget.item != null) return;
            final g = guessFor(logic.groceries, v, lastDomainId: logic.lastGroceryDomainId);
            if (logic.groceries.memory.containsKey(normLabel(v))) {
              setState(() {
                _guess = g;
                _domain = g.domainId;
                _project = g.projectId;
                _store = g.store ?? _store;
              });
            }
            setState(() => _aisle = aisleFor(logic.groceries, v));
          },
        ),
        TextField(controller: _qty, decoration: const InputDecoration(labelText: 'Combien', hintText: 'facultatif · ×3, 1 kg', isDense: true)),
        label('POUR QUEL DOMAINE ?'),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final d in domains) chip(d.name, d.id == _domain, () => setState(() => _domain = d.id), dot: domainColor(d.id, domains)),
          chip('Aucun', _domain == null, () => setState(() => _domain = null)),
        ]),
        if (projects.isNotEmpty) ...[
          label('POUR UN PROJET ?', 'facultatif'),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final p in projects.take(8))
              chip(p.title.length > 28 ? '${p.title.substring(0, 27)}…' : p.title, p.id == _project, () {
                setState(() {
                  _project = p.id == _project ? null : p.id;
                  if (_project != null && p.domainId != null) _domain = p.domainId;
                });
              }),
          ]),
        ],
        label('QUEL RAYON ?'),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final a in logic.groceries.aisles) chip(a, a == _aisle, () => setState(() => _aisle = a), dot: aisleColor(logic.groceries.aisles, a)),
        ]),
        label('OÙ ÇA S’ACHÈTE ?'),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final s in logic.groceries.stores) chip(s, s == _store, () => setState(() => _store = s)),
          ActionChip(label: const Text('＋'), onPressed: _newStore),
        ]),
        const SizedBox(height: 16),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: kGroceryAccent, foregroundColor: kGroceryInk, minimumSize: const Size.fromHeight(50)),
          onPressed: _save,
          child: Text(widget.item == null ? 'Ajouter à la liste' : 'Enregistrer', style: const TextStyle(fontWeight: FontWeight.w800)),
        ),
        if (widget.item != null)
          Wrap(alignment: WrapAlignment.center, children: [
            TextButton(
              key: const Key('grocery-have'),
              onPressed: () async {
                final it = widget.item!;
                await logic.alreadyHave(
                    GroceryRow(label: it.label, store: it.store, source: it.source, itemId: it.id, aisle: _aisle), widget.monday ?? '');
                if (context.mounted) Navigator.of(context).pop();
              },
              child: const Text('J’en ai déjà'),
            ),
            TextButton(
              onPressed: () async {
                await logic.removeGrocery(widget.item!.id);
                if (context.mounted) Navigator.of(context).pop();
              },
              child: const Text('Retirer de la liste', style: TextStyle(color: Color(0xFFF07A6A))),
            ),
          ]),
      ]),
    );
  }
}
