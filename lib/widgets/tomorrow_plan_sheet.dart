import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:collection/collection.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/models.dart';

Future<void> showTomorrowPlanSheet(
  BuildContext context, {
  required AppLogic logic,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _TomorrowPlanSheet(logic: logic),
  );
}

class _TomorrowPlanSheet extends StatefulWidget {
  final AppLogic logic;
  const _TomorrowPlanSheet({required this.logic});

  @override
  State<_TomorrowPlanSheet> createState() => _TomorrowPlanSheetState();
}

class _TomorrowPlanSheetState extends State<_TomorrowPlanSheet> {
  AppLogic get logic => widget.logic;
  AppState get st => logic.state;

  final _quickAddCtrl = TextEditingController();
  final _quickAddFocus = FocusNode();

  @override
  void dispose() {
    _quickAddCtrl.dispose();
    _quickAddFocus.dispose();
    super.dispose();
  }

  DateTime get _tomorrow =>
      DateTime.now().add(const Duration(days: 1));

  String get _tomorrowYmd => yyyymmdd(
      DateTime(_tomorrow.year, _tomorrow.month, _tomorrow.day));

  List<DayPlanItem> get _tomorrowActions => st.dayPlan
      .where((it) =>
          it.yyyymmdd == _tomorrowYmd &&
          it.kind == PlanKind.action &&
          !it.archived &&
          !it.done)
      .toList()
    ..sort((a, b) => a.order.compareTo(b.order));

  List<Activity> get _dailyRoutines => st.activities
      .where((a) =>
          a.isHabit && logic.effectiveHabitFreq(a) == HabitFreq.daily)
      .toList()
    ..sort((a, b) => a.order.compareTo(b.order));

  // Prochaines actions des objectifs actifs non encore planifiées demain
  List<({Goal goal, GoalAction action})> get _goalSuggestions {
    final alreadyPlanned = _tomorrowActions
        .map((it) => it.goalActionId)
        .whereNotNull()
        .toSet();

    return st.goals
        .where((g) => g.status == 'active' && g.nextAction != null)
        .map((g) => (goal: g, action: g.nextAction!))
        .where((s) => !alreadyPlanned.contains(s.action.id))
        .toList();
  }

  Future<void> _quickAdd() async {
    final title = _quickAddCtrl.text.trim();
    if (title.isEmpty) return;
    await logic.addPlanAction(ymd: _tomorrowYmd, title: title);
    _quickAddCtrl.clear();
    setState(() {});
    HapticFeedback.lightImpact();
  }

  Future<void> _addGoalAction(Goal goal, GoalAction action) async {
    // Vérifie que l'action n'est pas déjà planifiée demain
    if (st.dayPlan.any((it) =>
        it.yyyymmdd == _tomorrowYmd && it.goalActionId == action.id)) return;
    await logic.addPlanAction(ymd: _tomorrowYmd, title: action.title);
    // Rattache le goalActionId sur l'item qu'on vient d'ajouter
    final item = st.dayPlan.lastWhereOrNull(
        (it) => it.yyyymmdd == _tomorrowYmd && it.title == action.title);
    if (item != null) {
      item.goalActionId = action.id;
      logic.onChange();
    }
    setState(() {});
    HapticFeedback.lightImpact();
  }

