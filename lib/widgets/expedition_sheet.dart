import 'package:flutter/material.dart';
import 'package:productivitwo_v1/app_logic.dart';
import 'package:productivitwo_v1/expedition.dart';
import 'package:productivitwo_v1/firestore_sync.dart';
import 'package:productivitwo_v1/gold_engine.dart';

const _kGold = Color(0xFFD4A017);

/// Donjon (Phase 2) : une fois le château trouvé sur la carte, on franchit le
/// niveau en relevant les DÉFIS préparés par Orion en amont — des objectifs
/// réels (routines / tâches / temps) qui se valident TOUT SEULS dès que tu les
/// accomplis dans l'app. Pas d'outils à acheter : on débloque par l'effort réel.
Future<void> showExpeditionSheet(
    BuildContext context, AppLogic logic, FirestoreSync sync) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => _ExpeditionSheet(logic: logic, sync: sync),
  );
}

class _ExpeditionSheet extends StatefulWidget {
  final AppLogic logic;
  final FirestoreSync sync;
  const _ExpeditionSheet({required this.logic, required this.sync});
  @override
  State<_ExpeditionSheet> createState() => _ExpeditionSheetState();
}

class _ExpeditionSheetState extends State<_ExpeditionSheet> {
  AppLogic get logic => widget.logic;
  FirestoreSync get sync => widget.sync;
  bool _busy = false;

  int get _level => logic.effectiveLevel() + 1;

  @override
  void initState() {
    super.initState();
    // Génère les défis du donjon à l'ouverture (instantané, sans Orion).
    logic.ensureExpeditionChallenges(sync);
  }

  Future<void> _unlock() async {
    if (_busy) return;
    setState(() => _busy = true);
    final ok = await sync.completeExpedition(_level);
    if (ok) {
      logic.state.unlockedLevel = _level;
      logic.state.expeditionCleared.clear();
      logic.onChange();
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) return;
    final lvl = logic.userLevelData();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Niveau ${lvl.level} débloqué ! 🏁'),
        content: Text(
            'Tu as relevé tous les défis du donjon. Tu es désormais « ${lvl.title} ».'),
        actions: [
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: _kGold),
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Super')),
        ],
      ),
    );
    if (mounted) Navigator.pop(context); // referme le donjon
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final biome = expeditionBiome(_level);
    final challenges = logic.expeditionChallengeStatuses();
    final doneCount = challenges.where((c) => c.done).length;
    final allDone = challenges.isNotEmpty && doneCount == challenges.length;

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      expand: false,
      builder: (_, scroll) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
            child: Row(children: [
              Text(biome.emoji, style: const TextStyle(fontSize: 22)),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Donjon · Niveau $_level',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                    Text(
                        challenges.isEmpty
                            ? 'Relève les défis d\'Orion pour débloquer'
                            : 'Défis relevés : $doneCount / ${challenges.length}',
                        style: TextStyle(
                            fontSize: 11.5,
                            color: cs.onSurface.withOpacity(.55))),
                  ],
                ),
              ),
            ]),
          ),
          Expanded(
            child: challenges.isEmpty
                ? _waiting(cs)
                : ListView(
                    controller: scroll,
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                    children: [
                      for (var i = 0; i < challenges.length; i++)
                        _room(cs, i + 1, challenges[i]),
                    ],
                  ),
          ),
          if (challenges.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: _kGold),
                  onPressed: (allDone && !_busy) ? _unlock : null,
                  child: Text(allDone
                      ? 'Débloquer le niveau $_level 🏁'
                      : 'Relève tous les défis pour débloquer'),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _waiting(ColorScheme cs) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('🗺️', style: TextStyle(fontSize: 48)),
              const SizedBox(height: 12),
              Text('Pas encore de défis',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface)),
              const SizedBox(height: 6),
              Text(
                  'Crée au moins une routine, une tâche ou une activité de temps : '
                  'tes défis du donjon seront générés à partir d\'elles.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 12.5, color: cs.onSurface.withOpacity(.55))),
            ],
          ),
        ),
      );

  Widget _room(
      ColorScheme cs,
      int n,
      ({String label, String type, int target, int progress, bool done}) c) {
    final pct = c.target > 0
        ? (c.progress / c.target).clamp(0.0, 1.0)
        : (c.done ? 1.0 : 0.0);
    final color = c.done ? Colors.green.shade600 : _kGold;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.done
            ? Colors.green.withOpacity(.08)
            : cs.surfaceContainerHighest.withOpacity(.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(c.done ? .6 : .4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(c.done ? '✅' : '🚪', style: const TextStyle(fontSize: 22)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Défi $n',
                    style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: color)),
                const SizedBox(height: 2),
                Text(c.label,
                    style: const TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w600)),
                if (c.target > 1) ...[
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: pct,
                      minHeight: 5,
                      backgroundColor: cs.onSurface.withOpacity(.10),
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text('${c.progress} / ${c.target}',
                      style: TextStyle(
                          fontSize: 10.5,
                          color: cs.onSurface.withOpacity(.5))),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
