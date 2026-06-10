import 'dart:async';

import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/domain_colors.dart';
import 'package:productivitwo_v1/widgets/daily_schedule_view.dart';

class FocusView extends StatefulWidget {
  final AppLogic logic;
  final AppState state;
  final Project? focusProject;
  final ProjectTask? focusTask;
  final VoidCallback onGoToProjects;
  final void Function(Activity activity, Project? project, ProjectTask? task)
      onStartTimer;
  final VoidCallback onStopTimer;
  // Décompte du minuteur en cours (null = pas de minuteur → chrono normal).
  final DateTime? countdownEndsAt;
  final int? countdownTotalSec;
  // Coupe le minuteur SANS arrêter la session (bascule en chrono).
  final VoidCallback onStopCountdown;
  final void Function(Project project, ProjectTask task) onClearFocusTask;
  final void Function(Project project, ProjectTask task)? onTaskTap;
  // Widget optionnel rendu en tête de l'onglet (ex : bannière Quête du jour).
  final Widget? header;

  const FocusView({
    super.key,
    required this.logic,
    required this.state,
    required this.onGoToProjects,
    required this.onStartTimer,
    required this.onStopTimer,
    required this.onStopCountdown,
    this.countdownEndsAt,
    this.countdownTotalSec,
    required this.onClearFocusTask,
    this.focusProject,
    this.focusTask,
    this.onTaskTap,
    this.header,
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final running = _runningActivity;

    return running == null ? _buildIdle(context, cs) : _buildActive(context, cs, running);
  }

  // ── État idle ─────────────────────────────────────────────────────────────────

  Widget _buildIdle(BuildContext context, ColorScheme cs) {
    final now = DateTime.now();
    final todayStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    return SafeArea(
      child: SingleChildScrollView(
        // Padding bas généreux : dégage la pile de boutons du FAB (~156px) pour
        // que les derniers items du programme restent cochables.
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 140),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.header != null) ...[
              widget.header!,
              const SizedBox(height: 20),
            ],
            Text(
              'Aujourd\'hui',
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: cs.onSurface),
            ),
            const SizedBox(height: 24),

            // Programme horaire (stream Firestore)
            DailyScheduleView(date: todayStr, logic: logic),

            const SizedBox(height: 24),

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


  // ── État actif ───────────────────────────────────────────────────────────────

  Widget _buildActive(BuildContext context, ColorScheme cs, Activity running) {
    final domain = st.activeDomains
        .where((d) => d.id == running.domainId)
        .firstOrNull;
    final color = domainColor(running.domainId, st.activeDomains) ?? cs.primary;
    final elapsed = _elapsedDuration;
    final task = widget.focusTask;
    final project = widget.focusProject;
    final now = DateTime.now();
    final todayStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    final endsAt = widget.countdownEndsAt;
    final remaining = endsAt != null ? endsAt.difference(now) : null;
    final isCountdown = remaining != null && remaining > Duration.zero;


    return SafeArea(
      child: SingleChildScrollView(
        // Padding bas généreux : le programme du jour est en bas ici, il doit
        // rester cochable sous la pile de boutons du FAB (~156px).
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 140),
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
                onTap: () => widget.onTaskTap?.call(project, task),
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

            // Minuteur (anneau de décompte) OU chrono (temps écoulé)
            if (isCountdown) ...[
              Center(
                child: _CountdownRing(
                  remaining: remaining,
                  totalSec: widget.countdownTotalSec ?? remaining.inSeconds,
                  color: color,
                ),
              ),
              const SizedBox(height: 20),
              Center(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.timer_off_outlined, size: 18),
                  label: const Text('Arrêter le minuteur'),
                  onPressed: widget.onStopCountdown,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(200, 48),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ] else ...[
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
            ],

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
              const SizedBox(height: 24),
              Center(
                child: TextButton.icon(
                  icon: const Icon(Icons.account_tree_outlined, size: 16),
                  label: const Text('Lier à une tâche'),
                  onPressed: () => _showTaskPicker(context, running),
                ),
              ),
            ],

            // Programme du jour — masqué pendant un minuteur (mode focus pur)
            if (!isCountdown) ...[
              const SizedBox(height: 32),
              DailyScheduleView(date: todayStr, logic: logic),
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
    final wasDone = action.done;
    setState(() {
      action.done = value;
      action.doneAt = value ? DateTime.now() : null;
    });
    // XP : action Gantt cochée (par jour, jamais décrémenté).
    if (value && !wasDone) {
      final now = DateTime.now();
      final ymd =
          '${now.year.toString().padLeft(4, '0')}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
      final m = widget.logic.state.ganttActionsByDay;
      m[ymd] = (m[ymd] ?? 0) + 1;
      widget.logic.onChange();
    }
    final sync = FirestoreSync();
    await sync.saveProjectTasks(project.id, project.tasks);
  }

  // ── Flow démarrage ───────────────────────────────────────────────────────────

  Future<void> _showTaskPicker(BuildContext context, Activity activity) async {
    final result = await _pickTask(context, activity);
    if (result == null || !mounted) return;
    widget.onStartTimer(activity, result.$1, result.$2);
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

// ── Anneau de décompte (mode minuteur) ───────────────────────────────────────

class _CountdownRing extends StatelessWidget {
  final Duration remaining;
  final int totalSec;
  final Color color;
  const _CountdownRing(
      {required this.remaining, required this.totalSec, required this.color});

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final progress =
        totalSec > 0 ? (remaining.inSeconds / totalSec).clamp(0.0, 1.0) : 0.0;
    final urgent = remaining.inSeconds <= 60;
    final ringColor = urgent ? Colors.red.shade400 : color;
    return SizedBox(
      width: 240,
      height: 240,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 240,
            height: 240,
            child: CircularProgressIndicator(
              value: progress,
              strokeWidth: 12,
              strokeCap: StrokeCap.round,
              backgroundColor: cs.surfaceContainerHighest.withOpacity(.4),
              valueColor: AlwaysStoppedAnimation<Color>(ringColor),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _fmt(remaining),
                style: TextStyle(
                  fontSize: 46,
                  fontWeight: FontWeight.w300,
                  letterSpacing: 1,
                  color: cs.onSurface,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 2),
              Text('restant',
                  style: TextStyle(
                      fontSize: 11,
                      letterSpacing: 2,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface.withOpacity(.45))),
            ],
          ),
        ],
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
