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

/// Décor PUREMENT VISUEL (overlay cosmétique, n'affecte jamais walkable) : posé
/// de façon déterministe sur le terrain extérieur, les villages et les abords des
/// murs pour donner vie à la carte.
enum WtDecor { rock, tree, bush, house, torch }

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
  final Set<Point<int>> decoWalls; // murs intérieurs déco (cases absolues)
  // true = domaine de la COLONNE GAUCHE, agencé en MIROIR (château à gauche/extérieur,
  // village à droite/cour ; mur fermé à droite). Le rendu adapte le nom + l'araignée.
  final bool mirror;
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
    this.decoWalls = const {},
    this.mirror = false,
  });
}

class WorldLayout {
  final int cols, rows;
  final List<List<WtTile>> grid;
  final List<CastleBlock> castles;
  final Map<String, CastleBlock> byDomain;
  final Set<String> chests;
  final Map<String, WtDecor> decor; // "x_y" → décor cosmétique (overlay)
  final Point<int> start;
  final int courLeft, courRight; // bande X de la COUR centrale (courRight exclusif)
  final Point<int>? donjonAt; // tuile du donjon, en haut de la cour (au‑dessus des domaines)
  WorldLayout({
    required this.cols,
    required this.rows,
    required this.grid,
    required this.castles,
    required this.chests,
    required this.start,
    required this.courLeft,
    required this.courRight,
    this.decor = const {},
    this.donjonAt,
  }) : byDomain = {for (final c in castles) c.domainId: c};

  bool inBounds(int x, int y) => x >= 0 && x < cols && y >= 0 && y < rows;
  WtTile at(int x, int y) => grid[y][x];
  bool walkable(int x, int y) => inBounds(x, y) && grid[y][x] != WtTile.wall;
  // COUR centrale (gazon) : terrain situé dans la bande X entre les deux colonnes.
  bool isCourtyard(int x, int y) =>
      inBounds(x, y) &&
      x >= courLeft &&
      x < courRight &&
      grid[y][x] == WtTile.terrain;
}

// ── Géométrie d'une bande ──────────────────────────────────────────────────
const int _kBridgeW = 3;
const int _kVillageCols = 5;
const int _kGardenCols = 12; // jardin (serpents)
const int _kTurretCols = 1; // tourelle (défense) + chargeur
const int _kDayCols = 7; // 7 colonnes‑jours
const int _kCastleCols = _kTurretCols + _kDayCols; // 8
const int _kInnerW = _kVillageCols + _kGardenCols + _kCastleCols; // 25
// Hauteur intérieure MINIMALE d'un domaine : garantit un jardin assez grand pour
// que la mini‑app dashboard (qui recouvre le jardin) soit lisible/utilisable.
const int _kMinInnerRows = 10;
const int _kMargin = 2;
// Bande RÉSERVÉE en haut de la map (au‑dessus des châteaux) : y est affiché en
// permanence le donjon (vue ExpeditionView). Les châteaux/cour sont décalés vers
// le bas d'autant ; le bas du panneau donjon tombe pile au sommet des châteaux.
const int _kDonjonRows = 13;
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

// ── Structures de murs intérieures (déterministes par nombre de lignes) ──────
// Chaque domaine reçoit, dans son JARDIN, une « silhouette de forteresse » faite
// de murs. La sélection est déterministe (même nb de lignes → même structure) et
// le registre est EXTENSIBLE : on ajoute un template en l'appendant à la fin.

/// Contexte passé à un template : dimensions du jardin + nb de lignes du domaine.
class WallTemplateCtx {
  final int width; // = gardenRect.width (12)
  final int height; // = gardenRect.height (variable selon lines)
  final int lines; // DomainSpec.lines (sémantique métier ≠ height)
  const WallTemplateCtx(this.width, this.height, this.lines);
}

/// Renvoie les cases murs en coords RELATIVES au gardenRect (0,0 = haut‑gauche).
/// INVARIANT que chaque template DOIT respecter : jamais x==0 ni x==width-1, jamais
/// une colonne entière, jamais une ligne entière → la 1ʳᵉ et la dernière colonne du
/// jardin restent libres = corridor d'entrée/sortie garanti. (Le stamping valide en
/// plus la connectivité par flood‑fill, donc un template fautif est neutralisé.)
typedef WallTemplate = Set<Point<int>> Function(WallTemplateCtx ctx);

