import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/models.dart';

Future<void> showCoursesSheet(BuildContext context,
    {required AppLogic logic}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _CoursesSheet(logic: logic),
  );
}

class _CoursesSheet extends StatefulWidget {
  final AppLogic logic;
  const _CoursesSheet({required this.logic});

  @override
  State<_CoursesSheet> createState() => _CoursesSheetState();
}

class _CoursesSheetState extends State<_CoursesSheet> {
  final Set<String> _selected = {};

  AppLogic get logic => widget.logic;
  AppState get st => logic.state;

  List<DayPlanItem> get _reserve => st.dayPlan
      .where((a) =>
          a.kind == PlanKind.action &&
          a.toPlan == true &&
          a.archived == true &&
          !a.done)
      .toList()
    ..sort((a, b) => a.title.compareTo(b.title));

  List<DayPlanItem> get _active => st.dayPlan
      .where((a) =>
          a.kind == PlanKind.action &&
          a.toPlan == true &&
          a.archived != true &&
          !a.done)
      .toList()
    ..sort((a, b) => a.title.compareTo(b.title));

  Map<String, Activity> get _habitsById => {
        for (final a in st.activities.where((x) => x.isHabit)) a.id: a
      };

  String _habitName(String? habitId) {
    if (habitId == null || habitId.isEmpty) return 'Sans routine';
    return _habitsById[habitId]?.name ?? 'Routine';
  }

  void _addToPlan() {
    for (final id in _selected) {
      final item = st.dayPlan.firstWhereOrNull((a) => a.id == id);
      if (item != null) {
        item.archived = false;
        item.done = false;
        item.toPlan = true;
      }
    }
    logic.onChange();
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final reserve = _reserve;
    final active = _active;

    final byHabit = <String?, List<DayPlanItem>>{};
    for (final it in reserve) {
      (byHabit[it.habitId] ??= []).add(it);
    }
    final habitIds = byHabit.keys.toList()
      ..sort((a, b) => _habitName(a).compareTo(_habitName(b)));

    final allSelected = reserve.isNotEmpty &&
        _selected.length == reserve.length;

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
            child: Row(
              children: [
                Icon(Icons.shopping_cart_outlined,
                    size: 20, color: cs.onSurface.withOpacity(.7)),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Liste de courses',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add),
                  tooltip: 'Ajouter un article',
                  onPressed: () async {
                    final ctrl = TextEditingController();
                    final habits = st.activities
                        .where((a) => a.isHabit)
                        .toList()
                      ..sort((a, b) => a.name.compareTo(b.name));
                    String? selectedHabitId;

                    final result = await showDialog<({String title, String? habitId})>(
                      context: context,
                      builder: (ctx) => StatefulBuilder(
                        builder: (ctx, setD) => AlertDialog(
                          title: const Text('Ajouter un article'),
                          content: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              TextField(
                                controller: ctrl,
                                autofocus: true,
                                textCapitalization: TextCapitalization.sentences,
                                decoration: const InputDecoration(hintText: 'Nom de l\'article'),
                                onSubmitted: (_) {
                                  final t = ctrl.text.trim();
                                  if (t.isNotEmpty) Navigator.pop(ctx, (title: t, habitId: selectedHabitId));
                                },
                              ),
                              const SizedBox(height: 12),
                              DropdownButtonFormField<String?>(
                                value: selectedHabitId,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                  labelText: 'Routine (optionnel)',
                                  isDense: true,
                                ),
                                items: [
                                  const DropdownMenuItem<String?>(
                                    value: null,
                                    child: Text('Sans routine'),
                                  ),
                                  ...habits.map((h) => DropdownMenuItem<String?>(
                                    value: h.id,
                                    child: Text(h.name, overflow: TextOverflow.ellipsis),
                                  )),
                                ],
                                onChanged: (v) => setD(() => selectedHabitId = v),
                              ),
                            ],
                          ),
                          actions: [
                            TextButton(
                                onPressed: () => Navigator.pop(ctx),
                                child: const Text('Annuler')),
                            FilledButton(
                                onPressed: () {
                                  final t = ctrl.text.trim();
                                  if (t.isNotEmpty) Navigator.pop(ctx, (title: t, habitId: selectedHabitId));
                                },
                                child: const Text('Ajouter')),
                          ],
                        ),
                      ),
                    );
                    if (result == null) return;
                    final now = DateTime.now();
                    final ymd = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
                    await logic.addToPlanAction(
                      ymd: ymd,
                      title: result.title,
                      habitId: result.habitId,
                    );
                    // Activer directement (pas en réserve)
                    final item = logic.state.dayPlan.lastWhere(
                      (a) => a.toPlan == true,
                      orElse: () => logic.state.dayPlan.last,
                    );
                    item.archived = false;
                    logic.onChange();
                    setState(() {});
                  },
                ),
                if (reserve.isNotEmpty)
                  TextButton(
                    style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact),
                    onPressed: () => setState(() {
                      if (allSelected) {
                        _selected.clear();
                      } else {
                        _selected.addAll(reserve.map((e) => e.id));
                      }
                    }),
                    child: Text(
                        allSelected ? 'Désélectionner tout' : 'Tout sélectionner'),
                  ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: EdgeInsets.fromLTRB(
                  16, 12, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
              children: [
                // ── En liste (déjà activés) ────────────────────────────────
                if (active.isNotEmpty) ...[
                  Text(
                    'En liste (${active.length})',
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: cs.primary),
                  ),
                  const SizedBox(height: 4),
                  for (final it in active)
                    ListTile(
                      dense: true,
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 4),
                      leading: Icon(Icons.check_circle_outline,
                          size: 18, color: cs.primary.withOpacity(.6)),
                      title: Text(it.title,
                          style: const TextStyle(fontSize: 14)),
                      subtitle: Text(_habitName(it.habitId),
                          style: TextStyle(
                              fontSize: 11,
                              color: cs.onSurface.withOpacity(.5))),
                    ),
                  const SizedBox(height: 16),
                ],

                // ── En réserve (à ajouter) ─────────────────────────────────
                if (reserve.isEmpty && active.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: Center(
                      child: Text(
                        'Aucun article en réserve',
                        style: TextStyle(
                            color: cs.onSurface.withOpacity(.4)),
                      ),
                    ),
                  )
                else if (reserve.isNotEmpty) ...[
                  Text(
                    'En réserve (${reserve.length})',
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: cs.onSurface.withOpacity(.6)),
                  ),
                  const SizedBox(height: 4),
                  for (final hid in habitIds) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
                      child: Text(
                        _habitName(hid),
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 11,
                            letterSpacing: .4,
                            color: cs.onSurface.withOpacity(.4)),
                      ),
                    ),
                    for (final it in byHabit[hid]!)
                      CheckboxListTile(
                        dense: true,
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 4),
                        value: _selected.contains(it.id),
                        onChanged: (v) => setState(() {
                          if (v == true) {
                            _selected.add(it.id);
                          } else {
                            _selected.remove(it.id);
                          }
                        }),
                        title: Text(it.title,
                            style: const TextStyle(fontSize: 14)),
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                  ],
                ],
              ],
            ),
          ),

          // ── CTA ────────────────────────────────────────────────────────────
          if (_selected.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: FilledButton.icon(
                onPressed: _addToPlan,
                icon: const Icon(Icons.add_shopping_cart, size: 18),
                label: Text('Ajouter au plan (${_selected.length})'),
                style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48)),
              ),
            ),
        ],
      ),
    );
  }
}
