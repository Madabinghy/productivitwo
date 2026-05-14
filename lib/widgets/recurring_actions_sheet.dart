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

  Future<void> _edit(RecurringAction ra) async {
    RecurrenceType type = ra.type;
    List<int> weekdays = List.from(ra.weekdays);

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

              const SizedBox(height: 20),
              FilledButton(
                onPressed: () {
                  ra.type = type;
                  ra.weekdays = List.from(weekdays);
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

  Widget _typeChip(BuildContext context, String label,
      {required bool selected, required VoidCallback onTap}) {
    final cs = Theme.of(context).colorScheme;
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
                        subtitle: Text(
                          _typeLabel(ra),
                          style: TextStyle(
                              fontSize: 12,
                              color: cs.onSurface.withOpacity(.45)),
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
