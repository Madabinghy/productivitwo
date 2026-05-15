import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/domain_colors.dart';
import 'package:productivitwo_v1/widgets/routine_detail_sheet.dart';

class RoutineFreqCard extends StatelessWidget {
  final AppLogic logic;
  const RoutineFreqCard({super.key, required this.logic});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final habits = logic.state.activities
        .where((a) => a.isHabit && logic.effectiveHabitTarget(a) > 0)
        .toList();

    // Données par fréquence
    _FreqData build(HabitFreq freq) {
      final list = habits
          .where((a) => logic.effectiveHabitFreq(a) == freq)
          .toList();
      if (list.isEmpty) return _FreqData(freq, [], 0, 0);

      int done = 0;
      final items = <_RoutineItem>[];
      for (final a in list) {
        final target = logic.effectiveHabitTarget(a);
        final int current;
        switch (freq) {
          case HabitFreq.daily:
            current = logic.habitValueOn(a.id, today);
            break;
          case HabitFreq.weekly:
            current = logic.habitSliding(a.id, 7).done;
            break;
          case HabitFreq.monthly:
            current = logic.habitSliding(a.id, 30).done;
            break;
        }
        final reached = current >= target;
        if (reached) done++;
        items.add(_RoutineItem(a, current, target, reached));
      }
      // Tri urgence : non-faites d'abord (ratio croissant)
      items.sort((a, b) {
        if (a.reached != b.reached) return a.reached ? 1 : -1;
        return (a.current / a.target).compareTo(b.current / b.target);
      });
      return _FreqData(freq, items, done, list.length);
    }

    final daily = build(HabitFreq.daily);
    final weekly = build(HabitFreq.weekly);
    final monthly = build(HabitFreq.monthly);

    if (daily.total == 0 && weekly.total == 0 && monthly.total == 0) {
      return const SizedBox.shrink();
    }

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Routines',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: cs.onSurface.withOpacity(.6),
              ),
            ),
            const SizedBox(height: 12),
            if (daily.total > 0)
              _FreqRow(data: daily, logic: logic, cs: cs),
            if (weekly.total > 0) ...[
              const SizedBox(height: 8),
              _FreqRow(data: weekly, logic: logic, cs: cs),
            ],
            if (monthly.total > 0) ...[
              const SizedBox(height: 8),
              _FreqRow(data: monthly, logic: logic, cs: cs),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Row par fréquence ─────────────────────────────────────────────────────────

class _FreqRow extends StatelessWidget {
  final _FreqData data;
  final AppLogic logic;
  final ColorScheme cs;

  const _FreqRow({required this.data, required this.logic, required this.cs});

  String get _label => switch (data.freq) {
        HabitFreq.daily => 'Quotidiennes',
        HabitFreq.weekly => 'Hebdomadaires',
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

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => _showDetail(context),
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
          ],
        ),
      ),
    );
  }

  void _showDetail(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.5,
        maxChildSize: 0.9,
        builder: (ctx, sc) => ListView(
          controller: sc,
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          children: [
            Text(
              _label,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 12),
            for (final item in data.items) ...[
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => showRoutineSheet(
                  ctx,
                  logic: logic,
                  habitId: item.activity.id,
                  day: DateTime.now(),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: _RoutineDetailRow(
                    item: item,
                    logic: logic,
                    cs: cs,
                  ),
                ),
              ),
              const Divider(height: 1),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Ligne détail par routine ──────────────────────────────────────────────────

class _RoutineDetailRow extends StatelessWidget {
  final _RoutineItem item;
  final AppLogic logic;
  final ColorScheme cs;

  const _RoutineDetailRow(
      {required this.item, required this.logic, required this.cs});

  @override
  Widget build(BuildContext context) {
    final ratio = (item.current / item.target).clamp(0.0, 1.0);
    final dColor = domainColor(item.activity.domainId, logic.state.domains);
    final barColor = item.reached
        ? Colors.green.shade400
        : ratio >= 0.5
            ? Colors.orange.shade400
            : Colors.red.shade400;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (item.activity.iconCode != null) ...[
              Icon(
                IconData(item.activity.iconCode!, fontFamily: 'MaterialIcons'),
                size: 14,
                color: dColor ?? cs.onSurface.withOpacity(.5),
              ),
              const SizedBox(width: 6),
            ] else if (dColor != null) ...[
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: dColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
            ],
            Expanded(
              child: Text(
                item.activity.name,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: item.reached
                      ? cs.onSurface.withOpacity(.45)
                      : cs.onSurface,
                  decoration: item.reached ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
            Text(
              '${item.current}/${item.target}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: barColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 5,
            backgroundColor: cs.onSurface.withOpacity(.08),
            valueColor: AlwaysStoppedAnimation<Color>(barColor),
          ),
        ),
      ],
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
