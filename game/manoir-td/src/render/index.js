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

  // tirs ennemis (segments) — d'autres faisceaux viendront avec les tourelles
  for (const b of game.G.beams) {
    if (!b.seg) continue;
    const ln = b.life / (b.maxLife || 0.12);
    ctx.save(); ctx.globalAlpha = ln; ctx.strokeStyle = b.color; ctx.lineWidth = 2.5; ctx.lineCap = 'round';
    ctx.shadowColor = b.color; ctx.shadowBlur = 6;
    ctx.beginPath(); ctx.moveTo(b.x1, b.y1); ctx.lineTo(b.x2, b.y2); ctx.stroke(); ctx.restore();
  }

  for (const e of game.G.enemies) drawEnemy(ctx, e, th.enemy, t);

  drawHero(game, ctx, th, t);

  ctx.restore();
}
