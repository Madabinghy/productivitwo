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

/// Soir, « Journée parfaite » : ce qu'il manque encore, séries en jeu
/// d'abord. Null quand il ne manque rien (pas de notification).
({String title, String body})? eveningDigest({required int routines, required int blocks, required List<String> seriesAtRisk}) {
  final missing = routines + blocks;
  if (missing == 0) return null;
  final parts = [
    if (seriesAtRisk.isNotEmpty)
      '🔥 ${seriesAtRisk.length <= 2 ? seriesAtRisk.join(', ') : '${seriesAtRisk.take(2).join(', ')} +${seriesAtRisk.length - 2}'} à tenir ce soir',
    if (routines > 0) _n(routines, 'routine', 'routines'),
    if (blocks > 0) _n(blocks, 'bloc', 'blocs'),
  ];
  return (title: 'Journée parfaite : il manque $missing', body: parts.join(' · '));
}
