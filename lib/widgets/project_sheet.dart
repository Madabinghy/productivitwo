import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:productivitwo_v1/widgets/activity_picker.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/checklist_logic.dart' show setActionDone, setChecklistItem;
import 'package:productivitwo_v1/utils/domain_colors.dart';
import 'package:productivitwo_v1/utils/palier_colors.dart' show kPalierCoral;
import 'package:productivitwo_v1/utils/progress_bricks.dart';
import 'package:productivitwo_v1/widgets/progress_bricks.dart';
import 'package:productivitwo_v1/widgets/wall_task.dart';
import 'package:productivitwo_v1/widgets/session_player_screen.dart';
import 'package:productivitwo_v1/widgets/task_fiche_sheet.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/widgets/confirm_done.dart';
import 'package:webview_flutter/webview_flutter.dart';

// ── Entrée publique ───────────────────────────────────────────────────────────

Future<void> showProjectSheet(
  BuildContext context, {
  required Project project,
  required List<Domain> domains,
  String? targetTaskId,
  List<Activity> activities = const [], // pour lier une action à une activité-temps
  List<Session> sessions = const [], // chronos ouverts → briques « chrono dessus »
  AppLogic? logic,
  void Function(Activity activity, Project project, ProjectTask task)? onStartTimer,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ProjectSheet(
      project: project,
      domains: domains,
      targetTaskId: targetTaskId,
      activities: activities,
      sessions: sessions,
      logic: logic,
      onStartTimer: onStartTimer,
    ),
  );
}

// ── Sheet ─────────────────────────────────────────────────────────────────────

class _ProjectSheet extends StatefulWidget {
  final Project project;
  final List<Domain> domains;
  final String? targetTaskId;
  final List<Activity> activities;
  final List<Session> sessions;
  final AppLogic? logic;
  final void Function(Activity activity, Project project, ProjectTask task)? onStartTimer;

  const _ProjectSheet({
    required this.project,
    required this.domains,
    this.targetTaskId,
    this.activities = const [],
    this.sessions = const [],
    this.logic,
    this.onStartTimer,
  });

  @override
  State<_ProjectSheet> createState() => _ProjectSheetState();
}

class _ProjectSheetState extends State<_ProjectSheet> {
  late Project _project;
  final _sync = FirestoreSync();
  final _scrollCtrl = ScrollController();
  final _taskKeys = <String, GlobalKey>{};
  List<Map<String, dynamic>> _docs = [];
  /// Tâches faites MASQUÉES par défaut (retour user 2026-10 : prioriser
  /// l'action) ; « Afficher les faites · n » les ramène. La tâche visée
  /// reste toujours visible.
  bool _showDone = false;
  /// Description repliée derrière un bouton discret « Détail ».
  bool _detailOpen = false;

  bool _visible(ProjectTask t) => _showDone || t.status != 'done' || t.id == widget.targetTaskId;

