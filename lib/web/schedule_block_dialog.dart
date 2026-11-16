import 'package:flutter/material.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/actions_logic.dart' show isFolderProject;
import 'package:productivitwo_v1/utils/block_stack.dart';
import 'package:productivitwo_v1/utils/interventions.dart' show stripLeadEmoji;
import 'package:productivitwo_v1/utils/today_logic.dart' show canCancelBlock, kSkipUnavailable;
import 'package:productivitwo_v1/widgets/activity_picker.dart' show groupActivitiesByDomain, groupedActivityItems;
import 'package:productivitwo_v1/web/desktop_dialog.dart';
import 'package:productivitwo_v1/web/duration_chooser.dart';
import 'package:productivitwo_v1/web/theme_tokens.dart';

/// Éditeur de bloc du programme, version desktop (refonte web § 2.3 « Modifier »).
/// Retourne le bloc modifié (ou créé) via `Navigator.pop`, ou `null` si annulé.
/// La suppression est un soft-delete : `status: 'deleted'` sur le bloc rendu.
///
/// Avec [activities] et [projects] (Cette semaine), la fenêtre montre et règle
/// CE QUE LE BLOC PORTE : un mode, une activité, un projet ou une tâche
/// (`utils/block_stack.dart`). Sans eux, les liens du bloc sont gardés tels quels.
Future<ScheduleBlock?> showScheduleBlockDialog(
  BuildContext context, {
  required ScheduleBlock block,
  bool isNew = false,
  List<Activity>? activities,
  List<Project>? projects,
  List<Domain> domains = const [],
  bool Function(BlockTarget target)? canRework,
  Future<void> Function(BlockTarget target)? onRework,
}) {
  return showDesktopDialog<ScheduleBlock>(
    context,
    maxWidth: 520,
    builder: (_) =>
        _ScheduleBlockDialog(
            block: block,
            isNew: isNew,
            activities: activities,
            projects: projects,
            domains: domains,
            canRework: canRework,
            onRework: onRework),
  );
}

const _kCategories = [
  ('project', 'Projet'),
  ('routine', 'Routine'),
  ('personal', 'Perso'),
  ('break', 'Pause'),
];

class _ScheduleBlockDialog extends StatefulWidget {
  final ScheduleBlock block;
  final bool isNew;
  final List<Activity>? activities;
  final List<Project>? projects;
  final List<Domain> domains;

  /// Une cible qui est une séance (sa préparation, son jalon) se retouche
  /// d'ici : thème, préparation, déroulé.
  final bool Function(BlockTarget target)? canRework;
  final Future<void> Function(BlockTarget target)? onRework;
  const _ScheduleBlockDialog(
      {required this.block,
      required this.isNew,
      this.activities,
      this.projects,
      this.domains = const [],
      this.canRework,
      this.onRework});

  @override
  State<_ScheduleBlockDialog> createState() => _ScheduleBlockDialogState();
}

class _ScheduleBlockDialogState extends State<_ScheduleBlockDialog> {
  late final TextEditingController _title;
  late final TextEditingController _start;
  late int _durationMin;
  late String _category;
  late BlockLayers _layers;
  int _tick = 0;

