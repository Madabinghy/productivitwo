// Unités joueur — le Cuirassé-tortue (V2, cf. CUIRASSE-TORTUE-specs.md).
// MOBILE = artillerie : se déplace lentement ET tire ; la carapace pivote vers la menace
//   la plus proche (corps fixe), et chacun des 4 canons vise EN PLUS indépendamment.
// DÉPLOYÉE = soin : increvable, immobile, DÉSARMÉE, aura de soin (façon Bercail).
import { TORTUE, baseHp, MAP } from '../config.js';
import { blocked, compass, angDiff } from '../geometry.js';
import { killTarget, targets } from './enemies.js';

export function deployUnit(game, u) {
  u.deployed = !u.deployed; if (u.deployed) u.moveTarget = null;
  game.ui.msg = u.deployed ? 'Cuirassé-tortue déployé — increvable & aura de soin (désarmé).' : 'Cuirassé-tortue replié — artillerie mobile.';
}

function initCannons(u) {
  u.carapace = u.carapace == null ? 180 : u.carapace;     // orientation de la carapace (deg)
  u.cannons = TORTUE.cannonRest.map(off => ({ off, angle: 180 + off, cd: Math.random() * TORTUE.cannonInterval }));
}

export function updateUnits(game, dt) {
  for (const u of game.ui.placed) {
    if (u.cat !== 'unit' || u.built === false) continue;
    if (u.hp == null) { u.hp = baseHp('tortue'); u.maxHp = u.hp; }
    if (!u.cannons) initCannons(u);

    if (u.deployed) {
      // soin de zone (façon Bercail), désarmée, increvable
      if (game.HERO && Math.hypot(game.HERO.x - u.x, game.HERO.y - u.y) < TORTUE.healRadius)
        game.HERO.hp = Math.min(game.HERO.maxHp || 100, (game.HERO.hp == null ? 100 : game.HERO.hp) + TORTUE.healHero * dt);
      for (const o of game.ui.placed) {
        if (o === u || o.built === false || (o.cat !== 'turret' && o.cat !== 'unit')) continue;
        if (Math.hypot(o.x - u.x, o.y - u.y) < TORTUE.healRadius) { const om = o.maxHp || baseHp(o.key); o.hp = Math.min(om, (o.hp == null ? om : o.hp) + TORTUE.healTurret * dt); }
      }
      continue;
    }

    // déplacement lent (ordre au clic) — le corps NE tourne PAS pour viser
    if (u.moveTarget) {
      const dx = u.moveTarget.x - u.x, dy = u.moveTarget.y - u.y, d = Math.hypot(dx, dy);
      if (d < 8) u.moveTarget = null;
      else {
        const sp = TORTUE.speed * dt; let nx = u.x + dx / d * sp, ny = u.y + dy / d * sp;
        nx = Math.max(20, Math.min(MAP.W - 20, nx)); ny = Math.max(20, Math.min(MAP.H - 20, ny));
        if (!blocked(game.WALLS, u.x, u.y, nx, u.y)) u.x = nx;
        if (!blocked(game.WALLS, u.x, u.y, u.x, ny)) u.y = ny;
        u.bodyDir = compass(dx, dy);
      }
    }

    // cibles à portée + LOS, triées par distance (chaque canon en prend une différente)
    const cand = [];
    for (const e of targets(game)) { const d = Math.hypot(e.x - u.x, e.y - u.y); if (d <= TORTUE.range && !blocked(game.WALLS, u.x, u.y, e.x, e.y)) cand.push({ e, d }); }
    cand.sort((a, b) => a.d - b.d);

    // carapace : pivote vers la menace la plus proche (sinon revient face au corps)
    const restCar = u.moveTarget ? (u.bodyDir || 180) : (u.carapace || 180);
    const carTgt = cand.length ? compass(cand[0].e.x - u.x, cand[0].e.y - u.y) : restCar;
    u.carapace = approach(u.carapace, carTgt, TORTUE.carapaceRot * dt);

    // 4 canons : chacun vise indépendamment, tire quand aligné (cadence décalée)
    u.cannons.forEach((c, i) => {
      c.cd -= dt;
      const tgt = cand.length ? cand[i % cand.length].e : null;
      const aimAngle = tgt ? compass(tgt.x - u.x, tgt.y - u.y) : (u.carapace + c.off);
      c.angle = approach(c.angle, aimAngle, TORTUE.cannonRot * dt);
      if (tgt && c.cd <= 0 && Math.abs(angDiff(aimAngle, c.angle)) < 12) {
        c.cd = TORTUE.cannonInterval; c.flash = 0.09;
        const rad = c.angle * Math.PI / 180, mx = u.x + Math.sin(rad) * 16, my = u.y - Math.cos(rad) * 16;
        game.G.projectiles.push({ x: mx, y: my, tgt, color: '#ff8a3d', shot: 'obus', dmg: TORTUE.dmg, speed: TORTUE.projSpeed, ang: c.angle });
      }
      if (c.flash) c.flash -= dt;
    });
  }
}

// rapproche l'angle a vers b d'au plus step degrés (chemin le plus court)
function approach(a, b, step) {
  if (a == null) return b;
  const d = angDiff(b, a); const m = Math.max(-step, Math.min(step, d));
  return ((a + m) % 360 + 360) % 360;
}
