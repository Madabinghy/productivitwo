// Bataille de nuisibles — moteur de simulation DÉTERMINISTE.
//
// Principe : aucune tâche serveur (pas de cron). Une partie = un journal
// d'événements de dépôt (append-only). La position de chaque unité à un instant
// donné = nombre de « ticks » (cases) écoulés depuis son dépôt. On rejoue la
// partie tick par tick depuis t=0 pour résoudre collisions, flammes et victoire.
// Les deux clients (et le serveur, qui crédite la victoire) calculent la même
// partie à partir des mêmes events → cohérence garantie, anti-triche sur le score.
//
// Géométrie : grille `lanes` × `width`. Côté 0 part de la case 0 et avance vers
// la droite (case W = camp adverse franchi = victoire). Côté 1 part de W-1 et
// avance vers la gauche (case -1 = franchi). 1 tick = 1 case ; la durée réelle
// d'un tick (minutes) est portée par la partie, pas par le moteur.
//
// Pur Dart : aucune dépendance Flutter/Firebase (testable, mirroir TS côté CF).

/// Un dépôt dans la partie (pièce du journal). `tick` = index entier du tick au
/// moment du dépôt = floor((deployedAt − startAt) / tickMinutes), calculé par
/// l'appelant pour rester déterministe.
class BattleEvent {
  final String id;
  final int side; // 0 (gauche→droite) | 1 (droite→gauche)
  final int lane; // 0..lanes-1
  final String kind; // 'pest' | 'flame'
  final String tier; // 'spider'|'scorpion'|'serpent' (pest) ; '' pour flamme
  final int tick; // tick de dépôt

  const BattleEvent({
    required this.id,
    required this.side,
    required this.lane,
    required this.kind,
    required this.tier,
    required this.tick,
  });

  bool get isFlame => kind == 'flame';
  bool get isArrow => kind == 'arrow';

  static BattleEvent from(Map j) => BattleEvent(
        id: (j['id'] ?? '') as String,
        side: (j['side'] as num?)?.toInt() ?? 0,
        lane: (j['lane'] as num?)?.toInt() ?? 0,
        kind: (j['kind'] ?? 'pest') as String,
        tier: (j['tier'] ?? 'spider') as String,
        tick: (j['tick'] as num?)?.toInt() ?? 0,
      );
}

/// Une partie (config + état). `startAtMs` en millis epoch (null = pas démarrée).
/// Pur : l'appelant convertit le Timestamp Firestore en millis.
class Battle {
  final String id;
  final int width;
  final int lanes;
  final int tickMinutes;
  final String status; // 'waiting' | 'active' | 'finished'
  final List<String> players;
  final Map<String, int> sides; // uid → côté (0|1)
  final Map<String, String> pseudos; // uid → pseudo
  final int? startAtMs;
  final String? winnerUid;
  final int? winTick;

  const Battle({
    required this.id,
    required this.width,
    required this.lanes,
    required this.tickMinutes,
    required this.status,
    required this.players,
    required this.sides,
    required this.pseudos,
    this.startAtMs,
    this.winnerUid,
    this.winTick,
  });

  bool get active => status == 'active';
  bool get finished => status == 'finished';
  int sideOf(String uid) => sides[uid] ?? 0;
  String pseudoOf(String uid) => pseudos[uid] ?? '?';

  /// Tick courant déduit de l'horloge murale (1 tick = `tickMinutes`).
  int nowTick(int nowMs) {
    if (startAtMs == null) return 0;
    final t = (nowMs - startAtMs!) ~/ (tickMinutes * 60000);
    return t < 0 ? 0 : t;
  }

  static Battle from(Map j) => Battle(
        id: (j['id'] ?? '') as String,
        width: (j['width'] as num?)?.toInt() ?? 7,
        lanes: (j['lanes'] as num?)?.toInt() ?? 5,
        tickMinutes: (j['tickMinutes'] as num?)?.toInt() ?? 60,
        status: (j['status'] ?? 'waiting') as String,
        players: ((j['players'] as List?) ?? const []).cast<String>(),
        sides: ((j['sides'] as Map?) ?? const {})
            .map((k, v) => MapEntry(k.toString(), (v as num).toInt())),
        pseudos: ((j['pseudos'] as Map?) ?? const {})
            .map((k, v) => MapEntry(k.toString(), v.toString())),
        startAtMs: (j['startAtMs'] as num?)?.toInt(),
        winnerUid: j['winnerUid'] as String?,
        winTick: (j['winTick'] as num?)?.toInt(),
      );
}

