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
  /// id = id du DOMAINE de vie que cette grotte incarne (la map = miroir de
  /// l'équilibre des domaines). Docs legacy : 'nw'|'ne'|'sw'|'se' (migrés au load).
  final String id;
  final int x, y;
  final String ownerUid;
  final int blueLevel;
  final bool occupied;
  // Domaine de vie incarné par la grotte (= id, conservé explicite pour la
  // lisibilité et la rétro-compat des docs legacy positionnels). Vide = legacy.
  final String domainId;

  const TerritoryCave({
    required this.id,
    required this.x,
    required this.y,
    required this.ownerUid,
    required this.blueLevel,
    required this.occupied,
    this.domainId = '',
  });

  TerritoryCave copyWith(
          {String? ownerUid, int? blueLevel, bool? occupied, String? domainId}) =>
      TerritoryCave(
        id: id,
        x: x,
        y: y,
        ownerUid: ownerUid ?? this.ownerUid,
        blueLevel: blueLevel ?? this.blueLevel,
        occupied: occupied ?? this.occupied,
        domainId: domainId ?? this.domainId,
      );

  static TerritoryCave from(Map j) => TerritoryCave(
        id: (j['id'] ?? '') as String,
        x: (j['x'] as num?)?.toInt() ?? 0,
        y: (j['y'] as num?)?.toInt() ?? 0,
        ownerUid: (j['ownerUid'] ?? '') as String,
        blueLevel: (j['blueLevel'] as num?)?.toInt() ?? 1,
        occupied: (j['occupied'] as bool?) ?? false,
        domainId: (j['domainId'] ?? '') as String,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'x': x,
        'y': y,
        'ownerUid': ownerUid,
        'blueLevel': blueLevel,
        'occupied': occupied,
        'domainId': domainId,
      };
}

/// L'envahisseur courant sur une map (1 seul à la fois). En solo = le bot 🟡.
/// Marche tick par tick vers `targetCaveId` ; sa FORCE (charge verte) n'est pas
/// stockée en clair — seul son `level` l'est (révélé au combat = brouillard de
/// force). `lastStepAtMs` cadence l'avancée (rapide en test, 1h en prod).
class Invader {
  final String attackerUid; // 'bot' en solo
  final String color; // 'yellow' (bot) | 'red' (joueur)
  final int level; // force → buildInvaderForce au combat
  final int x, y;
  final String targetCaveId;
  final String state; // 'marching' | 'at_cave' | 'installed' | 'resolved'
  final int lastStepAtMs;
  // Horodatage du spawn (figé, jamais ré-écrit par advanceInvader). Permet à la
  // map UNIFIÉE de dériver la position de l'araignée du temps écoulé le long de
  // SON propre chemin (géométrie ≠ 9×9) sans corrompre x/y du substrat territoire.
  final int spawnAtMs;

  const Invader({
    required this.attackerUid,
    required this.color,
    required this.level,
    required this.x,
    required this.y,
    required this.targetCaveId,
    required this.state,
    required this.lastStepAtMs,
    this.spawnAtMs = 0,
  });

  bool get marching => state == 'marching';
  bool get atCave => state == 'at_cave';

  Invader copyWith(
          {int? x, int? y, String? state, int? lastStepAtMs, int? spawnAtMs}) =>
      Invader(
        attackerUid: attackerUid,
        color: color,
        level: level,
        x: x ?? this.x,
        y: y ?? this.y,
        targetCaveId: targetCaveId,
        state: state ?? this.state,
        lastStepAtMs: lastStepAtMs ?? this.lastStepAtMs,
        spawnAtMs: spawnAtMs ?? this.spawnAtMs,
      );

  static Invader? from(Map? j) {
    if (j == null) return null;
    final last = (j['lastStepAtMs'] as num?)?.toInt() ?? 0;
    return Invader(
      attackerUid: (j['attackerUid'] ?? 'bot') as String,
      color: (j['color'] ?? 'yellow') as String,
      level: (j['level'] as num?)?.toInt() ?? 1,
      x: (j['x'] as num?)?.toInt() ?? 0,
      y: (j['y'] as num?)?.toInt() ?? 0,
      targetCaveId: (j['targetCaveId'] ?? '') as String,
      state: (j['state'] ?? 'marching') as String,
      lastStepAtMs: last,
      // Rétro-compat : docs sans spawnAtMs → on retombe sur lastStepAtMs.
      spawnAtMs: (j['spawnAtMs'] as num?)?.toInt() ?? last,
    );
  }

