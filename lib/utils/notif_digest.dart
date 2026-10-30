/// Textes des notifications du jour (refonte 2026-10-30). Purs : `main.dart`
/// compose les faits, les replanifie à chaque ouverture et changement.
library;

String _n(int n, String one, String many) => '$n ${n > 1 ? many : one}';

/// Matin, « Ta journée » : ce que la journée porte, en une ligne.
String morningDigest({required int blocks, required int routines, required int focused, required int series}) {
  final parts = [
    if (blocks > 0) _n(blocks, 'bloc', 'blocs'),
    if (routines > 0) _n(routines, 'routine', 'routines'),
    if (focused > 0) _n(focused, 'action visée', 'actions visées'),
    if (series > 0) '🔥 ${_n(series, 'série', 'séries')} à tenir',
  ];
  return parts.isEmpty ? 'Rien de prévu : pose ta journée.' : parts.join(' · ');
}
