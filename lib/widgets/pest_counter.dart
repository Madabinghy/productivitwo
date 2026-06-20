import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/gold_engine.dart';

/// Compteur global de nuisibles (transposé du HUD web « Le Monde ») :
/// 🕷️ routines · 🦂 activités-temps · 🐍 tâches en retard, tous domaines.
/// Tap → panneau de stats avec comparatif hebdomadaire (jours tenus).
class PestCounterCard extends StatelessWidget {
  final AppLogic logic;
  const PestCounterCard({super.key, required this.logic});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = logic.worldPestTotals();
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      child: Material(
        color: cs.surfaceContainerHighest.withOpacity(.4),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _showStats(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Text('Nuisibles',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface.withOpacity(.7))),
                const Spacer(),
                _chip(context, '🕷️', t.spiders),
                const SizedBox(width: 14),
                _chip(context, '🦂', t.scorpions),
                const SizedBox(width: 14),
                _chip(context, '🐍', t.snakes),
                const SizedBox(width: 6),
                Icon(Icons.chevron_right,
                    size: 18, color: cs.onSurface.withOpacity(.35)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _chip(BuildContext context, String emoji, int n) {
    final cs = Theme.of(context).colorScheme;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Text(emoji, style: const TextStyle(fontSize: 16)),
      const SizedBox(width: 4),
      Text('$n',
          style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: cs.onSurface)),
    ]);
  }

  void _showStats(BuildContext context) {
    final totals = logic.worldPestTotals();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final thisWk = logic.worldWeekWins(today);
    final lastWk = logic.worldWeekWins(today.subtract(const Duration(days: 7)));
    showDialog<void>(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return AlertDialog(
          title: const Text('Nuisibles', style: TextStyle(fontSize: 17)),
          content: SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _statRow(ctx, '🕷️', 'Routines', totals.spiders,
                    thisWk.routineDays,
                    thisWk.routineDays - lastWk.routineDays, 'jours tenus'),
                const Divider(height: 18),
                _statRow(ctx, '🦂', 'Activités-temps', totals.scorpions,
                    thisWk.activityDays,
                    thisWk.activityDays - lastWk.activityDays, 'jours sur cible'),
                const Divider(height: 18),
                _statRow(ctx, '🐍', 'Tâches en retard', totals.snakes, null,
                    null, null),
                const SizedBox(height: 10),
                Text(
                    'Comparatif : cette semaine (7 j) vs les 7 jours précédents.',
                    style: TextStyle(
                        fontSize: 11, color: cs.onSurface.withOpacity(.5))),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Fermer')),
          ],
        );
      },
    );
  }

  Widget _statRow(BuildContext context, String emoji, String label, int alive,
      int? weekWins, int? delta, String? winsLabel) {
    final cs = Theme.of(context).colorScheme;
    final deltaStr = delta == null ? null : (delta >= 0 ? '+$delta' : '$delta');
    final deltaColor = delta == null || delta == 0
        ? cs.onSurface.withOpacity(.5)
        : (delta > 0 ? const Color(0xFF22C55E) : const Color(0xFFEF4444));
    return Row(children: [
      Text(emoji, style: const TextStyle(fontSize: 24)),
      const SizedBox(width: 12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style:
                  const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          if (weekWins != null && winsLabel != null)
            Text('$weekWins $winsLabel cette semaine',
                style: TextStyle(
                    fontSize: 11.5, color: cs.onSurface.withOpacity(.55))),
        ]),
      ),
      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text('$alive',
            style:
                const TextStyle(fontWeight: FontWeight.w900, fontSize: 22)),
        Text('vivants',
            style:
                TextStyle(fontSize: 9, color: cs.onSurface.withOpacity(.45))),
        if (deltaStr != null)
          Text('$deltaStr vs sem. dern.',
              style: TextStyle(
                  color: deltaColor,
                  fontWeight: FontWeight.w800,
                  fontSize: 11.5)),
      ]),
    ]);
  }
}
