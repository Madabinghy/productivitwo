import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/models.dart';

class NewActionResult {
  final String title;
  final String? domainId;
  final String? activityId;
  final String? blockId;
  final String? goalId;

  const NewActionResult({
    required this.title,
    this.domainId,
    this.activityId,
    this.blockId,
    this.goalId,
  });
}

Future<NewActionResult?> showNewActionSheet(
  BuildContext context, {
  required AppLogic logic,
}) {
  return showModalBottomSheet<NewActionResult>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _NewActionSheet(logic: logic),
  );
}

class _NewActionSheet extends StatefulWidget {
  final AppLogic logic;
  const _NewActionSheet({required this.logic});

  @override
  State<_NewActionSheet> createState() => _NewActionSheetState();
}

class _NewActionSheetState extends State<_NewActionSheet> {
  final _titleCtrl = TextEditingController();
  String? _domainId;
  String? _activityId;
  String? _blockId;
  String? _goalId;

  // Récurrence
  RecurrenceType? _recurrenceType; // null = pas de récurrence
  final List<int> _weekdays = []; // 1=Lun..7=Dim

  AppLogic get logic => widget.logic;
  AppState get st => logic.state;

  List<Activity> get _activitiesForDomain {
    if (_domainId == null) return [];
    return st.activities
        .where((a) => a.domainId == _domainId && !a.isHabit)
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  List<Goal> get _goalsForDomain {
    if (_domainId == null) return [];
    return st.goals
        .where((g) => g.domainId == _domainId && g.status == 'active')
        .toList()
      ..sort((a, b) => a.title.compareTo(b.title));
  }

  List<DayBlock> get _blocks =>
      ([...st.blocks]..sort((a, b) => a.order.compareTo(b.order)));

  void _onDomainChanged(String? id) {
    setState(() {
      _domainId = id;
      // Réinitialise activité et objectif si hors du nouveau domaine
      if (_activityId != null &&
          st.activities.firstWhereOrNull(
                  (a) => a.id == _activityId && a.domainId == id) ==
              null) {
        _activityId = null;
      }
      if (_goalId != null &&
          st.goals.firstWhereOrNull(
                  (g) => g.id == _goalId && g.domainId == id) ==
              null) {
        _goalId = null;
      }
    });
  }

  void _submit() {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) return;

    if (_recurrenceType != null) {
      // Crée l'action récurrente et génère les occurrences pour les 8 prochains jours
      widget.logic.createRecurringAction(
        title: title,
        domainId: _domainId,
        activityId: _activityId,
        blockId: _blockId,
        type: _recurrenceType!,
        weekdays: List.from(_weekdays),
      );
      final today = DateTime.now();
      for (int i = 0; i < 8; i++) {
        final d = today.add(Duration(days: i));
        widget.logic.ensureRecurringActionsForDay(
          '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}',
        );
      }
      Navigator.pop(context, null);
      return;
    }

    Navigator.pop(
      context,
      NewActionResult(
        title: title,
        domainId: _domainId,
        activityId: _activityId,
        blockId: _blockId,
        goalId: _goalId,
      ),
    );
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final domains = [...st.domains]..sort((a, b) => a.name.compareTo(b.name));
    final activities = _activitiesForDomain;
    final goals = _goalsForDomain;
    final blocks = _blocks;

    final selectedBlock =
        blocks.firstWhereOrNull((b) => b.id == _blockId);
    final selectedActivity =
        activities.firstWhereOrNull((a) => a.id == _activityId);
    final selectedGoal =
        goals.firstWhereOrNull((g) => g.id == _goalId);

    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 8, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Nouvelle action',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
          ),
          const SizedBox(height: 16),