Set<Point<int>> _tplEmpty(WallTemplateCtx c) => const {};

Set<Point<int>> _tplPillars(WallTemplateCtx c) {
  final s = <Point<int>>{};
  for (var y = 1; y <= c.height - 2; y += 2) {
    for (var x = 2; x <= c.width - 3; x += 3) {
      s.add(Point(x, y));
    }
  }
  return s;
}

Set<Point<int>> _tplCentralDivider(WallTemplateCtx c) {
  final s = <Point<int>>{};
  final cx = c.width ~/ 2; // ∈ [1, width-2] car width=12
  final gapY = c.height ~/ 2; // un passage garanti
  for (var y = 1; y <= c.height - 2; y++) {
    if (y == gapY) continue;
    s.add(Point(cx, y));
  }
  return s;
}

Set<Point<int>> _tplCorners(WallTemplateCtx c) {
  if (c.width < 3 || c.height < 3) return const {};
  return {
    const Point(1, 1),
    Point(c.width - 2, 1),
    Point(1, c.height - 2),
    Point(c.width - 2, c.height - 2),
  };
}

Set<Point<int>> _tplChevrons(WallTemplateCtx c) {
  if (c.width < 5) return const {};
  final s = <Point<int>>{};
  for (var y = 1; y <= c.height - 2; y++) {
    s.add(Point(2 + (y % (c.width - 4)), y)); // 1 mur/ligne → ligne jamais scellée
  }
  return s;
}

/// REGISTRE : ordre STABLE. Index 0 = template VIDE (fallback sûr). Ne JAMAIS
/// réordonner (la sélection est déterministe par index). Ajouter = append en fin.
const List<WallTemplate> kWallTemplates = <WallTemplate>[
  _tplEmpty,
  _tplPillars,
  _tplCentralDivider,
  _tplCorners,
  _tplChevrons,
];

/// Sélection déterministe par nb de lignes (hash de Knuth borné, pas `% length`
/// brut qui aurait une période courte). `lines<=1` → vide (petits domaines respirent).
int wallTemplateIndexFor(int lines) {
  if (lines <= 1) return 0;
  return 1 + ((lines * 2654435761) >> 8) % (kWallTemplates.length - 1);
}

/// BFS 4‑dir bornée au gardenRect (walkable = WtTile.garden). True si la colonne
/// gauche du jardin atteint sa colonne droite → village→jardin→château traversable.
bool _gardenConnectedLR(List<List<WtTile>> grid, Rectangle<int> g) {
  final left = g.left, right = g.left + g.width - 1;
  final seen = <int>{};
  final queue = <Point<int>>[];
  for (var y = g.top; y < g.top + g.height; y++) {
    if (grid[y][left] == WtTile.garden) {
      seen.add(left * 100000 + y);
      queue.add(Point(left, y));
    }
  }
  var head = 0;
  while (head < queue.length) {
    final p = queue[head++];
    if (p.x == right) return true;
    for (final d in const [Point(1, 0), Point(-1, 0), Point(0, 1), Point(0, -1)]) {
      final nx = p.x + d.x, ny = p.y + d.y;
      if (nx < left || nx > right || ny < g.top || ny >= g.top + g.height) continue;
      if (grid[ny][nx] != WtTile.garden) continue;
      final key = nx * 100000 + ny;
      if (seen.add(key)) queue.add(Point(nx, ny));
    }
  }
  return false;
}

