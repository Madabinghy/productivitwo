import 'dart:collection';
import 'dart:math';

import 'world_map_gen.dart';

/// CARTE ORGANIQUE « vieille carte » (contemplative, type deepnight).
///
/// Couche POSÉE par‑dessus l'overworld Voronoï de `world_map_gen.dart` : elle ne
/// touche pas la structure des régions (chaque domaine = une contrée), elle ajoute
/// (1) des CÔTES adoucies façon littoral et (2) une classification de BIOMES par
/// distance à l'eau (côtes basses → cœur des terres en altitude). Tout est
/// DÉTERMINISTE (même données + même seed → même carte) et le fichier reste PUR
/// (aucune dépendance Flutter/Flame) → testable et réutilisable par le rendu.

enum OrganicBiome { water, shore, plain, forest, hills, mountain }

/// Résultat : côtes adoucies + biome + élévation par case, régions héritées de
/// l'overworld (couleurs/centres des domaines conservés).
class OrganicMap {
  final int cols, rows;
  final List<String?> owner; // côtes adoucies ; null = eau
  final List<OrganicBiome> biome; // aplati y*cols+x
  final List<int> elevation; // 0..255 (distance à l'eau, lissée)
  final List<MapRegion> regions;
  final Map<String, MapRegion> byDomain;
  final Point<int> start;

  OrganicMap({
    required this.cols,
    required this.rows,
    required this.owner,
    required this.biome,
    required this.elevation,
    required this.regions,
    required this.start,
  }) : byDomain = {for (final r in regions) r.domainId: r};

  bool inBounds(int x, int y) => x >= 0 && x < cols && y >= 0 && y < rows;
  int _i(int x, int y) => y * cols + x;
  String? ownerAt(int x, int y) => inBounds(x, y) ? owner[_i(x, y)] : null;
  bool isLand(int x, int y) => ownerAt(x, y) != null;
  OrganicBiome biomeAt(int x, int y) =>
      inBounds(x, y) ? biome[_i(x, y)] : OrganicBiome.water;
  int elevAt(int x, int y) => inBounds(x, y) ? elevation[_i(x, y)] : 0;
}

// Seuils d'altitude (sur 0..255) délimitant les biomes intérieurs. La côte est
// détectée à part (adjacence eau), elle prime sur ces seuils.
const int _kForest = 70;
const int _kHills = 130;
const int _kMountain = 195;

