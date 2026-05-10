import 'package:flutter/material.dart';
import 'package:productivitwo_v1/models.dart';

class RoutineProgressSummary {
  final int reached;
  final int catchup;

  const RoutineProgressSummary({
    required this.reached,
    required this.catchup,
  });

  int get total => reached + catchup;
  double get progress => total == 0 ? 0.0 : reached / total;
  bool get allReached => total > 0 && catchup == 0;
}

class RoutineAppBarChip extends StatelessWidget {
  final RoutineProgressSummary summary;
  final List<double>? trend30d;
  final VoidCallback? onTap;

  const RoutineAppBarChip({
    super.key,
    required this.summary,
    this.trend30d,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (summary.total == 0) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final bg = cs.surfaceContainerHighest.withValues(alpha: .55);
    final border = cs.outlineVariant.withValues(alpha: .55);
    final trophyColor = summary.allReached ? cs.primary : cs.secondary;
    final textStyle = theme.textTheme.labelMedium?.copyWith(
      fontWeight: FontWeight.w800,
      letterSpacing: .1,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.emoji_events_rounded,
                  size: 16,
                  color: trophyColor,
                ),
                const SizedBox(width: 6),
                Text(
                  '${summary.reached} / ${summary.reached+summary.catchup}',
                  style: textStyle,
                ),
                const SizedBox(width: 8),
                if (trend30d != null && trend30d!.isNotEmpty)
                  SizedBox(
                    width: 64,
                    child: TinyRatioBars(values: trend30d!, height: 20),
                  )
                else
                  SizedBox(
                    width: 40,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: LinearProgressIndicator(
                        value: summary.progress,
                        minHeight: 6,
                        backgroundColor: cs.surfaceContainerLow,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class RoutineProgressItem {
  final Activity activity;
  final String label;
  final int done;
  final int target;

  const RoutineProgressItem({
    required this.activity,
    required this.label,
    required this.done,
    required this.target,
  });

  bool get isReached => target > 0 && done >= target;
  bool get isCatchup => target > 0 && done < target;
  double get progress => target <= 0 ? 0.0 : (done / target).clamp(0.0, 1.0);
}


class TinyRatioBars extends StatelessWidget {
  final List<double> values;
  final double height;

  const TinyRatioBars({
    super.key,
    required this.values,
    this.height = 56,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (values.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final v in values)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1),
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    height: height * v.clamp(0.0, 1.0),
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: .75),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}