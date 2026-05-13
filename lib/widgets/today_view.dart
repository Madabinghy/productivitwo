// ignore_for_file: deprecated_member_use

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:collection/collection.dart';
import 'package:productivitwo_v1/widgets/assign_activity_sheet.dart';
import 'package:productivitwo_v1/widgets/day_block_sheet.dart';
import 'package:productivitwo_v1/widgets/goals_view.dart';
import 'package:productivitwo_v1/widgets/habit_settings_sheet.dart';
import 'package:productivitwo_v1/widgets/now_habit_tile_full.dart';
import 'package:productivitwo_v1/widgets/tiny_bar.dart';

class TodayView extends StatefulWidget {
  final AppLogic logic;
  final AppState state;
  final void Function(String habitId)? onGoNow;
  final VoidCallback? onGoNowTab; // ✅ juste switch d'onglet
  final void Function(String habitId)? onOpenRoutineDetail;
  const TodayView({
    super.key,
    required this.logic,
    required this.state,
    this.onGoNow,
    this.onGoNowTab,
    this.onOpenRoutineDetail,
  });

  @override
  State<TodayView> createState() => _TodayViewState();
}

enum _Scope { goals, today }

class _TodayViewState extends State<TodayView> {
  // Choix JOUR: aujourd'hui / demain
  bool _showDone = false;

  Timer? _runWatch;
  String? _lastRunningId;
  bool _showAll = true;
  bool _showCourses = false; // repli/dépli manuel
  bool _showSnoozed = false;
  bool _showTomorrow = false;
  final Set<String> _collapsedBlockIds = {};
  bool _showBlocks = true;

  _Scope _scope = _Scope.today;

  bool _passesFilters(DayPlanItem it) {
    final f = widget.logic.state.filters; // ou _state!.filters si tu préfères

    // ✅ auto-actif
    if (!f.isActive) return true;

    // filtre domaine
    final domId = (it.domainId ?? '').trim();
    if (f.domainIds.isNotEmpty) {
      if (domId.isEmpty) return false;
      if (!f.domainIds.contains(domId)) return false;
    }

    // filtre activité (time)
    final actId = (it.activityId ?? '').trim();
    if (f.activityIds.isNotEmpty) {
      if (actId.isEmpty) return false;
      if (!f.activityIds.contains(actId)) return false;
    }

    return true;
  }

