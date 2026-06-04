import 'dart:async';
import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/notifications.dart';

class DailyScheduleView extends StatefulWidget {
  final String date; // YYYY-MM-DD
  final AppLogic logic;

  const DailyScheduleView({super.key, required this.date, required this.logic});

  @override
  State<DailyScheduleView> createState() => _DailyScheduleViewState();
}

class _DailyScheduleViewState extends State<DailyScheduleView> {
  final _sync = FirestoreSync();
  DailySchedule? _schedule;
  StreamSubscription<DailySchedule?>? _sub;
  // Défis déjà comptés (tap OU auto) — évite tout double comptage par bloc.
  final Set<String> _won = {};

  @override
  void initState() {
    super.initState();
    _sub = _sync.streamDailySchedule(widget.date).listen((s) {
      if (mounted) setState(() => _schedule = s);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  // ── Actions ─────────────────────────────────────────────────────────────────

  Future<void> _toggleDone(ScheduleBlock block) async {
    final newStatus = block.status == 'done' ? 'pending' : 'done';
    await _sync.updateBlockStatus(widget.date, block.id, newStatus);
    if (block.challenge && newStatus == 'done' && !_won.contains(block.id)) {
      _won.add(block.id);
      widget.logic.recordChallengeAccepted(widget.date.replaceAll('-', ''));
    }
  }

  Future<void> _deleteBlock(ScheduleBlock block) async {
    await _sync.updateBlockStatus(widget.date, block.id, 'deleted');
    if (block.challenge) {
      NotificationService.cancelChallengeAll(block.id);
    }
  }

  /// Défi programmé gagné automatiquement si du temps a été loggué sur
  /// l'activité le jour cible (≥ 60 % de la durée prévue, plancher 10 min).
  /// Appelé en post-frame depuis build (FocusView rebuild quand on logge).
  void _maybeAutoWin() {
    if (!mounted) return;
    final now = DateTime.now();
    final todayStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    if (widget.date != todayStr) return;
    final dayStart = DateTime(now.year, now.month, now.day);
    for (final b in _schedule?.blocks ?? <ScheduleBlock>[]) {
      if (!b.challenge ||
          b.status != 'pending' ||
          b.activityId == null ||
          _won.contains(b.id)) {
        continue;
      }
      final loggedMin = widget.logic
          .totalForRangeByActivity(b.activityId!, dayStart, now)
          .inMinutes;
      final threshold = (b.durationMin * 0.6).round();
      if (loggedMin >= (threshold < 10 ? 10 : threshold)) {
        _won.add(b.id);
        _sync.updateBlockStatus(widget.date, b.id, 'done');
        widget.logic.recordChallengeAccepted(widget.date.replaceAll('-', ''));
      }
    }
  }

  Future<void> _reorder(int oldIndex, int newIndex) async {
    final schedule = _schedule;
    if (schedule == null) return;
    if (newIndex > oldIndex) newIndex--;
    final visible = schedule.blocks.where((b) => b.status != 'deleted').toList();
    final deleted = schedule.blocks.where((b) => b.status == 'deleted').toList();
    final moved = visible.removeAt(oldIndex);
    visible.insert(newIndex, moved);
    await _sync.saveDailySchedule(DailySchedule(
      date: schedule.date,
      generatedBy: schedule.generatedBy,
      generatedAt: schedule.generatedAt,
      blocks: [...visible, ...deleted],
    ));
  }

  Future<void> _saveBlock(ScheduleBlock updated) async {
    final schedule = _schedule;
    if (schedule == null) return;
    final blocks = schedule.blocks.map((b) => b.id == updated.id ? updated : b).toList();
    await _sync.saveDailySchedule(DailySchedule(
      date: schedule.date,
      generatedBy: schedule.generatedBy,
      generatedAt: schedule.generatedAt,
      blocks: blocks,
    ));
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final visible = _schedule?.blocks.where((b) => b.status != 'deleted').toList() ?? [];
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeAutoWin());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Programme du jour',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface),
            ),
            const Spacer(),
            if (_schedule != null)
              Text(
                _schedule!.generatedBy == 'orion' ? '✨ ORION' : '🤖 Claude',
                style: TextStyle(
                    fontSize: 11, color: cs.onSurface.withOpacity(.4)),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (visible.isEmpty)
          _buildEmptyState(cs)
        else
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: visible.length,
            onReorder: _reorder,
            proxyDecorator: (child, index, anim) => Material(
              color: Colors.transparent,
              elevation: 6,
              shadowColor: Colors.black26,
              borderRadius: BorderRadius.circular(12),
              child: child,
            ),
            itemBuilder: (context, i) =>
                _buildBlock(context, cs, visible[i], key: ValueKey(visible[i].id)),
          ),
      ],
    );
  }

  Widget _buildBlock(BuildContext context, ColorScheme cs, ScheduleBlock block,
      {required Key key}) {
    final isDone = block.status == 'done';
    // Défi programmé = teinte dorée distincte (cohérent avec « Challenge me »).
    final color =
        block.challenge ? const Color(0xFFB8860B) : _categoryColor(block.category, cs);

    return Dismissible(
      key: key,
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: cs.errorContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(Icons.delete_outline, color: cs.onErrorContainer, size: 20),
      ),
      onDismissed: (_) => _deleteBlock(block),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: GestureDetector(
          onTap: () => _showEditSheet(context, cs, block),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Heure
              SizedBox(
                width: 46,
                child: Text(
                  block.startTime,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: isDone
                        ? cs.onSurface.withOpacity(.25)
                        : cs.onSurface.withOpacity(.55),
                  ),
                ),
              ),
              // Barre couleur catégorie
              Container(
                width: 3,
                height: 44,
                margin: const EdgeInsets.only(right: 12),
                decoration: BoxDecoration(
                  color: isDone ? color.withOpacity(.2) : color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Contenu
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      block.title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: isDone
                            ? cs.onSurface.withOpacity(.3)
                            : cs.onSurface,
                        decoration:
                            isDone ? TextDecoration.lineThrough : null,
                        decorationColor: cs.onSurface.withOpacity(.3),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(_categoryIcon(block.category),
                            size: 11,
                            color: isDone
                                ? color.withOpacity(.25)
                                : color.withOpacity(.8)),
                        const SizedBox(width: 4),
                        Text(
                          '${block.durationMin} min',
                          style: TextStyle(
                              fontSize: 11,
                              color: cs.onSurface
                                  .withOpacity(isDone ? .2 : .4)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Bouton checkbox
              GestureDetector(
                onTap: () => _toggleDone(block),
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 0, 8),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isDone ? color : Colors.transparent,
                      border: isDone
                          ? null
                          : Border.all(
                              color: cs.onSurface.withOpacity(.2),
                              width: 1.5),
                    ),
                    child: isDone
                        ? Icon(Icons.check, size: 15, color: cs.surface)
                        : null,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withOpacity(.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outline.withOpacity(.12)),
      ),
      child: Row(
        children: [
          Icon(Icons.today_outlined,
              size: 20, color: cs.onSurface.withOpacity(.3)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Pas de programme pour aujourd\'hui.\nDis à Claude ce que tu veux faire.',
              style: TextStyle(
                  fontSize: 13,
                  color: cs.onSurface.withOpacity(.4),
                  height: 1.45),
            ),
          ),
        ],
      ),
    );
  }

  void _showEditSheet(BuildContext context, ColorScheme cs, ScheduleBlock block) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) =>
          _BlockEditSheet(block: block, onSave: _saveBlock),
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────

  Color _categoryColor(String category, ColorScheme cs) => switch (category) {
        'project' => cs.primary,
        'routine' => const Color(0xFF1a9e6e),
        'personal' => cs.secondary,
        'break' => cs.outline,
        _ => cs.tertiary,
      };

  IconData _categoryIcon(String category) => switch (category) {
        'project' => Icons.rocket_launch_outlined,
        'routine' => Icons.loop,
        'personal' => Icons.home_outlined,
        'break' => Icons.coffee_outlined,
        _ => Icons.circle_outlined,
      };
}