  Map<String, dynamic> toJson() => {
        'attackerUid': attackerUid,
        'color': color,
        'level': level,
        'x': x,
        'y': y,
        'targetCaveId': targetCaveId,
        'state': state,
        'lastStepAtMs': lastStepAtMs,
        'spawnAtMs': spawnAtMs,
      };
}

class Territory {
  final String uid, pseudo;
  final int seed, cols, rows;
  final Point<int> castle;
  final bool fog;
  final List<TerritoryCave> caves;
  final Invader? invader;
  final bool mapTaken; // château tombé (4 grottes prises puis château) → défaite
  // Lundi (YYYY-MM-DD) de la dernière semaine où l'auto-trigger de menace a été
  // évalué → idempotence : un seul spawn hebdo de bot scalé sur la chute de score.
  final String lastThreatWeek;

  const Territory({
    required this.uid,
    required this.pseudo,
    required this.seed,
    required this.cols,
    required this.rows,
    required this.castle,
    required this.fog,
    required this.caves,
    this.invader,
    this.mapTaken = false,
    this.lastThreatWeek = '',
  });

  /// Niveau de map = Σ des niveaux des grottes que JE possède (= rang ladder à
  /// venir). Une grotte prise par un envahisseur ne compte plus → ton niveau baisse.
  int get level =>
      caves.where((c) => c.ownerUid == uid).fold(0, (s, c) => s + c.blueLevel);

  /// Combien de grottes je possède encore.
  int ownedCount(String me) => caves.where((c) => c.ownerUid == me).length;

  TerritoryCave? caveById(String id) {
    for (final c in caves) {
      if (c.id == id) return c;
    }
    return null;
  }

  Territory copyWith({
    bool? fog,
    List<TerritoryCave>? caves,
    int? seed,
    Invader? invader,
    bool clearInvader = false,
    bool? mapTaken,
    String? lastThreatWeek,
  }) =>
      Territory(
        uid: uid,
        pseudo: pseudo,
        seed: seed ?? this.seed,
        cols: cols,
        rows: rows,
        castle: castle,
        fog: fog ?? this.fog,
        caves: caves ?? this.caves,
        invader: clearInvader ? null : (invader ?? this.invader),
        mapTaken: mapTaken ?? this.mapTaken,
        lastThreatWeek: lastThreatWeek ?? this.lastThreatWeek,
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
      invader: Invader.from(j['invader'] as Map?),
      mapTaken: (j['mapTaken'] as bool?) ?? false,
      lastThreatWeek: (j['lastThreatWeek'] ?? '') as String,
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
        'invader': invader?.toJson(),
        'mapTaken': mapTaken,
        'lastThreatWeek': lastThreatWeek,
      };
}