  Future<void> _addGoalDialog(BuildContext context, {String? preselectedDomainId}) async {
    final logic = widget.logic;
    final st = widget.state;
    String? selectedDomainId = preselectedDomainId ?? (st.domains.isNotEmpty ? st.domains.first.id : null);
    final titleCtrl = TextEditingController();
    final actionCtrl = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Nouvel objectif'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: selectedDomainId,
                  decoration: const InputDecoration(labelText: 'Domaine'),
                  items: st.domains
                      .map((d) => DropdownMenuItem(value: d.id, child: Text(d.name)))
                      .toList(),
                  onChanged: (v) => setS(() => selectedDomainId = v),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: titleCtrl,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Objectif'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: actionCtrl,
                  decoration: const InputDecoration(labelText: 'Première action (optionnel)'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
            FilledButton(
              onPressed: () {
                final title = titleCtrl.text.trim();
                if (title.isEmpty || selectedDomainId == null) return;
                logic.createGoal(
                  domainId: selectedDomainId!,
                  title: title,
                  firstAction: actionCtrl.text.trim().isEmpty ? null : actionCtrl.text.trim(),
                );
                setState(() {});
                Navigator.pop(ctx);
              },
              child: const Text('Ajouter'),
            ),
          ],
        ),
      ),
    );
  }

  void _openGoalDetail(BuildContext context, Goal goal) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => GoalDetailSheet(
        goal: goal,
        logic: widget.logic,
        state: widget.state,
        onChanged: () => setState(() {}),
      ),
    );
  }

  Widget _buildGoalsContent(BuildContext context) {
    final logic = widget.logic;
    final st = widget.state;
    final filters = logic.state.filters;

    // Activité en cours → domaine prioritaire
    final running = logic.runningActivity();
    final runningDomainId = running?.domainId;

    // Objectifs actifs filtrés par domaine
    var activeGoals = st.goals.where((g) => g.status == 'active').toList();
    if (filters.domainIds.isNotEmpty) {
      activeGoals = activeGoals.where((g) => filters.domainIds.contains(g.domainId)).toList();
    }

    // Domaines ayant des objectifs, avec domaine de l'activité en cours en tête
    final domainsWithGoals = st.domains
        .where((d) => activeGoals.any((g) => g.domainId == d.id))
        .toList()
      ..sort((a, b) {
        if (a.id == runningDomainId) return -1;
        if (b.id == runningDomainId) return 1;
        return 0;
      });

    if (activeGoals.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              filters.domainIds.isNotEmpty
                  ? 'Aucun objectif dans ce domaine.'
                  : 'Aucun objectif actif.',
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => _addGoalDialog(context),
              icon: const Icon(Icons.add),
              label: const Text('Créer un objectif'),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 120),
      children: [
        for (final domain in domainsWithGoals) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
            child: Row(
              children: [
                if (domain.id == runningDomainId)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Icon(Icons.play_circle_outline,
                        size: 16, color: Theme.of(context).colorScheme.primary),
                  ),
                Expanded(
                  child: Text(
                    domain.name,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: domain.id == runningDomainId
                          ? Theme.of(context).colorScheme.primary
                          : Colors.grey,
                    ),
                  ),
                ),
                TextButton.icon(
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Ajouter'),
                  onPressed: () => _addGoalDialog(context, preselectedDomainId: domain.id),
                ),
              ],
            ),
          ),
          for (final goal in activeGoals.where((g) => g.domainId == domain.id))
            GoalCard(
              goal: goal,
              muted: false,
              logic: widget.logic,
              onTap: () => _openGoalDetail(context, goal),
              onArchive: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Archiver ?'),
                    content: Text('Archiver "${goal.title}" ?'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Annuler')),
                      FilledButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Archiver')),
                    ],
                  ),
                );
                if (confirm == true) {
                  logic.archiveGoal(goal.id);
                  setState(() {});
                }
              },
            ),
        ],
        const Divider(height: 32),
        Center(
          child: TextButton.icon(
            onPressed: () => _addGoalDialog(context),
            icon: const Icon(Icons.add),
            label: const Text('Nouvel objectif'),
          ),
        ),
      ],
    );
  }

  // Retourne l'id du bloc sélectionné, '' pour désassigner, null si annulé
  Widget _blockItemTile(BuildContext context, DayPlanItem it) {
    final cs = Theme.of(context).colorScheme;
    final logic = widget.logic;
    final today = DateTime.now();

    if (it.kind == PlanKind.habit) {
      final habitId = it.refId ?? it.habitId;
      final act = habitId == null
          ? null
          : logic.state.activities.firstWhereOrNull((a) => a.id == habitId);

      final quota = act != null ? logic.dayQuotaFor(act) : 1;
      final done = habitId != null ? logic.habitValueOn(habitId, today) : 0;
      final isDone = done >= quota;

      void inc(int delta) {
        if (habitId == null) return;
        logic.incHabit(habitId, delta, today);
        logic.onChange();
        setState(() {});
      }

      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            // Coche simple si quota = 1, sinon icône d'état
            GestureDetector(
              onTap: () => inc(isDone ? -1 : 1),
              child: Icon(
                isDone ? Icons.check_circle : Icons.radio_button_unchecked,
                size: 20,
                color: isDone ? cs.primary : cs.onSurface.withOpacity(0.35),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                it.title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: isDone ? cs.onSurface.withOpacity(0.4) : cs.onSurface,
                  decoration: isDone ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
            // Quota > 1 : compteur + bouton +
            if (quota > 1) ...[
              SizedBox(
                width: 32,
                height: 32,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.remove, size: 18,
                      color: done > 0
                          ? cs.onSurface.withOpacity(0.5)
                          : cs.onSurface.withOpacity(0.2)),
                  onPressed: done > 0 ? () => inc(-1) : null,
                ),
              ),
              Text(
                '$done/$quota',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isDone
                      ? cs.primary
                      : cs.onSurface.withOpacity(0.55),
                ),
              ),
              SizedBox(
                width: 32,
                height: 32,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.add, size: 18,
                      color: isDone
                          ? cs.onSurface.withOpacity(0.3)
                          : cs.primary),
                  onPressed: isDone ? null : () => inc(1),
                ),
              ),
            ],
          ],
        ),
      );
    }

    // Action simple
    final isDone = it.done;
    return InkWell(
      onTap: () {
        it.done = !it.done;
        logic.onChange();
        setState(() {});
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(
              isDone ? Icons.check_circle : Icons.radio_button_unchecked,
              size: 20,
              color: isDone ? cs.primary : cs.onSurface.withOpacity(0.35),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                it.title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: isDone ? cs.onSurface.withOpacity(0.4) : cs.onSurface,
                  decoration: isDone ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tomorrowSection({required String tomorrowYmd}) {
    final todayYmd = yyyymmdd(DateTime.now());
    final items = widget.logic.planFor(tomorrowYmd)
        .where((it) => !it.archived && !it.done)
        .toList()
      ..sort((a, b) => a.order.compareTo(b.order));

    if (items.isEmpty && !_showTomorrow) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => setState(() => _showTomorrow = !_showTomorrow),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Demain${items.isNotEmpty ? " (${items.length})" : ""}',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: cs.onSurface.withOpacity(0.6),
                    ),
                  ),
                ),
                Icon(
                  _showTomorrow ? Icons.expand_less : Icons.expand_more,
                  size: 20,
                  color: cs.onSurface.withOpacity(0.5),
                ),
              ],
            ),
          ),
        ),
        if (_showTomorrow) ...[
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Rien de prévu pour demain.',
                style: TextStyle(color: cs.onSurface.withOpacity(0.5)),
              ),
            )
          else
            for (final it in items)
              Card(
                margin: const EdgeInsets.only(bottom: 6),
                child: ListTile(
                  dense: true,
                  leading: Icon(
                    it.kind == PlanKind.habit
                        ? Icons.repeat
                        : Icons.check_box_outline_blank,
                    size: 18,
                    color: cs.onSurface.withOpacity(0.4),
                  ),
                  title: Text(
                    it.title,
                    style: const TextStyle(fontSize: 14),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: IconButton(
                    tooltip: "Ramener à aujourd'hui",
                    icon: Icon(Icons.arrow_back,
                        size: 18, color: cs.primary),
                    onPressed: () {
                      widget.logic.moveItemToDayById(it.id, todayYmd);
                      widget.logic.onChange();
                      setState(() {});
                    },
                  ),
                ),
              ),
        ],
      ],
    );
  }

  Widget _buildBlockSection(
    BuildContext context,
    DayBlock block,
    List<DayPlanItem> items,
    String ymd,
  ) {
    final logic = widget.logic;
    final cs = Theme.of(context).colorScheme;
    final isCollapsed = _collapsedBlockIds.contains(block.id);
    final isDisabled = logic.isBlockDisabledForDay(block.id, ymd);
    bool _itemIsDone(DayPlanItem it) {
      if (it.kind == PlanKind.habit) {
        final habitId = it.refId ?? it.habitId;
        final act = habitId == null
            ? null
            : logic.state.activities.firstWhereOrNull((a) => a.id == habitId);
        return act != null ? logic.habitReached(act) : it.done;
      }
      return it.done;
    }

    final doneCount = items.where(_itemIsDone).length;
    final total = items.length;
    final isComplete = total > 0 && doneCount == total;
    final label = '${block.emoji != null ? "${block.emoji} " : ""}${block.name}';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(
        children: [
          InkWell(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            onTap: () => setState(() {
              if (isCollapsed) {
                _collapsedBlockIds.remove(block.id);
              } else {
                _collapsedBlockIds.add(block.id);
              }
            }),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
              child: Row(
                children: [
                  if (isComplete)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Icon(Icons.check_circle,
                          size: 18, color: cs.primary),
                    ),
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: isDisabled
                            ? cs.onSurface.withOpacity(0.4)
                            : isComplete
                                ? cs.primary
                                : null,
                        decoration: isDisabled ? TextDecoration.lineThrough : null,
                      ),
                    ),
                  ),
                  if (total > 0)
                    Text(
                      '$doneCount/$total',
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurface.withOpacity(0.55),
                      ),
                    ),
                  const SizedBox(width: 4),
                  IconButton(
                    tooltip: isDisabled ? "Réactiver" : "Passer aujourd'hui",
                    icon: Icon(
                      Icons.arrow_forward,
                      size: 18,
                      color: isDisabled
                          ? cs.onSurface.withOpacity(0.3)
                          : cs.primary,
                    ),
                    onPressed: () {
                      logic.toggleBlockDisabledForDay(block.id, ymd);
                      setState(() {});
                    },
                  ),
                  Icon(isCollapsed ? Icons.expand_more : Icons.expand_less,
                      size: 20),
                ],
              ),
            ),
          ),
          if (!isCollapsed && !isDisabled) ...[
            const Divider(height: 1),
            ...items.map((it) => _blockItemTile(context, it)),
            if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  'Aucun item dans ce bloc pour aujourd\'hui.',
                  style: TextStyle(color: cs.onSurface.withOpacity(0.55)),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _coursesSection({
    required List<DayPlanItem> courses,
    required bool autoExpanded,
    required Activity? shoppingAct,
  }) {
    if (courses.isEmpty) return const SizedBox.shrink();

    final expanded = autoExpanded || _showCourses;

    // Map habitId -> nom de routine
    final habitsById = {
      for (final a in widget.logic.state.activities.where((x) => x.isHabit))
        a.id: a
    };

    String habitName(String? habitId) {
      if (habitId == null || habitId.isEmpty) return "Sans routine";
      return habitsById[habitId]?.name ?? "Routine";
    }

    // Group: habitId -> items
    final byHabit = <String?, List<DayPlanItem>>{};
    for (final it in courses) {
      (byHabit[it.habitId] ??= []).add(it);
    }

    // Tri interne + tri des groupes
    for (final list in byHabit.values) {
      list.sort((a, b) => a.title.compareTo(b.title));
    }
    final habitIds = byHabit.keys.toList()
      ..sort((a, b) => habitName(a).compareTo(habitName(b)));

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _showCourses = !_showCourses),
              onLongPress: shoppingAct == null
                  ? null
                  : () {
                      final running = widget.logic.runningActivity();
                      if (running == null || running.id != shoppingAct.id) {
                        widget.logic.start(shoppingAct.id);
                        setState(() {});
                      }
                    },
              child: Row(
                children: [
                  const Icon(Icons.shopping_cart_outlined, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "Courses (${courses.length})",
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    size: 20,
                  ),
                ],
              ),
            ),
            if (expanded) ...[
              const SizedBox(height: 8),

              // Groupes par routine
              for (final hid in habitIds) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 6, bottom: 6),
                  child: Text(
                    "${habitName(hid)} (${byHabit[hid]!.length})",
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withOpacity(.75),
                    ),
                  ),
                ),
                for (final it in byHabit[hid]!)
                  _todayTile(
                    context,
                    it,
                    key: ValueKey("courses:${hid ?? "none"}:${it.id}"),
                    showDrag: false,
                    indexForDrag: 0,
                  ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Future<bool> _startOrPickActivityForAction(DayPlanItem it) async {
    final running = widget.logic.runningActivity();

    // 1️⃣ Action déjà liée à une activité
    if (it.activityId != null && it.activityId!.isNotEmpty) {
      // même activité déjà en cours → rien à faire (mais on considère OK)
      if (running != null && running.id == it.activityId) {
        return true;
      }

      // sinon on stoppe ce qui tourne (si besoin)
      if (running != null) {
        widget.logic.stopActive();
      }

      final act = widget.state.activities.firstWhere(
        (a) => a.id == it.activityId,
        orElse: () => Activity(
          domainId: it.domainId ?? '',
          name: 'Activité',
          habitTarget: 1,
        ),
      );

      widget.logic.start(act.id);
      return true;
    }

    // 2️⃣ Pas d'activité → ouvrir le picker
    final picked =
        await widget.logic.openAssignActivitySheetAndWait(context, it);
    if (picked == null) return false; // ✅ annulé

    setState(() {
      it.activityId = picked.id;
      it.domainId = picked.domainId;
    });
    widget.logic.onChange();

    // on lance directement
    final running2 = widget.logic.runningActivity();
    if (running2 != null) widget.logic.stopActive();
    widget.logic.start(picked.id);

    return true;
  }

  Widget _actionCardContent(
    DayPlanItem it, {
    required DateTime viewedDay,
    required String ymdViewed,
    required bool isTodayTab,
  }) {
    // Lookup routine (habit)
    Activity? habit;
    if ((it.habitId ?? '').isNotEmpty) {
      habit = widget.state.activities
          .cast<Activity?>()
          .firstWhere((a) => a?.id == it.habitId, orElse: () => null);
    }

    // Lookup activité (time)
    Activity? activity;
    if ((it.activityId ?? '').isNotEmpty) {
      activity = widget.state.activities
          .cast<Activity?>()
          .firstWhere((a) => a?.id == it.activityId, orElse: () => null);
    }

    // Lookup domaine
    String? domName;
    if ((it.domainId ?? '').isNotEmpty) {
      domName = widget.state.domains
          .cast<Domain?>()
          .firstWhere((d) => d?.id == it.domainId, orElse: () => null)
          ?.name;
    }

    // ---------- helpers UI ----------
    Widget iconBtn({
      required IconData icon,
      required String tooltip,
      required VoidCallback onPressed,
    }) {
      return IconButton(
        tooltip: tooltip,
        icon: Icon(icon, size: 18),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 32, height: 32),
        visualDensity: VisualDensity.compact,
        onPressed: onPressed,
      );
    }

    void toast(String msg) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }

    // day keys
    final now = DateTime.now();
    final base = DateTime(now.year, now.month, now.day);
    final todayYmd = yyyymmdd(base);
    final tomorrowYmd = yyyymmdd(base.add(const Duration(days: 1)));
    final afterTomorrowYmd = yyyymmdd(base.add(const Duration(days: 2)));

    final isOnToday = (ymdViewed == todayYmd);
    final destForward = isOnToday ? tomorrowYmd : afterTomorrowYmd;
    final destBackward = todayYmd;

    void moveToTop() {
      widget.logic.movePlanItemToTop(ymdViewed, it.id);
      widget.logic.onChange();
      setState(() {});
    }

    void moveToEnd() {
      widget.logic.movePlanItemToEnd(ymdViewed, it.id);
      widget.logic.onChange();
      setState(() {});
    }

    void moveToDay(String targetYmd, {required bool forward}) {
      final fromYmd = ymdViewed;
      widget.logic.moveItemToDayById(it.id, targetYmd);
      widget.logic.onChange();
      setState(() {});
      final msg = forward
          ? (isOnToday ? 'Déplacé à demain' : 'Déplacé à après-demain')
          : "Renvoyé à aujourd'hui";
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        duration: const Duration(seconds: 4),
        content: Text(msg),
        action: forward
            ? SnackBarAction(
                label: 'Annuler',
                onPressed: () {
                  widget.logic.moveItemToDayById(it.id, fromYmd);
                  widget.logic.onChange();
                  setState(() {});
                },
              )
            : null,
      ));
    }

    Widget moveDayArrows() {
      // Aujourd'hui : seulement →
      if (isOnToday) {
        return iconBtn(
          icon: Icons.arrow_forward,
          tooltip: 'Déplacer vers demain',
          onPressed: () => moveToDay(destForward, forward: true),
        );
      }

      // Demain : ← et →
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          iconBtn(
            icon: Icons.arrow_back,
            tooltip: "Renvoyer à aujourd'hui",
            onPressed: () => moveToDay(destBackward, forward: false),
          ),
          iconBtn(
            icon: Icons.arrow_forward,
            tooltip: 'Déplacer vers après-demain',
            onPressed: () => moveToDay(destForward, forward: true),
          ),
        ],
      );
    }

    // ---------- render ----------
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ▶︎ PLAY / LINK
            SizedBox(
              width: 44,
              child: IconButton(
                icon: Icon(
                  activity != null ? Icons.play_arrow : Icons.link,
                  size: 20,
                ),
                tooltip: activity != null
                    ? "Lancer l'activité"
                    : "Associer puis lancer",
                padding: EdgeInsets.zero,
                onPressed: () async {
                  final ok = await _startOrPickActivityForAction(it);
                  if (!ok) return;
                  widget.logic.setNowFocus(it.id);
                  widget.onGoNowTab?.call();
                },
              ),
            ),

            // CONTENU
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Titre
                  Text(
                    it.title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 15),
                  ),

                  // Routine
                  if (habit != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      "Routine • ${habit.name}",
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withOpacity(0.55),
                      ),
                    ),
                  ],

                  // Activité
                  if (activity != null) ...[
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            "Activité • ${activity.name}",
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withOpacity(0.55),
                            ),
                          ),
                        ),
                        InkWell(
                          onTap: () {
                            setState(() => it.activityId = null);
                            widget.logic.onChange();
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(2),
                            child: Icon(
                              Icons.close,
                              size: 14,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withOpacity(0.6),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],

                  // Domaine fallback
                  if (habit == null && activity == null && domName != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      "Domaine • $domName",
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withOpacity(0.5),
                      ),
                    ),
                  ],

                  const SizedBox(height: 6),

                  // ✅ LIGNE CONTROLES (comme routines)
                  Row(
                    children: [
                      const Spacer(),
                      iconBtn(
                        icon: Icons.arrow_upward,
                        tooltip: "En haut",
                        onPressed: moveToTop,
                      ),
                      iconBtn(
                        icon: Icons.arrow_downward,
                        tooltip: "En bas",
                        onPressed: moveToEnd,
                      ),
                      if (!isTodayTab) ...[
                        // quand tu es sur l'onglet demain, tu veux aussi ← →
                        moveDayArrows(),
                      ] else ...[
                        // today: juste →
                        moveDayArrows(),
                      ],
                    ],
                  ),
                ],
              ),
            ),

            // CHECKBOX DONE
            SizedBox(
              width: 32,
              child: Checkbox(
                value: it.done,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onChanged: (v) {
                  final done = v ?? false;

                  if (done && it.toPlan == true) {
                    widget.logic.archiveAction(it);
                    widget.logic.onChange();
                    setState(() {});
                    return;
                  }

                  setState(() => it.done = done);
                  widget.logic.onChange();
                },
              ),
            ),

            // SNOOZE
            PopupMenuButton<String>(
              tooltip: 'Plus tard',
              onSelected: (v) async {
                // ⚠️ pas de setState(async) ici : ok, on le fait autour
                if (v == 'tomorrow') {
                  await widget.logic.snoozeToTomorrow(it);
                } else if (v == 'date') {
                  await widget.logic.snoozeToDate(context, it);
                } else if (v == 'unsnooze') {
                  widget.logic.unsnooze(it);
                }
                widget.logic.onChange();
                if (!mounted) return;
                setState(() {});
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                    value: 'tomorrow', child: Text("Pas aujourd'hui")),
                const PopupMenuItem(
                    value: 'date', child: Text("Choisir une date…")),
                if (it.snoozeUntil != null)
                  const PopupMenuItem(
                      value: 'unsnooze', child: Text("Réafficher")),
              ],
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Icon(
                  Icons.snooze,
                  size: 18,
                  color:
                      Theme.of(context).colorScheme.onSurface.withOpacity(.75),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _deleteActionWithUndo(DayPlanItem it) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;

    final idx = widget.logic.state.dayPlan.indexWhere((e) => e.id == it.id);
    if (idx < 0) return;

    final removed = widget.logic.state.dayPlan[idx];

    setState(() {
      widget.logic.state.dayPlan.removeAt(idx);
    });
    widget.logic.onChange();

    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 4),
        content: Text(
          "Action supprimée : ${removed.title}",
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        action: SnackBarAction(
          label: "Annuler",
          onPressed: () {
            setState(() {
              final safeIdx = idx.clamp(0, widget.logic.state.dayPlan.length);
              widget.logic.state.dayPlan.insert(safeIdx, removed);
            });
            widget.logic.onChange();
          },
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();

    // 1) housekeeping après build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startupHousekeeping();
      widget.logic.backfillDomainIdsForPlan();
      if (mounted) setState(() {});
    });

    // 2) watcher start/stop activité => refresh "À faire"
    _lastRunningId = widget.logic.runningActivity()?.id;
    _runWatch = Timer.periodic(const Duration(milliseconds: 500), (_) {
      final cur = widget.logic.runningActivity()?.id;
      if (cur != _lastRunningId) {
        _lastRunningId = cur;
        if (mounted) setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _runWatch?.cancel();
    super.dispose();
  }

/*   Widget _domainHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.w800,
          color: Theme.of(context).colorScheme.onSurface.withOpacity(.75),
        ),
      ),
    );
  } */

  void _startupHousekeeping() {
    widget.logic.maybeCarryFromYesterday();
    widget.logic.ensureDailyHabitsPlanned();
  }

  bool isHabitReached(DayPlanItem it) {
    if (it.kind != PlanKind.habit || it.refId == null) return false;
    final act =
        widget.state.activities.firstWhereOrNull((a) => a.id == it.refId);
    if (act == null) return false;

    final freq = widget.logic.effectiveHabitFreq(act);
    final target = widget.logic.effectiveHabitTarget(act);

    int done;
    switch (freq) {
      case HabitFreq.daily:
        done = widget.logic.habitValueOn(act.id, DateTime.now());
        break;
      case HabitFreq.weekly:
        done = widget.logic.habitSliding(act.id, 7).done;
        break;
      case HabitFreq.monthly:
        done = widget.logic.habitSliding(act.id, 30).done;
        break;
    }
    return target > 0 && done >= target;
  }

  bool _showInbox = false; // plié par défaut

  Widget _inboxSection({
    required List<DayPlanItem> inbox,
    required void Function(DayPlanItem it) onTapAssign,
  }) {
    if (inbox.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _showInbox = !_showInbox),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                const Icon(Icons.inbox, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "Inbox (${inbox.length})",
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 16),
                  ),
                ),
                Icon(
                  _showInbox ? Icons.expand_less : Icons.expand_more,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
        if (_showInbox) ...[
          const SizedBox(height: 8),
          ...inbox.map((it) {
            return _todayTile(
              context,
              it,
              key: ValueKey('inbox:${it.id}'),
              showDrag: false,
              indexForDrag: 0,
              onTapOverride: () => onTapAssign(it), // ✅ ICI
            );
          }),
        ],
      ],
    );
  }

  void _openAssignActivitySheet(BuildContext context, DayPlanItem action) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => AssignActivitySheet(
        st: widget.logic.state,
        onPick: (act) {
          setState(() {
            action.activityId = act.id;
            action.domainId = act.domainId;

            // ✅ Inbox -> Active (clarifié)
            action.status = ActionStatus.active;
          });

          widget.logic.onChange();
          widget.logic.rev.value++; // ✅ si tu utilises rev pour refresh NowTab
          Navigator.pop(context);
        },
        onKeepInbox: () {
          // rien à faire, on garde ActionStatus.inbox
          Navigator.pop(context);
        },
      ),
    );
  }

  String? _lastAutoPlannedYmd;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final baseDay = DateTime(now.year, now.month, now.day);

    final day = (_scope == _Scope.today)
        ? baseDay
        : baseDay.add(const Duration(days: 1));

    final ymd = yyyymmdd(day);
    final todayDate = DateTime(now.year, now.month, now.day);

    // ✅ matérialise 1 seule fois par ymd
    if (_scope == _Scope.today && _lastAutoPlannedYmd != ymd) {
      _lastAutoPlannedYmd = ymd;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        widget.logic.ensureUnderHabitsPlannedToday(ymd: ymd, now: now);
        setState(() {}); // refresh UI une fois les items créés
      });
    }

    bool isSnoozed(DayPlanItem it) {
      final u = it.snoozeUntil;
      return u != null && u.isAfter(now);
    }

    final isTodayTab = ymd == yyyymmdd(now);

    // 1) Base: plan du jour affiché
    final basePlan = widget.logic.planFor(ymd).toList();

    // ✅ running / planning
    final running = widget.logic.runningActivity();
    final hasRunning = isTodayTab && running != null;

    // --- planOrAuto : injecte virtHabits (aujourd'hui seulement)
    List<DayPlanItem> planOrAuto() {
      if (!isTodayTab) return basePlan; // demain : pas de virtHabits

      final habits =
          widget.logic.state.activities.where((a) => a.isHabit).toList();

      final under = habits.where((a) {
        final freq = widget.logic.effectiveHabitFreq(a);
        final target = widget.logic.effectiveHabitTarget(a);

        int done;
        switch (freq) {
          case HabitFreq.daily:
            done = widget.logic.habitValueOn(a.id, todayDate);
            break;
          case HabitFreq.weekly:
            done = widget.logic.habitSliding(a.id, 7).done;
            break;
          case HabitFreq.monthly:
            done = widget.logic.habitSliding(a.id, 30).done;
            break;
        }

        return target > 0 && done < target;
      }).toList();

      final plannedHabitIds = basePlan
          .where((x) => x.kind == PlanKind.habit)
          .map((x) => (x.refId ?? x.habitId ?? '').trim())
          .where((s) => s.isNotEmpty)
          .toSet();

      final plannedSomewhereElse = widget.logic.state.dayPlan
          .where((x) =>
              x.kind == PlanKind.habit &&
              x.refId != null &&
              x.refId!.isNotEmpty &&
              x.archived != true)
          .where((x) => x.yyyymmdd != ymd) // autre jour que celui affiché
          .map((x) => x.refId!)
          .toSet();

      final virtHabits = under
          .where((a) => !plannedHabitIds.contains(a.id))
          .where(
              (a) => !plannedSomewhereElse.contains(a.id)) // ✅ bloque doublons
          .map((a) => DayPlanItem(
                id: 'virt:${a.id}',
                kind: PlanKind.habit,
                refId: a.id,
                domainId: a.domainId,
                title: a.name,
                yyyymmdd: ymd,
                done: false,
                doneCount: 0,
                allDay: true,
                order: 1 << 30,
              ))
          .toList();

      if (virtHabits.isEmpty) return basePlan;
      return [...basePlan, ...virtHabits];
    }

    final baseOrAuto = planOrAuto();

    // ✅ Dédup safe
    final seen = <String>{};
    baseOrAuto.removeWhere((a) => !seen.add(a.id));

    final shoppingAct = widget.logic.shoppingActivity();
    final shoppingId = shoppingAct?.id;

    bool isLaterToday(DayPlanItem it) {
      final until = it.snoozeUntil;
      if (until == null) return false;
      final sameDay = until.year == now.year &&
          until.month == now.month &&
          until.day == now.day;
      return sameDay && until.isAfter(now);
    }

    // ✅ LATER TODAY
    final laterToday = baseOrAuto.where((it) {
      if (it.kind != PlanKind.action && it.kind != PlanKind.habit) return false;
      if (it.done) return false;
      return isLaterToday(it);
    }).toList()
      ..sort((a, b) => a.snoozeUntil!.compareTo(b.snoozeUntil!));

    // ✅ Source unique (actions + routines)
    final allActions = baseOrAuto
        .where((x) => x.kind == PlanKind.action || x.kind == PlanKind.habit)
        .toList()
      ..sort((a, b) => a.order.compareTo(b.order));

    // ✅ SNOOZED SECTION LIST
    final snoozedActions = baseOrAuto
        .where(
            (a) => !a.done && a.archived != true && !widget.logic.isCourse(a))
        .where((a) {
          final actId = (a.activityId ?? '').trim();
          if (actId.isEmpty) return true;
          return !widget.logic.isActivitySnoozed(actId, now);
        })
        .where(isSnoozed)
        .toList()
      ..sort((a, b) {
        final au = a.snoozeUntil ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bu = b.snoozeUntil ?? DateTime.fromMillisecondsSinceEpoch(0);
        final c = au.compareTo(bu);
        if (c != 0) return c;
        return a.title.compareTo(b.title);
      });

    Widget _snoozedSection({
      required List<DayPlanItem> snoozed,
      required void Function(DayPlanItem it) onUnsnooze,
    }) {
      if (snoozed.isEmpty) return const SizedBox.shrink();

      String fmt(DateTime d) {
        final dd = d.day.toString().padLeft(2, '0');
        final mm = d.month.toString().padLeft(2, '0');
        return "$dd/$mm";
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _showSnoozed = !_showSnoozed),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                children: [
                  const Icon(Icons.schedule, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "Plus tard (${snoozed.length})",
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 16),
                    ),
                  ),
                  Icon(_showSnoozed ? Icons.expand_less : Icons.expand_more,
                      size: 20),
                ],
              ),
            ),
          ),
          if (_showSnoozed) ...[
            const SizedBox(height: 6),
            ...snoozed.map((it) {
              final until = it.snoozeUntil;
              return Dismissible(
                key: ValueKey("snoozed:${it.id}"),
                direction: DismissDirection.startToEnd,
                background: Container(
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  color: Colors.green.withOpacity(0.12),
                  child: const Icon(Icons.undo, color: Colors.green),
                ),
                onDismissed: (_) => onUnsnooze(it),
                child: Opacity(
                  opacity: 0.75,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (until != null)
                        Padding(
                          padding: const EdgeInsets.only(left: 12, bottom: 8),
                          child: Text(
                            "Reparaît le ${fmt(until)}",
                            style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withOpacity(0.45),
                            ),
                          ),
                        ),
                      _todayTile(
                        context,
                        it,
                        key: ValueKey("snoozed_tile:${it.id}"),
                        showDrag: false,
                        indexForDrag: 0,
                      ),
                      const SizedBox(height: 15),
                    ],
                  ),
                ),
              );
            }),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () {
                setState(() {
                  for (final it in snoozed) {
                    it.snoozeUntil = null;
                  }
                });
                widget.logic.onChange();
              },
              child: const Text("Tout réafficher"),
            ),
          ],
          const SizedBox(height: 10),
        ],
      );
    }

    final autoExpanded =
        running != null && shoppingId != null && running.id == shoppingId;

    // 1) DONE
    final doneActions =
        allActions.where((a) => a.done && a.archived != true).toList();

    // 2) OPEN POOL
    final openPool = allActions
        .where((a) => !a.done && a.archived != true)
        .where((a) => !widget.logic.isSnoozed(a, now))
        .where((a) {
      final actId = (a.activityId ?? '').trim();
      if (actId.isEmpty) return true;
      return !widget.logic.isActivitySnoozed(actId, now);
    }).toList();

    // ✅ FILTRES AUTO-ACTIFS (dès qu'il y a au moins 1 filtre sélectionné)
    final f = widget.logic.state.filters;
    final manualFiltersActive =
        f.domainIds.isNotEmpty || f.activityIds.isNotEmpty;