/// Une invasion (tower-defense asymétrique). Pur : `startAtMs` en millis epoch
/// (null = pas encore engagée). La `force` envahisseur (side 0) est figée inline ;
/// les events défenseur (side 1) vivent dans la sous-collection `events`.
class Invasion {
  final String id;
  final String invaderUid;
  final String invaderPseudo;
  final String defenderUid;
  final String defenderPseudo;
  final String redTier; // palier du rouge (plafond) = type de boss
  final int level;
  final String status; // 'pending' | 'active' | 'repelled' | 'held'
  final List<BattleEvent> force; // armée figée side 0 (tick = vague)
  final int forceMasse;
  final int width;
  final int lanes;
  final int tickMinutes;
  final int? startAtMs;
  final String? winner; // 'invader' | 'defender' | null
  final int? winTick;
  final bool revealedToDefender;
  final int? defenderReward;

  const Invasion({
    required this.id,
    required this.invaderUid,
    required this.invaderPseudo,
    required this.defenderUid,
    required this.defenderPseudo,
    required this.redTier,
    required this.level,
    required this.status,
    required this.force,
    required this.forceMasse,
    required this.width,
    required this.lanes,
    required this.tickMinutes,
    this.startAtMs,
    this.winner,
    this.winTick,
    required this.revealedToDefender,
    this.defenderReward,
  });

  bool get pending => status == 'pending';
  bool get active => status == 'active';
  bool get repelled => status == 'repelled';
  bool get held => status == 'held';

  /// Tick courant déduit de l'horloge murale (1 tick = `tickMinutes`).
  int nowTick(int nowMs) {
    if (startAtMs == null) return 0;
    final t = (nowMs - startAtMs!) ~/ (tickMinutes * 60000);
    return t < 0 ? 0 : t;
  }

  /// Identité de l'envahisseur visible par le défenseur (masquée tant que non
  /// révélée = invasion non repoussée).
  String invaderLabelForDefender() =>
      revealedToDefender ? invaderPseudo : '???';

  static Invasion from(Map j) {
    final rawForce = (j['force'] as List?) ?? const [];
    return Invasion(
      id: (j['id'] ?? '') as String,
      invaderUid: (j['invaderUid'] ?? '') as String,
      invaderPseudo: (j['invaderPseudo'] ?? 'Anonyme') as String,
      defenderUid: (j['defenderUid'] ?? '') as String,
      defenderPseudo: (j['defenderPseudo'] ?? 'Anonyme') as String,
      redTier: (j['redTier'] ?? 'spider') as String,
      level: (j['level'] as num?)?.toInt() ?? 1,
      status: (j['status'] ?? 'pending') as String,
      force: rawForce.map((u) {
        final m = u as Map;
        return BattleEvent(
          id: (m['id'] ?? '') as String,
          side: 0,
          lane: (m['lane'] as num?)?.toInt() ?? 0,
          kind: 'pest',
          tier: (m['tier'] ?? 'spider') as String,
          tick: (m['tick'] as num?)?.toInt() ?? 0,
        );
      }).toList(),
      forceMasse: (j['forceMasse'] as num?)?.toInt() ?? 0,
      width: (j['width'] as num?)?.toInt() ?? 7,
      lanes: (j['lanes'] as num?)?.toInt() ?? 5,
      tickMinutes: (j['tickMinutes'] as num?)?.toInt() ?? 60,
      startAtMs: (j['startAtMs'] as num?)?.toInt(),
      winner: j['winner'] as String?,
      winTick: (j['winTick'] as num?)?.toInt(),
      revealedToDefender: (j['revealedToDefender'] as bool?) ?? false,
      defenderReward: (j['defenderReward'] as num?)?.toInt(),
    );
  }
}

