import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:intl/intl.dart';

class GoalsView extends StatefulWidget {
  final AppLogic logic;
  final AppState state;

  const GoalsView({super.key, required this.logic, required this.state});

  @override
  State<GoalsView> createState() => _GoalsViewState();
}

class _GoalsViewState extends State<GoalsView> {
  bool _showDone = false;

  AppLogic get logic => widget.logic;
  AppState get st => widget.state;

  @override
  Widget build(BuildContext context) {
    final activeGoals =
        st.goals.where((g) => g.status == 'active').toList();
    final doneGoals = st.goals
        .where((g) => g.status == 'done' || g.status == 'archived')
        .toList()
      ..sort((a, b) =>
          (b.doneAt ?? b.createdAt).compareTo(a.doneAt ?? a.createdAt));

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          const SliverAppBar(
            title: Text('Objectifs'),
            floating: true,
            snap: true,
          ),
          if (activeGoals.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Text(
                  'Aucun objectif actif.\nAppuie sur + pour en ajouter un.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            )
          else
            for (final domain in st.domains)
              ..._buildDomainSection(
                context,
                domain,
                activeGoals
                    .where((g) => g.domainId == domain.id)
                    .toList(),
              ),
          if (doneGoals.isNotEmpty)
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(height: 32),
                  InkWell(
                    onTap: () =>
                        setState(() => _showDone = !_showDone),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      child: Row(
                        children: [
                          Icon(
                            _showDone
                                ? Icons.expand_less
                                : Icons.expand_more,
                            size: 18,
                            color: Colors.grey,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Terminés / Archivés (${doneGoals.length})',
                            style: const TextStyle(
                                color: Colors.grey, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_showDone)
                    for (final g in doneGoals)
                      GoalCard(
                        goal: g,
                        muted: true,
                        onTap: null,
                        onArchive: null,
                      ),
                  const SizedBox(height: 80),
                ],
              ),
            )
          else
            const SliverToBoxAdapter(child: SizedBox(height: 80)),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _addGoalDialog(context),
        tooltip: 'Nouvel objectif',
        child: const Icon(Icons.add),
      ),
    );
  }

  List<Widget> _buildDomainSection(
      BuildContext context, Domain domain, List<Goal> goals) {
    if (goals.isEmpty) return [];
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(
            domain.name.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
      ),
      SliverList(
        delegate: SliverChildBuilderDelegate(
          (ctx, i) => GoalCard(
            goal: goals[i],
            muted: false,
            logic: logic,
            onTap: () => _openGoalSheet(context, goals[i]),
            onArchive: () => _confirmArchive(context, goals[i]),
          ),
          childCount: goals.length,
        ),
      ),
    ];
  }

