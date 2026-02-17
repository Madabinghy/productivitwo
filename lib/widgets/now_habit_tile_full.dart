import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/main.dart';
import 'package:productivitwo_v1/models.dart';

class NowHabitTileFull extends StatelessWidget {
  final AppLogic logic;
  final AppState st;
  final String habitId; // Activity.id (habit)
  final DateTime day;

  // callbacks UI
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  // optionnel: si tu veux forcer une animation reset depuis NowTab
  final int ringToken;
  final void Function()? onRingBump;

  const NowHabitTileFull({
    super.key,
    required this.logic,
    required this.st,
    required this.habitId,
    required this.day,
    this.onTap,
    this.onLongPress,
    this.ringToken = 0,
    this.onRingBump,
  });

  String _habitSubText({
    required HabitFreq freq,
    required int dayDone,
    required int dayQuota,
    required int weekDone,
    required int weekTarget,
    required int monthDone,
    required int monthTarget,
  }) {
    switch (freq) {
      case HabitFreq.daily:
        return "Aujourd’hui $dayDone/$dayQuota";
      case HabitFreq.weekly:
        return "7j $weekDone/$weekTarget  •  Aujourd’hui $dayDone/$dayQuota";
      case HabitFreq.monthly:
      return "30j $monthDone/$monthTarget  •  Aujourd’hui $dayDone/$dayQuota";
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d0 = DateTime(day.year, day.month, day.day);

    final act = st.activities.firstWhere((a) => a.id == habitId);

    logic.habitSliding(habitId, 1);
    final h90 = logic.habitSliding(habitId, 90);

    final quotaD = logic.dayQuotaFor(act);
    final freq = logic.effectiveHabitFreq(act);
    final isDaily = (act.habitFreq ?? HabitFreq.monthly) == HabitFreq.daily;

    final series30 = List<double>.generate(30, (i) {
      final day30 = DateTime(d0.year, d0.month, d0.day).subtract(Duration(days: 29 - i));
      return logic.habitValueOn(habitId, day30).toDouble();
    });

    final histMax = isDaily ? quotaD.toDouble().clamp(1.0, 9999.0) : 1.0;

    final target = h90.ratio.clamp(0.0, 1.0);

    final subText = _habitSubText(
      freq: freq,
      dayDone: logic.habitValueOn(habitId, d0),
      dayQuota: quotaD,
      weekDone: logic.habitSliding(habitId, 7).done,
      weekTarget: logic.weekTargetFrom(act),
      monthDone: logic.habitSliding(habitId, 30).done,
      monthTarget: logic.monthTargetFrom(act),
    );

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Ring 90j
            SizedBox(
              width: 56,
              height: 56,
              child: TweenAnimationBuilder<double>(
                key: ValueKey("$habitId|$ringToken"),
                tween: Tween<double>(begin: 1.0, end: target),
                duration: const Duration(seconds: 5),
                curve: Curves.easeOutCubic,
                builder: (context, p, _) {
                  return MiniRingThick(
                    progress: p,
                    strokeWidth: 7,
                    center: Text(
                      "${(target * 100).round()}%",
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                    ),
                  );
                },
              ),
            ),

            const SizedBox(width: 12),

            // Titre + histogram + subtext
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    act.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                  const SizedBox(height: 8),

                  SizedBox(
                    height: 26,
                    child: GestureDetector(
                      onTap: onTap,
                      child: MiniHistogram30d(
                        values: series30,
                        maxValue: histMax,
                        highlightLast: true,
                      ),
                    ),
                  ),

                  const SizedBox(height: 4),

                  Opacity(
                    opacity: 0.65,
                    child: Text(
                      subText,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        height: 1.1,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(width: 12),

            // + / -
            SizedBox(
              width: 44,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  StepButton(
                    icon: Icons.add,
                    onTap: () {
                      onRingBump?.call();
                      logic.incHabit(habitId, 1, today);
                      logic.onChange();
                    },
                  ),
                  const SizedBox(height: 10),
                  StepButton(
                    icon: Icons.remove,
                    onTap: () {
                      onRingBump?.call();
                      logic.incHabit(habitId, -1, today);
                      logic.onChange();
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}