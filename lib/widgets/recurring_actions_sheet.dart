import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/models.dart';

Future<void> showRecurringActionsSheet(
  BuildContext context, {
  required AppLogic logic,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _RecurringActionsSheet(logic: logic),
  );
}

class _RecurringActionsSheet extends StatefulWidget {
  final AppLogic logic;
  const _RecurringActionsSheet({required this.logic});

  @override
  State<_RecurringActionsSheet> createState() => _RecurringActionsSheetState();
}

class _RecurringActionsSheetState extends State<_RecurringActionsSheet> {
  AppLogic get logic => widget.logic;

  static const _dayLabels = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];

  static String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  String _dateRangeLabel(RecurringAction ra) {
    if (ra.isExpired) return '⌛ Expirée le ${_fmtDate(ra.endDate!)}';
    if (ra.startDate != null && ra.endDate != null) {
      return '${_fmtDate(ra.startDate!)} → ${_fmtDate(ra.endDate!)}';
    }
    if (ra.startDate != null) return 'Depuis le ${_fmtDate(ra.startDate!)}';
    if (ra.endDate != null) return 'Jusqu\'au ${_fmtDate(ra.endDate!)}';
    return '';
  }

  String _typeLabel(RecurringAction ra) {
    if (ra.type == RecurrenceType.daily) return 'Chaque jour';
    if (ra.weekdays.isEmpty) return 'Jours spécifiques';
    return ra.weekdays
        .map((d) => _dayLabels[d - 1])
        .join(' · ');
  }

  Future<void> _delete(RecurringAction ra) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer la récurrence ?'),
        content: Text(
            'Les occurrences futures non cochées de "${ra.title}" seront supprimées.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Supprimer')),
        ],
      ),
    );
    if (ok != true) return;
    logic.deleteRecurringAction(ra.id);
    setState(() {});
  }

  Future<void> _pickDate(
    BuildContext context,
    DateTime? initial,
    ValueChanged<DateTime?> onPicked,
  ) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: initial ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    onPicked(picked);
  }

  Future<void> _edit(RecurringAction ra) async {
    RecurrenceType type = ra.type;
    List<int> weekdays = List.from(ra.weekdays);
    DateTime? startDate = ra.startDate;
    DateTime? endDate = ra.endDate;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: EdgeInsets.fromLTRB(
              20, 8, 20, 16 + MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(ra.title,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 16)),
              const SizedBox(height: 16),

              // Type chips
              Row(
                children: [
                  _typeChip(
                    ctx, 'Chaque jour',
                    selected: type == RecurrenceType.daily,
                    onTap: () => setS(() {
                      type = RecurrenceType.daily;
                      weekdays.clear();
                    }),
                  ),
                  const SizedBox(width: 8),
                  _typeChip(
                    ctx, 'Jours spécifiques',
                    selected: type == RecurrenceType.specificDays,
                    onTap: () => setS(() =>
                        type = RecurrenceType.specificDays),
                  ),
                ],
              ),

              // Sélecteur de jours
              if (type == RecurrenceType.specificDays) ...[
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: List.generate(7, (i) {
                    final day = i + 1;
                    final selected = weekdays.contains(day);
                    final cs = Theme.of(ctx).colorScheme;
                    return GestureDetector(
                      onTap: () => setS(() {
                        if (selected) {
                          weekdays.remove(day);
                        } else {
                          weekdays.add(day);
                        }
                      }),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        width: 38,
                        height: 38,
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

              // ── Période (optionnel) ──────────────────────────────────
              const SizedBox(height: 16),
              Text('Période (optionnel)',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(ctx).colorScheme.onSurface.withOpacity(.5))),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _DatePickerTile(
                      label: 'Début',
                      date: startDate,
                      onTap: () => _pickDate(ctx, startDate,
                          (d) => setS(() => startDate = d)),
                      onClear: startDate != null
                          ? () => setS(() => startDate = null)
                          : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _DatePickerTile(
                      label: 'Fin',
                      date: endDate,
                      onTap: () => _pickDate(ctx, endDate,
                          (d) => setS(() => endDate = d)),
                      onClear: endDate != null
                          ? () => setS(() => endDate = null)
                          : null,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),
              FilledButton(
                onPressed: () {
                  ra.type = type;
                  ra.weekdays = List.from(weekdays);
                  ra.startDate = startDate;
                  ra.endDate = endDate;
                  logic.onChange();
                  // Regénère pour les 8 prochains jours
                  final today = DateTime.now();
                  for (int i = 0; i < 8; i++) {
                    final d = today.add(Duration(days: i));
                    logic.ensureRecurringActionsForDay(
                      '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}',
                    );
                  }
                  Navigator.pop(ctx);
                  setState(() {});
                },
                child: const Text('Enregistrer'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _typeChip(BuildContext ctx, String label,
      {required bool selected, required VoidCallback onTap}) {
    final cs = Theme.of(ctx).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? cs.primary : cs.primary.withOpacity(.08),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: selected ? cs.onPrimary : cs.primary.withOpacity(.7),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final actions = logic.state.recurringActions;

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (ctx, sc) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Row(
              children: [
                const Expanded(
                  child: Text('Actions récurrentes',
                      style: TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 18)),
                ),
                if (actions.isNotEmpty)
                  Chip(
                    label: Text('${actions.length}'),
                    visualDensity: VisualDensity.compact,
                    backgroundColor: cs.primary.withOpacity(.1),
                    labelStyle: TextStyle(
                        fontSize: 12,
                        color: cs.primary,
                        fontWeight: FontWeight.w600),
                    side: BorderSide.none,
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: actions.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        'Aucune action récurrente.\nCrée-en une depuis le sheet de nouvelle action.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: cs.onSurface.withOpacity(.4),
                            fontSize: 13),
                      ),
                    ),
                  )
                : ListView.separated(
                    controller: sc,
                    padding: const EdgeInsets.only(bottom: 32),
                    itemCount: actions.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, indent: 16, endIndent: 16),
                    itemBuilder: (ctx, i) {
                      final ra = actions[i];
                      return ListTile(
                        leading: CircleAvatar(
                          radius: 18,
                          backgroundColor:
                              cs.primary.withOpacity(ra.active ? .12 : .06),
                          child: Icon(Icons.repeat,
                              size: 16,
                              color: cs.primary
                                  .withOpacity(ra.active ? .8 : .35)),
                        ),
                        title: Text(
                          ra.title,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: ra.active
                                ? cs.onSurface
                                : cs.onSurface.withOpacity(.4),
                            decoration: ra.active
                                ? null
                                : TextDecoration.lineThrough,
                          ),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _typeLabel(ra),
                              style: TextStyle(
                                  fontSize: 12,
                                  color: cs.onSurface.withOpacity(.45)),
                            ),
                            if (ra.startDate != null || ra.endDate != null)
                              Text(
                                _dateRangeLabel(ra),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: ra.isExpired
                                      ? cs.error.withOpacity(.7)
                                      : cs.primary.withOpacity(.7),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Pause / Réactiver
                            IconButton(
                              tooltip:
                                  ra.active ? 'Mettre en pause' : 'Réactiver',
                              icon: Icon(
                                ra.active
                                    ? Icons.pause_circle_outline
                                    : Icons.play_circle_outline,
                                size: 20,
                                color: cs.onSurface.withOpacity(.5),
                              ),
                              onPressed: () {
                                ra.active = !ra.active;
                                logic.onChange();
                                setState(() {});
                              },
                            ),
                            // Modifier
                            IconButton(
                              tooltip: 'Modifier',
                              icon: Icon(Icons.edit_outlined,
                                  size: 20,
                                  color: cs.onSurface.withOpacity(.5)),
                              onPressed: () => _edit(ra),
                            ),
                            // Supprimer
                            IconButton(
                              tooltip: 'Supprimer',
                              icon: Icon(Icons.delete_outline,
                                  size: 20,
                                  color: cs.onSurface.withOpacity(.4)),
                              onPressed: () => _delete(ra),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ── Widget date picker compact ────────────────────────────────────────────────

class _DatePickerTile extends StatelessWidget {
  final String label;
  final DateTime? date;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  const _DatePickerTile({
    required this.label,
    required this.date,
    required this.onTap,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasDate = date != null;
    final dateStr = hasDate
        ? '${date!.day.toString().padLeft(2, '0')}/${date!.month.toString().padLeft(2, '0')}/${date!.year}'
        : label;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(
            color: hasDate ? cs.primary.withOpacity(.5) : cs.outline.withOpacity(.4),
          ),
          borderRadius: BorderRadius.circular(8),
          color: hasDate ? cs.primaryContainer.withOpacity(.3) : null,
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today_outlined,
                size: 14,
                color: hasDate ? cs.primary : cs.onSurface.withOpacity(.4)),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                dateStr,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: hasDate ? FontWeight.w600 : FontWeight.normal,
                  color: hasDate ? cs.primary : cs.onSurface.withOpacity(.45),
                ),
              ),
            ),
            if (onClear != null)
              GestureDetector(
                onTap: onClear,
                child: Icon(Icons.close,
                    size: 14, color: cs.onSurface.withOpacity(.4)),
              ),
          ],
        ),
      ),
    );
  }
}