// activité en cours (uniquement sur l'onglet “today”)
    final runningId = hasRunning ? running.id : null;

    /// ✅ Inbox stricte (ta définition actuelle)
    bool isInbox(DayPlanItem a) {
      final noDomain = (a.domainId == null || a.domainId!.isEmpty);
      final noAct = (a.activityId == null || a.activityId!.isEmpty);
      final notCourses = a.toPlan != true;
      return noDomain && noAct && notCourses;
    }

    Activity? _activityById(String? id) {
      final actId = (id ?? '').trim();
      if (actId.isEmpty) return null;
      for (final a in widget.logic.state.activities) {
        if (a.id == actId) return a;
      }
      return null;
    }

    String? effectiveActivityId(DayPlanItem it) {
      // action / item classique
      if (it.kind == PlanKind.action) {
        final id = (it.activityId ?? '').trim();
        return id.isEmpty ? null : id;
      }

      // habit / routine
      if (it.kind == PlanKind.habit) {
        final habitId = (it.refId ?? it.habitId ?? '').trim();
        if (habitId.isEmpty) return null;

        final routineAct = _activityById(habitId);
        final linkedId = (routineAct?.linkedActivityId ?? '').trim();
        if (linkedId.isNotEmpty) return linkedId;

        // fallback legacy si besoin
        final legacy = (it.activityId ?? '').trim();
        return legacy.isEmpty ? null : legacy;
      }

      // autres types si nécessaire
      final id = (it.activityId ?? '').trim();
      return id.isEmpty ? null : id;
    }

    bool isActivitySnoozedNow(String? activityId) {
      final id = (activityId ?? '').trim();
      if (id.isEmpty) return false;

      final iso = widget.logic.state.snoozedUntil[id];
      if (iso == null || iso.isEmpty) return false;

      final until = DateTime.tryParse(iso);
      if (until == null) return false;

      return until.isAfter(DateTime.now());
    }

    bool passesEffectiveFilters(DayPlanItem it) {
      final itAct = effectiveActivityId(it);

      // 0) masquer tout item lié à une activité cachée / snoozée
      if (isActivitySnoozedNow(itAct)) return false;

      // 1) filtres manuels => ton filtre actuel
      if (manualFiltersActive) return _passesFilters(it);

      // 2) sinon, si activité en cours => ne montrer que cette activité + inbox
      if (runningId != null) {
        if (itAct != null && itAct.isNotEmpty) return itAct == runningId;
        return isInbox(it);
      }

      // 3) sinon => pas de filtre
      return true;
    }

    final openPoolFiltered = openPool.where(passesEffectiveFilters).toList();

    // ✅ INBOX (neutres)
    final inboxActions = openPoolFiltered.where((a) {
      final noDomain = (a.domainId == null || a.domainId!.isEmpty);
      final noAct = (a.activityId == null || a.activityId!.isEmpty);
      final notCourses = a.toPlan != true;
      return noDomain && noAct && notCourses;
    }).toList()
      ..sort((a, b) => a.title.compareTo(b.title));

    // ✅ COURSES
    final shoppingActions = (shoppingId == null)
        ? <DayPlanItem>[]
        : openPoolFiltered
            .where((a) => a.activityId == shoppingId && a.toPlan == true)
            .toList();

    final usedIds = <String>{
      ...inboxActions.map((e) => e.id),
      ...shoppingActions.map((e) => e.id),
    };

    // Items assignés à un bloc (exclus de la liste libre)
    final sortedBlocks = [...widget.logic.state.blocks]
      ..sort((a, b) => a.order.compareTo(b.order));
    final blockItemsByBlockId = <String, List<DayPlanItem>>{};
    for (final b in sortedBlocks) {
      var items = widget.logic.blockItemsForDay(b.id, ymd);
      // Si une activité est en cours, on filtre les items du bloc
      // pour n'afficher que ceux qui lui sont liés
      if (runningId != null) {
        items = items.where((it) {
          final actId = effectiveActivityId(it);
          return actId == runningId;
        }).toList();
      }
      blockItemsByBlockId[b.id] = items;
    }
    // Avec filtre actif, on n'affiche que les blocs qui ont des items liés
    final visibleBlocks = runningId != null
        ? sortedBlocks
            .where((b) => blockItemsByBlockId[b.id]!.isNotEmpty)
            .toList()
        : sortedBlocks;
    final blockItemIds = <String>{
      for (final items in blockItemsByBlockId.values)
        for (final it in items) it.id,
    };
    usedIds.addAll(blockItemIds);

    final todo = openPoolFiltered
        .where((it) => !usedIds.contains(it.id) && it.kind != PlanKind.habit)
        .toList();

    // (Optionnel) tu peux garder ton tri par order déjà fait via allActions,
    // ici on stabilise :
    todo.sort((a, b) => a.order.compareTo(b.order));

    // ✅ + si tu veux garder le where(_passesFilters) en aval, il est déjà appliqué ici.
    // Donc on utilise directement todo/inbox/courses.

    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: SegmentedButton<_Scope>(
              segments: const [
                ButtonSegment(
                  value: _Scope.goals,
                  icon: Icon(Icons.flag_rounded),
                  label: Text('Objectifs'),
                ),
                ButtonSegment(
                  value: _Scope.today,
                  icon: Icon(Icons.bolt_rounded),
                  label: Text('Actions'),
                ),
              ],
              selected: {_scope},
              onSelectionChanged: (s) => setState(() => _scope = s.first),
            ),
          ),
          if (_scope == _Scope.goals)
            Expanded(child: _buildGoalsContent(context))
          else
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
                children: [
          // Défi du jour
          if (isTodayTab) ...[
            Builder(builder: (context) {
              final challenge = widget.logic.dailyChallengeHabit(ymd);
              if (challenge == null) return const SizedBox.shrink();

              final cs = Theme.of(context).colorScheme;
              final today = DateTime.now();
              final todayDate = DateTime(today.year, today.month, today.day);
              final sevenDaysAgo = todayDate.subtract(const Duration(days: 7));
              final quota = widget.logic.dayQuotaFor(challenge);
              final done7 = widget.logic.habitSumForRange(
                  challenge.id, sevenDaysAgo, todayDate);
              final ratio7 = (done7 / (quota * 7)).clamp(0.0, 1.0);

              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => widget.onOpenRoutineDetail?.call(challenge.id),
                  child: Ink(
                    decoration: BoxDecoration(
                      color: cs.primaryContainer.withValues(alpha: .45),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color: cs.primary.withValues(alpha: .3)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                '⚡ Défi du jour',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: cs.primary,
                                  letterSpacing: .5,
                                ),
                              ),
                              const Spacer(),
                              TextButton(
                                style: TextButton.styleFrom(
                                  padding: EdgeInsets.zero,
                                  minimumSize: Size.zero,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  foregroundColor:
                                      cs.onSurface.withValues(alpha: .45),
                                  textStyle: const TextStyle(fontSize: 12),
                                ),
                                onPressed: () {
                                  widget.logic.skipChallengeForToday(ymd);
                                  setState(() {});
                                },
                                child: const Text('Passer'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            challenge.name,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(3),
                            child: LinearProgressIndicator(
                              value: ratio7,
                              minHeight: 5,
                              backgroundColor:
                                  cs.onSurface.withValues(alpha: .10),
                              color: ratio7 < 0.5 ? cs.error : cs.primary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${(ratio7 * 100).round()}% sur 7 jours',
                            style: TextStyle(
                              fontSize: 11,
                              color: cs.onSurface.withValues(alpha: .55),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
          ],

          // Blocs journaliers
          if (isTodayTab) ...[
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Blocs',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() => _showBlocks = !_showBlocks),
                  child: Text(_showBlocks ? 'Masquer' : 'Voir tout'),
                ),
                IconButton(
                  tooltip: 'Gérer les blocs',
                  icon: const Icon(Icons.tune, size: 20),
                  onPressed: () => showDayBlocksSheet(context, logic: widget.logic).then((_) => setState(() {})),
                ),
              ],
            ),
            if (_showBlocks) ...[
              if (sortedBlocks.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: TextButton.icon(
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Créer un premier bloc'),
                    onPressed: () => showDayBlocksSheet(context, logic: widget.logic).then((_) => setState(() {})),
                  ),
                )
              else ...[
                const SizedBox(height: 4),
                for (final b in visibleBlocks)
                  _buildBlockSection(
                    context,
                    b,
                    blockItemsByBlockId[b.id] ?? [],
                    ymd,
                  ),
                const SizedBox(height: 8),
              ],
            ],
          ],
          _inboxSection(
            inbox: inboxActions,
            onTapAssign: (it) => _openAssignActivitySheet(context, it),
          ),
          const SizedBox(height: 12),
          _coursesSection(
            courses: shoppingActions,
            autoExpanded: autoExpanded,
            shoppingAct: shoppingAct,
          ),
          Row(
            children: [
              const Expanded(
                child: Text(
                  "Actions",
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
              ),
              if (isTodayTab && sortedBlocks.isNotEmpty)
                TextButton.icon(
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                  icon: const Icon(Icons.tune, size: 16),
                  label: const Text('Blocs'),
                  onPressed: () => showDayBlocksSheet(context, logic: widget.logic).then((_) => setState(() {})),
                ),
              TextButton(
                onPressed: () => setState(() => _showAll = !_showAll),
                child: Text(_showAll ? "Masquer" : "Voir tout"),
              ),
            ],
          ),
          if (_showAll) ...[
            const SizedBox(height: 8),
            if (todo.isEmpty)
              Text(
                "Aucune action pour l'instant.",
                style: TextStyle(
                  color:
                      Theme.of(context).colorScheme.onSurface.withOpacity(.7),
                ),
              )
            else
              ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: todo.length,
                onReorder: (oldIndex, newIndex) {
                  setState(() {
                    widget.logic.reorderTodayBucket(
                      yyyymmdd: ymd,
                      bucketVisible: todo,
                      oldIndex: oldIndex,
                      newIndex: newIndex,
                    );
                  });
                },
                itemBuilder: (context, i) {
                  final it = todo[i];
                  final tile = _todayTile(
                    context,
                    it,
                    key: ValueKey("todo:${it.id}"),
                    showDrag: true,
                    indexForDrag: i,
                  );

                  return KeyedSubtree(
                    key: ValueKey("todoWrap:${it.id}"),
                    child: tile,
                  );
                },
              ),
            const SizedBox(height: 12),
          ],
          if (isTodayTab && laterToday.isNotEmpty) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                const Text(
                  "Ce soir",
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
                const SizedBox(width: 8),
                Text(
                  "(${laterToday.length})",
                  style: TextStyle(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withOpacity(0.6),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...laterToday.map((it) {
              if (it.kind == PlanKind.action) {
                return _todayTile(
                  context,
                  it,
                  key: ValueKey("later:${it.id}"),
                  showDrag: false,
                  indexForDrag: 0,
                );
              } else {
                return _habitTileLater(context, it);
              }
            }),
          ],
          if (isTodayTab && doneActions.isNotEmpty) ...[
            const SizedBox(height: 8),
            InkWell(
              onTap: () => setState(() => _showDone = !_showDone),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        "Faits (${doneActions.length})",
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withOpacity(0.75),
                        ),
                      ),
                    ),
                    Icon(
                      _showDone ? Icons.expand_less : Icons.expand_more,
                      size: 20,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withOpacity(0.6),
                    ),
                  ],
                ),
              ),
            ),
            if (_showDone) ...[
              ...doneActions.map((it) {
                final viewedDay = DateTime.now();
                return Dismissible(
                  key: ValueKey("done:${it.id}"),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    color: Colors.red.withOpacity(0.15),
                    child: const Icon(Icons.delete, color: Colors.red),
                  ),
                  onDismissed: (_) => _deleteActionWithUndo(it),
                  child: _actionCardContent(
                    it,
                    viewedDay: viewedDay,
                    ymdViewed: ymd,
                    isTodayTab: isTodayTab,
                  ),
                );
              }),
            ],
          ],
          if (isTodayTab)
            _snoozedSection(
              snoozed: snoozedActions,
              onUnsnooze: (it) {
                setState(() => it.snoozeUntil = null);
                widget.logic.onChange();
              },
            ),
          // Section Demain (repliable)
          if (isTodayTab) ...[
            const SizedBox(height: 8),
            _tomorrowSection(tomorrowYmd: yyyymmdd(
              DateTime.now().add(const Duration(days: 1)))),
          ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  Map<String, String?> buildHabitToActivityMap(List<HabitAssocEvent> events) {
    final pinned = <String, String>{};
    final suggested = <String, String>{};

    for (final e in events) {
      switch (e.type) {
        case HabitAssocEventType.pinned:
          if (e.toActivityId != null) pinned[e.habitId] = e.toActivityId!;
          break;
        case HabitAssocEventType.changeSuggested:
          if (e.toActivityId != null) suggested[e.habitId] = e.toActivityId!;
          break;
      }
    }

    // pinned gagne toujours
    final out = <String, String?>{};
    for (final habitId in {...pinned.keys, ...suggested.keys}) {
      out[habitId] = pinned[habitId] ?? suggested[habitId];
    }
    return out;
  }

  Widget _habitTileLater(BuildContext context, DayPlanItem it) {
    final cs = Theme.of(context).colorScheme;
    final until = it.snoozeUntil!;
    final hh = until.hour.toString().padLeft(2, '0');
    final mm = until.minute.toString().padLeft(2, '0');

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(Icons.repeat, color: cs.primary.withOpacity(0.8)),
        title: Text(it.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text("🌙 $hh:$mm"),
        trailing: const Icon(Icons.chevron_right),
        onTap: () {
          // option : la remettre en “maintenant” (unsnooze)⏰
          setState(() => it.snoozeUntil = null);
          widget.logic.onChange();
        },
      ),
    );
  }

  Future<String?> _promptText({
    required String title,
    String initial = "",
  }) async {
    final c = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: c,
          autofocus: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => Navigator.of(ctx).pop(c.text.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text("Annuler"),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(c.text.trim()),
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

  Future<void> _renameRoutine(Activity act) async {
    // ✅ simple guard
    final current = act.name.trim();
    final txt = await _promptText(
      title: "Renommer la routine",
      initial: current,
    );

    final next = (txt ?? "").trim();
    if (next.isEmpty || next == current) return;

    setState(() {
      act.name = next;
    });

    widget.logic.onChange();

    // optionnel: petit feedback
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Routine renommée"),
          duration: Duration(milliseconds: 900),
        ),
      );
    });
  }

  Widget _todayTile(
    BuildContext context,
    DayPlanItem it, {
    required Key key,
    required bool showDrag,
    required int indexForDrag,
    VoidCallback? onTapOverride,
  }) {
    final now = DateTime.now();

    // ✅ jour affiché (aujourd'hui / demain) selon ton ancienne logique
    final viewed =
        (_scope == _Scope.today) ? now : now.add(const Duration(days: 1));

    final isTodayTab = (_scope == _Scope.today);

    final viewedDay = DateTime(viewed.year, viewed.month, viewed.day);
    final ymdViewed = yyyymmdd(viewedDay);

    final isVirtual = it.id.startsWith('virt:');

    // --- UI helpers -----------------------------------------------------------

    Widget dragHandle() {
      final icon = Icon(
        Icons.drag_handle,
        size: 20,
        color: showDrag
            ? Colors.white.withValues(alpha: 0.85)
            : Colors.white.withValues(alpha: 0.25),
      );

      if (!showDrag) {
        return SizedBox(width: 32, height: 32, child: Center(child: icon));
      }

      return ReorderableDragStartListener(
        index: indexForDrag,
        child: SizedBox(width: 32, height: 32, child: Center(child: icon)),
      );
    }

    Widget btnCompact({
      required IconData icon,
      required String tooltip,
      required VoidCallback? onPressed,
      double size = 20,
    }) {
      return IconButton(
        tooltip: tooltip,
        icon: Icon(icon, size: size),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 32, height: 32),
        visualDensity: VisualDensity.compact,
        onPressed: onPressed,
      );
    }

    void toast(String msg) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }

    // ❌ pour les virtuels : pas de déplacement “entre jours”
    Widget moveDayArrowsIfAny() {
      final canMove =
          !isVirtual && ((it.kind == PlanKind.action) || (it.refId != null));
      if (!canMove) return const SizedBox.shrink();

      // viewed = today ou tomorrow selon onglet
      final ymdPrev = yyyymmdd(viewedDay.subtract(const Duration(days: 1)));
      final ymdNext = yyyymmdd(viewedDay.add(const Duration(days: 1)));

      // Sur today : → (vers demain)
      // Sur tomorrow : ← (vers today) et → (vers après-demain)
      final forwardTooltip =
          isTodayTab ? "Déplacer vers demain" : "Déplacer vers après-demain";
      final backTooltip = "Renvoyer à aujourd'hui";

      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!isTodayTab)
            btnCompact(
              icon: Icons.arrow_back,
              tooltip: backTooltip,
              onPressed: () {
                widget.logic.movePlanItemToDay(it.id, ymdPrev);
                toast("Déplacé vers aujourd'hui");
                setState(() {});
              },
            ),
          btnCompact(
            icon: Icons.arrow_forward,
            tooltip: forwardTooltip,
            onPressed: () {
              widget.logic.movePlanItemToDay(it.id, ymdNext);
              toast(isTodayTab
                  ? "Déplacé vers demain"
                  : "Déplacé vers après-demain");
              setState(() {});
            },
          ),
        ],
      );
    }

    Widget moveToEndArrowIfAny() {
      final canMoveEnd =
          !isVirtual; // tu peux aussi autoriser actions virtuelles si tu veux
      return btnCompact(
        icon: Icons.arrow_downward,
        tooltip:
            isVirtual ? "Raccourci (non planifié)" : "Mettre en fin de liste",
        onPressed: canMoveEnd
            ? () {
                widget.logic.movePlanItemToEnd(ymdViewed, it.id);
                setState(() {});
              }
            : null,
      );
    }

    Widget moveToTopArrowIfAny() {
      final ymd = yyyymmdd(viewedDay);

      return IconButton(
        icon: const Icon(Icons.arrow_upward, size: 20),
        tooltip: "Mettre en haut",
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 32, height: 32),
        visualDensity: VisualDensity.compact,
        onPressed: () {
          widget.logic.movePlanItemToTop(ymd, it.id);
          setState(() {});
        },
      );
    }

    final removeBtn = btnCompact(
      icon: Icons.close,
      tooltip: "Retirer de la liste du jour",
      onPressed: () {
        setState(() {
          widget.state.dayPlan.removeWhere((e) => e.id == it.id);
          widget.logic.onChange();
        });
      },
      size: 18,
    );

    Widget _actionControlsRow(DayPlanItem it) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          btnCompact(
            icon: Icons.arrow_upward,
            tooltip: "En haut",
            onPressed: () {
              final ymd =
                  yyyymmdd(DateTime(viewed.year, viewed.month, viewed.day));
              widget.logic.movePlanItemToTop(ymd, it.id);
              setState(() {});
            },
          ),
          btnCompact(
            icon: Icons.arrow_downward,
            tooltip: "En bas",
            onPressed: () {
              final ymd =
                  yyyymmdd(DateTime(viewed.year, viewed.month, viewed.day));
              widget.logic.movePlanItemToEnd(ymd, it.id);
              setState(() {});
            },
          ),
          // ← / → (today/tomorrow) si tu l'as déjà
          moveDayArrowsIfAny(),
        ],
      );
    }

    String _actionSubtitle(DayPlanItem it) {
      if (it.goalActionId != null) {
        final g = widget.state.goals.firstWhereOrNull(
            (g) => g.actions.any((a) => a.id == it.goalActionId));
        if (g != null) return '🎯 ${g.title}';
      }
      final actId = (it.activityId ?? '').trim();
      if (actId.isEmpty) return "Inbox";
      final a = widget.state.activities.firstWhereOrNull((x) => x.id == actId);
      return "Activité • ${a?.name ?? '—'}";
    }

    Widget _actionCardLikeHabit(DayPlanItem it) {
      final dim = it.done;
      final cs = Theme.of(context).colorScheme;
      final subtitle = _actionSubtitle(it);

      return Card(
        margin: const EdgeInsets.only(bottom: 6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Row(
            children: [
              Checkbox(
                value: it.done,
                shape: const CircleBorder(),
                onChanged: (v) {
                  final done = v ?? false;
                  if (done && it.toPlan == true) {
                    widget.logic.archiveAction(it);
                    setState(() {});
                    return;
                  }
                  setState(() => it.done = done);
                  widget.logic.onChange();
                },
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      it.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: dim
                            ? cs.onSurface.withOpacity(.45)
                            : cs.onSurface,
                        decoration: dim ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    if (subtitle != 'Inbox') ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurface.withOpacity(.50),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (showDrag) dragHandle(),
            ],
          ),
        ),
      );
    }

    Future<void> _openActionSheet(BuildContext context, DayPlanItem it) async {
      final res = await showModalBottomSheet<_ActionSheetResult>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (ctx) {
          return Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 10,
              bottom: 16 + MediaQuery.of(ctx).viewInsets.bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ---- Titre (rename)
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        it.title,
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 18),
                      ),
                    ),
                    IconButton(
                      tooltip: "Renommer",
                      onPressed: () async {
                        final txt = await _askText(ctx, "Renommer l'action");
                        if (txt == null) return;
                        final t = txt.trim();
                        if (t.isEmpty) return;
                        Navigator.pop(ctx, _ActionSheetResult(rename: t));
                      },
                      icon: const Icon(Icons.edit),
                    ),
                  ],
                ),

                const SizedBox(height: 8),

                // ---- Activité liée
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text("Activité"),
                  subtitle: Text(
                    (it.activityId ?? '').isEmpty
                        ? "Aucune"
                        : (widget.logic.state.activities
                            .firstWhere((a) => a.id == it.activityId,
                                orElse: () => Activity(
                                    domainId: '',
                                    name: 'Activité',
                                    habitTarget: 1))
                            .name),
                  ),
                  trailing: Wrap(
                    spacing: 8,
                    children: [
                      TextButton(
                        onPressed: () async {
                          final picked = await widget.logic
                              .openAssignActivitySheetAndWait(ctx, it);
                          if (picked == null) return;
                          Navigator.pop(
                              ctx,
                              _ActionSheetResult(
                                  newActivityId: picked.id,
                                  newDomainId: picked.domainId));
                        },
                        child: Text((it.activityId ?? '').isEmpty
                            ? "Associer"
                            : "Changer"),
                      ),
                      if ((it.activityId ?? '').isNotEmpty)
                        TextButton(
                          onPressed: () => Navigator.pop(
                              ctx, _ActionSheetResult(unlink: true)),
                          child: const Text("Retirer"),
                        ),
                    ],
                  ),
                ),

                // ---- Bloc assigné
                if (widget.logic.state.blocks.isNotEmpty) ...[
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text("Bloc"),
                    subtitle: Text(() {
                      final bid = widget.logic.effectiveBlockId(it);
                      if (bid == null) return "Aucun";
                      final b = widget.logic.state.blocks
                          .firstWhereOrNull((b) => b.id == bid);
                      if (b == null) return "Aucun";
                      return '${b.emoji != null ? "${b.emoji} " : ""}${b.name}';
                    }()),
                    trailing: Wrap(
                      spacing: 8,
                      children: [
                        TextButton(
                          onPressed: () async {
                            final picked = await showBlockPickerSheet(
                                ctx,
                                logic: widget.logic,
                                currentBlockId: it.blockId);
                            if (picked == null) return;
                            widget.logic.assignActionToBlock(
                                it.id, picked.isEmpty ? null : picked);
                            if (!mounted) return;
                            Navigator.pop(ctx, _ActionSheetResult());
                          },
                          child: Text(
                              (widget.logic.effectiveBlockId(it) == null)
                                  ? "Assigner"
                                  : "Changer"),
                        ),
                        if (widget.logic.effectiveBlockId(it) != null)
                          TextButton(
                            onPressed: () {
                              widget.logic.assignActionToBlock(it.id, null);
                              Navigator.pop(ctx, _ActionSheetResult());
                            },
                            child: const Text("Retirer"),
                          ),
                      ],
                    ),
                  ),
                ],

                if (!isVirtual) ...[
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      Icons.arrow_forward,
                      size: 18,
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                    ),
                    title: Text(isTodayTab ? 'Déplacer à demain' : 'Déplacer à après-demain'),
                    onTap: () {
                      final now = DateTime.now();
                      final today = DateTime(now.year, now.month, now.day);
                      final dest = isTodayTab
                          ? yyyymmdd(today.add(const Duration(days: 1)))
                          : yyyymmdd(today.add(const Duration(days: 2)));
                      widget.logic.moveItemToDayById(it.id, dest);
                      widget.logic.onChange();
                      setState(() {});
                      Navigator.pop(ctx);
                    },
                  ),
                ],

                const Divider(height: 16),

                Row(
                  children: [
                    if (it.goalActionId != null) ...[
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(
                              ctx, _ActionSheetResult(deactivate: true)),
                          child: const Text("Retirer de la liste"),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => Navigator.pop(
                            ctx, _ActionSheetResult(markDone: true)),
                        icon: const Icon(Icons.check),
                        label: const Text("Marquer fait"),
                      ),
                    ),
                  ],
                ),

                // ---- Supprimer (optionnel)
                TextButton(
                  style: TextButton.styleFrom(
                      foregroundColor: Theme.of(ctx).colorScheme.error),
                  onPressed: () =>
                      Navigator.pop(ctx, _ActionSheetResult(delete: true)),
                  child: const Text("Supprimer"),
                ),
              ],
            ),
          );
        },
      );

      if (res == null) return;

      setState(() {
        if (res.rename != null) it.title = res.rename!;
        if (res.unlink == true) it.activityId = null;
        if (res.newActivityId != null) {
          it.activityId = res.newActivityId;
          it.domainId = res.newDomainId ?? it.domainId;
        }
        if (res.markDone == true) it.done = true;
      });

      if (res.delete == true) {
        widget.state.dayPlan.removeWhere((e) => e.id == it.id);
      }

      if (res.deactivate == true && it.goalActionId != null) {
        widget.logic.removeGoalActionFromToday(it.goalActionId!);
      }

      widget.logic.onChange();
    }

    Widget buildTitle(String title, {bool struck = false, bool dim = false}) {
      return Text(
        title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 18,
          decoration: struck ? TextDecoration.lineThrough : null,
          color: dim ? Colors.white.withValues(alpha: 0.55) : null,
        ),
      );
    }

    // --- SWITCH by kind -------------------------------------------------------

    switch (it.kind) {
      case PlanKind.action:
        {
          final card = GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTapOverride ??
                () async {
                  await _openActionSheet(context, it);
                  if (!mounted) return;
                  setState(() {});
                },
            child: _actionCardLikeHabit(it),
          );

          return Dismissible(
            key: ValueKey("dismiss:${it.id}"),
            direction: DismissDirection.endToStart,
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              color: Colors.red.withOpacity(0.15),
              child: const Icon(Icons.delete, color: Colors.red),
            ),
            onDismissed: (_) => _deleteActionWithUndo(it),
            child: card,
          );
        }

      case PlanKind.activityTime:
        {
          final dayStart =
              DateTime(viewedDay.year, viewedDay.month, viewedDay.day);
          final dur =
              widget.logic.totalForRangeByActivity(it.refId!, dayStart, now);

          final startBtn = FilledButton.icon(
            onPressed: () {
              widget.logic.start(it.refId!);
              setState(() {});
            },
            icon: const Icon(Icons.play_arrow),
            label: Text(it.refId == null ? "Lancer" : "Lancer"),
          );

          return Card(
            key: key,
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                children: [
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (showDrag) dragHandle(),
                      moveToEndArrowIfAny(),
                    ],
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          buildTitle(it.title),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      isTodayTab ? "Aujourd'hui :" : "Demain :",
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w400,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      "${dur.inMinutes ~/ 60}h ${dur.inMinutes % 60}m",
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              startBtn,
                              removeBtn,
                              moveDayArrowsIfAny(),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

      case PlanKind.habit:
        {
          final habitId = it.refId;
          final act =
              widget.state.activities.firstWhereOrNull((a) => a.id == habitId);

          if (act == null || habitId == null || habitId.isEmpty) {
            return Card(
              key: key,
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text(
                  it.title,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 15),
                ),
                subtitle: const Text("Activité introuvable (supprimée ?)"),
                trailing: removeBtn,
              ),
            );
          }

          // ✅ Ta logique "virtuel" reste valable
          final isVirtual = it.id.startsWith('virt:');

          // ✅ UI : NowHabitTileFull + row d'actions
          return Card(
            key: key,
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ✅ Boutons “organisation” (pas de comptage ici)
                  Row(
                    children: [
                      // Drag handle si tu veux le garder dans la tuile
                      if (showDrag) dragHandle(),
                      if (showDrag) const SizedBox(width: 6),

                      moveToTopArrowIfAny(),

                      // Mettre fin de liste
                      moveToEndArrowIfAny(),

                      const SizedBox(width: 6),

                      // Flèches jour (←/→)
                      moveDayArrowsIfAny(),

                      const Spacer(),

                      // Optionnel : retirer du jour (désactivé pour virtuel si tu veux)
                      if (!isVirtual) removeBtn,
                    ],
                  ),

                  NowHabitTileFull(
                    logic: widget.logic,
                    st: widget.state, // ✅ TodayView => state
                    habitId: habitId,
                    day: viewedDay, // ✅ ton jour affiché
                    onTap: () async {
                      final res = await showHabitSettingsSheet(
                        context,
                        act: act,
                        onRename: (refresh) async {
                          await _renameRoutine(act);
                          refresh();
                        },
                        onSaved: () {
                          widget.logic.onChange();
                          setState(() {}); // ✅ refresh TodayView
                        },
                      );

                      if (res == null) return;

                      // Si tu as laissé applyDirectly=true (par défaut), tu n'as RIEN d'autre à faire.
                      // Sinon, applique ici.
                    },
                    onLongPress: () async {
                      // si tu veux ouvrir le sheet d'édition complet
                      // openHabitEditSheet(...) ou ton editor
                    },
                  ),

                  const SizedBox(height: 6),
                ],
              ),
            ),
          );
        }
    }
  }

  Future<String?> _askText(BuildContext ctx, String title) async {
    final ctrl = TextEditingController();
    return await showDialog<String>(
      context: ctx,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: TextField(controller: ctrl, autofocus: true),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: const Text('OK')),
        ],
      ),
    );
  }

  Future<void> showHabitChecklist(
    BuildContext context, {
    required String title,
    required int done,
    required int target,
    required void Function(int newDone) onSet,
  }) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        int local = done;
        return StatefulBuilder(builder: (ctx, setSB) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      itemCount: target,
                      itemBuilder: (_, i) {
                        final checked = i < local;
                        return CheckboxListTile(
                          value: checked,
                          onChanged: (v) => setSB(() {
                            // cocher = régler "local" à max(i+1, local)
                            // décocher = régler à min(i, local)
                            local = v == true ? i + 1 : i;
                          }),
                          title: Text("Unité ${i + 1}"),
                          dense: true,
                          controlAffinity: ListTileControlAffinity.leading,
                        );
                      },
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton(
                      onPressed: () {
                        onSet(local);
                        Navigator.pop(ctx);
                      },
                      child: const Text("Valider"),
                    ),
                  ),
                ],
              ),
            ),
          );
        });
      },
    );
  }
}

