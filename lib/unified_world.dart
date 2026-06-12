import 'dart:math';

// MONDE UNIFIÉ — une grande carte 2D explorable à l'avatar qui FUSIONNE deux HUB :
// à GAUCHE la zone de FARM (chasse), au CENTRE le CHÂTEAU, à DROITE la zone
// TERRITOIRE (4 grottes à défendre ; bord d'arrivée des ennemis). Généré de façon
// DÉTERMINISTE depuis une seed (= seed du territoire → même carte sur tous les
// clients, donc spectatable au futur PvP). PUR (aucune dépendance Flutter) :
// l'état dynamique des grottes/envahisseur vit dans le doc `territories/{uid}`
// (modèles `territory.dart`) — ici on ne produit que la GÉOMÉTRIE traversable.
// Tranche 0 : géométrie + traversée seulement (défense = T1, invasion = T2).

enum UwTile { wall, floor, castle }

class UnifiedWorld {
  final int seed, cols, rows;
  final List<List<UwTile>> grid;
  final Point<int> start; // entrée (bord gauche, zone farm)
  final Point<int> castle; // centre
  // id de grotte ('nw'|'ne'|'sw'|'se') → case dans la bande droite. Les ids
  // matchent ceux du modèle Territory → on superpose l'état (niveau/propriété)
  // lu du doc sans dupliquer la position.
  final Map<String, Point<int>> caves;

  const UnifiedWorld({
    required this.seed,
    required this.cols,
    required this.rows,
    required this.grid,
    required this.start,
    required this.castle,
    required this.caves,
  });

  bool inBounds(int x, int y) => x >= 0 && x < cols && y >= 0 && y < rows;
  bool walkable(int x, int y) => inBounds(x, y) && grid[y][x] != UwTile.wall;
  UwTile at(int x, int y) => grid[y][x];

  /// id de la grotte posée sur cette case, ou null.
  String? caveIdAt(int x, int y) {
    for (final e in caves.entries) {
      if (e.value.x == x && e.value.y == y) return e.key;
    }
    return null;
  }
}

/// Génère le monde unifié (déterministe via seed). Grille tout en mur, puis on
/// CREUSE des couloirs garantissant la connexité : épine horizontale gauche→droite
/// (passe par le château), poche ouverte côté farm, anneau de couloirs dans la
/// bande territoire pour atteindre les 4 grottes des coins.
UnifiedWorld generateUnifiedWorld(int seed) {
  final rng = Random(seed);
  const cols = 15, rows = 9;
  final grid = [
    for (int y = 0; y < rows; y++)
      [for (int x = 0; x < cols; x++) UwTile.wall]
  ];
  void floor(int x, int y) {
    if (x < 0 || x >= cols || y < 0 || y >= rows) return;
    if (grid[y][x] == UwTile.wall) grid[y][x] = UwTile.floor;
  }

  final midY = rows ~/ 2; // 4
  final centerX = cols ~/ 2; // 7

  // Épine horizontale : entrée gauche → château → bande droite.
  for (int x = 0; x < cols; x++) floor(x, midY);

  // Zone FARM (gauche) : poche ouverte pour la chasse.
  for (int y = 2; y <= rows - 3; y++) {
    for (int x = 0; x <= centerX - 2; x++) floor(x, y);
  }

  // Bande TERRITOIRE (droite) : anneau de couloirs reliant les 4 coins.
  final leftCol = cols - 4; // 11
  final rightCol = cols - 1; // 14
  const topRow = 1;
  final botRow = rows - 2; // 7
  for (int y = topRow; y <= botRow; y++) {
    floor(leftCol, y);
    floor(rightCol, y);
  }
  for (int x = leftCol; x <= rightCol; x++) {
    floor(x, topRow);
    floor(x, botRow);
  }
  // Relie l'épine à la bande (le centre du parcours doit toucher l'anneau).
  for (int x = centerX; x <= rightCol; x++) floor(x, midY);

  // Quelques poches de sol déterministes côté farm (texture la chasse à venir).
  final pockets = 4 + rng.nextInt(3);
  for (int i = 0; i < pockets; i++) {
    floor(rng.nextInt(centerX - 1), rng.nextInt(rows));
  }

  // Château au centre.
  grid[midY][centerX] = UwTile.castle;

  // Grottes aux 4 coins de la bande droite (restent des cases sol : l'avatar
  // engage au contact/dessus en T1).
  final caves = <String, Point<int>>{
    'nw': const Point(11, topRow),
    'ne': const Point(14, topRow),
    'sw': Point(leftCol, botRow),
    'se': Point(rightCol, botRow),
  };

  return UnifiedWorld(
    seed: seed,
    cols: cols,
    rows: rows,
    grid: grid,
    start: Point(0, midY),
    castle: Point(centerX, midY),
    caves: caves,
  );
}
