// Commandant adverse — la Veilleuse (1ʳᵉ version de l'IA, inspirée de IA Adversaire - Protos).
// Elle entre dans le manoir, gagne du territoire en bâtissant des cercles d'invocation
// (qui produisent les flemmes) et déploie des tourelles adverses. Objectif joueur : tout détruire.
import { ROOMS, COFFRE, baseHp } from '../config.js';
import { blocked } from '../geometry.js';
import { nearestNode, bfsPath } from '../graph.js';
import { spawnFlemmeAt } from './enemies.js';

const AI = {
  income: 9, startMass: 55, cap: 320, commMove: 46,
  circleCost: 55, circleHp: 150, circleSpawnEvery: 5.5,
  eturretCost: 48, eturretHp: 90, eturretRange: 250, eturretDmg: 8, eturretInterval: 1.1,
};

export function initEnemyAI(game) {
  const waves = (game.mission && game.mission.waves) || 4;
  game.G.foes = [];
  game.ai = {
    mass: AI.startMass, buildT: 7, spawned: false, defeated: false,
    target: null, path: null, pi: 0,
    commHp: 280 + waves * 40, maxCircles: waves, maxTurrets: Math.max(1, Math.ceil(waves / 3)),
    flemmeCap: 9 + waves,
  };
}

// Mix de sbires produits par les cercles d'invocation (araignées jaunes + scorpions inclus).
const SBIRE_KINDS = ['spider', 'mecha', 'yellow', 'yellow', 'scorpion'];

const roomCenter = (r) => ({ x: r.x + r.w / 2, y: r.y + r.h / 2 });
const commander = (game) => game.G.foes.find(f => f.kind === 'commander');

