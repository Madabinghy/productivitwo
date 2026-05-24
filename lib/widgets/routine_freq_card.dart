import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/domain_colors.dart';

class RoutineFreqCard extends StatefulWidget {
  final AppLogic logic;
  final Future<void> Function() onCreateRoutine;
  final Future<void> Function(Activity) onEditRoutine;
  final void Function(Activity) onDeleteRoutine;

  const RoutineFreqCard({
    super.key,
    required this.logic,
    required this.onCreateRoutine,
    required this.onEditRoutine,
    required this.onDeleteRoutine,
  });

  @override
  State<RoutineFreqCard> createState() => _RoutineFreqCardState();
}

class _RoutineFreqCardState extends State<RoutineFreqCard> {
  // Sections dépliées par défaut
  final Set<HabitFreq> _expanded = {HabitFreq.daily};

  AppLogic get logic => widget.logic;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final habits = logic.state.activities
        .where((a) => a.isHabit && !a.deleted && logic.effectiveHabitTarget(a) > 0)
        .toList();

    _FreqData buildData(HabitFreq freq) {
      final list = habits
          .where((a) => logic.effectiveHabitFreq(a) == freq)
          .toList()
        ..sort((a, b) => a.order.compareTo(b.order));
      if (list.isEmpty) return _FreqData(freq, [], 0, 0);

      int done = 0;
      final items = <_RoutineItem>[];
      for (final a in list) {
        final target = logic.effectiveHabitTarget(a);
        final int current = switch (freq) {
          HabitFreq.daily   => logic.habitValueOn(a.id, today),
          HabitFreq.weekly  => logic.habitSliding(a.id, 7).done,
          HabitFreq.monthly => logic.habitSliding(a.id, 30).done,
        };
        final reached = current >= target;
        if (reached) done++;
        items.add(_RoutineItem(a, current, target, reached));
      }
      return _FreqData(freq, items, done, list.length);
    }

    final sections = [
      buildData(HabitFreq.daily),
      buildData(HabitFreq.weekly),
      buildData(HabitFreq.monthly),
    ].where((d) => d.total > 0).toList();

    if (sections.isEmpty) {
      // État vide : juste le header avec le +
      return Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
          child: Row(
            children: [
              Text(
                'Routines',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: cs.onSurface.withOpacity(.6),
                ),
              ),
              const Spacer(),
              Text(
                'Aucune routine',
                style: TextStyle(
                  fontSize: 12,
                  color: cs.onSurface.withOpacity(.35),
                  fontStyle: FontStyle.italic,
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.add_rounded, size: 20),
                tooltip: 'Nouvelle routine',
                visualDensity: VisualDensity.compact,
                onPressed: widget.onCreateRoutine,
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ────────────────────────────────────────────────────────
            Row(
              children: [
                Text(
                  'Routines',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: cs.onSurface.withOpacity(.6),
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.add_rounded, size: 20),
                  tooltip: 'Nouvelle routine',
                  visualDensity: VisualDensity.compact,
                  onPressed: widget.onCreateRoutine,
                ),
              ],
            ),
            const SizedBox(height: 4),
            // ── Sections par fréquence ─────────────────────────────────────
            for (final data in sections) ...[
              _FreqSection(
                data: data,
                logic: logic,
                cs: cs,
                today: today,
                expanded: _expanded.contains(data.freq),
                onToggle: () => setState(() {
                  if (_expanded.contains(data.freq)) {
                    _expanded.remove(data.freq);
                  } else {
                    _expanded.add(data.freq);
                  }
                }),
                onIncrement: (activity, delta) {
                  HapticFeedback.lightImpact();
                  logic.incHabitWithAssocEvent(activity.id, delta, today);
                  logic.onChange();
                  setState(() {});
                },
                onEdit: widget.onEditRoutine,
                onDelete: widget.onDeleteRoutine,
              ),
              if (data != sections.last) const Divider(height: 16),
            ],
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }
}

// ── Section par fréquence ─────────────────────────────────────────────────────

class _FreqSection extends StatelessWidget {
  final _FreqData data;
  final AppLogic logic;
  final ColorScheme cs;
  final DateTime today;
  final bool expanded;
  final VoidCallback onToggle;
  final void Function(Activity, int) onIncrement;
  final Future<void> Function(Activity) onEdit;
  final void Function(Activity) onDelete;

  const _FreqSection({
    required this.data,
    required this.logic,
    required this.cs,
    required this.today,
    required this.expanded,
    required this.onToggle,
    required this.onIncrement,
    required this.onEdit,
    required this.onDelete,
  });

  String get _label => switch (data.freq) {
        HabitFreq.daily   => 'Quotidiennes',
        HabitFreq.weekly  => 'Hebdomadaires',
        HabitFreq.monthly => 'Mensuelles',
      };

