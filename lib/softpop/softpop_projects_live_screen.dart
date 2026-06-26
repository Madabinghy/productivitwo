import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/models.dart';
import 'softpop_tokens.dart';
import 'softpop_theme.dart';
import 'softpop_components.dart';

/// Vue Projets branchée sur les vrais projets Gantt (AppLogic.currentProjects).
///
/// Liste des projets actifs → détail « parcours à jalons » réel (tâches
/// `isMilestone` + actions `TaskAction`). Cocher une action persiste via
/// `sync.saveProjectTasks`. Données réelles.
class SoftPopProjectsLiveScreen extends StatefulWidget {
  final AppLogic logic;
  const SoftPopProjectsLiveScreen({super.key, required this.logic});

  @override
  State<SoftPopProjectsLiveScreen> createState() =>
      _SoftPopProjectsLiveScreenState();
}

class _SoftPopProjectsLiveScreenState extends State<SoftPopProjectsLiveScreen> {
  AppLogic get logic => widget.logic;

  static const _palette = [
    SoftPop.violet, SoftPop.coral, SoftPop.teal, SoftPop.amber, SoftPop.pink,
  ];
  Color _domColor(String? domainId) {
    final doms = logic.state.activeDomains;
    final idx = doms.indexWhere((d) => d.id == domainId);
    if (idx >= 0 && doms[idx].colorValue != null) return Color(doms[idx].colorValue!);
    return idx >= 0 ? _palette[idx % _palette.length] : SoftPop.violet;
  }

  List<Project> get _projects => logic.currentProjects
      .where((p) => p.status == 'active' || p.status == 'draft')
      .toList();

  (int, int) _progress(Project p) {
    var done = 0, total = 0;
    for (final t in p.tasks) {
      for (final a in t.actions) {
        total++;
        if (a.done) done++;
      }
    }
    return (done, total);
  }

  @override
  Widget build(BuildContext context) {
    final projects = _projects;
    return Theme(
      data: softPopTheme(),
      child: Scaffold(
        appBar: AppBar(title: const Text('Projets')),
        body: projects.isEmpty
            ? _empty()
            : ListView(
                padding: const EdgeInsets.fromLTRB(
                    SoftPop.s16, SoftPop.s8, SoftPop.s16, SoftPop.s32),
                children: [
                  for (final p in projects) ...[
                    _projectCard(p),
                    const SizedBox(height: SoftPop.s8),
                  ],
                ],
              ),
      ),
    );
  }

  Widget _projectCard(Project p) {
    final c = _domColor(p.domainId);
    final (done, total) = _progress(p);
    final pct = total == 0 ? 0.0 : done / total;
    return SoftCard(
      radius: SoftPop.rCardSm,
      onTap: () async {
        await Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => _ProjectDetail(logic: logic, project: p, color: c)));
        setState(() {}); // refresh % au retour
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    color: c.withValues(alpha: .14),
                    borderRadius: BorderRadius.circular(12)),
                child: Icon(Icons.flag_rounded, color: c, size: 20),
              ),
              const SizedBox(width: SoftPop.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.title,
                        style: SoftPop.ui(size: 15, weight: FontWeight.w700)),
                    if (p.endDate != null)
                      Text('📅 ${_date(p.endDate!)}',
                          style: SoftPop.ui(size: 11, color: SoftPop.inkMuted)),
                  ],
                ),
              ),
              Text('${(pct * 100).round()}%',
                  style: SoftPop.mono(size: 16, color: c)),
            ],
          ),
          const SizedBox(height: SoftPop.s12),
          SoftXpBar(value: pct, gradient: LinearGradient(colors: [c, c])),
          const SizedBox(height: SoftPop.s4),
          Text('$done / $total actions',
              style: SoftPop.mono(size: 10, color: SoftPop.inkMuted)),
        ],
      ),
    );
  }

  Widget _empty() => Center(
        child: Padding(
          padding: const EdgeInsets.all(SoftPop.s32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const PomoMascot(size: 88),
              const SizedBox(height: SoftPop.s20),
              Text('Aucun projet actif',
                  textAlign: TextAlign.center,
                  style: SoftPop.ui(size: 18, weight: FontWeight.w700)),
              const SizedBox(height: SoftPop.s8),
              Text('Crée un projet dans l’app classique pour le suivre ici.',
                  textAlign: TextAlign.center,
                  style: SoftPop.ui(size: 14, color: SoftPop.inkSecondary)),
            ],
          ),
        ),
      );

  static String _date(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
}

/// Détail d'un projet : parcours à jalons réel + actions cochables (persistées).
class _ProjectDetail extends StatefulWidget {
  final AppLogic logic;
  final Project project;
  final Color color;
  const _ProjectDetail(
      {required this.logic, required this.project, required this.color});

  @override
  State<_ProjectDetail> createState() => _ProjectDetailState();
}

class _ProjectDetailState extends State<_ProjectDetail> {
  AppLogic get logic => widget.logic;
  Project get p => widget.project;
  Color get c => widget.color;
  final Set<String> _expanded = {};

