import 'dart:collection';
import 'dart:math';

/// OVERWORLD ORGANIQUE PROCÉDURAL (v2, libéré de la contrainte « bandes »).
///
/// Chaque domaine devient une RÉGION organique dont la TAILLE ∝ son poids
/// (nb de routines+activités, ou temps investi — décidé par l'appelant). Les régions
/// sont générées par un Voronoï PONDÉRÉ (croissance multi-sources en BFS) : des
/// graines réparties grandissent jusqu'à atteindre leur quota de cases → régions
/// contiguës aux frontières naturelles. Les cases non revendiquées = vide (eau).
///
/// Fichier PUR (records en entrée, aucune dépendance Flame/Flutter) → testable et
/// réutilisable par n'importe quel moteur de rendu.

/// Entrée : un domaine et son poids (≥ 0). Le poids pilote la taille de sa région.
class DomainWeight {
  final String domainId;
  final int? colorValue;
  final int weight;
  const DomainWeight(this.domainId, this.colorValue, this.weight);
}

/// Une région générée (un domaine).
class MapRegion {
  final String domainId;
  final int? colorValue;
  final Point<int> seed; // graine d'origine
  final Point<int> center; // centroïde (cases revendiquées)
  final int size; // nb de cases
  const MapRegion(this.domainId, this.colorValue, this.seed, this.center, this.size);
}

/// La carte : grille `owner` (domainId par case, null = vide/eau) + régions + spawn.
class WorldMap {
  final int cols, rows;
  final List<String?> owner; // aplati : index = y*cols + x
  final List<MapRegion> regions;
  final Map<String, MapRegion> byDomain;
  final Point<int> start;

  WorldMap({
    required this.cols,
    required this.rows,
    required this.owner,
    required this.regions,
    required this.start,
  }) : byDomain = {for (final r in regions) r.domainId: r};

  bool inBounds(int x, int y) => x >= 0 && x < cols && y >= 0 && y < rows;
  String? ownerAt(int x, int y) => inBounds(x, y) ? owner[y * cols + x] : null;
  bool walkable(int x, int y) => ownerAt(x, y) != null; // terre = praticable
}

const int _kTilesPerWeight = 26; // « surface » d'une unité de poids
const double _kFill = 0.62; // part de la grille couverte par les terres (reste = eau)
const int _kMinRegion = 10; // une région minuscule a quand même de la place

/// Génère l'overworld depuis les poids des domaines. Déterministe pour un `seed`
/// donné (même données → même carte).
WorldMap generateOverworld(List<DomainWeight> domains, {int seed = 0}) {
  final dw = domains.where((d) => d.domainId.isNotEmpty).toList();
  final rng = Random(seed == 0 ? dw.length * 7 + 3 : seed);

  if (dw.isEmpty) {
    return WorldMap(
      cols: 12,
      rows: 12,
      owner: List<String?>.filled(12 * 12, null),
      regions: const [],
      start: const Point(6, 6),
    );
  }

  final totalW = dw.fold<int>(0, (s, d) => s + max(1, d.weight));
  final targetTiles = max(totalW * _kTilesPerWeight, 400);
  final side = (sqrt(targetTiles / _kFill)).ceil();
  final cols = side, rows = side;
  final owner = List<String?>.filled(cols * rows, null);
  int idx(int x, int y) => y * cols + x;

  // 1) Graines réparties (échantillonnage par rejet : on garde la plus éloignée).
  final seeds = <Point<int>>[];
  for (var i = 0; i < dw.length; i++) {
    Point<int> best = Point(rng.nextInt(cols), rng.nextInt(rows));
    var bestMin = -1.0;
    for (var t = 0; t < 30; t++) {
      final c = Point(rng.nextInt(cols), rng.nextInt(rows));
      var m = double.infinity;
      for (final s in seeds) {
        final d = ((c.x - s.x) * (c.x - s.x) + (c.y - s.y) * (c.y - s.y)).toDouble();
        if (d < m) m = d;
      }
      if (seeds.isEmpty || m > bestMin) {
        bestMin = m;
        best = c;
      }
    }
    seeds.add(best);
  }

  // 2) Quota de cases par région ∝ poids.
  final targets = [
    for (final d in dw)
      max(_kMinRegion, (max(1, d.weight) / totalW * targetTiles).round())
  ];

  // 3) Croissance multi-sources (Voronoï pondéré) en round-robin.
  final frontiers = List.generate(dw.length, (_) => Queue<Point<int>>());
  final claimed = List.filled(dw.length, 0);
  for (var i = 0; i < dw.length; i++) {
    final s = seeds[i];
    if (owner[idx(s.x, s.y)] == null) {
      owner[idx(s.x, s.y)] = dw[i].domainId;
      claimed[i]++;
      frontiers[i].add(s);
    }
  }
  const dirs = [Point(1, 0), Point(-1, 0), Point(0, 1), Point(0, -1)];
  var active = true;
  while (active) {
    active = false;
    for (var i = 0; i < dw.length; i++) {
      if (claimed[i] >= targets[i] || frontiers[i].isEmpty) continue;
      active = true;
      final cur = frontiers[i].removeFirst();
      for (final dxy in dirs) {
        final nx = cur.x + dxy.x, ny = cur.y + dxy.y;
        if (nx < 0 || nx >= cols || ny < 0 || ny >= rows) continue;
        if (owner[idx(nx, ny)] != null) continue;
        owner[idx(nx, ny)] = dw[i].domainId;
        claimed[i]++;
        frontiers[i].add(Point(nx, ny));
        if (claimed[i] >= targets[i]) break;
      }
    }
  }

  // 4) Régions (centroïde) + spawn = centre de la plus grande région.
  final sumX = <String, int>{}, sumY = <String, int>{}, cnt = <String, int>{};
  for (var y = 0; y < rows; y++) {
    for (var x = 0; x < cols; x++) {
      final o = owner[idx(x, y)];
      if (o == null) continue;
      sumX[o] = (sumX[o] ?? 0) + x;
      sumY[o] = (sumY[o] ?? 0) + y;
      cnt[o] = (cnt[o] ?? 0) + 1;
    }
  }
  final regions = <MapRegion>[];
  for (var i = 0; i < dw.length; i++) {
    final id = dw[i].domainId;
    final n = cnt[id] ?? 0;
    final center = n == 0
        ? seeds[i]
        : Point<int>((sumX[id]! / n).round(), (sumY[id]! / n).round());
    regions.add(MapRegion(id, dw[i].colorValue, seeds[i], center, n));
  }
  regions.sort((a, b) => b.size.compareTo(a.size));
  final start = regions.isNotEmpty ? regions.first.center : Point(cols ~/ 2, rows ~/ 2);

  return WorldMap(
    cols: cols,
    rows: rows,
    owner: owner,
    regions: regions,
    start: start,
  );
}