  @override
  void initState() {
    super.initState();
    _project = widget.project;
    _healOrphanedPhaseIds();
    for (final t in _project.tasks) {
      _taskKeys[t.id] = GlobalKey();
    }
    if (widget.targetTaskId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToTarget());
    }
    _loadDocs();
  }

  /// Corrige les phaseId orphelins en utilisant le groupLabel (insensible à la casse).
  /// Sauvegarde silencieusement si des corrections ont été faites.
  void _healOrphanedPhaseIds() {
    final phaseIds = { for (final p in _project.phases) p.id };
    final phaseByLabelLower = {
      for (final p in _project.phases) p.label.toLowerCase().trim(): p
    };
    var changed = false;
    for (final t in _project.tasks) {
      if (t.phaseId != null && phaseIds.contains(t.phaseId)) continue;
      if (t.groupLabel == null) continue;
      final matched = phaseByLabelLower[t.groupLabel!.toLowerCase().trim()];
      if (matched != null) {
        t.phaseId = matched.id;
        t.groupLabel = matched.label;
        changed = true;
      }
    }
    if (changed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _sync.saveProjectTasks(_project.id, _project.tasks);
      });
    }
  }

  Future<void> _loadDocs() async {
    final docs = await _sync.fetchDocuments(projectId: _project.id);
    if (mounted) setState(() => _docs = docs);
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
    if (next == 'done' && !await confirmDone(context, title: task.title, task: true)) return;
    setState(() => task.status = next);
    await _sync.saveProject(_project);
  }

  /// Valide le plan : le brouillon devient actif → il compte désormais dans
  /// l'économie d'Or et le score. Recale les tâches sans date sur aujourd'hui.
  Future<void> _validatePlan() async {
    final today = DateTime.now();
    final todayMid = DateTime(today.year, today.month, today.day);
    setState(() {
      _project.status = 'active';
      for (final t in _project.tasks) {
        if (t.startDate.isBefore(DateTime(2001))) t.startDate = todayMid;
      }
    });
    await _sync.saveProject(_project);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Plan validé — le projet est actif. 🚀')));
  }

  /// Renomme le projet (édition manuelle).
  Future<void> _renameProject() async {
    final ctrl = TextEditingController(text: _project.title);
    final newTitle = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Renommer le projet'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'Titre du projet'),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('Renommer')),
        ],
      ),
    );
    if (newTitle == null || newTitle.isEmpty || newTitle == _project.title) {
      return;
    }
    setState(() => _project.title = newTitle);
    await _sync.saveProject(_project);
  }

  Future<String?> _promptText(String title, String hint, String initial) {
    final ctrl = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(hintText: hint),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('OK')),
        ],
      ),
    );
  }

  Future<void> _addPhase() async {
    final label = await _promptText('Nouvelle phase', 'Nom de la phase', '');
    if (label == null || label.isEmpty) return;
    _project.phases.add(ProjectPhase(
      label: label,
      startDate: _project.startDate,
      endDate: _project.endDate ??
          _project.startDate.add(const Duration(days: 30)),
    ));
    setState(() {});
    await _sync.saveProject(_project);
  }

  Future<void> _renamePhase(ProjectPhase phase) async {
    final label =
        await _promptText('Renommer la phase', 'Nom de la phase', phase.label);
    if (label == null || label.isEmpty || label == phase.label) return;
    setState(() => phase.label = label);
    await _sync.saveProject(_project);
  }

  Future<void> _deletePhase(ProjectPhase phase) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer la phase ?'),
        content: Text(
            'Les tâches de « ${phase.label} » deviennent « sans phase ». La phase est supprimée.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler')),
          FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(ctx).colorScheme.error),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Supprimer')),
        ],
      ),
    );
    if (ok != true) return;
    for (final t in _project.tasks) {
      if (t.phaseId == phase.id) t.phaseId = null;
    }
    _project.phases.removeWhere((p) => p.id == phase.id);
    setState(() {});
    await _sync.saveProject(_project);
  }

  /// Vrai si toutes les tâches (hors « skipped ») sont faites → terminable.
  bool get _allTasksDone {
    final inScope =
        _project.tasks.where((t) => t.status != 'skipped').toList();
    return inScope.isNotEmpty && inScope.every((t) => t.status == 'done');
  }

  /// Termine le projet (toutes tâches faites → status 'done', va dans TERMINÉ)
  /// ou le rouvre (status 'active').
  Future<void> _toggleComplete(BuildContext context) async {
    final completing = _project.status != 'done';
    if (completing && !_allTasksDone) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:
              Text('Termine toutes les tâches avant de clôturer le projet.')));
      return;
    }
    setState(() => _project.status = completing ? 'done' : 'active');
    await _sync.saveProject(_project);
    if (!context.mounted) return;
    if (completing) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('✅ « ${_project.title} » terminé — rangé dans Terminé.')));
      Navigator.pop(context);
    }
  }

  /// Supprime le projet (confirmation simple — l'économie d'or du jeu a été
  /// retirée). Archiver reste l'option qui garde l'historique.
  Future<void> _deleteProject() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer le projet ?'),
        content: Text(
          'Le projet « ${_project.title} » et tout son contenu seront supprimés.'
          '\n\nAstuce : « Mettre en veille » garde l\'historique.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _sync.deleteProject(_project.id);
    if (!mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Projet supprimé')));
  }

  Color _domainColor(ColorScheme cs) {
    if (widget.project.domainId == null) return cs.primary;
    final idx = widget.domains.indexWhere((d) => d.id == widget.project.domainId);
    if (idx < 0) return cs.primary;
    final d = widget.domains[idx];
    if (d.colorValue != null) return Color(d.colorValue!);
    return kDomainPalette[idx % kDomainPalette.length];
  }

  // ── Activité liée : chrono hérité par toutes les actions du projet ────────

  Widget _linkedActivityRow(ColorScheme cs) {
    final linked = widget.activities
        .firstWhereOrNull((a) => a.id == _project.linkedActivityId);
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: _pickLinkedActivity,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Icon(Icons.timer_outlined,
              size: 13,
              color: linked == null
                  ? cs.onSurface.withOpacity(.4)
                  : cs.primary.withOpacity(.8)),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              linked == null
                  ? 'Lier à une activité (chrono des actions)'
                  : 'Activité liée : ${linked.name}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight:
                      linked == null ? FontWeight.w400 : FontWeight.w600,
                  color: linked == null
                      ? cs.onSurface.withOpacity(.45)
                      : cs.primary.withOpacity(.85)),
            ),
          ),
          Icon(Icons.chevron_right,
              size: 14, color: cs.onSurface.withOpacity(.3)),
        ]),
      ),
    );
  }

  Future<void> _pickLinkedActivity() async {
    // Activités-temps, celles du domaine du projet en premier.
    final candidates = widget.activities.where((a) => a.type == 'time' && !a.deleted).toList();
    if (candidates.isEmpty) return;
    final picked = await showActivityPicker(context,
        activities: candidates,
        domains: widget.domains,
        title: 'Activité liée au projet',
        selectedId: _project.linkedActivityId,
        preferDomainId: _project.domainId,
        extras: [if (_project.linkedActivityId != null) const ActivityPickerExtra('', 'Aucune (délier)', icon: Icons.link_off)]);
    if (picked == null) return;
    setState(() =>
        _project.linkedActivityId = picked.isEmpty ? null : picked);
    await _sync.saveProject(_project);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = _domainColor(cs);
    final today = DateTime.now();

    final done  = _project.tasks.where((t) => t.status == 'done').length;
    final running = runningTargets(widget.sessions);
    final wall = projectBricks(_project, today, runningTaskIds: running.taskIds, runningActionIds: running.actionIds);

    // Grouper tâches par phase (phaseId en priorité, groupLabel en fallback)
    final phaseByLabel = { for (final p in _project.phases) p.label: p };
    final phaseByLabelLower = { for (final p in _project.phases) p.label.toLowerCase().trim(): p };
    final phaseIds = { for (final p in _project.phases) p.id };
    final grouped = <String?, List<ProjectTask>>{};
    for (final t in _project.tasks) {
      String? key = t.phaseId;
      // phaseId orphelin (phase supprimée ou désynchronisée) → on efface
      if (key != null && !phaseIds.contains(key)) key = null;
      // Fallback : groupLabel — insensible à la casse
      if (key == null && t.groupLabel != null) {
        final matched = phaseByLabel[t.groupLabel]
            ?? phaseByLabelLower[t.groupLabel!.toLowerCase().trim()];
        key = matched?.id;
      }
      grouped.putIfAbsent(key, () => []).add(t);
    }

    return DraggableScrollableSheet(
      // Pleine page (retour user 2026-10) : le projet déplié se lit en entier.
      initialChildSize: 1.0,
      maxChildSize: 1.0,
      minChildSize: 0.5,
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
                            GestureDetector(
                              onTap: () => _changeDomain(context, cs),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _project.domainId != null
                                        ? (widget.domains
                                                .where((d) => d.id == _project.domainId)
                                                .firstOrNull
                                                ?.name ??
                                            'Domaine inconnu')
                                        : 'Sans domaine',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: color,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Icon(Icons.edit_outlined, size: 11, color: color.withOpacity(.5)),
                                ],
                              ),
                            ),
                            const SizedBox(height: 3),
                            GestureDetector(
                              onTap: _renameProject,
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Flexible(
                                    child: Text(
                                      _project.title,
                                      style: const TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.w800),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Icon(Icons.edit_outlined,
                                        size: 14,
                                        color: cs.onSurface.withOpacity(.35)),
                                  ),
                                ],
                              ),
                            ),
                            if (_project.description != null &&
                                _project.description!.isNotEmpty) ...[
                              GestureDetector(
                                onTap: () => setState(() => _detailOpen = !_detailOpen),
                                behavior: HitTestBehavior.opaque,
                                child: Padding(
                                  padding: const EdgeInsets.only(top: 4, bottom: 2),
                                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                                    Text('Détail',
                                        style: TextStyle(
                                            fontSize: 12.5, fontWeight: FontWeight.w700, color: cs.primary.withOpacity(.85))),
                                    Icon(_detailOpen ? Icons.expand_less : Icons.expand_more,
                                        size: 16, color: cs.primary.withOpacity(.85)),
                                  ]),
                                ),
                              ),
                              if (_detailOpen)
                                Text(_project.description!,
                                    style: TextStyle(fontSize: 13, color: cs.onSurface.withOpacity(.55))),
                            ],
                          ],
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          _project.status == 'done'
                              ? Icons.check_circle
                              : Icons.check_circle_outline,
                          size: 20,
                          color: _project.status == 'done'
                              ? Colors.green
                              : (_allTasksDone
                                  ? Colors.green.withOpacity(.7)
                                  : cs.onSurface.withOpacity(.25)),
                        ),
                        tooltip: _project.status == 'done'
                            ? 'Rouvrir le projet'
                            : 'Terminer le projet',
                        visualDensity: VisualDensity.compact,
                        onPressed: () => _toggleComplete(context),
                      ),
                      IconButton(
                        icon: Icon(
                          _project.status == 'archived'
                              ? Icons.unarchive_outlined
                              : Icons.archive_outlined,
                          size: 20,
                          color: cs.onSurface.withOpacity(.4),
                        ),
                        tooltip: _project.status == 'archived'
                            ? 'Réactiver le projet'
                            : 'Mettre en veille',
                        visualDensity: VisualDensity.compact,
                        onPressed: () => _toggleArchive(context, cs),
                      ),
                      IconButton(
                        icon: Icon(Icons.delete_outline,
                            size: 20, color: cs.error.withOpacity(.5)),
                        tooltip: 'Supprimer le projet',
                        visualDensity: VisualDensity.compact,
                        onPressed: _deleteProject,
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
                        '${wall.done} / ${wall.total} tâches${wall.expected > 0 && wall.expected < wall.total ? ' · attendu ${wall.expected}' : ''}',
                        style: TextStyle(
                            fontSize: 12, color: cs.onSurface.withOpacity(.45)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Mur des projets (lot 2) : la rangée de briques du projet,
                  // tap sur une brique = déplie cette tâche.
                  ProgressBricks(
                      row: wall,
                      height: 14,
                      highlight: _expandedIndex(wall),
                      onBrick: (i) => _focusBrick(wall, i),
                      pickerTitle: 'Tâches · ${_project.title}'),
                  if (behindLabel(wall) == null && wall.total > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text('Touche une brique pour déplier sa tâche',
                          style: TextStyle(fontSize: 11.5, color: cs.onSurface.withOpacity(.45))),
                    ),
                  if (behindLabel(wall) != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(behindLabel(wall)!,
                          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: kPalierCoral)),
                    ),
                  const SizedBox(height: 8),
                  _linkedActivityRow(cs),
                  if (_project.status == 'draft') ...[
                    const SizedBox(height: 12),
                    _DraftPlanBanner(onValidate: _validatePlan),
                  ],
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
                  if (done > 0) _doneToggle(cs, done),
                  // Phases dans l'ordre, puis tâches sans phase
                  for (final phase in _project.phases) ...[
                    _PhaseHeader(
                      phase: phase,
                      onRename: () => _renamePhase(phase),
                      onDelete: () => _deletePhase(phase),
                    ),
                    for (final task in (grouped[phase.id] ?? []).where(_visible))
                      KeyedSubtree(key: _taskKeys[task.id], child: _wallTask(task, today, running)),
                  ],
                  // Tâches sans phase
                  if ((grouped[null] ?? []).isNotEmpty) ...[
                    if (_project.phases.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(0, 12, 0, 4),
                        child: Text(
                          'Sans phase',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                            color: cs.onSurface.withOpacity(.45),
                          ),
                        ),
                      ),
                    for (final task in (grouped[null] ?? []).where(_visible))
                      KeyedSubtree(key: _taskKeys[task.id], child: _wallTask(task, today, running)),
                  ],

                  // Ajouter une tâche / une phase (gestion autonome, sans IA)
                  const SizedBox(height: 10),
                  Center(
                    child: Wrap(
                      spacing: 4,
                      alignment: WrapAlignment.center,
                      children: [
                        TextButton.icon(
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Ajouter une tâche'),
                          onPressed: _addTask,
                        ),
                        TextButton.icon(
                          icon: const Icon(Icons.create_new_folder_outlined,
                              size: 18),
                          label: const Text('Ajouter une phase'),
                          onPressed: _addPhase,
                        ),
                      ],
                    ),
                  ),

                  // ── Documents liés au projet ─────────────────────────
                  if (_docs.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Divider(height: 1, color: cs.outlineVariant.withOpacity(.3)),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(0, 14, 0, 8),
                      child: Text(
                        'DOCUMENTS (${_docs.length})',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1,
                          color: cs.onSurface.withOpacity(.4),
                        ),
                      ),
                    ),
                    for (final doc in _docs)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                          decoration: BoxDecoration(
                            color: cs.surfaceContainerHighest.withOpacity(.4),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.description_outlined,
                                  size: 16,
                                  color: cs.onSurface.withOpacity(.45)),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  doc['title'] as String? ?? 'Document',
                                  style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500),
                                ),
                              ),
                            ],
                          ),
                        ),
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

  Future<void> _toggleArchive(BuildContext context, ColorScheme cs) async {
    final isArchived = _project.status == 'archived';
    if (!isArchived) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Mettre en veille ?'),
          content: Text(
              'Le projet "${_project.title}" sera masqué de la vue principale. Tu pourras le réactiver depuis l\'onglet Projets.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Annuler')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Mettre en veille')),
          ],
        ),
      );
      if (confirm != true) return;
    }
    setState(() => _project.status = isArchived ? 'active' : 'archived');
    await _sync.saveProject(_project);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _changeDomain(BuildContext context, ColorScheme cs) async {
    final domains = widget.domains;

    final selected = await showModalBottomSheet<String?>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Text('Changer de domaine',
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.bold)),
            ),
            ListTile(
              leading: Icon(Icons.remove_circle_outline,
                  color: cs.onSurface.withOpacity(.4)),
              title: Text('Sans domaine',
                  style: TextStyle(color: cs.onSurface.withOpacity(.5))),
              onTap: () => Navigator.pop(ctx, ''),
            ),
            const Divider(height: 1),
            for (final d in domains)
              ListTile(
                leading: Container(
                  width: 12, height: 12,
                  decoration: BoxDecoration(
                    color: d.colorValue != null
                        ? Color(d.colorValue!)
                        : cs.primary,
                    shape: BoxShape.circle,
                  ),
                ),
                title: Text(d.name,
                    style: TextStyle(
                      fontWeight: _project.domainId == d.id
                          ? FontWeight.bold
                          : FontWeight.normal,
                    )),
                trailing: _project.domainId == d.id
                    ? Icon(Icons.check, color: cs.primary)
                    : null,
                onTap: () => Navigator.pop(ctx, d.id),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (selected == null) return;
    setState(() => _project.domainId = selected.isEmpty ? null : selected);
    await _sync.saveProject(_project);
  }

  /// Tâche jalon d'une intervention native → écran « séance en cours ».
  VoidCallback? _sessionLauncher(ProjectTask task) {
    if (task.interventionRole != 'session' || task.interventionId == null) return null;
    final i = _project.interventions.where((x) => x.id == task.interventionId).firstOrNull;
    if (i == null) return null;
    return () => showSessionPlayer(context,
        project: _project, intervention: i, sessionTask: task, sync: _sync)
        .then((_) {
      if (mounted) setState(() {});
    });
  }

  Widget _doneToggle(ColorScheme cs, int done) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: () => setState(() => _showDone = !_showDone),
        icon: Icon(_showDone ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 16),
        label: Text(_showDone
            ? 'Masquer les ${done > 1 ? '$done tâches faites' : 'tâche faite'}'
            : 'Afficher les ${done > 1 ? '$done tâches faites' : 'tâche faite'}'),
        style: TextButton.styleFrom(
          foregroundColor: cs.onSurface.withOpacity(.55),
          textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
          visualDensity: VisualDensity.compact,
        ),
      ),
    );
  }

  Future<void> _openTaskDetail(ProjectTask task, {String? actionId}) async {
    await showTaskDetail(context,
        project: _project,
        task: task,
        activities: widget.activities,
        sync: _sync,
        logic: widget.logic,
        onStartTimer: widget.onStartTimer,
        expandActionId: actionId,
        onChanged: () => setState(() {}));
    if (mounted) setState(() {});
  }

  /// Tâche dépliée sur place : la tâche visée (ou touchée dans la rangée) s'ouvre.
  String? _expandedTaskId;

  int? _expandedIndex(BrickRow wall) {
    final id = _expandedTaskId ?? widget.targetTaskId;
    if (id == null) return null;
    final i = wall.bricks.indexWhere((b) => b.id == id);
    return i < 0 ? null : i;
  }

  void _focusBrick(BrickRow wall, int i) {
    if (i < 0 || i >= wall.total) return;
    final id = wall.bricks[i].id;
    setState(() {
      _expandedTaskId = id;
      _showDone = _showDone || _project.tasks.any((t) => t.id == id && t.status == 'done');
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _taskKeys[id]?.currentContext;
      if (ctx != null) Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 350), curve: Curves.easeOut, alignment: 0.15);
    });
  }

  Future<void> _setActionDone(TaskAction a, bool done) async {
    if (done && !await confirmDone(context, title: a.title)) return;
    setState(() => setActionDone(a, done));
    await _sync.patchActionOf(_project, a);
  }

  Future<void> _setStep(TaskAction a, ChecklistItem c, bool done) async {
    setState(() => setChecklistItem(a, c.id, done));
    await _sync.patchActionOf(_project, a);
  }

  Widget _wallTask(ProjectTask task, DateTime today, ({Set<String> taskIds, Set<String> actionIds}) running) {
    final expandId = _expandedTaskId ?? widget.targetTaskId;
    return WallTask(
      key: ValueKey('wall-${task.id}-${expandId == task.id}'),
      task: task,
      today: today,
      runningTaskIds: running.taskIds,
      runningActionIds: running.actionIds,
      initiallyExpanded: task.id == expandId,
      isTarget: task.id == widget.targetTaskId,
      onOpenFiche: () => _openTaskDetail(task),
      onOpenAction: (a) => _openTaskDetail(task, actionId: a.id),
      onToggleDone: () => _toggleStatus(task),
      onActionDone: _setActionDone,
      onStep: _setStep,
      onLaunchSession: _sessionLauncher(task),
    );
  }

  /// Crée une tâche dans le projet, sans IA (titre + phase + dates optionnelles).
  Future<void> _addTask() async {
    final ctrl = TextEditingController();
    String? phaseId =
        _project.phases.isNotEmpty ? _project.phases.first.id : null;
    var start = DateTime.now();
    DateTime? end;

    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSB) => Padding(
          padding: EdgeInsets.fromLTRB(
              20, 16, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Nouvelle tâche',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 14),
              TextField(
                controller: ctrl,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                    labelText: 'Titre', border: OutlineInputBorder()),
              ),
              if (_project.phases.isNotEmpty) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  value: phaseId,
                  decoration: const InputDecoration(
                      labelText: 'Phase', border: OutlineInputBorder()),
                  items: [
                    const DropdownMenuItem(
                        value: null, child: Text('Aucune phase')),
                    for (final p in _project.phases)
                      DropdownMenuItem(value: p.id, child: Text(p.label)),
                  ],
                  onChanged: (v) => setSB(() => phaseId = v),
                ),
              ],
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.play_arrow_outlined, size: 20),
                title: const Text('Début'),
                trailing: Text(_fmt(start)),
                onTap: () async {
                  final d = await showDatePicker(
                    context: ctx,
                    initialDate: start,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100),
                  );
                  if (d != null) setSB(() => start = d);
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.flag_outlined, size: 20),
                title: const Text('Échéance (optionnelle)'),
                trailing: Text(end != null ? _fmt(end!) : 'Aucune'),
                onTap: () async {
                  final d = await showDatePicker(
                    context: ctx,
                    initialDate: end ?? start,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100),
                  );
                  if (d != null) setSB(() => end = d);
                },
              ),
              const SizedBox(height: 8),
              Row(children: [
                const Spacer(),
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Annuler')),
                FilledButton(
                  onPressed: () {
                    if (ctrl.text.trim().isEmpty) return;
                    Navigator.pop(ctx, true);
                  },
                  child: const Text('Créer'),
                ),
              ]),
            ],
          ),
        ),
      ),
    );

    if (created == true && ctrl.text.trim().isNotEmpty) {
      final task = ProjectTask(
        title: ctrl.text.trim(),
        phaseId: phaseId,
        groupLabel:
            _project.phases.where((p) => p.id == phaseId).firstOrNull?.label,
        startDate: start,
        endDate: end,
      );
      setState(() => _project.tasks.add(task));
      await _sync.saveProjectTasks(_project.id, _project.tasks);
    }
    ctrl.dispose();
  }

  String _fmt(DateTime d) {
    const m = ['jan', 'fév', 'mar', 'avr', 'mai', 'juin',
                'juil', 'aoû', 'sep', 'oct', 'nov', 'déc'];
    return '${d.day} ${m[d.month - 1]}';
  }
}

