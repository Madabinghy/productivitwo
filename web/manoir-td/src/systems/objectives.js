// Objectifs & conditions de fin : allumage des bougies, conquête de salle, victoire,
// coffre forcé / Commander tombé, rapport de données « fuitées », reprise.
import { COFFRE, COFFRE_BREACH } from '../config.js';
import { spawnEnemies } from './enemies.js';

const DOMAINS = ['Cybersécurité', 'Finance', 'Marketing digital', 'Développement web', 'Design UX',
  'Data science', 'Langues', 'Droit des affaires', 'Comptabilité', 'Gestion de projet',
  'Intelligence artificielle', 'Photographie'];

export function makeReport() {
  const hex = '0123456789ABCDEF'; let id = '#'; for (let i = 0; i < 4; i++) id += hex[Math.floor(Math.random() * 16)];
  return { id, domain: DOMAINS[Math.floor(Math.random() * DOMAINS.length)], level: 2 + Math.floor(Math.random() * 58), pct: 30 + Math.floor(Math.random() * 70) };
}

export function updateObjectives(game) {
  const G = game.G, H = game.HERO, ui = game.ui;

  // allumage des bougies au passage du Commander (< 70 px)
  for (let i = 0; i < game.CANDLES.length; i++) {
    if (G.lit.has(i)) continue;
    const c = game.CANDLES[i];
    if (Math.hypot(c.x - H.x, c.y - H.y) < 70) G.lit.add(i);
  }

  // conquête : toutes les bougies d'une salle allumées
  for (const r of game.ROOMS) {
    if (ui.owned[r.id]) continue;
    if (game.ROOMCAND[r.id].every(idx => G.lit.has(idx))) { ui.owned[r.id] = true; ui.msg = '✦ ' + r.name + ' conquise — toutes ses bougies brûlent !'; }
  }

  // victoire : mission = anéantir l'IA adverse (Veilleuse + sanctuaires + flemmes)
  if (!ui.win) {
    if (game.mission) {
      if (game.ai && game.ai.spawned && game.ai.defeated && G.foes.length === 0 && G.enemies.length === 0) {
        ui.win = true; ui.msg = '✦ La Veilleuse est vaincue — le manoir est purgé. Victoire !';
      }
    } else if (G.lit.size >= game.CANDLES.length) {
      ui.win = true; ui.msg = '✦ Manoir entièrement éclairé — le coffre est sauf. Victoire !';
    }
  }

  // défaite : coffre forcé
  if (!ui.breached) {
    for (const e of G.enemies) {
      if (Math.hypot(e.x - COFFRE.x, e.y - COFFRE.y) < COFFRE_BREACH) {
        ui.breached = true; ui.report = makeReport();
        ui.msg = '⚠ Coffre-fort forcé — vos données confidentielles ont fuité !'; break;
      }
    }
  }
}

// Reprendre la défense après une défaite.
export function resume(game) {
  const H = game.HERO, ui = game.ui;
  H.x = 540; H.y = 1320; H.trail = []; H.hp = H.maxHp || 100; H.inv = 2;
  game.G.mottes = []; spawnEnemies(game);
  ui.breached = false; ui.heroDown = false; ui.report = null;
  ui.msg = 'Le Commander se relève — renforce la défense près du coffre.';
}
