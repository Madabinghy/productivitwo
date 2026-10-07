import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/checklist_logic.dart';
import 'package:productivitwo_v1/utils/duration_fmt.dart';
import 'package:productivitwo_v1/utils/intervention_builder.dart';
import 'package:productivitwo_v1/utils/time_spent.dart';
import 'package:productivitwo_v1/utils/project_health.dart';
import 'package:productivitwo_v1/web/action_dialogs.dart';
import 'package:productivitwo_v1/web/theme_tokens.dart';

const _tabular = [FontFeature.tabularFigures()];

/// Onglet « Réalisation » de la fiche projet (le plus fin des trois : Vision ·
/// Plan d'action · Réalisation) : chaque action traitée comme un micro-projet. À gauche, le plan (phases → tâches → actions) ; à droite,
/// l'espace de travail de l'action sélectionnée : étapes cochables,
/// réordonnables, renommables, ajout à la volée, marquer faite / rouvrir.
///
/// Le modèle ne change pas (`TaskAction.checklist` = `ChecklistItem[]`) : tout
/// ce qui est édité ici se coche aussi sur mobile (carte MAINTENANT, écran
/// Focus) et par le MCP (`mark_checklist_item`). Règle d'achèvement partagée
/// dans `utils/checklist_logic.dart`.
class ProjectChecklistsView extends StatefulWidget {
  final Project project;
  final FirestoreSync sync;
  final List<Activity> activities;
  final VoidCallback onChanged;
  const ProjectChecklistsView({
    super.key,
    required this.project,
    required this.sync,
    this.activities = const [],
    required this.onChanged,
  });

  @override
  State<ProjectChecklistsView> createState() => _ProjectChecklistsViewState();
}

enum _Filter { all, open, bare }

class _ProjectChecklistsViewState extends State<ProjectChecklistsView> {
  String? _selectedId;
  _Filter _filter = _Filter.open;
  bool _hideDoneItems = false;
  // Mode étroit : l'espace de travail remplace la liste.
  bool _narrowDetail = false;
  // Minutes réellement passées par action (chrono ciblé, 365 j).
  Map<String, int> _spent = const {};
  // Bilan de séance (clôture d'une intervention) : brouillons par intervention.
  final Map<String, TextEditingController> _debriefCtrls = {};
  final Map<String, List<String>> _carryDrafts = {};
  final TextEditingController _carryAddCtrl = TextEditingController();
  bool _savingDebrief = false;

  @override
  void dispose() {
    for (final c in _debriefCtrls.values) {
      c.dispose();
    }
    _carryAddCtrl.dispose();
    super.dispose();
  }

  Project get _p => widget.project;

  @override
  void initState() {
    super.initState();
    widget.sync.fetchRecentSessions(365).then((sessions) {
      if (mounted) setState(() => _spent = spentByAction(sessions));
    });
  }

  /// Actions dans l'ordre du plan (phases → tâches en ordre Gantt → actions).
  List<_Entry> get _entries {
    final out = <_Entry>[];
    for (final sec in phaseSections(_p)) {
      for (final t in sec.tasks) {
        for (final a in t.actions) {
          out.add(_Entry(phase: sec.phase, task: t, action: a));
        }
      }
    }
    return out;
  }

  bool _passes(_Entry e) => switch (_filter) {
        _Filter.all => true,
        _Filter.open => !e.action.done,
        _Filter.bare => e.action.checklist.isEmpty && !e.action.done,
      };

  _Entry? get _selected {
    final all = _entries;
    final byId = all.where((e) => e.action.id == _selectedId).firstOrNull;
    if (byId != null) return byId;
    // Défaut : première action ouverte, sinon la première.
    return all.where((e) => !e.action.done).firstOrNull ?? all.firstOrNull;
  }