/// Choisit le template selon `lines`, l'applique (n'écrase QUE des cases garden),
/// valide la connectivité ; si le jardin est scellé → revert + fallback vide.
/// Retourne les cases murs ABSOLUES réellement posées (pour le rendu déco).
Set<Point<int>> _stampGardenWalls(
    List<List<WtTile>> grid, Rectangle<int> g, int lines) {
  final tpl = kWallTemplates[wallTemplateIndexFor(lines)];
  final rel = tpl(WallTemplateCtx(g.width, g.height, lines));
  final placed = <Point<int>>{};
  for (final p in rel) {
    final x = g.left + p.x, y = g.top + p.y;
    if (x < g.left || x >= g.left + g.width) continue; // clamp défensif
    if (y < g.top || y >= g.top + g.height) continue;
    if (grid[y][x] != WtTile.garden) continue; // n'écrase jamais autre chose
    grid[y][x] = WtTile.wall;
    placed.add(Point(x, y));
  }
  if (!_gardenConnectedLR(grid, g)) {
    for (final p in placed) {
      grid[p.y][p.x] = WtTile.garden; // revert → jardin garanti ouvert
    }
    return const {};
  }
  return placed;
}

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
        start: Point(cols ~/ 2, rows ~/ 2),
        courLeft: 0,
        courRight: 0);
  }

  // DEUX COLONNES : domaine 1 (index 0) à DROITE, domaine 2 à GAUCHE (miroir), etc.
  final rightDomains = <DomainSpec>[];
  final leftDomains = <DomainSpec>[];
  for (var i = 0; i < domains.length; i++) {
    (i.isEven ? rightDomains : leftDomains).add(domains[i]);
  }
  int colHeight(List<DomainSpec> col) => col.isEmpty
      ? 0
      : col.fold<int>(0, (s, d) => s + _blockH(d)) - (col.length - 1);
  final hR = colHeight(rightDomains), hL = colHeight(leftDomains);
  // + bande donjon réservée en haut (au‑dessus des châteaux).
  final worldRows = _kMargin * 2 + _kDonjonRows + (hR > hL ? hR : hL);

  // Largeur : [ext gauche][bloc GAUCHE miroir][COUR][bloc DROITE normal][ext droite].
  const courW = 5;
  final blockW = _blockW();
  final gBlockL = _kMargin + _kRightExt; // bloc gauche (après l'extension gauche)
  final courL = gBlockL + blockW; // début de la cour
  final dBlockL = courL + courW; // bloc droite
  final worldCols = dBlockL + blockW + _kRightExt + _kMargin;

  final grid = [
    for (int y = 0; y < worldRows; y++)
      [for (int x = 0; x < worldCols; x++) WtTile.terrain]
  ];

  // Pont vertical CENTRAL (dans la cour) — relie les deux colonnes. Démarre SOUS la
  // bande donjon réservée.
  final bridgeX = courL + courW ~/ 2;
  for (var y = _kMargin + _kDonjonRows; y < worldRows - _kMargin; y++) {
    grid[y][bridgeX] = WtTile.bridge;
  }

  // Châteaux empilés SOUS la bande donjon (décalés de _kDonjonRows vers le bas).
  final castles = <CastleBlock>[];
  var topR = _kMargin + _kDonjonRows;
  for (final d in rightDomains) {
    castles.add(_carveBlock(grid, d, dBlockL, topR, bridgeX, mirror: false));
    topR += _blockH(d) - 1;
  }
  var topL = _kMargin + _kDonjonRows;
  for (final d in leftDomains) {
    castles.add(_carveBlock(grid, d, gBlockL, topL, bridgeX, mirror: true));
    topL += _blockH(d) - 1;
  }

  // RACCOURCI : portes dans les murs partagés entre domaines d'une MÊME colonne
  // (jardin → jardin verticalement, sans repasser par le pont central).
  void interGardenDoors(List<CastleBlock> col) {
    for (var k = 1; k < col.length; k++) {
      final g = col[k].gardenRect;
      final sharedRow = col[k].bounds.top;
      grid[sharedRow][g.left + g.width ~/ 3] = WtTile.garden;
      grid[sharedRow][g.left + (2 * g.width) ~/ 3] = WtTile.garden;
    }
  }
  interGardenDoors(castles.where((c) => !c.mirror).toList());
  interGardenDoors(castles.where((c) => c.mirror).toList());

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

  // Spawn AU CENTRE de la cour (entre les deux colonnes).
  final start = Point(bridgeX, worldRows ~/ 2);

  // Décor cosmétique en DERNIER (lit la grille finale, n'écrase rien de jouable).
  final decor = _buildDecor(grid, castles, worldCols, worldRows, rng);

  // Donjon : ancré en HAUT de la bande réservée ; le panneau (hauteur _kDonjonRows)
  // descend jusqu'au sommet des châteaux.
  final donjonAt = Point(bridgeX, _kMargin);

  return WorldLayout(
      cols: worldCols,
      rows: worldRows,
      grid: grid,
      castles: castles,
      chests: chests,
      start: start,
      courLeft: courL,
      courRight: dBlockL,
      decor: decor,
      donjonAt: donjonAt);
}

