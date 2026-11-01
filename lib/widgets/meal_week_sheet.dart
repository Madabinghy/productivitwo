import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/duration_fmt.dart' show fmtMin;
import 'package:productivitwo_v1/utils/engagement_stats.dart' show ymdOf;
import 'package:productivitwo_v1/utils/meal_plan.dart';
import 'package:productivitwo_v1/utils/meals.dart' show sortDishes;
import 'package:productivitwo_v1/widgets/dishes_sheet.dart' show kMealAccent, showDishSheet, showDishesSheet;
import 'package:productivitwo_v1/widgets/fiche.dart' show showFiche;

const _days = ['lun.', 'mar.', 'mer.', 'jeu.', 'ven.', 'sam.', 'dim.'];
const _months = ['janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'];

DateTime _mondayOf(DateTime d) => DateTime(d.year, d.month, d.day - (d.weekday - 1));

/// « Les repas de la semaine » (maquette validée 2026-11-01, écran 2) : un
/// plat par repas, les restes remplissent les midis suivants ; en bas, la
/// liste de courses de la semaine.
Future<void> showMealWeekSheet(BuildContext context, {required AppLogic logic, required FirestoreSync sync, int weekOffset = 0}) {
  return showFiche<void>(context, builder: (ctx, scroll) => MealWeekSheet(logic: logic, sync: sync, scroll: scroll, weekOffset: weekOffset));
}

class MealWeekSheet extends StatefulWidget {
  final AppLogic logic;
  final FirestoreSync sync;
  final ScrollController? scroll;
  final int weekOffset;
  final Stream<List<Recipe>>? recipes;
  const MealWeekSheet({super.key, required this.logic, required this.sync, this.scroll, this.weekOffset = 0, this.recipes});

  @override
  State<MealWeekSheet> createState() => _MealWeekSheetState();
}

class _MealWeekSheetState extends State<MealWeekSheet> {
  late int _offset = widget.weekOffset;
  late final Stream<List<Recipe>> _recipes = widget.recipes ?? widget.sync.streamRecipes();
  List<Recipe> _all = const [];

  AppLogic get logic => widget.logic;

  @override
  void initState() {
    super.initState();
    logic.addListener(_onLogic);
  }

  @override
  void dispose() {
    logic.removeListener(_onLogic);
    super.dispose();
  }

  void _onLogic() {
    if (mounted) setState(() {});
  }

  DateTime get _monday {
    final m = _mondayOf(logic.livedToday);
    return DateTime(m.year, m.month, m.day + 7 * _offset);
  }

  List<String> get _ymds => [for (var i = 0; i < 7; i++) ymdOf(DateTime(_monday.year, _monday.month, _monday.day + i))];

