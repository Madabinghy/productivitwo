import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/domain_colors.dart';
import 'package:productivitwo_v1/utils/engagement_stats.dart' show ymdOf;
import 'package:productivitwo_v1/utils/finances.dart' show euros, isTracked, parseEuros;
import 'package:productivitwo_v1/utils/groceries.dart';
import 'package:productivitwo_v1/utils/meal_plan.dart';
import 'package:productivitwo_v1/widgets/fiche.dart' show showFiche;
import 'package:productivitwo_v1/widgets/groceries_sheet.dart' show kGroceryAccent, kGroceryInk, menuDomainOf;
import 'package:productivitwo_v1/widgets/undo_snack.dart' show ClosingSnackBar;
import 'package:wakelock_plus/wakelock_plus.dart';

/// En magasin et en caisse (maquette validée 2026-11-02 « Courses
/// générales », lot 3) : un endroit à la fois, gros carrés, ce qui est dans le
/// panier descend ; « Passer en caisse » → un total, réparti par domaine de
/// vie (et projet) en dépenses Finances.

String _mondayOf(AppLogic logic) {
  final t = logic.livedToday;
  return ymdOf(DateTime(t.year, t.month, t.day - (t.weekday - 1)));
}

List<GroceryRow> _rows(AppLogic logic, List<Recipe> recipes) {
  final monday = _mondayOf(logic);
  final week = logic.mealWeek(monday);
  return groceryRows(menuLines: shoppingFor(week, recipes), menuChecked: week.checked, g: logic.groceries, menuDomainId: menuDomainOf(logic), monday: monday);
}

void _toggle(AppLogic logic, GroceryRow r) {
  if (r.itemId != null) {
    logic.setGroceryInBasket(r.itemId!, !r.inBasket);
    return;
  }
  final monday = _mondayOf(logic);
  final c = {...logic.mealWeek(monday).checked};
  c.contains(r.menuKey) ? c.remove(r.menuKey) : c.add(r.menuKey!);
  logic.setShoppingChecked(monday, c);
}

Future<void> showGroceryShop(BuildContext context, {required AppLogic logic, required String store, required List<Recipe> recipes}) {
  return Navigator.of(context).push(MaterialPageRoute(fullscreenDialog: true, builder: (_) => GroceryShopScreen(logic: logic, store: store, recipes: recipes)));
}

class GroceryShopScreen extends StatefulWidget {
  final AppLogic logic;
  final String store;
  final List<Recipe> recipes;
  const GroceryShopScreen({super.key, required this.logic, required this.store, required this.recipes});

  @override
  State<GroceryShopScreen> createState() => _GroceryShopScreenState();
}

class _GroceryShopScreenState extends State<GroceryShopScreen> {
  late String _store = widget.store;
  AppLogic get logic => widget.logic;

  @override
  void initState() {
    super.initState();
    logic.addListener(_onLogic);
    WakelockPlus.enable().catchError((_) {});
  }

  @override
  void dispose() {
    logic.removeListener(_onLogic);
    WakelockPlus.disable().catchError((_) {});
    super.dispose();
  }

  void _onLogic() {
    if (mounted) setState(() {});
  }

