import 'dart:math';

// ── Jeu de territoire : la map PERSISTÉE d'un user ───────────────────────────
// Un doc Firestore `territories/{uid}` = source de vérité (pas de Random local) :
// l'envahisseur spectate la même map. La grille/labyrinthe se RÉGÉNÈRE identique
// sur tous les clients depuis `seed` (déterministe), donc seul l'état dynamique
// est stocké. Sous-tranche A : château au centre + 4 grottes aux coins + brouillard.
// (L'envahisseur courant arrive en sous-tranche C, le siège en D.)

enum TerrTile { wall, floor, castle, cave }

/// Une grotte = territoire défensif. Possédée → 🔵 bleu, son boss = ton deck bleu
/// (niveau `blueLevel`, monté en battant ton propre boss). `occupied` = un
/// envahisseur s'y est installé (siège à venir, sous-tranche D).
class TerritoryCave {
  final String id; // 'nw' | 'ne' | 'sw' | 'se'
  final int x, y;
  final String ownerUid;
  final int blueLevel;
  final bool occupied;

  const TerritoryCave({
    required this.id,
    required this.x,
    required this.y,
    required this.ownerUid,
    required this.blueLevel,
    required this.occupied,
  });

  TerritoryCave copyWith({String? ownerUid, int? blueLevel, bool? occupied}) =>
      TerritoryCave(
        id: id,
        x: x,
        y: y,
        ownerUid: ownerUid ?? this.ownerUid,
        blueLevel: blueLevel ?? this.blueLevel,
        occupied: occupied ?? this.occupied,
      );

  static TerritoryCave from(Map j) => TerritoryCave(
        id: (j['id'] ?? '') as String,
        x: (j['x'] as num?)?.toInt() ?? 0,
        y: (j['y'] as num?)?.toInt() ?? 0,
        ownerUid: (j['ownerUid'] ?? '') as String,
        blueLevel: (j['blueLevel'] as num?)?.toInt() ?? 1,
        occupied: (j['occupied'] as bool?) ?? false,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'x': x,
        'y': y,
        'ownerUid': ownerUid,
        'blueLevel': blueLevel,
        'occupied': occupied,
      };
}

class Territory {
  final String uid, pseudo;
  final int seed, cols, rows;
  final Point<int> castle;
  final bool fog;
  final List<TerritoryCave> caves;

  const Territory({
    required this.uid,
    required this.pseudo,
    required this.seed,
    required this.cols,
    required this.rows,
    required this.castle,
    required this.fog,
    required this.caves,
  });

  /// Niveau de map = Σ des 4 niveaux de grottes (= rang ladder à venir).
  int get level => caves.fold(0, (s, c) => s + c.blueLevel);

  /// Combien de grottes je possède encore.
  int ownedCount(String me) => caves.where((c) => c.ownerUid == me).length;

  TerritoryCave? caveById(String id) {
    for (final c in caves) {
      if (c.id == id) return c;
    }
    return null;
  }

  Territory copyWith({bool? fog, List<TerritoryCave>? caves, int? seed}) =>
      Territory(
        uid: uid,
        pseudo: pseudo,
        seed: seed ?? this.seed,
        cols: cols,
        rows: rows,
        castle: castle,
        fog: fog ?? this.fog,
        caves: caves ?? this.caves,
      );

  static Territory from(Map j) {
    final c = (j['castle'] as Map?) ?? const {};
    return Territory(
      uid: (j['uid'] ?? '') as String,
      pseudo: (j['pseudo'] ?? 'Anonyme') as String,
      seed: (j['seed'] as num?)?.toInt() ?? 0,
      cols: (j['cols'] as num?)?.toInt() ?? 9,
      rows: (j['rows'] as num?)?.toInt() ?? 9,
      castle: Point((c['x'] as num?)?.toInt() ?? 4, (c['y'] as num?)?.toInt() ?? 4),
      fog: (j['fog'] as bool?) ?? true,
      caves: ((j['caves'] as List?) ?? const [])
          .map((e) => TerritoryCave.from(e as Map))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'uid': uid,
        'pseudo': pseudo,
        'seed': seed,
        'cols': cols,
        'rows': rows,
        'castle': {'x': castle.x, 'y': castle.y},
        'fog': fog,
        'level': level, // dénormalisé pour la query ladder
        'caves': [for (final c in caves) c.toJson()],
      };
}

/// Territoire initial d'un user : 9×9, château au centre, 4 grottes aux coins,
/// toutes possédées (niveau 1), brouillard actif. Seed déterministe depuis l'uid.
Territory initialTerritory(String uid, String pseudo, {int? seed}) {
  const cols = 9, rows = 9;
  final s = seed ?? (uid.hashCode & 0x7fffffff);
  final caves = <TerritoryCave>[
    TerritoryCave(id: 'nw', x: 0, y: 0, ownerUid: uid, blueLevel: 1, occupied: false),
    TerritoryCave(id: 'ne', x: cols - 1, y: 0, ownerUid: uid, blueLevel: 1, occupied: false),
    TerritoryCave(id: 'sw', x: 0, y: rows - 1, ownerUid: uid, blueLevel: 1, occupied: false),
    TerritoryCave(id: 'se', x: cols - 1, y: rows - 1, ownerUid: uid, blueLevel: 1, occupied: false),
  ];
  return Territory(
    uid: uid,
    pseudo: pseudo,
    seed: s,
    cols: cols,
    rows: rows,
    castle: const Point(cols ~/ 2, rows ~/ 2),
    fog: true,
    caves: caves,
  );
}

/// Grille DÉTERMINISTE depuis la seed : tout en mur, puis on creuse un chemin
/// floor du château vers CHAQUE grotte (toutes atteignables ; le reste = murs à
/// percer à la pioche plus tard). Identique sur tous les clients à seed égale.
List<List<TerrTile>> generateTerritoryGrid(Territory t) {
  final rng = Random(t.seed);
  final grid = [
    for (var y = 0; y < t.rows; y++)
      [for (var x = 0; x < t.cols; x++) TerrTile.wall]
  ];
  void floor(int x, int y) {
    if (x < 0 || x >= t.cols || y < 0 || y >= t.rows) return;
    if (grid[y][x] == TerrTile.wall) grid[y][x] = TerrTile.floor;
  }

  // Chemin de Manhattan château→(tx,ty), axe choisi par la seed (sinue un peu).
  void carve(int tx, int ty) {
    var x = t.castle.x, y = t.castle.y;
    floor(x, y);
    while (x != tx || y != ty) {
      final dx = tx - x, dy = ty - y;
      if (dx != 0 && (dy == 0 || rng.nextBool())) {
        x += dx > 0 ? 1 : -1;
      } else {
        y += dy > 0 ? 1 : -1;
      }
      floor(x, y);
    }
  }

  for (final c in t.caves) {
    carve(c.x, c.y);
  }
  grid[t.castle.y][t.castle.x] = TerrTile.castle;
  for (final c in t.caves) {
    grid[c.y][c.x] = TerrTile.cave;
  }
  return grid;
}
