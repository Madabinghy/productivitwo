// Système tourelles — étoffé à l'étape 5. Pour l'instant : dégât d'un tir ennemi sur une
// tourelle (avec interception par bouclier), et points d'entrée no-op pour le reste.
import { baseHp } from '../config.js';

// Un tir ennemi (e) touche une tourelle (tgt). Renvoie l'id détruit ou null.
export function hitTurret(game, e, tgt) {
  // (l'interception par bouclier sera ajoutée avec les boucliers à l'étape 5)
  const hitT = tgt;
  if (hitT.hp == null) { const mh = baseHp(hitT.key); hitT.hp = mh; hitT.maxHp = mh; }
  hitT.hp -= 7;
  game.G.beams.push({ x1: e.x, y1: e.y, x2: hitT.x, y2: hitT.y, color: '#ff5d7a', life: 0.12, maxLife: 0.12, seg: true });
  return hitT.hp <= 0 ? hitT.id : null;
}

export function updateTurrets(_game, _dt) { /* étape 5 */ }
