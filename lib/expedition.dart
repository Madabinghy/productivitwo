import 'dart:math';

/// Expédition = la mini-carte sinueuse 2D qu'on traverse pour révéler/débloquer
/// le prochain niveau. PUR (aucune dépendance Flutter) : généré de façon
/// DÉTERMINISTE à partir du numéro de niveau (même niveau ⇒ même carte au reload),
/// re-skinné/rallongé selon le niveau. Pas de moteur de jeu : juste un graphe de
/// nœuds (row, lane) + des arêtes, dessiné côté widget.

enum ExpNodeType { start, step, rock, gate, hole, bonus, finish }

/// Outil (consommable boutique) requis pour franchir un nœud. null = gratuit
/// (départ, bonus, arrivée).
String? toolForType(ExpNodeType t) {
  switch (t) {
    case ExpNodeType.step:
      return 'pas';
    case ExpNodeType.rock:
      return 'pioche';
    case ExpNodeType.gate:
      return 'cle';
    case ExpNodeType.hole:
      return 'pelle';
    case ExpNodeType.start:
    case ExpNodeType.bonus:
    case ExpNodeType.finish:
      return null;
  }
}

class ExpeditionNode {
  final String id;
  final int row; // position verticale (0 = départ, en haut)
  final int lane; // colonne (0..lanes-1)
  final ExpNodeType type;
  final List<String> next; // ids des nœuds suivants (peut brancher)
  final int bonusGold; // or crédité en atteignant un nœud bonus
  ExpeditionNode({
    required this.id,
    required this.row,
    required this.lane,
    required this.type,
    required this.next,
    this.bonusGold = 0,
  });
}

class Expedition {
  final int level;
  final List<ExpeditionNode> nodes;
  final int lanes;
  final int rows;
  Expedition({
    required this.level,
    required this.nodes,
    required this.lanes,
    required this.rows,
  });

  ExpeditionNode get start => nodes.first;
  ExpeditionNode byId(String id) => nodes.firstWhere((n) => n.id == id);

  /// Nœuds atteignables = non franchis mais ayant un prédécesseur franchi.
  /// [cleared] inclut implicitement le départ.
  Set<String> reachable(Set<String> cleared) {
    final eff = {start.id, ...cleared};
    final out = <String>{};
    for (final n in nodes) {
      if (eff.contains(n.id)) continue;
      for (final src in nodes) {
        if (eff.contains(src.id) && src.next.contains(n.id)) {
          out.add(n.id);
          break;
        }
      }
    }
    return out;
  }

  bool isComplete(Set<String> cleared) =>
      cleared.contains(nodes.lastWhere((n) => n.type == ExpNodeType.finish).id);
}

/// Génère l'expédition d'un niveau (déterministe via seed = level).
/// Chaîne de segments : linéaires (1 nœud) ou forks (vrai choix de route :
/// route courte 1 obstacle cher ⟷ route longue 2 pas bon marché), puis arrivée.
/// Plus le niveau monte : plus de segments (traversée plus longue).
Expedition generateExpedition(int level) {
  final rng = Random(level * 1000003 + 7);
  const lanes = 3;
  const center = 1;
  final nodes = <ExpeditionNode>[];
  var row = 0;
  var idc = 0;
  String nid() => 'n${idc++}';

  final start = ExpeditionNode(
      id: nid(), row: row, lane: center, type: ExpNodeType.start, next: []);
  nodes.add(start);
  var prev = start;

  final segCount = (2 + level ~/ 2).clamp(2, 8);
  for (var s = 0; s < segCount; s++) {
    final fork = rng.nextBool();
    if (!fork) {
      row++;
      final n = ExpeditionNode(
          id: nid(), row: row, lane: center, type: ExpNodeType.step, next: []);
      prev.next.add(n.id);
      nodes.add(n);
      // Embranchement bonus optionnel (cul-de-sac récompense).
      if (rng.nextInt(3) == 0) {
        final b = ExpeditionNode(
            id: nid(),
            row: row,
            lane: rng.nextBool() ? 0 : 2,
            type: ExpNodeType.bonus,
            next: [],
            bonusGold: 5 + rng.nextInt(6));
        n.next.add(b.id);
        nodes.add(b);
      }
      prev = n;
    } else {
      final entry = prev;
      row++;
      final obs = [ExpNodeType.rock, ExpNodeType.gate, ExpNodeType.hole][
          rng.nextInt(3)];
      // Route courte (droite) : 1 obstacle.
      final a = ExpeditionNode(
          id: nid(), row: row, lane: 2, type: obs, next: []);
      // Route longue (gauche) : 2 pas.
      final b1 = ExpeditionNode(
          id: nid(), row: row, lane: 0, type: ExpNodeType.step, next: []);
      row++;
      final b2 = ExpeditionNode(
          id: nid(), row: row, lane: 0, type: ExpNodeType.step, next: []);
      final merge = ExpeditionNode(
          id: nid(), row: row, lane: center, type: ExpNodeType.step, next: []);
      entry.next.addAll([a.id, b1.id]);
      a.next.add(merge.id);
      b1.next.add(b2.id);
      b2.next.add(merge.id);
      nodes.addAll([a, b1, b2, merge]);
      prev = merge;
    }
  }

  row++;
  final finish = ExpeditionNode(
      id: nid(), row: row, lane: center, type: ExpNodeType.finish, next: []);
  prev.next.add(finish.id);
  nodes.add(finish);

  return Expedition(
      level: level, nodes: nodes, lanes: lanes, rows: row + 1);
}

/// Biome (skin) du niveau — purement cosmétique, varie selon le niveau.
({String emoji, String label}) expeditionBiome(int level) {
  const biomes = [
    (emoji: '🌲', label: 'Forêt'),
    (emoji: '🏜️', label: 'Désert'),
    (emoji: '🏔️', label: 'Montagne'),
    (emoji: '🌊', label: 'Côte'),
    (emoji: '🌋', label: 'Volcan'),
    (emoji: '❄️', label: 'Toundra'),
    (emoji: '🏝️', label: 'Île'),
    (emoji: '🕳️', label: 'Caverne'),
  ];
  return biomes[level % biomes.length];
}
