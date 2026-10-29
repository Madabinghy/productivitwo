import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/actions_logic.dart' show actionDueLabel, effectiveDueDate, flowTaskOf, focusLabel, kFlowTaskId;
import 'package:productivitwo_v1/utils/checklist_logic.dart' show setActionDone;
import 'package:productivitwo_v1/utils/default_estimate.dart' show defaultEstimateFor;
import 'package:productivitwo_v1/utils/duration_fmt.dart' show fmtMin;
import 'package:productivitwo_v1/widgets/confirm_done.dart' show confirmDone;
import 'package:productivitwo_v1/widgets/focus_day_sheet.dart' show pickFocusDay, FocusDay, FocusClear;
import 'package:productivitwo_v1/utils/interventions.dart';
import 'package:productivitwo_v1/utils/palier_colors.dart';
import 'package:productivitwo_v1/utils/project_health.dart' show HealthKind, ganttOrder;
import 'package:productivitwo_v1/utils/project_moment.dart';
import 'package:productivitwo_v1/widgets/fiche.dart';
import 'package:productivitwo_v1/widgets/action_focus_screen.dart' show showActionFocusScreen;
import 'package:productivitwo_v1/widgets/project_sheet.dart';
import 'package:productivitwo_v1/widgets/task_picker_sheet.dart' show showTaskPicker, kPickFlowTask;
import 'package:productivitwo_v1/widgets/task_fiche_sheet.dart' show stripLeadingEmoji;
import 'package:productivitwo_v1/widgets/session_player_screen.dart';
import 'package:productivitwo_v1/widgets/status_row.dart' show ExpectedBar;

/// Fiche projet « une carte, une fiche » (2026-10) : en-tête + chip d'état,
/// CETTE SEMAINE (actions à 7 jours / prépa de la séance), DEPUIS LE DÉBUT ·
/// AVANCEMENT (tâches faites avec le repère « attendu aujourd'hui »),
/// PROCHAINE SÉANCE, gestes (prochaine action, plan d'action, terminer /
/// archiver / rouvrir). Le plan détaillé reste `showProjectSheet`.
/// Retourne true si le projet a changé de statut.
Future<bool> showProjectFiche(
  BuildContext context, {
  required Project project,
  required List<Project> allProjects,
  required List<Domain> domains,
  required List<Activity> activities,
  required List<Session> sessions,
  FirestoreSync? sync,
  AppLogic? logic,
  void Function(Activity activity, Project project, ProjectTask task)? onStartTimer,
  /// Ouverte depuis la tuile PROJETS d'Aujourd'hui : section DÉCISIONS qui
  /// sort le projet de la tête (passer pour aujourd'hui, viser demain, pause).
  VoidCallback? onSkipToday,
  /// Tap sur une action (et « Prochaine action ») = la page focus de l'action,
  /// pour la travailler tout de suite (tuile PROJETS d'Aujourd'hui).
  bool actionsOpenFocus = false,
}) async {
  final changed = await showFiche<bool>(context,
      builder: (ctx, scroll) => _ProjectFiche(
            project: project,
            allProjects: allProjects,
            domains: domains,
            activities: activities,
            sessions: sessions,
            sync: sync ?? FirestoreSync(),
            logic: logic,
            onStartTimer: onStartTimer,
            onSkipToday: onSkipToday,
            actionsOpenFocus: actionsOpenFocus,
            scroll: scroll,
          ));
  return changed ?? false;
}

class _ProjectFiche extends StatefulWidget {
  final Project project;
  final List<Project> allProjects;
  final List<Domain> domains;
  final List<Activity> activities;
  final List<Session> sessions;
  final FirestoreSync sync;
  final AppLogic? logic;
  final void Function(Activity activity, Project project, ProjectTask task)? onStartTimer;
  final VoidCallback? onSkipToday;
  final bool actionsOpenFocus;
  final ScrollController scroll;
  const _ProjectFiche({
    required this.project,
    required this.allProjects,
    required this.domains,
    required this.activities,
    required this.sessions,
    required this.sync,
    this.logic,
    required this.onStartTimer,
    this.onSkipToday,
    this.actionsOpenFocus = false,
    required this.scroll,
  });