  Color _barColor(double ratio) {
    if (ratio >= 1.0) return Colors.green.shade400;
    if (ratio >= 0.6) return Colors.orange.shade400;
    return Colors.red.shade400;
  }

  @override
  Widget build(BuildContext context) {
    final ratio = data.total == 0 ? 0.0 : data.done / data.total;
    final barColor = _barColor(ratio);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Ligne header fréquence ───────────────────────────────────────────
        InkWell(
          onTap: onToggle,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                SizedBox(
                  width: 110,
                  child: Text(
                    _label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: cs.onSurface.withOpacity(.8),
                    ),
                  ),
                ),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: ratio,
                      minHeight: 8,
                      backgroundColor: cs.onSurface.withOpacity(.1),
                      valueColor: AlwaysStoppedAnimation<Color>(barColor),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '${data.done}/${data.total}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: barColor,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  expanded ? Icons.expand_less : Icons.expand_more,
                  size: 18,
                  color: cs.onSurface.withOpacity(.4),
                ),
              ],
            ),
          ),
        ),
        // ── Liste inline (si déplié) ─────────────────────────────────────────
        if (expanded) ...[
          const SizedBox(height: 4),
          for (final item in data.items)
            _RoutineRow(
              item: item,
              logic: logic,
              cs: cs,
              today: today,
              freq: data.freq,
              onIncrement: (delta) => onIncrement(item.activity, delta),
              onEdit: () => onEdit(item.activity),
              onDelete: () => onDelete(item.activity),
            ),
        ],
      ],
    );
  }
}

// ── Ligne d'une routine avec -/+ ─────────────────────────────────────────────

class _RoutineRow extends StatelessWidget {
  final _RoutineItem item;
  final AppLogic logic;
  final ColorScheme cs;
  final DateTime today;
  final HabitFreq freq;
  final void Function(int) onIncrement;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _RoutineRow({
    required this.item,
    required this.logic,
    required this.cs,
    required this.today,
    required this.freq,
    required this.onIncrement,
    required this.onEdit,
    required this.onDelete,
  });

  Color get _barColor {
    final ratio = (item.current / item.target).clamp(0.0, 1.0);
    if (item.reached) return Colors.green.shade400;
    if (ratio >= 0.5) return Colors.orange.shade400;
    return cs.onSurface.withOpacity(.25);
  }

  void _showOptions(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  item.activity.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.edit_outlined),
                  title: const Text('Modifier'),
                  onTap: () {
                    Navigator.pop(ctx);
                    onEdit();
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.delete_outline,
                      color: cs.error),
                  title: Text('Supprimer',
                      style: TextStyle(color: cs.error)),
                  onTap: () {
                    Navigator.pop(ctx);
                    onDelete();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final dColor = domainColor(
        item.activity.domainId, logic.state.activeDomains);
    final canDecrement = item.current > 0;

    return GestureDetector(
      onLongPress: () => _showOptions(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            // Icône / point couleur
            SizedBox(
              width: 20,
              child: item.activity.iconCode != null
                  ? Icon(
                      IconData(item.activity.iconCode!,
                          fontFamily: 'MaterialIcons'),
                      size: 14,
                      color: dColor ?? cs.onSurface.withOpacity(.5),
                    )
                  : Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: dColor ?? cs.onSurface.withOpacity(.3),
                        shape: BoxShape.circle,
                      ),
                    ),
            ),
            const SizedBox(width: 4),
            // Nom
            Expanded(
              child: Text(
                item.activity.name,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: item.reached
                      ? cs.onSurface.withOpacity(.4)
                      : cs.onSurface.withOpacity(.85),
                  decoration:
                      item.reached ? TextDecoration.lineThrough : null,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 6),
            // Score
            Text(
              '${item.current}/${item.target}',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: _barColor,
              ),
            ),
            const SizedBox(width: 4),
            // Bouton −
            SizedBox(
              width: 32,
              height: 32,
              child: IconButton(
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.remove_rounded,
                    size: 16,
                    color: canDecrement
                        ? cs.onSurface.withOpacity(.5)
                        : cs.onSurface.withOpacity(.15)),
                onPressed:
                    canDecrement ? () => onIncrement(-1) : null,
              ),
            ),
            // Bouton +
            SizedBox(
              width: 32,
              height: 32,
              child: IconButton(
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.add_rounded,
                    size: 16,
                    color: item.reached
                        ? cs.onSurface.withOpacity(.3)
                        : (dColor ?? cs.primary)),
                onPressed: () => onIncrement(1),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Modèles internes ─────────────────────────────────────────────────────────

class _FreqData {
  final HabitFreq freq;
  final List<_RoutineItem> items;
  final int done;
  final int total;
  const _FreqData(this.freq, this.items, this.done, this.total);
}

class _RoutineItem {
  final Activity activity;
  final int current;
  final int target;
  final bool reached;
  const _RoutineItem(this.activity, this.current, this.target, this.reached);
}
