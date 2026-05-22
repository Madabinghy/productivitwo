import 'package:flutter/material.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/domain_colors.dart';

// ── Entrée publique ───────────────────────────────────────────────────────────

Future<void> showProjectSheet(
  BuildContext context, {
  required Project project,
  required List<Domain> domains,
  String? targetTaskId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ProjectSheet(
      project: project,
      domains: domains,
      targetTaskId: targetTaskId,
    ),
  );
}

// ── Sheet ─────────────────────────────────────────────────────────────────────

class _ProjectSheet extends StatefulWidget {
  final Project project;
  final List<Domain> domains;
  final String? targetTaskId;

  const _ProjectSheet({
    required this.project,
    required this.domains,
    this.targetTaskId,
  });

  @override
  State<_ProjectSheet> createState() => _ProjectSheetState();
}

class _ProjectSheetState extends State<_ProjectSheet> {
  late Project _project;
  final _sync = FirestoreSync();
  final _scrollCtrl = ScrollController();
  final _taskKeys = <String, GlobalKey>{};

  @override
  void initState() {
    super.initState();
    _project = widget.project;
    for (final t in _project.tasks) {
      _taskKeys[t.id] = GlobalKey();
    }
    if (widget.targetTaskId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToTarget());
    }
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _scrollToTarget() {
    final key = _taskKeys[widget.targetTaskId];
    if (key == null) return;
    final ctx = key.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(ctx,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOut,
        alignment: 0.2);
  }

  Future<void> _toggleStatus(ProjectTask task) async {
    final next = task.status == 'done' ? 'pending' : 'done';
    setState(() => task.status = next);
    await _sync.saveProject(_project);
  }

