// Rendu du manoir : sol des salles, couloirs, portes, murs, portails d'entrée, bougies.
import { ROOMS, VPW, VPH, GRID, MAP } from '../config.js';
import { door } from '../graph.js';

function roundRect(ctx, x, y, w, h, r) {
  ctx.beginPath();
  ctx.moveTo(x + r, y);
  ctx.arcTo(x + w, y, x + w, y + h, r);
  ctx.arcTo(x + w, y + h, x, y + h, r);
  ctx.arcTo(x, y + h, x, y, r);
  ctx.arcTo(x, y, x + w, y, r);
  ctx.closePath();
}

export function drawWorld(game, ctx, th, t) {
  const { EDGES, WALLS, CANDLES } = game; const ui = game.ui;
  const A = th.accent;

  // texture de grille de fond — un peu plus marquée pour que le SOL reste lisible une fois
  // éclairé de nuit (le cône du Commander révèle alors une vraie grille, pas du noir uni).
  ctx.save();
  ctx.globalAlpha = 0.30; ctx.strokeStyle = A; ctx.lineWidth = 1;
  for (let x = 0; x <= MAP.W; x += 50) { ctx.beginPath(); ctx.moveTo(x, 0); ctx.lineTo(x, MAP.H); ctx.stroke(); }
  for (let y = 0; y <= MAP.H; y += 50) { ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(MAP.W, y); ctx.stroke(); }
  ctx.restore();

  // couloirs : strips de sol le long des arêtes du graphe
  ctx.save();
  ctx.lineCap = 'round'; ctx.lineJoin = 'round';
  ctx.strokeStyle = A; ctx.globalAlpha = 0.22; ctx.lineWidth = 30;
  for (const e of EDGES) { ctx.beginPath(); ctx.moveTo(e.x1, e.y1); ctx.lineTo(e.x2, e.y2); ctx.stroke(); }
  ctx.globalAlpha = 0.32; ctx.lineWidth = 8; ctx.shadowColor = A; ctx.shadowBlur = 6;
  for (const e of EDGES) { ctx.beginPath(); ctx.moveTo(e.x1, e.y1); ctx.lineTo(e.x2, e.y2); ctx.stroke(); }
  ctx.restore();

  // salles : sol + bordure (conquise = teintée à l'accent de la salle)
  for (const r of ROOMS) {
    const owned = !!ui.owned[r.id];
    ctx.save();
    roundRect(ctx, r.x, r.y, r.w, r.h, 14);
    ctx.fillStyle = owned ? th.roomBg : 'rgba(8,6,14,.55)';
    ctx.fill();
    if (owned) { ctx.shadowColor = r.ac; ctx.shadowBlur = 50; ctx.fill(); ctx.shadowBlur = 0; }
    ctx.lineWidth = 1.5; ctx.strokeStyle = owned ? r.ac + 'aa' : 'rgba(120,120,150,.18)';
    ctx.stroke();
    ctx.restore();
    if (owned) {
      ctx.save(); ctx.fillStyle = r.ac;
      ctx.font = "13px 'Chakra Petch', monospace"; ctx.globalAlpha = 0.9;
      ctx.fillText(r.name.toUpperCase(), r.x + 16, r.y + 24);
      ctx.restore();
    }
  }

  // murs (segments bloquants ; les trous sont les portes)
  ctx.save();
  ctx.strokeStyle = 'rgba(150,150,180,.42)'; ctx.lineWidth = 4; ctx.lineCap = 'round';
  for (const w of WALLS) { ctx.beginPath(); ctx.moveTo(w.x1, w.y1); ctx.lineTo(w.x2, w.y2); ctx.stroke(); }
  ctx.restore();

  // portes : halos lumineux
  for (const r of ROOMS) {
    const d = door(r);
    ctx.save();
    const g = ctx.createRadialGradient(d.x, d.y, 0, d.x, d.y, 12);
    g.addColorStop(0, r.ac); g.addColorStop(1, 'transparent');
    ctx.fillStyle = g; ctx.beginPath(); ctx.arc(d.x, d.y, 12, 0, 7); ctx.fill();
    ctx.restore();
  }

  // portails d'entrée des flemmes (droite de la carte)
  for (const e of [{ x: MAP.R, y: 200 }, { x: MAP.R, y: 1400 }]) {
    const pr = 17 + Math.sin(t * 3) * 3;
    ctx.save();
    const g = ctx.createRadialGradient(e.x, e.y, 0, e.x, e.y, pr);
    g.addColorStop(0, '#ff5d7a'); g.addColorStop(0.7, '#ff5d7a55'); g.addColorStop(1, 'transparent');
    ctx.fillStyle = g; ctx.beginPath(); ctx.arc(e.x, e.y, pr, 0, 7); ctx.fill();
    ctx.restore();
  }

  // bougies allumées : halo + flamme
  const W = ui.warmth == null ? 0.55 : ui.warmth;
  for (let i = 0; i < CANDLES.length; i++) {
    const c = CANDLES[i];
    if (game.G.lit.has(i)) {
      const gsz = 44 + W * 82;
      ctx.save();
      const g = ctx.createRadialGradient(c.x, c.y, 0, c.x, c.y, gsz / 2);
      g.addColorStop(0, th.flame); g.addColorStop(0.6, th.flame + '55'); g.addColorStop(1, 'transparent');
      ctx.globalAlpha = 0.5; ctx.fillStyle = g; ctx.beginPath(); ctx.arc(c.x, c.y, gsz / 2, 0, 7); ctx.fill();
      ctx.globalAlpha = 1; ctx.shadowColor = th.flame; ctx.shadowBlur = 10 + W * 14;
      const fl = 1 + Math.sin(t * 7 + i) * 0.1;
      ctx.fillStyle = '#fff'; ctx.beginPath(); ctx.ellipse(c.x, c.y, 3, 5 * fl, 0, 0, 7); ctx.fill();
      ctx.fillStyle = th.flame; ctx.beginPath(); ctx.ellipse(c.x, c.y + 1, 2, 3 * fl, 0, 0, 7); ctx.fill();
      ctx.restore();
    } else {
      // mèche éteinte : petit repère discret
      ctx.save(); ctx.globalAlpha = 0.28; ctx.fillStyle = '#6a6480';
      ctx.beginPath(); ctx.arc(c.x, c.y, 2.5, 0, 7); ctx.fill(); ctx.restore();
    }
  }
}
