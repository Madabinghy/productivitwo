import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/actions_logic.dart' show actionDueLabel;
import 'package:productivitwo_v1/utils/interventions.dart';
import 'package:productivitwo_v1/utils/palier_colors.dart';
import 'package:productivitwo_v1/utils/project_health.dart' show HealthKind;
import 'package:productivitwo_v1/utils/project_moment.dart';
import 'package:productivitwo_v1/widgets/fiche.dart';
import 'package:productivitwo_v1/widgets/project_sheet.dart';
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

  void _openPlan({String? taskId}) =>
      showProjectSheet(context,
          project: p,
          domains: widget.domains,
          targetTaskId: taskId,
          activities: widget.activities,
          sessions: widget.sessions,
          logic: widget.logic,
          onStartTimer: widget.onStartTimer);

  /// Tap sur une action = SA tâche, l'action dépliée (pas tout le plan).
  Future<void> _openAction(ProjectTask task, TaskAction action) async {
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
          if (p.status == 'active') ...[
            FicheTitle('CETTE SEMAINE',
                trailing: FicheDelta(
                    week.isEmpty ? 'rien d\'échu à 7 jours' : '${week.length} action${week.length > 1 ? 's' : ''}${m.sessionSoon ? ' avant la séance' : ''}',
                    color: week.any((a) => a.due != null && a.due!.isBefore(DateTime(now.year, now.month, now.day))) ? kPalierCoral : st)),
            if (week.isEmpty)
              FicheNote(m.next == null
                  ? 'Aucune action ouverte : définis la prochaine action dans le plan.'
                  : 'Prochaine action : ${m.next!.action.title} (${m.next!.task.title}).')
            else
              for (final a in week.take(6))
                FicheStep(
                  title: a.action.title,
                  detail: '${a.task.title}${a.due != null ? ' · ${actionDueLabel(a.due!, now)}' : ''}',
                  current: identical(a.action, m.next?.action) || a.action.id == m.next?.action.id,
                  onTap: () => _openAction(a.task, a.action),
                ),
            if (week.length > 6)
              FicheNote('+ ${week.length - 6} autre${week.length - 6 > 1 ? 's' : ''} dans le plan d\'action.'),
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
          if (p.status == 'active' && widget.onSkipToday != null) _decisions(m),
          if (p.status == 'active')
            FicheActions(
              primaryLabel: m.next == null ? 'Définir la prochaine action' : 'Prochaine action',
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
              child: Text('Prochaine action : ${m.next!.action.title} · ${m.next!.task.title}',
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