  Future<void> _save() async {
    await widget.sync.saveProjectTasks(_p.id, _p.tasks);
    widget.onChanged();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 2200),
      ));
  }

  // ── Mutations ───────────────────────────────────────────────────────────────

  Future<void> _toggleItem(TaskAction a, ChecklistItem c, bool v) async {
    final changed = setChecklistItem(a, c.id, v);
    setState(() {});
    await _save();
    if (changed) _snack(a.done ? 'Action faite : ${a.title}' : 'Action rouverte : ${a.title}');
  }

  Future<void> _addItem(TaskAction a, String title) async {
    if (addChecklistItem(a, title) == null) return;
    setState(() {});
    await _save();
  }

  Future<void> _removeItem(TaskAction a, ChecklistItem c) async {
    final index = a.checklist.indexOf(c);
    setState(() => removeChecklistItem(a, c.id));
    await _save();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('Étape retirée : ${c.title}'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'Annuler',
          textColor: kBPrimary,
          onPressed: () async {
            if (a.checklist.any((x) => x.id == c.id)) return;
            setState(() => a.checklist.insert(index.clamp(0, a.checklist.length), c));
            await _save();
          },
        ),
      ));
  }

  Future<void> _renameItem(TaskAction a, ChecklistItem c, String title) async {
    if (!renameChecklistItem(a, c.id, title)) return;
    setState(() {});
    await _save();
  }

  Future<void> _moveItem(TaskAction a, int oldIndex, int newIndex) async {
    setState(() => moveChecklistItem(a, oldIndex, newIndex));
    await _save();
  }

  Future<void> _setDone(TaskAction a, bool done) async {
    setState(() => setActionDone(a, done));
    await _save();
    _snack(done ? 'Action faite : ${a.title}' : 'Action rouverte : ${a.title}');
  }

  Future<void> _editAction(_Entry e) async {
    final changed = await showEditActionDialog(context,
        sync: widget.sync, action: e.action, projects: [_p], project: _p, task: e.task);
    if (changed && mounted) {
      setState(() {});
      widget.onChanged();
    }
  }

  void _select(_Entry e, {bool narrow = false}) => setState(() {
        _selectedId = e.action.id;
        if (narrow) _narrowDetail = true;
      });

  void _step(int dir) {
    final list = _entries.where(_passes).toList();
    if (list.isEmpty) return;
    final cur = _selected;
    var i = cur == null ? -1 : list.indexWhere((e) => e.action.id == cur.action.id);
    i = (i + dir).clamp(0, list.length - 1);
    setState(() => _selectedId = list[i].action.id);
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final entries = _entries;
    if (entries.isEmpty) return _empty();
    return LayoutBuilder(builder: (ctx, box) {
      final wide = box.maxWidth >= 1100;
      final sel = _selected;
      if (wide) {
        return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(width: 380, child: _navigator(entries, narrow: false)),
          const VerticalDivider(width: 1, color: kBLine),
          Expanded(child: sel == null ? _noSelection() : _workspace(sel)),
        ]);
      }
      if (_narrowDetail && sel != null) {
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() => _narrowDetail = false),
                icon: const Icon(Icons.chevron_left, size: 18),
                label: const Text('Toutes les actions'),
                style: TextButton.styleFrom(foregroundColor: kBPrimary),
              ),
            ),
          ),
          Expanded(child: _workspace(sel)),
        ]);
      }
      return _navigator(entries, narrow: true);
    });
  }

  Widget _empty() => const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.checklist_rtl, size: 36, color: kBText4),
            SizedBox(height: 12),
            Text('Aucune action dans ce projet.',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: kBText2)),
            SizedBox(height: 6),
            Text(
              'Ajoute des actions à tes tâches dans le plan d\'action : chacune pourra\n'
              'être découpée ici en étapes, cochables aussi sur mobile pendant un bloc.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: kBText3, height: 1.4),
            ),
          ]),
        ),
      );

  Widget _noSelection() => const Center(
        child: Text('Choisis une action à gauche.', style: TextStyle(color: kBText3)),
      );

  // ── Navigateur (gauche) ─────────────────────────────────────────────────────

  Widget _navigator(List<_Entry> entries, {required bool narrow}) {
    final shown = entries.where(_passes).toList();
    final sel = _selected;
    final totalItems = entries.fold<int>(0, (s, e) => s + e.action.checklistTotal);
    final doneItems = entries.fold<int>(0, (s, e) => s + e.action.checklistDone);
    final withList = entries.where((e) => e.action.checklist.isNotEmpty).length;

    final rows = <Widget>[];
    ProjectPhase? lastPhase;
    var firstSection = true;
    ProjectTask? lastTask;
    for (final e in shown) {
      final phaseChanged = firstSection || e.phase?.id != lastPhase?.id;
      if (phaseChanged && _p.phases.isNotEmpty) {
        rows.add(Padding(
          padding: EdgeInsets.fromLTRB(16, firstSection ? 4 : 16, 16, 4),
          child: Text((e.phase?.label ?? 'Sans phase').toUpperCase(),
              style: const TextStyle(
                  fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: .8, color: kBText4)),
        ));
      }
      if (phaseChanged || e.task.id != lastTask?.id) {
        final t = e.task;
        final open = t.actions.where((a) => !a.done).length;
        rows.add(Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),
          child: Row(children: [
            Icon(
                t.status == 'done' ? Icons.check_circle_outline : Icons.radio_button_unchecked,
                size: 13,
                color: t.status == 'done' ? kBPrimaryDark : kBText4),
            const SizedBox(width: 6),
            Expanded(
              child: Text(t.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w600, color: kBText2)),
            ),
            Text('$open à faire',
                style: const TextStyle(fontSize: 10.5, color: kBText4, fontFeatures: _tabular)),
          ]),
        ));
      }
      rows.add(_actionRow(e, selected: !narrow && sel?.action.id == e.action.id, narrow: narrow));
      lastPhase = e.phase;
      lastTask = e.task;
      firstSection = false;
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            '${entries.length} action${entries.length > 1 ? 's' : ''} · $withList avec étapes'
            '${totalItems > 0 ? ' · $doneItems / $totalItems étape${totalItems > 1 ? 's' : ''}' : ''}',
            style: const TextStyle(fontSize: 12, color: kBText3, fontFeatures: _tabular),
          ),
          const SizedBox(height: 10),
          Wrap(spacing: 6, runSpacing: 6, children: [
            _filterChip('À faire', _Filter.open),
            _filterChip('Sans étapes', _Filter.bare),
            _filterChip('Toutes', _Filter.all),
          ]),
        ]),
      ),
      const Divider(height: 1, color: kBLine),
      Expanded(
        child: shown.isEmpty
            ? Center(
                child: Text(
                  switch (_filter) {
                    _Filter.open => 'Tout est fait. 🎉',
                    _Filter.bare => 'Toutes les actions ouvertes ont des étapes.',
                    _Filter.all => 'Aucune action.',
                  },
                  style: const TextStyle(color: kBText3, fontSize: 13),
                ),
              )
            : ListView(padding: const EdgeInsets.only(bottom: 24), children: rows),
      ),
    ]);
  }

  Widget _filterChip(String label, _Filter f) {
    final on = _filter == f;
    return InkWell(
      onTap: () => setState(() => _filter = f),
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: on ? kBActive : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: on ? kBPrimary.withOpacity(.35) : kBLine),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600, color: on ? kBText : kBText3)),
      ),
    );
  }

  Widget _actionRow(_Entry e, {required bool selected, required bool narrow}) {
    final a = e.action;
    final total = a.checklistTotal, done = a.checklistDone;
    final next = nextChecklistItem(a);
    return InkWell(
      onTap: () => _select(e, narrow: narrow),
      child: Container(
        margin: const EdgeInsets.fromLTRB(10, 1, 10, 1),
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        decoration: BoxDecoration(
          color: selected ? kBActive : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: selected ? kBPrimary.withOpacity(.35) : Colors.transparent),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(a.done ? Icons.check_circle : Icons.radio_button_unchecked,
                size: 15, color: a.done ? kBPrimaryDark : kBText3),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(a.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 13,
                      color: a.done ? kBText4 : kBText,
                      decoration: a.done ? TextDecoration.lineThrough : null,
                      decorationColor: kBText4)),
              if (total > 0) ...[
                const SizedBox(height: 5),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: done / total,
                    minHeight: 3,
                    backgroundColor: kBLine,
                    valueColor: AlwaysStoppedAnimation(
                        done == total ? kBPrimaryDark : kBPrimary.withOpacity(.7)),
                  ),
                ),
                if (next != null && !a.done) ...[
                  const SizedBox(height: 4),
                  Text('→ ${next.title}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11.5, color: kBText3)),
                ],
              ] else if (!a.done) ...[
                const SizedBox(height: 3),
                const Text('Pas encore d\'étapes',
                    style: TextStyle(fontSize: 11, color: kBText4, fontStyle: FontStyle.italic)),
              ],
            ]),
          ),
          const SizedBox(width: 8),
          if (total > 0)
            Text('$done/$total',
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: done == total ? kBPrimaryDark : kBText3,
                    fontFeatures: _tabular)),
          if (narrow) const Icon(Icons.chevron_right, size: 16, color: kBText4),
        ]),
      ),
    );
  }

  // ── Espace de travail (droite) ──────────────────────────────────────────────

  Widget _workspace(_Entry e) {
    final a = e.action;
    final total = a.checklistTotal, done = a.checklistDone;
    final linked = a.linkedActivityId == null
        ? null
        : widget.activities.where((x) => x.id == a.linkedActivityId).firstOrNull;
    final list = _entries.where(_passes).toList();
    final idx = list.indexWhere((x) => x.action.id == a.id);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 18, 28, 32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // Fil d'Ariane + navigation
          Row(children: [
            Expanded(
              child: Text(
                '${e.phase != null ? '${e.phase!.label} › ' : ''}${e.task.title}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: kBText3),
              ),
            ),
            IconButton(
              tooltip: 'Action précédente',
              icon: const Icon(Icons.keyboard_arrow_up, size: 18),
              color: kBText3,
              visualDensity: VisualDensity.compact,
              onPressed: idx > 0 ? () => _step(-1) : null,
            ),
            IconButton(
              tooltip: 'Action suivante',
              icon: const Icon(Icons.keyboard_arrow_down, size: 18),
              color: kBText3,
              visualDensity: VisualDensity.compact,
              onPressed: idx >= 0 && idx < list.length - 1 ? () => _step(1) : null,
            ),
          ]),
          const SizedBox(height: 6),
          // Titre + édition
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => _setDone(a, !a.done),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(a.done ? Icons.check_circle : Icons.radio_button_unchecked,
                    size: 24, color: a.done ? kBPrimaryDark : kBText3),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: InkWell(
                onTap: () => _editAction(e),
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(a.title,
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -.2,
                          color: a.done ? kBText3 : kBText,
                          decoration: a.done ? TextDecoration.lineThrough : null,
                          decorationColor: kBText4)),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Modifier l\'action (titre, contextes, estimation, déplacer…)',
              icon: const Icon(Icons.edit_outlined, size: 17, color: kBText3),
              visualDensity: VisualDensity.compact,
              onPressed: () => _editAction(e),
            ),
          ]),
          const SizedBox(height: 8),
          // Méta
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final c in a.allContexts) _pill(c, kBText3),
            if (a.estimatedMin != null) _pill('≈ ${fmtMin(a.estimatedMin!)}', kBText3),
            if (spentLabel(_spent[a.id] ?? 0, a.estimatedMin, fmtMin) case final sp?)
              _pill(sp.label, sp.over ? kBAlert : kBText3),
            if (linked != null) _pill('⏱ ${linked.name}', kBPrimary),
            if (a.done && a.doneAt != null) _pill('Faite le ${_dmy(a.doneAt!)}', kBPrimaryDark),
          ]),
          const SizedBox(height: 18),
          ..._interventionCards(e),
          // Progression
          Row(children: [
            Expanded(
              child: Text(
                total == 0
                    ? 'Étapes'
                    : '$done / $total étape${total > 1 ? 's' : ''}'
                        '${done < total ? ' · reste ${total - done}' : ' · terminé'}',
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600, color: kBText2, fontFeatures: _tabular),
              ),
            ),
            if (total > 0)
              InkWell(
                onTap: () => setState(() => _hideDoneItems = !_hideDoneItems),
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: Text(_hideDoneItems ? 'Afficher les faites' : 'Masquer les faites',
                      style: const TextStyle(fontSize: 12, color: kBPrimary)),
                ),
              ),
          ]),
          if (total > 0) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: done / total,
                minHeight: 5,
                backgroundColor: kBLine,
                valueColor: AlwaysStoppedAnimation(done == total ? kBPrimaryDark : kBPrimary),
              ),
            ),
          ],
          const SizedBox(height: 10),
          // Étapes
          Container(
            decoration: BoxDecoration(
              color: kBSurface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: kBLine),
            ),
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (total == 0)
                const Padding(
                  padding: EdgeInsets.fromLTRB(10, 10, 10, 6),
                  child: Text(
                    'Découpe cette action en étapes concrètes : la dernière cochée marque '
                    'l\'action faite. Les étapes se cochent aussi sur mobile pendant un bloc.',
                    style: TextStyle(fontSize: 12.5, color: kBText3, height: 1.4),
                  ),
                )
              else
                _ItemsList(
                  key: ValueKey('items/${a.id}'),
                  action: a,
                  hideDone: _hideDoneItems,
                  onToggle: (c, v) => _toggleItem(a, c, v),
                  onRename: (c, t) => _renameItem(a, c, t),
                  onDelete: (c) => _removeItem(a, c),
                  onMove: (o, n) => _moveItem(a, o, n),
                ),
              _AddField(key: ValueKey('add/${a.id}'), onAdd: (t) => _addItem(a, t)),
            ]),
          ),
          const SizedBox(height: 16),
          // Pied : marquer faite / rouvrir
          Row(children: [
            if (!a.done)
              FilledButton.icon(
                onPressed: () => _setDone(a, true),
                icon: const Icon(Icons.check, size: 16),
                label: Text(total > done ? 'Marquer l\'action faite' : 'Marquer faite'),
                style: FilledButton.styleFrom(
                    backgroundColor: kBPrimary,
                    foregroundColor: kBBg,
                    visualDensity: VisualDensity.compact),
              )
            else
              OutlinedButton.icon(
                onPressed: () => _setDone(a, false),
                icon: const Icon(Icons.undo, size: 16),
                label: const Text('Rouvrir l\'action'),
                style: OutlinedButton.styleFrom(
                    foregroundColor: kBText2,
                    side: const BorderSide(color: kBLine),
                    visualDensity: VisualDensity.compact),
              ),
            const Spacer(),
            Text(
              '${e.task.actions.where((x) => x.done).length} / ${e.task.actions.length} '
              'action${e.task.actions.length > 1 ? 's' : ''} de la tâche',
              style: const TextStyle(fontSize: 11.5, color: kBText4, fontFeatures: _tabular),
            ),
          ]),
        ]),
      ),
    );
  }

  // ── Séances : bilan de clôture, rappel du bilan précédent ──────────────────

  ProjectIntervention? _interventionOf(ProjectTask t) =>
      t.interventionId == null ? null : _p.interventions.where((i) => i.id == t.interventionId).firstOrNull;

  /// Dernière séance datée avant [i] qui porte un bilan.
  ProjectIntervention? _previousWithDebrief(ProjectIntervention i) {
    final before = _p.interventions
        .where((x) =>
            x.id != i.id &&
            x.date.isBefore(i.date) &&
            ((x.debriefText ?? '').trim().isNotEmpty || x.carryOver.isNotEmpty))
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    return before.lastOrNull;
  }

  List<Widget> _interventionCards(_Entry e) {
    final i = _interventionOf(e.task);
    if (i == null) return const [];
    final out = <Widget>[];
    if (e.task.interventionRole == 'closure') {
      out.add(_debriefCard(i));
    } else if (e.task.interventionRole == 'prep') {
      final prev = _previousWithDebrief(i);
      if (prev != null) out.add(_previousDebriefCard(prev));
    } else if (e.task.interventionRole == 'session') {
      out.add(_sessionInfoCard(i));
    }
    if (out.isNotEmpty) out.add(const SizedBox(height: 18));
    return out;
  }

  Widget _interventionBox({required Widget child}) => Container(
        decoration: BoxDecoration(
          color: kBSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: kBLine),
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
        child: child,
      );

  Widget _sessionInfoCard(ProjectIntervention i) => _interventionBox(
        child: Row(children: [
          const Icon(Icons.school_outlined, size: 16, color: kBPrimary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${interventionDayLabel(i.date)} · ${hmFr(i.startTime)}–${hmFr(i.endTime)}'
              '${i.place != null && i.place!.isNotEmpty ? ' · ${i.place}' : ''}',
              style: const TextStyle(fontSize: 13, color: kBText2, fontFeatures: _tabular),
            ),
          ),
        ]),
      );

  Widget _previousDebriefCard(ProjectIntervention prev) => _interventionBox(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('BILAN DE LA SÉANCE PRÉCÉDENTE · ${interventionDayLabel(prev.date)}',
              style: const TextStyle(
                  fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.3, color: kBText3)),
          if ((prev.debriefText ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(prev.debriefText!.trim(),
                style: const TextStyle(fontSize: 13, color: kBText2, height: 1.4)),
          ],
          if (prev.carryOver.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final c in prev.carryOver)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('↳ ', style: TextStyle(fontSize: 13, color: kBText3)),
                  Expanded(child: Text(c.title, style: const TextStyle(fontSize: 13, color: kBText))),
                ]),
              ),
            const SizedBox(height: 6),
            const Text('Ces points sont dans la checklist de « Adapter au bilan précédent ».',
                style: TextStyle(fontSize: 11.5, color: kBText4)),
          ],
        ]),
      );

  Widget _debriefCard(ProjectIntervention i) {
    final ctrl = _debriefCtrls.putIfAbsent(i.id, () => TextEditingController(text: i.debriefText ?? ''));
    final draft = _carryDrafts.putIfAbsent(i.id, () => i.carryOver.map((c) => c.title).toList());
    final next = nextInterventionAfter(_p, i);
    void addPoint() {
      final v = _carryAddCtrl.text.trim();
      if (v.isEmpty) return;
      setState(() {
        draft.add(v);
        _carryAddCtrl.clear();
      });
    }

    return _interventionBox(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.rate_review_outlined, size: 16, color: kBPrimary),
          const SizedBox(width: 8),
          Expanded(
            child: Text('BILAN DE LA SÉANCE · ${interventionDayLabel(i.date)}',
                style: const TextStyle(
                    fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.3, color: kBText3)),
          ),
          if (i.debriefAt != null)
            Text('enregistré le ${_dmy(i.debriefAt!)}',
                style: const TextStyle(fontSize: 11.5, color: kBText4)),
        ]),
        const SizedBox(height: 10),
        TextField(
          controller: ctrl,
          minLines: 2,
          maxLines: 6,
          style: const TextStyle(fontSize: 13.5, color: kBText, height: 1.4),
          decoration: InputDecoration(
            hintText: 'Comment ça s\'est passé ? Ce qui a marché, ce qui a coincé, où vous en êtes…',
            hintStyle: const TextStyle(fontSize: 13, color: kBText4),
            filled: true,
            fillColor: const Color(0x0FFFFFFF),
            contentPadding: const EdgeInsets.all(12),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: kBLine)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: kBLine)),
          ),
        ),
        const SizedBox(height: 12),
        const Text('À REPRENDRE LA PROCHAINE FOIS',
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.3, color: kBText3)),
        const SizedBox(height: 6),
        for (var k = 0; k < draft.length; k++)
          Row(children: [
            const Icon(Icons.subdirectory_arrow_right, size: 14, color: kBText3),
            const SizedBox(width: 6),
            Expanded(child: Text(draft[k], style: const TextStyle(fontSize: 13, color: kBText))),
            IconButton(
              tooltip: 'Retirer',
              icon: const Icon(Icons.close, size: 14, color: kBText4),
              visualDensity: VisualDensity.compact,
              onPressed: () => setState(() => draft.removeAt(k)),
            ),
          ]),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _carryAddCtrl,
              style: const TextStyle(fontSize: 13, color: kBText),
              decoration: const InputDecoration(
                hintText: 'Ajouter un point (Entrée)',
                hintStyle: TextStyle(fontSize: 12.5, color: kBText4),
                isDense: true,
                border: InputBorder.none,
              ),
              onSubmitted: (_) => addPoint(),
            ),
          ),
          IconButton(
            tooltip: 'Ajouter',
            icon: const Icon(Icons.add, size: 16, color: kBPrimary),
            visualDensity: VisualDensity.compact,
            onPressed: addPoint,
          ),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: Text(
              next == null
                  ? 'Pas de séance suivante planifiée : les points seront repris à la création de la prochaine.'
                  : 'Les points iront dans la prépa de « ${next.title} » (${interventionDayLabel(next.date)}).',
              style: const TextStyle(fontSize: 11.5, color: kBText4),
            ),
          ),
          const SizedBox(width: 10),
          FilledButton(
            onPressed: _savingDebrief ? null : () => _saveDebrief(i, ctrl.text, draft),
            style: FilledButton.styleFrom(
              backgroundColor: kBPrimary,
              foregroundColor: kBBg,
              shape: const StadiumBorder(),
              textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
            child: const Text('Enregistrer le bilan'),
          ),
        ]),
      ]),
    );
  }

  Future<void> _saveDebrief(ProjectIntervention i, String text, List<String> points) async {
    setState(() => _savingDebrief = true);
    addPointIfPending() {
      final v = _carryAddCtrl.text.trim();
      if (v.isNotEmpty && !points.contains(v)) points.add(v);
      _carryAddCtrl.clear();
    }

    addPointIfPending();
    i.debriefText = text.trim().isEmpty ? null : text.trim();
    final kept = <ChecklistItem>[];
    for (final t in points) {
      kept.add(i.carryOver.where((c) => c.title == t).firstOrNull ?? ChecklistItem(title: t));
    }
    i.carryOver = kept;
    i.debriefAt = DateTime.now();
    final fed = applyCarryOver(_p, i, points);
    try {
      await widget.sync.saveProject(_p);
      widget.onChanged();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(fed == null
            ? 'Bilan enregistré.'
            : 'Bilan enregistré · ${points.length} point${points.length > 1 ? 's' : ''} poussé'
                '${points.length > 1 ? 's' : ''} dans la prépa de « ${fed.title} ».'),
        duration: const Duration(seconds: 4),
      ));
    } finally {
      if (mounted) setState(() => _savingDebrief = false);
    }
  }

  Widget _pill(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
            color: color.withOpacity(.12), borderRadius: BorderRadius.circular(999)),
        child: Text(text,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
      );
}