class HabitAutoTicksRow extends StatelessWidget {
  final int done; // ex: 3
  final int target; // ex: 1 (info, pas limitant)
  final VoidCallback onIncOne;
  final VoidCallback onDecOne;

  const HabitAutoTicksRow({
    super.key,
    required this.done,
    required this.target,
    required this.onIncOne,
    required this.onDecOne,
  });

  @override
  Widget build(BuildContext context) {
    // On aligne sur HabitTicksRow : 10 ronds max en ligne
    const int show = 10;

    Widget dot(bool filled, {bool isBonus = false}) => GestureDetector(
          onTap: () => filled ? onDecOne() : onIncOne(),
          onLongPress: () {
            // boost ±5 simple (même logique que HabitTicksRow)
            for (int k = 0; k < 5; k++) {
              if (!filled) {
                onIncOne();
              } else {
                onDecOne();
              }
            }
          },
          child: Container(
            width: 18,
            height: 18,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              // plein -> primary ; vide -> transparent
              color: filled ? Theme.of(context).colorScheme.primary : null,
              border: Border.all(
                color: isBonus
                    // bonus un poil plus visible (optionnel)
                    ? Theme.of(context).colorScheme.primary.withOpacity(0.65)
                    : Theme.of(context).colorScheme.onSurface.withOpacity(0.35),
              ),
            ),
          ),
        );

