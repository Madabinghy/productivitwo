import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/domain_colors.dart';
import 'package:productivitwo_v1/utils/engagement_stats.dart';
import 'package:productivitwo_v1/utils/folder_merge.dart';
import 'package:productivitwo_v1/utils/objective_progress.dart';
import 'package:productivitwo_v1/utils/project_health.dart';
import 'package:productivitwo_v1/utils/today_logic.dart';
import 'package:productivitwo_v1/utils/week_planner.dart';
import 'package:productivitwo_v1/web/project_edit_dialog.dart';
import 'package:productivitwo_v1/web/quick_add_action_dialog.dart';
import 'package:productivitwo_v1/web/theme_tokens.dart';
import 'package:productivitwo_v1/widgets/objective_edit_sheet.dart';

// Onglet Projets (refonte web § 4.1–4.4) : en-tête + recherche + Nouveau
// projet · carte Objectif · filtres domaine / En veille / Archivés · tableau
// des projets (avancement, prochaine action cochable, échéance, état, 7 jours).

const _tabular = [FontFeature.tabularFigures()];
const _kDayLong = ['lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche'];

String _fmtHm(int min) {
  final h = min ~/ 60, m = min % 60;
  if (min == 0) return '—';
  if (h == 0) return '$m min';
  return m == 0 ? '$h h' : '$h h ${m.toString().padLeft(2, '0')}';
}

