import 'package:flutter/material.dart';

/// Le bouton flottant des activités (retour user 2026-11-19) : ▶ ouvre le lanceur ; dès qu'un chrono tourne, il
/// devient ■ et l'arrête d'un geste, puis redevient ▶ pour en lancer une autre. Appui long sur ■ = le lanceur
/// quand même (changer d'activité sans passer par l'arrêt).
class ActivityFab extends StatelessWidget {
  /// Le nom de l'activité dont le chrono tourne, null si aucun.
  final String? runningName;
  final VoidCallback onLaunch;
  final VoidCallback onStop;
  const ActivityFab({super.key, required this.runningName, required this.onLaunch, required this.onStop});

  @override
  Widget build(BuildContext context) {
    final name = runningName;
    if (name == null) {
      return FloatingActionButton(
        key: const ValueKey('fab-launch-activity'),
        heroTag: 'fab_launch_activity',
        tooltip: 'Lancer une activité',
        onPressed: onLaunch,
        child: const Icon(Icons.play_arrow_rounded),
      );
    }
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: 'Arrêter $name. Appui long : lancer une autre activité.',
      child: GestureDetector(
        onLongPress: onLaunch,
        child: FloatingActionButton(
          key: const ValueKey('fab-stop-activity'),
          heroTag: 'fab_launch_activity',
          backgroundColor: cs.error,
          foregroundColor: cs.onError,
          onPressed: onStop,
          child: const Icon(Icons.stop_rounded),
        ),
      ),
    );
  }
}