/// Territoire initial d'un user : 9×9, château au centre, **une grotte par
/// domaine de vie** (la map = miroir de l'équilibre des domaines), toutes
/// possédées (niveau 1), brouillard actif. Seed déterministe depuis l'uid.
/// `domainIds` vide (legacy/inconnu) → retombe sur les 4 coins historiques.
Territory initialTerritory(String uid, String pseudo,
    {int? seed, List<String> domainIds = const []}) {
  const cols = 9, rows = 9;
  final s = seed ?? (uid.hashCode & 0x7fffffff);
  final ids = domainIds.isEmpty ? const ['nw', 'ne', 'sw', 'se'] : domainIds;
  final pts = perimeterSlots(cols, rows, ids.length);
  final caves = <TerritoryCave>[
    for (int i = 0; i < ids.length; i++)
      TerritoryCave(
        id: ids[i],
        x: pts[i].x,
        y: pts[i].y,
        ownerUid: uid,
        blueLevel: 1,
        occupied: false,
        domainId: domainIds.isEmpty ? '' : ids[i],
      ),
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

/// `n` positions distinctes réparties sur le périmètre d'une grille cols×rows
/// (coins d'abord, puis milieux d'arêtes). Positions vestigiales pour la
/// god-view 9×9 retirée ; la géométrie jouée vient de `generateUnifiedWorld`.
List<Point<int>> perimeterSlots(int cols, int rows, int n) {
  final ring = <Point<int>>[];
  for (int x = 0; x < cols; x++) ring.add(Point(x, 0));
  for (int y = 1; y < rows; y++) ring.add(Point(cols - 1, y));
  for (int x = cols - 2; x >= 0; x--) ring.add(Point(x, rows - 1));
  for (int y = rows - 2; y >= 1; y--) ring.add(Point(0, y));
  if (n <= 0) return const [];
  final out = <Point<int>>[];
  for (int i = 0; i < n; i++) {
    out.add(ring[((i * ring.length) ~/ n) % ring.length]);
  }
  return out;
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

// ── Envahisseur : spawn + marche (purs ; l'appelant fournit l'horloge nowMs) ──

/// La grotte la + faible que JE possède (cible de l'envahisseur). Tie-break id.
TerritoryCave? weakestOwnedCave(Territory t, String me) {
  TerritoryCave? best;
  for (final c in t.caves) {
    if (c.ownerUid != me) continue;
    if (best == null ||
        c.blueLevel < best.blueLevel ||
        (c.blueLevel == best.blueLevel && c.id.compareTo(best.id) < 0)) {
      best = c;
    }
  }
  return best;
}

/// Fait apparaître le bot 🟡 au bord (haut-centre), ciblant ta grotte la + faible.
/// Brouillard levé. Sa MENACE = `botLevel` (DÉCORRÉLÉE du niveau de ta grotte :
/// une grotte non défendue tombe si menace > son niveau ; la monter au-dessus de
/// la menace la protège passivement). Caché → révélé au combat. En prod, `botLevel`
/// scalera sur l'ampleur de la chute de score hebdo. null-safe si plus de grotte.
Territory spawnBotInvader(Territory t, String me, int nowMs, {int botLevel = 2}) {
  final target = weakestOwnedCave(t, me);
  // Plus de grotte possédée → le bot vise le CHÂTEAU (targetCaveId='castle'). Si la
  // map est déjà prise, rien à faire.
  final String targetId;
  if (target != null) {
    targetId = target.id;
  } else if (!t.mapTaken) {
    targetId = 'castle';
  } else {
    return t;
  }
  final inv = Invader(
    attackerUid: 'bot',
    color: 'yellow',
    level: botLevel,
    x: t.cols ~/ 2,
    y: 0,
    targetCaveId: targetId,
    state: 'marching',
    lastStepAtMs: nowMs,
    spawnAtMs: nowMs,
  );
  return t.copyWith(invader: inv, fog: false);
}

/// Avance l'envahisseur des pas DUS depuis `lastStepAtMs` (cadence `stepMs`) ; un
/// pas = une case vers la grotte cible (Manhattan, ignore les murs — la friction
/// des murs est pour TOI, pas pour le maraudeur). Arrivé → state 'at_cave'.
/// Retourne (territoire, a-bougé). Pur.
({Territory t, bool moved}) advanceInvader(Territory t, int nowMs, int stepMs) {
  final inv = t.invader;
  if (inv == null || !inv.marching) return (t: t, moved: false);
  // Cible = une grotte, ou le château ('castle').
  final int tx, ty;
  if (inv.targetCaveId == 'castle') {
    tx = t.castle.x;
    ty = t.castle.y;
  } else {
    final cave = t.caveById(inv.targetCaveId);
    if (cave == null) return (t: t, moved: false);
    tx = cave.x;
    ty = cave.y;
  }
  var due = (nowMs - inv.lastStepAtMs) ~/ stepMs;
  if (due <= 0) return (t: t, moved: false);
  var x = inv.x, y = inv.y, steps = 0;
  while (due > 0 && (x != tx || y != ty)) {
    final dx = tx - x, dy = ty - y;
    if (dx != 0 && (dy == 0 || dx.abs() >= dy.abs())) {
      x += dx > 0 ? 1 : -1;
    } else {
      y += dy > 0 ? 1 : -1;
    }
    due--;
    steps++;
  }
  if (steps == 0) return (t: t, moved: false);
  final arrived = x == tx && y == ty;
  return (
    t: t.copyWith(
        invader: inv.copyWith(
            x: x,
            y: y,
            state: arrived ? 'at_cave' : 'marching',
            lastStepAtMs: inv.lastStepAtMs + steps * stepMs)),
    moved: true
  );
}