/// Unité vivante à l'instant simulé (pour le rendu).
class BattleUnit {
  final String id;
  final int side;
  final int lane;
  final int cell; // position courante (peut sortir [0,width) au franchissement)
  final bool isFlame;
  final String tier;
  const BattleUnit({
    required this.id,
    required this.side,
    required this.lane,
    required this.cell,
    required this.isFlame,
    required this.tier,
  });
}

/// Résultat d'une simulation jusqu'à `nowTick`.
class BattleSimResult {
  final List<BattleUnit> units; // unités vivantes à nowTick (avec position)
  final int? winnerSide; // 0 | 1 | null (en cours)
  final int? winTick; // tick auquel la victoire a été atteinte
  const BattleSimResult({
    required this.units,
    required this.winnerSide,
    required this.winTick,
  });

  bool get finished => winnerSide != null;
}

// État interne mutable d'une unité pendant le replay.
class _U {
  final String id;
  final int side, lane;
  final bool isFlame;
  String tier;
  bool alive = true;
  int cell;
  _U(this.id, this.side, this.lane, this.isFlame, this.tier, this.cell);

  int get dir => side == 0 ? 1 : -1;
}

int _strength(String tier) => switch (tier) {
      'serpent' => 3,
      'scorpion' => 2,
      _ => 1,
    };

String? _tierBelow(String tier) => switch (tier) {
      'serpent' => 'scorpion',
      'scorpion' => 'spider',
      _ => null,
    };

/// Rejoue la partie jusqu'à `nowTick` inclus. `width` = nombre de cases,
/// `lanes` = nombre de couloirs. Retourne les unités vivantes + le vainqueur.
BattleSimResult simulateBattle({
  required List<BattleEvent> events,
  required int width,
  required int lanes,
  required int nowTick,
}) {
  // Camp de départ par côté.
  int camp(int side) => side == 0 ? 0 : width - 1;
  // Case de franchissement atteinte (au-delà du camp adverse).
  bool crossed(_U u) => u.side == 0 ? u.cell >= width : u.cell < 0;

  final byTick = <int, List<BattleEvent>>{};
  for (final e in events) {
    (byTick[e.tick] ??= []).add(e);
  }

  final units = <_U>[];
  int? winnerSide, winTick;

  for (int t = 0; t <= nowTick; t++) {
    // 1) Avancer les unités déjà présentes (spawnTick < t).
    final prev = <String, int>{}; // id → case précédente (détection de croisement)
    for (final u in units) {
      if (!u.alive) continue;
      prev[u.id] = u.cell;
      u.cell += u.dir;
    }
    // 2) Faire apparaître les dépôts de ce tick (au camp, sans avancer).
    final arrivals = byTick[t];
    if (arrivals != null) {
      for (final e in arrivals) {
        final u = _U(e.id, e.side, e.lane, e.isFlame, e.tier, camp(e.side));
        prev[u.id] = u.cell;
        units.add(u);
      }
    }
    // 3) Résoudre collisions/flammes par couloir.
    _resolveLane(units, prev);
    // 4) Victoire : un NUISIBLE (pas une flamme) a franchi le camp adverse.
    int? side0Win, side1Win;
    for (final u in units) {
      if (!u.alive || u.isFlame) continue;
      if (crossed(u)) {
        if (u.side == 0) side0Win = 0;
        if (u.side == 1) side1Win = 1;
      }
    }
    if (side0Win != null || side1Win != null) {
      // Déterministe en cas d'égalité de tick : côté 0 prioritaire.
      winnerSide = side0Win ?? side1Win;
      winTick = t;
      break;
    }
  }

  final view = <BattleUnit>[];
  for (final u in units) {
    if (!u.alive) continue;
    view.add(BattleUnit(
      id: u.id,
      side: u.side,
      lane: u.lane,
      cell: u.cell,
      isFlame: u.isFlame,
      tier: u.tier,
    ));
  }
  return BattleSimResult(units: view, winnerSide: winnerSide, winTick: winTick);
}

