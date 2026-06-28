// Rendu de l'IA adverse : territoire revendiqué + structures (cercle d'invocation,
// tourelle adverse) + la Veilleuse (commandant).
import { ROOMS } from '../config.js';
import { drawBossSpider } from './boss_sprite.js';

const PUR = '#c77dff';

function roundRect(ctx, x, y, w, h, r) {
  ctx.beginPath(); ctx.moveTo(x + r, y);
  ctx.arcTo(x + w, y, x + w, y + h, r); ctx.arcTo(x + w, y + h, x, y + h, r);
  ctx.arcTo(x, y + h, x, y, r); ctx.arcTo(x, y, x + w, y, r); ctx.closePath();
}
function hpBar(ctx, x, y, w, f, col) {
  ctx.fillStyle = 'rgba(0,0,0,.6)'; ctx.fillRect(x - w / 2, y, w, 4);
  ctx.fillStyle = col; ctx.fillRect(x - w / 2, y, w * Math.max(0, Math.min(1, f)), 4);
}

export function drawEnemyTerritory(game, ctx) {
  for (const r of ROOMS) {
    if (!game.ui.enemyOwned[r.id]) continue;
    ctx.save();
    roundRect(ctx, r.x, r.y, r.w, r.h, 14);
    ctx.fillStyle = 'rgba(199,125,255,.10)'; ctx.fill();
    ctx.strokeStyle = PUR + '66'; ctx.lineWidth = 1.5; ctx.setLineDash([8, 6]); ctx.stroke(); ctx.setLineDash([]);
    ctx.restore();
  }
}

export function drawFoes(game, ctx, th, t) {
  for (const f of game.G.foes) {
    ctx.save(); ctx.translate(f.x, f.y);
    if (f.kind === 'circle') {
      // cercle d'invocation : bassin sombre + anneaux runiques + lueur
      const g = ctx.createRadialGradient(0, 0, 0, 0, 0, 30); g.addColorStop(0, PUR + '55'); g.addColorStop(0.6, PUR + '18'); g.addColorStop(1, 'transparent');
      ctx.fillStyle = g; ctx.beginPath(); ctx.arc(0, 0, 30, 0, 7); ctx.fill();
      ctx.save(); ctx.rotate(t * 0.6); ctx.setLineDash([6, 8]); ctx.strokeStyle = PUR; ctx.lineWidth = 2; ctx.shadowColor = PUR; ctx.shadowBlur = 10;
      ctx.beginPath(); ctx.arc(0, 0, 20, 0, 7); ctx.stroke(); ctx.restore();
      ctx.save(); ctx.rotate(-t * 0.4); ctx.setLineDash([3, 6]); ctx.strokeStyle = PUR + 'aa'; ctx.lineWidth = 1.5;
      ctx.beginPath(); ctx.arc(0, 0, 13, 0, 7); ctx.stroke(); ctx.restore();
      ctx.fillStyle = '#1a1030'; ctx.beginPath(); ctx.arc(0, 0, 8, 0, 7); ctx.fill();
      ctx.fillStyle = PUR; ctx.shadowColor = PUR; ctx.shadowBlur = 12; ctx.beginPath(); ctx.arc(0, 0, 4, 0, 7); ctx.fill(); ctx.shadowBlur = 0;
      hpBar(ctx, 0, -28, 36, f.hp / f.maxHp, PUR);
    } else if (f.kind === 'eturret') {
      ctx.fillStyle = 'rgba(0,0,0,.4)'; ctx.beginPath(); ctx.ellipse(0, 10, 14, 4, 0, 0, 7); ctx.fill();
      const bg = ctx.createRadialGradient(0, -2, 1, 0, 0, 15); bg.addColorStop(0, '#3a2a4a'); bg.addColorStop(1, '#160f22');
      ctx.fillStyle = bg; ctx.strokeStyle = '#ff5d7a'; ctx.lineWidth = 2; ctx.shadowColor = '#ff5d7a'; ctx.shadowBlur = 7;
      ctx.beginPath(); ctx.arc(0, 0, 13, 0, 7); ctx.fill(); ctx.stroke(); ctx.shadowBlur = 0;
      ctx.fillStyle = '#ff5d7a'; ctx.shadowColor = '#ff5d7a'; ctx.shadowBlur = 9; ctx.beginPath(); ctx.arc(0, 0, 4.5, 0, 7); ctx.fill(); ctx.shadowBlur = 0;
      // 3 buses rouges
      for (const a of [-0.5, 0, 0.5]) { ctx.save(); ctx.rotate(a); ctx.fillStyle = '#ff5d7a'; ctx.fillRect(-1.3, -18, 2.6, 8); ctx.restore(); }
      hpBar(ctx, 0, -24, 30, f.hp / f.maxHp, '#ff5d7a');
    } else if (f.kind === 'commander') {
      const glow = ctx.createRadialGradient(0, 0, 0, 0, 0, 38); glow.addColorStop(0, PUR + '33'); glow.addColorStop(1, 'transparent');
      ctx.fillStyle = glow; ctx.beginPath(); ctx.arc(0, 0, 38, 0, 7); ctx.fill();
      // araignée-boss (sprite) si chargée, sinon repli sur la silhouette de capuche
      if (drawBossSpider(ctx, f, t, 150)) {
        hpBar(ctx, 0, -64, 60, f.hp / f.maxHp, PUR);
        ctx.fillStyle = '#d9c2ff'; ctx.font = "10px 'Chakra Petch', monospace"; ctx.textAlign = 'center';
        ctx.fillText('LA VEILLEUSE', 0, 68);
        ctx.restore(); continue;
      }
      ctx.fillStyle = 'rgba(0,0,0,.45)'; ctx.beginPath(); ctx.ellipse(0, 16, 18, 5, 0, 0, 7); ctx.fill();
      ctx.save(); ctx.rotate((f.dir || 0) * Math.PI / 180);
      // cape (goutte)
      const cg = ctx.createLinearGradient(0, -18, 0, 16); cg.addColorStop(0, '#6a3fb0'); cg.addColorStop(0.5, '#3a2060'); cg.addColorStop(1, '#1a0f2e');
      ctx.fillStyle = cg; ctx.strokeStyle = PUR; ctx.lineWidth = 2; ctx.shadowColor = PUR; ctx.shadowBlur = 10;
      ctx.beginPath(); ctx.moveTo(0, -20); ctx.quadraticCurveTo(16, 0, 11, 16); ctx.quadraticCurveTo(0, 22, -11, 16); ctx.quadraticCurveTo(-16, 0, 0, -20); ctx.fill(); ctx.stroke(); ctx.shadowBlur = 0;
      // capuche
      ctx.fillStyle = '#2a1a44'; ctx.beginPath(); ctx.ellipse(0, -9, 9, 11, 0, 0, 7); ctx.fill();
      // œil-lanterne
      const pulse = 0.7 + 0.3 * Math.sin(t * 4);
      ctx.fillStyle = PUR; ctx.shadowColor = PUR; ctx.shadowBlur = 12 * pulse; ctx.beginPath(); ctx.arc(0, -10, 3.4, 0, 7); ctx.fill(); ctx.shadowBlur = 0;
      ctx.restore();
      hpBar(ctx, 0, -28, 44, f.hp / f.maxHp, PUR);
      ctx.fillStyle = '#d9c2ff'; ctx.font = "9px 'Chakra Petch', monospace"; ctx.textAlign = 'center';
      ctx.fillText('LA VEILLEUSE', 0, 30);
    }
    ctx.restore();
  }
}