  Color _domainColor(ColorScheme cs) {
    if (widget.project.domainId == null) return cs.primary;
    final idx = widget.domains.indexWhere((d) => d.id == widget.project.domainId);
    if (idx < 0) return cs.primary;
    final d = widget.domains[idx];
    if (d.colorValue != null) return Color(d.colorValue!);
    return kDomainPalette[idx % kDomainPalette.length];
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = _domainColor(cs);
    final today = DateTime.now();

    final done  = _project.tasks.where((t) => t.status == 'done').length;
    final total = _project.tasks.length;
    final progress = total > 0 ? done / total : 0.0;

    // Grouper tâches par phase (puis sans phase)
    final phaseMap = { for (final p in _project.phases) p.id: p };
    final grouped = <String?, List<ProjectTask>>{};
    for (final t in _project.tasks) {
      grouped.putIfAbsent(t.phaseId, () => []).add(t);
    }

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      expand: false,
      builder: (_, __) => Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // ── Drag handle ──────────────────────────────────────────────
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 10, bottom: 6),
                width: 36, height: 4,
                decoration: BoxDecoration(
                  color: cs.onSurface.withOpacity(.15),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // ── Header ───────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (widget.project.domainId != null)
                              Text(
                                widget.domains
                                    .where((d) => d.id == widget.project.domainId)
                                    .firstOrNull?.name ?? '',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: color,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            const SizedBox(height: 3),
                            Text(
                              _project.title,
                              style: const TextStyle(
                                  fontSize: 20, fontWeight: FontWeight.w800),
                            ),
                            if (_project.description != null &&
                                _project.description!.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                _project.description!,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: cs.onSurface.withOpacity(.55),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_outlined, size: 20),
                        onPressed: () => Navigator.pop(context),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Dates + progression
                  Row(
                    children: [
                      Icon(Icons.calendar_today_outlined,
                          size: 12, color: cs.onSurface.withOpacity(.4)),
                      const SizedBox(width: 5),
                      Text(
                        '${_fmt(_project.startDate)} → ${_project.endDate != null ? _fmt(_project.endDate!) : '—'}',
                        style: TextStyle(
                            fontSize: 12, color: cs.onSurface.withOpacity(.5)),
                      ),
                      const Spacer(),
                      Text(
                        '$done / $total tâches',
                        style: TextStyle(
                            fontSize: 12, color: cs.onSurface.withOpacity(.45)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: progress,
                    minHeight: 4,
                    borderRadius: BorderRadius.circular(2),
                    backgroundColor: cs.onSurface.withOpacity(.08),
                    color: color,
                  ),
                  const SizedBox(height: 14),
                  Divider(height: 1, color: cs.outlineVariant.withOpacity(.4)),
                ],
              ),
            ),

            // ── Liste des tâches ─────────────────────────────────────────
            Expanded(
              child: ListView(
                controller: _scrollCtrl,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  // Phases dans l'ordre, puis tâches sans phase
                  for (final phase in _project.phases) ...[
                    _PhaseHeader(phase: phase),
                    for (final task in grouped[phase.id] ?? [])
                      _TaskTile(
                        key: _taskKeys[task.id],
                        task: task,
                        isTarget: task.id == widget.targetTaskId,
                        today: today,
                        cs: cs,
                        onToggle: () => _toggleStatus(task),
                      ),
                  ],
                  // Tâches sans phase
                  if ((grouped[null] ?? []).isNotEmpty) ...[
                    if (_project.phases.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(0, 12, 0, 4),
                        child: Text(
                          'Sans phase',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                            color: cs.onSurface.withOpacity(.4),
                          ),
                        ),
                      ),
                    for (final task in grouped[null] ?? [])
                      _TaskTile(
                        key: _taskKeys[task.id],
                        task: task,
                        isTarget: task.id == widget.targetTaskId,
                        today: today,
                        cs: cs,
                        onToggle: () => _toggleStatus(task),
                      ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _fmt(DateTime d) {
    const m = ['jan', 'fév', 'mar', 'avr', 'mai', 'juin',
                'juil', 'aoû', 'sep', 'oct', 'nov', 'déc'];
    return '${d.day} ${m[d.month - 1]}';
  }
}

// ── Header de phase ───────────────────────────────────────────────────────────

class _PhaseHeader extends StatelessWidget {
  final ProjectPhase phase;
  const _PhaseHeader({required this.phase});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Color? color;
    if (phase.color != null) {
      try {
        final hex = phase.color!.replaceAll('#', '');
        color = Color(int.parse('FF$hex', radix: 16));
      } catch (_) {}
    }
    color ??= cs.primary;

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 14, 0, 6),
      child: Row(
        children: [
          Container(
            width: 8, height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(
            phase.label.toUpperCase(),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
              color: color,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Divider(color: cs.outlineVariant.withOpacity(.4))),
        ],
      ),
    );
  }
}

// ── Tuile de tâche ────────────────────────────────────────────────────────────

class _TaskTile extends StatelessWidget {
  final ProjectTask task;
  final bool isTarget;
  final DateTime today;
  final ColorScheme cs;
  final VoidCallback onToggle;

  const _TaskTile({
    super.key,
    required this.task,
    required this.isTarget,
    required this.today,
    required this.cs,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final isDone    = task.status == 'done';
    final isSkipped = task.status == 'skipped';
    final todayD    = DateTime(today.year, today.month, today.day);
    final isOverdue = task.endDate != null &&
        task.endDate!.isBefore(todayD) &&
        !isDone && !isSkipped;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: isTarget
            ? cs.primaryContainer.withOpacity(.35)
            : cs.surfaceContainerHighest.withOpacity(.35),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isTarget
              ? cs.primary.withOpacity(.4)
              : cs.outlineVariant.withOpacity(.35),
          width: isTarget ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        onTap: task.isMilestone ? null : onToggle,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Icône statut / jalon
              Padding(
                padding: const EdgeInsets.only(top: 1, right: 10),
                child: task.isMilestone
                    ? Transform.rotate(
                        angle: 0.785,
                        child: Container(
                          width: 13, height: 13,
                          decoration: BoxDecoration(
                            color: isDone
                                ? Colors.green.shade500
                                : Colors.orange.shade600,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      )
                    : Icon(
                        isDone
                            ? Icons.check_circle_rounded
                            : isSkipped
                                ? Icons.remove_circle_outline
                                : Icons.radio_button_unchecked,
                        size: 18,
                        color: isDone
                            ? Colors.green.shade500
                            : isSkipped
                                ? cs.onSurface.withOpacity(.3)
                                : isOverdue
                                    ? cs.error
                                    : cs.onSurface.withOpacity(.45),
                      ),
              ),

              // Contenu
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface.withOpacity(isDone || isSkipped ? .35 : .9),
                        decoration: isDone ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    if (task.endDate != null) ...[
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Icon(
                            Icons.event_outlined,
                            size: 11,
                            color: isOverdue ? cs.error : cs.onSurface.withOpacity(.35),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _fmtDate(task.endDate!),
                            style: TextStyle(
                              fontSize: 11,
                              color: isOverdue ? cs.error : cs.onSurface.withOpacity(.4),
                              fontWeight: isOverdue ? FontWeight.w600 : FontWeight.normal,
                            ),
                          ),
                          if (isOverdue) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: cs.error.withOpacity(.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '−${todayD.difference(task.endDate!).inDays}j',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: cs.error,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                    // Actions / sous-étapes
                    if (task.stepsTotal > 0) ...[
                      const SizedBox(height: 4),
                      Text(
                        '${task.stepsDone}/${task.stepsTotal} étapes',
                        style: TextStyle(
                          fontSize: 11,
                          color: cs.onSurface.withOpacity(.35),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // Badge cible ORION
              if (isTarget)
                Padding(
                  padding: const EdgeInsets.only(left: 6, top: 1),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFe8c94a).withOpacity(.15),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                          color: const Color(0xFFe8c94a).withOpacity(.4)),
                    ),
                    child: const Text(
                      'ORION',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                        color: Color(0xFFe8c94a),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _fmtDate(DateTime d) {
    const m = ['jan', 'fév', 'mar', 'avr', 'mai', 'juin',
                'juil', 'aoû', 'sep', 'oct', 'nov', 'déc'];
    return '${d.day} ${m[d.month - 1]} ${d.year}';
  }
}