  Future<void> _checkout() async {
    final done = await showGroceryCheckout(context, logic: logic, recipes: widget.recipes, store: _store);
    if (done == true && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final mute = cs.onSurface.withValues(alpha: .55);
    final rows = _rows(logic, widget.recipes);
    final here = rows.where((r) => r.store == _store).toList()..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
    final toTake = here.where((r) => !r.inBasket).toList();
    final inBasket = here.where((r) => r.inBasket).toList();
    final basketAll = rows.where((r) => r.inBasket).length;
    final otherStores = rowsByStore(rows.where((r) => !r.inBasket && r.store != _store).toList(), logic.groceries.stores).map((e) => e.key).toList();
    final ratio = here.isEmpty ? 0.0 : inBasket.length / here.length;

    Widget line(GroceryRow r) => InkWell(
          onTap: () => _toggle(logic, r),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: r.inBasket ? kGroceryAccent : null,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: r.inBasket ? kGroceryAccent : mute, width: 2),
                ),
                child: r.inBasket ? const Icon(Icons.check, size: 18, color: kGroceryInk) : null,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(r.label,
                      style: TextStyle(
                        fontSize: r.inBasket ? 15 : 18,
                        fontWeight: FontWeight.w800,
                        color: r.inBasket ? mute : null,
                        decoration: r.inBasket ? TextDecoration.lineThrough : null,
                      )),
                  if (!r.inBasket && (r.qty.isNotEmpty || r.from.isNotEmpty))
                    Text([if (r.qty.isNotEmpty) r.qty, if (r.from.isNotEmpty) r.from.join(', ')].join(' · '), style: TextStyle(fontSize: 13, color: mute)),
                ]),
              ),
            ]),
          ),
        );

    return Scaffold(
      appBar: AppBar(
        title: Text('Au rayon ${_store.toLowerCase()}'),
        actions: [
          if (otherStores.isNotEmpty || logic.groceries.stores.length > 1)
            PopupMenuButton<String>(
              tooltip: 'Changer de magasin',
              icon: const Icon(Icons.storefront_outlined),
              onSelected: (s) => setState(() => _store = s),
              itemBuilder: (_) => [
                for (final s in {...otherStores, ...logic.groceries.stores}.where((s) => s != _store))
                  PopupMenuItem(value: s, child: Text('$s${otherStores.contains(s) ? ' · ${rows.where((r) => !r.inBasket && r.store == s).length}' : ''}')),
              ],
            ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 120), children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(value: ratio, minHeight: 8, color: kGroceryAccent, backgroundColor: cs.onSurface.withValues(alpha: .08)),
        ),
        const SizedBox(height: 6),
        Text(
          [
            '${inBasket.length} / ${here.length} dans le panier',
            if (otherStores.isNotEmpty) '${otherStores.join(' et ')} ensuite',
          ].join(' · '),
          style: TextStyle(fontSize: 13, color: mute),
        ),
        if (toTake.isNotEmpty) ...[
          Padding(padding: const EdgeInsets.only(top: 16, bottom: 4), child: Text('À PRENDRE · ${toTake.length}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: .8, color: mute))),
          for (final r in toTake) line(r),
        ] else
          Padding(
            padding: const EdgeInsets.only(top: 24),
            child: Text(here.isEmpty ? 'Rien à prendre ici.' : '✓ Tout est dans le panier.', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: kGroceryAccent)),
          ),
        if (inBasket.isNotEmpty) ...[
          Padding(padding: const EdgeInsets.only(top: 16, bottom: 4), child: Text('DANS LE PANIER · ${inBasket.length}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: .8, color: mute))),
          for (final r in inBasket) line(r),
        ],
      ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: kGroceryAccent, foregroundColor: kGroceryInk, minimumSize: const Size.fromHeight(52)),
            onPressed: basketAll == 0 ? null : _checkout,
            icon: const Icon(Icons.point_of_sale_rounded),
            label: Text(basketAll == 0 ? 'Passer en caisse' : 'Passer en caisse · $basketAll', style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
        ),
      ),
    );
  }
}

/// La caisse : un total, réparti par domaine (et projet). Renvoie true si enregistré.
Future<bool?> showGroceryCheckout(BuildContext context, {required AppLogic logic, required List<Recipe> recipes, String? store}) {
  return showFiche<bool>(context, builder: (ctx, scroll) => GroceryCheckout(logic: logic, recipes: recipes, store: store, scroll: scroll));
}

class GroceryCheckout extends StatefulWidget {
  final AppLogic logic;
  final List<Recipe> recipes;
  final String? store;
  final ScrollController? scroll;
  const GroceryCheckout({super.key, required this.logic, required this.recipes, this.store, this.scroll});

  @override
  State<GroceryCheckout> createState() => _GroceryCheckoutState();
}

class _GroceryCheckoutState extends State<GroceryCheckout> {
  final _total = TextEditingController();
  late final List<CheckoutLine> _lines = checkoutLinesOf(_rows(widget.logic, widget.recipes), widget.logic.groceries);
  List<TicketShare> _shares = const [];
  int? _lastTotal;

  @override
  void dispose() {
    _total.dispose();
    super.dispose();
  }

  void _recompute() {
    final t = parseEuros(_total.text);
    setState(() {
      if (t != _lastTotal) _shares = t == null ? const [] : splitTicket(t, _lines);
      _lastTotal = t;
    });
  }

