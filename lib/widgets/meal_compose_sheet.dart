import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/utils/groceries.dart' show normLabel, PantryState;
import 'package:productivitwo_v1/widgets/undo_snack.dart' show ClosingSnackBar;
import 'package:productivitwo_v1/utils/meal_compose.dart';
import 'package:productivitwo_v1/utils/meal_families.dart';
import 'package:productivitwo_v1/utils/meal_plan.dart';
import 'package:productivitwo_v1/widgets/dishes_sheet.dart' show kMealAccent;
import 'package:productivitwo_v1/widgets/fiche.dart' show showFiche;
import 'package:productivitwo_v1/utils/engagement_stats.dart' show ymdOf;

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
  // Le jour composé (retour user 2026-11-05 : préparer vendredi depuis la feuille d'aujourd'hui).
  late String _ymd = widget.ymd;
  String get _monday => _mondayOf(_ymd);
  // Les briques choisies par famille qui compte (plusieurs possibles depuis le 2026-11-05 : œufs ET
  // bacon) ; accompagnements à part.
  final Map<String, List<MealComponent>> _pick = {};
  final Set<String> _sides = {};
  int _idea = 0;
  bool _loaded = false;

  AppLogic get logic => widget.logic;
  String get _key => mealKey(_ymd, _moment);

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
    final cur = logic.mealWeek(_monday).slots[_key];
    if (cur != null && cur.isComposed) {
      for (final c in cur.components) {
        if (countsInMeal(c.families)) {
          for (final f in c.families) {
            if (kMealFamilies.contains(f)) _add(f, c);
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
      for (final f in kMealFamilies)
        for (final c in _pick[f] ?? const <MealComponent>[])
          if (seen.add(normLabel(c.label))) c,
      for (final s in _sides) MealComponent(s, const [kAccompagnement]),
    ];
  }

  bool _has(String family, String label) => (_pick[family] ?? const []).any((x) => normLabel(x.label) == normLabel(label));

  void _add(String family, MealComponent c) {
    if (_has(family, c.label)) return;
    (_pick[family] ??= []).add(c);
  }

  void _remove(String label) {
    for (final l in _pick.values) {
      l.removeWhere((x) => normLabel(x.label) == normLabel(label));
    }
    _pick.removeWhere((_, l) => l.isEmpty);
  }

  /// Toucher une brique l'ajoute (à toutes ses familles) ou la retire ; plusieurs par famille.
  void _toggle(String family, MealComponent c) {
    setState(() {
      if (_has(family, c.label)) {
        _remove(c.label);
      } else {
        for (final f in c.families) {
          if (kMealFamilies.contains(f)) _add(f, c);
        }
        if (!c.families.contains(family)) _add(family, c);
      }
    });
  }

  Future<void> _save(List<MealComponent> cs) async {
    final cur = logic.mealWeek(_monday).slots[_key];
    final meal = PlannedMeal(title: composedTitle(cs), components: cs, ate: cur?.ate, ateWhat: cur?.ateWhat);
    await logic.setMeal(_monday, _key, meal);
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

  void _goDay(String ymd) => setState(() {
        _ymd = ymd;
        _loaded = false;
      });

  /// Les 7 jours de la semaine du jour composé, ‹ › pour changer de semaine ; un point = un repas déjà posé.
  Widget _dayStrip(ColorScheme cs, Color mute) {
    final monday = DateTime.parse(_monday);
    final today = ymdOf(DateTime.now());
    final week = logic.mealWeek(_monday);
    String shift(int days) => ymdOf(DateTime(monday.year, monday.month, monday.day + days));
    return Row(children: [
      IconButton(
        key: const Key('compose-prev-week'),
        visualDensity: VisualDensity.compact,
        tooltip: 'Semaine d’avant',
        onPressed: () => _goDay(shift(-7 + DateTime.parse(_ymd).weekday - 1)),
        icon: const Icon(Icons.chevron_left_rounded),
      ),
      for (var i = 0; i < 7; i++)
        Expanded(child: Builder(builder: (_) {
          final y = shift(i);
          final on = y == _ymd;
          final has = kMealMoments.any((m) => week.slots[mealKey(y, m)] != null);
          final d = DateTime.parse(y);
          return InkWell(
            key: Key('compose-day-$y'),
            borderRadius: BorderRadius.circular(10),
            onTap: () => _goDay(y),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                color: on ? kMealAccent.withValues(alpha: .22) : null,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: on ? kMealAccent : Colors.transparent, width: 1.5),
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(_kDays[i], style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: mute)),
                Text('${d.day}', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: y == today ? kMealAccent : null)),
                Container(width: 5, height: 5, decoration: BoxDecoration(shape: BoxShape.circle, color: has ? kMealAccent : Colors.transparent)),
              ]),
            ),
          );
        })),
      IconButton(
        key: const Key('compose-next-week'),
        visualDensity: VisualDensity.compact,
        tooltip: 'Semaine d’après',
        onPressed: () => _goDay(shift(7 + DateTime.parse(_ymd).weekday - 1)),
        icon: const Icon(Icons.chevron_right_rounded),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) _loadCurrent();
    final cs = Theme.of(context).colorScheme;
    final mute = cs.onSurface.withValues(alpha: .55);
    final history = composedHistory(logic.meals);
    final learned = learnedBreakfast(history);
    final opts = optionsFor(logic.groceries, _moment, learned: learned);
    final ideas = suggestMeals(g: logic.groceries, ymd: _ymd, moment: _moment, history: history);
    final idea = ideas.isEmpty ? null : ideas[_idea % ideas.length];
    final week = logic.mealWeek(_monday);
    final picked = _components;
    final covered = coveredFamilies(picked);
    final valid = covered.length >= 2;
    final sides = opts[kAccompagnement] ?? const <MealComponent>[];

    Widget chip(String family, MealComponent c) {
      final color = kFamilyColors[family]!;
      final on = family == kAccompagnement ? _sides.contains(c.label) : _has(family, c.label);
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
      // Une brique choisie reste dans sa rangée même si le placard ne la propose pas à ce moment
      // (bug user 2026-11-05 : « Bacon » tapé au petit-déj était choisi sans se voir).
      final base = opts[family] ?? const <MealComponent>[];
      final list = [
        ...base,
        for (final c in _pick[family] ?? const <MealComponent>[])
          if (!base.any((b) => normLabel(b.label) == normLabel(c.label))) c,
      ];
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
      final chosen = _pick[family] ?? const <MealComponent>[];
      final c = chosen.isEmpty ? null : chosen.map((x) => x.label).join(' + ');
      final color = kFamilyColors[family]!;
      return Expanded(
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: c != null ? color.withValues(alpha: .2) : null,
            border: c == null ? Border.all(color: cs.outlineVariant) : null,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(familyLabel(family).replaceAll(RegExp(r's$'), ''), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
            Text(c ?? '—', maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c == null ? mute : null)),
          ]),
        ),
      );
    }

    return ListView(controller: widget.scroll, padding: const EdgeInsets.fromLTRB(20, 8, 20, 32), children: [
      Text('Composer · ${_dayTitle(_ymd)}', style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
      const SizedBox(height: 8),
      _dayStrip(cs, mute),
      const SizedBox(height: 10),
      SegmentedButton<String>(
        key: const Key('compose-moment'),
        segments: [
          for (final m in kMealMoments)
            ButtonSegment(
              value: m,
              label: Text('${kMealMomentLabel[m]}${week.slots[mealKey(_ymd, m)] != null ? ' ✓' : ''}'),
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
      Text(idea != null ? 'Ou compose : une ou plusieurs briques par famille' : 'Deux familles suffisent, plusieurs briques possibles',
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

const _kDays = ['lu', 'ma', 'me', 'je', 've', 'sa', 'di'];
const _kDayNames = ['lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche'];
const _kMonths = ['janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'];

String _mondayOf(String ymd) {
  final d = DateTime.parse(ymd);
  return ymdOf(DateTime(d.year, d.month, d.day - (d.weekday - 1)));
}

/// « aujourd'hui » · « demain » · « vendredi 6 nov. ».
String _dayTitle(String ymd) {
  final d = DateTime.parse(ymd);
  final n = DateTime.now();
  final diff = DateTime(d.year, d.month, d.day).difference(DateTime(n.year, n.month, n.day)).inDays;
  if (diff == 0) return 'aujourd’hui';
  if (diff == 1) return 'demain';
  return '${_kDayNames[d.weekday - 1]} ${d.day} ${_kMonths[d.month - 1]}';
}