// Résout, dans chaque couloir, les rencontres entre unités ADVERSES :
//  - même case courante, OU croisement (elles ont échangé leurs cases) ;
//  - flamme vs nuisible adverse → le nuisible meurt, la flamme survit ;
//  - nuisible vs nuisible → égalité = double mort ; sinon le plus fort survit
//    dégradé d'un cran, le plus faible meurt ;
//  - flamme vs flamme adverse → se traversent (ignorées) ;
//  - jamais de feu ami (les flammes verrouillent leur couloir au dépôt).
void _resolveLane(List<_U> units, Map<String, int> prev) {
  bool meet(_U a, _U b) {
    if (a.cell == b.cell) return true;
    final pa = prev[a.id], pb = prev[b.id];
    if (pa == null || pb == null) return false;
    return pa == b.cell && pb == a.cell; // croisement (échange de cases)
  }

  for (int i = 0; i < units.length; i++) {
    final a = units[i];
    if (!a.alive) continue;
    for (int j = i + 1; j < units.length; j++) {
      final b = units[j];
      if (!b.alive) continue;
      if (a.side == b.side || a.lane != b.lane) continue;
      if (!meet(a, b)) continue;

      if (a.isFlame && b.isFlame) continue; // les feux se traversent
      if (a.isFlame) {
        b.alive = false;
        continue;
      }
      if (b.isFlame) {
        a.alive = false;
        break; // a est mort, plus de rencontre pour lui
      }
      // nuisible vs nuisible
      final sa = _strength(a.tier), sb = _strength(b.tier);
      if (sa == sb) {
        a.alive = false;
        b.alive = false;
        break;
      } else if (sa > sb) {
        b.alive = false;
        final d = _tierBelow(a.tier);
        if (d != null) a.tier = d;
      } else {
        a.alive = false;
        final d = _tierBelow(b.tier);
        if (d != null) b.tier = d;
        break;
      }
    }
  }
}

// ── Invasion : tower-defense ASYMÉTRIQUE (mode « Territoires ») ───────────────
// Réutilise le même moteur de réplay déterministe, mais asymétrique :
//   • Envahisseur = side 0 : sa force est FIGÉE (events au tick 0), elle avance vers
//     la droite et FRANCHIT à cell ≥ width (= territoire tenu).
//   • Défenseur = side 1 : joue en direct sur les ticks. Il dépose des nuisibles
//     BLOQUEURS (`kind:'pest'`, avancent vers la gauche, mêlée normale) et tire des
//     FLÈCHES (`kind:'arrow'`, à distance).
//   • Le défenseur gagne UNIQUEMENT en éliminant TOUTE la force envahisseur ; le
//     franchissement côté défenseur ne gagne PAS (c'est l'asymétrie).
// Flèche = dégrade d'un cran (serpent→scorpion→spider→mort) le nuisible envahisseur
// le plus avancé de la lane visée. Moteur PUR, mirroir TS exact côté Cloud Function.

/// Un nuisible tombé au combat (pour le feed des pertes). `cause` = 'arrow'
/// (achevé par une flèche) ou 'melee' (achevé par un nuisible adverse). `tier`
/// = le palier au moment de la mort.
class BattleCasualty {
  final String id;
  final int side; // 0 = envahisseur · 1 = défenseur
  final String tier;
  final String cause; // 'arrow' | 'melee'
  final int tick;
  final int lane;
  const BattleCasualty({
    required this.id,
    required this.side,
    required this.tier,
    required this.cause,
    required this.tick,
    required this.lane,
  });
}

/// Résultat d'une simulation d'invasion jusqu'à `nowTick`.
class InvasionSimResult {
  final List<BattleUnit> units; // unités vivantes à nowTick (rendu)
  final List<BattleCasualty> casualties; // morts cumulés (ordre chronologique)
  final String? winner; // 'invader' | 'defender' | null (en cours)
  final int? winTick;
  const InvasionSimResult({
    required this.units,
    required this.casualties,
    required this.winner,
    required this.winTick,
  });

  bool get finished => winner != null;
}

