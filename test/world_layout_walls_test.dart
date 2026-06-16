import 'dart:collection';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/world_layout.dart';

// BFS global sur les cases walkable : `start` atteint-il une case `castle` du
// domaine ? Garantit que les structures de murs ne scellent jamais un domaine.
bool _reaches(WorldLayout w, Point<int> start, bool Function(int, int) goal) {
  final seen = HashSet<int>()..add(start.x * 100000 + start.y);
  final q = Queue<Point<int>>()..add(start);
  while (q.isNotEmpty) {
    final p = q.removeFirst();
    if (goal(p.x, p.y)) return true;
    for (final d in const [
      Point(1, 0),
      Point(-1, 0),
      Point(0, 1),
      Point(0, -1)
    ]) {
      final nx = p.x + d.x, ny = p.y + d.y;
      if (!w.walkable(nx, ny)) continue;
      if (seen.add(nx * 100000 + ny)) q.add(Point(nx, ny));
    }
  }
  return false;
}

DomainSpec _dom(String id, int routines, int activities) => DomainSpec(
      domainId: id,
      colorValue: 0xFF888888,
      routineIds: [for (var i = 0; i < routines; i++) '${id}_r$i'],
      activityIds: [for (var i = 0; i < activities; i++) '${id}_a$i'],
    );

void main() {
  test('chaque jardin reste traversable pour toute taille de domaine', () {
    for (var lines = 0; lines <= 30; lines++) {
      // Répartit les lignes entre routines/activités pour varier sep + parité.
      final r = lines ~/ 2, a = lines - r;
      final w = buildWorld([_dom('d', r, a)]);
      final c = w.castles.single;
      // L'avatar (start) atteint le château du domaine.
      expect(
        _reaches(w, w.start, (x, y) => w.at(x, y) == WtTile.castle),
        isTrue,
        reason: 'lines=$lines : château injoignable (jardin scellé ?)',
      );
      // Les murs déco ne débordent jamais hors du jardin.
      for (final p in c.decoWalls) {
        expect(c.gardenRect.containsPoint(Point(p.x + 0.0, p.y + 0.0)), isTrue,
            reason: 'mur déco hors jardin à $p (lines=$lines)');
        expect(w.at(p.x, p.y), WtTile.wall);
      }
    }
  });

  test('sélection déterministe et bornée au registre', () {
    for (var lines = 0; lines <= 50; lines++) {
      final i = wallTemplateIndexFor(lines);
      expect(i, inInclusiveRange(0, kWallTemplates.length - 1));
      expect(wallTemplateIndexFor(lines), i); // pur/déterministe
      if (lines <= 1) expect(i, 0);
    }
  });

  test('décor cosmétique : seulement terrain/village, déterministe', () {
    final spec = [_dom('a', 3, 2), _dom('b', 0, 4), _dom('c', 5, 0)];
    final w1 = buildWorld(spec);
    final w2 = buildWorld(spec);
    // Déterminisme : même monde → même décor.
    expect(w1.decor.length, w2.decor.length);
    expect(w1.decor.keys.toSet(), w2.decor.keys.toSet());
    // Le décor ne tombe JAMAIS sur une case jouable (mur/jardin/château/coffre/pont).
    for (final key in w1.decor.keys) {
      final parts = key.split('_');
      final x = int.parse(parts[0]), y = int.parse(parts[1]);
      final t = w1.at(x, y);
      expect(t == WtTile.terrain || t == WtTile.village, isTrue,
          reason: 'décor sur tuile $t à $key (doit être terrain/village)');
    }
  });

  test('multi-domaines empilés : tous les châteaux joignables', () {
    final w = buildWorld([
      _dom('a', 3, 0),
      _dom('b', 1, 5),
      _dom('c', 6, 4),
      _dom('d', 0, 2),
    ]);
    for (final c in w.castles) {
      expect(
        _reaches(w, w.start,
            (x, y) => c.castleRect.containsPoint(Point(x + 0.0, y + 0.0))),
        isTrue,
        reason: 'château ${c.domainId} injoignable',
      );
    }
  });
}