  Future<void> _pick(String key, String label) async {
    final monday = ymdOf(_monday);
    final cur = logic.mealWeek(monday).slots[key];
    final s = sortDishes(_all, DateTime.now());
    final dishes = [...s.often, ...s.stale, ...s.fresh];
    final choice = await showModalBottomSheet<Object>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        final mute = cs.onSurface.withValues(alpha: .55);
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * .75),
            child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), children: [
              Text(label, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text('Un plat de plusieurs portions remplit aussi les midis suivants.', style: TextStyle(fontSize: 12.5, color: mute)),
              const SizedBox(height: 8),
              for (final r in dishes)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(r.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(['×${r.portions} portions', if (r.minutes != null) fmtMin(r.minutes!), if (r.timesCooked > 0) 'fait ${r.timesCooked} fois'].join(' · '),
                      style: TextStyle(fontSize: 12, color: mute)),
                  trailing: cur?.recipeId == r.id ? const Icon(Icons.check_rounded, color: kMealAccent) : null,
                  onTap: () => Navigator.pop(ctx, r),
                ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.add_rounded),
                title: const Text('Nouveau plat'),
                onTap: () => Navigator.pop(ctx, 'new'),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.storefront_outlined),
                title: const Text('Dehors / libre'),
                onTap: () => Navigator.pop(ctx, 'out'),
              ),
              if (cur != null)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.clear_rounded),
                  title: const Text('Vider ce repas'),
                  onTap: () => Navigator.pop(ctx, 'clear'),
                ),
            ]),
          ),
        );
      },
    );
    if (!mounted || choice == null) return;
    if (choice is Recipe) {
      await logic.setMeal(monday, key, PlannedMeal(recipeId: choice.id, title: choice.title, portions: choice.portions));
    } else if (choice == 'out') {
      await logic.setMeal(monday, key, const PlannedMeal(title: 'Dehors / libre', out: true));
    } else if (choice == 'clear') {
      await logic.setMeal(monday, key, null);
    } else if (choice == 'new') {
      await showDishSheet(context, sync: widget.sync, all: _all);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final mute = cs.onSurface.withValues(alpha: .55);
    final monday = ymdOf(_monday);
    final sunday = DateTime(_monday.year, _monday.month, _monday.day + 6);
    final today = ymdOf(logic.livedToday);
    return StreamBuilder<List<Recipe>>(
      stream: _recipes,
      builder: (ctx, snap) {
        _all = snap.data ?? _all;
        final week = logic.mealWeek(monday);
        final left = leftoversOf(week.slots, _ymds);
        final lines = shoppingFor(week, _all);
        final toBuy = lines.where((l) => !week.checked.contains(l.key)).length;
        Widget slot(String ymd, String moment, int i) {
          final key = mealKey(ymd, moment);
          final p = week.slots[key];
          final fromKey = left[key];
          final from = fromKey == null ? null : week.slots[fromKey];
          final past = ymd.compareTo(today) < 0;
          return Opacity(
            opacity: past ? .55 : 1,
            child: Material(
              color: from != null ? Colors.transparent : cs.surfaceContainerHighest.withValues(alpha: .35),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: from != null ? BorderSide(color: kMealAccent.withValues(alpha: .4)) : BorderSide.none,
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => _pick(key, '${_days[i]} ${moment == 'midi' ? 'midi' : 'soir'}'),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(children: [
                    SizedBox(
                      width: 70,
                      child: Text('${_days[i]} $moment', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: ymd == today ? kMealAccent : mute)),
                    ),
                    Expanded(
                      child: Text(
                        p != null ? p.title : (from != null ? '↳ les restes · ${from.title}' : '+ choisir'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: p != null && !p.out ? FontWeight.w700 : FontWeight.w500,
                          color: p == null ? mute : (p.out ? mute : cs.onSurface),
                        ),
                      ),
                    ),
                    if (p != null && !p.out && p.portions > 1) Text('×${p.portions}', style: TextStyle(fontSize: 12, color: mute)),
                  ]),
                ),
              ),
            ),
          );
        }

        return ListView(controller: widget.scroll, padding: const EdgeInsets.fromLTRB(20, 8, 20, 32), children: [
          Row(children: [
            const Expanded(child: Text('Les repas de la semaine', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900))),
            IconButton(onPressed: _offset > -1 ? () => setState(() => _offset--) : null, icon: const Icon(Icons.chevron_left_rounded)),
            IconButton(onPressed: _offset < 3 ? () => setState(() => _offset++) : null, icon: const Icon(Icons.chevron_right_rounded)),
          ]),
          Text(
            '${_offset == 0 ? 'Cette semaine' : (_offset == 1 ? 'La semaine prochaine' : 'Semaine')} · ${_monday.day} ${_months[_monday.month - 1]} → ${sunday.day} ${_months[sunday.month - 1]}',
            style: TextStyle(fontSize: 13, color: mute),
          ),
          const SizedBox(height: 4),
          Text('Touche un repas pour choisir le plat. Les restes d’un plat à plusieurs portions remplissent les midis suivants.',
              style: TextStyle(fontSize: 12.5, color: mute)),
          for (final (i, ymd) in _ymds.indexed) ...[
            const SizedBox(height: 10),
            slot(ymd, 'midi', i),
            const SizedBox(height: 5),
            slot(ymd, 'soir', i),
          ],
          const SizedBox(height: 18),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: kMealAccent, foregroundColor: const Color(0xFF0F1A0C), minimumSize: const Size.fromHeight(50)),
            onPressed: () => showShoppingSheet(context, logic: logic, sync: widget.sync, monday: monday, recipes: _all),
            icon: const Icon(Icons.shopping_basket_outlined),
            label: Text(lines.isEmpty ? 'Liste de courses' : 'Liste de courses · $toBuy à prendre', style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(onPressed: () => showDishesSheet(context, sync: widget.sync), child: const Text('Mes plats ›')),
          ),
        ]);
      },
    );
  }
}

