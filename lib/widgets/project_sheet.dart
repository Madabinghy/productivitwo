import 'package:flutter/material.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/gold_economy.dart';
import 'package:productivitwo_v1/gold_purchase.dart';
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
  List<Map<String, dynamic>> _docs = [];

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

  /// Supprime le projet. Gratuit en brouillon ; sinon coût d'or (un joker
  /// l'annule). Archiver reste l'option gratuite pour garder l'historique.
  Future<void> _deleteProject() async {
    final billed = _project.status != 'draft';
    final actions =
        _project.tasks.fold<int>(0, (s, t) => s + t.actions.length);
    final cost = GoldEconomy.deleteProjectCost(_project.tasks.length, actions);
    final showCost = billed && cost > 0;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer le projet ?'),
        content: Text(
          'Le projet « ${_project.title} » et tout son contenu seront supprimés.'
          '${showCost ? ' Coût : $cost or.' : ''}'
          '\n\nAstuce : « Mettre en veille » garde l\'historique gratuitement.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(showCost ? 'Supprimer (−$cost or)' : 'Supprimer'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (showCost) {
      var usedJoker = await _sync.consumeJoker();
      // Pas de joker en stock → proposer d'en acheter pour annuler le coût.
      if (!usedJoker && mounted) {
        final bought = await offerBuyConsumable(
          context,
          _sync,
          itemKey: 'joker',
          price: GoldEconomy.shopJoker,
          label: 'Joker de suppression',
          rationale: 'Annule le coût de $cost or de cette suppression.',
        );
        if (bought) usedJoker = await _sync.consumeJoker();
      }
      if (usedJoker) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('🗑️ Joker utilisé — suppression gratuite.')));
        }
      } else {
        _sync.applyGold(GoldLedgerEntry(
          delta: -cost,
          category: 'loss',
          reasonCode: 'delete_project',
          label: 'Suppression du projet « ${_project.title} »',
          refType: 'project',
          refId: _project.id,
        ));
      }
    }
    await _sync.deleteProject(_project.id);
    if (!mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(showCost
            ? 'Projet supprimé · −$cost or'
            : 'Projet supprimé')));
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
                        onOpenDetail: _openTaskDetail,
                        onToggleTodayFlag: () async {
                          setState(() => task.todayFlag = !task.todayFlag);
                          await _sync.saveProjectTasks(
                              _project.id, _project.tasks);
                        },
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
                        onOpenDetail: _openTaskDetail,
                        onToggleTodayFlag: () async {
                          setState(() => task.todayFlag = !task.todayFlag);
                          await _sync.saveProjectTasks(
                              _project.id, _project.tasks);
                        },
                      ),
                  ],

                  // Ajouter une tâche (gestion autonome, sans IA)
                  const SizedBox(height: 10),
                  Center(
                    child: TextButton.icon(
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Ajouter une tâche'),
                      onPressed: _addTask,
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

  Future<void> _openTaskDetail(ProjectTask task) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _TaskDetailSheet(
        task: task,
        project: _project,
        sync: _sync,
        onChanged: () => setState(() {}),
      ),
    );
    setState(() {});
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

class _TaskDetailSheet extends StatefulWidget {
  final ProjectTask task;
  final Project project;
  final FirestoreSync sync;
  final VoidCallback onChanged;

  const _TaskDetailSheet({
    required this.task,
    required this.project,
    required this.sync,
    required this.onChanged,
  });

  @override
  State<_TaskDetailSheet> createState() => _TaskDetailSheetState();
}

class _TaskDetailSheetState extends State<_TaskDetailSheet>
    with TickerProviderStateMixin {
  late ProjectTask _task;
  bool _saving = false;
  late TabController _actionTabs;

  @override
  void initState() {
    super.initState();
    _task = widget.task;
    _actionTabs = TabController(length: 2, vsync: this);
    _actionTabs.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _actionTabs.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final tasks = widget.project.tasks
        .map((t) => t.id == _task.id ? _task : t)
        .toList();
    await widget.sync.saveProjectTasks(widget.project.id, tasks);
    widget.onChanged();
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _addAction() async {
    final ctrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nouvelle action'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'Description…'),
          onSubmitted: (v) { if (v.trim().isNotEmpty) Navigator.pop(ctx, v.trim()); },
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          FilledButton(
            onPressed: () {
              if (ctrl.text.trim().isNotEmpty) Navigator.pop(ctx, ctrl.text.trim());
            },
            child: const Text('Ajouter'),
          ),
        ],
      ),
    );
    if (result == null) return;
    setState(() => _task.actions.add(TaskAction(title: result)));
    _save();
  }

  // ── Opérations structurelles (déplacer / promouvoir) ──────────────────────
  // Mêmes helpers FirestoreSync que la vue web : ils relisent Firestore puis
  // écrivent ; ici on reflète le retrait local + on notifie le parent.

  Future<Project?> _pickProject(String title, {String? excludeId}) async {
    final projects = await widget.sync.fetchProjects();
    if (!mounted) return null;
    final candidates = projects
        .where((p) => p.id != excludeId && p.status != 'archived')
        .toList()
      ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Aucun autre projet disponible.')));
      return null;
    }
    return showModalBottomSheet<Project>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(title,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final p in candidates)
                    ListTile(
                      title: Text(p.title),
                      onTap: () => Navigator.pop(ctx, p),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<ProjectTask?> _pickTask(Project project, {String? excludeTaskId}) async {
    final tasks = project.tasks.where((t) => t.id != excludeTaskId).toList();
    if (!mounted) return null;
    if (tasks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('« ${project.title} » n\'a aucune autre tâche.')));
      return null;
    }
    return showModalBottomSheet<ProjectTask>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Tâche cible — ${project.title}',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final t in tasks)
                    ListTile(
                      title: Text(t.title),
                      onTap: () => Navigator.pop(ctx, t),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _moveTaskToAnotherProject() async {
    final target = await _pickProject('Déplacer la tâche vers…',
        excludeId: widget.project.id);
    if (target == null) return;
    setState(() => _saving = true);
    await widget.sync
        .moveTaskToProject(widget.project.id, target.id, _task.id);
    widget.project.tasks.removeWhere((t) => t.id == _task.id);
    widget.onChanged();
    if (!mounted) return;
    Navigator.pop(context); // la tâche a quitté ce projet
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Tâche déplacée vers « ${target.title} ».')));
  }

  Future<void> _moveActionToAnotherTask(TaskAction a) async {
    final target = await _pickProject('Déplacer l\'action vers…');
    if (target == null) return;
    final excludeTaskId = target.id == widget.project.id ? _task.id : null;
    final targetTask = await _pickTask(target, excludeTaskId: excludeTaskId);
    if (targetTask == null) return;
    setState(() => _saving = true);
    await widget.sync.moveActionToTask(
      fromProjectId: widget.project.id,
      fromTaskId: _task.id,
      toProjectId: target.id,
      toTaskId: targetTask.id,
      actionId: a.id,
    );
    _task.actions.removeWhere((x) => x.id == a.id);
    if (target.id == widget.project.id) {
      widget.project.tasks
          .where((t) => t.id == targetTask.id)
          .firstOrNull
          ?.actions
          .add(a);
    }
    widget.onChanged();
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Action déplacée vers « ${targetTask.title} ».')));
  }

  Future<void> _promoteActionToSubproject(TaskAction a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Promouvoir en sous-projet'),
        content: Text(
            'Créer un sous-projet « ${a.title} » sous « ${widget.project.title} » ? '
            'L\'action sera retirée de cette tâche.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Créer')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _saving = true);
    final child = await widget.sync.promoteActionToSubproject(
      parentProjectId: widget.project.id,
      taskId: _task.id,
      actionId: a.id,
    );
    _task.actions.removeWhere((x) => x.id == a.id);
    widget.onChanged();
    if (!mounted) return;
    setState(() => _saving = false);
    if (child != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Sous-projet « ${child.title} » créé.')));
    }
  }

  // ── CRUD tâche (autonome, sans IA) ──────────────────────────────────────────

  Future<void> _renameTask() async {
    final ctrl = TextEditingController(text: _task.title);
    final result = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Renommer la tâche'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(border: OutlineInputBorder()),
          onSubmitted: (v) {
            if (v.trim().isNotEmpty) Navigator.pop(c, v.trim());
          },
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c), child: const Text('Annuler')),
          FilledButton(
            onPressed: () {
              final v = ctrl.text.trim();
              if (v.isNotEmpty) Navigator.pop(c, v);
            },
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (result != null) {
      setState(() => _task.title = result);
      _save();
    }
  }

  Future<void> _editTaskDetails() async {
    var start = _task.startDate;
    DateTime? end = _task.endDate;
    var phaseId = _task.phaseId;
    var milestone = _task.isMilestone;
    final phases = widget.project.phases;

    final saved = await showModalBottomSheet<bool>(
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
              const Text('Modifier la tâche',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.play_arrow_outlined, size: 20),
                title: const Text('Début'),
                trailing: Text(_fmtD(start)),
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
                title: const Text('Échéance'),
                trailing: Text(end != null ? _fmtD(end!) : 'Aucune'),
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
              if (phases.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: DropdownButtonFormField<String?>(
                    value: phases.any((p) => p.id == phaseId) ? phaseId : null,
                    decoration: const InputDecoration(
                        labelText: 'Phase', border: OutlineInputBorder()),
                    items: [
                      const DropdownMenuItem(
                          value: null, child: Text('Aucune phase')),
                      for (final p in phases)
                        DropdownMenuItem(value: p.id, child: Text(p.label)),
                    ],
                    onChanged: (v) => setSB(() => phaseId = v),
                  ),
                ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Jalon (milestone)'),
                value: milestone,
                onChanged: (v) => setSB(() => milestone = v),
              ),
              const SizedBox(height: 8),
              Row(children: [
                const Spacer(),
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Annuler')),
                FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Enregistrer')),
              ]),
            ],
          ),
        ),
      ),
    );
    if (saved != true) return;
    setState(() {
      _task.startDate = start;
      _task.endDate = end;
      _task.phaseId = phaseId;
      _task.groupLabel =
          phases.where((p) => p.id == phaseId).firstOrNull?.label;
      _task.isMilestone = milestone;
    });
    _save();
  }

  /// Repousser l'échéance d'une tâche : date picker (postérieure à l'échéance
  /// actuelle) → coût `deadlinePush` par semaine entamée de décalage. Un Sursis
  /// en stock le rend gratuit (achat-à-l'usage proposé sinon). Repousser sort la
  /// tâche de `lateTasks()` → stoppe le −1/j.
  Future<void> _pushDeadline() async {
    final cur = _task.endDate;
    if (cur == null) return;
    final ref = DateTime(cur.year, cur.month, cur.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: ref.add(const Duration(days: 7)),
      firstDate: ref.add(const Duration(days: 1)),
      lastDate: DateTime(2100),
      helpText: 'Repousser l\'échéance au…',
    );
    if (picked == null || !mounted) return;
    final pickedMid = DateTime(picked.year, picked.month, picked.day);
    final deltaDays = pickedMid.difference(ref).inDays;
    if (deltaDays <= 0) return;
    final weeks = (deltaDays + 6) ~/ 7; // semaines entamées
    // Brouillon = hors économie (report gratuit).
    final billed = widget.project.status != 'draft';
    final cost = billed ? GoldEconomy.deadlinePush * weeks : 0;

    if (cost > 0) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Repousser la deadline ?'),
          content: Text(
              'L\'échéance de « ${_task.title} » passera au ${_fmtD(pickedMid)} '
              '(+$weeks semaine${weeks > 1 ? 's' : ''}).\n\nCoût : $cost or — '
              'gratuit si tu as un Sursis en stock.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Annuler')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text('Repousser (−$cost or)')),
          ],
        ),
      );
      if (proceed != true) return;

      var usedSursis = await widget.sync.consumeSursis();
      if (!usedSursis && mounted) {
        final bought = await offerBuyConsumable(
          context,
          widget.sync,
          itemKey: 'sursis',
          price: GoldEconomy.shopSursis,
          label: 'Sursis de deadline',
          rationale: 'Annule le coût de $cost or de ce report.',
        );
        if (bought) usedSursis = await widget.sync.consumeSursis();
      }
      if (usedSursis) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('⏳ Sursis utilisé — report gratuit.')));
        }
      } else {
        widget.sync.applyGold(GoldLedgerEntry(
          delta: -cost,
          category: 'loss',
          reasonCode: 'deadline_push',
          label: 'Report d\'échéance « ${_task.title} »',
          refType: 'task',
          refId: _task.id,
        ));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Échéance repoussée · −$cost or')));
        }
      }
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Échéance repoussée.')));
    }

    setState(() => _task.endDate = pickedMid);
    await _save();
  }

  Future<void> _deleteTask() async {
    // Brouillon = CRUD libre, suppression gratuite (hors économie).
    final billed = widget.project.status != 'draft';
    final cost = GoldEconomy.deleteTaskCost(_task.actions.length);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer la tâche ?'),
        content: Text(
            'La tâche « ${_task.title} » et ses ${_task.actions.length} action(s) '
            'seront supprimées.${billed ? ' Coût : $cost or.' : ''}'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(billed ? 'Supprimer (−$cost or)' : 'Supprimer'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    widget.project.tasks.removeWhere((t) => t.id == _task.id);
    await widget.sync.saveProjectTasks(widget.project.id, widget.project.tasks);
    if (billed) {
      widget.sync.applyGold(GoldLedgerEntry(
        delta: -cost,
        category: 'loss',
        reasonCode: 'delete_task',
        label: 'Suppression tâche « ${_task.title} »',
        refType: 'task',
        refId: _task.id,
      ));
    }
    widget.onChanged();
    if (!mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(billed ? 'Tâche supprimée · −$cost or' : 'Tâche supprimée')));
  }

  String _fmtD(DateTime d) {
    const m = ['jan', 'fév', 'mar', 'avr', 'mai', 'juin',
                'juil', 'aoû', 'sep', 'oct', 'nov', 'déc'];
    return '${d.day} ${m[d.month - 1]} ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final todoActions = _task.actions.where((a) => !a.done).toList();
    final doneActions = _task.actions.where((a) => a.done).toList();
    final allDone = _task.actions.isNotEmpty &&
        _task.actions.every((a) => a.done);
    final isDone = _task.status == 'done';
    final isOnFaitTab = _actionTabs.index == 1;

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      maxChildSize: 0.92,
      minChildSize: 0.4,
      expand: false,
      builder: (_, scroll) => Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: _renameTask,
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(children: [
                        Flexible(
                          child: Text(_task.title,
                              style: const TextStyle(
                                  fontSize: 17, fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(width: 5),
                        Icon(Icons.edit_outlined,
                            size: 13, color: cs.onSurface.withOpacity(.3)),
                      ]),
                    ),
                  ),
                ),
                if (_saving)
                  const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                PopupMenuButton<String>(
                  tooltip: 'Options',
                  icon: Icon(Icons.more_vert,
                      size: 20, color: cs.onSurface.withOpacity(.45)),
                  onSelected: (v) {
                    if (v == 'edit') _editTaskDetails();
                    if (v == 'push') _pushDeadline();
                    if (v == 'move_task') _moveTaskToAnotherProject();
                    if (v == 'delete') _deleteTask();
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 'edit',
                      child: Text('Modifier (dates, phase…)'),
                    ),
                    if (_task.endDate != null)
                      const PopupMenuItem(
                        value: 'push',
                        child: Text('Repousser la deadline'),
                      ),
                    const PopupMenuItem(
                      value: 'move_task',
                      child: Text('Déplacer vers un autre projet'),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Text('Supprimer la tâche'),
                    ),
                  ],
                ),
                // Toggle done
                TextButton.icon(
                  icon: Icon(
                    isDone ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
                    color: isDone ? Colors.green : cs.onSurface.withOpacity(.4),
                    size: 18,
                  ),
                  label: Text(isDone ? 'Terminée' : 'À faire',
                      style: TextStyle(
                          color: isDone ? Colors.green : cs.onSurface.withOpacity(.5))),
                  onPressed: () {
                    setState(() =>
                        _task.status = isDone ? 'pending' : 'done');
                    _save();
                  },
                ),
              ],
            ),
          ),
          Divider(height: 1, color: cs.outlineVariant.withOpacity(.3)),

          // Onglets À faire / Fait
          TabBar(
            controller: _actionTabs,
            tabs: [
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('À faire'),
                    if (todoActions.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: cs.primary.withOpacity(.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${todoActions.length}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: cs.primary,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Fait'),
                    if (doneActions.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${doneActions.length}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Colors.green,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
            indicatorSize: TabBarIndicatorSize.tab,
            dividerColor: Colors.transparent,
            labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
          Divider(height: 1, color: cs.outlineVariant.withOpacity(.2)),

          // Liste des actions (filtrée par onglet)
          Expanded(
            child: isOnFaitTab
                // ── Onglet Fait ──────────────────────────────────────────
                ? (doneActions.isEmpty
                    ? Center(
                        child: Text('Aucune action réalisée.',
                            style: TextStyle(
                                color: cs.onSurface.withOpacity(.35),
                                fontStyle: FontStyle.italic)),
                      )
                    : ListView.builder(
                        controller: scroll,
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                        itemCount: doneActions.length,
                        itemBuilder: (ctx, i) {
                          final a = doneActions[i];
                          return Dismissible(
                            key: ValueKey('done_${a.title}_$i'),
                            direction: DismissDirection.endToStart,
                            background: Container(
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 16),
                              color: cs.errorContainer,
                              child: Icon(Icons.delete_outline, color: cs.error),
                            ),
                            onDismissed: (_) {
                              setState(() => _task.actions.remove(a));
                              _save();
                            },
                            child: ListTile(
                              dense: true,
                              contentPadding: const EdgeInsets.only(left: 0, right: 4),
                              leading: Checkbox(
                                value: true,
                                activeColor: Colors.green,
                                onChanged: (v) {
                                  setState(() {
                                    a.done = false;
                                    a.doneAt = null;
                                  });
                                  _save();
                                },
                              ),
                              title: Text(a.title,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: cs.onSurface.withOpacity(.35),
                                    decoration: TextDecoration.lineThrough,
                                  )),
                            ),
                          );
                        },
                      ))
                // ── Onglet À faire ───────────────────────────────────────
                : Column(
                    children: [
                      Expanded(
                        child: todoActions.isEmpty
                            ? Center(
                                child: Text('Aucune action à faire.',
                                    style: TextStyle(
                                        color: cs.onSurface.withOpacity(.35),
                                        fontStyle: FontStyle.italic)),
                              )
                            : ReorderableListView.builder(
                                scrollController: scroll,
                                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                                buildDefaultDragHandles: false,
                                itemCount: todoActions.length,
                                onReorder: (oldIndex, newIndex) {
                                  setState(() {
                                    if (newIndex > oldIndex) newIndex--;
                                    final movedItem = todoActions[oldIndex];
                                    final targetItem = newIndex < todoActions.length
                                        ? todoActions[newIndex]
                                        : null;
                                    _task.actions.remove(movedItem);
                                    if (targetItem == null) {
                                      _task.actions.add(movedItem);
                                    } else {
                                      final targetIdx = _task.actions.indexOf(targetItem);
                                      _task.actions.insert(targetIdx, movedItem);
                                    }
                                  });
                                  _save();
                                },
                                itemBuilder: (ctx, i) {
                                  final a = todoActions[i];
                                  return Dismissible(
                                    key: ValueKey('todo_${a.title}_$i'),
                                    direction: DismissDirection.endToStart,
                                    background: Container(
                                      alignment: Alignment.centerRight,
                                      padding: const EdgeInsets.only(right: 16),
                                      color: cs.errorContainer,
                                      child: Icon(Icons.delete_outline, color: cs.error),
                                    ),
                                    onDismissed: (_) {
                                      setState(() => _task.actions.remove(a));
                                      _save();
                                      final billed =
                                          widget.project.status != 'draft';
                                      if (billed) {
                                        widget.sync.applyGold(GoldLedgerEntry(
                                          delta: -GoldEconomy.deleteAction,
                                          category: 'loss',
                                          reasonCode: 'delete_action',
                                          label:
                                              'Suppression action « ${a.title} »',
                                          refType: 'task',
                                          refId: _task.id,
                                        ));
                                      }
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(SnackBar(
                                        duration: const Duration(seconds: 2),
                                        content: Text(billed
                                            ? 'Action supprimée · −${GoldEconomy.deleteAction} or'
                                            : 'Action supprimée'),
                                      ));
                                    },
                                    child: ListTile(
                                      key: ValueKey('tile_todo_${a.title}_$i'),
                                      dense: true,
                                      contentPadding: const EdgeInsets.only(left: 0, right: 4),
                                      onLongPress: () async {
                                        final ctrl = TextEditingController(text: a.title);
                                        final result = await showDialog<String>(
                                          context: context,
                                          builder: (c) => AlertDialog(
                                            title: const Text('Modifier l\'action'),
                                            content: TextField(
                                              controller: ctrl,
                                              autofocus: true,
                                              decoration: const InputDecoration(
                                                  border: OutlineInputBorder()),
                                              onSubmitted: (v) {
                                                if (v.trim().isNotEmpty)
                                                  Navigator.pop(c, v.trim());
                                              },
                                            ),
                                            actions: [
                                              TextButton(
                                                  onPressed: () => Navigator.pop(c),
                                                  child: const Text('Annuler')),
                                              FilledButton(
                                                onPressed: () {
                                                  final v = ctrl.text.trim();
                                                  if (v.isNotEmpty) Navigator.pop(c, v);
                                                },
                                                child: const Text('Enregistrer'),
                                              ),
                                            ],
                                          ),
                                        );
                                        ctrl.dispose();
                                        if (result != null) {
                                          setState(() => a.title = result);
                                          _save();
                                        }
                                      },
                                      leading: Checkbox(
                                        value: false,
                                        onChanged: (v) {
                                          setState(() {
                                            a.done = v ?? false;
                                            a.doneAt = a.done ? DateTime.now() : null;
                                          });
                                          _save();
                                        },
                                      ),
                                      title: Text(a.title,
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: cs.onSurface,
                                          )),
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          PopupMenuButton<String>(
                                            tooltip: 'Réorganiser',
                                            icon: Icon(Icons.more_vert,
                                                size: 18,
                                                color: cs.onSurface
                                                    .withOpacity(.3)),
                                            padding: EdgeInsets.zero,
                                            onSelected: (v) {
                                              if (v == 'move')
                                                _moveActionToAnotherTask(a);
                                              if (v == 'promote')
                                                _promoteActionToSubproject(a);
                                            },
                                            itemBuilder: (_) => const [
                                              PopupMenuItem(
                                                value: 'move',
                                                child: Text(
                                                    'Déplacer vers une autre tâche'),
                                              ),
                                              PopupMenuItem(
                                                value: 'promote',
                                                child: Text(
                                                    'Promouvoir en sous-projet'),
                                              ),
                                            ],
                                          ),
                                          ReorderableDragStartListener(
                                            index: i,
                                            child: Icon(Icons.drag_handle,
                                                color: cs.onSurface
                                                    .withOpacity(.3)),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
          ),

          // Footer (uniquement sur l'onglet À faire)
          Padding(
            padding: EdgeInsets.fromLTRB(
                16, 8, 16, MediaQuery.of(context).padding.bottom + 12),
            child: Row(
              children: [
                if (!isOnFaitTab) ...[
                  TextButton.icon(
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Ajouter une action'),
                    onPressed: _addAction,
                  ),
                  if (_task.actions.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Text(
                      'Appui long = modifier',
                      style: TextStyle(
                        fontSize: 11,
                        color: cs.onSurface.withOpacity(.3),
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ],
                const Spacer(),
                if (!isDone && (allDone || _task.actions.isEmpty))
                  FilledButton.icon(
                    icon: const Icon(Icons.check_rounded, size: 16),
                    label: const Text('Valider la tâche'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.green.shade600,
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: () {
                      setState(() => _task.status = 'done');
                      _save();
                      Navigator.pop(context);
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
    );
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
  final Future<void> Function(ProjectTask)? onOpenDetail;
  final VoidCallback? onToggleTodayFlag;

  const _TaskTile({
    super.key,
    required this.task,
    required this.isTarget,
    required this.today,
    required this.cs,
    required this.onToggle,
    this.onOpenDetail,
    this.onToggleTodayFlag,
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
        onTap: task.isMilestone ? null : () => onOpenDetail?.call(task) ?? onToggle(),
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
              // Étoile priorité du jour
              GestureDetector(
                onTap: onToggleTodayFlag,
                child: Padding(
                  padding: const EdgeInsets.only(left: 6, top: 1),
                  child: Icon(
                    task.todayFlag
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    size: 16,
                    color: task.todayFlag
                        ? Colors.amber.shade600
                        : cs.onSurface.withOpacity(.25),
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

/// Bandeau « brouillon » : tant que le projet n'est pas validé, il reste hors
/// économie d'Or et hors score. Le bouton bascule le projet en actif.
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
              'Brouillon — modifie librement, hors or et hors score.',
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