// ── Sheet d'édition d'un bloc ─────────────────────────────────────────────────

class _BlockEditSheet extends StatefulWidget {
  final ScheduleBlock block;
  final Future<void> Function(ScheduleBlock) onSave;

  const _BlockEditSheet({required this.block, required this.onSave});

  @override
  State<_BlockEditSheet> createState() => _BlockEditSheetState();
}

class _BlockEditSheetState extends State<_BlockEditSheet> {
  late final TextEditingController _titleCtrl;
  late String _startTime;
  late int _durationMin;
  late String _category;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.block.title);
    _startTime = widget.block.startTime;
    _durationMin = widget.block.durationMin;
    _category = widget.block.category;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) return;
    setState(() => _saving = true);
    await widget.onSave(ScheduleBlock(
      id: widget.block.id,
      startTime: _startTime,
      durationMin: _durationMin,
      title: title,
      category: _category,
      projectId: widget.block.projectId,
      taskId: widget.block.taskId,
      activityId: widget.block.activityId,
      status: widget.block.status,
      doneAt: widget.block.doneAt,
    ));
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          24, 20, 24, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('Modifier le bloc',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ),
              IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => Navigator.pop(context)),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _titleCtrl,
            decoration: const InputDecoration(
                labelText: 'Titre',
                border: OutlineInputBorder(),
                isDense: true),
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _TimePickerField(
                  label: 'Début',
                  value: _startTime,
                  onChanged: (v) => setState(() => _startTime = v),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _DurationField(
                  value: _durationMin,
                  onChanged: (v) => setState(() => _durationMin = v),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _CategorySelector(
            value: _category,
            onChanged: (v) => setState(() => _category = v),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? 'Enregistrement…' : 'Enregistrer'),
          ),
        ],
      ),
    );
  }
}