/// Décor PUREMENT VISUEL, déterministe (même monde → même décor). Posé sur le
/// terrain extérieur (rochers/arbres/buissons), les villages (maisons) et les
/// abords des murs (torches). N'écrit JAMAIS dans `grid` → zéro impact walkable.
Map<String, WtDecor> _buildDecor(List<List<WtTile>> grid,
    List<CastleBlock> castles, int cols, int rows, Random rng) {
  final decor = <String, WtDecor>{};
  bool isWall(int x, int y) =>
      x >= 0 && x < cols && y >= 0 && y < rows && grid[y][x] == WtTile.wall;
  bool wallAdj(int x, int y) =>
      isWall(x - 1, y) || isWall(x + 1, y) || isWall(x, y - 1) || isWall(x, y + 1);

  // 1) Maisons dans les villages (~1 par 8 cases, ≥1 par village).
  for (final c in castles) {
    final v = c.villageRect;
    final cells = <Point<int>>[];
    for (var y = v.top; y < v.top + v.height; y++) {
      for (var x = v.left; x < v.left + v.width; x++) {
        if (grid[y][x] == WtTile.village) cells.add(Point(x, y));
      }
    }
    cells.shuffle(rng);
    final n = 1 + cells.length ~/ 8;
    for (var i = 0; i < n && i < cells.length; i++) {
      decor['${cells[i].x}_${cells[i].y}'] = WtDecor.house;
    }
  }

  // Cases RÉSERVÉES aux libellés de lignes (noms routines/activités, rendus à
  // droite des 7 colonnes‑jours) : JAMAIS de décor dessus, sinon il masque le
  // texte et casse la lisibilité. La 1ʳᵉ colonne du nom = dayX0 + 7.
  final protectedCells = <Point<int>>{};
  for (final c in castles) {
    for (final l in c.lanes) {
      if (c.mirror) {
        // Miroir : noms à GAUCHE du château (avant la tourelle).
        for (var x = 0; x < l.turretX; x++) {
          protectedCells.add(Point(x, l.y));
        }
      } else {
        for (var x = l.dayX0 + 7; x < cols; x++) {
          protectedCells.add(Point(x, l.y));
        }
      }
    }
  }

  // 2) Terrain extérieur épars + torches le long des remparts.
  const scatter = [WtDecor.rock, WtDecor.tree, WtDecor.bush];
  for (var y = 0; y < rows; y++) {
    for (var x = 0; x < cols; x++) {
      final id = '${x}_$y';
      if (decor.containsKey(id)) continue;
      if (protectedCells.contains(Point(x, y))) continue; // zone des noms
      final t = grid[y][x];
      if (t == WtTile.terrain) {
        if (wallAdj(x, y) && rng.nextDouble() < 0.18) {
          decor[id] = WtDecor.torch;
        } else if (rng.nextDouble() < 0.10) {
          decor[id] = scatter[rng.nextInt(scatter.length)];
        }
      } else if (t == WtTile.village &&
          wallAdj(x, y) &&
          rng.nextDouble() < 0.12) {
        decor[id] = WtDecor.torch;
      }
    }
  }
  return decor;
}