  /// Les couches se règlent ici : listes fournies, et pas un rendez-vous
  /// d'agenda (il se rattache en glissant une activité dessus).
  bool get _editsLayers =>
      widget.activities != null && widget.projects != null && widget.block.gcalEventId == null;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.block.title);
    _start = TextEditingController(text: widget.block.startTime);
    _durationMin = widget.block.durationMin > 0 ? widget.block.durationMin : 30;
    _category = widget.block.category;
    _layers = BlockLayers.of(widget.block);
  }

  Project? _projectById(String id) => widget.projects?.where((p) => p.id == id).firstOrNull;

  String _autoTitle(BlockLayers l) {
    final a = l.activityId == null ? null : widget.activities?.where((x) => x.id == l.activityId).firstOrNull;
    return layersTitle(timeBlock: l.timeBlock, activity: a?.name, targets: [
      for (final t in l.targets)
        () {
          final p = _projectById(t.projectId);
          final task = t.taskId == null ? null : p?.tasks.where((x) => x.id == t.taskId).firstOrNull;
          return (project: p?.title, task: task == null ? null : stripLeadEmoji(task.title));
        }(),
    ]);
  }

  /// Change les couches ; un titre posé par l'app suit, un titre à la main reste.
  void _setLayers(BlockLayers next) => setState(() {
        _tick++; // les listes des cibles reviennent à ce que porte le bloc
        _title.text = retitled(_title.text, _autoTitle(_layers), _autoTitle(next));
        if (next.hasTarget && !_layers.hasTarget) _category = 'project';
        _layers = next;
      });

  /// Une cible du bloc : son projet, sa tâche réglable, ✕ pour la retirer.
  Widget _targetRow(int index, BlockTarget t, InputDecoration deco) {
    final project = _projectById(t.projectId);
    final tasks = [
      for (final x in project?.tasks ?? const <ProjectTask>[])
        if ((x.status != 'done' && x.status != 'skipped') || x.id == t.taskId) x,
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(children: [
        Expanded(
          child: KeyedSubtree(
          key: ValueKey('target-$index-$_tick'),
          child: DropdownButtonFormField<String>(
            key: ValueKey('block-task-$index'),
            value: tasks.any((x) => x.id == t.taskId) ? t.taskId : '',
            isExpanded: true,
            decoration: deco.copyWith(labelText: project?.title ?? 'Projet'),
            items: [
              const DropdownMenuItem(value: '', child: Text('Tout le projet')),
              for (final x in tasks) DropdownMenuItem(value: x.id, child: Text(x.title, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) {
              final task = tasks.where((x) => x.id == v).firstOrNull;
              _setLayers(_layers.withTargetAt(
                  index,
                  BlockTarget(
                      projectId: t.projectId,
                      taskId: task?.id,
                      actionId: task?.actions.where((a) => !a.done).firstOrNull?.id)));
            },
          ),
          ),
        ),
        if (widget.onRework != null && (widget.canRework?.call(t) ?? false))
          IconButton(
            key: ValueKey('block-target-rework-$index'),
            tooltip: 'Retoucher la séance',
            icon: const Icon(Icons.edit_outlined, size: 17, color: kBText3),
            onPressed: () async {
              final oldAuto = _autoTitle(_layers);
              await widget.onRework!(t);
              if (!mounted) return;
              // La séance a pu changer de nom : les listes et le titre de l'app suivent.
              setState(() {
                _tick++;
                _title.text = retitled(_title.text, oldAuto, _autoTitle(_layers));
              });
            },
          ),
        IconButton(
          key: ValueKey('block-target-remove-$index'),
          tooltip: 'Retirer du bloc',
          icon: const Icon(Icons.close, size: 18, color: kBText3),
          onPressed: () => _setLayers(_layers.withoutTargetAt(index)),
        ),
      ]),
    );
  }

  Widget _layersSection() {
    const deco = InputDecoration(border: OutlineInputBorder(), isDense: true);
    final acts = [
      for (final a in widget.activities!)
        if ((!a.deleted && !a.isHabit) || a.id == _layers.activityId) a,
    ];
    final all = widget.projects!;
    final projects = [
      for (final p in all)
        if (p.status == 'active' && !isFolderProject(p, all)) p,
    ]..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    final targets = _layers.targets;
    final full = targets.length >= kMaxBlockTargets;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Text('CE BLOC PORTE',
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.3, color: kBText3)),
      const SizedBox(height: 8),
      Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        const Text('Mode', style: TextStyle(fontSize: 12, color: kBText3)),
        for (final kind in const ['deep', 'small', 'morning'])
          ChoiceChip(
            key: ValueKey('block-mode-$kind'),
            label: Text(kTimeBlockLabels[kind]!),
            selected: _layers.timeBlock == kind,
            onSelected: (on) => _setLayers(on
                ? stackLayers(_layers, BlockLayers(timeBlock: kind))
                : _layers.withoutMode()),
          ),
      ]),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(
        key: const ValueKey('block-activity'),
        value: acts.any((a) => a.id == _layers.activityId) ? _layers.activityId : '',
        isExpanded: true,
        decoration: deco.copyWith(labelText: 'Activité · là où le temps compte'),
        items: [
          const DropdownMenuItem(value: '', child: Text('Aucune')),
          ...groupedActivityItems(groupActivitiesByDomain(acts, widget.domains)),
        ],
        onChanged: (v) => _setLayers(v == null || v.isEmpty
            ? _layers.withoutActivity()
            : stackLayers(_layers, BlockLayers(activityId: v))),
      ),
      const SizedBox(height: 12),
      if (targets.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
              targets.length == 1 ? 'Projet, tâche ou séance' : '${targets.length} projets, tâches ou séances, dans l’ordre',
              style: const TextStyle(fontSize: 12, color: kBText3)),
        ),
      for (var i = 0; i < targets.length; i++) _targetRow(i, targets[i], deco),
      if (!full)
        KeyedSubtree(
          // La liste revient à vide après chaque choix.
          key: ValueKey('target-add-$_tick'),
          child: DropdownButtonFormField<String>(
          key: const ValueKey('block-project'),
          value: '',
          isExpanded: true,
          decoration: deco.copyWith(labelText: targets.isEmpty ? 'Projet' : 'Ajouter un projet'),
          items: [
            DropdownMenuItem(value: '', child: Text(targets.isEmpty ? 'Aucun' : 'Choisir…')),
            for (final p in projects) DropdownMenuItem(value: p.id, child: Text(p.title, overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (v) {
            if (v == null || v.isEmpty) return;
            // Déjà là « tout le projet » : `stackLayers` ne l'ajoute pas deux fois.
            _setLayers(stackLayers(_layers, BlockLayers(targets: [BlockTarget(projectId: v)])));
          },
        ),
        ),
      const SizedBox(height: 8),
      const Text(
        'Dans la semaine, tu peux aussi glisser une ligne de « À placer » sur un bloc : elle s’y ajoute.',
        style: TextStyle(fontSize: 12, color: kBText3, height: 1.35),
      ),
    ]);
  }

  @override
  void dispose() {
    _title.dispose();
    _start.dispose();
    super.dispose();
  }

  String? get _startError {
    final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(_start.text.trim());
    if (m == null) return 'Format HH:mm';
    final h = int.parse(m.group(1)!), min = int.parse(m.group(2)!);
    if (h > 23 || min > 59) return 'Heure invalide';
    return null;
  }

  /// « · fin 15:30 » d'après le début saisi et la durée choisie.
  String? get _endLabel {
    if (_startError != null) return null;
    final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(_start.text.trim())!;
    final end = (int.parse(m.group(1)!) * 60 + int.parse(m.group(2)!) + _durationMin) % (24 * 60);
    return ' · fin ${(end ~/ 60).toString().padLeft(2, '0')}:${(end % 60).toString().padLeft(2, '0')}';
  }

  bool get _valid => _title.text.trim().isNotEmpty && _startError == null;

  ScheduleBlock _result({String? status}) {
    final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(_start.text.trim())!;
    final b = widget.block;
    b.title = _title.text.trim();
    b.startTime =
        '${m.group(1)!.padLeft(2, '0')}:${m.group(2)}';
    b.durationMin = _durationMin;
    b.category = _category;
    if (_editsLayers) _layers.applyTo(b);
    if (status != null) b.status = status;
    return b;
  }

  Future<void> _pickTime() async {
    final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(_start.text.trim());
    final initial = m == null
        ? TimeOfDay.now()
        : TimeOfDay(hour: int.parse(m.group(1)!), minute: int.parse(m.group(2)!));
    final t = await showTimePicker(context: context, initialTime: initial);
    if (t == null) return;
    setState(() => _start.text =
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}');
  }

  @override
  Widget build(BuildContext context) {
    final linked = widget.block.projectId != null || widget.block.activityId != null;
    return Container(
      color: kBSurface,
      child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.isNew ? 'Nouveau bloc' : 'Modifier le bloc',
              style: const TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w600, color: kBText)),
          const SizedBox(height: 18),
          TextField(
            controller: _title,
            autofocus: widget.isNew,
            onChanged: (_) => setState(() {}),
            style: const TextStyle(color: kBText),
            decoration: const InputDecoration(labelText: 'Titre'),
          ),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _start,
                onChanged: (_) => setState(() {}),
                style: const TextStyle(color: kBText, fontFeatures: [FontFeature.tabularFigures()]),
                decoration: InputDecoration(
                  labelText: 'Début',
                  hintText: 'HH:mm',
                  errorText: _start.text.isEmpty ? null : _startError,
                  suffixIcon: IconButton(
                    tooltip: 'Choisir l\'heure',
                    icon: const Icon(Icons.schedule_outlined, size: 18),
                    onPressed: _pickTime,
                  ),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 14),
          Text('Durée${_endLabel ?? ''}', style: const TextStyle(fontSize: 12, color: kBText3)),
          const SizedBox(height: 4),
          DurationChooser(
            value: _durationMin,
            onChanged: (v) => setState(() => _durationMin = v ?? 5),
          ),
          const SizedBox(height: 18),
          Wrap(spacing: 8, children: [
            for (final (id, label) in _kCategories)
              ChoiceChip(
                label: Text(label),
                selected: _category == id,
                avatar: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                      color: kBCategoryColor[id],
                      borderRadius: BorderRadius.circular(3)),
                ),
                onSelected: (_) => setState(() => _category = id),
              ),
          ]),
          if (_editsLayers) ...[
            const SizedBox(height: 18),
            _layersSection(),
          ] else if (linked) ...[
            const SizedBox(height: 12),
            const Text(
              'Bloc lié à un projet ou une activité : le lien est conservé.',
              style: TextStyle(fontSize: 12, color: kBText3),
            ),
          ],
          const SizedBox(height: 22),
          // Deux groupes qui passent à la ligne plutôt que de déborder.
          Wrap(alignment: WrapAlignment.spaceBetween, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
           Row(mainAxisSize: MainAxisSize.min, children: [
            if (!widget.isNew)
              TextButton.icon(
                onPressed: () =>
                    Navigator.of(context).pop(_result(status: 'deleted')),
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('Supprimer'),
                style: TextButton.styleFrom(foregroundColor: kBAlert),
              ),
            if (!widget.isNew && canCancelBlock(widget.block))
              Tooltip(
                message: 'Annuler ce bloc : il sort du programme, sans report ni déplacement',
                child: TextButton.icon(
                  onPressed: _valid
                      ? () {
                          final b = _result(status: 'skipped');
                          b.skipReason = kSkipUnavailable;
                          Navigator.of(context).pop(b);
                        }
                      : null,
                  icon: const Icon(Icons.event_busy_rounded, size: 18),
                  label: const Text('Pas disponible'),
                  style: TextButton.styleFrom(foregroundColor: kBText2),
                ),
              ),
           ]),
           Row(mainAxisSize: MainAxisSize.min, children: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Annuler'),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _valid ? () => Navigator.of(context).pop(_result()) : null,
              style: FilledButton.styleFrom(
                  backgroundColor: kBPrimary, foregroundColor: kBBg),
              child: Text(widget.isNew ? 'Ajouter' : 'Enregistrer'),
            ),
           ]),
          ]),
        ],
      ),
      ),
    );
  }
}
