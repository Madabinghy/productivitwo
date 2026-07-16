import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/widgets/context_picker.dart';
import 'package:productivitwo_v1/widgets/new_project_sheet.dart';
import 'package:productivitwo_v1/widgets/project_sheet.dart';

/// « Prochaines actions » (GTD) — le canal PULL quand le Gantt est en retrait :
/// par projet actif, LA prochaine action (étoilées ⭐ en tête) + les actions
/// propres des activités, filtrables par contexte. Le + crée une action simple
/// (ownAction) ou un nouveau projet (flux déterministe).
/// La carte coach de « Maintenant » reste le canal PUSH.
class NextActionsSection extends StatefulWidget {
  final AppLogic logic;
  final FirestoreSync sync;

  const NextActionsSection({
    super.key,
    required this.logic,
    required this.sync,
  });

  @override
  State<NextActionsSection> createState() => _NextActionsSectionState();
}

/// Une entrée de la liste : l'action + son porteur.
class _NextAction {
  final String title;
  final String source; // nom du projet ou de l'activité
  final String? context;
  final bool starred;
  final bool needsDefinition; // tâche urgente sans action → « définir »
  final Project? project; // tap → fiche tâche
  final String? taskId;
  final String? chronoActivityId; // ▶ possible
  final String? actionId;

  _NextAction({
    required this.title,
    required this.source,
    this.context,
    this.starred = false,
    this.needsDefinition = false,
    this.project,
    this.taskId,
    this.chronoActivityId,
    this.actionId,
  });
}

class _NextActionsSectionState extends State<NextActionsSection> {
  String? _filterContext;
  bool _expanded = false;

  static const _collapsedCount = 8;

  // ── Dérivation (miroir de GanttMicroAction : 1 prochaine action / projet) ──
  List<_NextAction> _deriveAll() {
    final out = <_NextAction>[];
    final starredOut = <_NextAction>[];

    for (final p in widget.logic.currentProjects) {
      if (p.status != 'active') continue;
      final pending = p.tasks
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
      if (pending.isEmpty) continue;

      // Étoilées : chaque tâche todayFlag remonte (sa 1ʳᵉ action pending,
      // ou la tâche elle-même si elle n'a pas d'action).
      for (final t in pending.where((t) => t.todayFlag)) {
        final a = t.actions.where((a) => !a.done).firstOrNull;
        starredOut.add(_NextAction(
          title: a?.title ?? t.title,
          source: p.title,
          context: a?.context,
          starred: true,
          project: p,
          taskId: t.id,
          chronoActivityId: a?.linkedActivityId,
          actionId: a?.id,
        ));
      }

      // La prochaine action du projet : 1ʳᵉ action pending de la tâche la
      // plus urgente (hors étoilées, déjà remontées).
      final t = pending.where((t) => !t.todayFlag).firstOrNull;
      if (t == null) continue;
      final a = t.actions.where((a) => !a.done).firstOrNull;
      if (a != null) {
        out.add(_NextAction(
          title: a.title,
          source: p.title,
          context: a.context,
          project: p,
          taskId: t.id,
          chronoActivityId: a.linkedActivityId,
          actionId: a.id,
        ));
      } else {
        // GTD minimaliste : la tâche urgente n'a pas de prochaine action —
        // l'entrée invite à la définir (tap → fiche tâche).
        out.add(_NextAction(
          title: 'Définir la prochaine action — ${t.title}',
          source: p.title,
          needsDefinition: true,
          project: p,
          taskId: t.id,
        ));
      }
    }

    // Actions propres des activités (actions simples GTD).
    for (final act in widget.logic.state.activeActivities) {
      for (final a in act.ownActions.where((a) => !a.done)) {
        out.add(_NextAction(
          title: a.title,
          source: act.name,
          context: a.context,
          chronoActivityId: act.id,
          actionId: a.id,
        ));
      }
    }

    return [...starredOut, ...out];
  }

