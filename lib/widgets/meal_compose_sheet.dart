import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/utils/groceries.dart' show normLabel, PantryState;
import 'package:productivitwo_v1/widgets/undo_snack.dart' show ClosingSnackBar;
import 'package:productivitwo_v1/utils/meal_compose.dart';
import 'package:productivitwo_v1/utils/meal_families.dart';
import 'package:productivitwo_v1/utils/meal_plan.dart';
import 'package:productivitwo_v1/widgets/dishes_sheet.dart' show kMealAccent;
import 'package:productivitwo_v1/widgets/fiche.dart' show showFiche;

/// Couleurs des familles (maquette « Repas en 3 familles »).
const kFamilyColors = {
  kProteines: Color(0xFFE9776A),
  kFeculents: Color(0xFFE8A93D),
  kFibres: Color(0xFF5DBB82),
  kAccompagnement: Color(0xFF8A93A6),
};

/// « Composer un repas » (maquette validée 2026-11-04, Repas en 3 familles,
/// lot 2) : une idée prête avec ce qu'on a, sinon une brique par famille ;
/// « Valider » dès 2 familles sur 3. Sélecteur Petit-déj · Midi · Soir.
Future<void> showMealComposeSheet(BuildContext context, {required AppLogic logic, required String monday, required String ymd, required String moment}) {
  return showFiche<void>(context, builder: (ctx, scroll) => MealComposeSheet(logic: logic, monday: monday, ymd: ymd, moment: moment, scroll: scroll));
}

class MealComposeSheet extends StatefulWidget {
  final AppLogic logic;
  final String monday;
  final String ymd;
  final String moment;
  final ScrollController? scroll;
  const MealComposeSheet({super.key, required this.logic, required this.monday, required this.ymd, required this.moment, this.scroll});

  @override
  State<MealComposeSheet> createState() => _MealComposeSheetState();
}

class _MealComposeSheetState extends State<MealComposeSheet> {
  late String _moment = widget.moment;
  // Une brique par famille qui compte ; accompagnements à part (plusieurs).
  final Map<String, MealComponent> _pick = {};
  final Set<String> _sides = {};
  int _idea = 0;
  bool _loaded = false;

  AppLogic get logic => widget.logic;
  String get _key => mealKey(widget.ymd, _moment);

  @override
  void initState() {
    super.initState();
    _loadCurrent();
  }

  /// Le repas déjà composé de ce créneau, s'il y en a un.
  void _loadCurrent() {
    _pick.clear();
    _sides.clear();
    _idea = 0;
    final cur = logic.mealWeek(widget.monday).slots[_key];
    if (cur != null && cur.isComposed) {
      for (final c in cur.components) {
        if (countsInMeal(c.families)) {
          for (final f in c.families) {
            if (kMealFamilies.contains(f)) _pick[f] = c;
          }
        } else {
          _sides.add(c.label);
        }
      }
    }
    _loaded = true;
  }

  List<MealComponent> get _components {
    final seen = <String>{};
    return [
      for (final c in _pick.values)
        if (seen.add(normLabel(c.label))) c,
      for (final s in _sides) MealComponent(s, const [kAccompagnement]),
    ];
  }

  void _toggle(String family, MealComponent c) {
    setState(() {
      if (_pick[family]?.label == c.label) {
        // Retirer : la brique quitte toutes ses familles.
        _pick.removeWhere((_, v) => v.label == c.label);
      } else {
        _pick.removeWhere((_, v) => v.label == c.label);
        for (final f in c.families) {
          if (kMealFamilies.contains(f)) _pick[f] = c;
        }
        if (!c.families.contains(family)) _pick[family] = c;
      }
    });
  }

  Future<void> _save(List<MealComponent> cs) async {
    final cur = logic.mealWeek(widget.monday).slots[_key];
    final meal = PlannedMeal(title: composedTitle(cs), components: cs, ate: cur?.ate, ateWhat: cur?.ateWhat);
    await logic.setMeal(widget.monday, _key, meal);
    if (mounted) await Navigator.of(context).maybePop();
  }