          // Titre
          TextField(
            controller: _titleCtrl,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Titre',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 12),

          // Domaine
          _PickerRow(
            icon: Icons.folder_outlined,
            label: 'Domaine',
            value: _domainId == null
                ? null
                : domains
                    .firstWhereOrNull((d) => d.id == _domainId)
                    ?.name,
            onTap: () => _showPicker<String>(
              context,
              title: 'Domaine',
              items: domains.map((d) => (d.id, d.name)).toList(),
              selected: _domainId,
              onSelect: _onDomainChanged,
              canClear: true,
            ),
          ),
          const SizedBox(height: 8),

          // Activité (seulement si domaine sélectionné)
          if (_domainId != null) ...[
            _PickerRow(
              icon: Icons.bolt_outlined,
              label: 'Activité',
              value: selectedActivity?.name,
              onTap: activities.isEmpty
                  ? null
                  : () => _showPicker<String>(
                        context,
                        title: 'Activité',
                        items: activities
                            .map((a) => (a.id, a.name))
                            .toList(),
                        selected: _activityId,
                        onSelect: (id) =>
                            setState(() => _activityId = id),
                        canClear: true,
                      ),
            ),
            const SizedBox(height: 8),
          ],

          // Bloc
          if (blocks.isNotEmpty) ...[
            _PickerRow(
              icon: Icons.view_day_outlined,
              label: 'Bloc',
              value: selectedBlock == null
                  ? null
                  : '${selectedBlock.emoji != null ? "${selectedBlock.emoji} " : ""}${selectedBlock.name}',
              onTap: () => _showPicker<String>(
                context,
                title: 'Bloc',
                items: blocks
                    .map((b) => (
                          b.id,
                          '${b.emoji != null ? "${b.emoji} " : ""}${b.name}'
                        ))
                    .toList(),
                selected: _blockId,
                onSelect: (id) => setState(() => _blockId = id),
                canClear: true,
              ),
            ),
            const SizedBox(height: 8),
          ],

          // Objectif (seulement si domaine sélectionné et objectifs dispo)
          // Sélectionner un objectif auto-remplit domaine et activité
          if (_domainId != null && goals.isNotEmpty) ...[
            _PickerRow(
              icon: Icons.flag_outlined,
              label: 'Objectif',
              value: selectedGoal?.title,
              onTap: () => _showPicker<String>(
                context,
                title: 'Objectif',
                items: goals.map((g) => (g.id, g.title)).toList(),
                selected: _goalId,
                onSelect: (id) {
                  setState(() {
                    _goalId = id;
                    if (id != null) {
                      final g = st.goals
                          .firstWhereOrNull((g) => g.id == id);
                      if (g != null) {
                        _domainId = g.domainId;
                        _activityId = g.activityId;
                      }
                    }
                  });
                },
                canClear: true,
              ),
            ),
            const SizedBox(height: 8),
          ],

          const SizedBox(height: 8),

          // ── Récurrence ────────────────────────────────────────────────
          _RecurrenceRow(
            type: _recurrenceType,
            weekdays: _weekdays,
            onTypeChanged: (t) => setState(() {
              _recurrenceType = t;
              _weekdays.clear();
            }),
            onWeekdayToggled: (day) => setState(() {
              if (_weekdays.contains(day)) {
                _weekdays.remove(day);
              } else {
                _weekdays.add(day);
              }
            }),
          ),
          const SizedBox(height: 8),

          FilledButton(
            onPressed: _titleCtrl.text.trim().isEmpty ? null : _submit,
            child: const Text('Ajouter'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
        ],
      ),
    );
  }

  Future<void> _showPicker<T>(
    BuildContext context, {
    required String title,
    required List<(String, String)> items,
    required String? selected,
    required void Function(String?) onSelect,
    bool canClear = false,
  }) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 16)),
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final (id, label) in items)
                    ListTile(
                      title: Text(label),
                      trailing:
                          id == selected ? const Icon(Icons.check) : null,
                      onTap: () => Navigator.pop(ctx, id),
                    ),
                  if (canClear && selected != null)
                    ListTile(
                      leading: const Icon(Icons.close),
                      title: const Text('Aucun'),
                      onTap: () => Navigator.pop(ctx, ''),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (picked == null) return;
    onSelect(picked.isEmpty ? null : picked);
  }
}

class _PickerRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? value;
  final VoidCallback? onTap;

  const _PickerRow({
    required this.icon,
    required this.label,
    this.value,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasValue = value != null;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(
              color: cs.outline.withOpacity(onTap == null ? 0.2 : 0.5)),
          borderRadius: BorderRadius.circular(8),
          color: onTap == null ? cs.surfaceVariant.withOpacity(0.3) : null,
        ),
        child: Row(
          children: [
            Icon(icon,
                size: 18,
                color: onTap == null
                    ? cs.onSurface.withOpacity(0.3)
                    : cs.onSurface.withOpacity(0.6)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                hasValue ? value! : label,
                style: TextStyle(
                  color: hasValue
                      ? cs.onSurface
                      : cs.onSurface.withOpacity(onTap == null ? 0.3 : 0.5),
                  fontWeight:
                      hasValue ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
            if (onTap != null)
              Icon(Icons.chevron_right,
                  size: 18, color: cs.onSurface.withOpacity(0.4)),
          ],
        ),
      ),
    );
  }
}

// ── Widget récurrence ─────────────────────────────────────────────────────────

class _RecurrenceRow extends StatelessWidget {
  final RecurrenceType? type;
  final List<int> weekdays;
  final void Function(RecurrenceType?) onTypeChanged;
  final void Function(int) onWeekdayToggled;

  const _RecurrenceRow({
    required this.type,
    required this.weekdays,
    required this.onTypeChanged,
    required this.onWeekdayToggled,
  });

  static const _dayLabels = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Toggle + type
        Row(
          children: [
            Icon(Icons.repeat,
                size: 18, color: cs.onSurface.withOpacity(.5)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                type == null
                    ? 'Répéter'
                    : type == RecurrenceType.daily
                        ? 'Chaque jour'
                        : 'Jours spécifiques',
                style: TextStyle(
                  color: type != null
                      ? cs.primary
                      : cs.onSurface.withOpacity(.5),
                  fontWeight:
                      type != null ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
            if (type != null)
              TextButton(
                style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero),
                onPressed: () => onTypeChanged(null),
                child: const Text('Retirer'),
              ),
            if (type == null) ...[
              TextButton(
                style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8)),
                onPressed: () => onTypeChanged(RecurrenceType.daily),
                child: const Text('Chaque jour'),
              ),
              TextButton(
                style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8)),
                onPressed: () =>
                    onTypeChanged(RecurrenceType.specificDays),
                child: const Text('Jours…'),
              ),
            ],
          ],
        ),

        // Sélecteur de jours
        if (type == RecurrenceType.specificDays) ...[
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: List.generate(7, (i) {
              final day = i + 1;
              final selected = weekdays.contains(day);
              return GestureDetector(
                onTap: () => onWeekdayToggled(day),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: selected
                        ? cs.primary
                        : cs.primary.withOpacity(.08),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Center(
                    child: Text(
                      _dayLabels[i],
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: selected
                            ? cs.onPrimary
                            : cs.primary.withOpacity(.7),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ],
      ],
    );
  }
}