// ── Sheet détail d'une tâche ──────────────────────────────────────────────────

/// Fiche de TÂCHE : depuis 2026-10 c'est `showTaskFiche`
/// (`widgets/task_fiche_sheet.dart`, grammaire « une carte, une fiche »).
/// [expandActionId] ouvre directement la fiche de cette action.
Future<void> showTaskDetail(
  BuildContext context, {
  required Project project,
  required ProjectTask task,
  List<Activity> activities = const [],
  List<Project> allProjects = const [],
  FirestoreSync? sync,
  String? expandActionId,
  VoidCallback? onChanged,
  AppLogic? logic,
  void Function(Activity activity, Project project, ProjectTask task)? onStartTimer,
}) {
  return showTaskFiche(
    context,
    project: project,
    task: task,
    activities: activities,
    allProjects: allProjects,
    sync: sync,
    logic: logic,
    onStartTimer: onStartTimer,
    expandActionId: expandActionId,
    onChanged: onChanged,
  );
}

/// Liste des documents liés (programmes, briefs, livrables) : tap = visionneuse.
Future<void> showDocList(BuildContext context, List<Map<String, dynamic>> docs) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _DocListSheet(docs: docs),
  );
}

class _DocListSheet extends StatelessWidget {
  final List<Map<String, dynamic>> docs;
  const _DocListSheet({required this.docs});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      maxChildSize: 0.9,
      minChildSize: 0.3,
      expand: false,
      builder: (_, scroll) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Text(
              'DOCUMENTS (${docs.length})',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
                color: cs.onSurface.withOpacity(.4),
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: scroll,
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
              itemCount: docs.length,
              itemBuilder: (ctx, i) {
                final doc = docs[i];
                final title = doc['title'] as String? ?? 'Document';
                final html = doc['content'] as String? ?? '';
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    tileColor: cs.surfaceContainerHighest.withOpacity(.4),
                    leading: Icon(Icons.description_outlined,
                        color: cs.onSurface.withOpacity(.5)),
                    title: Text(title,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w500)),
                    trailing: Icon(Icons.chevron_right,
                        color: cs.onSurface.withOpacity(.3)),
                    onTap: () => Navigator.push(
                      ctx,
                      MaterialPageRoute(
                        builder: (_) => DocViewer(title: title, html: html),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class DocViewer extends StatefulWidget {
  final String title;
  final String html;
  const DocViewer({required this.title, required this.html});

  @override
  State<DocViewer> createState() => DocViewerState();
}

class DocViewerState extends State<DocViewer> {
  WebViewController? _ctrl;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      _ctrl = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(const Color(0xFF0A0A0A))
        ..setNavigationDelegate(NavigationDelegate(
          onPageFinished: (_) {
            if (mounted) setState(() => _ready = true);
          },
        ))
        ..loadHtmlString(widget.html);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: const Color(0xFF0A0A0A),
        appBar: AppBar(
          backgroundColor: const Color(0xFF111111),
          foregroundColor: Colors.white,
          title: Text(
            widget.title,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            overflow: TextOverflow.ellipsis,
          ),
          elevation: 0,
        ),
        body: kIsWeb
            ? const Center(
                child: Text('Ouvre le document depuis l\'app web.',
                    style: TextStyle(color: Colors.white54)))
            : Stack(children: [
                if (_ctrl != null) WebViewWidget(controller: _ctrl!),
                if (!_ready)
                  const Center(child: CircularProgressIndicator()),
              ]),
      );
}

// ── Header de phase ───────────────────────────────────────────────────────────

class _PhaseHeader extends StatelessWidget {
  final ProjectPhase phase;
  final VoidCallback? onRename;
  final VoidCallback? onDelete;
  const _PhaseHeader({required this.phase, this.onRename, this.onDelete});

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

    // Le nom de la phase a toute la largeur (retour user 2026-10) : plus de
    // capitales minuscules tronquées ni de filet qui lui vole la place.
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 16, 0, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 4,
            height: 18,
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              phase.label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                letterSpacing: .2,
                height: 1.2,
                color: color,
              ),
            ),
          ),
          if (onRename != null || onDelete != null)
            SizedBox(
              width: 30,
              height: 30,
              child: PopupMenuButton<String>(
                padding: EdgeInsets.zero,
                iconSize: 16,
                icon: Icon(Icons.more_horiz, color: cs.onSurface.withOpacity(.4)),
                onSelected: (v) {
                  if (v == 'rename') onRename?.call();
                  if (v == 'delete') onDelete?.call();
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'rename', child: Text('Renommer')),
                  const PopupMenuItem(value: 'delete', child: Text('Supprimer')),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ── Tuile de tâche ────────────────────────────────────────────────────────────

class _DraftPlanBanner extends StatelessWidget {
  final Future<void> Function() onValidate;
  const _DraftPlanBanner({required this.onValidate});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      decoration: BoxDecoration(
        color: cs.tertiaryContainer.withOpacity(.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.tertiary.withOpacity(.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.edit_note_outlined, size: 20, color: cs.tertiary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Brouillon — modifie librement, puis valide pour planifier.',
              style: TextStyle(
                  fontSize: 12.5, color: cs.onTertiaryContainer),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.tonalIcon(
            onPressed: onValidate,
            icon: const Icon(Icons.rocket_launch_outlined, size: 16),
            label: const Text('Valider'),
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Description repliable de la fiche projet ─────────────────────────────────
//
// Au-delà de [maxLines] lignes, le texte est tronqué avec un lien
// « … voir plus » / « voir moins ». La mesure utilise un TextPainter pour ne
// proposer le repli QUE si le texte déborde réellement.
