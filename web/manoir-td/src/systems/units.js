// Unités joueur — le Cuirassé-tortue (cf. CUIRASSE-TORTUE-specs.md + proto Artillerie).
// Deux postures avec TRANSITION animée (t : 0 mobile → 1 déployée, ~0,6 s) :
// MOBILE (t<0.04) = artillerie : se déplace lentement ET tire ; la carapace pivote vers la
//   menace la plus proche (corps + tête fixes), et chacun des 4 canons — posés sur les écailles —
//   vise EN PLUS indépendamment l'ennemi le plus proche de lui, avec recul au tir.
// DÉPLOYÉE (t>0.9) = soin : increvable, immobile, DÉSARMÉE, aura de soin (façon Bercail).
// Pendant la transition (0<t<1) : figée, ne tire pas, ne soigne pas (canons/pattes/tête rentrent).
import { TORTUE, baseHp, MAP } from '../config.js';
import { blocked, compass, angDiff } from '../geometry.js';
import { killTarget, targets } from './enemies.js';

export function deployUnit(game, u) {
  u.deployed = !u.deployed; if (u.deployed) u.moveTarget = null;
  game.ui.msg = u.deployed ? 'Cuirassé-tortue : déploiement… (aura de soin, increvable)' : 'Cuirassé-tortue : repli… (artillerie mobile)';
}

function initCannons(u) {
  u.carapace = u.carapace == null ? 180 : u.carapace;     // orientation de la carapace (deg)
  u.t = u.deployed ? 1 : 0;                               // avancement du déploiement (0→1)
  u.cannons = TORTUE.cannonRest.map((off, i) => ({
    off, mount: TORTUE.cannonMounts[i],                   // visée de repos + position sur la carapace
    angle: (u.carapace + off + 360) % 360, cd: Math.random() * TORTUE.cannonInterval, recoil: 0, flash: 0,
  }));
}

export function updateUnits(game, dt) {
  for (const u of game.ui.placed) {
    if (u.cat !== 'unit' || u.built === false) continue;
    if (u.hp == null) { u.hp = baseHp('tortue'); u.maxHp = u.hp; }
    if (!u.cannons) initCannons(u);

    // transition de déploiement animée (t vers 0 mobile / 1 déployée, ~0,6 s)
    const dest = u.deployed ? 1 : 0;
    if (u.t == null) u.t = dest;
    if (u.t < dest) u.t = Math.min(dest, u.t + dt / TORTUE.deployTime);
    else if (u.t > dest) u.t = Math.max(dest, u.t - dt / TORTUE.deployTime);
    for (const c of u.cannons) { if (c.recoil > 0) c.recoil = Math.max(0, c.recoil - dt * 4.5); if (c.flash > 0) c.flash -= dt; }

    const healing = u.deployed && u.t > 0.9;     // déployée complète → soin
    const mobile = !u.deployed && u.t < 0.04;    // repliée complète → artillerie

    if (healing) {
      // aura de soin (façon Bercail), désarmée, increvable
      if (game.HERO && Math.hypot(game.HERO.x - u.x, game.HERO.y - u.y) < TORTUE.healRadius)
        game.HERO.hp = Math.min(game.HERO.maxHp || 100, (game.HERO.hp == null ? 100 : game.HERO.hp) + TORTUE.healHero * dt);
      for (const o of game.ui.placed) {
        if (o === u || o.built === false || (o.cat !== 'turret' && o.cat !== 'unit')) continue;
        if (Math.hypot(o.x - u.x, o.y - u.y) < TORTUE.healRadius) { const om = o.maxHp || baseHp(o.key); o.hp = Math.min(om, (o.hp == null ? om : o.hp) + TORTUE.healTurret * dt); }
      }
      continue;
    }
    if (!mobile) continue;   // en pleine transition : figée (ni tir, ni soin, ni déplacement)

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

    // cibles à portée + LOS, triées par distance
    const cand = [];
    for (const e of targets(game)) { const d = Math.hypot(e.x - u.x, e.y - u.y); if (d <= TORTUE.range && !blocked(game.WALLS, u.x, u.y, e.x, e.y)) cand.push({ e, d }); }
    cand.sort((a, b) => a.d - b.d);

    // carapace : pivote vers la menace la plus proche (sinon revient face au corps)
    const restCar = u.moveTarget ? (u.bodyDir || 180) : (u.carapace || 180);
    const carTgt = cand.length ? compass(cand[0].e.x - u.x, cand[0].e.y - u.y) : restCar;
    u.carapace = approach(u.carapace, carTgt, TORTUE.carapaceRot * dt);

    // 4 canons : posés sur les écailles, chacun vise indépendamment l'ennemi le plus proche DE LUI,
    // tire quand aligné (cadence décalée) avec recul ; au repos = suit la carapace.
    u.cannons.forEach((c, i) => {
      c.cd -= dt;
      const mdir = (u.carapace + c.mount) * Math.PI / 180;
      const mx0 = u.x + Math.sin(mdir) * 16, my0 = u.y - Math.cos(mdir) * 16;  // base du canon sur la carapace
      let tgt = null, bd = 1e9;
      for (const o of cand) { const d = Math.hypot(o.e.x - mx0, o.e.y - my0); if (d < bd) { bd = d; tgt = o.e; } }
      const aimAngle = tgt ? compass(tgt.x - mx0, tgt.y - my0) : ((u.carapace + c.off + 360) % 360);
      c.angle = approach(c.angle, aimAngle, TORTUE.cannonRot * dt);
      if (tgt && c.cd <= 0 && Math.abs(angDiff(aimAngle, c.angle)) < 8) {
        c.cd = TORTUE.cannonInterval; c.flash = 0.09; c.recoil = 1;
        const rad = c.angle * Math.PI / 180, mx = mx0 + Math.sin(rad) * 14, my = my0 - Math.cos(rad) * 14;
        game.G.projectiles.push({ x: mx, y: my, tgt, color: '#ff8a3d', shot: 'obus', dmg: TORTUE.dmg, speed: TORTUE.projSpeed, ang: c.angle });
      }
    });
  }
}

// rapproche l'angle a vers b d'au plus step degrés (chemin le plus court)
function approach(a, b, step) {
  if (a == null) return b;
  const d = angDiff(b, a); const m = Math.max(-step, Math.min(step, d));
  return ((a + m) % 360 + 360) % 360;
}
