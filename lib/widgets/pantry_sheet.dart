import 'package:flutter/material.dart';
import 'package:productivitwo_v1/utils/game_rules.dart' show kRuleGroceries;
import 'package:productivitwo_v1/widgets/info_dot.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/utils/groceries.dart';
import 'package:productivitwo_v1/utils/pantry.dart';
import 'package:productivitwo_v1/widgets/fiche.dart' show showFiche;
import 'package:productivitwo_v1/widgets/groceries_sheet.dart' show kGroceryAccent, kGroceryInk;
import 'package:productivitwo_v1/widgets/undo_snack.dart' show ClosingSnackBar;

/// Feuille « Mes placards » (maquette validée 2026-11-03, lot 2) : ce qu'on a
/// chez soi, par rayon. Tap sur l'état = J'en ai → Bientôt fini → Plus rien ;
/// tap sur le produit = réglages (rayon, habituel, retirer) ; glisser = retirer.

const kPantryHave = Color(0xFF4CC38A);
const kPantryLow = Color(0xFFFAB219);
const kPantryOut = Color(0xFFE66767);

Color pantryStateColor(PantryState s) => switch (s) {
      PantryState.have => kPantryHave,
      PantryState.low => kPantryLow,
      PantryState.out => kPantryOut,
    };

/// Couleur d'un rayon (fixe par position, comme une légende).
const _kAislePalette = [
  Color(0xFFC98500), Color(0xFF3987E5), Color(0xFF199E70), Color(0xFF5FB8C9),
  Color(0xFF9085E9), Color(0xFFD55181), Color(0xFFE07B39), Color(0xFF8F9B96),
];
Color aisleColor(List<String> aisles, String aisle) {
  final i = aisles.indexOf(aisle);
  return i < 0 ? _kAislePalette.last : _kAislePalette[i % _kAislePalette.length];
}

const _months = ['janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'];
String _dayLabel(String ymd) {
  final p = ymd.split('-');
  if (p.length != 3) return ymd;
  final m = int.tryParse(p[1]) ?? 1;
  return '${int.tryParse(p[2]) ?? p[2]} ${_months[(m - 1).clamp(0, 11)]}';
}

Future<void> showPantrySheet(BuildContext context, {required AppLogic logic}) {
  return showFiche<void>(context, builder: (ctx, scroll) => PantrySheet(logic: logic, scroll: scroll));
}

class PantrySheet extends StatefulWidget {
  final AppLogic logic;
  final ScrollController? scroll;
  const PantrySheet({super.key, required this.logic, this.scroll});

  @override
  State<PantrySheet> createState() => _PantrySheetState();
}

class _PantrySheetState extends State<PantrySheet> {
  final _add = TextEditingController();
  String? _aisle;
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

  Future<void> _submit() async {
    final t = _add.text.trim();
    if (t.isEmpty) return;
    _add.clear();
    final known = logic.groceries.pantry[normLabel(t)];
    await logic.setPantryState(known?.label ?? t, PantryState.have);
    if (!mounted) return;
    final p = logic.groceries.pantry[normLabel(t)];
    if (p == null) return;
    ScaffoldMessenger.of(context).showClosingSnackBar(SnackBar(
      content: Text('${p.label} · ${p.aisle}'),
      duration: const Duration(seconds: 3),
      action: SnackBarAction(label: 'Modifier', onPressed: () => showPantryItemEditor(context, logic: logic, item: logic.groceries.pantry[p.key]!)),
    ));
  }

