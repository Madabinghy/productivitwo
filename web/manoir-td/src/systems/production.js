// Bâtiments producteurs : fabrication d'unités À LA DEMANDE (coût en masse immédiat).
// Le bâtiment (Atelier, puis Caserne) est posé/bâti comme une tourelle (cat:'turret',
// support), puis on le sélectionne et on clique un produit → trainUnit() dépense la masse
// et fait apparaître l'unité (cat:'unit', déjà bâtie) sur une case libre à côté.
import { GRID, MAP, costOf, unitStats, TRAIN_CD } from '../config.js';
import { blocked } from '../geometry.js';

// Décrémente le cooldown de fabrication de chaque bâtiment (appelé dans la boucle tick).
export function updateProduction(game, dt) {
  for (const p of game.ui.placed) {
    if (p.cat === 'turret' && p._trainCd > 0) p._trainCd = Math.max(0, p._trainCd - dt);
  }
}

// Cherche une case libre (grille) autour du bâtiment pour y déposer l'unité produite.
function freeSpotNear(game, x, y) {
  const dirs = [[1, 0], [-1, 0], [0, 1], [0, -1], [1, 1], [-1, 1], [1, -1], [-1, -1]];
  for (let r = 1; r <= 5; r++) {
    for (const [dx, dy] of dirs) {
      const nx = x + dx * GRID * r, ny = y + dy * GRID * r;
      if (nx < 60 || ny < 60 || nx > MAP.W - 60 || ny > MAP.H - 60) continue;
      if (blocked(game.WALLS, x, y, nx, ny)) continue;                       // séparé par un mur
      if (game.ui.placed.some(o => Math.hypot(o.x - nx, o.y - ny) < GRID * 0.6)) continue; // occupé
      return { x: nx, y: ny };
    }
  }
  return { x: x + GRID, y: y + GRID };
}

// Fabrique une unité depuis un bâtiment (à la demande). Refuse si cooldown ou masse insuffisante.
export function trainUnit(game, producer, unitKey) {
  const s = game.ui, st = unitStats(unitKey);
  if (!producer || producer.built === false || !st) return;
  if ((producer._trainCd || 0) > 0) { s.msg = 'Atelier occupé — patiente un instant.'; return; }
  const cost = costOf(unitKey).mass;
  if (game.G.mass < cost) { s.msg = 'Pas assez de masse (' + Math.round(game.G.mass) + '/' + cost + ' ✦).'; return; }
  game.G.mass -= cost;
  producer._trainCd = TRAIN_CD;
  const spot = freeSpotNear(game, producer.x, producer.y);
  s.placed.push({
    id: game.G.nextId++, cat: 'unit', key: unitKey, x: spot.x, y: spot.y, face: producer.face || 0,
    level: 1, bonusR: 0, bonusD: 0, maxHp: st.hp, hp: st.hp,
    built: true, prog: 1, deployed: false, moveTarget: null,
    aim: producer.face || 0, bodyDir: producer.face || 0, fireCd: 0, firing: 0,
  });
  s.msg = '⚙ ' + (st.name || unitKey) + ' fabriqué — clique-le pour l\'envoyer au combat.';
}
