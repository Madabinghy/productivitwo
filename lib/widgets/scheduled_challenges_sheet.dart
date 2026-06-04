import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/models.dart';
import 'package:productivitwo_v1/notifications.dart';

/// Sheet « Défis en cours » (bouton ⚡ de l'app bar) : liste les défis programmés
/// encore en attente (aujourd'hui/futur) et permet de les annuler.
Future<void> showScheduledChallengesSheet(
    BuildContext context, AppLogic logic, FirestoreSync sync) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _ScheduledChallengesSheet(logic: logic, sync: sync),
  );
}

class _ScheduledChallengesSheet extends StatefulWidget {
  final AppLogic logic;
  final FirestoreSync sync;
  const _ScheduledChallengesSheet({required this.logic, required this.sync});

  @override
  State<_ScheduledChallengesSheet> createState() =>
      _ScheduledChallengesSheetState();
}

class _ScheduledChallengesSheetState extends State<_ScheduledChallengesSheet> {
  List<({String date, ScheduleBlock block})>? _items;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await widget.sync.fetchScheduledChallenges();
    if (mounted) setState(() => _items = items);
  }

  Future<void> _delete(String date, ScheduleBlock block) async {
    await widget.sync.updateBlockStatus(date, block.id, 'deleted');
    final ids = NotificationService.challengeNotifIds(block.id);
    await NotificationService.cancelChallenge(ids.atTime, ids.reminder);
    await _load();
  }

  String _dayLabel(String ymd) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final parts = ymd.split('-');
    if (parts.length != 3) return ymd;
    final d = DateTime(
        int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
    final diff = d.difference(today).inDays;
    if (diff == 0) return "aujourd'hui";
    if (diff == 1) return 'demain';
    if (diff == 2) return 'après-demain';
    const mois = [
      'janv', 'févr', 'mars', 'avr', 'mai', 'juin',
      'juil', 'août', 'sept', 'oct', 'nov', 'déc'
    ];
    return '${d.day} ${mois[d.month - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final items = _items;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  const Text('🔥', style: TextStyle(fontSize: 18)),
                  const SizedBox(width: 8),
                  Text('Défis en cours',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: cs.onSurface)),
                ],
              ),
            ),
            if (items == null)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Aucun défi programmé.',
                    style: TextStyle(
                        color: cs.onSurface.withOpacity(.5),
                        fontStyle: FontStyle.italic)),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: items.length,
                  separatorBuilder: (_, __) => Divider(
                      height: 1, color: cs.outlineVariant.withOpacity(.3)),
                  itemBuilder: (_, i) {
                    final it = items[i];
                    final b = it.block;
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.local_fire_department_rounded,
                          color: Color(0xFFB8860B)),
                      title: Text(b.title),
                      subtitle: Text(
                          '${_dayLabel(it.date)} à ${b.startTime} • ${b.durationMin} min'),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, size: 20),
                        tooltip: 'Annuler ce défi',
                        onPressed: () => _delete(it.date, b),
                      ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 8),
            Text(
              'Les défis programmés te rappellent au moment choisi et se gagnent quand tu les coches ou logges le temps.',
              style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(.5)),
            ),
          ],
        ),
      ),
    );
  }
}