String _ddmm(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';

enum _Mode { active, paused, archived }

class ProjectsView extends StatefulWidget {
  final List<Project> projects;
  final List<Domain> domains;
  final List<Activity> activities;
  final List<StrategicObjective> objectives;
  final List<Session> recentSessions;
  final List<HabitHit> recentHits;
  final FirestoreSync sync;
  final VoidCallback onRefresh;
  final void Function(Project project, {String? taskId}) onOpenProject;

  const ProjectsView({
    super.key,
    required this.projects,
    required this.domains,
    required this.activities,
    required this.objectives,
    required this.recentSessions,
    required this.recentHits,
    required this.sync,
    required this.onRefresh,
    required this.onOpenProject,
  });

  @override
  State<ProjectsView> createState() => _ProjectsViewState();
}

class _ProjectsViewState extends State<ProjectsView> {
  String _query = '';
  String? _domainId;
  _Mode _mode = _Mode.active;
  bool _creating = false;
  // Dossiers (clients) dépliés dans le tableau ; repliés par défaut.
  final Set<String> _openFolders = {};
  // Blocs de la semaine courante, pour « planifiée demain 9 h ».
  final Map<String, List<ScheduleBlock>> _byDay = {};
  final List<StreamSubscription<DailySchedule?>> _subs = [];

  DateTime get _today => dateOnly(DateTime.now());

  @override
  void initState() {
    super.initState();
    for (final d in weekDates(weekStart(DateTime.now()))) {
      final key = ymdOf(d);
      _subs.add(widget.sync.streamDailySchedule(key).listen((s) {
        if (!mounted) return;
        setState(() => _byDay[key] =
            s?.blocks.where((b) => b.status != 'deleted').toList() ?? []);
      }));
    }
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  // ── Données ─────────────────────────────────────────────────────────────────

  List<Project> get _active =>
      widget.projects.where((p) => p.status != 'archived' && !p.paused).toList();
  List<Project> get _paused =>
      widget.projects.where((p) => p.status != 'archived' && p.paused).toList();
  List<Project> get _archived =>
      widget.projects.where((p) => p.status == 'archived').toList();

  /// Projet tel qu'il est jugé et affiché : la vue fusionnée pour un dossier
  /// (avancement, prochaine action, 7 jours cumulés), lui-même sinon.
  Project _display(Project p) => isFolder(p, widget.projects) ? mergeFolder(p, widget.projects).view : p;

  /// Sous-projets d'un dossier présents dans la liste courante.
  List<Project> _childrenOf(Project folder, List<Project> listed) =>
      folderChildren(folder, widget.projects).where((c) => listed.any((p) => p.id == c.id)).toList();

  List<Project> get _listed {
    final base = switch (_mode) {
      _Mode.active => _active,
      _Mode.paused => _paused,
      _Mode.archived => _archived,
    };
    final filtered = base
        .where((p) => _domainId == null || p.domainId == _domainId)
        .where((p) => projectMatches(p, _query))
        .toList();
    if (_mode == _Mode.active) {
      final now = DateTime.now();
      final rank = {
        for (final p in filtered)
          p.id: switch (projectHealth(_display(p), widget.recentSessions, now).kind) {
            HealthKind.stalled => 0,
            HealthKind.atRisk => 1,
            HealthKind.onTrack => 2,
            HealthKind.noDeadline => 3,
          }
      };
      filtered.sort((a, b) {
        final r = rank[a.id]!.compareTo(rank[b.id]!);
        if (r != 0) return r;
        if (a.endDate == null) return b.endDate == null ? 0 : 1;
        if (b.endDate == null) return -1;
        return a.endDate!.compareTo(b.endDate!);
      });
    }
    return filtered;
  }

  /// Bloc de la semaine visant [taskId], le plus proche à venir d'abord.
  ({DateTime day, ScheduleBlock block})? _plannedBlock(String taskId) {
    ({DateTime day, ScheduleBlock block})? best;
    for (final e in _byDay.entries) {
      for (final b in e.value) {
        if (b.taskId != taskId || b.status == 'done') continue;
        final day = DateTime.parse(e.key);
        if (day.isBefore(_today)) continue;
        if (best == null ||
            day.isBefore(best.day) ||
            (day == best.day && blockStartMin(b) < blockStartMin(best.block))) {
          best = (day: day, block: b);
        }
      }
    }
    return best;
  }

  // ── Actions ─────────────────────────────────────────────────────────────────

  Future<void> _newProject() async {
    if (_creating) return;
    final uid = FirebaseAuth.instance.currentUser?.uid ?? widget.sync.uid;
    if (uid == null) return;
    final p = Project(
      title: '',
      startDate: _today,
      createdBy: uid,
      domainId: _domainId,
    );
    // Titre, domaine, dates, phases saisis AVANT la création — le dialog
    // sauvegarde lui-même ; annuler ne crée rien.
    setState(() => _creating = true);
    try {
      final saved = await showProjectEditDialog(context,
          project: p, domains: widget.domains, sync: widget.sync, isNew: true);
      if (!saved || !mounted) return;
    } finally {
      if (mounted) setState(() => _creating = false);
    }
    widget.onRefresh();
    widget.onOpenProject(p);
  }

  Future<void> _checkAction(Project p, TaskAction a) async {
    setState(() {
      a.done = true;
      a.doneAt = DateTime.now();
    });
    await widget.sync.saveProjectTasks(p.id, p.tasks);
  }

  Future<void> _defineNextAction(Project p) async {
    final added = await showQuickAddActionDialog(context, project: p, sync: widget.sync);
    if (added && mounted) setState(() {});
  }

  Future<void> _setPaused(Project p, bool paused) async {
    setState(() => p.paused = paused);
    await widget.sync.saveProject(p);
    widget.onRefresh();
  }

  Future<void> _setArchived(Project p, bool archived) async {
    setState(() => p.status = archived ? 'archived' : 'active');
    await widget.sync.saveProject(p);
    widget.onRefresh();
  }

  Future<void> _delete(Project p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer définitivement ?'),
        content: Text('« ${p.title} » et ses tâches seront supprimés.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: kBAlert),
              child: const Text('Supprimer')),
        ],
      ),
    );
    if (ok != true) return;
    await widget.sync.deleteProject(p.id);
    widget.onRefresh();
  }

  Future<void> _editObjective(StrategicObjective o) async {
    final saved = await showObjectiveEditDialog(context,
        existing: o,
        domains: widget.domains,
        activities: widget.activities,
        projects: widget.projects,
        sync: widget.sync);
    if (saved != null) widget.onRefresh();
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final active = _active;
    final atRisk = active
        .where((p) => projectHealth(p, widget.recentSessions, now).kind != HealthKind.onTrack &&
            projectHealth(p, widget.recentSessions, now).kind != HealthKind.noDeadline)
        .length;
    final noNext = active.where((p) => nextAction(p) == null).length;
    final objective = widget.objectives.where((o) => o.status == 'active').firstOrNull;

    return Container(
      color: kBBg,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(32, 22, 32, 26),
        children: [
          _header(active.length, atRisk, noNext),
          if (objective != null) ...[
            const SizedBox(height: 18),
            _objectiveCard(objective, now),
          ],
          const SizedBox(height: 18),
          _filters(),
          const SizedBox(height: 12),
          _table(now),
        ],
      ),
    );
  }

  Widget _header(int nActive, int atRisk, int noNext) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Projets',
            style: TextStyle(
                fontSize: 22, fontWeight: FontWeight.w600, color: kBText, letterSpacing: -.2)),
        const SizedBox(height: 3),
        Text(
          '$nActive actif${nActive > 1 ? 's' : ''} · $atRisk à risque · '
          '$noNext sans prochaine action',
          style: const TextStyle(fontSize: 13, color: kBText3, fontFeatures: _tabular),
        ),
      ]),
      const Spacer(),
      SizedBox(
        width: 260,
        height: 40,
        child: TextField(
          onChanged: (v) => setState(() => _query = v),
          style: const TextStyle(fontSize: 13.5, color: kBText),
          decoration: InputDecoration(
            hintText: 'Rechercher un projet ou une tâche',
            hintStyle: const TextStyle(fontSize: 13, color: kBText4),
            prefixIcon: const Icon(Icons.search, size: 18, color: kBText3),
            isDense: true,
            filled: true,
            fillColor: const Color(0x12FFFFFF),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(999), borderSide: BorderSide.none),
          ),
        ),
      ),
      const SizedBox(width: 10),
      SizedBox(
        height: 40,
        child: FilledButton.icon(
          onPressed: _creating ? null : _newProject,
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Nouveau projet'),
          style: FilledButton.styleFrom(
            backgroundColor: kBPrimary,
            foregroundColor: kBBg,
            shape: const StadiumBorder(),
            textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    ]);
  }

  Widget _objectiveCard(StrategicObjective o, DateTime now) {
    final prog = computeObjectiveProgress(
        o, widget.activities, widget.recentSessions, widget.recentHits, now);
    final kept = prog.items.where((i) => i.onTrack).length;
    final linked = widget.projects.where((p) => o.projectIds.contains(p.id)).toList();
    final days = prog.daysLeft;
    return _card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _editObjective(o),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Row(children: [
            const Icon(Icons.flag_outlined, size: 18, color: kBPrimary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  _label('OBJECTIF'),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(o.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 14.5, fontWeight: FontWeight.w600, color: kBText)),
                  ),
                ]),
                const SizedBox(height: 4),
                Text(
                  linked.isEmpty
                      ? 'Aucun projet lié'
                      : linked.map((p) => p.title).join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5, color: kBText3),
                ),
              ]),
            ),
            const SizedBox(width: 20),
            SizedBox(
              width: 200,
              child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(
                  '${prog.items.isEmpty ? '—' : '$kept / ${prog.items.length}'}'
                  '${days != null ? ' · J-${days < 0 ? 0 : days}' : ''}',
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: days != null && days <= 7 ? kBAttention : kBText2,
                      fontFeatures: _tabular),
                ),
                const SizedBox(height: 6),
                _bar(prog.weekPercent ?? 0, kBPrimary),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _filters() {
    return Row(children: [
      Expanded(
        child: Wrap(spacing: 8, runSpacing: 6, children: [
          _chip('Tous', selected: _domainId == null, onTap: () => setState(() => _domainId = null)),
          for (final d in widget.domains.where((d) => !d.deleted))
            _chip(d.name,
                dot: domainColor(d.id, widget.domains),
                selected: _domainId == d.id,
                onTap: () => setState(() => _domainId = _domainId == d.id ? null : d.id)),
        ]),
      ),
      const SizedBox(width: 16),
      if (_mode != _Mode.active)
        _textLink('‹ Projets actifs', () => setState(() => _mode = _Mode.active)),
      if (_mode != _Mode.paused)
        _textLink('En veille · ${_paused.length}', () => setState(() => _mode = _Mode.paused),
            muted: true),
      if (_mode != _Mode.archived)
        _textLink('Archivés · ${_archived.length}',
            () => setState(() => _mode = _Mode.archived),
            muted: true),
    ]);
  }

  Widget _table(DateTime now) {
    final rows = _listed;
    final title = switch (_mode) {
      _Mode.active => null,
      _Mode.paused => 'EN VEILLE',
      _Mode.archived => 'ARCHIVÉS',
    };
    return _card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: _label(title),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          child: Row(children: [
            _th('Projet', 290),
            _th('Avancement', 170),
            Expanded(child: _th('Prochaine action', null)),
            _th('Échéance', 110),
            _th('État', 130),
            _th('7 jours', 80, right: true),
            const SizedBox(width: 36),
          ]),
        ),
        const Divider(height: 1, color: kBLine),
        if (rows.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 36),
            child: Text(
              _query.isNotEmpty
                  ? 'Aucun projet ne correspond à « $_query ».'
                  : switch (_mode) {
                      _Mode.active => 'Aucun projet actif — crée-en un pour commencer.',
                      _Mode.paused => 'Aucun projet en veille.',
                      _Mode.archived => 'Aucun projet archivé.',
                    },
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: kBText3),
            ),
          )
        else
          for (final p in rows)
            if (p.parentProjectId == null || !rows.any((r) => r.id == p.parentProjectId)) ...[
              if (isFolder(p, widget.projects)) ...[
                _row(p, now, view: _display(p), childCount: _childrenOf(p, rows).length),
                if (_openFolders.contains(p.id))
                  for (final c in _childrenOf(p, rows)) _row(c, now, indent: 28),
              ] else
                _row(p, now),
            ],
      ]),
    );
  }

  Widget _th(String text, double? width, {bool right = false}) {
    final t = Text(text,
        textAlign: right ? TextAlign.right : TextAlign.left,
        style: const TextStyle(
            fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.3, color: kBText3));
    return width == null ? t : SizedBox(width: width, child: t);
  }

  Widget _row(Project p, DateTime now, {Project? view, int indent = 0, int? childCount}) {
    // `view` = vue fusionnée d'un dossier (chiffres cumulés) ; `p` reste le
    // projet réel (ouverture, menu).
    final v = view ?? p;
    final folder = childCount != null;
    final open = _openFolders.contains(p.id);
    final domain = widget.domains.where((d) => d.id == p.domainId).firstOrNull;
    final dColor = domainColor(p.domainId, widget.domains) ?? kBText4;
    final phase = currentPhase(v, now);
    final prog = taskProgress(v);
    final health = projectHealth(v, widget.recentSessions, now);
    final minutes = minutesLast7Days(v, widget.recentSessions, now);
    final daysLeft = p.endDate == null ? null : dateOnly(p.endDate!).difference(_today).inDays;
    final dueColor = daysLeft == null
        ? kBText4
        : daysLeft < 0
            ? kBAlert
            : daysLeft <= 7
                ? kBAttention
                : kBText2;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => widget.onOpenProject(p),
        child: Container(
          height: 76,
          padding: EdgeInsets.fromLTRB(20.0 + indent, 0, 20, 0),
          decoration: BoxDecoration(
              color: folder ? const Color(0x08FFFFFF) : null,
              border: const Border(bottom: BorderSide(color: kBLine))),
          child: Row(children: [
            SizedBox(
              width: 290.0 - indent,
              child: Row(children: [
                if (folder)
                  InkWell(
                    onTap: () => setState(() => open ? _openFolders.remove(p.id) : _openFolders.add(p.id)),
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: Icon(open ? Icons.expand_more : Icons.chevron_right, size: 18, color: kBText3),
                    ),
                  )
                else
                  Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(color: dColor, shape: BoxShape.circle)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(p.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w600, color: kBText)),
                        const SizedBox(height: 3),
                        Text(
                          folder
                              ? '${domain?.name ?? 'Sans domaine'} · dossier · $childCount sous-projet${childCount > 1 ? 's' : ''}'
                              : '${domain?.name ?? 'Sans domaine'} · '
                                  '${phase != null ? 'phase ${phase.label}' : 'sans phase'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, color: kBText3),
                        ),
                      ]),
                ),
                const SizedBox(width: 12),
              ]),
            ),
            SizedBox(
              width: 170,
              child: Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _bar(prog.total == 0 ? 0 : prog.done / prog.total, kBPrimary),
                      const SizedBox(height: 6),
                      Text('${prog.done} / ${prog.total} tâche${prog.total > 1 ? 's' : ''}',
                          style: const TextStyle(
                              fontSize: 12, color: kBText3, fontFeatures: _tabular)),
                    ]),
              ),
            ),
            Expanded(child: _nextActionCell(v, folder: folder)),
            SizedBox(
              width: 110,
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.endDate == null ? '—' : _ddmm(p.endDate!),
                        style: TextStyle(
                            fontSize: 13, color: p.endDate == null ? kBText4 : kBText,
                            fontFeatures: _tabular)),
                    if (p.endDate != null) ...[
                      const SizedBox(height: 3),
                      Text(daysLeftLabel(p.endDate, _today),
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: dueColor,
                              fontFeatures: _tabular)),
                    ],
                  ]),
            ),
            SizedBox(width: 130, child: Align(alignment: Alignment.centerLeft, child: _healthPill(health))),
            SizedBox(
              width: 80,
              child: Text(_fmtHm(minutes),
                  textAlign: TextAlign.right,
                  style: TextStyle(
                      fontSize: 13,
                      color: minutes == 0 ? kBText4 : kBText2,
                      fontFeatures: _tabular)),
            ),
            SizedBox(width: 36, child: _rowMenu(p)),
          ]),
        ),
      ),
    );
  }

  Widget _nextActionCell(Project p, {bool folder = false}) {
    final next = nextAction(p);
    if (next == null) {
      // Dossier : les tâches vivent dans les sous-projets, on n'en crée pas ici.
      if (folder) {
        return const Align(
          alignment: Alignment.centerLeft,
          child: Text('Rien d\'ouvert dans les sous-projets',
              style: TextStyle(fontSize: 12.5, color: kBText4)),
        );
      }
      return Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: () => _defineNextAction(p),
          icon: const Icon(Icons.add, size: 15),
          label: const Text('Définir la prochaine action'),
          style: OutlinedButton.styleFrom(
            foregroundColor: kBText2,
            side: const BorderSide(color: Color(0x33FFFFFF)),
            shape: const StadiumBorder(),
            visualDensity: VisualDensity.compact,
            textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500),
          ),
        ),
      );
    }
    final t = next.task;
    final overdue = t.endDate != null && dateOnly(t.endDate!).isBefore(_today);
    final planned = _plannedBlock(t.id);
    final String sub;
    var subColor = kBText3;
    if (overdue) {
      sub = 'tâche en retard depuis le ${_ddmm(t.endDate!)}';
      subColor = kBAlert;
    } else if (planned != null) {
      final d = planned.day;
      final when = d == _today
          ? 'aujourd\'hui'
          : d == _today.add(const Duration(days: 1))
              ? 'demain'
              : _kDayLong[d.weekday - 1];
      final m = blockStartMin(planned.block);
      sub = 'planifiée $when ${m ~/ 60} h ${(m % 60).toString().padLeft(2, '0')}';
      subColor = kBPrimary;
    } else {
      sub = t.title;
    }
    return Row(children: [
      InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _checkAction(p, next.action),
        child: const Tooltip(
          message: 'Marquer comme faite',
          child: Padding(
            padding: EdgeInsets.all(4),
            child: Icon(Icons.radio_button_unchecked, size: 18, color: kBText3),
          ),
        ),
      ),
      const SizedBox(width: 6),
      Expanded(
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(next.action.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13.5, color: kBText)),
              const SizedBox(height: 3),
              Text(sub,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: subColor, fontFeatures: _tabular)),
            ]),
      ),
      const SizedBox(width: 12),
    ]);
  }

  Widget _healthPill(ProjectHealth h) {
    final color = switch (h.kind) {
      HealthKind.stalled => kBAlert,
      HealthKind.atRisk => kBAttention,
      HealthKind.noDeadline => kBText3,
      HealthKind.onTrack => kBPrimary,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
          color: color.withOpacity(.14), borderRadius: BorderRadius.circular(999)),
      child: Text(h.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w700, color: color, fontFeatures: _tabular)),
    );
  }

  Widget _rowMenu(Project p) {
    return PopupMenuButton<String>(
      tooltip: 'Actions',
      icon: const Icon(Icons.more_horiz, size: 18, color: kBText3),
      onSelected: (v) {
        switch (v) {
          case 'pause':
            _setPaused(p, true);
          case 'resume':
            _setPaused(p, false);
          case 'archive':
            _setArchived(p, true);
          case 'restore':
            _setArchived(p, false);
          case 'delete':
            _delete(p);
        }
      },
      itemBuilder: (_) => switch (_mode) {
        _Mode.active => const [
            PopupMenuItem(value: 'pause', child: Text('Mettre en veille')),
            PopupMenuItem(value: 'archive', child: Text('Archiver')),
          ],
        _Mode.paused => const [
            PopupMenuItem(value: 'resume', child: Text('Reprendre')),
            PopupMenuItem(value: 'archive', child: Text('Archiver')),
          ],
        _Mode.archived => const [
            PopupMenuItem(value: 'restore', child: Text('Restaurer')),
            PopupMenuItem(value: 'delete', child: Text('Supprimer définitivement')),
          ],
      },
    );
  }

  // ── Briques ─────────────────────────────────────────────────────────────────

  Widget _card({required Widget child}) => Container(
        decoration: BoxDecoration(
          color: kBSurface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: kBLine),
        ),
        clipBehavior: Clip.antiAlias,
        child: child,
      );

  Widget _label(String text) => Text(text,
      style: const TextStyle(
          fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.3, color: kBText3));

  Widget _bar(double v, Color color) => ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: SizedBox(
          height: 5,
          child: Stack(children: [
            Container(color: const Color(0x14FFFFFF)),
            FractionallySizedBox(widthFactor: v.clamp(0.0, 1.0), child: Container(color: color)),
          ]),
        ),
      );

  Widget _chip(String label, {Color? dot, required bool selected, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: selected ? kBActive : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? kBPrimary.withOpacity(.35) : kBLine),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (dot != null) ...[
            Container(width: 8, height: 8, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
            const SizedBox(width: 7),
          ],
          Text(label,
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: selected ? kBText : kBText2)),
        ]),
      ),
    );
  }

  Widget _textLink(String label, VoidCallback onTap, {bool muted = false}) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Text(label,
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: muted ? kBText3 : kBPrimary,
                  fontFeatures: _tabular)),
        ),
      );
}