CastleBlock _carveBlock(
    List<List<WtTile>> grid, DomainSpec d, int left, int top, int bridgeX,
    {bool mirror = false}) {
  final innerRows = _innerRows(d);
  final w = _blockW(), h = innerRows + 2;
  // Murs haut/bas + côté INTÉRIEUR (vers la cour) fermé ; côté EXTÉRIEUR ouvert
  // (par où viennent les nuisibles). Normal : intérieur=gauche. Miroir : intérieur=droite.
  for (var y = top; y < top + h; y++) {
    for (var x = left; x < left + w; x++) {
      final closed = mirror ? (x == left + w - 1) : (x == left);
      final edge = y == top || y == top + h - 1 || closed;
      if (edge) grid[y][x] = WtTile.wall;
    }
  }
  final il = left + 1, it = top + 1;
  final midY = it + innerRows ~/ 2;

  // Agencement horizontal des zones (inversé en miroir).
  final Rectangle<int> villageRect, gardenRect, castleRect;
  final int castleLeft, turretX, dayX0;
  if (!mirror) {
    // [village][jardin][château : tourelle + 7 jours] — calendrier à DROITE.
    villageRect = Rectangle(il, it, _kVillageCols, innerRows);
    gardenRect = Rectangle(il + _kVillageCols, it, _kGardenCols, innerRows);
    castleLeft = il + _kVillageCols + _kGardenCols;
    castleRect = Rectangle(castleLeft, it, _kCastleCols, innerRows);
    turretX = castleLeft;
    dayX0 = castleLeft + _kTurretCols;
  } else {
    // [château : 7 jours | tourelle][jardin][village]. Les 7 jours sont à GAUCHE
    // (extérieur, d'où arrivent les nuisibles) ; la tourelle est à DROITE (intérieur)
    // et vise vers la gauche pour empêcher les nuisibles de rentrer.
    castleLeft = il;
    castleRect = Rectangle(castleLeft, it, _kCastleCols, innerRows);
    gardenRect = Rectangle(il + _kCastleCols, it, _kGardenCols, innerRows);
    villageRect =
        Rectangle(il + _kCastleCols + _kGardenCols, it, _kVillageCols, innerRows);
    dayX0 = castleLeft; // 7 jours à gauche [castleLeft, castleLeft+7)
    turretX = castleLeft + _kDayCols; // tourelle à droite des jours (intérieur)
  }
  for (var y = it; y < it + innerRows; y++) {
    for (var x = villageRect.left; x < villageRect.left + _kVillageCols; x++) {
      grid[y][x] = WtTile.village;
    }
    for (var x = gardenRect.left; x < gardenRect.left + _kGardenCols; x++) {
      grid[y][x] = WtTile.garden;
    }
    for (var x = castleRect.left; x < castleRect.left + _kCastleCols; x++) {
      grid[y][x] = WtTile.castle;
    }
  }

  // Rangée 0 = libellés de jours ; puis routines (🕷️), séparateur, activités (🦂).
  final lanes = <LaneRow>[];
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

  // Pont : porte dans le mur INTÉRIEUR (vers le pont central) + corridor.
  if (!mirror) {
    grid[midY][left] = WtTile.bridge; // mur gauche
    for (var x = bridgeX; x < left; x++) {
      grid[midY][x] = WtTile.bridge; // corridor cour (gauche) → bloc
    }
  } else {
    grid[midY][left + w - 1] = WtTile.bridge; // mur droit
    for (var x = left + w; x <= bridgeX; x++) {
      grid[midY][x] = WtTile.bridge; // corridor bloc → cour (droite)
    }
  }

  final decoWalls = _stampGardenWalls(grid, gardenRect, d.lines);

  // ZONE TAMPON le long de la tourelle (côté jardin) : rien de bloquant ne doit y
  // spawn (mur déco compris). 3 colonnes réservées en partant de la tourelle :
  // MUNITIONS (collée à la tourelle) · RAMPE de lancement · case où l'avatar se
  // poste pour tirer. On force donc le garden sur ces cases + au‑dessus/dessous.
  final padDx = mirror ? 1 : -1; // côté jardin de la tourelle
  for (final lane in lanes) {
    final rx = turretX + padDx; // 1ʳᵉ colonne réservée (munitions)
    for (final dy in const [-1, 0, 1]) {
      for (final dx in const [0, 1, 2]) {
        final gx = rx + dx * padDx, gy = lane.y + dy;
        final inGarden = gx >= gardenRect.left &&
            gx < gardenRect.left + _kGardenCols &&
            gy >= it &&
            gy < it + innerRows;
        if (inGarden && grid[gy][gx] == WtTile.wall) {
          grid[gy][gx] = WtTile.garden;
        }
      }
    }
  }

  // PADDING : rangées de calendrier sans routine/activité → pierre + coffre au jardin.
  if (row < it + innerRows) {
    for (var y = row; y < it + innerRows; y++) {
      for (var x = castleRect.left; x < castleRect.left + _kCastleCols; x++) {
        grid[y][x] = WtTile.wall;
      }
    }
    final cy = (row + it + innerRows - 1) ~/ 2;
    final cx = gardenRect.left + _kGardenCols ~/ 2;
    if (grid[cy][cx] == WtTile.garden) grid[cy][cx] = WtTile.chest;
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
    decoWalls: decoWalls,
    mirror: mirror,
  );
}
