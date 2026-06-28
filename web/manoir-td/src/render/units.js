// Rendu des unités joueur — le Cuirassé-tortue (mobile : canons ; déployé : dôme + zone de soin/chantier).
import { TORTUE } from '../config.js';

const COL = '#9ad06a', SHELL1 = '#3a4a2e', SHELL2 = '#1c2618';

function shell(ctx, R) {
  ctx.beginPath();
  for (let i = 0; i < 6; i++) { const a = (i / 6) * Math.PI * 2 - Math.PI / 2; const x = Math.cos(a) * R, y = Math.sin(a) * R * 0.92; i ? ctx.lineTo(x, y) : ctx.moveTo(x, y); }
  ctx.closePath();
}

export function drawUnits(game, ctx, th, t) {
  for (const u of game.ui.placed) {
    if (u.cat !== 'unit') continue;
    const built = u.built !== false; const sel = game.ui.selId === u.id;

    // anneaux au sol
    if (built && u.deployed) {
      ctx.save();
      const g = ctx.createRadialGradient(u.x, u.y, 0, u.x, u.y, TORTUE.healRadius);
      g.addColorStop(0, '#7bff9b18'); g.addColorStop(0.72, 'transparent');
      ctx.fillStyle = g; ctx.beginPath(); ctx.arc(u.x, u.y, TORTUE.healRadius, 0, 7); ctx.fill();
      ctx.setLineDash([8, 6]); ctx.strokeStyle = COL + '88'; ctx.lineWidth = 1.5; ctx.beginPath(); ctx.arc(u.x, u.y, TORTUE.buildRadius, 0, 7); ctx.stroke(); ctx.setLineDash([]);
      ctx.restore();
    } else if (built && sel) {
      ctx.save(); ctx.strokeStyle = COL + '44'; ctx.lineWidth = 1; ctx.setLineDash([4, 6]); ctx.beginPath(); ctx.arc(u.x, u.y, TORTUE.range, 0, 7); ctx.stroke(); ctx.setLineDash([]); ctx.restore();
    }

    ctx.save(); ctx.translate(u.x, u.y);
    if (!built) ctx.globalAlpha = 0.3 + (u.prog || 0) * 0.5;
    // ombre
    ctx.fillStyle = 'rgba(0,0,0,.45)'; ctx.beginPath(); ctx.ellipse(0, 14, 20, 6, 0, 0, 7); ctx.fill();

    // canons (mobile uniquement), orientés
    if (!u.deployed) {
      ctx.save(); ctx.rotate((u.dir || 0) * Math.PI / 180);
      for (const side of [-1, 1]) {
        ctx.fillStyle = '#566079'; ctx.fillRect(side * 5 - 1.6, -22, 3.2, 16);
        ctx.fillStyle = COL; ctx.beginPath(); ctx.arc(side * 5, -22, 2, 0, 7); ctx.fill();
        if (u.flash > 0) { ctx.fillStyle = '#eaffff'; ctx.shadowColor = COL; ctx.shadowBlur = 8; ctx.beginPath(); ctx.arc(side * 5, -24, 2.6, 0, 7); ctx.fill(); ctx.shadowBlur = 0; }
      }
      ctx.restore();
    }

    // carapace (plaques hexagonales)
    const g = ctx.createRadialGradient(0, -4, 2, 0, 2, 22); g.addColorStop(0, '#5a7040'); g.addColorStop(0.55, SHELL1); g.addColorStop(1, SHELL2);
    ctx.fillStyle = g; ctx.strokeStyle = u.deployed ? '#7bff9b' : COL; ctx.lineWidth = 2.5;
    ctx.shadowColor = u.deployed ? '#7bff9b' : COL; ctx.shadowBlur = u.deployed ? 14 + Math.sin(t * 4) * 4 : 8;
    shell(ctx, 19); ctx.fill(); ctx.stroke(); ctx.shadowBlur = 0;
    // nervures
    ctx.strokeStyle = '#0008'; ctx.lineWidth = 1.5; shell(ctx, 12); ctx.stroke();
    // dôme central
    const dg = ctx.createRadialGradient(0, -2, 0, 0, 0, 8); dg.addColorStop(0, u.deployed ? '#bfffce' : '#cfe7ff'); dg.addColorStop(1, SHELL2);
    ctx.fillStyle = dg; ctx.beginPath(); ctx.arc(0, 0, 7, 0, 7); ctx.fill();
    ctx.fillStyle = u.deployed ? '#7bff9b' : COL; ctx.shadowColor = ctx.fillStyle; ctx.shadowBlur = 8; ctx.beginPath(); ctx.arc(0, 0, 3, 0, 7); ctx.fill(); ctx.shadowBlur = 0;
    ctx.restore();

    // sélection
    if (sel) { ctx.save(); ctx.strokeStyle = COL; ctx.lineWidth = 2; ctx.setLineDash([6, 6]); ctx.translate(u.x, u.y); ctx.rotate(t * 0.6); ctx.beginPath(); ctx.arc(0, 0, 26, 0, 7); ctx.stroke(); ctx.setLineDash([]); ctx.restore(); }

    // PV / chantier
    if (built) {
      const f = Math.max(0, Math.min(1, (u.hp == null ? u.maxHp : u.hp) / (u.maxHp || TORTUE.hp)));
      if (f < 1 && !u.deployed) { ctx.save(); ctx.fillStyle = 'rgba(0,0,0,.6)'; ctx.fillRect(u.x - 20, u.y - 28, 40, 4); ctx.fillStyle = f > 0.5 ? '#7bff9b' : f > 0.25 ? '#ffd66e' : '#ff5d7a'; ctx.fillRect(u.x - 20, u.y - 28, 40 * f, 4); ctx.restore(); }
    } else {
      const bp = Math.max(0, Math.min(1, u.prog || 0)); const isSite = game._buildId === u.id;
      ctx.save(); ctx.translate(u.x, u.y); ctx.setLineDash([6, 5]); ctx.strokeStyle = isSite ? th.flame : '#8a96b3'; ctx.lineWidth = 2;
      ctx.beginPath(); ctx.arc(0, 0, 26, 0, 7); ctx.stroke(); ctx.setLineDash([]);
      ctx.fillStyle = th.flame; ctx.font = "11px 'Chakra Petch', monospace"; ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
      ctx.fillText((isSite ? '⚒ ' : '') + Math.round(bp * 100) + '%', 0, 0); ctx.restore();
    }
  }
}
