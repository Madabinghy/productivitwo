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
  // Décor déterministe (cosmétique en T0) : buissons 🌿 sur des cases sol,
  // rochers 🪨 sur des cases mur. Encodés "x_y".
  final Set<String> bushes;
  final Set<String> rocks;
  // Porte en bois (chokepoint) : murs spéciaux à PV partagé que l'ennemi doit
  // forcer avant d'atteindre les domaines/château. Encodées "x_y".
  final Set<String> gate;
  // Carte ennemie (spawner) : cases d'où les sbires sont lâchés. Encodées "x_y".
  final Set<String> spawner;

  const UnifiedWorld({
    required this.seed,
    required this.cols,
    required this.rows,
    required this.grid,
    required this.start,
    required this.castle,
    required this.caves,
    required this.bushes,
    required this.rocks,
    this.gate = const {},
    this.spawner = const {},
  });

  bool hasBush(int x, int y) => bushes.contains('${x}_$y');
  bool hasRock(int x, int y) => rocks.contains('${x}_$y');
  bool isGate(int x, int y) => gate.contains('${x}_$y');
  bool isSpawner(int x, int y) => spawner.contains('${x}_$y');

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
UnifiedWorld generateUnifiedWorld(int seed,
    {List<String> caveIds = const ['nw', 'ne', 'sw', 'se']}) {
  final rng = Random(seed);
  // Grande carte : on respire (zone farm large, grottes espacées, vrai voyage
  // gauche→droite). Surtout en hauteur (la largeur du dialog web est bornée).
  const cols = 17, rows = 15;
  final grid = [
    for (int y = 0; y < rows; y++)
      [for (int x = 0; x < cols; x++) UwTile.wall]
  ];
  void floor(int x, int y) {
    if (x < 0 || x >= cols || y < 0 || y >= rows) return;
    if (grid[y][x] == UwTile.wall) grid[y][x] = UwTile.floor;
  }

  final midY = rows ~/ 2; // 7
  final castleX = cols - 1; // 16 — château tout à droite
  const gateX = 9; // porte en bois (chokepoint)
  const gateTop = 5, gateBot = 9;

  // Épine horizontale : entrée gauche → (porte) → domaines → château à droite.
  for (int x = 0; x < cols; x++) floor(x, midY);

  // Zone FARM (gauche, AVANT la porte) : poche ouverte pour poser les tours.
  for (int y = 2; y <= rows - 3; y++) {
    for (int x = 0; x <= gateX - 2; x++) floor(x, y); // x 0..7
  }

  // Bande TERRITOIRE (APRÈS la porte) : grottes décalées en cols 11/14.
  final leftCol = 11;
  final rightCol = 14;
  const topRow = 1;
  final botRow = rows - 2; // 13
  for (int y = topRow; y <= botRow; y++) {
    floor(leftCol, y);
    floor(rightCol, y);
  }
  for (int x = leftCol; x <= rightCol; x++) {
    floor(x, topRow);
    floor(x, botRow);
  }
  // Relie l'épine à la bande et au château (couloir y=midY de la porte au château :
  // on traverse tous les domaines pour arriver au château).
  for (int x = gateX + 1; x <= castleX; x++) floor(x, midY);

  // Quelques poches de sol déterministes côté farm (texture + emplacements tours).
  final pockets = 4 + rng.nextInt(3);
  for (int i = 0; i < pockets; i++) {
    floor(rng.nextInt(gateX - 1), rng.nextInt(rows));
  }

  // Château tout à droite, au milieu (le cœur, derrière tous les domaines).
  grid[midY][castleX] = UwTile.castle;

  // Porte en bois (x=9, y 5..9) : murs spéciaux (bloquent le passage) à PV
  // partagé — l'ennemi doit la forcer avant d'atteindre les domaines.
  final gate = <String>{};
  for (int gy = gateTop; gy <= gateBot; gy++) {
    grid[gy][gateX] = UwTile.wall;
    gate.add('${gateX}_$gy');
  }

  // Carte ennemie (spawner) : x=0, y 6..8 — d'où les sbires sont lâchés.
  final spawner = <String>{};
  for (int sy = 6; sy <= 8; sy++) {
    floor(0, sy);
    spawner.add('0_$sy');
  }

  // Grottes = domaines, réparties sur les deux colonnes de la bande droite
  // (leftCol/rightCol, entièrement creusées → toujours atteignables). Le nombre
  // suit la liste des domaines (N variable). Restent des cases sol : l'avatar
  // engage au contact/dessus.
  final ids = caveIds.isEmpty ? const ['nw', 'ne', 'sw', 'se'] : caveIds;
  final caves = <String, Point<int>>{};
  final leftCount = (ids.length + 1) ~/ 2; // colonne gauche prend l'impair
  List<int> rowsFor(int count) {
    if (count <= 0) return const [];
    if (count == 1) return [(topRow + botRow) ~/ 2];
    final step = (botRow - topRow) / (count - 1);
    return [for (int i = 0; i < count; i++) (topRow + step * i).round()];
  }

  final leftRows = rowsFor(leftCount);
  final rightRows = rowsFor(ids.length - leftCount);
  int li = 0, ri = 0;
  for (int i = 0; i < ids.length; i++) {
    final Point<int> p;
    if (i.isEven && li < leftRows.length) {
      p = Point(leftCol, leftRows[li++]);
    } else if (ri < rightRows.length) {
      p = Point(rightCol, rightRows[ri++]);
    } else {
      p = Point(leftCol, leftRows[li++]);
    }
    caves[ids[i]] = p;
  }
  bool isCave(int x, int y) =>
      caves.values.any((p) => p.x == x && p.y == y);

  // Décor : buissons 🌿 sur des cases sol (hors château/grottes/entrée),
  // rochers 🪨 sur des cases mur révélées → la carte ressemble à du terrain.
  final bushes = <String>{};
  final rocks = <String>{};
  final bushCount = 12 + rng.nextInt(8);
  final rockCount = 18 + rng.nextInt(10);
  var tries = 0;
  while ((bushes.length < bushCount || rocks.length < rockCount) &&
      tries < 800) {
    tries++;
    final bx = rng.nextInt(cols), by = rng.nextInt(rows);
    final key = '${bx}_$by';
    if (gate.contains(key) || spawner.contains(key)) continue;
    final isFloor = grid[by][bx] == UwTile.floor;
    if (isFloor) {
      if (bushes.length >= bushCount) continue;
      if (isCave(bx, by) || (bx == 0 && by == midY)) continue; // grottes / entrée
      bushes.add(key);
    } else if (grid[by][bx] == UwTile.wall) {
      if (rocks.length >= rockCount) continue;
      rocks.add(key);
    }
  }

  return UnifiedWorld(
    seed: seed,
    cols: cols,
    rows: rows,
    grid: grid,
    start: Point(0, midY),
    castle: Point(castleX, midY),
    caves: caves,
    bushes: bushes,
    rocks: rocks,
    gate: gate,
    spawner: spawner,
  );
}

/// Miroir HORIZONTAL d'un monde (x → cols-1-x) : château à gauche, farm à droite.
/// Sert à prévisualiser l'inversion de la map.
UnifiedWorld mirrorWorldX(UnifiedWorld w) {
  String flip(String k) {
    final p = k.split('_');
    return '${w.cols - 1 - int.parse(p[0])}_${p[1]}';
  }

  return UnifiedWorld(
    seed: w.seed,
    cols: w.cols,
    rows: w.rows,
    grid: [
      for (var y = 0; y < w.rows; y++)
        [for (var x = 0; x < w.cols; x++) w.grid[y][w.cols - 1 - x]]
    ],
    start: Point(w.cols - 1 - w.start.x, w.start.y),
    castle: Point(w.cols - 1 - w.castle.x, w.castle.y),
    caves: {
      for (final e in w.caves.entries)
        e.key: Point(w.cols - 1 - e.value.x, e.value.y)
    },
    bushes: {for (final k in w.bushes) flip(k)},
    rocks: {for (final k in w.rocks) flip(k)},
    gate: {for (final k in w.gate) flip(k)},
    spawner: {for (final k in w.spawner) flip(k)},
  );
}