  @override
  State<_ProjectFiche> createState() => _ProjectFicheState();
}

class _ProjectFicheState extends State<_ProjectFiche> {
  bool _changed = false;
  Project get p => widget.project;

  Future<void> _setStatus(String status) async {
    if (status == 'done') {
      final open = p.tasks.where((t) => t.id != 'gtd-flow' && t.status != 'done' && t.status != 'skipped').length;
      if (open > 0) {
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Terminer le projet ?'),
            content: Text('Il reste $open tâche${open > 1 ? 's' : ''} ouverte${open > 1 ? 's' : ''}. Elles sortiront des Actions.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Terminer')),
            ],
          ),
        );
        if (ok != true) return;
      }
    }
    p.status = status;
    await widget.sync.saveProject(p);
    _changed = true;
    if (mounted) Navigator.pop(context, true);
  }

  void _skipToday() {
    widget.onSkipToday?.call();
    Navigator.pop(context, true);
  }

  Future<void> _focusTomorrow(TaskAction a) async {
    final t = DateTime.now().add(const Duration(days: 1));
    a.focusDate = DateTime(t.year, t.month, t.day);
    await widget.sync.patchActionOf(p, a);
    _skipToday();
  }

  Future<void> _pause() async {
    p.paused = true;
    await widget.sync.saveProject(p);
    _changed = true;
    if (mounted) Navigator.pop(context, true);
  }

  Widget _decisions(ProjectMoment m) {
    final next = m.next;
    final rows = <({IconData icon, String title, String detail, VoidCallback onTap})>[
      (icon: Icons.skip_next_rounded, title: 'Suivant', detail: 'pas aujourd’hui · un autre projet passe en tête', onTap: _skipToday),
      if (next != null)
        (icon: Icons.wb_sunny_outlined, title: 'Viser demain', detail: '« ${next.action.title} » visée demain, le projet sort de la tête', onTap: () => _focusTomorrow(next.action)),
      (icon: Icons.pause_circle_outline, title: 'Mettre en pause', detail: 'hors des classements jusqu’à la reprise', onTap: _pause),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const FicheTitle('DÉCISIONS'),
      for (final r in rows)
        FicheStep(
          title: r.title,
          detail: r.detail,
          onTap: r.onTap,
          trailing: Icon(r.icon, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .6)),
        ),
    ]);
  }

  // ── CRUD des actions (retour user 2026-10-30) ─────────────────────────────
  // Ajouter (choix de la tâche), appui long = renommer · estimation · note ·
  // jour visé · faite · supprimer. Une action seule passe par patchActionOf,
  // la structure (ajout / suppression) par saveProjectTasks (fusion 3 voies).

  bool _showAll = false;

  Future<void> _saveTasks() async {
    await widget.sync.saveProjectTasks(p.id, p.tasks);
    _changed = true;
    if (mounted) setState(() {});
  }

  Future<void> _patch(TaskAction a) async {
    await widget.sync.patchActionOf(p, a);
    _changed = true;
    if (mounted) setState(() {});
  }

  List<ProjectTask> get _openTasks => [
        for (final t in ganttOrder(p))
          if (t.status != 'done' && t.status != 'skipped') t,
      ];

  Future<String?> _askText(String title, {String initial = '', String hint = '', bool multiline = false}) async {
    final ctrl = TextEditingController(text: initial);
    final v = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          minLines: multiline ? 3 : 1,
          maxLines: multiline ? 8 : 1,
          decoration: InputDecoration(hintText: hint),
          onSubmitted: multiline ? null : (v) => Navigator.pop(d, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(d, ctrl.text), child: const Text('OK')),
        ],
      ),
    );
    ctrl.dispose();
    return v?.trim();
  }

  Future<void> _addAction(ProjectMoment m) async {
    final tasks = _openTasks;
    ProjectTask? target = m.next?.task ?? tasks.firstOrNull;
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, setD) => AlertDialog(
          scrollable: true,
          title: const Text('Nouvelle action'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(
              controller: ctrl,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(hintText: 'Verbe + objet, ≤ 8 mots'),
              onSubmitted: (v) {
                if (v.trim().isNotEmpty) Navigator.pop(d, true);
              },
            ),
            const SizedBox(height: 14),
            const Text('Dans la tâche', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            // Sélecteur lisible (phases, avancement, échéance) au lieu d'une
            // liste déroulante plate.
            Material(
              color: Theme.of(d).colorScheme.onSurface.withValues(alpha: .06),
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () async {
                  final id = await showTaskPicker(d, project: p, currentTaskId: target?.id ?? kPickFlowTask);
                  if (id == null) return;
                  setD(() => target = id == kPickFlowTask ? null : tasks.where((t) => t.id == id).firstOrNull);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(children: [
                    Expanded(
                      child: Text(target == null ? 'Au fil de l\'eau' : stripLeadingEmoji(target!.title),
                          maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    ),
                    const Icon(Icons.unfold_more_rounded, size: 20),
                  ]),
                ),
              ),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Annuler')),
            FilledButton(
                onPressed: () {
                  if (ctrl.text.trim().isNotEmpty) Navigator.pop(d, true);
                },
                child: const Text('Ajouter')),
          ],
        ),
      ),
    );
    final title = ctrl.text.trim();
    ctrl.dispose();
    if (ok != true || title.isEmpty) return;
    final task = target ?? flowTaskOf(p);
    task.actions.add(TaskAction(title: title, estimatedMin: defaultEstimateFor(title)));
    await _saveTasks();
  }

  Future<void> _editAction(ProjectTask task, TaskAction a) async {
    final cs = Theme.of(context).colorScheme;
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(a.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            ),
          ),
          ListTile(leading: const Icon(Icons.edit_outlined), title: const Text('Renommer'), onTap: () => Navigator.pop(ctx, 'rename')),
          ListTile(
              leading: const Icon(Icons.timer_outlined),
              title: const Text('Estimation'),
              subtitle: a.estimatedMin == null ? null : Text(fmtMin(a.estimatedMin!)),
              onTap: () => Navigator.pop(ctx, 'estimate')),
          ListTile(
              leading: const Icon(Icons.notes_outlined),
              title: const Text('Note'),
              subtitle: a.note == null || a.note!.isEmpty ? null : Text(a.note!, maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: () => Navigator.pop(ctx, 'note')),
          ListTile(
              leading: const Icon(Icons.wb_sunny_outlined),
              title: const Text('Jour visé'),
              subtitle: a.focusDate == null ? null : Text(focusLabel(a.focusDate!, DateTime.now())),
              onTap: () => Navigator.pop(ctx, 'focus')),
          ListTile(leading: const Icon(Icons.check_circle_outline), title: const Text('Marquer faite'), onTap: () => Navigator.pop(ctx, 'done')),
          ListTile(
              leading: Icon(Icons.delete_outline, color: cs.error),
              title: Text('Supprimer l\'action', style: TextStyle(color: cs.error)),
              onTap: () => Navigator.pop(ctx, 'delete')),
        ]),
      ),
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'rename':
        final v = await _askText('Renommer l\'action', initial: a.title);
        if (v != null && v.isNotEmpty && v != a.title) {
          a.title = v;
          await _patch(a);
        }
      case 'estimate':
        final v = await _pickEstimate(a.estimatedMin);
        if (v != null) {
          a.estimatedMin = v == 0 ? null : v;
          await _patch(a);
        }
      case 'note':
        final v = await _askText('Note', initial: a.note ?? '', hint: 'Le détail, les consignes…', multiline: true);
        if (v != null && v != (a.note ?? '')) {
          a.note = v.isEmpty ? null : v;
          await _patch(a);
        }
      case 'focus':
        final pick = await pickFocusDay(context, current: a.focusDate);
        if (pick == null) return;
        a.focusDate = switch (pick) {
          FocusDay(:final day) => day,
          FocusClear() => null,
        };
        await _patch(a);
      case 'done':
        if (!await confirmDone(context, title: a.title)) return;
        setActionDone(a, true);
        await _patch(a);
      case 'delete':
        final ok = await showDialog<bool>(
          context: context,
          builder: (d) => AlertDialog(
            title: const Text('Supprimer l\'action ?'),
            content: Text('« ${a.title} » sera retirée de « ${task.title} ».'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Annuler')),
              FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Supprimer')),
            ],
          ),
        );
        if (ok != true) return;
        task.actions.removeWhere((x) => identical(x, a) || x.id == a.id);
        await _saveTasks();
    }
  }

  /// 0 = retirer l'estimation ; null = annulé.
  Future<int?> _pickEstimate(int? current) => showModalBottomSheet<int>(
        context: context,
        showDragHandle: true,
        builder: (ctx) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Estimation', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final v in const [5, 10, 15, 25, 45, 60, 90, 120])
                  ChoiceChip(label: Text(fmtMin(v)), selected: current == v, onSelected: (_) => Navigator.pop(ctx, v)),
                if (current != null) ActionChip(label: const Text('Retirer'), onPressed: () => Navigator.pop(ctx, 0)),
              ]),
            ]),
          ),
        ),
      );

  Widget _actionStep(ProjectMoment m, ProjectTask task, TaskAction a, DateTime? due, DateTime now) => FicheStep(
        title: a.title,
        detail: [
          task.id == kFlowTaskId ? 'Au fil de l\'eau' : task.title,
          if (due != null) actionDueLabel(due, now),
          if (a.focusDate != null) '☀ ${focusLabel(a.focusDate!, now)}',
          if (a.estimatedMin != null) '≈ ${fmtMin(a.estimatedMin!)}',
        ].join(' · '),
        current: identical(a, m.next?.action) || a.id == m.next?.action.id,
        onTap: () => _openAction(task, a),
        onLongPress: () => _editAction(task, a),
      );

  void _openPlan({String? taskId}) =>
      showProjectSheet(context,
          project: p,
          domains: widget.domains,
          targetTaskId: taskId,
          activities: widget.activities,
          sessions: widget.sessions,
          logic: widget.logic,
          onStartTimer: widget.onStartTimer);

  /// Tap sur une action = SA tâche, l'action dépliée (pas tout le plan) ;
  /// depuis la tuile PROJETS, la page focus de l'action.
  Future<void> _openAction(ProjectTask task, TaskAction action) async {
    final logic = widget.logic;
    if (widget.actionsOpenFocus && logic != null) {
      final chrono = widget.activities.where((a) => a.id == (action.linkedActivityId ?? p.linkedActivityId)).firstOrNull;
      await showActionFocusScreen(context, logic: logic, action: action, project: p, task: task, chronoActivity: chrono, sync: widget.sync);
      if (mounted) setState(() {});
      return;
    }
    await showTaskDetail(context,
        project: p,
        task: task,
        activities: widget.activities,
        allProjects: widget.allProjects,
        sync: widget.sync,
        logic: widget.logic,
        expandActionId: action.id,
        onStartTimer: widget.onStartTimer);
    if (mounted) setState(() {});
  }

  void _startNext(ProjectMoment m) {
    final n = m.next;
    if (n == null) {
      _openPlan();
      return;
    }
    final logic = widget.logic;
    if (logic != null) {
      final chrono = widget.activities.where((a) => a.id == (n.action.linkedActivityId ?? p.linkedActivityId)).firstOrNull;
      showActionFocusScreen(context, logic: logic, action: n.action, project: p, task: n.task, chronoActivity: chrono, sync: widget.sync)
          .then((_) {
        if (mounted) setState(() {});
      });
      return;
    }
    final act = widget.activities.where((a) => a.id == (n.action.linkedActivityId ?? p.linkedActivityId)).firstOrNull;
    if (act != null && widget.onStartTimer != null) {
      Navigator.pop(context, _changed);
      widget.onStartTimer!(act, p, n.task);
      return;
    }
    _openAction(n.task, n.action);
  }

  void _openSession(Intervention s) {
    final native = s.native;
    if (native == null) {
      _openPlan(taskId: s.milestone.id);
      return;
    }
    showSessionPlayer(context,
        project: p,
        intervention: native,
        sessionTask: s.milestone,
        sync: widget.sync,
        onStartTimer: widget.onStartTimer == null
            ? null
            : () {
                final act = widget.activities.where((a) => a.id == p.linkedActivityId).firstOrNull;
                if (act != null) widget.onStartTimer!(act, p, s.milestone);
              });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final m = projectMoment(p, widget.allProjects, widget.sessions, now);
    final st = palierColor(m.pctInt);
    final plan = m.plan;
    final s = m.session;
    final kpiParts = <String>[
      if (m.rootTitle != null) 'Pour ${m.rootTitle}',
      '${plan.total} tâche${plan.total > 1 ? 's' : ''}',
      if (s != null) sessionLabel(s, now) + (s.timeRange != null ? ' · ${s.timeRange}' : ''),
      if (p.endDate != null && s == null) 'échéance ${_date(p.endDate!)}',
    ];
    final week = m.weekActions;
    final inWeek = {for (final a in week) a.action.id};
    final rest = [
      for (final t in _openTasks)
        for (final a in t.actions)
          if (!a.done && !inWeek.contains(a.id)) (task: t, action: a),
    ];
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _changed);
      },
      child: ListView(
        controller: widget.scroll,
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
        children: [
          FicheHeader(
            title: p.title,
            chip: p.status == 'done' ? 'terminé' : (p.status == 'archived' ? 'en veille' : m.stateLabel),
            chipColor: p.status == 'active' ? st : kPalierMuted,
            kpi: kpiParts.join(' · '),
          ),
          // Décisions en tête (retour user 2026-10-30) : passer, viser demain, pause.
          if (p.status == 'active' && widget.onSkipToday != null) _decisions(m),
          if (p.status == 'active') ...[
            FicheTitle('CETTE SEMAINE',
                trailing: FicheDelta(
                    week.isEmpty ? 'rien d\'échu à 7 jours' : '${week.length} action${week.length > 1 ? 's' : ''}${m.sessionSoon ? ' avant la séance' : ''}',
                    color: week.any((a) => a.due != null && a.due!.isBefore(DateTime(now.year, now.month, now.day))) ? kPalierCoral : st)),
            if (week.isEmpty)
              FicheNote(m.next == null
                  ? 'Aucune action ouverte : ajoute la prochaine.'
                  : 'Rien d\'échu cette semaine. Prochaine action : ${m.next!.action.title}.')
            else
              for (final a in week) _actionStep(m, a.task, a.action, a.due, now),
            if (_showAll)
              for (final e in rest) _actionStep(m, e.task, e.action, effectiveDueDate(e.action, e.task), now),
            Row(children: [
              TextButton.icon(onPressed: () => _addAction(m), icon: const Icon(Icons.add, size: 18), label: const Text('Ajouter une action')),
              const Spacer(),
              if (rest.isNotEmpty)
                TextButton(
                  onPressed: () => setState(() => _showAll = !_showAll),
                  child: Text(_showAll ? 'Masquer les autres' : 'Toutes · + ${rest.length}'),
                ),
            ]),
            if (week.isNotEmpty || rest.isNotEmpty)
              Text('Appui long sur une action : renommer, estimer, noter, supprimer.',
                  style: TextStyle(fontSize: 11.5, color: cs.onSurface.withValues(alpha: .5))),
          ],
          FicheTitle('DEPUIS LE DÉBUT · AVANCEMENT', trailing: FicheDelta(m.upcoming ? 'démarre plus tard' : m.deltaLabel, color: st)),
          ExpectedBar(done: plan.done, total: plan.total, expected: plan.expected, color: st),
          const SizedBox(height: 6),
          Text(
            '${plan.done} tâche${plan.done > 1 ? 's' : ''} faite${plan.done > 1 ? 's' : ''} · attendu aujourd\'hui ${plan.expected} · ${plan.total} au total',
            style: TextStyle(fontSize: 12.5, color: cs.onSurface.withValues(alpha: .6)),
          ),
          if (m.health.kind == HealthKind.stalled)
            Text('Aucun signe de vie depuis ${m.health.count} j', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: kPalierCoral)),
          if (s != null) ...[
            FicheTitle('PROCHAINE SÉANCE', trailing: _prepChip(s)),
            FicheStep(
              title: s.title,
              detail: '${sessionLabel(s, now)}${s.timeRange != null ? ' · ${s.timeRange}' : ''}${s.native?.place != null ? ' · ${s.native!.place}' : ''}',
              current: m.sessionSoon,
              onTap: () => _openSession(s),
              trailing: Icon(Icons.play_circle_outline, color: cs.primary),
            ),
            if (s.prep != null)
              FicheStep(
                title: '📝 Prépa · ${s.prepTotal - s.prepOpen} / ${s.prepTotal}',
                detail: s.prepState == PrepState.ready
                    ? 'prête'
                    : s.prepState == PrepState.readyToPrint
                        ? 'reste à imprimer'
                        : s.prepState == PrepState.done
                            ? 'faite'
                            : 'en cours',
                done: s.prepState == PrepState.done,
                onTap: () => _openPlan(taskId: s.prep!.id),
              ),
          ],
          if (p.status == 'active')
            FicheActions(
              // Le bouton dit ce qu'il ouvre : la prochaine action, dans sa page
              // focus (le chrono s'y lance explicitement, jamais d'ici).
              primaryLabel: m.next == null ? 'Définir la prochaine action' : m.next!.action.title,
              primaryIcon: m.next == null ? Icons.add : Icons.play_arrow_rounded,
              onPrimary: () => _startNext(m),
              secondary: [
                (label: 'Déplier le projet', onTap: () => _openPlan()),
                (label: 'Terminer', onTap: () => _setStatus('done')),
                (label: 'Mettre en veille', onTap: () => _setStatus('archived')),
              ],
            )
          else
            FicheActions(
              primaryLabel: 'Rouvrir',
              primaryIcon: Icons.unarchive_outlined,
              onPrimary: () => _setStatus('active'),
              secondary: [(label: 'Plan d\'action', onTap: () => _openPlan())],
            ),
          if (m.next != null && p.status == 'active')
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text('Prochaine action · ${m.next!.task.title} · ouvre la page focus',
                  style: TextStyle(fontSize: 12.5, color: cs.onSurface.withValues(alpha: .6))),
            ),
        ],
      ),
    );
  }

  Widget _prepChip(Intervention s) {
    final (label, pct) = switch (s.prepState) {
      PrepState.none => ('sans prépa', 100),
      PrepState.todo => ('prépa ${s.prepTotal - s.prepOpen} / ${s.prepTotal}', 50),
      PrepState.readyToPrint => ('à imprimer', 70),
      PrepState.ready => ('prête', 100),
      PrepState.done => ('prête', 100),
    };
    return FicheDelta(label, color: palierColor(pct));
  }

  String _date(DateTime d) {
    const months = ['janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'];
    return '${d.day} ${months[d.month - 1]}';
  }
}
