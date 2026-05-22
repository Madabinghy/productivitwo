import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/domain_colors.dart';

class FocusView extends StatefulWidget {
  final AppLogic logic;
  final AppState state;
  final Project? focusProject;
  final ProjectTask? focusTask;
  final VoidCallback onGoToProjects;
  final void Function(Activity activity, Project? project, ProjectTask? task)
      onStartTimer;
  final VoidCallback onStopTimer;
  final void Function(Project project, ProjectTask task) onClearFocusTask;

  const FocusView({
    super.key,
    required this.logic,
    required this.state,
    required this.onGoToProjects,
    required this.onStartTimer,
    required this.onStopTimer,
    required this.onClearFocusTask,
    this.focusProject,
    this.focusTask,
  });

  @override
  State<FocusView> createState() => _FocusViewState();
}

class _FocusViewState extends State<FocusView> {
  Timer? _ticker;
  int _elapsed = 0; // secondes depuis début de session

  AppLogic get logic => widget.logic;
  AppState get st => widget.state;

  @override
  void initState() {
    super.initState();
    _startTicker();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsed++);
    });
  }

  // ── Données session en cours ─────────────────────────────────────────────────

  Session? get _runningSession {
    Session? last;
    for (final s in st.sessions) {
      if (s.endAt != null) continue;
      if (last == null || s.startAt.isAfter(last.startAt)) last = s;
    }
    return last;
  }

  Activity? get _runningActivity => logic.runningActivity();

  Duration get _elapsedDuration {
    final s = _runningSession;
    if (s == null) return Duration.zero;
    return DateTime.now().difference(s.startAt);
  }

  String _fmtDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    if (h > 0) return '${h}h ${m.toString().padLeft(2, '0')}m';
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  // ── Données camembert (sessions du jour) ─────────────────────────────────────

  Map<String, double> _todayMinutesByActivity() {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final result = <String, double>{};
    for (final s in st.sessions) {
      final start = s.startAt.isAfter(todayStart) ? s.startAt : todayStart;
      final end = s.endAt ?? now;
      if (end.isBefore(todayStart)) continue;
      final minutes = end.difference(start).inSeconds / 60.0;
      if (minutes <= 0) continue;
      result[s.activityId] = (result[s.activityId] ?? 0) + minutes;
    }
    return result;
  }

  double _totalTodayMinutes() =>
      _todayMinutesByActivity().values.fold(0.0, (a, b) => a + b);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final running = _runningActivity;

    return running == null ? _buildIdle(context, cs) : _buildActive(context, cs, running);
  }

  // ── État idle ─────────────────────────────────────────────────────────────────

  Widget _buildIdle(BuildContext context, ColorScheme cs) {
    final byActivity = _todayMinutesByActivity();
    final totalMin = _totalTodayMinutes();
    final totalH = totalMin / 60;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Aujourd\'hui',
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: cs.onSurface),
            ),
            Text(
              totalMin < 1
                  ? 'Aucune activité loggée'
                  : '${totalH.toStringAsFixed(1).replaceAll('.', 'h')} loggées',
              style: TextStyle(
                  fontSize: 14, color: cs.onSurface.withOpacity(.45)),
            ),
            const SizedBox(height: 32),

            // Camembert
            if (byActivity.isEmpty)
              _buildNoPieState(cs)
            else
              _buildPieChart(context, cs, byActivity, totalMin),

            const Spacer(),

            OutlinedButton.icon(
              icon: const Icon(Icons.account_tree_outlined, size: 18),
              label: const Text('Voir mes projets'),
              onPressed: widget.onGoToProjects,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoPieState(ColorScheme cs) {
    return Expanded(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.play_circle_outline,
                size: 64, color: cs.onSurface.withOpacity(.15)),
            const SizedBox(height: 16),
            Text(
              'Lance une activité pour commencer',
              style: TextStyle(
                  fontSize: 14, color: cs.onSurface.withOpacity(.35)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPieChart(BuildContext context, ColorScheme cs,
      Map<String, double> byActivity, double totalMin) {
    final activities = st.activeActivities;
    final entries = byActivity.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final sections = entries.map((e) {
      final activity =
          activities.where((a) => a.id == e.key).firstOrNull;
      final color = domainColor(activity?.domainId, st.activeDomains) ??
          cs.primary;
      final pct = e.value / totalMin;
      return PieChartSectionData(
        value: e.value,
        color: color,
        radius: 70,
        showTitle: pct > 0.08,
        title: '${(pct * 100).round()}%',
        titleStyle: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Colors.white),
      );
    }).toList();

    return Expanded(
      child: Column(
        children: [
          SizedBox(
            height: 200,
            child: PieChart(
              PieChartData(
                sections: sections,
                sectionsSpace: 2,
                centerSpaceRadius: 40,
              ),
            ),
          ),
          const SizedBox(height: 20),
          // Légende
          Wrap(
            spacing: 16,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: entries.map((e) {
              final activity =
                  activities.where((a) => a.id == e.key).firstOrNull;
              final color =
                  domainColor(activity?.domainId, st.activeDomains) ??
                      cs.primary;
              final mins = e.value.round();
              final label =
                  '${activity?.name ?? '?'}  ${mins >= 60 ? '${(mins / 60).toStringAsFixed(1)}h' : '${mins}m'}';
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                          color: color, shape: BoxShape.circle)),
                  const SizedBox(width: 5),
                  Text(label,
                      style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurface.withOpacity(.6))),
                ],
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // ── État actif ───────────────────────────────────────────────────────────────

  Widget _buildActive(BuildContext context, ColorScheme cs, Activity running) {
    final domain = st.activeDomains
        .where((d) => d.id == running.domainId)
        .firstOrNull;
    final color = domainColor(running.domainId, st.activeDomains) ?? cs.primary;
    final elapsed = _elapsedDuration;
    final task = widget.focusTask;
    final project = widget.focusProject;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header domaine + activité
            Row(
              children: [
                Container(
                  width: 8, height: 8,
                  decoration:
                      BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Text(
                  '${domain?.name.toUpperCase() ?? ''} · ${running.name}',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                      color: cs.onSurface.withOpacity(.5)),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Carte tâche Gantt (si liée)
            if (task != null && project != null) ...[
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onLongPress: () => widget.onClearFocusTask(project, task),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  decoration: BoxDecoration(
                    color: color.withOpacity(.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: color.withOpacity(.25)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        project.title,
                        style: TextStyle(
                            fontSize: 11,
                            color: color,
                            fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        task.title,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],

            // Timer
            Center(
              child: Text(
                _fmtDuration(elapsed),
                style: TextStyle(
                  fontSize: 52,
                  fontWeight: FontWeight.w200,
                  letterSpacing: 2,
                  color: cs.onSurface,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Center(
              child: FilledButton.icon(
                icon: const Icon(Icons.stop_rounded, size: 20),
                label: const Text('Arrêter'),
                onPressed: widget.onStopTimer,
                style: FilledButton.styleFrom(
                  backgroundColor: cs.error,
                  foregroundColor: cs.onError,
                  minimumSize: const Size(160, 48),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),

            // Sous-actions de la tâche
            if (task != null && task.actions.isNotEmpty) ...[
              const SizedBox(height: 32),
              Text(
                'SOUS-ACTIONS',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2,
                  color: cs.onSurface.withOpacity(.4),
                ),
              ),
              const SizedBox(height: 8),
              ...task.actions.map((a) => _ActionCheckTile(
                    action: a,
                    color: color,
                    onToggle: (value) => _toggleAction(a, value),
                  )),
            ],

            if (task == null) ...[
              const Spacer(),
              Center(
                child: TextButton.icon(
                  icon: const Icon(Icons.account_tree_outlined, size: 16),
                  label: const Text('Lier à une tâche'),
                  onPressed: () => _showTaskPicker(context, running),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _toggleAction(TaskAction action, bool value) async {
    final task = widget.focusTask;
    final project = widget.focusProject;
    if (task == null || project == null) return;
    setState(() {
      action.done = value;
      action.doneAt = value ? DateTime.now() : null;
    });
    final sync = FirestoreSync();
    await sync.saveProjectTasks(project.id, project.tasks);
  }

  // ── Flow démarrage ───────────────────────────────────────────────────────────

  Future<void> _showStartFlow(BuildContext context) async {
    // Étape 1 : choisir une activité
    final activity = await _pickActivity(context, domainId: null);
    if (activity == null || !mounted) return;

    // Étape 2 : choisir une tâche (optionnel)
    final result = await _pickTask(context, activity);
    if (!mounted) return;

    widget.onStartTimer(activity, result?.$1, result?.$2);
  }

  Future<void> _showTaskPicker(BuildContext context, Activity activity) async {
    final result = await _pickTask(context, activity);
    if (result == null || !mounted) return;
    widget.onStartTimer(activity, result.$1, result.$2);
  }

  Future<Activity?> _pickActivity(BuildContext context,
      {String? domainId}) async {
    final activities = domainId != null
        ? st.activeActivities.where((a) => a.domainId == domainId).toList()
        : st.activeActivities.where((a) => !a.isHabit).toList();

    if (activities.isEmpty) return null;
    if (activities.length == 1) return activities.first;

    return showModalBottomSheet<Activity>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: Text('Sur quelle activité ?',
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.bold)),
              ),
              for (final a in activities)
                ListTile(
                  leading: Container(
                    width: 10, height: 10,
                    decoration: BoxDecoration(
                      color: domainColor(a.domainId, st.activeDomains) ??
                          cs.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                  title: Text(a.name),
                  subtitle: Text(
                    st.activeDomains
                            .where((d) => d.id == a.domainId)
                            .firstOrNull
                            ?.name ??
                        '',
                    style: TextStyle(
                        fontSize: 12, color: cs.onSurface.withOpacity(.45)),
                  ),
                  onTap: () => Navigator.pop(ctx, a),
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Future<(Project, ProjectTask)?> _pickTask(
      BuildContext context, Activity activity) async {
    // Tâches actives aujourd'hui du même domaine
    final sync = FirestoreSync();
    List<Project> projects = [];
    try {
      projects = await sync.fetchProjects();
    } catch (_) {}

    final today = DateTime.now();
    final todayD = DateTime(today.year, today.month, today.day);

    final pairs = <(Project, ProjectTask)>[];
    for (final p in projects) {
      if (p.status == 'archived') continue;
      if (p.domainId != activity.domainId) continue;
      for (final t in p.tasks) {
        if (t.status == 'done' || t.status == 'skipped') continue;
        if (t.startDate.isAfter(todayD)) continue;
        pairs.add((p, t));
      }
    }

    if (!mounted) return null;

    return showModalBottomSheet<(Project, ProjectTask)>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Text('Sur quelle tâche ?',
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.bold)),
            ),
            if (pairs.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Text(
                  'Aucune tâche active aujourd\'hui dans ce domaine.',
                  style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(ctx).colorScheme.onSurface.withOpacity(.4)),
                ),
              ),
            for (final pair in pairs)
              ListTile(
                title: Text(pair.$2.title),
                subtitle: Text(pair.$1.title,
                    style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(ctx).colorScheme.onSurface.withOpacity(.45))),
                onTap: () => Navigator.pop(ctx, pair),
              ),
            ListTile(
              leading: const Icon(Icons.skip_next_outlined),
              title: const Text('Passer — sans tâche'),
              onTap: () => Navigator.pop(ctx, null),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ── Tuile sous-action cochable ────────────────────────────────────────────────

class _ActionCheckTile extends StatelessWidget {
  final TaskAction action;
  final Color color;
  final ValueChanged<bool> onToggle;

  const _ActionCheckTile({
    required this.action,
    required this.color,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => onToggle(!action.done),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(
              action.done
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked,
              size: 22,
              color: action.done ? color : cs.onSurface.withOpacity(.3),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                action.title,
                style: TextStyle(
                  fontSize: 14,
                  color: action.done
                      ? cs.onSurface.withOpacity(.35)
                      : cs.onSurface,
                  decoration:
                      action.done ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
