import 'dart:math';

/// MONDE V2 — UNE seule carte data‑driven : chaque domaine = une **bande** empilée
/// verticalement, full‑width, de la forme :
///
///   [ village (gauche) · jardin de serpents · CALENDRIER du domaine (droite) ]
///
/// Les bandes sont reliées par un **pont vertical à gauche** ; l'avatar circule sur
/// TOUT (plus de grotte à entrer). Le calendrier (lanes routines/activités) est rendu
/// INLINE : remplissage château (heatmap) + 7 colonnes‑jours, une ligne par
/// routine/activité. Le jardin ne fait farmer que les **serpents** (tâches en retard).
/// Le domaine le plus envahi est placé en haut. La carte grandit avec les données.
///
/// Ce fichier est PUR (records en entrée, aucune dépendance à AppLogic).

enum WtTile { terrain, wall, castle, garden, chest, village, bridge }

/// Entrée de construction : un domaine et ses lignes.
class DomainSpec {
  final String domainId;
  final int? colorValue; // ARGB du domaine
  final List<String> routineIds;
  final List<String> activityIds;
  const DomainSpec({
    required this.domainId,
    this.colorValue,
    this.routineIds = const [],
    this.activityIds = const [],
  });
  int get lines => routineIds.length + activityIds.length;
}

/// Une ligne du calendrier (routine/activité) projetée sur la grille.
class LaneRow {
  final String id;
  final bool isRoutine; // true = routine 🕷️, false = activité‑temps 🦂
  final int y; // rangée absolue
  final int turretX; // colonne de la tourelle (défense) + chargeur
  final int dayX0; // 1ʳᵉ des 7 colonnes‑jours (aujourd'hui = dayX0 + 6)
  const LaneRow(this.id, this.isRoutine, this.y, this.turretX, this.dayX0);
}

/// La bande (stripe) d'un domaine.
class CastleBlock {
  final String domainId;
  final int? colorValue;
  final Rectangle<int> bounds;
  final Rectangle<int> villageRect;
  final Rectangle<int> gardenRect; // jardin (serpents)
  final Rectangle<int> castleRect; // calendrier (tourelle + 7 jours)
  final List<LaneRow> lanes;
  final int sepY; // rangée séparatrice routines/activités (-1 si aucune)
  final int headerY; // rangée des libellés de jours (L M M J V S D)
  final int dayX0; // 1ʳᵉ des 7 colonnes‑jours (aujourd'hui = dayX0 + 6)
  const CastleBlock({
    required this.domainId,
    required this.colorValue,
    required this.bounds,
    required this.villageRect,
    required this.gardenRect,
    required this.castleRect,
    required this.lanes,
    required this.sepY,
    required this.headerY,
    required this.dayX0,
  });
}

class WorldLayout {
  final int cols, rows;
  final List<List<WtTile>> grid;
  final List<CastleBlock> castles;
  final Map<String, CastleBlock> byDomain;
  final Set<String> chests;
  final Point<int> start;
  WorldLayout({
    required this.cols,
    required this.rows,
    required this.grid,
    required this.castles,
    required this.chests,
    required this.start,
  }) : byDomain = {for (final c in castles) c.domainId: c};

  bool inBounds(int x, int y) => x >= 0 && x < cols && y >= 0 && y < rows;
  WtTile at(int x, int y) => grid[y][x];
  bool walkable(int x, int y) => inBounds(x, y) && grid[y][x] != WtTile.wall;
}

// ── Géométrie d'une bande ──────────────────────────────────────────────────
const int _kBridgeW = 3;
const int _kVillageCols = 5;
const int _kGardenCols = 12; // jardin (serpents)
const int _kTurretCols = 1; // tourelle (défense) + chargeur
const int _kDayCols = 7; // 7 colonnes‑jours
const int _kCastleCols = _kTurretCols + _kDayCols; // 8
const int _kInnerW = _kVillageCols + _kGardenCols + _kCastleCols; // 25
const int _kMinInnerRows = 4;
const int _kMargin = 2;
const int _kRightExt = 7; // extérieur à DROITE : d'où viennent les nuisibles + noms

// Routines en haut, séparateur, activités en bas (comme l'intérieur).
bool _hasSep(DomainSpec d) =>
    d.routineIds.isNotEmpty && d.activityIds.isNotEmpty;
int _innerRows(DomainSpec d) {
  final n = 1 + d.lines + (_hasSep(d) ? 1 : 0); // +1 = rangée libellés de jours
  return n < _kMinInnerRows ? _kMinInnerRows : n;
}

int _blockH(DomainSpec d) => _innerRows(d) + 2;
int _blockW() => _kInnerW + 2;

