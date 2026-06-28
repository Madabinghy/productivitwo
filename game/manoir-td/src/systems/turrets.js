// Tourelles de combat + bâtiments de soutien.
// - Acquisition de la cible la plus proche en portée + LOS + arc ; pivot ≤200°/s ; tir au cooldown.
// - Au repos : balayage 180° autour du point de visée (guard=90°, horloge continue) — demande V1.
// - Bercail : soigne héros & tourelles. Bouclier : intercepte les tirs ennemis.
import { turretStats, SHOT, TCOL, baseHp } from '../config.js';
import { blocked, compass, angDiff } from '../geometry.js';
import { killEnemy } from './enemies.js';

const GUARD = 90;        // demi-amplitude → balayage de 180°
const norm = (a) => ((a % 360) + 360) % 360;
const isBuilt = (t) => t.built !== false;

// Polyligne en zigzag pour les éclairs (fulgur).
function jagged(x1, y1, x2, y2) {
  const N = 6, dx = x2 - x1, dy = y2 - y1, len = Math.hypot(dx, dy) || 1, px = -dy / len, py = dx / len, amp = 6, pts = [];
  for (let k = 0; k <= N; k++) {
    const t = k / N; let bx = x1 + dx * t, by = y1 + dy * t;
    if (k > 0 && k < N) { const o = (Math.random() * 2 - 1) * amp; bx += px * o; by += py * o; }
    pts.push({ x: bx, y: by });
  }
  return pts;
}

function shieldSeg(game, sh) {
  const f = (game.AIM[sh.id] != null ? game.AIM[sh.id] : (sh.face || 0)) * Math.PI / 180;
  const dx = Math.sin(f), dy = -Math.cos(f); const px = -dy, py = dx; const HL = 34;
  return { ax: sh.x - px * HL, ay: sh.y - py * HL, bx: sh.x + px * HL, by: sh.y + py * HL };
}
function segParam(x1, y1, x2, y2, x3, y3, x4, y4) {
  const d = (x2 - x1) * (y4 - y3) - (y2 - y1) * (x4 - x3); if (Math.abs(d) < 1e-6) return null;
  const t = ((x3 - x1) * (y4 - y3) - (y3 - y1) * (x4 - x3)) / d;
  const u = ((x3 - x1) * (y2 - y1) - (y3 - y1) * (x2 - x1)) / d;
  return (t >= 0 && t <= 1 && u >= 0 && u <= 1) ? t : null;
}
// Premier bouclier sur la trajectoire d'un tir (x1,y1)->(x2,y2).
export function shieldBlock(game, x1, y1, x2, y2) {
  let best = null, bt = 2;
  for (const sh of game.ui.placed) {
    if (sh.cat !== 'turret' || sh.key !== 'bouclier' || !isBuilt(sh)) continue;
    const s = shieldSeg(game, sh); const t = segParam(x1, y1, x2, y2, s.ax, s.ay, s.bx, s.by);
    if (t != null && t < bt) { bt = t; best = sh; }
  }
  return best;
}

// Un tir ennemi (e) touche une tourelle (tgt) ; renvoie l'id détruit ou null.
export function hitTurret(game, e, tgt) {
  const blk = tgt.key !== 'bouclier' ? shieldBlock(game, e.x, e.y, tgt.x, tgt.y) : null;
  const hitT = blk || tgt;
  if (hitT.hp == null) { const mh = baseHp(hitT.key); hitT.hp = mh; hitT.maxHp = mh; }
  hitT.hp -= 7;
  game.G.beams.push({ kind: 'laser', ax: e.x, ay: e.y, bx: hitT.x, by: hitT.y, color: blk ? '#6fa8ff' : '#ff5d7a', life: 0.12, maxLife: 0.12 });
  return hitT.hp <= 0 ? hitT.id : null;
}

export function updateTurrets(game, dt) {
  const { G } = game; const time = G.time || 0;
  for (const t of game.ui.placed) {
    if (t.cat !== 'turret' || !isBuilt(t)) continue;
    const ts = turretStats(t);

    if (ts.heal) {
      if (game.HERO && Math.hypot(game.HERO.x - t.x, game.HERO.y - t.y) < ts.radius)
        game.HERO.hp = Math.min(game.HERO.maxHp || 100, (game.HERO.hp == null ? 100 : game.HERO.hp) + 15 * dt);
      for (const o of game.ui.placed) {
        if (o.cat === 'turret' && o !== t && Math.hypot(o.x - t.x, o.y - t.y) < ts.radius) {
          const om = o.maxHp || baseHp(o.key); o.hp = Math.min(om, (o.hp == null ? om : o.hp) + 12 * dt);
        }
      }
      continue;
    }
    if (ts.support) continue;

    const range = ts.range, half = ts.half, face = t.face == null ? 0 : t.face;
    let facing = game.AIM[t.id] == null ? face : game.AIM[t.id];

    let best = null, bd = 1e9;
    for (const e of G.enemies) {
      const d = Math.hypot(e.x - t.x, e.y - t.y);
      if (d <= range && d < bd && !blocked(game.WALLS, t.x, t.y, e.x, e.y)) {
        const ang = compass(e.x - t.x, e.y - t.y);
        if (Math.abs(angDiff(ang, facing)) <= half && Math.abs(angDiff(ang, face)) <= GUARD) { bd = d; best = e; }
      }
    }

    if (best) {
      const tang = compass(best.x - t.x, best.y - t.y);
      let df = angDiff(tang, facing);
      facing += Math.max(-200 * dt, Math.min(200 * dt, df));
      const off = angDiff(facing, face);
      if (off > GUARD) facing = face + GUARD; if (off < -GUARD) facing = face - GUARD;
      game.AIM[t.id] = norm(facing);

      game.CD[t.id] = (game.CD[t.id] || 0) - dt;
      if (game.CD[t.id] <= 0 && Math.abs(df) < half) {
        game.CD[t.id] = ts.interval;
        const cfg = SHOT[t.key] || { kind: 'beam', beam: 'laser' };
        const rad = (facing - 90) * Math.PI / 180, mxp = t.x + 20 * Math.cos(rad), myp = t.y + 20 * Math.sin(rad);
        const dmg = ts.dmg; const col = TCOL[t.key];
        if (cfg.kind === 'beam') {
          best.hp -= dmg;
          const beam = { kind: cfg.beam, color: col, life: 0.14, maxLife: 0.14 };
          if (cfg.beam === 'bolt') beam.pts = jagged(mxp, myp, best.x, best.y);
          else { beam.ax = mxp; beam.ay = myp; beam.bx = best.x; beam.by = best.y; }
          G.beams.push(beam);
          if (best.hp <= 0) killEnemy(game, best);
        } else {
          G.projectiles.push({ x: mxp, y: myp, tgt: best, color: col, shot: cfg.shot, dmg, speed: 430, ang: facing });
        }
      }
    } else {
      // balayage 180° au repos (horloge continue, déphasée par tourelle)
      const target = face + GUARD * Math.sin(time * 0.7 + (t.id % 7));
      const df = angDiff(target, facing);
      facing += Math.max(-120 * dt, Math.min(120 * dt, df));
      game.AIM[t.id] = norm(facing);
    }
  }
}
