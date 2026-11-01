import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/duration_fmt.dart' show fmtMin;
import 'package:productivitwo_v1/utils/engagement_stats.dart' show ymdOf;
import 'package:productivitwo_v1/utils/game_rules.dart';
import 'package:productivitwo_v1/utils/meal_day.dart';
import 'package:productivitwo_v1/utils/meal_plan.dart';
import 'package:productivitwo_v1/widgets/dishes_sheet.dart' show kMealAccent, showDishesSheet;
import 'package:productivitwo_v1/widgets/fiche.dart' show showFiche;
import 'package:productivitwo_v1/widgets/info_dot.dart';
import 'package:productivitwo_v1/widgets/meal_week_sheet.dart' show showMealWeekSheet, showShoppingSheet;
import 'package:productivitwo_v1/widgets/routines_day_view.dart' show routinePlus;

const _kAmber = Color(0xFFF0B44C);
const _kCook = Color(0xFFF0A35C);
const _kPlanned = Color(0xFF9DB8FF);
const _letters = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];

const kRuleMeals = GameRule('Les repas', [
  RuleCard('✅', 'Équilibré', 'Un +1 de ta routine Repas équilibré (ou « ✓ Mangé, équilibré » ici) dans le moment : avant 16 h c’est le midi, après le soir.'),
  RuleCard('🍝', 'Autre chose', 'Un repas noté sans le +1 : « Autre chose », un chrono Manger, ou « Dehors ». Il compte comme mangé, pas comme équilibré.'),
  RuleCard('🥡', 'Les restes', 'Un plat de plusieurs portions remplit tout seul les midis suivants dans le menu de la semaine.'),
  RuleCard('🛒', 'Les courses', 'La liste additionne les ingrédients des plats posés dans la semaine, et dit d’où vient chaque ligne.'),
]);

String _clock(int m) => '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';

/// Feuille « Repas » (maquette validée 2026-11-01 « Repas et menu », écran 1) :
/// le repas qui vient, la semaine midi / soir, trois chiffres, tes heures de
/// repas ; liens vers le menu, Mes plats et la liste de courses.
Future<void> showMealSheet(BuildContext context, {required AppLogic logic, required FirestoreSync sync}) {
  return showFiche<void>(context, builder: (ctx, scroll) => MealSheet(logic: logic, sync: sync, scroll: scroll));
}

class MealSheet extends StatefulWidget {
  final AppLogic logic;
  final FirestoreSync sync;
  final ScrollController? scroll;
  final Stream<List<Recipe>>? recipes;
  const MealSheet({super.key, required this.logic, required this.sync, this.scroll, this.recipes});

  @override
  State<MealSheet> createState() => _MealSheetState();
}