  // Tâches « jalons » si présentes, sinon toutes les tâches.
  List<ProjectTask> get _milestones {
    final ms = p.tasks.where((t) => t.isMilestone).toList();
    return ms.isNotEmpty ? ms : p.tasks;
  }

  (int, int) get _progress {
    var done = 0, total = 0;
    for (final t in p.tasks) {
      for (final a in t.actions) {
        total++;
        if (a.done) done++;
      }
    }
    return (done, total);
  }

  void _toggle(ProjectTask t, TaskAction a) {
    setState(() {
      a.done = !a.done;
      a.doneAt = a.done ? DateTime.now() : null;
    });
    logic.sync?.saveProjectTasks(p.id, p.tasks);
    logic.updateGanttCounts(logic.currentProjects);
  }

  @override
  Widget build(BuildContext context) {
    final (done, total) = _progress;
    final pct = total == 0 ? 0.0 : done / total;
    final ms = _milestones;
    return Theme(
      data: softPopTheme(),
      child: Scaffold(
        appBar: AppBar(title: const Text('Parcours du projet')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(
              SoftPop.s16, SoftPop.s8, SoftPop.s16, SoftPop.s32),
          children: [
            SoftCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(p.title,
                            style:
                                SoftPop.ui(size: 17, weight: FontWeight.w700)),
                      ),
                      Text('${(pct * 100).round()}%',
                          style: SoftPop.mono(size: 18, color: c)),
                    ],
                  ),
                  if (p.endDate != null)
                    Text('📅 Échéance ${_ProjectsList._d(p.endDate!)}',
                        style: SoftPop.ui(size: 11, color: SoftPop.inkMuted)),
                  const SizedBox(height: SoftPop.s12),
                  SoftXpBar(value: pct, gradient: LinearGradient(colors: [c, c])),
                  const SizedBox(height: SoftPop.s4),
                  Text('$done / $total actions',
                      style: SoftPop.mono(size: 10, color: SoftPop.inkMuted)),
                ],
              ),
            ),
            const SizedBox(height: SoftPop.s16),
            for (var i = 0; i < ms.length; i++) _milestoneCard(ms[i], i),
          ],
        ),
      ),
    );
  }

  Widget _milestoneCard(ProjectTask t, int idx) {
    final open = _expanded.contains(t.id);
    final done = t.actions.where((a) => a.done).length;
    final allDone = t.actions.isNotEmpty && done == t.actions.length;
    return Padding(
      padding: const EdgeInsets.only(bottom: SoftPop.s8),
      child: SoftCard(
        padding: EdgeInsets.zero,
        radius: SoftPop.rCardSm,
        child: Column(
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(SoftPop.rCardSm),
              onTap: () => setState(() =>
                  open ? _expanded.remove(t.id) : _expanded.add(t.id)),
              child: Padding(
                padding: const EdgeInsets.all(SoftPop.s12),
                child: Row(
                  children: [
                    Container(
                      width: 26,
                      height: 26,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: allDone ? SoftPop.teal : c.withValues(alpha: .14),
                      ),
                      child: allDone
                          ? const Icon(Icons.check, size: 15, color: Colors.white)
                          : Text('${idx + 1}',
                              style: SoftPop.ui(
                                  size: 12, weight: FontWeight.w700, color: c)),
                    ),
                    const SizedBox(width: SoftPop.s12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(t.title,
                              style: SoftPop.ui(
                                  size: 14, weight: FontWeight.w600)),
                          if (t.actions.isNotEmpty)
                            Text('$done/${t.actions.length}',
                                style: SoftPop.ui(
                                    size: 11, color: SoftPop.inkMuted)),
                        ],
                      ),
                    ),
                    if (t.actions.isNotEmpty)
                      Icon(open ? Icons.expand_less : Icons.expand_more,
                          color: SoftPop.inkMuted, size: 20),
                  ],
                ),
              ),
            ),
            if (open && t.actions.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    SoftPop.s12, 0, SoftPop.s12, SoftPop.s12),
                child: Column(
                  children: [for (final a in t.actions) _actionRow(t, a)],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _actionRow(ProjectTask t, TaskAction a) => InkWell(
        borderRadius: BorderRadius.circular(SoftPop.rTiny),
        onTap: () => _toggle(t, a),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: SoftPop.s8),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: a.done ? SoftPop.teal : Colors.transparent,
                  border: a.done
                      ? null
                      : Border.all(
                          color: SoftPop.inkMuted.withValues(alpha: .4),
                          width: 2),
                ),
                child: a.done
                    ? const Icon(Icons.check, size: 13, color: Colors.white)
                    : null,
              ),
              const SizedBox(width: SoftPop.s12),
              Expanded(
                child: Text(a.title,
                    style: SoftPop.ui(
                        size: 13,
                        color: a.done ? SoftPop.inkMuted : SoftPop.ink,
                        weight: FontWeight.w500)),
              ),
            ],
          ),
        ),
      );
}

// Petit util de date partagé.
class _ProjectsList {
  static String _d(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
}