/// La liste de courses d'une semaine (écran 6) : chaque ligne dit d'où elle
/// vient, se coche en magasin ; ajouts à la main.
Future<void> showShoppingSheet(BuildContext context, {required AppLogic logic, required FirestoreSync sync, required String monday, required List<Recipe> recipes}) {
  return showFiche<void>(context, builder: (ctx, scroll) => ShoppingSheet(logic: logic, monday: monday, recipes: recipes, scroll: scroll));
}

class ShoppingSheet extends StatefulWidget {
  final AppLogic logic;
  final String monday;
  final List<Recipe> recipes;
  final ScrollController? scroll;
  const ShoppingSheet({super.key, required this.logic, required this.monday, required this.recipes, this.scroll});

  @override
  State<ShoppingSheet> createState() => _ShoppingSheetState();
}

class _ShoppingSheetState extends State<ShoppingSheet> {
  final _add = TextEditingController();

  @override
  void dispose() {
    _add.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final mute = cs.onSurface.withValues(alpha: .55);
    final logic = widget.logic;
    final week = logic.mealWeek(widget.monday);
    final lines = shoppingFor(week, widget.recipes);
    final toBuy = lines.where((l) => !week.checked.contains(l.key)).toList();
    final got = lines.where((l) => week.checked.contains(l.key)).toList();
    final plats = week.slots.values.where((p) => !p.out).length;

    void toggle(ShoppingLine l) {
      final c = {...week.checked};
      c.contains(l.key) ? c.remove(l.key) : c.add(l.key);
      logic.setShoppingChecked(widget.monday, c);
      setState(() {});
    }

    void addManual() {
      final t = _add.text.trim();
      if (t.isEmpty) return;
      logic.setShoppingExtra(widget.monday, [...week.extra, ShoppingItem(label: t)]);
      _add.clear();
      setState(() {});
    }

    Widget line(ShoppingLine l, bool checked) => CheckboxListTile(
          value: checked,
          onChanged: (_) => toggle(l),
          activeColor: kMealAccent,
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text(l.label, style: TextStyle(fontSize: 15, decoration: checked ? TextDecoration.lineThrough : null, color: checked ? mute : null)),
          subtitle: Text(l.manual ? 'ajouté à la main' : l.from.join(' · '), style: TextStyle(fontSize: 11.5, color: mute)),
          secondary: l.manual
              ? IconButton(
                  icon: Icon(Icons.close_rounded, size: 18, color: mute),
                  onPressed: () {
                    logic.setShoppingExtra(widget.monday, [...week.extra.where((x) => '+${x.label.trim().toLowerCase()}' != l.key)]);
                    setState(() {});
                  },
                )
              : Text(l.qty, style: TextStyle(color: mute)),
        );

    return ListView(controller: widget.scroll, padding: const EdgeInsets.fromLTRB(20, 8, 20, 32), children: [
      Row(children: [
        const Expanded(child: Text('Liste de courses', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900))),
        Text('${toBuy.length}', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: mute)),
      ]),
      Text(plats == 0 ? 'Aucun plat posé cette semaine : la liste vient des plats de la semaine.' : 'Tirée des $plats repas posés, sans doublon. Coche en magasin.',
          style: TextStyle(fontSize: 13, color: mute)),
      const SizedBox(height: 8),
      for (final l in toBuy) line(l, false),
      Row(children: [
        Expanded(
          child: TextField(
            controller: _add,
            onSubmitted: (_) => addManual(),
            decoration: const InputDecoration(hintText: '+ Ajouter (lessive, café…)', border: InputBorder.none),
          ),
        ),
        IconButton(onPressed: addManual, icon: const Icon(Icons.add_circle_outline_rounded)),
      ]),
      if (got.isNotEmpty) ...[
        Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 4),
          child: Text('DANS LE PANIER · ${got.length}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: .8, color: mute)),
        ),
        for (final l in got) line(l, true),
      ],
    ]);
  }
}
