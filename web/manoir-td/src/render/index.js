// Orchestrateur de rendu : applique la caméra puis dessine le monde et les entités.
import { VPW, VPH, THEMES, COFFRE } from '../config.js';
import { drawWorld } from './world.js';
import { drawEnemy, drawCoffre, drawCrystal } from './sprites.js';
import { drawHero } from './hero.js';
import { armMuzzle } from '../systems/hero.js';
import { drawPlaced, drawGhost, drawBuildBeam, drawPlaceHalos } from './buildings.js';
import { drawFog, drawMinimap } from './fog.js';
import { enemyRevealed, turretSees } from '../systems/vision.js';

export function draw(game, ctx, t) {
  const th = THEMES[game.ui.amb];
  const cam = game.cam;
  const tx = Math.round(-(cam.fx - VPW / 2)), ty = Math.round(-(cam.fy - VPH / 2));

  ctx.clearRect(0, 0, VPW, VPH);
  ctx.fillStyle = th.stage; ctx.fillRect(0, 0, VPW, VPH);

  ctx.save();
  ctx.translate(tx, ty);

  drawWorld(game, ctx, th, t);
  drawPlaceHalos(game, ctx, th);

  for (const cr of game.CRYSTALS) drawCrystal(ctx, cr, t);
  drawCoffre(ctx, COFFRE, th, game.G.enemies.some(e => Math.hypot(e.x - COFFRE.x, e.y - COFFRE.y) < 170), t);

  // mottes de masse
  for (const m of game.G.mottes) {
    const fade = Math.min(1, m.life / 3); const sz = 7 + Math.sin(t * 4 + m.wob) * 1.2;
    ctx.save(); ctx.globalAlpha = fade;
    const g = ctx.createRadialGradient(m.x, m.y, 0, m.x, m.y, sz);
    g.addColorStop(0, '#fff7df'); g.addColorStop(0.6, th.flame); g.addColorStop(1, '#ff9e3d');
    ctx.fillStyle = g; ctx.shadowColor = th.flame; ctx.shadowBlur = 10;
    ctx.beginPath(); ctx.arc(m.x, m.y, sz, 0, 7); ctx.fill(); ctx.restore();
  }

  // faisceaux : laser (droit) / bolt (zigzag) — héros, tourelles, tirs ennemis
  for (const b of game.G.beams) {
    const ln = b.life / (b.maxLife || 0.14);
    ctx.save(); ctx.lineCap = 'round'; ctx.lineJoin = 'round'; ctx.shadowColor = b.color; ctx.shadowBlur = 6;
    const trace = () => {
      ctx.beginPath();
      if (b.pts) { ctx.moveTo(b.pts[0].x, b.pts[0].y); for (let i = 1; i < b.pts.length; i++) ctx.lineTo(b.pts[i].x, b.pts[i].y); }
      else { ctx.moveTo(b.ax, b.ay); ctx.lineTo(b.bx, b.by); }
      ctx.stroke();
    };
    ctx.strokeStyle = b.color; ctx.globalAlpha = ln * 0.4; ctx.lineWidth = b.kind === 'bolt' ? 7 : 8; trace();
    ctx.strokeStyle = b.kind === 'bolt' ? '#fff6c4' : '#eaffff'; ctx.globalAlpha = ln; ctx.lineWidth = b.kind === 'bolt' ? 2.4 : 2.6; trace();
    ctx.restore();
  }

  // faisceau de récolte (bras droit) : triangle cyan vers le gisement ciblé
  if (game._harvestId != null && game.CRYSTALS[game._harvestId]) {
    const H = game.HERO, cr = game.CRYSTALS[game._harvestId];
    const m = armMuzzle(H, cr.x, cr.y, 1);
    const dx = cr.x - m.x, dy = cr.y - m.y, d = Math.hypot(dx, dy) || 1; const px = -dy / d, py = dx / d, w = 15;
    const j = 0.5 + 0.5 * Math.sin(t * 16);
    ctx.save(); ctx.globalAlpha = 0.32 + j * 0.3; ctx.fillStyle = '#bfe6ff'; ctx.shadowColor = '#9fd8ff'; ctx.shadowBlur = 6;
    ctx.beginPath(); ctx.moveTo(m.x, m.y); ctx.lineTo(cr.x + px * w, cr.y + py * w); ctx.lineTo(cr.x - px * w, cr.y - py * w); ctx.closePath(); ctx.fill();
    ctx.restore();
  }

  drawPlaced(game, ctx, th, t);

  for (const e of game.G.enemies) {
    if (game.ui.darkMode && !(enemyRevealed(game, e) || turretSees(game, e))) continue; // caché par le brouillard
    drawEnemy(ctx, e, th.enemy, t);
  }

  // projectiles des tourelles (forme par type de tir)
  for (const p of game.G.projectiles) {
    ctx.save(); ctx.translate(p.x, p.y);
    if (p.shot === 'fireball') {
      ctx.rotate((p.ang || 0) * Math.PI / 180);
      ctx.globalAlpha = 0.7; ctx.fillStyle = p.color; ctx.shadowColor = p.color; ctx.shadowBlur = 8;
      ctx.beginPath(); ctx.ellipse(0, 10, 3, 12, 0, 0, 7); ctx.fill(); ctx.globalAlpha = 1; ctx.rotate(-(p.ang || 0) * Math.PI / 180);
    }
    if (p.shot === 'sigil') { ctx.strokeStyle = p.color; ctx.lineWidth = 2; ctx.shadowColor = p.color; ctx.shadowBlur = 10; ctx.beginPath(); ctx.arc(0, 0, 7, 0, 7); ctx.stroke(); }
    const g = ctx.createRadialGradient(0, -1, 0, 0, 0, 7);
    g.addColorStop(0, '#fff'); g.addColorStop(0.4, p.color); g.addColorStop(1, p.color + '00');
    ctx.fillStyle = g; ctx.shadowColor = p.color; ctx.shadowBlur = 11;
    ctx.beginPath(); ctx.arc(0, 0, p.shot === 'sigil' ? 4 : 6, 0, 7); ctx.fill();
    ctx.restore();
  }

  // traînée lumineuse du héros
  for (const tp of (game.HERO.trail || [])) {
    const sz = 8 + tp.life * 14;
    ctx.save(); ctx.globalAlpha = tp.life * 0.55;
    const g = ctx.createRadialGradient(tp.x, tp.y, 0, tp.x, tp.y, sz / 2);
    g.addColorStop(0, th.flame); g.addColorStop(1, 'transparent');
    ctx.fillStyle = g; ctx.beginPath(); ctx.arc(tp.x, tp.y, sz / 2, 0, 7); ctx.fill(); ctx.restore();
  }

  drawBuildBeam(game, ctx, t);
  drawHero(game, ctx, th, t);
  drawGhost(game, ctx, th, t);

  ctx.restore();

  // surcouches en repère écran
  drawFog(game, ctx, th, tx, ty);
  drawMinimap(game, ctx, th);
}
