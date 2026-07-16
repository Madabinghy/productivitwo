import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/domain_colors.dart';
import 'package:productivitwo_v1/widgets/next_actions_section.dart'
    show showCreateActionOrProjectSheet;
import 'package:productivitwo_v1/widgets/project_sheet.dart';

/// Onglet « Actions » : la liste GTD qui remplace l'onglet Projets quand le
/// Gantt est en retrait. Mode liste PAR PROJET : chaque projet actif expose
/// ses actions en attente (cochables, ▶ chrono ciblé) + les actions simples
/// des activités. En tête : « Je suis @… » — le contexte du moment filtre ce
/// qui est réalisable ici (partagé avec l'onglet Maintenant via nowContext).
class ActionsView extends StatefulWidget {
  final AppLogic logic;
  final void Function(Activity activity, Project project, ProjectTask task)?
      onStartTimer;

  const ActionsView({super.key, required this.logic, this.onStartTimer});

  @override
  State<ActionsView> createState() => _ActionsViewState();
}

/// Une action affichable, avec son porteur.
class _Entry {
  final TaskAction action;
  final Project? project; // null = action propre d'une activité
  final ProjectTask? task;
  final Activity? activity; // porteur (action propre) ou activité liée

  _Entry({required this.action, this.project, this.task, this.activity});

  String? get chronoActivityId =>
      activity?.id ?? action.linkedActivityId;
}

class _ActionsViewState extends State<ActionsView> {
  final _sync = FirestoreSync();

  AppState get _state => widget.logic.state;

  // ── Dérivation : actions en attente, groupées par porteur ──────────────────

  List<({Project project, List<_Entry> entries})> _projectGroups() {
    final out = <({Project project, List<_Entry> entries})>[];
    for (final p in widget.logic.currentProjects) {
      if (p.status != 'active') continue;
      final entries = <_Entry>[];
      final tasks = p.tasks
          .where((t) =>
              !t.isMilestone && t.status != 'done' && t.status != 'skipped')
          .toList()
        ..sort((a, b) {
          final ae = a.endDate, be = b.endDate;
          if (ae == null && be == null) return 0;
          if (ae == null) return 1;
          if (be == null) return -1;
          return ae.compareTo(be);
        });
      for (final t in tasks) {
        for (final a in t.actions.where((a) => !a.done)) {
          entries.add(_Entry(action: a, project: p, task: t));
        }
      }
      if (entries.isNotEmpty) out.add((project: p, entries: entries));
    }
    return out;
  }

  List<({Activity activity, List<_Entry> entries})> _activityGroups() {
    final out = <({Activity activity, List<_Entry> entries})>[];
    for (final act in _state.activeActivities) {
      final entries = [
        for (final a in act.ownActions.where((a) => !a.done))
          _Entry(action: a, activity: act),
      ];
      if (entries.isNotEmpty) out.add((activity: act, entries: entries));
    }
    return out;
  }

  Set<String> _allContexts(
    List<({Project project, List<_Entry> entries})> pGroups,
    List<({Activity activity, List<_Entry> entries})> aGroups,
  ) {
    final s = <String>{};
    for (final g in pGroups) {
      for (final e in g.entries) {
        if (e.action.context != null) s.add(e.action.context!);
      }
    }
    for (final g in aGroups) {
      for (final e in g.entries) {
        if (e.action.context != null) s.add(e.action.context!);
      }
    }
    return s;
  }

  // ── Mutations ───────────────────────────────────────────────────────────────

  Future<void> _toggleDone(_Entry e, bool done) async {
    e.action.done = done;
    e.action.doneAt = done ? DateTime.now() : null;
    if (e.project != null) {
      await _sync.saveProjectTasks(e.project!.id, e.project!.tasks);
    } else if (e.activity != null) {
      await _sync.updateOwnActions(e.activity!.id, e.activity!.ownActions);
    }
    widget.logic.onChange();
    if (mounted) setState(() {});
  }

  void _openProject(Project p, {String? targetTaskId}) {
    showProjectSheet(
      context,
      project: p,
      domains: _state.activeDomains,
      activities: _state.activities,
      targetTaskId: targetTaskId,
    ).then((_) {
      if (mounted) setState(() {});
    });
  }

