import 'package:flutter/material.dart';

/// Le bouton flottant des activités : ▶ ouvre TOUJOURS le lanceur (2026-11-20, retour user : avec le ■ à sa
/// place, il fallait arrêter le chrono pour voir l'état de ses activités). Quand un chrono tourne, un petit ■
/// rouge se pose juste au-dessus et l'arrête d'un geste.
class ActivityFab extends StatelessWidget {
  /// Le nom de l'activité dont le chrono tourne, null si aucun.
  final String? runningName;
  final VoidCallback onLaunch;
  final VoidCallback onStop;
  const ActivityFab({super.key, required this.runningName, required this.onLaunch, required this.onStop});

  @override
  Widget build(BuildContext context) {
    final name = runningName;
    final launch = FloatingActionButton(
      key: const ValueKey('fab-launch-activity'),
      heroTag: 'fab_launch_activity',
      tooltip: name == null ? 'Lancer une activité' : 'Voir mes activités',
      onPressed: onLaunch,
      child: const Icon(Icons.play_arrow_rounded),
    );
    if (name == null) return launch;
    final cs = Theme.of(context).colorScheme;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Semantics(
        button: true,
        label: 'Arrêter $name',
        child: FloatingActionButton(
          key: const ValueKey('fab-stop-activity'),
          heroTag: 'fab_stop_activity',
          mini: true,
          tooltip: 'Arrêter $name',
          backgroundColor: cs.error,
          foregroundColor: cs.onError,
          onPressed: onStop,
          child: const Icon(Icons.stop_rounded, size: 20),
        ),
      ),
      const SizedBox(height: 8),
      launch,
    ]);
  }
}