/// Construit la carte organique depuis les poids des domaines. Déterministe.
OrganicMap buildOrganicMap(List<DomainWeight> domains, {int seed = 0}) {
  final base = generateOverworld(domains, seed: seed);
  final cols = base.cols, rows = base.rows;
  int idx(int x, int y) => y * cols + x;
  final owner = List<String?>.of(base.owner);

  // 1) CÔTES ORGANIQUES — 2 passes de cellular automata, sans rng (déterministe) :
  //    une pointe isolée (< 3 voisins terre) est rongée par la mer ; un creux cerné
  //    (> 5 voisins terre) est comblé, son owner = domaine majoritaire alentour.
  for (var pass = 0; pass < 2; pass++) {
    final next = List<String?>.of(owner);
    for (var y = 0; y < rows; y++) {
      for (var x = 0; x < cols; x++) {
        final counts = <String, int>{};
        var land = 0;
        for (var dy = -1; dy <= 1; dy++) {
          for (var dx = -1; dx <= 1; dx++) {
            if (dx == 0 && dy == 0) continue;
            final nx = x + dx, ny = y + dy;
            if (nx < 0 || nx >= cols || ny < 0 || ny >= rows) continue;
            final o = owner[idx(nx, ny)];
            if (o != null) {
              land++;
              counts[o] = (counts[o] ?? 0) + 1;
            }
          }
        }
        final here = owner[idx(x, y)];
        if (here != null && land < 3) {
          next[idx(x, y)] = null;
        } else if (here == null && land > 5) {
          String? best;
          var bn = -1;
          counts.forEach((k, v) {
            if (v > bn) {
              bn = v;
              best = k;
            }
          });
          next[idx(x, y)] = best;
        }
      }
    }
    for (var i = 0; i < next.length; i++) {
      owner[i] = next[i];
    }
  }

  // GARDE‑FOU : le lissage ne doit jamais effacer un domaine. On re‑estampe le
  // centroïde (et son voisinage immédiat) de toute région disparue.
  for (final r in base.regions) {
    final present = owner.any((o) => o == r.domainId);
    if (present) continue;
    for (var dy = -1; dy <= 1; dy++) {
      for (var dx = -1; dx <= 1; dx++) {
        final x = r.center.x + dx, y = r.center.y + dy;
        if (x >= 0 && x < cols && y >= 0 && y < rows) {
          owner[idx(x, y)] = r.domainId;
        }
      }
    }
  }

  // 2) ÉLÉVATION = distance à l'eau (BFS multi‑source 4‑dir). Le bord de map compte
  //    comme eau → les contrées de bordure ont aussi une côte. Relief radial :
  //    littoral bas, cœur des terres haut.
  final dist = List<int>.filled(cols * rows, -1);
  final q = Queue<Point<int>>();
  for (var y = 0; y < rows; y++) {
    for (var x = 0; x < cols; x++) {
      if (owner[idx(x, y)] == null) {
        dist[idx(x, y)] = 0;
        q.add(Point(x, y));
      } else if (x == 0 || y == 0 || x == cols - 1 || y == rows - 1) {
        dist[idx(x, y)] = 1; // terre en bordure = côte (eau au‑delà du cadre)
        q.add(Point(x, y));
      }
    }
  }
  var maxDist = 1;
  const dirs4 = [Point(1, 0), Point(-1, 0), Point(0, 1), Point(0, -1)];
  while (q.isNotEmpty) {
    final c = q.removeFirst();
    for (final d in dirs4) {
      final nx = c.x + d.x, ny = c.y + d.y;
      if (nx < 0 || nx >= cols || ny < 0 || ny >= rows) continue;
      final ni = idx(nx, ny);
      if (dist[ni] != -1 || owner[ni] == null) continue;
      dist[ni] = dist[idx(c.x, c.y)] + 1;
      if (dist[ni] > maxDist) maxDist = dist[ni];
      q.add(Point(nx, ny));
    }
  }

  // 3) BIOME — élévation normalisée 0..255 + jitter de hash (casse les anneaux de
  //    distance), puis seuils ; la côte (adjacence eau) prime.
  final elevation = List<int>.filled(cols * rows, 0);
  final biome = List<OrganicBiome>.filled(cols * rows, OrganicBiome.water);
  bool adjWater(int x, int y) {
    for (final d in dirs4) {
      final nx = x + d.x, ny = y + d.y;
      if (nx < 0 || nx >= cols || ny < 0 || ny >= rows) return true;
      if (owner[idx(nx, ny)] == null) return true;
    }
    return false;
  }

  for (var y = 0; y < rows; y++) {
    for (var x = 0; x < cols; x++) {
      final i = idx(x, y);
      if (owner[i] == null) continue;
      final jitter = (((x * 49157 + y * 98317 + seed * 12289) & 0x7fffffff) % 41) - 20;
      final e = ((dist[i] / maxDist) * 235).round() + jitter;
      final ec = e.clamp(0, 255);
      elevation[i] = ec;
      if (adjWater(x, y)) {
        biome[i] = OrganicBiome.shore;
      } else if (ec < _kForest) {
        biome[i] = OrganicBiome.plain;
      } else if (ec < _kHills) {
        biome[i] = OrganicBiome.forest;
      } else if (ec < _kMountain) {
        biome[i] = OrganicBiome.hills;
      } else {
        biome[i] = OrganicBiome.mountain;
      }
    }
  }

  // Spawn = celui de l'overworld s'il est resté terre, sinon centre de la plus
  // grande contrée.
  var start = base.start;
  if (owner[idx(start.x, start.y)] == null) {
    start = base.regions.isNotEmpty
        ? base.regions.first.center
        : Point(cols ~/ 2, rows ~/ 2);
  }

  return OrganicMap(
    cols: cols,
    rows: rows,
    owner: owner,
    biome: biome,
    elevation: elevation,
    regions: base.regions,
    start: start,
  );
}