String _dmy(DateTime d) {
  const m = ['janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin',
             'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'];
  return '${d.day} ${m[d.month - 1]}';
}

class _Entry {
  final ProjectPhase? phase;
  final ProjectTask task;
  final TaskAction action;
  const _Entry({required this.phase, required this.task, required this.action});
}

// ── Liste d'étapes : cocher, renommer en place, réordonner, retirer ──────────

class _ItemsList extends StatefulWidget {
  final TaskAction action;
  final bool hideDone;
  final void Function(ChecklistItem, bool) onToggle;
  final void Function(ChecklistItem, String) onRename;
  final void Function(ChecklistItem) onDelete;
  final void Function(int oldIndex, int newIndex) onMove;
  const _ItemsList({
    super.key,
    required this.action,
    required this.hideDone,
    required this.onToggle,
    required this.onRename,
    required this.onDelete,
    required this.onMove,
  });

  @override
  State<_ItemsList> createState() => _ItemsListState();
}

class _ItemsListState extends State<_ItemsList> {
  String? _editingId;
  String? _hoverId;
  final _ctrl = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _startEdit(ChecklistItem c) {
    _ctrl.text = c.title;
    _ctrl.selection = TextSelection(baseOffset: 0, extentOffset: c.title.length);
    setState(() => _editingId = c.id);
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  void _commit(ChecklistItem c) {
    final t = _ctrl.text;
    setState(() => _editingId = null);
    widget.onRename(c, t);
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.action.checklist;
    // Le réordonnancement porte sur la liste complète : masquer les faites
    // désactive le glisser (indices différents).
    final shown = widget.hideDone ? items.where((c) => !c.done).toList() : items;
    final canReorder = !widget.hideDone && shown.length > 1;
    final next = nextChecklistItem(widget.action);

    Widget row(int i, ChecklistItem c) {
      final editing = _editingId == c.id;
      final hover = _hoverId == c.id;
      final isNext = !c.done && c.id == next?.id && !widget.action.done;
      return MouseRegion(
        key: ValueKey(c.id),
        onEnter: (_) => setState(() => _hoverId = c.id),
        onExit: (_) => setState(() => _hoverId = null),
        child: Container(
          decoration: BoxDecoration(
            color: isNext ? kBPrimary.withOpacity(.06) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Row(children: [
            if (canReorder)
              ReorderableDragStartListener(
                index: i,
                child: MouseRegion(
                  cursor: SystemMouseCursors.grab,
                  child: Icon(Icons.drag_indicator,
                      size: 16, color: hover ? kBText3 : kBText4.withOpacity(.35)),
                ),
              )
            else
              const SizedBox(width: 16),
            const SizedBox(width: 4),
            InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => widget.onToggle(c, !c.done),
              child: Padding(
                padding: const EdgeInsets.all(5),
                child: Icon(c.done ? Icons.check_circle : Icons.radio_button_unchecked,
                    size: 18, color: c.done ? kBPrimaryDark : isNext ? kBPrimary : kBText3),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: editing
                  ? CallbackShortcuts(
                      bindings: {
                        const SingleActivator(LogicalKeyboardKey.escape): () =>
                            setState(() => _editingId = null),
                      },
                      child: TextField(
                        controller: _ctrl,
                        focusNode: _focus,
                        style: const TextStyle(fontSize: 13.5, color: kBText),
                        decoration: const InputDecoration(
                            isDense: true,
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(vertical: 8)),
                        onSubmitted: (_) => _commit(c),
                        onTapOutside: (_) => _commit(c),
                      ),
                    )
                  : InkWell(
                      onTap: () => _startEdit(c),
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(c.title,
                            style: TextStyle(
                                fontSize: 13.5,
                                color: c.done ? kBText4 : kBText,
                                decoration: c.done ? TextDecoration.lineThrough : null,
                                decorationColor: kBText4)),
                      ),
                    ),
            ),
            if (c.done && c.doneAt != null && hover)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Text(_dmy(c.doneAt!),
                    style: const TextStyle(fontSize: 10.5, color: kBText4)),
              ),
            Opacity(
              opacity: hover || editing ? 1 : 0,
              child: IconButton(
                tooltip: 'Retirer l\'étape',
                icon: const Icon(Icons.close, size: 15),
                color: kBText3,
                visualDensity: VisualDensity.compact,
                onPressed: () => widget.onDelete(c),
              ),
            ),
          ]),
        ),
      );
    }

    if (!canReorder) {
      return Column(children: [for (var i = 0; i < shown.length; i++) row(i, shown[i])]);
    }
    return ReorderableListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      onReorder: widget.onMove,
      proxyDecorator: (child, _, __) => Material(
        color: kBRaised,
        borderRadius: BorderRadius.circular(8),
        elevation: 4,
        child: child,
      ),
      children: [for (var i = 0; i < shown.length; i++) row(i, shown[i])],
    );
  }
}

// ── Champ d'ajout : Entrée ajoute et garde le focus ──────────────────────────

class _AddField extends StatefulWidget {
  final void Function(String) onAdd;
  const _AddField({super.key, required this.onAdd});

  @override
  State<_AddField> createState() => _AddFieldState();
}

class _AddFieldState extends State<_AddField> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submit() {
    final t = _ctrl.text.trim();
    if (t.isEmpty) return;
    widget.onAdd(t);
    _ctrl.clear();
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 2, 4, 0),
      child: Row(children: [
        const Icon(Icons.add, size: 18, color: kBText4),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: _ctrl,
            focusNode: _focus,
            style: const TextStyle(fontSize: 13.5, color: kBText),
            decoration: const InputDecoration(
              hintText: 'Ajouter une étape… (Entrée pour enchaîner)',
              hintStyle: TextStyle(color: kBText4, fontSize: 13),
              isDense: true,
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(vertical: 10),
            ),
            onSubmitted: (_) => _submit(),
          ),
        ),
      ]),
    );
  }
}