  void _openGoalSheet(BuildContext context, Goal goal) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => GoalDetailSheet(
        goal: goal,
        logic: logic,
        state: st,
        onChanged: () => setState(() {}),
      ),
    );
  }

  Future<void> _addGoalDialog(BuildContext context) async {
    String? selectedDomainId =
        st.domains.isNotEmpty ? st.domains.first.id : null;
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
                  decoration:
                      const InputDecoration(labelText: 'Domaine'),
                  items: st.domains
                      .map((d) => DropdownMenuItem(
                            value: d.id,
                            child: Text(d.name),
                          ))
                      .toList(),
                  onChanged: (v) => setS(() => selectedDomainId = v),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: titleCtrl,
                  autofocus: true,
                  decoration:
                      const InputDecoration(labelText: 'Objectif'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: actionCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Première action (optionnel)'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Annuler')),
            FilledButton(
              onPressed: () {
                final title = titleCtrl.text.trim();
                if (title.isEmpty || selectedDomainId == null) return;
                logic.createGoal(
                  domainId: selectedDomainId!,
                  title: title,
                  firstAction: actionCtrl.text.trim().isEmpty
                      ? null
                      : actionCtrl.text.trim(),
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

  Future<void> _confirmArchive(BuildContext context, Goal goal) async {
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
            child: const Text('Archiver'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      logic.archiveGoal(goal.id);
      setState(() {});
    }
  }
}

// ── Sheet objectifs d'un domaine ─────────────────────────────────────────────

class DomainGoalsSheet extends StatefulWidget {
  final Domain domain;
  final AppLogic logic;
  final AppState state;

  const DomainGoalsSheet({
    super.key,
    required this.domain,
    required this.logic,
    required this.state,
  });

  @override
  State<DomainGoalsSheet> createState() => _DomainGoalsSheetState();
}

class _DomainGoalsSheetState extends State<DomainGoalsSheet> {
  AppLogic get logic => widget.logic;
  AppState get st => widget.state;
  Domain get domain => widget.domain;

  @override
  Widget build(BuildContext context) {
    final activeGoals = st.goals
        .where((g) => g.domainId == domain.id && g.status == 'active')
        .toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Objectifs · ${domain.name}',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Ajouter'),
                  onPressed: () => _addGoalDialog(context),
                ),
              ],
            ),
          ),
          if (activeGoals.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Text(
                'Aucun objectif actif pour ce domaine.',
                style: TextStyle(color: Colors.grey),
              ),
            )
          else
            ...activeGoals.map((g) => GoalCard(
                  goal: g,
                  muted: false,
                  logic: logic,
                  onTap: () => _openGoalSheet(context, g),
                  onArchive: () => _confirmArchive(context, g),
                )),
        ],
      ),
    );
  }

  void _openGoalSheet(BuildContext context, Goal goal) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => GoalDetailSheet(
        goal: goal,
        logic: logic,
        state: st,
        onChanged: () => setState(() {}),
      ),
    );
  }

  Future<void> _addGoalDialog(BuildContext context) async {
    final titleCtrl = TextEditingController();
    final actionCtrl = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Nouvel objectif · ${domain.name}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleCtrl,
                autofocus: true,
                decoration:
                    const InputDecoration(labelText: 'Objectif'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: actionCtrl,
                decoration: const InputDecoration(
                    labelText: 'Première action (optionnel)'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler')),
          FilledButton(
            onPressed: () {
              final title = titleCtrl.text.trim();
              if (title.isEmpty) return;
              logic.createGoal(
                domainId: domain.id,
                title: title,
                firstAction: actionCtrl.text.trim().isEmpty
                    ? null
                    : actionCtrl.text.trim(),
              );
              setState(() {});
              Navigator.pop(ctx);
            },
            child: const Text('Ajouter'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmArchive(BuildContext context, Goal goal) async {
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
            child: const Text('Archiver'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      logic.archiveGoal(goal.id);
      setState(() {});
    }
  }
}

// ── Card résumé ──────────────────────────────────────────────────────────────

class GoalCard extends StatelessWidget {
  final Goal goal;
  final bool muted;
  final VoidCallback? onTap;
  final VoidCallback? onArchive;
  final AppLogic? logic;

  const GoalCard({
    super.key,
    required this.goal,
    required this.muted,
    required this.onTap,
    required this.onArchive,
    this.logic,
  });

  @override
  Widget build(BuildContext context) {
    final isDone =
        goal.status == 'done' || goal.status == 'archived';
    final theme = Theme.of(context);
    final total = goal.stepsTotal;
    final done = goal.stepsDone;
    final progress =
        total > 0 ? (done / total).clamp(0.0, 1.0) : null;
    final next = goal.nextAction;

    return Dismissible(
      key: ValueKey(goal.id),
      direction: onArchive != null
          ? DismissDirection.endToStart
          : DismissDirection.none,
      confirmDismiss: (_) async {
        onArchive?.call();
        return false;
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: Colors.orange.shade100,
        child:
            const Icon(Icons.archive_outlined, color: Colors.orange),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      goal.title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        decoration:
                            isDone ? TextDecoration.lineThrough : null,
                        color: muted ? Colors.grey : null,
                      ),
                    ),
                  ),
                  if (total > 0)
                    Text(
                      '$done/$total',
                      style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade500),
                    ),
                  const SizedBox(width: 4),
                  Icon(Icons.chevron_right,
                      size: 18, color: Colors.grey.shade400),
                ],
              ),
              if (progress != null) ...[
                const SizedBox(height: 5),
                LinearProgressIndicator(
                  value: progress,
                  minHeight: 3,
                  borderRadius: BorderRadius.circular(2),
                  backgroundColor: Colors.grey.shade200,
                  color: theme.colorScheme.primary,
                ),
              ],
              if (next != null) ...[
                const SizedBox(height: 5),
                Row(
                  children: [
                    Icon(Icons.arrow_right,
                        size: 16,
                        color: theme.colorScheme.secondary),
                    const SizedBox(width: 2),
                    Expanded(
                      child: Text(
                        next.title,
                        style: TextStyle(
                          fontSize: 13,
                          color: muted
                              ? Colors.grey
                              : theme.colorScheme.secondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ] else if (!isDone && total == 0) ...[
                const SizedBox(height: 4),
                Text(
                  'Ajouter des actions…',
                  style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade400,
                      fontStyle: FontStyle.italic),
                ),
              ],
              if (logic != null && goal.linkedHabitIds.isNotEmpty && !isDone) ...[
                const SizedBox(height: 6),
                _RoutineChipsRow(goal: goal, logic: logic!),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _RoutineChipsRow extends StatelessWidget {
  final Goal goal;
  final AppLogic logic;

  const _RoutineChipsRow({required this.goal, required this.logic});

  @override
  Widget build(BuildContext context) {
    final habits = logic.state.activities
        .where((a) => a.isHabit && goal.linkedHabitIds.contains(a.id))
        .toList();
    if (habits.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: habits.map((h) {
        final reached = logic.habitReached(h);
        final color = reached ? Colors.green : Colors.grey.shade400;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 4),
            Text(
              h.name,
              style: TextStyle(fontSize: 11, color: color),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        );
      }).toList(),
    );
  }
}

// ── Sheet de détail ──────────────────────────────────────────────────────────

class GoalDetailSheet extends StatefulWidget {
  final Goal goal;
  final AppLogic logic;
  final AppState state;
  final VoidCallback onChanged;

  const GoalDetailSheet({
    required this.goal,
    required this.logic,
    required this.state,
    required this.onChanged,
  });

  @override
  State<GoalDetailSheet> createState() => GoalDetailSheetState();
}

class GoalDetailSheetState extends State<GoalDetailSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  final _fmt = DateFormat('d MMM', 'fr');

  Goal get goal => widget.goal;
  AppLogic get logic => widget.logic;
  AppState get st => widget.state;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = goal.stepsTotal;
    final done = goal.stepsDone;
    final progress =
        total > 0 ? (done / total).clamp(0.0, 1.0) : null;

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scroll) => Column(
        children: [
          // En-tête
          Padding(
            padding:
                const EdgeInsets.fromLTRB(20, 4, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    goal.title,
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  onPressed: () => _editTitle(context),
                ),
                IconButton(
                  icon: const Icon(Icons.check_circle_outline, size: 20),
                  tooltip: 'Marquer terminé',
                  onPressed: () {
                    logic.markGoalDone(goal.id);
                    widget.onChanged();
                    Navigator.pop(ctx);
                  },
                ),
              ],
            ),
          ),
          if (progress != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              child: Row(
                children: [
                  Expanded(
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 4,
                      borderRadius: BorderRadius.circular(2),
                      backgroundColor: Colors.grey.shade200,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '$done/$total',
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey.shade500),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          TabBar(
            controller: _tabs,
            tabs: const [
              Tab(text: 'Actions'),
              Tab(text: 'Associations'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _buildActionsTab(ctx, scroll),
                _buildAssocTab(ctx),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Onglet Actions ─────────────────────────────────────────────────────

  Widget _buildActionsTab(BuildContext ctx, ScrollController scroll) {
    final pending =
        goal.actions.where((a) => !a.done).toList();
    final done = goal.actions.where((a) => a.done).toList()
      ..sort((a, b) =>
          (b.doneAt ?? DateTime(0)).compareTo(a.doneAt ?? DateTime(0)));

    return ListView(
      controller: scroll,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        // Liste réordrable des actions en attente
        if (pending.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'Aucune action en attente.',
              style: TextStyle(
                  color: Colors.grey.shade400,
                  fontStyle: FontStyle.italic),
            ),
          )
        else
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: pending.length,
            onReorder: (oldIdx, newIdx) {
              // Trouver les vrais index dans goal.actions
              final oldReal = goal.actions.indexOf(pending[oldIdx]);
              int newReal;
              if (newIdx >= pending.length) {
                newReal = goal.actions.indexOf(pending.last) + 1;
              } else {
                newReal = goal.actions.indexOf(pending[newIdx]);
              }
              logic.reorderGoalActions(goal.id, oldReal, newReal);
              setState(() {});
              widget.onChanged();
            },
            itemBuilder: (ctx, i) {
              final a = pending[i];
              final isFirst = i == 0;
              return _ActionTile(
                key: ValueKey(a.id),
                action: a,
                isFirst: isFirst,
                alreadyInToday: st.dayPlan
                    .any((it) => it.goalActionId == a.id),
                onToggle: (val) {
                  logic.toggleGoalAction(goal.id, a.id, val);
                  setState(() {});
                  widget.onChanged();
                },
                onAddToToday: () {
                  logic.addGoalActionToToday(goal.id, a.id);
                  setState(() {});
                  widget.onChanged();
                },
                onRemoveFromToday: () {
                  logic.removeGoalActionFromToday(a.id);
                  setState(() {});
                  widget.onChanged();
                },
                onDelete: () {
                  logic.deleteGoalAction(goal.id, a.id);
                  setState(() {});
                  widget.onChanged();
                },
              );
            },
          ),

        // Bouton ajouter
        TextButton.icon(
          onPressed: () => _addAction(ctx),
          icon: const Icon(Icons.add, size: 16),
          label: const Text('Ajouter une action'),
        ),

        // Actions faites
        if (done.isNotEmpty) ...[
          const SizedBox(height: 8),
          const Divider(),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              'Réalisées (${done.length})',
              style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade500,
                  fontWeight: FontWeight.w600),
            ),
          ),
          for (final a in done)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  const Icon(Icons.check, size: 14, color: Colors.green),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(a.title,
                        style: const TextStyle(
                            fontSize: 13,
                            decoration: TextDecoration.lineThrough,
                            color: Colors.grey)),
                  ),
                  if (a.doneAt != null)
                    Text(
                      _fmt.format(a.doneAt!),
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey.shade400),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 40),
        ] else
          const SizedBox(height: 40),
      ],
    );
  }

  // ── Onglet Associations ────────────────────────────────────────────────

  Widget _buildAssocTab(BuildContext ctx) {
    final activities =
        st.activities.where((a) => !a.isHabit && a.domainId == goal.domainId).toList();
    final habits = st.activities
        .where((a) => a.isHabit && a.domainId == goal.domainId)
        .toList();

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      children: [
        _SectionLabel('Domaine'),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          value: goal.domainId,
          decoration: const InputDecoration(isDense: true),
          items: st.domains
              .map((d) => DropdownMenuItem(value: d.id, child: Text(d.name)))
              .toList(),
          onChanged: (v) {
            if (v == null || v == goal.domainId) return;
            logic.setGoalDomain(goal.id, v);
            setState(() {});
            widget.onChanged();
          },
        ),
        const SizedBox(height: 20),
        _SectionLabel('Activité liée (temps)'),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          value: goal.activityId,
          decoration:
              const InputDecoration(hintText: 'Aucune', isDense: true),
          items: [
            const DropdownMenuItem(value: null, child: Text('Aucune')),
            ...activities.map((a) =>
                DropdownMenuItem(value: a.id, child: Text(a.name))),
          ],
          onChanged: (v) {
            logic.setGoalLinkedActivity(goal.id, v);
            setState(() {});
            widget.onChanged();
          },
        ),
        if (goal.activityId != null) ...[
          const SizedBox(height: 6),
          _WeeklyActivityChip(
              logic: logic, activityId: goal.activityId!),
        ],
        const SizedBox(height: 20),
        _SectionLabel('Routines liées'),
        const SizedBox(height: 6),
        if (habits.isEmpty)
          Text('Aucune routine dans ce domaine.',
              style: TextStyle(
                  color: Colors.grey.shade400,
                  fontStyle: FontStyle.italic,
                  fontSize: 13))
        else
          for (final h in habits) ...[
            () {
              final done = logic.activeHabitDone(h);
              final target = logic.activeHabitTarget(h);
              final reached = target > 0 && done >= target;
              final progressText = target > 0 ? '$done / $target' : null;
              final color = reached
                  ? Colors.green
                  : (done > 0 ? Colors.orange : Colors.grey.shade400);
              return CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(h.name, style: const TextStyle(fontSize: 14)),
                subtitle: progressText == null
                    ? null
                    : Row(
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                                color: color, shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            reached ? 'Atteinte · $progressText' : progressText,
                            style: TextStyle(fontSize: 11, color: color),
                          ),
                        ],
                      ),
                value: goal.linkedHabitIds.contains(h.id),
                onChanged: (_) {
                  logic.toggleGoalLinkedHabit(goal.id, h.id);
                  setState(() {});
                  widget.onChanged();
                },
              );
            }(),
          ],
        const SizedBox(height: 40),
      ],
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────

  Future<void> _addAction(BuildContext context) async {
    final ctrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nouvelle action'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Action'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler')),
          FilledButton(
            onPressed: () {
              final t = ctrl.text.trim();
              if (t.isEmpty) return;
              logic.addGoalAction(goal.id, t);
              setState(() {});
              widget.onChanged();
              Navigator.pop(ctx);
            },
            child: const Text('Ajouter'),
          ),
        ],
      ),
    );
  }

  Future<void> _editTitle(BuildContext context) async {
    final ctrl = TextEditingController(text: goal.title);
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Renommer'),
        content: TextField(
            controller: ctrl,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Objectif')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler')),
          FilledButton(
            onPressed: () {
              final t = ctrl.text.trim();
              if (t.isNotEmpty) {
                goal.title = t;
                logic.onChange();
              }
              setState(() {});
              widget.onChanged();
              Navigator.pop(ctx);
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}

// ── Tile d'action ─────────────────────────────────────────────────────────────

class _ActionTile extends StatelessWidget {
  final GoalAction action;
  final bool isFirst;
  final bool alreadyInToday;
  final void Function(bool) onToggle;
  final VoidCallback onAddToToday;
  final VoidCallback onRemoveFromToday;
  final VoidCallback onDelete;

  const _ActionTile({
    super.key,
    required this.action,
    required this.isFirst,
    required this.alreadyInToday,
    required this.onToggle,
    required this.onAddToToday,
    required this.onRemoveFromToday,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Checkbox(
          value: action.done,
          onChanged: (v) => onToggle(v ?? false),
        ),
        Expanded(
          child: Text(
            action.title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: isFirst ? FontWeight.w500 : FontWeight.normal,
            ),
          ),
        ),
        if (!alreadyInToday)
          IconButton(
            icon: Icon(Icons.today_outlined,
                size: 18, color: theme.colorScheme.secondary),
            tooltip: 'Planifier aujourd\'hui',
            onPressed: onAddToToday,
          )
        else
          IconButton(
            icon: Icon(Icons.today, size: 18, color: theme.colorScheme.primary),
            tooltip: 'Retirer du plan du jour',
            onPressed: onRemoveFromToday,
          ),
        IconButton(
          icon: Icon(Icons.delete_outline,
              size: 18, color: Colors.grey.shade400),
          onPressed: onDelete,
        ),
        ReorderableDragStartListener(
          index: 0,
          child: Icon(Icons.drag_handle,
              size: 18, color: Colors.grey.shade400),
        ),
      ],
    );
  }
}

// ── Chip progression activité ─────────────────────────────────────────────────

class _WeeklyActivityChip extends StatelessWidget {
  final AppLogic logic;
  final String activityId;

  const _WeeklyActivityChip(
      {required this.logic, required this.activityId});

  @override
  Widget build(BuildContext context) {
    final w = logic.timeSliding(activityId, 7);
    final label =
        '${w.doneMin} min cette semaine${w.targetMin > 0 ? ' / ${w.targetMin} min' : ''}';
    return Chip(
      avatar: const Icon(Icons.timer_outlined, size: 14),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Colors.grey.shade600,
          letterSpacing: 0.3,
        ),
      );
}