  void _openTask(_NextAction it) {
    final p = it.project;
    if (p == null) return;
    showProjectSheet(
      context,
      project: p,
      domains: widget.logic.state.activeDomains,
      activities: widget.logic.state.activities,
      targetTaskId: it.taskId,
    ).then((_) {
      if (mounted) setState(() {});
    });
  }

  // ── Le + rapide : action simple OU nouveau projet ──────────────────────────
  Future<void> _showCreateSheet() async {
    final titleCtrl = TextEditingController();
    String? pickedContext;
    String mode = 'action'; // 'action' | 'project'
    String? activityId;
    final timeActivities = widget.logic.state.activeActivities
        .where((a) => a.type == 'time')
        .toList();
    if (timeActivities.isNotEmpty) activityId = timeActivities.first.id;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => Padding(
          padding: EdgeInsets.fromLTRB(
              20, 20, 20, 24 + MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Créer',
                  style:
                      TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              const SizedBox(height: 14),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                      value: 'action',
                      label: Text('Action simple'),
                      icon: Icon(Icons.bolt, size: 16)),
                  ButtonSegment(
                      value: 'project',
                      label: Text('Nouveau projet'),
                      icon: Icon(Icons.flag, size: 16)),
                ],
                selected: {mode},
                onSelectionChanged: (s) => setLocal(() => mode = s.first),
              ),
              const SizedBox(height: 14),
              if (mode == 'project')
                Text(
                  'Nom, échéance, première action — dans la fiche qui suit.',
                  style: TextStyle(
                      fontSize: 12.5,
                      color: Theme.of(ctx).colorScheme.onSurface
                          .withOpacity(.55)),
                )
              else ...[
                TextField(
                  controller: titleCtrl,
                  autofocus: true,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    hintText: 'Ex : Réserver le contrôle technique',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                ContextPicker(
                  value: pickedContext,
                  sync: widget.sync,
                  onChanged: (c) => setLocal(() => pickedContext = c),
                ),
                if (timeActivities.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text('SUR L\'ACTIVITÉ',
                      style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: .8,
                          color: Theme.of(ctx).colorScheme.onSurface
                              .withOpacity(.45))),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final a in timeActivities)
                        ChoiceChip(
                          selected: activityId == a.id,
                          onSelected: (_) =>
                              setLocal(() => activityId = a.id),
                          showCheckmark: false,
                          label: Text(a.name),
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
                  ),
                ] else
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      'Crée d\'abord une activité-temps pour porter tes actions simples.',
                      style: TextStyle(
                          fontSize: 12.5,
                          color: Theme.of(ctx).colorScheme.onSurface
                              .withOpacity(.55)),
                    ),
                  ),
              ],
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () async {
                    if (mode == 'project') {
                      Navigator.pop(ctx);
                      await showNewProjectSheet(
                        context,
                        domains: widget.logic.state.activeDomains,
                        sync: widget.sync,
                        onCreated: () {
                          if (mounted) setState(() {});
                        },
                      );
                      return;
                    }
                    final title = titleCtrl.text.trim();
                    final actId = activityId;
                    if (title.isEmpty || actId == null) return;
                    await widget.sync.addOwnActionToActivity(actId, title,
                        context: pickedContext);
                    // Reflète immédiatement dans l'état local (le doc Firestore
                    // est la source ; le prochain pull réconciliera par ID).
                    final act = widget.logic.state.activities
                        .where((a) => a.id == actId)
                        .firstOrNull;
                    act?.ownActions.add(TaskAction(
                        title: title,
                        linkedActivityId: actId,
                        context: pickedContext));
                    widget.logic.onChange();
                    if (ctx.mounted) Navigator.pop(ctx);
                    if (mounted) setState(() {});
                  },
                  child: Text(mode == 'project'
                      ? 'Continuer'
                      : 'Créer l\'action'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    titleCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final all = _deriveAll();
    if (all.isEmpty) {
      // Rien à distiller — la section reste discrète avec juste le +.
      return Padding(
        padding: const EdgeInsets.only(top: 20),
        child: Row(children: [
          _sectionTitle(cs),
          const Spacer(),
          _addButton(cs),
        ]),
      );
    }

    final contexts =
        all.map((a) => a.context).whereType<String>().toSet().toList()..sort();
    var filter = _filterContext;
    if (filter != null && !contexts.contains(filter)) filter = null;
    final filtered =
        filter == null ? all : all.where((a) => a.context == filter).toList();
    final visible =
        _expanded ? filtered : filtered.take(_collapsedCount).toList();

    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            _sectionTitle(cs),
            const Spacer(),
            _addButton(cs),
          ]),
          if (contexts.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final c in contexts)
                  ChoiceChip(
                    selected: filter == c,
                    onSelected: (_) => setState(
                        () => _filterContext = filter == c ? null : c),
                    showCheckmark: false,
                    label: Text(c),
                    labelStyle: TextStyle(
                      fontSize: 12,
                      fontWeight:
                          filter == c ? FontWeight.w600 : FontWeight.w500,
                      color: filter == c
                          ? cs.primary
                          : cs.onSurface.withOpacity(.6),
                    ),
                    selectedColor: cs.primary.withOpacity(.14),
                    backgroundColor: cs.surfaceContainerHighest.withOpacity(.35),
                    side: BorderSide(
                        color: filter == c
                            ? cs.primary.withOpacity(.5)
                            : Colors.transparent),
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          for (final it in visible) _tile(cs, it),
          if (!_expanded && filtered.length > _collapsedCount)
            TextButton(
              onPressed: () => setState(() => _expanded = true),
              child: Text(
                  'Voir les ${filtered.length - _collapsedCount} autres'),
            ),
        ],
      ),
    );
  }

  Widget _sectionTitle(ColorScheme cs) => Row(children: [
        Icon(Icons.checklist_rtl,
            size: 15, color: cs.onSurface.withOpacity(.5)),
        const SizedBox(width: 6),
        Text('PROCHAINES ACTIONS',
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: .8,
                color: cs.onSurface.withOpacity(.5))),
      ]);

  Widget _addButton(ColorScheme cs) => IconButton(
        tooltip: 'Créer une action ou un projet',
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints(),
        icon: Icon(Icons.add_circle_outline, size: 20, color: cs.primary),
        onPressed: _showCreateSheet,
      );

  Widget _tile(ColorScheme cs, _NextAction it) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: it.needsDefinition
            ? cs.primaryContainer.withOpacity(.15)
            : cs.surfaceContainerHighest.withOpacity(.35),
        borderRadius: BorderRadius.circular(12),
        border: it.needsDefinition
            ? Border.all(color: cs.primary.withOpacity(.25))
            : null,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: it.project != null ? () => _openTask(it) : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
          child: Row(children: [
            if (it.starred)
              const Padding(
                padding: EdgeInsets.only(right: 8),
                child: Icon(Icons.star_rounded,
                    size: 18, color: Color(0xFFF2B01E)),
              )
            else if (it.needsDefinition)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Icon(Icons.edit_note,
                    size: 18, color: cs.primary.withOpacity(.8)),
              ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(it.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          fontStyle: it.needsDefinition
                              ? FontStyle.italic
                              : FontStyle.normal)),
                  Row(children: [
                    Flexible(
                      child: Text(it.source,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 11,
                              color: cs.onSurface.withOpacity(.5))),
                    ),
                    if (it.context != null) ...[
                      const SizedBox(width: 6),
                      Text(it.context!,
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: cs.primary.withOpacity(.75))),
                    ],
                  ]),
                ],
              ),
            ),
            if (it.chronoActivityId != null && it.actionId != null)
              IconButton(
                tooltip: 'Lancer le chrono',
                icon:
                    Icon(Icons.play_circle_fill, size: 26, color: cs.primary),
                visualDensity: VisualDensity.compact,
                onPressed: () {
                  widget.logic.start(it.chronoActivityId!,
                      taskId: it.taskId, actionId: it.actionId);
                  setState(() {});
                },
              ),
          ]),
        ),
      ),
    );
  }
}