export function updateEnemyAI(game, dt) {
  if (!game.mission || game.noSpawn || !game.ai) return;
  const ai = game.ai, G = game.G;

  let C = commander(game);
  if (!C && !ai.defeated) {
    const p = game.NODES[game.ENTRY[0]];
    C = { kind: 'commander', x: p.x, y: p.y, hp: ai.commHp, maxHp: ai.commHp, dir: 180, _foe: true };
    G.foes.push(C); ai.spawned = true;
    game.ui.msg = '☾ La Veilleuse entre dans le manoir — détruis-la et ses sanctuaires.';
  }

  if (C) {
    ai.mass = Math.min(AI.cap, ai.mass + AI.income * dt);
    const circles = G.foes.filter(f => f.kind === 'circle');
    C._moved = false;

    // cible : salle non revendiquée la plus proche (le territoire s'étend de proche en proche)
    if (!ai.target || game.ui.enemyOwned[ai.target]) {
      let best = null, bd = 1e9;
      for (const r of ROOMS) { if (game.ui.enemyOwned[r.id]) continue; const c = roomCenter(r); const d = Math.hypot(c.x - C.x, c.y - C.y); if (d < bd) { bd = d; best = r; } }
      ai.target = best ? best.id : null; ai.path = null;
    }
    const room = ai.target ? ROOMS.find(r => r.id === ai.target) : null;

    if (room) {
      const c = roomCenter(room), d = Math.hypot(c.x - C.x, c.y - C.y);
      if (d < 150 && circles.length < ai.maxCircles && ai.mass >= AI.circleCost) {
        ai.mass -= AI.circleCost;
        G.foes.push({ kind: 'circle', x: c.x, y: c.y, hp: AI.circleHp, maxHp: AI.circleHp, roomId: room.id, spawnT: 2, _foe: true });
        game.ui.enemyOwned[room.id] = true; ai.target = null;
      } else { // avance vers la salle via le graphe
        if (!ai.path || ai.pi >= ai.path.length) { ai.path = bfsPath(game.NODES, nearestNode(game.NODES, C.x, C.y), nearestNode(game.NODES, c.x, c.y)) || []; ai.pi = 0; }
        if (ai.path && ai.pi < ai.path.length) {
          const n = game.NODES[ai.path[ai.pi]], dx = n.x - C.x, dy = n.y - C.y, dd = Math.hypot(dx, dy) || 1, st = AI.commMove * dt;
          C.dir = Math.atan2(dx, -dy) * 180 / Math.PI; C._moved = true;
          if (dd <= st) { C.x = n.x; C.y = n.y; ai.pi++; } else { C.x += dx / dd * st; C.y += dy / dd * st; }
        }
      }
    }

    // attaque directe (sort spectral) sur le héros ou une tourelle/unité à portée
    C.atkCd = (C.atkCd || 0) - dt;
    let at = null, ad = 1e9;
    const dHc = Math.hypot(game.HERO.x - C.x, game.HERO.y - C.y);
    if (dHc < 320 && !blocked(game.WALLS, C.x, C.y, game.HERO.x, game.HERO.y)) { at = game.HERO; ad = dHc; }
    for (const p of game.ui.placed) {
      if ((p.cat !== 'turret' && p.cat !== 'unit') || p.built === false || p.deployed) continue;
      const d = Math.hypot(p.x - C.x, p.y - C.y); if (d < 320 && d < ad && !blocked(game.WALLS, C.x, C.y, p.x, p.y)) { ad = d; at = p; }
    }
    if (at && C.atkCd <= 0) {
      C.atkCd = 2.4; C.anim = 'attack'; C.animT = 0.6; C.animDur = 0.6; C.dir = Math.atan2(at.x - C.x, -(at.y - C.y)) * 180 / Math.PI;
      game.G.beams.push({ kind: 'bolt', ax: C.x, ay: C.y, bx: at.x, by: at.y, color: '#c77dff', life: 0.18, maxLife: 0.18 });
      if (at === game.HERO) { if ((game.HERO.inv || 0) <= 0 && !game.ui.heroDown) { game.HERO.hp -= 12; game.HERO.inv = 0.4; if (game.HERO.hp <= 0) { game.HERO.hp = 0; game.ui.heroDown = true; game.ui.msg = '⚠ Le Commander est tombé.'; } } }
      else { if (at.hp == null) { at.hp = baseHp(at.key); at.maxHp = at.hp; } at.hp -= 14; if (at.hp <= 0) { game.ui.placed = game.ui.placed.filter(x => x !== at); if (game.ui.selId === at.id) game.ui.selId = null; } }
    }
    // état d'animation du boss
    if ((C.animT || 0) > 0) { C.animT -= dt; C.anim = 'attack'; } else C.anim = C._moved ? 'walk' : 'idle';

    // déploie une tourelle adverse vers le coffre du joueur
    ai.buildT -= dt;
    if (ai.buildT <= 0 && G.foes.filter(f => f.kind === 'eturret').length < ai.maxTurrets && ai.mass >= AI.eturretCost) {
      ai.buildT = 9; ai.mass -= AI.eturretCost;
      const a = Math.atan2(COFFRE.y - C.y, COFFRE.x - C.x);
      G.foes.push({ kind: 'eturret', x: C.x + Math.cos(a) * 42, y: C.y + Math.sin(a) * 42, hp: AI.eturretHp, maxHp: AI.eturretHp, cd: 0, _foe: true });
    }
  }

  // cercles d'invocation : produisent les flemmes
  for (const f of G.foes) {
    if (f.kind !== 'circle') continue;
    f.spawnT -= dt;
    if (f.spawnT <= 0) { f.spawnT = AI.circleSpawnEvery; if (G.enemies.length < ai.flemmeCap) spawnFlemmeAt(game, f.x, f.y, SBIRE_KINDS[(Math.random() * SBIRE_KINDS.length) | 0]); }
  }

  // tourelles adverses : tirent sur la tourelle/le Commander du joueur à portée
  for (const f of G.foes) {
    if (f.kind !== 'eturret') continue;
    f.cd -= dt; if (f.cd > 0) continue;
    let tgt = null, bd = 1e9;
    for (const p of game.ui.placed) { if ((p.cat !== 'turret' && p.cat !== 'unit') || p.built === false || p.deployed) continue; const d = Math.hypot(p.x - f.x, p.y - f.y); if (d < AI.eturretRange && d < bd && !blocked(game.WALLS, f.x, f.y, p.x, p.y)) { bd = d; tgt = p; } }
    const dh = Math.hypot(game.HERO.x - f.x, game.HERO.y - f.y);
    if (dh < AI.eturretRange && dh < bd && !blocked(game.WALLS, f.x, f.y, game.HERO.x, game.HERO.y)) { tgt = game.HERO; bd = dh; }
    if (!tgt) continue;
    f.cd = AI.eturretInterval;
    game.G.beams.push({ kind: 'laser', ax: f.x, ay: f.y, bx: tgt.x, by: tgt.y, color: '#c77dff', life: 0.12, maxLife: 0.12 });
    if (tgt === game.HERO) {
      if ((game.HERO.inv || 0) <= 0 && !game.ui.heroDown) { game.HERO.hp -= AI.eturretDmg; game.HERO.inv = 0.3; if (game.HERO.hp <= 0) { game.HERO.hp = 0; game.ui.heroDown = true; game.ui.msg = '⚠ Le Commander est tombé.'; } }
    } else {
      if (tgt.hp == null) { tgt.hp = baseHp(tgt.key); tgt.maxHp = tgt.hp; }
      tgt.hp -= AI.eturretDmg;
      if (tgt.hp <= 0) { game.ui.placed = game.ui.placed.filter(x => x !== tgt); if (game.ui.selId === tgt.id) game.ui.selId = null; }
    }
  }
}
