// Construction « occupée » : le Commander bâtit le chantier le plus proche à portée de vision,
// drainant masse + temps. Stalle si la masse manque. À prog>=1, le bâtiment devient opérationnel.
import { VIS, costOf, upgradeCost, TURRET_ITEMS, SUPPORT_ITEMS } from '../config.js';
import { blocked } from '../geometry.js';

const nameOf = (key) => { const it = TURRET_ITEMS.concat(SUPPORT_ITEMS).find(z => z.key === key); return it ? it.name : key; };

export function updateConstruction(game, dt) {
  const H = game.HERO, G = game.G;
  game._buildId = null; game._buildStall = false;
  // chantiers : bâtiments neufs (built===false) ET améliorations en cours (upgrading)
  const sites = game.ui.placed.filter(p => (p.cat === 'turret' || p.cat === 'unit') && (p.built === false || p.upgrading));
  if (!sites.length) return;
  let near = null, nd = 1e9;
  for (const s of sites) { const d = Math.hypot(s.x - H.x, s.y - H.y); if (d <= VIS && !blocked(game.WALLS, H.x, H.y, s.x, s.y) && d < nd) { nd = d; near = s; } }
  if (!near) return;
  game._buildId = near.id;
  const upgrading = near.built !== false && near.upgrading;
  const cost = upgrading ? upgradeCost(near.key, near.level) : costOf(near.key);
  const bd = 1 - 0.15 * ((game.tourSkills && game.tourSkills.build) || 0); // « Chantier rapide »
  const cMass = cost.mass * bd, cTime = cost.time * bd;
  const want = (cMass / cTime) * dt;
  const avail = Math.min(want, G.mass);
  const frac = want > 0 ? avail / want : 1;
  game._buildStall = frac < 0.999;
  G.mass -= avail;
  if (upgrading) {
    near.upProg = Math.min(1, (near.upProg || 0) + (dt / cTime) * frac);
    if (near.upProg >= 1) { near.level++; near.upgrading = false; near.upProg = 0; game.ui.msg = '✦ ' + nameOf(near.key) + ' améliorée (niv ' + near.level + ').'; }
  } else {
    near.prog = Math.min(1, (near.prog || 0) + (dt / cTime) * frac);
    if (near.prog >= 1) { near.built = true; near.prog = 1; game.ui.msg = '✦ ' + nameOf(near.key) + ' achevé(e) — opérationnel.'; }
  }
}