  /// Une brique qui n'est pas au placard (tapée à la main).
  Future<void> _addOther(String family) async {
    final ctrl = TextEditingController();
    final label = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(family == kAccompagnement ? 'Un accompagnement' : '${familyLabel(family)} : autre chose'),
        content: TextField(
          key: const Key('compose-other-text'),
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'Steak, riz, salade…'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Ajouter')),
        ],
      ),
    );
    final l = label?.trim() ?? '';
    if (l.isEmpty || !mounted) return;
    // Retour user 2026-11-04 : la brique tapée était choisie sans se voir (pas de pastille). Elle va
    // au placard (« J'en ai » : on compose avec ce qu'on a) et garde la famille de la rangée ; elle
    // apparaît alors dans la rangée, déjà choisie.
    final k = normLabel(l);
    final known = logic.groceries.pantry[k];
    if (known == null || known.state == PantryState.out) await logic.setPantryState(l, PantryState.have);
    final label2 = logic.groceries.pantry[k]?.label ?? l;
    if (!familiesFor(logic.groceries, label2).contains(family)) await logic.setFoodFamilies(label2, [family]);
    if (!mounted) return;
    final c = MealComponent(label2, familiesFor(logic.groceries, label2));
    if (family == kAccompagnement) {
      setState(() => _sides.add(label2));
    } else {
      _toggle(family, c);
    }
    ScaffoldMessenger.maybeOf(context)?.showClosingSnackBar(SnackBar(content: Text('$label2 ajouté au repas et à tes placards'), duration: const Duration(seconds: 3)));
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) _loadCurrent();
    final cs = Theme.of(context).colorScheme;
    final mute = cs.onSurface.withValues(alpha: .55);
    final history = composedHistory(logic.meals);
    final learned = learnedBreakfast(history);
    final opts = optionsFor(logic.groceries, _moment, learned: learned);
    final ideas = suggestMeals(g: logic.groceries, ymd: widget.ymd, moment: _moment, history: history);
    final idea = ideas.isEmpty ? null : ideas[_idea % ideas.length];
    final week = logic.mealWeek(widget.monday);
    final picked = _components;
    final covered = coveredFamilies(picked);
    final valid = covered.length >= 2;
    final sides = opts[kAccompagnement] ?? const <MealComponent>[];

    Widget chip(String family, MealComponent c) {
      final color = kFamilyColors[family]!;
      final on = family == kAccompagnement ? _sides.contains(c.label) : _pick[family]?.label == c.label;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: FilterChip(
          key: Key('compose-${family}-${normLabel(c.label)}'),
          label: Text(c.label),
          selected: on,
          showCheckmark: false,
          selectedColor: color.withValues(alpha: .28),
          side: BorderSide(color: on ? color : cs.outlineVariant, width: on ? 2 : 1),
          onSelected: (_) {
            if (family == kAccompagnement) {
              setState(() => _sides.contains(c.label) ? _sides.remove(c.label) : _sides.add(c.label));
            } else {
              _toggle(family, c);
            }
          },
        ),
      );
    }

    Widget row(String family) {
      final list = opts[family] ?? const <MealComponent>[];
      final color = kFamilyColors[family]!;
      return Padding(
        padding: const EdgeInsets.only(top: 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(5))),
            const SizedBox(width: 8),
            Text(familyLabel(family), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
            if (family == kFibres) ...[
              const SizedBox(width: 6),
              Text(_moment == kBreakfast ? 'fruits' : 'légumes, fruits', style: TextStyle(fontSize: 12, color: mute)),
            ],
          ]),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (final c in list) chip(family, c),
              ActionChip(
                key: Key('compose-other-$family'),
                avatar: const Icon(Icons.add_rounded, size: 16),
                label: Text(list.isEmpty ? 'Rien au placard · autre' : 'Autre'),
                onPressed: () => _addOther(family),
              ),
            ]),
          ),
        ]),
      );
    }

    Widget plateCell(String family) {
      final c = _pick[family];
      final color = kFamilyColors[family]!;
      return Expanded(
        child: Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: c != null ? color.withValues(alpha: .2) : null,
            border: c == null ? Border.all(color: cs.outlineVariant) : null,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(familyLabel(family).replaceAll(RegExp(r's$'), ''), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
            Text(c?.label ?? '—', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c == null ? mute : null)),
          ]),
        ),
      );
    }

    return ListView(controller: widget.scroll, padding: const EdgeInsets.fromLTRB(20, 8, 20, 32), children: [
      const Text('Composer un repas', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
      const SizedBox(height: 10),
      SegmentedButton<String>(
        key: const Key('compose-moment'),
        segments: [
          for (final m in kMealMoments)
            ButtonSegment(
              value: m,
              label: Text('${kMealMomentLabel[m]}${week.slots[mealKey(widget.ymd, m)] != null ? ' ✓' : ''}'),
            ),
        ],
        selected: {_moment},
        showSelectedIcon: false,
        onSelectionChanged: (s) => setState(() {
          _moment = s.first;
          _loaded = false;
        }),
      ),
      if (idea != null) ...[
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withValues(alpha: .35),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: kMealAccent),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('IDÉE AVEC CE QUE TU AS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: .8, color: kMealAccent)),
            const SizedBox(height: 4),
            Text(idea.title, key: const Key('compose-idea'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            if (idea.reasons.isNotEmpty || sides.isNotEmpty)
              Text(
                [
                  if (sides.isNotEmpty) 'avec : ${sides.take(3).map((c) => c.label.toLowerCase()).join(', ')}',
                  ...idea.reasons,
                ].join(' · '),
                style: TextStyle(fontSize: 13, color: mute),
              ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: FilledButton(
                  key: const Key('compose-take'),
                  style: FilledButton.styleFrom(backgroundColor: kMealAccent, foregroundColor: const Color(0xFF0F1A0C), minimumSize: const Size.fromHeight(44)),
                  onPressed: () => _save(idea.components),
                  child: const Text('Je prends', style: TextStyle(fontWeight: FontWeight.w800)),
                ),
              ),
              if (ideas.length > 1) ...[
                const SizedBox(width: 8),
                OutlinedButton(
                  key: const Key('compose-next-idea'),
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                  onPressed: () => setState(() => _idea++),
                  child: const Text('Autre idée'),
                ),
              ],
            ]),
          ]),
        ),
      ],
      const SizedBox(height: 16),
      Text(idea != null ? 'Ou compose : une brique par famille' : 'Une brique par famille, deux familles suffisent',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: mute)),
      for (final f in kMealFamilies) row(f),
      if (sides.isNotEmpty || _sides.isNotEmpty) ...[
        const SizedBox(height: 14),
        Text('Avec (facultatif)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: mute)),
        const SizedBox(height: 6),
        Wrap(children: [
          for (final c in sides) chip(kAccompagnement, c),
          for (final s in _sides.where((s) => !sides.any((c) => c.label == s))) chip(kAccompagnement, MealComponent(s, const [kAccompagnement])),
        ]),
      ],
      const SizedBox(height: 20),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: cs.surfaceContainerHighest.withValues(alpha: .35), borderRadius: BorderRadius.circular(20)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [plateCell(kProteines), const SizedBox(width: 8), plateCell(kFeculents), const SizedBox(width: 8), plateCell(kFibres)]),
          const SizedBox(height: 12),
          FilledButton(
            key: const Key('compose-save'),
            style: FilledButton.styleFrom(backgroundColor: kMealAccent, foregroundColor: const Color(0xFF0F1A0C), minimumSize: const Size.fromHeight(50)),
            onPressed: valid ? () => _save(picked) : null,
            child: Text(
              valid ? 'Valider · ${covered.length} familles sur 3' : 'Choisis encore ${2 - covered.length} famille${covered.length == 1 ? '' : 's'}',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ]),
      ),
    ]);
  }
}