/// Rejoue une invasion jusqu'à `nowTick` inclus.
///
/// Ordre intra-tick (à RÉPLIQUER À L'IDENTIQUE côté TypeScript, sinon le client et le
/// serveur divergent) : 1) avancer · 2) spawns du tick · 3) appliquer les flèches
/// (triées par id pour un ordre stable) · 4) mêlée par couloir · 5) test de victoire
/// (franchissement envahisseur prioritaire, puis élimination totale).
InvasionSimResult simulateInvasion({
  required List<BattleEvent> events,
  required int width,
  required int lanes,
  required int nowTick,
}) {
  int camp(int side) => side == 0 ? 0 : width - 1;

  final byTick = <int, List<BattleEvent>>{};
  for (final e in events) {
    (byTick[e.tick] ??= []).add(e);
  }

  final units = <_U>[];
  final casualties = <BattleCasualty>[];
  bool anyInvader = false;
  String? winner;
  int? winTick;

  for (int t = 0; t <= nowTick; t++) {
    // 1) Avancer les unités déjà présentes.
    final prev = <String, int>{};
    for (final u in units) {
      if (!u.alive) continue;
      prev[u.id] = u.cell;
      u.cell += u.dir;
    }
    // 2) Spawns du tick : pests/flammes → unités ; flèches mises de côté.
    final arrows = <BattleEvent>[];
    final arrivals = byTick[t];
    if (arrivals != null) {
      for (final e in arrivals) {
        if (e.isArrow) {
          arrows.add(e);
          continue;
        }
        final u = _U(e.id, e.side, e.lane, e.isFlame, e.tier, camp(e.side));
        prev[u.id] = u.cell;
        units.add(u);
        if (e.side == 0 && !e.isFlame) anyInvader = true;
      }
    }
    // 3) Flèches (ordre stable par id) : chacune dégrade l'envahisseur le plus avancé.
    arrows.sort((a, b) => a.id.compareTo(b.id));
    for (final a in arrows) {
      final killed = _applyArrow(units, a.lane);
      if (killed != null) {
        casualties.add(BattleCasualty(
            id: killed.id,
            side: killed.side,
            tier: killed.tier,
            cause: 'arrow',
            tick: t,
            lane: killed.lane));
      }
    }
    // 4) Mêlée par couloir (logique identique à la bataille). On diffe l'état
    //    vivant avant/après pour attribuer la cause 'melee' aux nouveaux morts.
    final aliveBefore = <String>{for (final u in units) if (u.alive) u.id};
    _resolveLane(units, prev);
    for (final u in units) {
      if (!u.alive && aliveBefore.contains(u.id)) {
        casualties.add(BattleCasualty(
            id: u.id,
            side: u.side,
            tier: u.tier,
            cause: 'melee',
            tick: t,
            lane: u.lane));
      }
    }
    // 5a) Victoire envahisseur : un de ses nuisibles a franchi le camp défenseur.
    bool invaderCrossed = false;
    for (final u in units) {
      if (!u.alive || u.isFlame) continue;
      if (u.side == 0 && u.cell >= width) {
        invaderCrossed = true;
        break;
      }
    }
    if (invaderCrossed) {
      winner = 'invader';
      winTick = t;
      break;
    }
    // 5b) Victoire défenseur : toute la force envahisseur est éliminée.
    if (anyInvader) {
      final invadersAlive =
          units.any((u) => u.alive && !u.isFlame && u.side == 0);
      if (!invadersAlive) {
        winner = 'defender';
        winTick = t;
        break;
      }
    }
  }

  final view = <BattleUnit>[];
  for (final u in units) {
    if (!u.alive) continue;
    view.add(BattleUnit(
      id: u.id,
      side: u.side,
      lane: u.lane,
      cell: u.cell,
      isFlame: u.isFlame,
      tier: u.tier,
    ));
  }
  return InvasionSimResult(
      units: view, casualties: casualties, winner: winner, winTick: winTick);
}

// Dégrade d'un cran le nuisible ENVAHISSEUR (side 0) le plus avancé vivant de `lane`
// (cell max ; égalité → id le plus petit). Spider → mort. Retourne l'unité TUÉE
// (spider achevé), ou null si simple dégradation / lane vide.
_U? _applyArrow(List<_U> units, int lane) {
  _U? best;
  for (final u in units) {
    if (!u.alive || u.isFlame || u.side != 0 || u.lane != lane) continue;
    if (best == null) {
      best = u;
      continue;
    }
    if (u.cell > best.cell || (u.cell == best.cell && u.id.compareTo(best.id) < 0)) {
      best = u;
    }
  }
  if (best == null) return null;
  final d = _tierBelow(best.tier);
  if (d == null) {
    best.alive = false;
    return best;
  }
  best.tier = d;
  return null;
}
