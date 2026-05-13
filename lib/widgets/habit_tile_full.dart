import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/main.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/utils/domain_colors.dart';

class HabitTileFull extends StatelessWidget {
  final Activity habit;
  final AppLogic logic;

  // animation ring
  final double ringTarget; // 0..1
  final int ringToken; // pour reset l’anim (ValueKey)
  final VoidCallback onRingBump; // déclenche token++ dans le parent

  // histogram
  final List<double> series30;
  final double histMax;

  // texte
  final String subText;

  // actions UI
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onInc;
  final VoidCallback onDec;

  final List<Domain>? domains; // pour dériver la couleur de domaine

  const HabitTileFull({
    super.key,
    required this.habit,
    required this.logic,
    required this.ringTarget,
    required this.ringToken,
    required this.onRingBump,
    required this.series30,
    required this.histMax,
    required this.subText,
    required this.onTap,
    required this.onLongPress,
    required this.onInc,
    required this.onDec,
    this.domains,
  });

  @override
  Widget build(BuildContext context) {
    final target = ringTarget.clamp(0.0, 1.0);
    final dColor = domains != null
        ? domainColor(habit.domainId, domains!)
        : null;

    return InkWell(
      onLongPress: onLongPress,
      onTap: onTap,
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
                key: ValueKey("${habit.id}|$ringToken"),
                tween: Tween<double>(begin: 1.0, end: target),
                duration: const Duration(seconds: 5),
                curve: Curves.easeOutCubic,
                builder: (context, p, _) {
                  return MiniRingThick(
                    progress: p,
                    strokeWidth: 7,
                    color: dColor,
                    center: Text(
                      "${(target * 100).round()}%",
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: dColor,
                      ),
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
                    habit.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
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
                        color: dColor,
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
                      onRingBump();
                      onInc();
                    },
                  ),
                  const SizedBox(height: 10),
                  StepButton(
                    icon: Icons.remove,
                    onTap: () {
                      onRingBump();
                      onDec();
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