  Future<void> _remove(PantryItem p) async {
    await logic.removePantryItem(p.key);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showClosingSnackBar(SnackBar(
        content: Text('${p.label} retiré des placards'),
        duration: const Duration(seconds: 4),
        action: SnackBarAction(label: 'Annuler', onPressed: () => logic.updatePantryItem(p)),
      ));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final mute = cs.onSurface.withValues(alpha: .55);
    final g = logic.groceries;
    final all = g.pantry.values.toList();
    final used = {for (final p in all) p.aisle};
    final chips = [...g.aisles.where(used.contains), ...used.where((a) => !g.aisles.contains(a))];
    if (_aisle != null && !used.contains(_aisle)) _aisle = null;
    final groups = pantryByAisle(g, where: _aisle == null ? null : (p) => p.aisle == _aisle);
    final low = all.where((p) => p.state == PantryState.low).length;
    final out = all.where((p) => p.state == PantryState.out).length;
    // Le dernier achat : le jour le plus récent et ce qui y a été rangé.
    final last = all.map((p) => p.boughtAt).whereType<String>().fold<String?>(null, (a, b) => a == null || b.compareTo(a) > 0 ? b : a);
    final lastCount = last == null ? 0 : all.where((p) => p.boughtAt == last).length;

    return ListView(controller: widget.scroll, padding: const EdgeInsets.fromLTRB(20, 8, 20, 32), children: [
      Row(children: [
        Flexible(child: Text('Mes placards', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900))),
        const SizedBox(width: 4),
        const InfoDot(kRuleGroceries, startAt: 4),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(color: kGroceryAccent.withValues(alpha: .16), borderRadius: BorderRadius.circular(20)),
          child: Text('${all.length} produit${all.length > 1 ? 's' : ''}',
              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: kGroceryAccent)),
        ),
      ]),
      const SizedBox(height: 2),
      Text(
        all.isEmpty
            ? 'Ce que tu as chez toi, par rayon.'
            : [if (low > 0) '$low bientôt fini${low > 1 ? 's' : ''}', if (out > 0) '$out plus rien', if (low == 0 && out == 0) 'rien ne manque'].join(' · '),
        style: TextStyle(fontSize: 13, color: mute),
      ),
      if (last != null) ...[
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(color: kGroceryAccent.withValues(alpha: .10), borderRadius: BorderRadius.circular(14)),
          child: Text.rich(TextSpan(children: [
            TextSpan(text: 'Achats du ${_dayLabel(last)}', style: const TextStyle(fontWeight: FontWeight.w800, color: kGroceryAccent)),
            TextSpan(text: ' · $lastCount produit${lastCount > 1 ? 's' : ''} rangé${lastCount > 1 ? 's' : ''}'),
          ]), style: const TextStyle(fontSize: 13)),
        ),
      ],
      const SizedBox(height: 12),
      TextField(
        key: const Key('pantry-add'),
        controller: _add,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          hintText: 'J\'ai… (ex. pâtes)',
          prefixIcon: const Icon(Icons.add_rounded, size: 20),
          isDense: true,
          filled: true,
          fillColor: cs.onSurface.withValues(alpha: .05),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
        ),
      ),
      if (chips.length > 1) ...[
        const SizedBox(height: 10),
        SizedBox(
          height: 34,
          child: ListView(scrollDirection: Axis.horizontal, children: [
            _chip(cs, 'Tout', _aisle == null, () => setState(() => _aisle = null)),
            for (final a in chips) _chip(cs, a, _aisle == a, () => setState(() => _aisle = _aisle == a ? null : a)),
          ]),
        ),
      ],
      if (all.isEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 24, 4, 8),
          child: Text(
            'Tes placards se remplissent tout seuls quand Claude lit ton ticket de caisse, ou quand tu passes en caisse dans la liste de courses. Tu peux aussi ajouter un produit ci-dessus.',
            style: TextStyle(color: mute, height: 1.4),
          ),
        ),
      for (final e in groups) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 18, 2, 6),
          child: Row(children: [
            Container(width: 9, height: 9, decoration: BoxDecoration(color: aisleColor(g.aisles, e.key), borderRadius: BorderRadius.circular(3))),
            const SizedBox(width: 8),
            Expanded(
              child: Text(e.key.toUpperCase(),
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: .6, color: mute)),
            ),
            Text('${e.value.length}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: mute)),
          ]),
        ),
        Container(
          decoration: BoxDecoration(color: cs.onSurface.withValues(alpha: .04), borderRadius: BorderRadius.circular(16)),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Column(children: [
            for (var i = 0; i < e.value.length; i++) _row(cs, e.value[i], first: i == 0),
          ]),
        ),
      ],
      const SizedBox(height: 18),
      Center(
        child: TextButton.icon(
          onPressed: () => showAislesSheet(context, logic: logic),
          icon: const Icon(Icons.view_list_rounded, size: 18),
          label: const Text('Gérer les rayons'),
          style: TextButton.styleFrom(foregroundColor: kGroceryAccent),
        ),
      ),
    ]);
  }

  Widget _chip(ColorScheme cs, String label, bool on, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(right: 6),
        child: Material(
          color: on ? cs.onSurface : cs.onSurface.withValues(alpha: .07),
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              child: Text(label,
                  style: TextStyle(fontSize: 12.5, fontWeight: on ? FontWeight.w800 : FontWeight.w600, color: on ? cs.surface : cs.onSurface.withValues(alpha: .7))),
            ),
          ),
        ),
      );

  Widget _row(ColorScheme cs, PantryItem p, {required bool first}) {
    final c = pantryStateColor(p.state);
    final listed = logic.groceries.items.values.any((x) => normLabel(x.label) == p.key);
    final meta = [
      if (p.staple) 'habituel',
      if (p.state != PantryState.have) listed ? 'sur la liste' : 'à racheter',
      if (p.boughtAt != null) 'acheté le ${_dayLabel(p.boughtAt!)}',
    ].join(' · ');
    return Dismissible(
      key: ValueKey('pantry-${p.key}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 12),
        child: Icon(Icons.delete_outline_rounded, color: cs.onSurface.withValues(alpha: .5)),
      ),
      onDismissed: (_) => _remove(p),
      child: InkWell(
        onTap: () => showPantryItemEditor(context, logic: logic, item: p),
        child: Container(
          decoration: BoxDecoration(border: first ? null : Border(top: BorderSide(color: cs.onSurface.withValues(alpha: .06)))),
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(p.label, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                if (meta.isNotEmpty)
                  Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: cs.onSurface.withValues(alpha: .5))),
              ]),
            ),
            const SizedBox(width: 8),
            Tooltip(
              message: 'Passer à « ${pantryStateLabel(nextPantryState(p.state))} »',
              child: Material(
                color: c.withValues(alpha: .18),
                borderRadius: BorderRadius.circular(20),
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => logic.setPantryState(p.label, nextPantryState(p.state)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                    child: Text(pantryStateLabel(p.state), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: c)),
                  ),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Réglages d'un produit : état, rayon, habituel, retirer.
Future<void> showPantryItemEditor(BuildContext context, {required AppLogic logic, required PantryItem item}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
      final cs = Theme.of(ctx).colorScheme;
      final p = logic.groceries.pantry[item.key] ?? item;
      final aisles = [...logic.groceries.aisles, if (!logic.groceries.aisles.contains(p.aisle)) p.aisle];
      Future<void> save(PantryItem next) async {
        await logic.updatePantryItem(next);
        setS(() {});
      }

      Widget pill(String label, bool on, Color c, VoidCallback onTap) => Padding(
            padding: const EdgeInsets.only(right: 6, bottom: 6),
            child: Material(
              color: on ? c.withValues(alpha: .22) : cs.onSurface.withValues(alpha: .06),
              borderRadius: BorderRadius.circular(20),
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  child: Text(label, style: TextStyle(fontSize: 13, fontWeight: on ? FontWeight.w800 : FontWeight.w600, color: on ? c : cs.onSurface.withValues(alpha: .75))),
                ),
              ),
            ),
          );
      Text section(String t) => Text(t, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: .6, color: cs.onSurface.withValues(alpha: .5)));

      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(p.label, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
            if (p.boughtAt != null)
              Text('acheté le ${_dayLabel(p.boughtAt!)}', style: TextStyle(fontSize: 12.5, color: cs.onSurface.withValues(alpha: .5))),
            const SizedBox(height: 14),
            section('CHEZ TOI'),
            const SizedBox(height: 8),
            Wrap(children: [
              for (final s in PantryState.values) pill(pantryStateLabel(s), p.state == s, pantryStateColor(s), () => save(p.copyWith(state: s))),
            ]),
            const SizedBox(height: 10),
            section('RAYON'),
            const SizedBox(height: 8),
            Wrap(children: [
              for (final a in aisles) pill(a, p.aisle == a, aisleColor(logic.groceries.aisles, a), () => save(p.copyWith(aisle: a))),
            ]),
            const SizedBox(height: 4),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: p.staple,
              onChanged: (v) => save(p.copyWith(staple: v)),
              title: const Text('Produit habituel', style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text('Revient sur la liste dès qu\'il n\'y en a plus'),
              activeThumbColor: kGroceryAccent,
            ),
            if (p.state != PantryState.have && !p.staple && !logic.groceries.items.values.any((x) => normLabel(x.label) == p.key && !x.inBasket))
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: OutlinedButton.icon(
                  key: const ValueKey('pantry-add-to-list'),
                  onPressed: () async {
                    await logic.addGrocery(label: p.label, aisle: p.aisle, source: 'pantry');
                    setS(() {});
                  },
                  icon: const Icon(Icons.add_shopping_cart_outlined, size: 18),
                  label: const Text('Ajouter à la liste de courses'),
                ),
              ),
            const SizedBox(height: 4),
            TextButton.icon(
              onPressed: () async {
                Navigator.pop(ctx);
                await logic.removePantryItem(p.key);
              },
              icon: const Icon(Icons.delete_outline_rounded, size: 18),
              label: const Text('Retirer des placards'),
              style: TextButton.styleFrom(foregroundColor: cs.error),
            ),
          ]),
        ),
      );
    }),
  );
}