    final cappedDone = done.clamp(0, show);
    final canShowBonus = cappedDone < show; // tant qu'on n'a pas 10 pleins

    return Row(
      children: [
        // ronds validés
        for (int i = 0; i < cappedDone; i++) dot(true),

        // 1 rond "bonus" vide cliquable (+1)
        if (canShowBonus) dot(false, isBonus: true),

        // (optionnel) petit texte
        const SizedBox(width: 8),
        Text(
          "$done / $target",
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

class HabitTicksRow extends StatelessWidget {
  final int done; // ex: 3
  final int target; // ex: 10
  final VoidCallback onIncOne;
  final VoidCallback onDecOne;
  final Future<void> Function()? onOpenFull; // ouvre la checklist complète

  const HabitTicksRow({
    super.key,
    required this.done,
    required this.target,
    required this.onIncOne,
    required this.onDecOne,
    this.onOpenFull,
  });

  @override
  Widget build(BuildContext context) {
    final show = target.clamp(0, 10); // max 10 ronds en ligne
    final extra = (target - show).clamp(0, 999);

    Widget dot(int i, bool filled) => GestureDetector(
          onTap: () => filled ? onDecOne() : onIncOne(),
          onLongPress: () {
            // boost ±5 simple
            for (int k = 0; k < 5; k++) {
              if (!filled)
                onIncOne();
              else
                onDecOne();
            }
          },
          child: Container(
            width: 18,
            height: 18,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: filled ? Theme.of(context).colorScheme.primary : null,
              border: Border.all(
                color:
                    Theme.of(context).colorScheme.onSurface.withOpacity(0.35),
              ),
            ),
          ),
        );

    return Row(
      children: [
        // ticks
        for (int i = 0; i < show; i++) dot(i, i < done),
        // +X pour les cibles longues
        if (extra > 0)
          TextButton(
            onPressed: onOpenFull,
            child: Text("+$extra"),
          ),
      ],
    );
  }
}

class NowTab extends StatefulWidget {
  final AppLogic logic;
  final AppState st;
  final List<DayPlanItem> items;
  final DateTime day;

  final List<RowItem> Function({
    required List<DayPlanItem> items,
    required AppState st,
    required AppLogic logic,
    required Map<String, String?> assoc,
  }) buildRowsGrouped;

  final VoidCallback? onGoTodo; // ✅ AJOUT

  const NowTab({
    super.key,
    required this.logic,
    required this.st,
    required this.items,
    required this.day,
    required this.buildRowsGrouped,
    this.onGoTodo, // ✅ AJOUT
  });

  @override
  State<NowTab> createState() => _NowTabState();
}

class _NowTabState extends State<NowTab> {
// 👉 gèle “ce qu'on fait maintenant”
// option: sauter les items déjà “faits”
  final Set<String> _skippedIds = {};
  final Set<String> _doneTodayIds = {};
  bool _showArchives = false;
  bool _showGlobalArchives = false;

  String? _skippedYmd;
  String? _activeBlockId; // bloc actif en mode séquence

  List<String> checklistForHabit(String habitName) {
    switch (habitName.toLowerCase()) {
      case 'Prendre un bain de mer':
        return ['Lait', 'Fruits', 'Légumes'];
      case 'soin':
        return ['Douche', 'Dents', 'Peau'];
      default:
        return ['Courses', 'Dents', 'Peau'];
    }
  }

  Future<void> _openSnoozeActivitySheet(
      BuildContext context, Activity a) async {
    final logic = widget.logic;
    final now = DateTime.now();

    DateTime endOfDay(DateTime d) =>
        DateTime(d.year, d.month, d.day, 23, 59, 59);

    Future<void> hideUntil(DateTime until) async {
      logic.snoozeActivityUntil(a.id, until);
      Navigator.pop(context);
      if (!mounted) return;
      setState(() {});
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        final snoozed = logic.isActivitySnoozed(a.id, now);

        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.snooze),
                  title: Text(a.name,
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle:
                      Text(snoozed ? "Cachée (zzz)" : "Cacher l'activité ?"),
                ),
                const Divider(height: 1),
                ListTile(
                  title: const Text("Demain"),
                  onTap: () =>
                      hideUntil(endOfDay(now.add(const Duration(days: 1)))),
                ),
                ListTile(
                  title: const Text("Dans 3 jours"),
                  onTap: () =>
                      hideUntil(endOfDay(now.add(const Duration(days: 3)))),
                ),
                ListTile(
                  title: const Text("Dans 7 jours"),
                  onTap: () =>
                      hideUntil(endOfDay(now.add(const Duration(days: 7)))),
                ),
                ListTile(
                  title: const Text("Choisir une date…"),
                  onTap: () async {
                    Navigator.pop(ctx);
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: now.add(const Duration(days: 1)),
                      firstDate: now,
                      lastDate: now.add(const Duration(days: 365)),
                    );
                    if (picked == null) return;
                    logic.snoozeActivityUntil(a.id, endOfDay(picked));
                    if (!mounted) return;
                    setState(() {});
                  },
                ),
                if (snoozed)
                  ListTile(
                    leading: const Icon(Icons.visibility),
                    title: const Text("Afficher"),
                    onTap: () {
                      logic.unsnoozeActivity(a.id);
                      Navigator.pop(ctx);
                      if (!mounted) return;
                      setState(() {});
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Activity? _activityById(String? id) {
    final actId = (id ?? '').trim();
    if (actId.isEmpty) return null;
    for (final a in widget.logic.state.activities) {
      if (a.id == actId) return a;
    }
    return null;
  }

  Future<Activity?> _pickActivity() async {
    Activity? picked;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => AssignActivitySheet(
        st: widget.logic.state,
        onPick: (act) {
          picked = act;
          Navigator.pop(context);
        },
        onKeepInbox: () => Navigator.pop(context),
      ),
    );

    return picked;
  }

  Future<void> _pickAndAttachActivityToRoutine(String habitId) async {
    final picked = await _pickActivity();
    if (picked == null) return;

    await widget.logic.attachLinkedActivityToRoutine(
      habitId,
      picked.id,
    );

    setState(() {});
  }

  Widget _nowHabitCard(BuildContext context, DayPlanItem it) {
    final ymd =
        yyyymmdd(DateTime(widget.day.year, widget.day.month, widget.day.day));

    // it.refId = habitId chez toi (routine)
    final habitId = it.refId ?? it.habitId;
    if (habitId == null) {
      // fallback : si routine mal formée
      return _nowActionCard(context, it, _skippedIds.length, 1);
    }

    // ✅ garde ton comportement checklist
    widget.logic.ensureChecklistDay(ymd);
    widget.logic.nowHabitId = habitId;

    final act = widget.st.activities.firstWhere(
      (a) => a.id == habitId,
      orElse: () => Activity(domainId: '', name: it.title, habitTarget: 1),
    );

    // Nom du domaine
    final domName = widget.st.domains
        .firstWhere((d) => d.id == it.domainId,
            orElse: () => Domain(id: it.domainId, name: "Domaine"))
        .name;

// routine activity = act (celle que tu as déjà trouvée via habitId)
    final linkedId = act.linkedActivityId; // ✅ nouveau champ sur Activity
    final linkedAct =
        (linkedId == null || linkedId.isEmpty) ? null : _activityById(linkedId);

    final hasLinked = linkedAct != null;

    final running = widget.logic.runningActivity();
    final isRunningThis =
        hasLinked && running != null && running.id == linkedAct.id;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ✅ ton header routine (tu peux réutiliser _nowCard si tu veux)
          Row(
            children: [
              IconButton(
                tooltip: "Fin de liste",
                icon: const Icon(Icons.arrow_downward),
                onPressed: () {
                  setState(() {
                    widget.logic.moveItemToEnd(ymd, it);
                  });
                },
              ),
              Text(domName,
                  style: const TextStyle(
                      fontWeight: FontWeight.w900, fontSize: 18)),
              const SizedBox(width: 6),
              IconButton(
                tooltip: "À demain",
                icon: const Icon(Icons.arrow_forward),
                onPressed: () {
                  widget.logic.moveItemToTomorrow(ymd, it);
                  _skippedIds.add(it.id);
                  setState(() {});
                  ScaffoldMessenger.of(context).clearSnackBars();
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: const Text('Déplacé à demain'),
                    action: SnackBarAction(
                      label: 'Annuler',
                      onPressed: () {
                        widget.logic.moveItemToDayById(it.id, ymd);
                        _skippedIds.remove(it.id);
                        widget.logic.onChange();
                        setState(() {});
                      },
                    ),
                  ));
                },
              ),
            ],
          ),
          const SizedBox(height: 10),

          // ✅ tuile routine détaillée (celle que tu avais)
          NowHabitTileFull(
            logic: widget.logic,
            st: widget.st,
            habitId: habitId,
            day: widget.day,
            onTap: () async {
              final res = await showHabitSettingsSheet(
                context,
                act: act,
                onRename: (refresh) async {
                  await _renameRoutine(act);
                  refresh();
                },
                onSaved: () {
                  widget.logic.onChange();
                  setState(() {}); // ✅ refresh TodayView
                },
              );

              if (res == null) return;

              // Si tu as laissé applyDirectly=true (par défaut), tu n'as RIEN d'autre à faire.
              // Sinon, applique ici.
            },
            onLongPress: () {
              // openHabitEditSheet etc.
            },
          ),

          const SizedBox(height: 10),
          if (hasLinked) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    "Liée à : ${linkedAct.name}",
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withOpacity(.65),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    await widget.logic
                        .attachLinkedActivityToRoutine(habitId, null);
                    widget.logic.onChange();
                    widget.logic.rev.value++;
                    setState(() {});
                  },
                  child: const Text("Désassocier"),
                ),
              ],
            ),
          ],
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  icon: Icon(
                    !hasLinked
                        ? Icons.link
                        : (isRunningThis ? Icons.stop : Icons.play_arrow),
                    size: 20,
                  ),
                  label: Text(
                    !hasLinked
                        ? "Associer"
                        : (isRunningThis ? "Stop" : linkedAct.name),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),

                  // ✅ rouge si STOP
                  style: isRunningThis
                      ? FilledButton.styleFrom(
                          backgroundColor: Colors.red.withOpacity(0.85),
                          foregroundColor: Colors.white,
                        )
                      : null,

                  onPressed: () async {
                    // 1) pas associé -> associer
                    if (!hasLinked) {
                      await _pickAndAttachActivityToRoutine(habitId);
                      setState(() {});
                      return;
                    }

                    // 2) associé + en cours -> STOP
                    if (isRunningThis) {
                      widget.logic.stopActive();
                      setState(() {}); // ✅ refresh immédiat
                      return;
                    }

                    // 3) associé + pas en cours -> START (optionnel: stop autre session)
                    if (running != null) widget.logic.stopActive();
                    widget.logic.start(linkedAct.id);

                    // si tu utilises rev.value++ pour rafraîchir d'autres widgets
                    widget.logic.rev.value++;

                    setState(() {});
                  },

                  onLongPress: hasLinked
                      ? () async {
                          await widget.logic
                              .attachLinkedActivityToRoutine(habitId, null);
                          setState(() {});
                        }
                      : null,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.snooze),
                  label: const Text("Masquer"),
                  // ✅ visible mais grisé si pas associé
                  onPressed: !hasLinked
                      ? null
                      : () => _openSnoozeActivitySheet(context, linkedAct),
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),
          // ✅ checklist (ton rendu existant)
          _routineChecklist(it),

          const SizedBox(height: 12),
          _activitiesSuggestionForCurrent(it),

          const SizedBox(height: 10),
          _toPlanSection(it),
          const SizedBox(height: 10),
          _archivesSection(it),
          const SizedBox(height: 10),
          _archivesGlobalSection(),
        ],
      ),
    );
  }

  Widget _nowActionCard(
      BuildContext context, DayPlanItem it, int skipped, int total) {
    final domainName = (it.domainId != null)
        ? widget.st.domains
            .firstWhere(
              (d) => d.id == it.domainId,
              orElse: () => Domain(id: it.domainId!, name: "Domaine"),
            )
            .name
        : "Maintenant";

    final running = widget.logic.runningActivity();

    final actId = (it.activityId ?? '').trim(); // DayPlanItem action
    final hasActivity = actId.isNotEmpty;

    Activity? act;
    if (hasActivity) {
      final idx =
          widget.logic.state.activities.indexWhere((a) => a.id == actId);
      if (idx >= 0) act = widget.logic.state.activities[idx];
    }

    final actName = act?.name ?? "Activité";
    final isRunningThis = hasActivity && running != null && running.id == actId;

// Style STOP (rouge mais theme-friendly)
    final ButtonStyle? startStopStyle = isRunningThis
        ? FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.errorContainer,
            foregroundColor: Theme.of(context).colorScheme.onErrorContainer,
          )
        : null;

    final ymd =
        yyyymmdd(DateTime.now()); // ou la date affichée si tu passes day

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min, // 🔑 évite l'overflow
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ───── HEADER ─────
            Row(
              children: [
                IconButton(
                  tooltip: "Fin de liste",
                  icon: const Icon(Icons.arrow_downward),
                  onPressed: () {
                    setState(() {
                      widget.logic.moveItemToEnd(ymd, it);
                    });
                  },
                ),
                Expanded(
                  child: Text(
                    domainName.toUpperCase(),
                    style: TextStyle(
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w800,
                      color: Theme.of(context)
                          .colorScheme
                          .primary
                          .withOpacity(0.9),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: "À demain",
                  icon: const Icon(Icons.arrow_forward),
                  onPressed: () {
                    widget.logic.moveItemToTomorrow(ymd, it);
                    _skippedIds.add(it.id);
                    setState(() {});
                    ScaffoldMessenger.of(context).clearSnackBars();
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: const Text('Déplacé à demain'),
                      action: SnackBarAction(
                        label: 'Annuler',
                        onPressed: () {
                          widget.logic.moveItemToDayById(it.id, ymd);
                          _skippedIds.remove(it.id);
                          widget.logic.onChange();
                          setState(() {});
                        },
                      ),
                    ));
                  },
                ),
/*                 if (_skippedIds.isNotEmpty)
                  TextButton(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 0),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      minimumSize: Size.zero,
                    ),
                    onPressed: () {
                      setState(() {
                        _skippedIds.clear();
                        _lockedPlanId = null;
                      });
                      _persistNowSets();
                    },
                    child: Text(
                      "Réinitialiser (${_skippedIds.length} / $total)",
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ), */
              ],
            ),

            const SizedBox(height: 10),

            // ───── TITRE ─────
            Text(
              it.title,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),

            const SizedBox(height: 16),

            // ───── ACTIONS PRINCIPALES ─────
            Row(
              children: [
                // 1) Start/Stop (ou Associer)
                Expanded(
                  child: FilledButton.icon(
                    style: startStopStyle,
                    icon: Icon(!hasActivity
                        ? Icons.link
                        : (isRunningThis ? Icons.stop : Icons.play_arrow)),
                    label: Text(
                      !hasActivity
                          ? "Associer"
                          : (isRunningThis ? "STOP" : actName),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onPressed: () async {
                      if (!hasActivity) {
                        final picked = await widget.logic
                            .openAssignActivitySheetAndWait(context, it);
                        if (!mounted) return;
                        if (picked == null) return;

                        setState(() {
                          it.activityId = picked.id;
                          it.domainId =
                              picked.domainId; // si ton DayPlanItem a domainId
                        });
                        widget.logic.onChange();
                        return;
                      }

                      if (isRunningThis) {
                        widget.logic.stopActive();
                        if (!mounted) return;
                        setState(() {});
                        return;
                      }

                      widget.logic.start(actId);
                      if (!mounted) return;
                      setState(() {});
                    },
                  ),
                ),

                const SizedBox(width: 8),

                // 2) Cacher l'activité (zzz) — seulement si associée
                SizedBox(
                  width: 44,
                  height: 44,
                  child: IconButton(
                    tooltip:
                        hasActivity ? "Cacher l'activité" : "Associer d'abord",
                    onPressed: !hasActivity || act == null
                        ? null
                        : () => _openSnoozeActivitySheet(context, act!),
                    icon: const Icon(Icons.snooze),
                  ),
                ),

                const SizedBox(width: 6),

                // 3) Fait (petit bouton vert, icône seule)
                SizedBox(
                  width: 44,
                  height: 44,
                  child: IconButton(
                    tooltip: "Fait",
                    onPressed: () {
                      setState(() {
                        it.done = true;
                        it.isNowFocus = false;
                      });
                      widget.logic.onChange();
                    },
                    style: IconButton.styleFrom(
                      backgroundColor:
                          Theme.of(context).colorScheme.primaryContainer,
                      foregroundColor:
                          Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                    icon: const Icon(Icons.check),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 8),

            // ───── SNOOZE BLOCK (SCROLLABLE) ─────
            Flexible(child: _checklistBlock(context, it)),
          ],
        ),
      ),
    );
  }

  Future<String?> _askText(BuildContext ctx, String title) async {
    final ctrl = TextEditingController();
    return await showDialog<String>(
      context: ctx,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: TextField(controller: ctrl, autofocus: true),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: const Text('OK')),
        ],
      ),
    );
  }

  Future<void> _addChecklistItem(DayPlanItem it) async {
    final txt = await _askText(context, "Ajouter un item");
    if (txt == null) return;

    final t = txt.trim();
    if (t.isEmpty) return;

    setState(() {
      it.checklist.add(ChecklistItem(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        title: t,
        done: false,
      ));
    });

    widget.logic.onChange();
  }

  Widget _checklistBlock(BuildContext context, DayPlanItem it) {
    final cs = Theme.of(context).colorScheme;

    final total = it.checklist.length;
    final doneCount = it.checklist.where((x) => x.done).length;
    final hasItems = total > 0;
    final allDone = hasItems && doneCount == total;
    final noneDone = doneCount == 0;

    void setAll(bool v) {
      setState(() {
        for (final c in it.checklist) {
          c.done = v;
        }
      });
      widget.logic.onChange();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header
        Row(
          children: [
            Expanded(
              child: Text(
                "Checklist${hasItems ? " ($doneCount/$total)" : ""}",
                style:
                    const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
            ),

            // ✅ Tout cocher
            IconButton(
              tooltip: "Tout cocher",
              onPressed: (!hasItems || allDone) ? null : () => setAll(true),
              icon: const Icon(Icons.done_all),
            ),

            // ✅ Tout décocher
            IconButton(
              tooltip: "Tout décocher",
              onPressed: (!hasItems || noneDone) ? null : () => setAll(false),
              icon: const Icon(Icons.remove_done),
            ),

            // Ajouter
            IconButton(
              tooltip: "Ajouter",
              onPressed: () => _addChecklistItem(it),
              icon: const Icon(Icons.add),
            ),
          ],
        ),

        const SizedBox(height: 8),

        // ✅ IMPORTANT : contraindre + scroll
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 260),
          child: it.checklist.isEmpty
              ? Opacity(
                  opacity: 0.6,
                  child: Text(
                    "Aucun item.",
                    style: TextStyle(color: cs.onSurface.withOpacity(.7)),
                  ),
                )
              : ReorderableListView.builder(
                  shrinkWrap: true,
                  buildDefaultDragHandles: false,
                  itemCount: it.checklist.length,
                  onReorder: (oldIndex, newIndex) {
                    setState(() {
                      if (newIndex > oldIndex) newIndex -= 1;
                      final x = it.checklist.removeAt(oldIndex);
                      it.checklist.insert(newIndex, x);
                    });
                    widget.logic.onChange();
                  },
                  itemBuilder: (context, i) {
                    final c = it.checklist[i];

                    final k = (c.id.trim().isNotEmpty)
                        ? ValueKey("chk:${it.id}:${c.id}")
                        : ValueKey("chk:${it.id}:idx:$i");

                    return ListTile(
                      key: k,
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: ReorderableDragStartListener(
                        index: i,
                        child: const Icon(Icons.drag_handle),
                      ),
                      title: Text(
                        c.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          decoration:
                              c.done ? TextDecoration.lineThrough : null,
                          color: c.done
                              ? cs.onSurface.withOpacity(.55)
                              : cs.onSurface.withOpacity(.92),
                        ),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Checkbox(
                            value: c.done,
                            onChanged: (v) {
                              setState(() => c.done = v ?? false);
                              widget.logic.onChange();
                            },
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                          ),
                          IconButton(
                            tooltip: "Supprimer",
                            onPressed: () {
                              setState(() => it.checklist.removeAt(i));
                              widget.logic.onChange();
                            },
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  final redOutlineStyle = OutlinedButton.styleFrom(
    side: BorderSide(
      color: Colors.red.withOpacity(0.75),
      width: 1,
    ),
    foregroundColor: Colors.red.withOpacity(0.85),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  );

  Future<String?> _promptText({
    required String title,
    String initial = "",
  }) async {
    final c = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: c,
          autofocus: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => Navigator.of(ctx).pop(c.text.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text("Annuler"),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(c.text.trim()),
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

  Widget _routineChecklist(DayPlanItem it) {
    if (it.kind != PlanKind.habit || it.refId == null) {
      return const SizedBox.shrink();
    }

    final habitId = it.refId!;

    // Activity (habit) + freq
    final act = widget.st.activities.firstWhere((a) => a.id == habitId);
    final freq = widget.logic.effectiveHabitFreq(act);

    String scopeLabel() {
      switch (freq) {
        case HabitFreq.daily:
          return "Aujourd'hui";
        case HabitFreq.weekly:
          return "Cette semaine";
        case HabitFreq.monthly:
          return "Ce mois-ci";
      }
    }

    final items = widget.logic.checklistForHabit(habitId);

    // ✅ coches persistées par période (daily/weekly/monthly)
    final doneSet = widget.logic.checklistDoneSet(habitId, widget.day);

    final total = items.length;
    final checkedCount = doneSet.length.clamp(0, total);
    final ratio = total == 0 ? 0.0 : checkedCount / total;

    Future<bool> _confirmReset() async {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("Réinitialiser la checklist ?"),
          content: Text(
            "Cela efface les coches pour : ${scopeLabel().toLowerCase()}.",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("Annuler"),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text("Réinitialiser"),
            ),
          ],
        ),
      );
      return ok == true;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    "Checklist • ${scopeLabel()}",
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 14),
                  ),
                ),
                if (doneSet.isNotEmpty)
                  TextButton(
                    onPressed: () async {
                      final ok = await _confirmReset();
                      if (!ok) return;
                      widget.logic.clearChecklistForPeriod(habitId, widget.day);
                      setState(() {});
                    },
                    child: const Text("Réinitialiser"),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            if (items.isNotEmpty) ...[
              TinyBar(
                ratio: ratio,
                labelLeft: "${scopeLabel()} : $checkedCount / $total",
                padding: const EdgeInsets.only(top: 6, bottom: 6),
              ),
            ],
            if (items.isEmpty)
              Text(
                "Aucun item. Appuie sur + pour en ajouter.",
                style: TextStyle(
                  color:
                      Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                ),
              )
            else
              for (int i = 0; i < items.length; i++)
                _checklistRow(
                  habitId: habitId,
                  index: i,
                  label: items[i],
                  doneSet: doneSet,
                ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                tooltip: "Ajouter un item",
                onPressed: () async {
                  final txt = await _promptText(title: "Ajouter un item");
                  if (txt == null || txt.trim().isEmpty) return;
                  widget.logic.addChecklistItem(habitId, txt.trim());
                  setState(() {});
                },
                icon: const Icon(Icons.add),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _checklistRow({
    required String habitId,
    required int index,
    required String label,
    required Set<int> doneSet,
  }) {
    final isChecked = doneSet.contains(index);

    return Row(
      children: [
        Checkbox(
          value: isChecked,
          onChanged: (_) {
            widget.logic.toggleChecklistItem(habitId, widget.day, index);
            setState(() {});
          },
        ),
        Expanded(
          child: Text(label, maxLines: 2, overflow: TextOverflow.ellipsis),
        ),
        IconButton(
          tooltip: "Renommer",
          onPressed: () async {
            final txt = await _promptText(title: "Renommer", initial: label);
            if (txt == null || txt.isEmpty) return;

            // Renommer ne change PAS l'index -> les coches restent OK
            widget.logic.renameChecklistItem(habitId, index, txt);
            setState(() {});
          },
          icon: const Icon(Icons.edit),
        ),
        IconButton(
          tooltip: "Supprimer",
          onPressed: () {
            // ⚠️ suppression d'item = décalage d'index -> il faut réaligner les coches
            widget.logic
                .removeChecklistItemAndFixDone(habitId, widget.day, index);
            setState(() {});
          },
          icon: const Icon(Icons.delete_outline),
        ),
      ],
    );
  }

  void _loadPersistedForDay(String ymd) {
    _skippedIds
      ..clear()
      ..addAll(widget.logic.nowSkippedSet(ymd));

    _doneTodayIds
      ..clear()
      ..addAll(widget.logic.nowDoneSet(ymd));
  }

  void _ensureDay(String ymd) {
    if (_skippedYmd == null) {
      _skippedYmd = ymd;
      _loadPersistedForDay(ymd);
      return;
    }
    if (_skippedYmd != ymd) {
      _skippedYmd = ymd;
      _loadPersistedForDay(ymd);
    }
  }

  List<DayPlanItem> _archivedForHabit(DayPlanItem it) {
    final habitId = it.refId;
    if (habitId == null) return const [];

    final list = widget.st.dayPlan.where((a) {
      if (a.kind != PlanKind.action) return false;
      if (a.habitId != habitId) return false;
      return a.archived == true;
    }).toList();

    list.sort((a, b) => a.title.compareTo(b.title));
    return list;
  }

  Widget _archivesSection(DayPlanItem it) {
    final items = _archivedForHabit(it);
    if (items.isEmpty) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: () => setState(() => _showArchives = !_showArchives),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      "Archives (${items.length})",
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  Icon(
                    _showArchives ? Icons.expand_less : Icons.expand_more,
                    size: 20,
                  ),
                ],
              ),
            ),
            if (_showArchives) ...[
              const SizedBox(height: 8),
              for (final a in items)
                Row(
                  children: [
                    const Icon(Icons.archive_outlined, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        a.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    TextButton(
                      onPressed: () => _reactivateArchivedAction(a),
                      child: const Text("Activer"),
                    ),
                  ],
                ),
            ],
          ],
        ),
      ),
    );
  }

  void _reactivateArchivedAction(DayPlanItem a) {
    setState(() {
      a.archived = false;
      a.done = false;
      a.toPlan = true;
/*       _showGlobalArchives = false;
      _showArchives = false; */
    });
    widget.logic.onChange();
  }

  List<DayPlanItem> _archivedGlobal() {
    final list = widget.st.dayPlan.where((a) {
      if (a.kind != PlanKind.action) return false;
      if (a.archived != true) return false;
      return a.habitId == null; // ✅ global
    }).toList();

    list.sort((a, b) => a.title.compareTo(b.title));
    return list;
  }

  Widget _archivesGlobalSection() {
    final items = _archivedGlobal();
    if (items.isEmpty) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: () =>
                  setState(() => _showGlobalArchives = !_showGlobalArchives),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      "Archives globales (${items.length})",
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  Icon(
                    _showGlobalArchives ? Icons.expand_less : Icons.expand_more,
                    size: 20,
                  ),
                ],
              ),
            ),
            if (_showGlobalArchives) ...[
              const SizedBox(height: 8),
              for (final a in items)
                Row(
                  children: [
                    const Icon(Icons.history, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        a.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    TextButton(
                      onPressed: () => _reactivateArchivedAction(a),
                      child: const Text("Activer"),
                    ),
                  ],
                ),
            ],
          ],
        ),
      ),
    );
  }

  List<DayPlanItem> _actionsToPlanForHabit(DayPlanItem it) {
    final habitId = it.refId;
    if (habitId == null) return const [];

    final list = widget.st.dayPlan.where((a) {
      if (a.kind != PlanKind.action) return false;

      // ✅ À prévoir = pas fait, pas archivé, et toPlan=true
      if (a.done) return false;
      if (a.archived == true) return false;
      if (a.toPlan != true) return false;

      return a.habitId == habitId;
    }).toList();

    list.sort((a, b) {
      final c = a.yyyymmdd.compareTo(b.yyyymmdd);
      if (c != 0) return c;
      return a.order.compareTo(b.order);
    });

    return list;
  }

  Widget _toPlanSection(DayPlanItem it) {
    final habitId = it.refId;
    if (habitId == null) return const SizedBox.shrink();

    final actions = _actionsToPlanForHabit(it);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "À prévoir",
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
            ),
            const SizedBox(height: 6),
            if (actions.isEmpty)
              Text(
                "Rien à prévoir pour l'instant.",
                style: TextStyle(
                  color:
                      Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                ),
              )
            else
              for (final a in actions)
                Row(
                  children: [
                    const Icon(Icons.push_pin_outlined, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        a.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    IconButton(
                      tooltip: "Marquer fait",
                      icon: const Icon(Icons.check, size: 18),
                      onPressed: () {
                        widget.logic.archiveAction(a);
                        setState(() {});
                      },
                    ),
                  ],
                ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                tooltip: "Ajouter à prévoir",
                icon: const Icon(Icons.add),
                onPressed: () async {
                  final txt = await _promptText(title: "Ajouter à prévoir");
                  if (txt == null || txt.trim().isEmpty) return;

                  final habitAct = widget.st.activities.firstWhere(
                    (a) => a.id == habitId,
                    orElse: () => Activity(
                      domainId: it.domainId ?? "",
                      name: "Routine",
                      type: 'habit',
                    ),
                  );

                  await widget.logic.addToPlanAction(
                    ymd: yyyymmdd(DateTime(
                        widget.day.year, widget.day.month, widget.day.day)),
                    title: txt.trim(),
                    habitId: habitId, // ✅ liée à la routine
                    domainId: habitAct.domainId, // ✅ domaine
                  );

                  if (!mounted) return;
                  setState(() {});
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  String freqLabelForActivity(Activity act) {
    final f = widget.logic.effectiveHabitFreq(act);
    return freqLabel(f);
  }

  String freqLabel(HabitFreq f) {
    switch (f) {
      case HabitFreq.daily:
        return "jour";
      case HabitFreq.weekly:
        return "semaine";
      case HabitFreq.monthly:
        return "mois";
    }
  }

  Future<void> _renameRoutine(Activity act) async {
    // ✅ simple guard
    final current = act.name.trim();
    final txt = await _promptText(
      title: "Renommer la routine",
      initial: current,
    );

    final next = (txt ?? "").trim();
    if (next.isEmpty || next == current) return;

    setState(() {
      act.name = next;
    });

    widget.logic.onChange();

    // optionnel: petit feedback
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Routine renommée"),
          duration: Duration(milliseconds: 900),
        ),
      );
    });
  }

  Widget autoManualBadge(
      {required Activity act,
      required VoidCallback onToggle,
      required VoidCallback onLongPress}) {
    final isAuto = act.autoTune && !act.manualTarget;

    final color = isAuto
        ? Colors.cyanAccent.withOpacity(0.85)
        : Colors.white.withOpacity(0.75);

    final bg = isAuto
        ? Colors.cyanAccent.withOpacity(0.15)
        : Colors.white.withOpacity(0.08);

    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onToggle,
      onLongPress: onLongPress,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isAuto ? Icons.trending_up : Icons.horizontal_rule,
              size: 14,
              color: color,
            ),
            const SizedBox(width: 4),
            Text(
              isAuto ? "A" : "M",
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBlockChipBar(BuildContext context, String ymd) {
    final logic = widget.logic;
    final runningAct = logic.runningActivity();

    bool blockHasActivityItem(DayBlock b) {
      if (runningAct == null) return true;
      return logic.blockItemsForDay(b.id, ymd).any((it) {
        final actId = it.kind == PlanKind.habit
            ? (() {
                final habitId = (it.refId ?? it.habitId ?? '').trim();
                if (habitId.isEmpty) return null;
                final routineAct = widget.st.activities
                    .firstWhereOrNull((a) => a.id == habitId);
                final linked = (routineAct?.linkedActivityId ?? '').trim();
                return linked.isNotEmpty ? linked : it.activityId;
              })()
            : (it.activityId ?? '').trim().isEmpty
                ? null
                : it.activityId;
        return actId == runningAct.id;
      });
    }

    final sortedBlocks = ([...logic.state.blocks]
          ..sort((a, b) => a.order.compareTo(b.order)))
        .where((b) =>
            !logic.isBlockDisabledForDay(b.id, ymd) &&
            blockHasActivityItem(b))
        .toList();
    if (sortedBlocks.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: sortedBlocks.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final b = sortedBlocks[i];
          final isActive = _activeBlockId == b.id;
          final isComplete = logic.isBlockComplete(b.id, ymd);
          final label =
              '${b.emoji != null ? "${b.emoji} " : ""}${b.name}';

          return FilterChip(
            selected: isActive,
            label: Text(label,
                style: TextStyle(
                    fontWeight:
                        isActive ? FontWeight.w700 : FontWeight.w500)),
            avatar: isComplete
                ? const Icon(Icons.check_circle, size: 14)
                : null,
            showCheckmark: false,
            onSelected: (_) {
              setState(() {
                _activeBlockId = isActive ? null : b.id;
              });
            },
          );
        },
      ),
    );
  }

  Widget _blockCompleteView(BuildContext context, String ymd) {
    final nextBlock = widget.logic.nextIncompleteBlock(ymd);
    final cs = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline,
                size: 56, color: cs.primary),
            const SizedBox(height: 16),
            const Text(
              'Bloc terminé !',
              style:
                  TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 20),
            if (nextBlock != null)
              FilledButton.icon(
                icon: const Icon(Icons.arrow_forward),
                label: Text(
                    '${nextBlock.emoji != null ? "${nextBlock.emoji} " : ""}${nextBlock.name}'),
                onPressed: () =>
                    setState(() => _activeBlockId = nextBlock.id),
              ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () =>
                  setState(() => _activeBlockId = null),
              child: const Text('Vue sans bloc'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: widget.logic.rev, // ✅ rebuild quand reorder/onChange
      builder: (context, _, __) {
        final ymd = yyyymmdd(
          DateTime(widget.day.year, widget.day.month, widget.day.day),
        );

        _ensureDay(ymd);

        final logic = widget.logic;
        final sortedBlocks = [...logic.state.blocks]
          ..sort((a, b) => a.order.compareTo(b.order));

        // Auto-détection uniquement si aucun bloc actif :
        // timer en cours → bloc lié en priorité, sinon prochain bloc incomplet
        if (_activeBlockId == null && sortedBlocks.isNotEmpty) {
          final fromTimer = logic.blockForRunningActivity(ymd);
          final next = fromTimer ?? logic.nextIncompleteBlock(ymd);
          if (next != null) _activeBlockId = next.id;
        }

        // Vérifie que le bloc actif existe encore et n'est pas désactivé
        if (_activeBlockId != null &&
            (!logic.state.blocks.any((b) => b.id == _activeBlockId) ||
                logic.isBlockDisabledForDay(_activeBlockId!, ymd))) {
          _activeBlockId = null;
        }

        Widget content;

        if (_activeBlockId != null) {
          // Mode séquence bloc
          final runningAct = logic.runningActivity();

          // Filtre par activité en cours si un timer est actif
          bool passesActivityFilter(DayPlanItem it) {
            if (runningAct == null) return true;
            final actId = it.kind == PlanKind.habit
                ? (() {
                    final habitId = (it.refId ?? it.habitId ?? '').trim();
                    if (habitId.isEmpty) return null;
                    final routineAct = widget.st.activities
                        .firstWhereOrNull((a) => a.id == habitId);
                    final linked =
                        (routineAct?.linkedActivityId ?? '').trim();
                    return linked.isNotEmpty ? linked : it.activityId;
                  })()
                : (it.activityId ?? '').trim().isEmpty
                    ? null
                    : it.activityId;
            return actId == runningAct.id;
          }

          final allBlockItems = logic.blockItemsForDay(_activeBlockId!, ymd)
              .where(passesActivityFilter)
              .toList();

          final blockItems = allBlockItems
              .where((it) => !it.done && !_skippedIds.contains(it.id))
              .toList();

          if (blockItems.isEmpty) {
            content = _blockCompleteView(context, ymd);
          } else {
            final chosen = blockItems.first;
            final doneInBlock =
                allBlockItems.where((it) => it.done).length;
            final totalInBlock = allBlockItems.length;
            final activeBlock = logic.state.blocks
                .firstWhere((b) => b.id == _activeBlockId);
            final blockLabel =
                '${activeBlock.emoji != null ? "${activeBlock.emoji} " : ""}${activeBlock.name}';

            if (chosen.kind == PlanKind.action) {
              content = Padding(
                padding:
                    const EdgeInsets.fromLTRB(16, 8, 16, 120),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '$blockLabel · $doneInBlock/$totalInBlock',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context)
                                  .colorScheme
                                  .primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _nowActionCard(
                        context, chosen, _skippedIds.length,
                        totalInBlock),
                  ],
                ),
              );
            } else if (chosen.kind == PlanKind.habit) {
              content = Padding(
                padding:
                    const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '$blockLabel · $doneInBlock/$totalInBlock',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context)
                            .colorScheme
                            .primary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                        child: _nowHabitCard(context, chosen)),
                  ],
                ),
              );
            } else {
              content = _blockCompleteView(context, ymd);
            }
          }
        } else {
          // Mode libre (sans bloc)
          final todo = widget.items
              .where((it) =>
                  (widget.logic.effectiveBlockId(it) ?? '').isEmpty)
              .toList();

          DayPlanItem? focusedAction;
          for (final x in todo) {
            if (x.kind == PlanKind.action &&
                x.isNowFocus == true &&
                !x.done) {
              focusedAction = x;
              break;
            }
          }

          final chosen =
              focusedAction ?? (todo.isNotEmpty ? todo.first : null);
          final bool isPinned =
              (focusedAction != null && identical(chosen, focusedAction));

          void unpinNow() {
            final a = focusedAction;
            if (a == null) return;
            setState(() => a.isNowFocus = false);
            widget.logic.onChange();
          }

          if (chosen == null) {
            content = _allDoneView(context);
          } else if (chosen.kind == PlanKind.action) {
            content = Padding(
              padding:
                  const EdgeInsets.fromLTRB(16, 16, 16, 120),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (isPinned) ...[
                    Row(
                      children: [
                        IconButton(
                          tooltip: 'Désépingler',
                          icon: const Icon(Icons.arrow_back),
                          onPressed: unpinNow,
                        ),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Action épinglée',
                            style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 16),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                  _nowActionCard(
                      context, chosen, _skippedIds.length,
                      todo.length),
                ],
              ),
            );
          } else if (chosen.kind == PlanKind.habit) {
            content = Padding(
              padding:
                  const EdgeInsets.fromLTRB(16, 16, 16, 16),
              child: _nowHabitCard(context, chosen),
            );
          } else {
            content = _allDoneView(context);
          }
        }

        return Column(
          children: [
            if (sortedBlocks.isNotEmpty) ...[
              const SizedBox(height: 8),
              _buildBlockChipBar(context, ymd),
              const SizedBox(height: 4),
            ],
            Expanded(child: content),
          ],
        );
      },
    );
  }

  Widget _activitiesSuggestionForCurrent(DayPlanItem it) {
    // On ne propose que si l'item actuel est une routine
    if (it.kind != PlanKind.habit) return const SizedBox.shrink();

    // Domain du plan item (déjà stocké chez toi dans DayPlanItem)
    final domId = it.domainId;
    if (domId == null) return const SizedBox.shrink();

    // Activités time du domaine
    final acts = widget.st.activities
        .where((a) => !a.isHabit && a.domainId == domId)
        .toList();

    if (acts.isEmpty) return const SizedBox.shrink();

    // (option) éviter de proposer l'activité déjà en cours
    final running = widget.logic.runningActivity();
    final filtered =
        running == null ? acts : acts.where((a) => a.id != running.id).toList();

    if (filtered.isEmpty) return const SizedBox.shrink();

    // Nom du domaine
    final domName = widget.st.domains
        .firstWhere((d) => d.id == domId,
            orElse: () => Domain(id: domId, name: "Domaine"))
        .name;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Activités • $domName",
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color:
                    Theme.of(context).colorScheme.onSurface.withOpacity(0.75),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final a in filtered)
                  FilledButton.tonalIcon(
                    onPressed: () {
                      widget.logic
                          .start(a.id); // ✅ adapte le nom exact si besoin
                      setState(() {
                        // Optionnel: on peut locker l'item actuel pour rester dessus
                        // (et l'utilisateur clique ensuite "Fait" => assoc)
                      });
                    },
                    icon: const Icon(Icons.play_arrow, size: 18),
                    label: Text(a.name),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

/*   void _onSkip() {
    setState(() {
      if (_lockedPlanId != null) _skippedIds.add(_lockedPlanId!);
      _lockedPlanId = null;
    });
    _persistNowSets();
  } */

  Widget _allDoneView(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("✨ Tout est fait",
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            Text(
              "Tu peux lancer une activité ou ajouter une routine dans l'onglet À faire.",
              textAlign: TextAlign.center,
              style: TextStyle(
                color:
                    Theme.of(context).colorScheme.onSurface.withOpacity(0.75),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionSheetResult {
  final String? rename;
  final bool? unlink;
  final String? newActivityId;
  final String? newDomainId;
  final bool? markDone;
  final bool? delete;
  final bool? deactivate;

  _ActionSheetResult({
    this.rename,
    this.unlink,
    this.newActivityId,
    this.newDomainId,
    this.markDone,
    this.delete,
    this.deactivate,
  });
}