// ── Champ sélecteur d'heure ───────────────────────────────────────────────────

class _TimePickerField extends StatelessWidget {
  final String label;
  final String value;
  final ValueChanged<String> onChanged;

  const _TimePickerField(
      {required this.label, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () async {
        final parts = value.split(':');
        final initial = TimeOfDay(
          hour: int.tryParse(parts.elementAtOrNull(0) ?? '') ?? 9,
          minute: int.tryParse(parts.elementAtOrNull(1) ?? '') ?? 0,
        );
        final picked =
            await showTimePicker(context: context, initialTime: initial);
        if (picked != null) {
          onChanged(
              '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}');
        }
      },
      child: InputDecorator(
        decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
            isDense: true),
        child: Text(value, style: const TextStyle(fontSize: 14)),
      ),
    );
  }
}

// ── Champ durée ───────────────────────────────────────────────────────────────

class _DurationField extends StatefulWidget {
  final int value;
  final ValueChanged<int> onChanged;

  const _DurationField({required this.value, required this.onChanged});

  @override
  State<_DurationField> createState() => _DurationFieldState();
}

class _DurationFieldState extends State<_DurationField> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.value.toString());
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _ctrl,
      keyboardType: TextInputType.number,
      decoration: const InputDecoration(
          labelText: 'Durée (min)',
          border: OutlineInputBorder(),
          isDense: true),
      onChanged: (v) {
        final n = int.tryParse(v);
        if (n != null && n > 0) widget.onChanged(n);
      },
    );
  }
}

// ── Sélecteur de catégorie ────────────────────────────────────────────────────

class _CategorySelector extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;

  const _CategorySelector(
      {required this.value, required this.onChanged});

  static const _cats = [
    ('project', 'Projet', Icons.rocket_launch_outlined),
    ('routine', 'Routine', Icons.loop),
    ('personal', 'Perso', Icons.home_outlined),
    ('break', 'Pause', Icons.coffee_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _cats.map((c) {
        final selected = value == c.$1;
        return ChoiceChip(
          avatar: Icon(c.$3, size: 14),
          label: Text(c.$2, style: const TextStyle(fontSize: 13)),
          selected: selected,
          onSelected: (_) => onChanged(c.$1),
          selectedColor: cs.primaryContainer,
          labelStyle: TextStyle(
              color: selected ? cs.onPrimaryContainer : cs.onSurface),
        );
      }).toList(),
    );
  }
}
