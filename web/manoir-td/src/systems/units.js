// Unités joueur mobiles — le Cuirassé-tortue.
// Mobile : se déplace (ordres au clic) + ses canons fauchent flemmes/structures à 360°.
// Déployé : immobile, increvable, soigne (héros + tourelles + unités) et ouvre une zone de
// chantier (cf. vision.js canPlaceAt / visionSources). Inspiré de Cuirassé-tortue - Déploiement.
import { TORTUE, baseHp, MAP } from '../config.js';
import { blocked, compass } from '../geometry.js';
import { killTarget, targets } from './enemies.js';

export function deployUnit(game, u) {
  u.deployed = !u.deployed; if (u.deployed) u.moveTarget = null;
  game.ui.msg = u.deployed ? 'Cuirassé-tortue déployé — increvable, soigne et ouvre une zone de chantier.' : 'Cuirassé-tortue replié — mobile, canons actifs.';
}

export function updateUnits(game, dt) {
  for (const u of game.ui.placed) {
    if (u.cat !== 'unit' || u.built === false) continue;
    if (u.hp == null) { u.hp = baseHp('tortue'); u.maxHp = u.hp; }

    if (u.deployed) {
      // soin de zone (comme un Bercail)
      if (game.HERO && Math.hypot(game.HERO.x - u.x, game.HERO.y - u.y) < TORTUE.healRadius)
        game.HERO.hp = Math.min(game.HERO.maxHp || 100, (game.HERO.hp == null ? 100 : game.HERO.hp) + TORTUE.healHero * dt);
      for (const o of game.ui.placed) {
        if (o === u || o.built === false || (o.cat !== 'turret' && o.cat !== 'unit')) continue;
        if (Math.hypot(o.x - u.x, o.y - u.y) < TORTUE.healRadius) { const om = o.maxHp || baseHp(o.key); o.hp = Math.min(om, (o.hp == null ? om : o.hp) + TORTUE.healTurret * dt); }
      }
      continue; // déployé : immobile, ne tire pas
    }

    // déplacement (ordre au clic)
    if (u.moveTarget) {
      const dx = u.moveTarget.x - u.x, dy = u.moveTarget.y - u.y, d = Math.hypot(dx, dy);
      if (d < 8) u.moveTarget = null;
      else {
        const sp = TORTUE.speed * dt; let nx = u.x + dx / d * sp, ny = u.y + dy / d * sp;
        nx = Math.max(20, Math.min(MAP.W - 20, nx)); ny = Math.max(20, Math.min(MAP.H - 20, ny));
        if (!blocked(game.WALLS, u.x, u.y, nx, u.y)) u.x = nx;
        if (!blocked(game.WALLS, u.x, u.y, u.x, ny)) u.y = ny;
        u.dir = compass(dx, dy);
      }
    }

    // canons : flemme/structure la plus proche en portée + LOS (360°)
    u.cd = (u.cd || 0) - dt;
    let best = null, bd = 1e9;
    for (const e of targets(game)) { const d = Math.hypot(e.x - u.x, e.y - u.y); if (d <= TORTUE.range && d < bd && !blocked(game.WALLS, u.x, u.y, e.x, e.y)) { bd = d; best = e; } }
    if (best) {
      if (!u.moveTarget) u.dir = compass(best.x - u.x, best.y - u.y);
      if (u.cd <= 0) {
        u.cd = TORTUE.interval; u.flash = 0.1;
        // deux canons (faisceaux jumeaux)
        const r = (u.dir - 90) * Math.PI / 180, px = -Math.sin(u.dir * Math.PI / 180), py = Math.cos(u.dir * Math.PI / 180);
        for (const side of [-1, 1]) {
          const mx = u.x + px * 7 * side, my = u.y + py * 7 * side;
          game.G.beams.push({ kind: 'laser', ax: mx, ay: my, bx: best.x, by: best.y, color: '#bfe6ff', life: 0.1, maxLife: 0.1 });
        }
        best.hp -= TORTUE.dmg; if (best.hp <= 0) killTarget(game, best);
      }
    }
    if (u.flash) u.flash -= dt;
  }
}