  void _launch(_Entry e) {
    final actId = e.chronoActivityId;
    if (actId == null) return;
    widget.logic.start(actId,
        taskId: e.task?.id, actionId: e.action.id);
    if (mounted) setState(() {});
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pGroups = _projectGroups();
    final aGroups = _activityGroups();
    final contexts = _allContexts(pGroups, aGroups).toList()..sort();
    var nowContext = _state.nowContext;
    if (nowContext != null && !contexts.contains(nowContext)) {
      nowContext = null;
    }

    bool visible(_Entry e) =>
        nowContext == null || e.action.context == nowContext;

    final visibleProjectGroups = [
      for (final g in pGroups)
        (project: g.project, entries: g.entries.where(visible).toList()),
    ].where((g) => g.entries.isNotEmpty).toList();
    final visibleActivityGroups = [
      for (final g in aGroups)
        (activity: g.activity, entries: g.entries.where(visible).toList()),
    ].where((g) => g.entries.isNotEmpty).toList();

    final empty =
        visibleProjectGroups.isEmpty && visibleActivityGroups.isEmpty;

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
        children: [
          // ── En-tête + création ─────────────────────────────────────────────
          Row(children: [
            Text('Actions',
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: cs.onSurface)),
            const Spacer(),
            IconButton(
              tooltip: 'Créer une action ou un projet',
              icon: Icon(Icons.add_circle, color: cs.primary, size: 26),
              onPressed: () => showCreateActionOrProjectSheet(
                context,
                logic: widget.logic,
                sync: _sync,
                onCreated: () {
                  if (mounted) setState(() {});
                },
              ),
            ),
          ]),

          // ── « Je suis… » : le contexte du moment filtre la liste ───────────
          if (contexts.isNotEmpty) ...[
            Row(children: [
              Icon(Icons.place_outlined,
                  size: 14, color: cs.onSurface.withOpacity(.45)),
              const SizedBox(width: 6),
              Text('JE SUIS…',
                  style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: .8,
                      color: cs.onSurface.withOpacity(.45))),
            ]),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final c in contexts)
                  ChoiceChip(
                    selected: nowContext == c,
                    onSelected: (_) {
                      _state.nowContext = nowContext == c ? null : c;
                      widget.logic.onChange();
                      setState(() {});
                    },
                    showCheckmark: false,
                    label: Text(c),
                    labelStyle: TextStyle(
                      fontSize: 12.5,
                      fontWeight: nowContext == c
                          ? FontWeight.w600
                          : FontWeight.w500,
                      color: nowContext == c
                          ? cs.primary
                          : cs.onSurface.withOpacity(.65),
                    ),
                    selectedColor: cs.primary.withOpacity(.14),
                    backgroundColor: cs.surfaceContainerHighest.withOpacity(.35),
                    side: BorderSide(
                        color: nowContext == c
                            ? cs.primary.withOpacity(.5)
                            : Colors.transparent),
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
              ],
            ),
            if (nowContext != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Réalisable $nowContext — le reste est masqué.',
                  style: TextStyle(
                      fontSize: 11.5,
                      fontStyle: FontStyle.italic,
                      color: cs.onSurface.withOpacity(.5)),
                ),
              ),
            const SizedBox(height: 14),
          ],

          if (empty)
            Padding(
              padding: const EdgeInsets.only(top: 40),
              child: Center(
                child: Text(
                  nowContext != null
                      ? 'Rien à faire $nowContext pour l\'instant.'
                      : 'Aucune action en attente.\nCapture une idée ou crée une action avec +.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 14, color: cs.onSurface.withOpacity(.45)),
                ),
              ),
            ),

          // ── Par projet ─────────────────────────────────────────────────────
          for (final g in visibleProjectGroups) ...[
            _groupHeader(
              cs,
              g.project.title,
              domainColor(g.project.domainId, _state.activeDomains) ??
                  cs.primary,
              onTap: () => _openProject(g.project),
            ),
            for (final e in g.entries) _entryTile(cs, e),
            const SizedBox(height: 10),
          ],

          // ── Actions simples (activités) ────────────────────────────────────
          if (visibleActivityGroups.isNotEmpty) ...[
            _groupHeader(cs, 'Actions simples', cs.tertiary),
            for (final g in visibleActivityGroups) ...[
              Padding(
                padding: const EdgeInsets.only(left: 2, top: 2, bottom: 4),
                child: Text(g.activity.name.toUpperCase(),
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: .8,
                        color: cs.onSurface.withOpacity(.4))),
              ),
              for (final e in g.entries) _entryTile(cs, e),
            ],
          ],
        ],
      ),
    );
  }

  Widget _groupHeader(ColorScheme cs, String title, Color color,
      {VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 6),
        child: Row(children: [
          Container(
            width: 8,
            height: 8,
            decoration:
                BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: cs.onSurface.withOpacity(.75))),
          ),
          if (onTap != null)
            Icon(Icons.chevron_right,
                size: 16, color: cs.onSurface.withOpacity(.3)),
        ]),
      ),
    );
  }

  Widget _entryTile(ColorScheme cs, _Entry e) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withOpacity(.35),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [
        Checkbox(
          value: false,
          shape: const CircleBorder(),
          onChanged: (v) => _toggleDone(e, v ?? false),
        ),
        Expanded(
          child: InkWell(
            onTap: e.project != null
                ? () => _openProject(e.project!, targetTaskId: e.task?.id)
                : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(e.action.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13.5, fontWeight: FontWeight.w600)),
                  if (e.task != null || e.action.context != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Row(children: [
                        if (e.task != null)
                          Flexible(
                            child: Text(e.task!.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 11,
                                    color: cs.onSurface.withOpacity(.5))),
                          ),
                        if (e.action.context != null) ...[
                          if (e.task != null) const SizedBox(width: 6),
                          Text(e.action.context!,
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: cs.primary.withOpacity(.75))),
                        ],
                      ]),
                    ),
                ],
              ),
            ),
          ),
        ),
        if (e.chronoActivityId != null)
          IconButton(
            tooltip: 'Lancer le chrono',
            icon: Icon(Icons.play_circle_fill, size: 24, color: cs.primary),
            visualDensity: VisualDensity.compact,
            onPressed: () => _launch(e),
          ),
        const SizedBox(width: 2),
      ]),
    );
  }
}