  Future<void> _edit(int i) async {
    final ctrl = TextEditingController(text: (_shares[i].amount / 100).toStringAsFixed(2).replaceAll('.', ','));
    final v = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Corriger cette part'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]'))],
          decoration: const InputDecoration(suffixText: '€', helperText: 'le reste se répartit sur les autres'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, parseEuros(ctrl.text) ?? (ctrl.text.trim() == '0' ? 0 : null)), child: const Text('OK')),
        ],
      ),
    );
    if (v == null) return;
    setState(() => _shares = adjustShare(_shares, i, v));
  }

  Future<void> _save() async {
    final logic = widget.logic;
    final first = !isTracked(logic.finances, logic.livedTodayYmd);
    final ids = await logic.checkoutGroceries(lines: _lines, shares: _shares, store: widget.store, monday: _mondayOf(logic));
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop(true);
    final routine = logic.budgetRoutine;
    messenger.showClosingSnackBar(SnackBar(
      content: Text([
        if (first) '✓ Jour suivi',
        '${ids.length} dépense${ids.length > 1 ? 's' : ''} dans « Courses »',
        if (first && routine != null) '${routine.name} +1',
      ].join(' · ')),
      duration: const Duration(seconds: 4),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final mute = cs.onSurface.withValues(alpha: .55);
    final st = widget.logic.state;
    final domains = st.activeDomains;
    final total = _shares.fold<int>(0, (s, x) => s + x.amount);
    return ListView(controller: widget.scroll, padding: const EdgeInsets.fromLTRB(20, 8, 20, 32), children: [
      const Text('Le ticket fait ?', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
      Text('${_lines.length} ligne${_lines.length > 1 ? 's' : ''} dans le panier', style: TextStyle(fontSize: 13, color: mute)),
      TextField(
        controller: _total,
        autofocus: true,
        textAlign: TextAlign.center,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]'))],
        style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w900),
        decoration: InputDecoration(hintText: '0', suffixText: '€', suffixStyle: TextStyle(fontSize: 22, color: mute), border: InputBorder.none),
        onChanged: (_) => _recompute(),
      ),
      if (_shares.isNotEmpty) ...[
        Text('RÉPARTI PAR DOMAINE DE VIE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: .8, color: mute)),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: SizedBox(
            height: 10,
            child: Row(children: [
              for (final s in _shares)
                if (s.amount > 0) Expanded(flex: s.amount, child: ColoredBox(color: domainColor(s.domainId, domains) ?? mute)),
            ]),
          ),
        ),
        const SizedBox(height: 6),
        for (final (i, s) in _shares.indexed)
          InkWell(
            onTap: () => _edit(i),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Container(width: 9, height: 9, decoration: BoxDecoration(color: domainColor(s.domainId, domains) ?? mute, shape: BoxShape.circle)),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      [
                        domains.where((d) => d.id == s.domainId).firstOrNull?.name ?? 'Sans domaine',
                        if (s.projectId != null) widget.logic.currentProjects.where((p) => p.id == s.projectId).firstOrNull?.title ?? 'projet',
                      ].join(' · '),
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                    ),
                  ),
                  Text(euros(s.amount), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                  Icon(Icons.edit_outlined, size: 15, color: mute),
                ]),
                Padding(
                  padding: const EdgeInsets.only(left: 16, top: 2),
                  child: Text('${s.labels.length} ligne${s.labels.length > 1 ? 's' : ''} · ${s.labels.take(4).join(', ')}${s.labels.length > 4 ? '…' : ''}',
                      style: TextStyle(fontSize: 11.5, color: mute)),
                ),
              ]),
            ),
          ),
        const SizedBox(height: 4),
        Text('Réparti d’après les prix déjà vus (≈), sinon à parts égales. Touche une part pour la corriger.', style: TextStyle(fontSize: 12, color: mute)),
      ],
      const SizedBox(height: 16),
      FilledButton(
        style: FilledButton.styleFrom(backgroundColor: kGroceryAccent, foregroundColor: kGroceryInk, minimumSize: const Size.fromHeight(50)),
        onPressed: total <= 0 ? null : _save,
        child: Text(
          total <= 0 ? 'Enregistrer' : 'Enregistrer · ${_shares.where((s) => s.amount > 0).length} dépense${_shares.where((s) => s.amount > 0).length > 1 ? 's' : ''}',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      Container(
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(border: Border.all(color: const Color(0x80FFD27A)), borderRadius: BorderRadius.circular(12)),
        child: const Text('📷 Bientôt : prendre le ticket en photo, Claude lira chaque ligne et son prix.', style: TextStyle(fontSize: 12.5)),
      ),
    ]);
  }
}
