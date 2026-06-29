// Rendu du Cuirassé-tortue (cf. CUIRASSE-TORTUE-specs.md + captures).
// MOBILE : carapace acier 6 plaques (pivote), cœur OR, 4 canons à visée indépendante, pattes, tête.
// DÉPLOYÉE : rétractée, cœur VERT, aura de soin + motes, badge INCREVABLE (PV masqués).
import { TORTUE } from '../config.js';

const STEEL_HI = '#8a96b3', STEEL = '#566079', STEEL_DK = '#161220';
const GOLD = '#ffce5e', GOLD_D = '#ff9e3d', GREEN = '#6effa8', GREEN_D = '#1d9c5e';

function plates(ctx, R, col, edge) {
  // dôme + 6 écailles
  const g = ctx.createRadialGradient(0, -R * 0.3, 2, 0, 0, R);
  g.addColorStop(0, STEEL_HI); g.addColorStop(0.55, STEEL); g.addColorStop(1, STEEL_DK);
  ctx.fillStyle = g; ctx.strokeStyle = edge; ctx.lineWidth = 2;
  ctx.beginPath(); ctx.arc(0, 0, R, 0, 7); ctx.fill(); ctx.stroke();
  ctx.strokeStyle = 'rgba(0,0,0,.45)'; ctx.lineWidth = 1.4;
  for (let i = 0; i < 6; i++) { const a = (i / 6) * Math.PI * 2; ctx.beginPath(); ctx.moveTo(Math.cos(a) * 4, Math.sin(a) * 4); ctx.lineTo(Math.cos(a) * R, Math.sin(a) * R); ctx.stroke(); }
}

