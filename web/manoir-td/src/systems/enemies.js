// Système ennemis (« les flemmes ») : apparition par portails, errance via le graphe (BFS),
// chasse du héros à vue, tir sur les tourelles, extinction des bougies, dégâts de contact.
import { ENEMY } from '../config.js';
import { blocked } from '../geometry.js';
import { nearestNode, bfsPath } from '../graph.js';
import { hitTurret } from './turrets.js';

export function spawnEnemies(game) {
  game.G.enemies = []; game._spawnT = 0;
  spawnOne(game, 0); spawnOne(game, 1);
}

export function spawnOne(game, idx) {
  const cur = game.ENTRY[idx]; const p = game.NODES[cur];
  const hp = 44 + (game.G.kills || 0) * 5;
  game.G.enemies.push({
    x: p.x, y: p.y, hp, maxHp: hp, speed: 30 + Math.random() * 14,
    chase: false, path: null, pi: 0, acd: Math.random(),
    kind: idx === 0 ? 'spider' : 'mecha', spawn: idx, facing: 180,
  });
}

export function killEnemy(game, e) {
  if (!e || e.dead) return;
  e.dead = true; game.G.kills = (game.G.kills || 0) + 1;
  const val = Math.round(7 + (e.maxHp || 44) / 13);
  game.G.mottes.push({ x: e.x, y: e.y, val, life: 18, max: 18, wob: Math.random() * 6.28 });
}

export function updateEnemies(game, dt) {
  const { G, WALLS, NODES, CANDLES } = game; const H = game.HERO; const ui = game.ui;

  // vagues (suspendues pendant l'intro du tuto via game.noSpawn)
  if (!game.noSpawn) {
    game._spawnT = (game._spawnT || 0) + dt;
    if (game._spawnT >= ENEMY.spawnEvery) {
      game._spawnT = 0;
      if (G.enemies.length < ENEMY.cap) { spawnOne(game, 0); spawnOne(game, 1); }
    }
  }

  const destroyed = [];
  for (const e of G.enemies) {
    const dH = Math.hypot(H.x - e.x, H.y - e.y);
    const sees = dH < ENEMY.chaseDist && !blocked(WALLS, e.x, e.y, H.x, H.y) && !ui.heroDown;

    if (sees) {
      e.chase = true; e.path = null; const sp = ENEMY.chaseSpeed * dt;
      const a = Math.atan2(H.y - e.y, H.x - e.x);
      let nx = e.x + Math.cos(a) * sp, ny = e.y + Math.sin(a) * sp;
      e.facing = Math.atan2(nx - e.x, -(ny - e.y)) * 180 / Math.PI;
      if (!blocked(WALLS, e.x, e.y, nx, ny)) { e.x = nx; e.y = ny; }
      else { if (!blocked(WALLS, e.x, e.y, nx, e.y)) e.x = nx; if (!blocked(WALLS, e.x, e.y, e.x, ny)) e.y = ny; }
      if (dH < ENEMY.contactDist && (H.inv || 0) <= 0 && !ui.heroDown) {
        H.hp = (H.hp == null ? 100 : H.hp) - ENEMY.contactDmg; H.inv = 1.1;
        const a2 = Math.atan2(H.y - e.y, H.x - e.x);
        H.x = Math.max(20, Math.min(2900 - 20, H.x + Math.cos(a2) * 30));
        H.y = Math.max(20, Math.min(1760 - 20, H.y + Math.sin(a2) * 30));
        H.trail = [];
        if (H.hp <= 0) { H.hp = 0; ui.heroDown = true; ui.msg = '⚠ Le Commander est tombé.'; }
        else ui.msg = '⚠ Une flemme frappe le Commander ! (' + Math.max(0, Math.round(H.hp)) + ' PV)';
      }
    } else {
      e.chase = false;
      if (!e.path || e.pi >= e.path.length) {
        let goal; const lit = [...G.lit];
        if (lit.length) {
          let bd = 1e9, bc = lit[0];
          for (const idx of lit) { const cc = CANDLES[idx]; const dd = Math.hypot(cc.x - e.x, cc.y - e.y); if (dd < bd) { bd = dd; bc = idx; } }
          const c = CANDLES[bc]; goal = nearestNode(NODES, c.x, c.y);
        } else goal = Math.floor(Math.random() * NODES.length);
        e.path = bfsPath(NODES, nearestNode(NODES, e.x, e.y), goal) || []; e.pi = 0;
      }
      if (e.path && e.pi < e.path.length) {
        const n = NODES[e.path[e.pi]]; const dx = n.x - e.x, dy = n.y - e.y, d = Math.hypot(dx, dy) || 1;
        const st = e.speed * dt; e.facing = Math.atan2(dx, -dy) * 180 / Math.PI;
        if (d <= st) { e.x = n.x; e.y = n.y; e.pi++; } else { e.x += dx / d * st; e.y += dy / d * st; }
      }
    }

    // souffle les bougies allumées proches
    if (G.lit.size) {
      for (const idx of [...G.lit]) {
        const cc = CANDLES[idx];
        if (Math.hypot(cc.x - e.x, cc.y - e.y) < ENEMY.blowDist) { G.lit.delete(idx); e.path = null; ui.msg = '⚠ Une flemme a soufflé une de vos bougies !'; }
      }
    }

    // tire sur la tourelle la plus proche à portée
    let tgt = null, tb = 1e9;
    for (const t of ui.placed) { if (t.cat !== 'turret') continue; const d = Math.hypot(t.x - e.x, t.y - e.y); if (d < ENEMY.turretFireDist && d < tb && !blocked(WALLS, e.x, e.y, t.x, t.y)) { tb = d; tgt = t; } }
    if (tgt) {
      e.acd = (e.acd || 0) - dt;
      if (e.acd <= 0) { e.acd = 1.2; const removed = hitTurret(game, e, tgt); if (removed != null) destroyed.push(removed); }
    }
  }

  if (destroyed.length) {
    ui.placed = ui.placed.filter(p => destroyed.indexOf(p.id) < 0);
    ui.selId = null; ui.msg = 'Une tourelle a été détruite par les flemmes !';
  }
  G.enemies = G.enemies.filter(e => !e.dead);
}