class _MealSheetState extends State<MealSheet> {
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
    final t = logic.livedToday;
    return DateTime(t.year, t.month, t.day - (t.weekday - 1));
  }

  List<String> get _days => [for (var i = 0; i < 7; i++) ymdOf(DateTime(_monday.year, _monday.month, _monday.day + i))];

  Future<void> _eaten(String key, PlannedMeal? slot, {required bool balanced}) async {
    final monday = ymdOf(_monday);
    await logic.setMeal(monday, key, (slot ?? PlannedMeal(title: balanced ? 'Repas équilibré' : 'Autre chose')).withAte(balanced ? 'ok' : 'other'));
    if (balanced) {
      final r = logic.state.activities.where(isBalancedMealRoutine).firstOrNull;
      if (r != null) routinePlus(logic, r);
      if (slot != null && !slot.out && slot.recipeId != null) {
        try {
          await widget.sync.recordMealCooked(slot.title);
        } catch (_) {}
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final mute = cs.onSurface.withValues(alpha: .55);
    final now = DateTime.now();
    final st = logic.state;
    final monday = ymdOf(_monday);
    final week = logic.mealWeek(monday);
    final today = ymdOf(logic.livedToday);
    final moment = currentMealMoment(now);
    final key = mealKey(today, moment);
    final v = mealWeekView(days: _days, week: week, activities: st.activities, hits: st.habitHits, sessions: st.sessions, now: now, dayStartMin: logic.dayStartMin);
    final cook = st.activities.where(isCookActivity).firstOrNull;
    return StreamBuilder<List<Recipe>>(
      stream: _recipes,
      builder: (ctx, snap) {
        _all = snap.data ?? _all;
        final left = leftoversOf(week.slots, _days);
        final slot = week.slots[key];
        final fromSlot = left[key] == null ? null : week.slots[left[key]];
        final recipe = slot?.recipeId == null ? null : _all.where((r) => r.id == slot!.recipeId).firstOrNull;
        final lines = shoppingFor(week, _all);
        final toBuy = lines.where((l) => !week.checked.contains(l.key)).length;
        final done = v.cells[key] == MealCell.ok || slot?.ate != null;

        Widget title(String t, [String? right]) => Padding(
              padding: const EdgeInsets.only(top: 20, bottom: 8),
              child: Row(children: [
                Expanded(child: Text(t, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: .8, color: mute))),
                if (right != null) Text(right, style: TextStyle(fontSize: 11.5, color: mute)),
              ]),
            );
        Widget stat(String val, String lab, {Color? color}) => Expanded(
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: cs.surfaceContainerHighest.withValues(alpha: .35), borderRadius: BorderRadius.circular(14)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(val, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: color)),
                  Text(lab, style: TextStyle(fontSize: 11.5, color: mute)),
                ]),
              ),
            );
        Color cellColor(MealCell c) => switch (c) {
              MealCell.ok => kMealAccent,
              MealCell.other => const Color(0xFF3A2F1B),
              MealCell.planned => const Color(0xFF1D2742),
              _ => cs.onSurface.withValues(alpha: .06),
            };
        String cellText(MealCell c) => switch (c) { MealCell.ok => '✓', MealCell.other => '~', MealCell.none => '?', _ => '' };

        final heroTitle = slot != null ? slot.title : (fromSlot != null ? 'Les restes · ${fromSlot.title}' : 'Rien de prévu');
        final heroSub = [
          if (slot != null && !slot.out && slot.portions > 1) '${slot.portions} portions → les midis suivants',
          if (recipe?.minutes != null) fmtMin(recipe!.minutes!),
          if (slot == null && fromSlot == null) 'choisis un plat dans le menu de la semaine',
        ].join(' · ');

        return ListView(controller: widget.scroll, padding: const EdgeInsets.fromLTRB(20, 8, 20, 32), children: [
          Row(children: [
            const Expanded(child: Text('Repas', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900))),
            if (v.counted > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(color: kMealAccent.withValues(alpha: .16), borderRadius: BorderRadius.circular(20)),
                child: Text('${v.balanced} / ${v.counted} équilibrés', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: kMealAccent)),
              ),
            const SizedBox(width: 6),
            const InfoDot(kRuleMeals),
          ]),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF1D2A1A), Color(0xFF15211C)]),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFF2F4A2A)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(moment == 'midi' ? 'CE MIDI' : 'CE SOIR', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: .8, color: mute)),
              const SizedBox(height: 2),
              Text(heroTitle, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
              if (heroSub.isNotEmpty) Text(heroSub, style: TextStyle(fontSize: 13, color: mute)),
              const SizedBox(height: 10),
              if (done)
                Text(v.cells[key] == MealCell.ok ? '✓ Mangé, équilibré' : '✓ Noté : autre chose', style: const TextStyle(fontWeight: FontWeight.w700, color: kMealAccent))
              else
                Wrap(spacing: 8, runSpacing: 8, children: [
                  if (cook != null)
                    FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: _kCook, foregroundColor: const Color(0xFF1D1206)),
                      onPressed: () {
                        logic.start(cook.id);
                        Navigator.of(context).pop();
                      },
                      icon: const Icon(Icons.play_arrow_rounded, size: 18),
                      label: const Text('Cuisiner'),
                    ),
                  OutlinedButton(onPressed: () => _eaten(key, slot ?? fromSlot, balanced: true), child: const Text('✓ Mangé, équilibré')),
                  OutlinedButton(onPressed: () => _eaten(key, slot, balanced: false), child: const Text('Autre chose')),
                ]),
            ]),
          ),
          title('CETTE SEMAINE', 'midi · soir'),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: cs.surfaceContainerHighest.withValues(alpha: .35), borderRadius: BorderRadius.circular(16)),
            child: Column(children: [
              Row(children: [
                const SizedBox(width: 38),
                for (final l in _letters) Expanded(child: Center(child: Text(l, style: TextStyle(fontSize: 11, color: mute)))),
              ]),
              for (final m in kMealMoments)
                Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Row(children: [
                    SizedBox(width: 38, child: Text(m, style: TextStyle(fontSize: 11, color: mute))),
                    for (final d in _days)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: Container(
                            height: 28,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: cellColor(v.cells[mealKey(d, m)] ?? MealCell.empty),
                              borderRadius: BorderRadius.circular(7),
                              border: mealKey(d, m) == key ? Border.all(color: cs.onSurface, width: 1.5) : null,
                            ),
                            child: Text(
                              cellText(v.cells[mealKey(d, m)] ?? MealCell.empty),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: v.cells[mealKey(d, m)] == MealCell.ok ? const Color(0xFF0F1A0C) : (v.cells[mealKey(d, m)] == MealCell.other ? _kAmber : mute),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ]),
                ),
              const SizedBox(height: 8),
              Wrap(spacing: 10, runSpacing: 4, children: [
                for (final (c, l) in [(kMealAccent, 'équilibré'), (const Color(0xFF3A2F1B), 'autre chose'), (_kPlanned, 'prévu'), (cs.onSurface.withValues(alpha: .1), 'rien noté')])
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(width: 9, height: 9, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3))),
                    const SizedBox(width: 4),
                    Text(l, style: TextStyle(fontSize: 11.5, color: mute)),
                  ]),
              ]),
            ]),
          ),
          const SizedBox(height: 10),
          Row(children: [
            stat('${v.balanced} / ${v.counted}', 'repas équilibrés'),
            const SizedBox(width: 8),
            stat(v.cookMin == 0 ? '—' : fmtMin(v.cookMin), 'cuisiné cette semaine'),
            const SizedBox(width: 8),
            stat('${v.skippedLunches}', 'midi${v.skippedLunches > 1 ? 's' : ''} sans rien', color: v.skippedLunches > 0 ? _kAmber : null),
          ]),
          if (v.lunchClock != null || v.dinnerClock != null) ...[
            title('TES HEURES DE REPAS', 'd’après Manger'),
            Text(
              [
                if (v.lunchClock != null) 'Midi vers ${_clock(v.lunchClock!)}',
                if (v.dinnerClock != null) 'dîner vers ${_clock(v.dinnerClock!)}',
              ].join(' · '),
              style: const TextStyle(fontSize: 14),
            ),
          ],
          const SizedBox(height: 18),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: kMealAccent, foregroundColor: const Color(0xFF0F1A0C), minimumSize: const Size.fromHeight(50)),
            onPressed: () => showMealWeekSheet(context, logic: logic, sync: widget.sync),
            icon: const Icon(Icons.calendar_view_week_rounded),
            label: const Text('Les repas de la semaine', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
          Wrap(alignment: WrapAlignment.spaceBetween, children: [
            TextButton(onPressed: () => showDishesSheet(context, sync: widget.sync), child: const Text('Mes plats ›')),
            TextButton(
              onPressed: () => showShoppingSheet(context, logic: logic, sync: widget.sync, monday: monday, recipes: _all),
              child: Text('Liste de courses${toBuy > 0 ? ' · $toBuy' : ''}'),
            ),
          ]),
        ]);
      },
    );
  }
}
