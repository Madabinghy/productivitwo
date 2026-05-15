import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/widgets/habit_settings_sheet.dart'
    show freqLabel;
import 'package:productivitwo_v1/widgets/icon_picker_sheet.dart';

class NewRoutineResult {
  final String name;
  final String domainId;
  final String? linkedActivityId;
  final String? blockId;
  final int? iconCode;
  final HabitFreq freq;
  final int target;

  const NewRoutineResult({
    required this.name,
    required this.domainId,
    this.linkedActivityId,
    this.blockId,
    this.iconCode,
    this.freq = HabitFreq.daily,
    this.target = 1,
  });
}

Future<NewRoutineResult?> showNewRoutineSheet(
  BuildContext context, {
  required AppLogic logic,
}) {
  return showModalBottomSheet<NewRoutineResult>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _NewRoutineSheet(logic: logic),
  );
}

class _NewRoutineSheet extends StatefulWidget {
  final AppLogic logic;
  const _NewRoutineSheet({required this.logic});

  @override
  State<_NewRoutineSheet> createState() => _NewRoutineSheetState();
}

class _NewRoutineSheetState extends State<_NewRoutineSheet> {
  final _nameCtrl = TextEditingController();
  String? _domainId;
  String? _linkedActivityId;
  String? _blockId;
  int? _iconCode;
  HabitFreq _freq = HabitFreq.daily;
  int _target = 1;

  AppLogic get logic => widget.logic;
  AppState get st => logic.state;

  List<Activity> get _timeActivitiesForDomain {
    if (_domainId == null) return [];
    return st.activities
        .where((a) => a.domainId == _domainId && !a.isHabit)
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  List<DayBlock> get _blocks =>
      ([...st.blocks]..sort((a, b) => a.order.compareTo(b.order)));

  void _onDomainChanged(String? id) {
    setState(() {
      _domainId = id;
      if (_linkedActivityId != null &&
          st.activities.firstWhereOrNull((a) =>
                  a.id == _linkedActivityId && a.domainId == id) ==
              null) {
        _linkedActivityId = null;
      }
    });
  }

  void _submit() {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty || _domainId == null) return;

    Navigator.pop(
      context,
      NewRoutineResult(
        name: name,
        domainId: _domainId!,
        linkedActivityId: _linkedActivityId,
        blockId: _blockId,
        iconCode: _iconCode,
        freq: _freq,
        target: _target,
      ),
    );
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final domains = [...st.domains]..sort((a, b) => a.name.compareTo(b.name));
    final activities = _timeActivitiesForDomain;
    final blocks = _blocks;

    final selectedDomain =
        domains.firstWhereOrNull((d) => d.id == _domainId);
    final selectedActivity =
        activities.firstWhereOrNull((a) => a.id == _linkedActivityId);
    final selectedBlock =
        blocks.firstWhereOrNull((b) => b.id == _blockId);

    final canSubmit =
        _nameCtrl.text.trim().isNotEmpty && _domainId != null;

    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 8, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Nouvelle routine',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
          ),
          const SizedBox(height: 16),

          // Nom
          TextField(
            controller: _nameCtrl,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Nom',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 12),

          // Fréquence
          Row(
            children: [
              const Text('Fréquence',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const Spacer(),
              DropdownButton<HabitFreq>(
                value: _freq,
                items: HabitFreq.values
                    .map((f) => DropdownMenuItem(
                          value: f,
                          child: Text(freqLabel(f)),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => _freq = v);
                },
              ),
            ],
          ),
          const SizedBox(height: 4),

          // Cible
          Row(
            children: [
              const Text('Cible',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const Spacer(),
              IconButton(
                onPressed: () =>
                    setState(() => _target = (_target - 1).clamp(1, 999)),
                icon: const Icon(Icons.remove_circle_outline),
                visualDensity: VisualDensity.compact,
              ),
              Text('$_target',
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 16)),
              IconButton(
                onPressed: () =>
                    setState(() => _target = (_target + 1).clamp(1, 999)),
                icon: const Icon(Icons.add_circle_outline),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Domaine (obligatoire)
          _PickerRow(
            icon: Icons.folder_outlined,
            label: 'Domaine *',
            value: selectedDomain?.name,
            onTap: () => _showPicker(
              context,
              title: 'Domaine',
              items: domains.map((d) => (d.id, d.name)).toList(),
              selected: _domainId,
              onSelect: _onDomainChanged,
              canClear: false,
            ),
          ),
          const SizedBox(height: 8),

          // Activité liée (timer, optionnel, filtré par domaine)
          if (_domainId != null) ...[
            _PickerRow(
              icon: Icons.timer_outlined,
              label: 'Activité liée (timer)',
              value: selectedActivity?.name,
              onTap: activities.isEmpty
                  ? null
                  : () => _showPicker(
                        context,
                        title: 'Activité liée',
                        items: activities
                            .map((a) => (a.id, a.name))
                            .toList(),
                        selected: _linkedActivityId,
                        onSelect: (id) =>
                            setState(() => _linkedActivityId = id),
                        canClear: true,
                      ),
            ),
            const SizedBox(height: 8),
          ],

          // Bloc (optionnel)
          if (blocks.isNotEmpty) ...[
            _PickerRow(
              icon: Icons.view_day_outlined,
              label: 'Bloc',
              value: selectedBlock == null
                  ? null
                  : '${selectedBlock.emoji != null ? "${selectedBlock.emoji} " : ""}${selectedBlock.name}',
              onTap: () => _showPicker(
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

          // Icône (optionnelle)
          _PickerRow(
            icon: _iconCode != null
                ? IconData(_iconCode!, fontFamily: 'MaterialIcons')
                : Icons.emoji_emotions_outlined,
            label: 'Icône',
            value: _iconCode != null ? 'Choisie' : null,
            onTap: () async {
              final picked =
                  await showIconPickerSheet(context, current: _iconCode);
              if (picked == null) return;
              setState(() => _iconCode = picked == -1 ? null : picked);
            },
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: canSubmit ? _submit : null,
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

  Future<void> _showPicker(
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
                      trailing: id == selected
                          ? const Icon(Icons.check)
                          : null,
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
              color: cs.outline
                  .withOpacity(onTap == null ? 0.2 : 0.5)),
          borderRadius: BorderRadius.circular(8),
          color: onTap == null
              ? cs.surfaceVariant.withOpacity(0.3)
              : null,
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
                      : cs.onSurface
                          .withOpacity(onTap == null ? 0.3 : 0.5),
                  fontWeight:
                      hasValue ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
            if (onTap != null)
              Icon(Icons.chevron_right,
                  size: 18,
                  color: cs.onSurface.withOpacity(0.4)),
          ],
        ),
      ),
    );
  }
}
