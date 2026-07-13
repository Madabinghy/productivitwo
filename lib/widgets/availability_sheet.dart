import 'package:flutter/material.dart';

/// « Et là, tu es dispo ? » — la disponibilité devient un FAIT tracké
/// (DailySchedule.unavailableUntil). Retourne :
///  · null            → fermé sans répondre (rien n'est écrit)
///  · [kAvailableNow] → « Oui — on enchaîne » (le flow continue)
///  · un DateTime     → « pas dispo avant X » (le coach suit le flow)
final DateTime kAvailableNow = DateTime.fromMillisecondsSinceEpoch(0);

/// [pause] = variante « bouton pause » de Maintenant : on l'ouvre soi-même
/// pour se déclarer indispo — le titre le dit, et le CTA « dispo » n'apparaît
/// que si une fenêtre est déjà active ([paused]), pour la lever.
Future<DateTime?> showAvailabilitySheet(BuildContext context,
    {bool pause = false, bool paused = false}) {
  final now = DateTime.now();
  DateTime at(int h, [int m = 0]) =>
      DateTime(now.year, now.month, now.day, h, m);
  DateTime inOneHour() => now.add(const Duration(hours: 1));
  // « Pas aujourd'hui » = jusqu'à demain 5 h (la journée vécue se termine là).
  DateTime tomorrow() {
    final t = now.add(const Duration(days: 1));
    return DateTime(t.year, t.month, t.day, 5, 0);
  }

  final options = <(String, DateTime)>[
    ('Dans 1 h', inOneHour()),
    if (now.hour < 17) ('Pas avant 18 h', at(18)),
    if (now.hour < 19) ('Pas avant ce soir (20 h)', at(20)),
    ('Pas aujourd\'hui', tomorrow()),
  ];

  return showModalBottomSheet<DateTime>(
    context: context,
    showDragHandle: true,
    builder: (sctx) {
      final cs = Theme.of(sctx).colorScheme;
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                pause
                    ? (paused ? 'Pause en cours' : 'Pause — pas dispo avant…')
                    : 'Et là, tu es dispo ?',
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(
              'Je suis le flow : aucune relance, aucune dérive avant l\'heure dite.',
              style: TextStyle(
                  fontSize: 12.5, color: cs.onSurface.withOpacity(.55)),
            ),
            const SizedBox(height: 14),
            // « Dispo » : réponse du flow report, ou levée d'une pause active —
            // mais jamais en ouvrant le bouton pause sans fenêtre en cours
            // (on vient se déclarer INDISPO, pas l'inverse).
            if (!pause || paused) ...[
              FilledButton.icon(
                icon: const Icon(Icons.bolt_rounded, size: 18),
                label: Text(pause
                    ? 'Je suis dispo — reprendre'
                    : 'Oui — on enchaîne'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999)),
                ),
                onPressed: () => Navigator.pop(sctx, kAvailableNow),
              ),
              const SizedBox(height: 10),
            ],
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final o in options)
                  ActionChip(
                    label: Text(o.$1, style: const TextStyle(fontSize: 12.5)),
                    onPressed: () => Navigator.pop(sctx, o.$2),
                  ),
                ActionChip(
                  label: const Text('Autre heure…',
                      style: TextStyle(fontSize: 12.5)),
                  onPressed: () async {
                    final t = await showTimePicker(
                        context: sctx,
                        initialTime: TimeOfDay(
                            hour: (now.hour + 2).clamp(0, 23), minute: 0));
                    if (t != null && sctx.mounted) {
                      var picked =
                          DateTime(now.year, now.month, now.day, t.hour, t.minute);
                      // Heure déjà passée = on parle de demain.
                      if (!picked.isAfter(now)) {
                        picked = picked.add(const Duration(days: 1));
                      }
                      Navigator.pop(sctx, picked);
                    }
                  },
                ),
              ],
            ),
          ],
        ),
      );
    },
  );
}
