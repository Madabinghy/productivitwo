import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/domain_colors.dart';
import 'package:productivitwo_v1/widgets/context_picker.dart';
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

  /// Activité effective : porteur (action propre) > lien propre de l'action
  /// > lien hérité du projet.
  String? get chronoActivityId =>
      activity?.id ?? action.linkedActivityId ?? project?.linkedActivityId;
}

class _ActionsViewState extends State<ActionsView> {
  final _sync = FirestoreSync();

  // Section « Terminées » repliée par défaut (consultation ponctuelle).
  bool _showDone = false;

  AppState get _state => widget.logic.state;

  // À l'écoute d'AppLogic : un contexte ajouté depuis une fiche/dialog doit
  // apparaître SANS changer d'onglet (constaté sur build — la vue n'était
  // rafraîchie que par les rebuilds du parent).
  @override
  void initState() {
    super.initState();
    widget.logic.addListener(_onLogicChange);
  }

  @override
  void dispose() {
    widget.logic.removeListener(_onLogicChange);
    super.dispose();
  }

  void _onLogicChange() {
    if (mounted) setState(() {});
  }

  // ── Dérivation : actions en attente, groupées par porteur ──────────────────

  List<({Project project, List<_Entry> entries})> _projectGroups() {
    final out = <({Project project, List<_Entry> entries})>[];
    for (final p in widget.logic.currentProjects) {
      if (p.status != 'active' || p.paused) continue;
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
      // Groupe gardé même vide : un projet fraîchement créé (ou dont tout est
      // fait) reste visible avec l'invitation « Définir la prochaine action ».
      out.add((project: p, entries: entries));
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

  /// Actions VALIDÉES (projets — tous statuts — + actions simples), les plus
  /// récentes d'abord : retrouver ce qui a été fait, et décocher au besoin.
  List<_Entry> _doneEntries() {
    final out = <_Entry>[];
    for (final p in widget.logic.currentProjects) {
      for (final t in p.tasks) {
        for (final a in t.actions.where((a) => a.done)) {
          out.add(_Entry(action: a, project: p, task: t));
        }
      }
    }
    for (final act in _state.activeActivities) {
      for (final a in act.ownActions.where((a) => a.done)) {
        out.add(_Entry(action: a, activity: act));
      }
    }
    out.sort((x, y) => (y.action.doneAt ?? y.action.createdAt)
        .compareTo(x.action.doneAt ?? x.action.createdAt));
    return out;
  }

  Set<String> _allContexts(
    List<({Project project, List<_Entry> entries})> pGroups,
    List<({Activity activity, List<_Entry> entries})> aGroups,
  ) {
    final s = <String>{};
    for (final g in pGroups) {
      for (final e in g.entries) {
        s.addAll(e.action.allContexts);
      }
    }
    for (final g in aGroups) {
      for (final e in g.entries) {
        s.addAll(e.action.allContexts);
      }
    }
    return s;
  }

  // ── Mutations ───────────────────────────────────────────────────────────────

  Future<void> _toggleDone(_Entry e, bool done) async {
    e.action.done = done;
    e.action.doneAt = done ? DateTime.now() : null;
    // Décocher depuis « Terminées » : une tâche close (toutes actions faites)
    // doit se rouvrir, sinon l'action restaurée resterait invisible en attente.
    if (!done && e.task != null && e.task!.status != 'pending') {
      e.task!.status = 'pending';
    }
    // Optimiste : pas d'await sur l'ack serveur (hors-ligne il n'arrive
    // jamais — la coche restait sans effet jusqu'au prochain rebuild).
    if (e.project != null) {
      unawaited(_sync.saveProjectTasks(e.project!.id, e.project!.tasks));
    } else if (e.activity != null) {
      unawaited(_sync.updateOwnActions(e.activity!.id, e.activity!.ownActions));
    }
    widget.logic.onChange();
    if (mounted) setState(() {});
    // Égrainage GTD : la dernière action du projet vient d'être cochée —
    // c'est LE moment de définir la suivante (le réflexe se forge à la
    // complétion, pas à la planification).
    final p = e.project;
    if (done && p != null && mounted) {
      final hasPending = p.tasks
          .where((t) =>
              !t.isMilestone && t.status != 'done' && t.status != 'skipped')
          .any((t) => t.actions.any((a) => !a.done));
      if (!hasPending) await _quickAddAction(p, followUp: true);
    }
  }

  // ── Ajout direct d'action au projet (la couche tâches est ignorée) ────────

  /// Tâche-réceptacle des actions ajoutées au fil de l'eau : id stable,
  /// invisible dans la liste (seules les actions s'affichent), visible dans
  /// la fiche projet/Gantt comme n'importe quelle tâche.
  static const _flowTaskId = 'gtd-flow';

  ProjectTask _flowTask(Project p) {
    final existing = p.tasks.firstWhereOrNull((t) => t.id == _flowTaskId);
    if (existing != null) {
      // Réactivée si elle avait été close (toutes actions faites).
      if (existing.status != 'pending') existing.status = 'pending';
      return existing;
    }
    final t = ProjectTask(
      id: _flowTaskId,
      title: 'Au fil de l\'eau',
      startDate: DateTime.now(),
      // endDate null → triée en dernier : les tâches datées gardent la
      // priorité d'urgence (coach/ORION).
    );
    p.tasks.add(t);
    return t;
  }

  /// Dialog rapide titre + contextes → action directement dans le projet.
  /// CHAÎNABLE : « Ajouter » enregistre, vide le champ et garde le dialog
  /// ouvert (contextes conservés) pour saisir plusieurs prochaines actions
  /// d'affilée ; « Terminer » ferme.
  /// [followUp] = égrainage après complétion (« Et la prochaine ? »).
  Future<void> _quickAddAction(Project p, {bool followUp = false}) async {
    final ctrl = TextEditingController();
    var pickedContexts = <String>[];
    var added = 0;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
        Future<void> add() async {
          final v = ctrl.text.trim();
          if (v.isEmpty) return;
          final t = _flowTask(p);
          t.actions.add(TaskAction(
            title: v,
            context: pickedContexts.isEmpty ? null : pickedContexts.first,
            contexts: List.of(pickedContexts),
          ));
          setLocal(() {
            added++;
            ctrl.clear();
          });
          // Optimiste : pas d'await sur l'ack serveur (hors-ligne il
          // n'arrive jamais — l'ajout chaînable resterait bloqué).
          unawaited(_sync.saveProjectTasks(p.id, p.tasks));
          widget.logic.onChange();
          if (mounted) setState(() {});
        }

        return AlertDialog(
          // Beaucoup de contextes : sans scroll, les chips passaient SOUS
          // les boutons Annuler/Ajouter (constaté sur build).
          scrollable: true,
          title: Text(followUp
              ? 'Et la prochaine action ?'
              : 'Prochaine action'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(p.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12.5,
                      color: Theme.of(ctx).colorScheme.onSurface
                          .withOpacity(.55))),
              const SizedBox(height: 10),
              TextField(
                controller: ctrl,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                    hintText: 'La prochaine action concrète…'),
                onSubmitted: (_) => add(),
              ),
              const SizedBox(height: 12),
              ContextPicker(
                values: pickedContexts,
                sync: _sync,
                onValuesChanged: (list) => pickedContexts = list,
              ),
              if (added > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                      added == 1
                          ? '1 action ajoutée — enchaîne ou termine.'
                          : '$added actions ajoutées — enchaîne ou termine.',
                      style: TextStyle(
                          fontSize: 11.5,
                          fontStyle: FontStyle.italic,
                          color: Theme.of(ctx).colorScheme.onSurface
                              .withOpacity(.5))),
                ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(added > 0
                    ? 'Terminer'
                    : (followUp ? 'Plus tard' : 'Annuler'))),
            FilledButton(
              onPressed: add,
              child: const Text('Ajouter'),
            ),
          ],
        );
      }),
    );
    ctrl.dispose();
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

  Future<void> _persistEntry(_Entry e) async {
    // Optimiste, comme _toggleDone : l'UI reflète tout de suite.
    if (e.project != null) {
      unawaited(_sync.saveProjectTasks(e.project!.id, e.project!.tasks));
    } else if (e.activity != null) {
      unawaited(_sync.updateOwnActions(e.activity!.id, e.activity!.ownActions));
    }
    widget.logic.onChange();
    if (mounted) setState(() {});
  }

  Future<void> _togglePause(Project p) async {
    p.paused = !p.paused;
    unawaited(_sync.saveProject(p));
    widget.logic.onChange();
    if (mounted) setState(() {});
  }

  // ── « Process » GTD : tap sur une action → multi-contextes ─────────────────

  Future<void> _processAction(_Entry e) async {
    final available = await _sync.fetchAvailableContexts();
    if (!mounted) return;
    final selected = Set<String>.of(e.action.allContexts);
    // Un contexte orphelin (custom supprimé) reste sélectionnable ici.
    final all = [
      ...available,
      ...selected.where((c) => !available.contains(c)),
    ];
    // Lien chrono (actions de projet) : activité propre de l'action, sinon
    // héritée du projet. Les activités du même domaine passent en premier.
    final isProjectAction = e.project != null;
    var linkedId = e.action.linkedActivityId;
    final timeActivities = _state.activeActivities
        .where((a) => a.type == 'time')
        .toList()
      ..sort((a, b) {
        final ad = a.domainId == e.project?.domainId ? 0 : 1;
        final bd = b.domainId == e.project?.domainId ? 0 : 1;
        return ad != bd ? ad - bd : a.name.compareTo(b.name);
      });
    final inherited = e.project?.linkedActivityId == null
        ? null
        : _state.activities
            .firstWhereOrNull((a) => a.id == e.project!.linkedActivityId);
    final saved = await showModalBottomSheet<String>(
      context: context,
      // Scrollable : contextes + activités peuvent dépasser un écran — sans
      // ça le bouton Enregistrer devient inaccessible (constaté sur build).
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
              20, 20, 20, 24 + MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(e.action.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text('Où / avec quoi cette action est-elle réalisable ?',
                  style: TextStyle(
                      fontSize: 12.5,
                      color: Theme.of(ctx)
                          .colorScheme
                          .onSurface
                          .withOpacity(.55))),
              const SizedBox(height: 14),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final c in all)
                    FilterChip(
                      selected: selected.contains(c),
                      onSelected: (v) => setLocal(() {
                        v ? selected.add(c) : selected.remove(c);
                      }),
                      label: Text(c),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
              if (isProjectAction && timeActivities.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text('CHRONO SUR L\'ACTIVITÉ',
                    style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: .8,
                        color: Theme.of(ctx)
                            .colorScheme
                            .onSurface
                            .withOpacity(.45))),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final a in timeActivities.take(8))
                      ChoiceChip(
                        selected: linkedId == a.id,
                        onSelected: (_) => setLocal(() =>
                            linkedId = linkedId == a.id ? null : a.id),
                        showCheckmark: false,
                        label: Text(a.name),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
                if (linkedId == null && inherited != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('Hérite du projet : ${inherited.name}',
                        style: TextStyle(
                            fontSize: 11,
                            fontStyle: FontStyle.italic,
                            color: Theme.of(ctx)
                                .colorScheme
                                .onSurface
                                .withOpacity(.45))),
                  ),
              ],
              const SizedBox(height: 16),
              Row(children: [
                // Supprimer l'action (CRUD complet — confirmé après le pop).
                IconButton(
                  tooltip: 'Supprimer l\'action',
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.delete_outline,
                      size: 20, color: Theme.of(ctx).colorScheme.error),
                  onPressed: () => Navigator.pop(ctx, 'delete'),
                ),
                if (e.project != null)
                  TextButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _openProject(e.project!, targetTaskId: e.task?.id);
                    },
                    icon: const Icon(Icons.open_in_new, size: 15),
                    label: const Text('Fiche tâche'),
                  ),
                TextButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _scheduleAction(e);
                  },
                  icon: const Icon(Icons.event_outlined, size: 15),
                  label: const Text('Programmer'),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, 'save'),
                  child: const Text('Enregistrer'),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
    if (saved == 'save') {
      e.action.setContexts(selected.toList());
      if (isProjectAction) e.action.linkedActivityId = linkedId;
      await _persistEntry(e);
    } else if (saved == 'delete') {
      if (!mounted) return;
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Supprimer « ${e.action.title} » ?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Annuler')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Supprimer')),
          ],
        ),
      );
      if (ok != true) return;
      if (e.task != null) {
        e.task!.actions.remove(e.action);
      } else if (e.activity != null) {
        e.activity!.ownActions.remove(e.action);
      }
      await _persistEntry(e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Action supprimée'),
            duration: Duration(seconds: 2)));
      }
    }
  }

  /// Renomme un contexte custom : meta + propagation aux actions chargées qui
  /// le portent (tâches de projets + actions propres). Retourne le nouveau nom.
  Future<String?> _renameContext(String from) async {
    final ctrl = TextEditingController(text: from);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Renommer le contexte'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Ex : @atelier'),
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
    ctrl.dispose();
    if (result == null || result.isEmpty) return null;
    final to = result.startsWith('@') ? result : '@$result';
    if (to == from) return null;

    await _sync.renameCustomContext(from, to);
    for (final p in widget.logic.currentProjects) {
      var changed = false;
      for (final t in p.tasks) {
        for (final a in t.actions) {
          if (a.allContexts.contains(from)) {
            a.setContexts(
                [for (final c in a.allContexts) c == from ? to : c]);
            changed = true;
          }
        }
      }
      if (changed) await _sync.saveProjectTasks(p.id, p.tasks);
    }
    for (final act in _state.activities) {
      var changed = false;
      for (final a in act.ownActions) {
        if (a.allContexts.contains(from)) {
          a.setContexts([for (final c in a.allContexts) c == from ? to : c]);
          changed = true;
        }
      }
      if (changed) await _sync.updateOwnActions(act.id, act.ownActions);
    }
    final ni = _state.nowContexts.indexOf(from);
    if (ni >= 0) _state.nowContexts[ni] = to;
    widget.logic.onChange();
    return to;
  }

  // ── Programmer une action dans le programme du jour ────────────────────────
  // Demande user : date + heure + durée POUR LE PROGRAMME (pas le Gantt) —
  // l'action devient un bloc lié (lançable ▶, cochable).

  String _ymdOf(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _scheduleAction(_Entry e) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final days = [for (var i = 0; i < 7; i++) today.add(Duration(days: i))];
    const wd = ['lun', 'mar', 'mer', 'jeu', 'ven', 'sam', 'dim'];
    String dayLabel(DateTime d) {
      final diff = d.difference(today).inDays;
      if (diff == 0) return 'aujourd\'hui';
      if (diff == 1) return 'demain';
      return '${wd[d.weekday - 1]} ${d.day}';
    }

    var pickedDay = _ymdOf(today);
    var time = TimeOfDay.now();
    var duration = 30;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final cs2 = Theme.of(ctx).colorScheme;
          String hhmm() =>
              '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
          Text sectionLabel(String t) => Text(t,
              style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: .8,
                  color: cs2.onSurface.withOpacity(.45)));
          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
                20, 4, 20, 24 + MediaQuery.of(ctx).viewInsets.bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Programmer',
                    style:
                        TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(e.action.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12.5,
                        color: cs2.onSurface.withOpacity(.55))),
                const SizedBox(height: 14),
                sectionLabel('QUEL JOUR ?'),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final d in days)
                      ChoiceChip(
                        selected: pickedDay == _ymdOf(d),
                        onSelected: (_) =>
                            setLocal(() => pickedDay = _ymdOf(d)),
                        showCheckmark: false,
                        label: Text(dayLabel(d)),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(children: [
                  Icon(Icons.schedule_rounded,
                      size: 16, color: cs2.onSurface.withOpacity(.55)),
                  const SizedBox(width: 6),
                  Text('À ${hhmm()}',
                      style:
                          const TextStyle(fontWeight: FontWeight.w600)),
                  const Spacer(),
                  TextButton(
                    onPressed: () async {
                      final t = await showTimePicker(
                          context: ctx, initialTime: time);
                      if (t != null) setLocal(() => time = t);
                    },
                    child: const Text('Modifier'),
                  ),
                ]),
                sectionLabel('DURÉE'),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final d in const [15, 30, 45, 60, 90])
                      ChoiceChip(
                        selected: duration == d,
                        onSelected: (_) =>
                            setLocal(() => duration = d),
                        showCheckmark: false,
                        label: Text('$d min'),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    icon: const Icon(Icons.event_available_rounded,
                        size: 16),
                    label: const Text('Programmer'),
                    onPressed: () => Navigator.pop(ctx, true),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
    if (saved != true) return;
    final hhmm =
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    unawaited(_sync.addScheduleBlock(
        pickedDay,
        ScheduleBlock(
          startTime: hhmm,
          durationMin: duration,
          title: e.action.title,
          category: e.project != null ? 'project' : 'personal',
          projectId: e.project?.id,
          taskId: e.task?.id,
          activityId: e.chronoActivityId,
          actionId: e.action.id,
        )));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('📅 Programmé — $pickedDay à $hhmm ($duration min)'),
        duration: const Duration(seconds: 2),
      ));
    }
  }

  // ── Bouton @ : « je suis » + CRUD des contextes ─────────────────────────────

  Future<void> _showContextManager() async {
    final available = await _sync.fetchAvailableContexts();
    if (!mounted) return;
    final customs =
        available.where((c) => !kDefaultGtdContexts.contains(c)).toList();
    final addCtrl = TextEditingController();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final cs2 = Theme.of(ctx).colorScheme;
          return Padding(
            padding: EdgeInsets.fromLTRB(
                20, 20, 20, 24 + MediaQuery.of(ctx).viewInsets.bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Contextes',
                    style:
                        TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                Text('JE SUIS…',
                    style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: .8,
                        color: cs2.onSurface.withOpacity(.45))),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final c in [...kDefaultGtdContexts, ...customs])
                      FilterChip(
                        // Multi : on peut être @maison ET @ordinateur.
                        selected: _state.nowContexts.contains(c),
                        onSelected: (v) {
                          v
                              ? _state.nowContexts.add(c)
                              : _state.nowContexts.remove(c);
                          widget.logic.onChange();
                          setLocal(() {});
                          if (mounted) setState(() {});
                        },
                        label: Text(c),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Text('MES CONTEXTES PERSONNALISÉS',
                    style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: .8,
                        color: cs2.onSurface.withOpacity(.45))),
                const SizedBox(height: 6),
                if (customs.isEmpty)
                  Text('Aucun — ajoute le tien ci-dessous.',
                      style: TextStyle(
                          fontSize: 12.5,
                          color: cs2.onSurface.withOpacity(.5)))
                else ...[
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final c in customs)
                        InputChip(
                          label: Text(c),
                          visualDensity: VisualDensity.compact,
                          // Tap = renommer (propagé aux actions qui le portent)
                          onPressed: () async {
                            final to = await _renameContext(c);
                            if (to == null) return;
                            setLocal(() {
                              final i = customs.indexOf(c);
                              if (i >= 0) customs[i] = to;
                            });
                            if (mounted) setState(() {});
                          },
                          onDeleted: () async {
                            await _sync.removeCustomContext(c);
                            if (_state.nowContexts.remove(c)) {
                              widget.logic.onChange();
                            }
                            setLocal(() => customs.remove(c));
                            if (mounted) setState(() {});
                          },
                        ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('Tap pour renommer · ✕ pour supprimer',
                        style: TextStyle(
                            fontSize: 11,
                            fontStyle: FontStyle.italic,
                            color: cs2.onSurface.withOpacity(.4))),
                  ),
                ],
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: addCtrl,
                      decoration: const InputDecoration(
                          hintText: 'Ex : @atelier',
                          isDense: true,
                          border: OutlineInputBorder()),
                      onSubmitted: (_) {},
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () async {
                      final v = addCtrl.text.trim();
                      if (v.isEmpty) return;
                      final normalized = v.startsWith('@') ? v : '@$v';
                      await _sync.addCustomContext(normalized);
                      addCtrl.clear();
                      setLocal(() {
                        if (!customs.contains(normalized)) {
                          customs.add(normalized);
                        }
                      });
                    },
                    child: const Text('Ajouter'),
                  ),
                ]),
              ],
            ),
          );
        },
      ),
    );
    addCtrl.dispose();
    if (mounted) setState(() {});
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pGroups = _projectGroups();
    final aGroups = _activityGroups();
    final contexts = _allContexts(pGroups, aGroups).toList()..sort();
    // Contextes actifs = ceux qui existent encore dans la liste (un contexte
    // sans action ne filtre pas — il resterait invisible et bloquerait tout).
    final active = _state.nowContexts.where(contexts.contains).toSet();

    // Multi : réalisable si l'action porte AU MOINS UN des contextes actifs.
    bool visible(_Entry e) =>
        active.isEmpty ||
        e.action.allContexts.any(active.contains);

    // Un groupe sans AUCUNE entrée (projet à définir) reste visible hors
    // filtre de contexte ; un groupe vidé PAR le filtre est masqué.
    final visibleProjectGroups = [
      for (final g in pGroups)
        (
          project: g.project,
          entries: g.entries.where(visible).toList(),
          needsNext: g.entries.isEmpty,
        ),
    ]
        .where((g) =>
            g.entries.isNotEmpty || (g.needsNext && active.isEmpty))
        .toList();
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
              tooltip: 'Contextes : je suis… + gestion',
              icon: Icon(Icons.alternate_email, color: cs.primary, size: 24),
              onPressed: _showContextManager,
            ),
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
                    selected: active.contains(c),
                    onSelected: (_) {
                      // Multi : chaque tap ajoute/retire le contexte du set.
                      active.contains(c)
                          ? _state.nowContexts.remove(c)
                          : _state.nowContexts.add(c);
                      widget.logic.onChange();
                      setState(() {});
                    },
                    showCheckmark: false,
                    label: Text(c),
                    labelStyle: TextStyle(
                      fontSize: 12.5,
                      fontWeight: active.contains(c)
                          ? FontWeight.w600
                          : FontWeight.w500,
                      color: active.contains(c)
                          ? cs.primary
                          : cs.onSurface.withOpacity(.65),
                    ),
                    selectedColor: cs.primary.withOpacity(.14),
                    backgroundColor: cs.surfaceContainerHighest.withOpacity(.35),
                    side: BorderSide(
                        color: active.contains(c)
                            ? cs.primary.withOpacity(.5)
                            : Colors.transparent),
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
              ],
            ),
            if (active.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Réalisable ${(active.toList()..sort()).join(' ou ')} — le reste est masqué.',
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
                  active.isNotEmpty
                      ? 'Rien à faire ${(active.toList()..sort()).join(' ou ')} pour l\'instant.'
                      : 'Aucune action en attente.\nCapture une idée ou crée une action avec +.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 14, color: cs.onSurface.withOpacity(.45)),
                ),
              ),
            ),

          // ── @courses actif → la liste de courses du menu, cochable ────────
          // Subtilité d'accompagnement : être en courses, c'est avoir sa
          // liste sous la main — dérivée du menu, sans rien ressaisir.
          if (active.contains('@courses')) _CoursesSection(sync: _sync),

          // ── Par projet ─────────────────────────────────────────────────────
          for (final g in visibleProjectGroups) ...[
            _groupHeader(
              cs,
              g.project.title,
              domainColor(g.project.domainId, _state.activeDomains) ??
                  cs.primary,
              onTap: () => _openProject(g.project),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                // + direct : l'action atterrit dans le projet sans passer
                // par la fiche tâche (couche tâches ignorée côté user).
                IconButton(
                  tooltip: 'Ajouter une action',
                  icon: Icon(Icons.add,
                      size: 18, color: cs.primary.withOpacity(.75)),
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints(),
                  onPressed: () => _quickAddAction(g.project),
                ),
                const SizedBox(width: 6),
                // Pause GTD : sort les actions du projet des contextes/listes
                // sans l'archiver (il reste actif, juste « pas maintenant »).
                IconButton(
                  tooltip: 'Mettre en pause',
                  icon: Icon(Icons.pause_circle_outline,
                      size: 18, color: cs.onSurface.withOpacity(.4)),
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints(),
                  onPressed: () => _togglePause(g.project),
                ),
              ]),
            ),
            for (final e in g.entries) _entryTile(cs, e),
            if (g.entries.isEmpty) _defineTile(cs, g.project),
            const SizedBox(height: 10),
          ],

          // ── Projets en pause : repliés, réactivables en un tap ─────────────
          ...(() {
            final paused = widget.logic.currentProjects
                .where((p) => p.status == 'active' && p.paused)
                .toList();
            if (paused.isEmpty) return const <Widget>[];
            return <Widget>[
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 4),
                child: Text('EN PAUSE (${paused.length})',
                    style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: .8,
                        color: cs.onSurface.withOpacity(.4))),
              ),
              for (final p in paused)
                Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest.withOpacity(.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(children: [
                    Icon(Icons.pause, size: 14,
                        color: cs.onSurface.withOpacity(.35)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(p.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 13,
                              color: cs.onSurface.withOpacity(.5))),
                    ),
                    IconButton(
                      tooltip: 'Reprendre',
                      icon: Icon(Icons.play_circle_outline,
                          size: 20, color: cs.primary),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _togglePause(p),
                    ),
                  ]),
                ),
              const SizedBox(height: 10),
            ];
          })(),

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

          // ── Terminées : retrouver une action validée (et la décocher) ──────
          ...(() {
            final doneEntries = _doneEntries();
            if (doneEntries.isEmpty) return const <Widget>[];
            return <Widget>[
              const SizedBox(height: 10),
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => setState(() => _showDone = !_showDone),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(children: [
                    Icon(Icons.check_circle_outline,
                        size: 15, color: cs.onSurface.withOpacity(.4)),
                    const SizedBox(width: 8),
                    Text('TERMINÉES (${doneEntries.length})',
                        style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: .8,
                            color: cs.onSurface.withOpacity(.4))),
                    const Spacer(),
                    Icon(
                        _showDone
                            ? Icons.expand_less
                            : Icons.expand_more,
                        size: 18,
                        color: cs.onSurface.withOpacity(.35)),
                  ]),
                ),
              ),
              if (_showDone) ...[
                for (final e in doneEntries.take(_kDoneShown))
                  _doneTile(cs, e),
                if (doneEntries.length > _kDoneShown)
                  Padding(
                    padding: const EdgeInsets.only(top: 2, left: 4),
                    child: Text(
                        '… et ${doneEntries.length - _kDoneShown} plus anciennes.',
                        style: TextStyle(
                            fontSize: 11.5,
                            fontStyle: FontStyle.italic,
                            color: cs.onSurface.withOpacity(.4))),
                  ),
              ],
            ];
          })(),
        ],
      ),
    );
  }

  /// Plafond d'affichage de la liste « Terminées » (ListView non lazy).
  static const _kDoneShown = 50;

  /// « aujourd'hui » / « hier » / date courte — quand l'action a été validée.
  String _doneLabel(DateTime? d) {
    if (d == null) return '';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    final diff = today.difference(day).inDays;
    if (diff <= 0) return 'aujourd\'hui';
    if (diff == 1) return 'hier';
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
  }

  Widget _groupHeader(ColorScheme cs, String title, Color color,
      {VoidCallback? onTap, Widget? trailing}) {
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
          if (trailing != null) trailing,
          if (onTap != null)
            Icon(Icons.chevron_right,
                size: 16, color: cs.onSurface.withOpacity(.3)),
        ]),
      ),
    );
  }

  /// Projet sans action en attente : invitation GTD à définir la suivante.
  Widget _defineTile(ColorScheme cs, Project p) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withOpacity(.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.primary.withOpacity(.25)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        // Tap = dialog rapide (titre + contextes) — la fiche projet reste
        // accessible via l'en-tête de groupe / long press des actions.
        onTap: () => _quickAddAction(p),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(children: [
            Icon(Icons.edit_note, size: 18, color: cs.primary.withOpacity(.8)),
            const SizedBox(width: 8),
            const Expanded(
              child: Text('Définir la prochaine action',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      fontStyle: FontStyle.italic)),
            ),
          ]),
        ),
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
            // Tap = « Process » GTD : assigner les contextes de l'action.
            // Long press = fiche tâche (projets).
            onTap: () => _processAction(e),
            onLongPress: e.project != null
                ? () => _openProject(e.project!, targetTaskId: e.task?.id)
                : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(e.action.title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13.5, fontWeight: FontWeight.w600)),
                  // Couche tâches ignorée côté user : projet → action →
                  // @contextes, pas de niveau intermédiaire affiché.
                  if (e.action.allContexts.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                          (e.action.allContexts.toList()..sort()).join(' '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: cs.primary.withOpacity(.75))),
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

  /// Action validée : titre barré + porteur + date, décochable pour la
  /// remettre en attente.
  Widget _doneTile(ColorScheme cs, _Entry e) {
    final parent = e.project?.title ?? e.activity?.name ?? '';
    final when = _doneLabel(e.action.doneAt);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withOpacity(.18),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [
        Checkbox(
          value: true,
          shape: const CircleBorder(),
          onChanged: (v) => _toggleDone(e, v ?? false),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(e.action.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w500,
                        decoration: TextDecoration.lineThrough,
                        color: cs.onSurface.withOpacity(.55))),
                if (parent.isNotEmpty || when.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                        [
                          if (parent.isNotEmpty) parent,
                          if (when.isNotEmpty) when,
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 11,
                            color: cs.onSurface.withOpacity(.4))),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
      ]),
    );
  }
}