export function drawUnits(game, ctx, th, t) {
  for (const u of game.ui.placed) {
    if (u.cat !== 'unit') continue;
    const built = u.built !== false, sel = game.ui.selId === u.id, dep = u.deployed;

    // aura de soin (déployée) ou cercle de portée (sélectionnée mobile)
    if (built && dep) {
      ctx.save();
      const g = ctx.createRadialGradient(u.x, u.y, 0, u.x, u.y, TORTUE.healRadius);
      g.addColorStop(0, GREEN + '20'); g.addColorStop(0.72, 'transparent');
      ctx.fillStyle = g; ctx.beginPath(); ctx.arc(u.x, u.y, TORTUE.healRadius, 0, 7); ctx.fill();
      ctx.setLineDash([6, 8]); ctx.strokeStyle = GREEN + '66'; ctx.lineWidth = 1.5; ctx.beginPath(); ctx.arc(u.x, u.y, TORTUE.healRadius, 0, 7); ctx.stroke(); ctx.setLineDash([]);
      // motes de soin qui montent
      for (let k = 0; k < 5; k++) { const ph = (t * 0.6 + k / 5) % 1, a = k * 1.3, rr = TORTUE.healRadius * 0.5; const mx = u.x + Math.cos(a) * rr * (0.4 + ph * 0.5), my = u.y + rr * 0.3 - ph * 60; ctx.globalAlpha = (1 - ph) * 0.8; ctx.fillStyle = GREEN; ctx.font = '11px monospace'; ctx.fillText('+', mx, my); }
      ctx.globalAlpha = 1; ctx.restore();
    } else if (built && sel) {
      ctx.save(); ctx.strokeStyle = GOLD + '44'; ctx.lineWidth = 1; ctx.setLineDash([4, 6]); ctx.beginPath(); ctx.arc(u.x, u.y, TORTUE.range, 0, 7); ctx.stroke(); ctx.setLineDash([]); ctx.restore();
    }

    ctx.save(); ctx.translate(u.x, u.y);
    if (!built) ctx.globalAlpha = 0.3 + (u.prog || 0) * 0.5;
    ctx.fillStyle = 'rgba(0,0,0,.45)'; ctx.beginPath(); ctx.ellipse(0, 14, 22, 6, 0, 0, 7); ctx.fill();

    const R = 20, accent = dep ? GREEN : GOLD;

    if (!dep) {
      // pattes (corps fixe)
      ctx.fillStyle = STEEL; ctx.strokeStyle = STEEL_HI; ctx.lineWidth = 1;
      for (const a of [46, 134, 226, 314]) { const r = a * Math.PI / 180; ctx.save(); ctx.translate(Math.sin(r) * R, -Math.cos(r) * R); ctx.rotate(r); ctx.beginPath(); ctx.ellipse(0, 4, 4, 6, 0, 0, 7); ctx.fill(); ctx.stroke(); ctx.restore(); }
      // canons (visée indépendante)
      for (const c of (u.cannons || [])) {
        const rad = c.angle * Math.PI / 180, bx = Math.sin(rad), by = -Math.cos(rad);
        ctx.strokeStyle = '#3a3a45'; ctx.lineWidth = 4; ctx.lineCap = 'round';
        ctx.beginPath(); ctx.moveTo(bx * 10, by * 10); ctx.lineTo(bx * 22, by * 22); ctx.stroke();
        ctx.fillStyle = STEEL_DK; ctx.strokeStyle = GOLD; ctx.lineWidth = 1;
        ctx.save(); ctx.translate(bx * 12, by * 12); ctx.rotate(rad); ctx.fillRect(-3.5, -3.5, 7, 7); ctx.strokeRect(-3.5, -3.5, 7, 7); ctx.restore();
        if (c.flash > 0) { ctx.fillStyle = '#fff3c4'; ctx.shadowColor = GOLD_D; ctx.shadowBlur = 8; ctx.beginPath(); ctx.arc(bx * 24, by * 24, 3, 0, 7); ctx.fill(); ctx.shadowBlur = 0; }
      }
    }

    // carapace (pivote en mobile ; rétractée/figée en déployé)
    ctx.save(); ctx.rotate((dep ? 0 : (u.carapace || 180)) * Math.PI / 180);
    plates(ctx, dep ? R * 0.88 : R, STEEL, dep ? GREEN : STEEL_HI);
    // tête (mobile uniquement), à l'avant de la carapace
    if (!dep) { ctx.fillStyle = STEEL; ctx.strokeStyle = STEEL_HI; ctx.lineWidth = 1; ctx.beginPath(); ctx.ellipse(0, -R - 1, 6, 5, 0, 0, 7); ctx.fill(); ctx.stroke(); ctx.fillStyle = GOLD; ctx.shadowColor = GOLD; ctx.shadowBlur = 6; ctx.fillRect(-3, -R - 2, 6, 2); ctx.shadowBlur = 0; }
    ctx.restore();

    // cœur central lumineux
    const cg = ctx.createRadialGradient(0, 0, 0, 0, 0, 9); cg.addColorStop(0, '#fff'); cg.addColorStop(0.4, accent); cg.addColorStop(1, dep ? GREEN_D : GOLD_D);
    ctx.fillStyle = cg; ctx.shadowColor = accent; ctx.shadowBlur = 12; ctx.beginPath(); ctx.arc(0, 0, dep ? 8 : 7, 0, 7); ctx.fill(); ctx.shadowBlur = 0;
    ctx.strokeStyle = accent + 'aa'; ctx.lineWidth = 1.5; ctx.beginPath(); ctx.arc(0, 0, dep ? 11 : 12, 0, 7); ctx.stroke();
    ctx.restore();

    // sélection
    if (sel) { ctx.save(); ctx.strokeStyle = accent; ctx.lineWidth = 2; ctx.setLineDash([6, 6]); ctx.translate(u.x, u.y); ctx.rotate(t * 0.6); ctx.beginPath(); ctx.arc(0, 0, 28, 0, 7); ctx.stroke(); ctx.setLineDash([]); ctx.restore(); }

    // PV (mobile) / badge INCREVABLE (déployé) / % chantier
    if (!built) {
      const bp = Math.max(0, Math.min(1, u.prog || 0)), isSite = game._buildId === u.id;
      ctx.save(); ctx.translate(u.x, u.y); ctx.setLineDash([6, 5]); ctx.strokeStyle = isSite ? th.flame : '#8a96b3'; ctx.lineWidth = 2; ctx.beginPath(); ctx.arc(0, 0, 27, 0, 7); ctx.stroke(); ctx.setLineDash([]);
      ctx.fillStyle = th.flame; ctx.font = "11px 'Chakra Petch', monospace"; ctx.textAlign = 'center'; ctx.textBaseline = 'middle'; ctx.fillText((isSite ? '⚒ ' : '') + Math.round(bp * 100) + '%', 0, 0); ctx.restore();
    } else if (dep) {
      ctx.save(); ctx.fillStyle = GREEN; ctx.font = "8px 'Chakra Petch', monospace"; ctx.textAlign = 'center';
      ctx.fillStyle = 'rgba(10,30,18,.85)'; ctx.fillRect(u.x - 30, u.y - 34, 60, 12); ctx.fillStyle = GREEN; ctx.fillText('⛨ INCREVABLE', u.x, u.y - 25); ctx.restore();
    } else {
      const f = Math.max(0, Math.min(1, (u.hp == null ? u.maxHp : u.hp) / (u.maxHp || TORTUE.hp)));
      if (f < 1) { ctx.save(); ctx.fillStyle = 'rgba(0,0,0,.6)'; ctx.fillRect(u.x - 22, u.y - 30, 44, 4); ctx.fillStyle = f > 0.5 ? GOLD : f > 0.25 ? '#ffd66e' : '#ff5d7a'; ctx.fillRect(u.x - 22, u.y - 30, 44 * f, 4); ctx.restore(); }
    }
  }
}
