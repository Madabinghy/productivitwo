// Le Commander : déplacement (ZQSD/WASD/flèches), collisions murs, traînée, orientation
// lissée (déplacement > chantier > récolte > défense), et laser défensif du bras gauche.
import { HERO as HCFG, VIS, MAP } from '../config.js';
import { blocked, compass, angDiff } from '../geometry.js';
import { killTarget, targets } from './enemies.js';

// Point de bouche d'un bras : décalé du centre vers la cible, perpendiculaire selon le côté.
export function armMuzzle(H, tx, ty, side) {
  const dx = tx - H.x, dy = ty - H.y, d = Math.hypot(dx, dy) || 1; const ux = dx / d, uy = dy / d;
  return { x: H.x + ux * 15 - uy * 9 * side, y: H.y + uy * 15 + ux * 9 * side };
}

export function updateHeroMove(game, dt) {
  const H = game.HERO, K = game.keys, W = game.WALLS;
  let mx = 0, my = 0;
  if (K['a'] || K['q'] || K['arrowleft']) mx -= 1;
  if (K['d'] || K['arrowright']) mx += 1;
  if (K['w'] || K['z'] || K['arrowup']) my -= 1;
  if (K['s'] || K['arrowdown']) my += 1;
  // joystick tactile (mobile) : prioritaire sur le clavier quand il est poussé
  if (game.joy && (game.joy.x || game.joy.y)) { mx = game.joy.x; my = game.joy.y; }

  // ordre de déplacement (clic) : suivi tant qu'aucune touche n'est pressée
  if (game.heroTarget) {
    if (mx || my) game.heroTarget = null;            // ZQSD annule l'ordre
    else {
      const dx = game.heroTarget.x - H.x, dy = game.heroTarget.y - H.y, d = Math.hypot(dx, dy);
      if (d < 8) game.heroTarget = null;             // arrivé
      else { mx = dx / d; my = dy / d; }
    }
  }
  game._moveX = mx; game._moveY = my;

  if (mx || my) {
    game.freeCam = false;
    const L = Math.hypot(mx, my); const sp = HCFG.speed * dt;
    const px = H.x, py = H.y;
    let nx = H.x + mx / L * sp, ny = H.y + my / L * sp;
    nx = Math.max(20, Math.min(MAP.W - 20, nx)); ny = Math.max(20, Math.min(MAP.H - 20, ny));
    if (!blocked(W, H.x, H.y, nx, H.y)) H.x = nx;          // collision axe par axe (glisse le long des murs)
    if (!blocked(W, H.x, H.y, H.x, ny)) H.y = ny;
    if (!H.trail) H.trail = [];
    game._trailT = (game._trailT || 0) + dt;
    if (game._trailT >= 0.045) { game._trailT = 0; H.trail.push({ x: H.x, y: H.y, life: 0.55 }); if (H.trail.length > 14) H.trail.shift(); }
    // ordre de déplacement bloqué par un mur (pas de pathfinding héros) → abandon après ~1,2 s
    if (game.heroTarget) {
      game._stuckT = (Math.hypot(H.x - px, H.y - py) < sp * 0.3) ? (game._stuckT || 0) + dt : 0;
      if (game._stuckT > 1.2) { game.heroTarget = null; game._stuckT = 0; game.ui.msg = 'Chemin bloqué — déplace-toi en ZQSD.'; }
    }
  }
  if (H.trail) { for (const tp of H.trail) tp.life -= dt; H.trail = H.trail.filter(tp => tp.life > 0); }
}

// Laser défensif (bras gauche) : tire sur la flemme la plus proche à vue, même en agissant.
export function heroLaser(game, dt) {
  const H = game.HERO; const ui = game.ui; if (ui.heroDown) { game._laserTgt = null; return; }
  game._heroCD = (game._heroCD || 0) - dt;
  let be = null, bd = 1e9;
  for (const e of targets(game)) {
    const d = Math.hypot(e.x - H.x, e.y - H.y);
    if (d <= VIS * 0.95 && d < bd && !blocked(game.WALLS, H.x, H.y, e.x, e.y)) { bd = d; be = e; }
  }
  game._laserTgt = be || null;
  if (be && game._heroCD <= 0) {
    game._heroCD = HCFG.laserCd;
    const m = armMuzzle(H, be.x, be.y, -1);
    game.G.beams.push({ kind: 'laser', ax: m.x, ay: m.y, bx: be.x, by: be.y, color: '#8fe3ff', life: 0.12, maxLife: 0.12 });
    be.hp -= HCFG.laserDmg; if (be.hp <= 0) killTarget(game, be);
  }
}

// Orientation : le Commander regarde là où il va / agit.
export function orientHero(game, dt) {
  const H = game.HERO; let want = null;
  if (game._moveX || game._moveY) want = compass(game._moveX, game._moveY);
  else if (game._buildId != null) { const s = game.ui.placed.find(p => p.id === game._buildId); if (s) want = compass(s.x - H.x, s.y - H.y); }
  else if (game._harvestId != null && game.CRYSTALS[game._harvestId]) { const cr = game.CRYSTALS[game._harvestId]; want = compass(cr.x - H.x, cr.y - H.y); }
  else if (game._laserTgt) want = compass(game._laserTgt.x - H.x, game._laserTgt.y - H.y);
  if (want != null) {
    if (H.dir == null) H.dir = want;
    const dd = angDiff(want, H.dir); const stp = HCFG.turnRate * dt;
    H.dir += Math.max(-stp, Math.min(stp, dd));
  }
}
