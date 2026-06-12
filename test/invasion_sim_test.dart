// Tests du moteur d'invasion (tower-defense asymétrique) — `simulateInvasion`.
// Vérifie : franchissement envahisseur, élimination par flèches (dégradation),
// flèche sur lane vide (no-op), ciblage du plus avancé, mêlée bloqueur, asymétrie
// (le franchissement défenseur ne gagne pas), et déterminisme (ordre des events).
import 'package:flutter_test/flutter_test.dart';
import 'package:productivitwo_v1/battle_sim.dart';

BattleEvent ev(String id, int side, int lane, String kind, String tier, int tick) =>
    BattleEvent(id: id, side: side, lane: lane, kind: kind, tier: tier, tick: tick);

// Raccourcis lisibles.
BattleEvent pest(String id, int side, int lane, String tier, int tick) =>
    ev(id, side, lane, 'pest', tier, tick);
BattleEvent arrow(String id, int lane, int tick) =>
    ev(id, 1, lane, 'arrow', '', tick);

void main() {
  const w = 7, lanes = 5;

  test('boss seul, aucune défense → envahisseur franchit à tick=width', () {
    final r = simulateInvasion(
      events: [pest('boss', 0, 0, 'serpent', 0)],
      width: w,
      lanes: lanes,
      nowTick: 12,
    );
    expect(r.winner, 'invader');
    expect(r.winTick, w); // cell passe de 0 (tick0) à 7 (tick7)
  });

  test('serpent boss vs 3 flèches → défenseur élimine la force', () {
    final r = simulateInvasion(
      events: [
        pest('boss', 0, 0, 'serpent', 0),
        arrow('a1', 0, 1), // serpent → scorpion
        arrow('a2', 0, 2), // scorpion → spider
        arrow('a3', 0, 3), // spider → mort
      ],
      width: w,
      lanes: lanes,
      nowTick: 12,
    );
    expect(r.winner, 'defender');
    expect(r.winTick, 3);
    expect(r.units, isEmpty);
  });

  test('flèches insuffisantes (serpent + 1 flèche) → envahisseur tient', () {
    final r = simulateInvasion(
      events: [
        pest('boss', 0, 0, 'serpent', 0),
        arrow('a1', 0, 1), // serpent → scorpion, mais continue d'avancer
      ],
      width: w,
      lanes: lanes,
      nowTick: 12,
    );
    expect(r.winner, 'invader');
    expect(r.winTick, w);
  });

  test('flèche sur lane vide = no-op (le boss franchit quand même)', () {
    final r = simulateInvasion(
      events: [
        pest('boss', 0, 0, 'spider', 0),
        arrow('a1', 3, 1), // lane 3 : aucun envahisseur
      ],
      width: w,
      lanes: lanes,
      nowTick: 12,
    );
    expect(r.winner, 'invader');
  });

  test('la flèche cible le nuisible le plus avancé de la lane', () {
    // A devant (tick0), B derrière (spawn tick2). À tick3 : A cell3, B cell1.
    // La flèche de tick3 doit tuer A (cell3), laisser B vivant.
    final r = simulateInvasion(
      events: [
        pest('A', 0, 0, 'spider', 0),
        pest('B', 0, 0, 'spider', 2),
        arrow('a1', 0, 3),
      ],
      width: w,
      lanes: lanes,
      nowTick: 3,
    );
    expect(r.winner, isNull); // B survit, partie en cours
    final alive = r.units.where((u) => u.side == 0).toList();
    expect(alive.length, 1);
    expect(alive.first.id, 'B');
    expect(alive.first.cell, 1);
  });

  test('bloqueur défenseur intercepte un envahisseur (mêlée égale = double mort)', () {
    // Spider envahisseur lane0 (cell0→) ; spider bloqueur lane0 (cell6←).
    // Se croisent à mi-chemin → double mort → force éliminée → défenseur gagne.
    final r = simulateInvasion(
      events: [
        pest('inv', 0, 0, 'spider', 0),
        pest('blk', 1, 0, 'spider', 0),
      ],
      width: w,
      lanes: lanes,
      nowTick: 12,
    );
    expect(r.winner, 'defender');
  });

  test('asymétrie : le franchissement défenseur ne gagne PAS', () {
    // Lanes séparées, aucun obstacle : les deux franchissent au même tick=width.
    // La priorité va à l'envahisseur → prouve que la traversée défenseur est ignorée.
    final r = simulateInvasion(
      events: [
        pest('inv', 0, 0, 'spider', 0),
        pest('def', 1, 1, 'spider', 0),
      ],
      width: w,
      lanes: lanes,
      nowTick: 12,
    );
    expect(r.winner, 'invader');
    expect(r.winTick, w);
  });

  test('déterminisme : l\'ordre des events n\'affecte pas le résultat', () {
    final events = [
      pest('boss', 0, 2, 'serpent', 0),
      pest('r1', 0, 0, 'scorpion', 0),
      pest('blk', 1, 2, 'spider', 1),
      arrow('a1', 2, 1),
      arrow('a2', 2, 2),
      arrow('a3', 0, 1),
      arrow('a4', 0, 2),
    ];
    final r1 = simulateInvasion(
        events: events, width: w, lanes: lanes, nowTick: 20);
    final r2 = simulateInvasion(
        events: events.reversed.toList(), width: w, lanes: lanes, nowTick: 20);
    expect(r1.winner, r2.winner);
    expect(r1.winTick, r2.winTick);
  });

  test('feed des pertes : cause arrow vs melee, des deux côtés', () {
    // Serpent achevé par flèches (lane 0) ; sur lane 1, un envahisseur spider et
    // un bloqueur spider se croisent → double mort en mêlée.
    final r = simulateInvasion(
      events: [
        pest('boss', 0, 0, 'serpent', 0),
        arrow('a1', 0, 1),
        arrow('a2', 0, 2),
        arrow('a3', 0, 3),
        pest('inv1', 0, 1, 'spider', 0),
        pest('blk', 1, 1, 'spider', 0),
      ],
      width: w,
      lanes: lanes,
      nowTick: 12,
    );
    expect(r.winner, 'defender');
    final byArrow = r.casualties.where((c) => c.cause == 'arrow').toList();
    final byMelee = r.casualties.where((c) => c.cause == 'melee').toList();
    expect(byArrow.length, 1); // le serpent achevé à la 3e flèche
    expect(byArrow.first.id, 'boss');
    expect(byArrow.first.side, 0);
    // Mêlée : l'envahisseur spider ET le bloqueur tombent (double mort).
    expect(byMelee.any((c) => c.id == 'inv1' && c.side == 0), isTrue);
    expect(byMelee.any((c) => c.id == 'blk' && c.side == 1), isTrue);
  });

  test('partie en cours → winner null avant résolution', () {
    final r = simulateInvasion(
      events: [pest('boss', 0, 0, 'serpent', 0)],
      width: w,
      lanes: lanes,
      nowTick: 3, // boss encore en cell 3 < 7
    );
    expect(r.winner, isNull);
    expect(r.units.length, 1);
  });
}