  void _removeAction(DayPlanItem it) {
    st.dayPlan.removeWhere((x) => x.id == it.id);
    logic.onChange();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tomorrow = _tomorrow;
    final actions = _tomorrowActions;
    final routines = _dailyRoutines;
    final suggestions = _goalSuggestions;

    final dayNames = ['lun', 'mar', 'mer', 'jeu', 'ven', 'sam', 'dim'];
    final months = ['', 'jan', 'fév', 'mar', 'avr', 'mai', 'juin',
        'juil', 'aoû', 'sep', 'oct', 'nov', 'déc'];
    final dateLabel =
        '${dayNames[tomorrow.weekday - 1]} ${tomorrow.day} ${months[tomorrow.month]}';

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, sc) => Column(
        children: [
          // ── Header ────────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Planifier demain',
                          style: const TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 18)),
                      Text(dateLabel,
                          style: TextStyle(
                              fontSize: 13,
                              color: cs.onSurface.withOpacity(.45))),
                    ],
                  ),
                ),
                if (actions.isNotEmpty)
                  Chip(
                    label: Text('${actions.length} action${actions.length > 1 ? 's' : ''}'),
                    visualDensity: VisualDensity.compact,
                    backgroundColor: cs.primary.withOpacity(.1),
                    labelStyle: TextStyle(
                        fontSize: 12,
                        color: cs.primary,
                        fontWeight: FontWeight.w600),
                    side: BorderSide.none,
                  ),
              ],
            ),
          ),
          const Divider(height: 1),

          Expanded(
            child: ListView(
              controller: sc,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
              children: [

                // ── Saisie rapide ────────────────────────────────────────
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _quickAddCtrl,
                        focusNode: _quickAddFocus,
                        decoration: InputDecoration(
                          hintText: 'Ajouter une action rapidement…',
                          hintStyle: TextStyle(
                              color: cs.onSurface.withOpacity(.4),
                              fontSize: 14),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(
                                color: cs.onSurface.withOpacity(.15)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(
                                color: cs.onSurface.withOpacity(.15)),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          isDense: true,
                        ),
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _quickAdd(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _quickAdd,
                      style: FilledButton.styleFrom(
                          minimumSize: const Size(44, 44),
                          padding: EdgeInsets.zero),
                      child: const Icon(Icons.add),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // ── Actions planifiées ───────────────────────────────────
                _sectionTitle(cs, 'Actions planifiées',
                    count: actions.length),
                const SizedBox(height: 8),
                if (actions.isEmpty)
                  _emptyHint(cs, 'Aucune action planifiée pour demain.')
                else
                  ReorderableListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    buildDefaultDragHandles: false,
                    itemCount: actions.length,
                    onReorder: (oldIndex, newIndex) {
                      setState(() {
                        logic.reorderTodayBucket(
                          yyyymmdd: _tomorrowYmd,
                          bucketVisible: actions,
                          oldIndex: oldIndex,
                          newIndex: newIndex,
                        );
                      });
                    },
                    itemBuilder: (ctx, i) {
                      final it = actions[i];
                      return _ActionTile(
                        key: ValueKey(it.id),
                        item: it,
                        index: i,
                        cs: cs,
                        onDelete: () => _removeAction(it),
                      );
                    },
                  ),
                const SizedBox(height: 20),

                // ── Suggestions depuis les objectifs ──────────────────────
                if (suggestions.isNotEmpty) ...[
                  _sectionTitle(cs, 'Depuis tes objectifs'),
                  const SizedBox(height: 8),
                  ...suggestions.map((s) {
                    final domain = st.domains.firstWhereOrNull(
                        (d) => d.id == s.goal.domainId);
                    return _SuggestionTile(
                      goal: s.goal,
                      action: s.action,
                      domainName: domain?.name,
                      cs: cs,
                      onAdd: () => _addGoalAction(s.goal, s.action),
                    );
                  }),
                  const SizedBox(height: 20),
                ],

                // ── Routines du lendemain ─────────────────────────────────
                _sectionTitle(cs, 'Routines attendues demain',
                    count: routines.length),
                const SizedBox(height: 8),
                if (routines.isEmpty)
                  _emptyHint(cs, 'Aucune routine quotidienne.')
                else
                  ...routines.map((a) {
                    final quota = logic.dayQuotaFor(a);
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Icon(Icons.repeat,
                              size: 14,
                              color: cs.onSurface.withOpacity(.35)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              quota > 1 ? '${a.name}  ×$quota' : a.name,
                              style: TextStyle(
                                  fontSize: 13,
                                  color: cs.onSurface.withOpacity(.7)),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(ColorScheme cs, String title, {int? count}) => Row(
        children: [
          Text(title,
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: cs.onSurface.withOpacity(.7))),
          if (count != null && count > 0) ...[
            const SizedBox(width: 6),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: cs.primary.withOpacity(.1),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text('$count',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: cs.primary)),
            ),
          ],
        ],
      );

  Widget _emptyHint(ColorScheme cs, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(text,
            style: TextStyle(
                fontSize: 12, color: cs.onSurface.withOpacity(.4))),
      );
}

// ── Tuile action planifiée ────────────────────────────────────────────────────

class _ActionTile extends StatelessWidget {
  final DayPlanItem item;
  final int index;
  final ColorScheme cs;
  final VoidCallback onDelete;

  const _ActionTile({
    super.key,
    required this.item,
    required this.index,
    required this.cs,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          ReorderableDragStartListener(
            index: index,
            child: Icon(Icons.drag_handle,
                size: 18, color: cs.onSurface.withOpacity(.25)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(item.title,
                style: TextStyle(
                    fontSize: 14,
                    color: cs.onSurface.withOpacity(.85))),
          ),
          IconButton(
            icon: Icon(Icons.close,
                size: 16, color: cs.onSurface.withOpacity(.35)),
            visualDensity: VisualDensity.compact,
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}

// ── Tuile suggestion objectif ─────────────────────────────────────────────────

class _SuggestionTile extends StatelessWidget {
  final Goal goal;
  final GoalAction action;
  final String? domainName;
  final ColorScheme cs;
  final VoidCallback onAdd;

  const _SuggestionTile({
    required this.goal,
    required this.action,
    required this.domainName,
    required this.cs,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onAdd,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            border: Border.all(color: cs.onSurface.withOpacity(.1)),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(action.title,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w500)),
                    if (domainName != null)
                      Text(
                        '${goal.title}  ·  $domainName',
                        style: TextStyle(
                            fontSize: 11,
                            color: cs.onSurface.withOpacity(.4)),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.add_circle_outline,
                  size: 20, color: cs.primary.withOpacity(.7)),
            ],
          ),
        ),
      ),
    );
  }
}