WorldLayout buildWorld(List<DomainSpec> domains, {int seed = 0}) {
  if (domains.isEmpty) {
    final cols = _kBridgeW + _blockW() + 2 * _kMargin;
    final rows = _kMinInnerRows + 2 + 2 * _kMargin;
    final grid = [
      for (int y = 0; y < rows; y++)
        [for (int x = 0; x < cols; x++) WtTile.terrain]
    ];
    return WorldLayout(
        cols: cols,
        rows: rows,
        grid: grid,
        castles: const [],
        chests: const {},
        start: Point(cols ~/ 2, rows ~/ 2));
  }

  final blockLeft = _kMargin + _kBridgeW;
  // Pas de mur à droite : extérieur (nuisibles + libellés des lignes).
  final worldCols = blockLeft + _blockW() + _kRightExt;
  // Murs PARTAGÉS : le mur du bas d'un domaine = le mur du haut du suivant
  // (chevauchement d'1 rangée) → pas de terrain entre les châteaux.
  final worldRows = _kMargin * 2 +
      domains.fold<int>(0, (s, d) => s + _blockH(d)) -
      (domains.length - 1);

  final grid = [
    for (int y = 0; y < worldRows; y++)
      [for (int x = 0; x < worldCols; x++) WtTile.terrain]
  ];

  final bridgeX = _kMargin + _kBridgeW ~/ 2;
  for (var y = _kMargin; y < worldRows - _kMargin; y++) {
    grid[y][bridgeX] = WtTile.bridge;
  }

  final castles = <CastleBlock>[];
  var top = _kMargin;
  for (final d in domains) {
    castles.add(_carveBlock(grid, d, blockLeft, top, bridgeX));
    top += _blockH(d) - 1; // chevauchement du mur partagé
  }

  // RACCOURCI : une porte dans le mur PARTAGÉ entre domaines adjacents, en plein
  // jardin → on traverse d'un jardin à l'autre verticalement (sans repasser par le
  // pont). 2 ouvertures (gauche/droite du jardin) pour fluidifier.
  for (var k = 1; k < castles.length; k++) {
    final lower = castles[k];
    final sharedRow = lower.bounds.top; // = mur du bas du domaine au‑dessus
    final g = lower.gardenRect;
    grid[sharedRow][g.left + g.width ~/ 3] = WtTile.garden;
    grid[sharedRow][g.left + (2 * g.width) ~/ 3] = WtTile.garden;
  }

  final rng = Random(seed == 0 ? domains.length + 7 : seed);
  final chests = <String>{};
  final chestCount = 2 + domains.length ~/ 2;
  var tries = 0;
  while (chests.length < chestCount && tries < 400) {
    tries++;
    final x = rng.nextInt(worldCols), y = rng.nextInt(worldRows);
    if (grid[y][x] == WtTile.terrain) {
      grid[y][x] = WtTile.chest;
      chests.add('${x}_$y');
    }
  }

  // Spawn TOUT EN BAS À GAUCHE : village du dernier domaine (bas de la tour).
  final last = castles.last;
  final start = Point(last.villageRect.left,
      last.villageRect.top + last.villageRect.height - 1);

  return WorldLayout(
      cols: worldCols,
      rows: worldRows,
      grid: grid,
      castles: castles,
      chests: chests,
      start: start);
}

CastleBlock _carveBlock(
    List<List<WtTile>> grid, DomainSpec d, int left, int top, int bridgeX) {
  final innerRows = _innerRows(d);
  final w = _blockW(), h = innerRows + 2;
  // Murs : haut, bas, gauche — PAS à droite (les nuisibles viennent de l'extérieur).
  for (var y = top; y < top + h; y++) {
    for (var x = left; x < left + w; x++) {
      final edge = y == top || y == top + h - 1 || x == left;
      if (edge) grid[y][x] = WtTile.wall;
    }
  }
  final il = left + 1, it = top + 1;
  final midY = it + innerRows ~/ 2;
  final villageRect = Rectangle(il, it, _kVillageCols, innerRows);
  final gardenRect = Rectangle(il + _kVillageCols, it, _kGardenCols, innerRows);
  final castleLeft = il + _kVillageCols + _kGardenCols;
  final castleRect = Rectangle(castleLeft, it, _kCastleCols, innerRows);
  for (var y = it; y < it + innerRows; y++) {
    for (var x = il; x < il + _kVillageCols; x++) {
      grid[y][x] = WtTile.village;
    }
    for (var x = il + _kVillageCols; x < castleLeft; x++) {
      grid[y][x] = WtTile.garden;
    }
    for (var x = castleLeft; x < il + _kInnerW; x++) {
      grid[y][x] = WtTile.castle;
    }
  }

  // Rangée 0 = libellés de jours ; puis routines (🕷️), séparateur, activités (🦂).
  // Tourelle (défense) à gauche, puis 7 colonnes‑jours.
  final lanes = <LaneRow>[];
  final turretX = castleLeft;
  final dayX0 = castleLeft + _kTurretCols;
  final headerY = it;
  var row = it + 1;
  for (final r in d.routineIds) {
    if (row >= it + innerRows) break;
    lanes.add(LaneRow(r, true, row, turretX, dayX0));
    row++;
  }
  final sepY = _hasSep(d) ? row : -1;
  if (_hasSep(d) && row < it + innerRows) row++;
  for (final a in d.activityIds) {
    if (row >= it + innerRows) break;
    lanes.add(LaneRow(a, false, row, turretX, dayX0));
    row++;
  }

  // Pont : porte dans le mur gauche (mi‑hauteur) + corridor jusqu'au pont vertical.
  grid[midY][left] = WtTile.bridge;
  for (var x = bridgeX; x < left; x++) {
    grid[midY][x] = WtTile.bridge;
  }

  return CastleBlock(
    domainId: d.domainId,
    colorValue: d.colorValue,
    bounds: Rectangle(left, top, w, h),
    villageRect: villageRect,
    gardenRect: gardenRect,
    castleRect: castleRect,
    lanes: lanes,
    sepY: sepY,
    headerY: headerY,
    dayX0: dayX0,
  );
}
