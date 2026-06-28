// Orchestrateur de rendu : applique la caméra puis dessine le monde et les entités.
import { VPW, VPH, THEMES, COFFRE } from '../config.js';
import { drawWorld } from './world.js';
import { drawEnemy, drawCoffre, drawCrystal } from './sprites.js';
import { drawHero } from './hero.js';

export function draw(game, ctx, t) {
  const th = THEMES[game.ui.amb];
  const cam = game.cam;
  const tx = -(cam.fx - VPW / 2), ty = -(cam.fy - VPH / 2);

  ctx.clearRect(0, 0, VPW, VPH);
  ctx.fillStyle = th.stage; ctx.fillRect(0, 0, VPW, VPH);

  ctx.save();
  ctx.translate(Math.round(tx), Math.round(ty));

  drawWorld(game, ctx, th, t);

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

  for (const e of game.G.enemies) drawEnemy(ctx, e, th.enemy, t);

  // projectiles (tourelles — étape 5)
  for (const p of game.G.projectiles) {
    ctx.save(); ctx.fillStyle = p.color; ctx.shadowColor = p.color; ctx.shadowBlur = 11;
    ctx.beginPath(); ctx.arc(p.x, p.y, 6, 0, 7); ctx.fill(); ctx.restore();
  }

  // traînée lumineuse du héros
  for (const tp of (game.HERO.trail || [])) {
    const sz = 8 + tp.life * 14;
    ctx.save(); ctx.globalAlpha = tp.life * 0.55;
    const g = ctx.createRadialGradient(tp.x, tp.y, 0, tp.x, tp.y, sz / 2);
    g.addColorStop(0, th.flame); g.addColorStop(1, 'transparent');
    ctx.fillStyle = g; ctx.beginPath(); ctx.arc(tp.x, tp.y, sz / 2, 0, 7); ctx.fill(); ctx.restore();
  }

  drawHero(game, ctx, th, t);

  ctx.restore();
}