/// Liste de courses du menu (artefact `weekly_menu`), cochable — affichée
/// dans l'onglet Actions quand le contexte @courses est actif. L'état coché
/// vit sur l'artefact (partagé avec la fiche menu de l'Accueil).
class _CoursesSection extends StatefulWidget {
  final FirestoreSync sync;
  const _CoursesSection({required this.sync});

  @override
  State<_CoursesSection> createState() => _CoursesSectionState();
}

class _CoursesSectionState extends State<_CoursesSection> {
  // Stream créé UNE FOIS (même leçon que ArtifactShortcuts : un stream neuf
  // par build = StreamBuilder qui repart de zéro à chaque rebuild du parent).
  late final Stream<List<Artifact>> _stream =
      widget.sync.streamArtifacts();
  // Partagé entre recréations du State (liste scrollée) — même leçon que
  // ObjectivesCard/ArtifactShortcuts : pas de repli transitoire au retour.
  static List<Artifact> _last = const [];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return StreamBuilder<List<Artifact>>(
      stream: _stream,
      builder: (ctx, snap) {
        if (snap.hasData) _last = snap.data!;
        final menus = _last
            .where((a) =>
                !a.deleted &&
                a.kind == 'weekly_menu' &&
                a.shoppingList.isNotEmpty)
            .toList();
        if (menus.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final m in menus) ...[
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 6),
                child: Row(children: [
                  Icon(Icons.shopping_cart_outlined,
                      size: 14, color: cs.onSurface.withOpacity(.45)),
                  const SizedBox(width: 6),
                  Text('COURSES — MENU',
                      style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: .8,
                          color: cs.onSurface.withOpacity(.45))),
                  const Spacer(),
                  Text(
                      '${m.shoppingList.where((s) => !s.checked).length} restants',
                      style: TextStyle(
                          fontSize: 11,
                          color: cs.onSurface.withOpacity(.4))),
                ]),
              ),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final s in m.shoppingList)
                    FilterChip(
                      selected: s.checked,
                      onSelected: (v) {
                        s.checked = v;
                        widget.sync.saveArtifact(m);
                      },
                      label: Text(
                          s.qty.isEmpty ? s.label : '${s.label} ${s.qty}',
                          style: TextStyle(
                              fontSize: 12,
                              decoration: s.checked
                                  ? TextDecoration.lineThrough
                                  : null)),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
              const SizedBox(height: 12),
            ],
          ],
        );
      },
    );
  }
}
