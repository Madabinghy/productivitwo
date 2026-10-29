import 'package:flutter/material.dart';
import 'package:productivitwo_v1/utils/actions_logic.dart' show focusLabel, shortDateFr;

/// Choix d'un JOUR VISÉ (2026-10-30) : aujourd'hui · demain · lundi prochain ·
/// une date · retirer. Une intention, jamais une échéance : rien n'est jamais
/// « en retard » à cause d'elle.
sealed class FocusPick {
  const FocusPick();
}

class FocusDay extends FocusPick {
  final DateTime day;
  const FocusDay(this.day);
}

class FocusClear extends FocusPick {
  const FocusClear();
}

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// Lundi strictement après [today] (un lundi → le suivant).
DateTime nextMonday(DateTime today) {
  final d = _day(today);
  final add = 8 - d.weekday;
  return d.add(Duration(days: add == 7 ? 7 : add));
}

/// Null = annulé. [current] = jour visé actuel (pour « Retirer » et la date
/// initiale du calendrier).
Future<FocusPick?> pickFocusDay(BuildContext context, {DateTime? current, DateTime? today}) {
  final t = _day(today ?? DateTime.now());
  final tomorrow = t.add(const Duration(days: 1));
  final monday = nextMonday(t);
  return showModalBottomSheet<FocusPick>(
    context: context,
    showDragHandle: true,
    useSafeArea: true,
    builder: (ctx) {
      final cs = Theme.of(ctx).colorScheme;
      final text3 = cs.onSurface.withValues(alpha: .55);
      return SafeArea(
        child: ListView(shrinkWrap: true, padding: const EdgeInsets.only(bottom: 12), children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Viser un jour', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(
                current == null
                    ? 'Le jour où tu veux l\'avoir sous la main. Une intention : ni créneau, ni retard.'
                    : 'Actuellement ${focusLabel(current, t)}. Une intention : ni créneau, ni retard.',
                style: TextStyle(fontSize: 12.5, color: text3),
              ),
            ]),
          ),
          ListTile(
            leading: const Icon(Icons.today_outlined),
            title: const Text("Aujourd'hui"),
            subtitle: Text(shortDateFr(t, today: t)),
            onTap: () => Navigator.pop(ctx, FocusDay(t)),
          ),
          ListTile(
            leading: const Icon(Icons.wb_sunny_outlined),
            title: const Text('Demain'),
            subtitle: Text(shortDateFr(tomorrow, today: t)),
            onTap: () => Navigator.pop(ctx, FocusDay(tomorrow)),
          ),
          ListTile(
            leading: const Icon(Icons.next_week_outlined),
            title: const Text('Lundi prochain'),
            subtitle: Text(shortDateFr(monday, today: t)),
            onTap: () => Navigator.pop(ctx, FocusDay(monday)),
          ),
          ListTile(
            leading: const Icon(Icons.calendar_month_outlined),
            title: const Text('Choisir une date…'),
            onTap: () async {
              final d = await showDatePicker(
                context: ctx,
                initialDate: current ?? t,
                firstDate: t.subtract(const Duration(days: 365)),
                lastDate: t.add(const Duration(days: 365 * 3)),
                locale: const Locale('fr'),
              );
              if (!ctx.mounted) return;
              Navigator.pop(ctx, d == null ? null : FocusDay(_day(d)));
            },
          ),
          if (current != null)
            ListTile(
              leading: Icon(Icons.close_rounded, color: cs.error),
              title: Text('Retirer le jour visé', style: TextStyle(color: cs.error)),
              onTap: () => Navigator.pop(ctx, const FocusClear()),
            ),
        ]),
      );
    },
  );
}