/// Les rayons : ajouter, renommer, retirer (« Autre » reste).
Future<void> showAislesSheet(BuildContext context, {required AppLogic logic}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
      final cs = Theme.of(ctx).colorScheme;
      final g = logic.groceries;
      int count(String a) => g.pantry.values.where((p) => p.aisle == a).length;
      Future<String?> ask(String title, {String initial = ''}) {
        final c = TextEditingController(text: initial);
        return showDialog<String>(
          context: ctx,
          builder: (d) => AlertDialog(
            title: Text(title),
            content: TextField(controller: c, autofocus: true, textCapitalization: TextCapitalization.sentences, onSubmitted: (v) => Navigator.pop(d, v)),
            actions: [
              TextButton(onPressed: () => Navigator.pop(d), child: const Text('Annuler')),
              FilledButton(onPressed: () => Navigator.pop(d, c.text), child: const Text('OK')),
            ],
          ),
        );
      }

      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            const Text('Rayons', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900)),
            Text('Dans l\'ordre du magasin. Claude peut aussi en ajouter.', style: TextStyle(fontSize: 12.5, color: cs.onSurface.withValues(alpha: .5))),
            const SizedBox(height: 8),
            for (final a in g.aisles)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Container(width: 12, height: 12, decoration: BoxDecoration(color: aisleColor(g.aisles, a), borderRadius: BorderRadius.circular(3))),
                title: Text(a, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                subtitle: Text('${count(a)} produit${count(a) > 1 ? 's' : ''}'),
                trailing: a == kOtherAisle
                    ? null
                    : Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(
                          tooltip: 'Renommer',
                          icon: const Icon(Icons.edit_outlined, size: 19),
                          onPressed: () async {
                            final n = await ask('Renommer « $a »', initial: a);
                            if (n == null || n.trim().isEmpty) return;
                            await logic.renameAisle(a, n.trim());
                            setS(() {});
                          },
                        ),
                        IconButton(
                          tooltip: 'Retirer',
                          icon: const Icon(Icons.delete_outline_rounded, size: 19),
                          onPressed: () async {
                            await logic.removeAisle(a);
                            setS(() {});
                          },
                        ),
                      ]),
              ),
            const SizedBox(height: 6),
            FilledButton.icon(
              onPressed: () async {
                final n = await ask('Nouveau rayon');
                if (n == null || n.trim().isEmpty) return;
                await logic.addAisle(n.trim());
                setS(() {});
              },
              icon: const Icon(Icons.add_rounded),
              label: const Text('Ajouter un rayon'),
              style: FilledButton.styleFrom(backgroundColor: kGroceryAccent, foregroundColor: kGroceryInk),
            ),
          ]),
        ),
      );
    }),
  );
}
