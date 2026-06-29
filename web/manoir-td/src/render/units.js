// Rendu du Cuirassé-tortue (cf. CUIRASSE-TORTUE-specs.md + proto Artillerie).
// Transition animée pilotée par u.t (0 = mobile, 1 = déployée) :
//   pattes/tête/canons rentrent quand t→1, lumière OR→VERT, écailles s'écartent, liseré vert,
//   cœur grossit. MOBILE : canons posés sur les écailles, recul au tir. DÉPLOYÉE : aura + motes,
//   badge INCREVABLE (PV masqués).
import { TORTUE } from '../config.js';
import { drawArt } from './art.js';

const STEEL_HI = '#8a96b3', STEEL = '#566079', STEEL_DK = '#161220';
const GOLD = '#ffce5e', GOLD_D = '#ff9e3d', GREEN = '#6effa8', GREEN_D = '#1d9c5e';
const TORTUE_ART_SCALE = 0.34;

// État MOBILE : sprite PNG designé (carapace orientée vers la menace) + éclairs de bouche.
// Repère déjà translaté sur l'unité. Renvoie false si l'image n'est pas chargée → fallback canvas.
function drawTortueMobileArt(ctx, u) {
  if (!drawArt(ctx, 'cuirasse-tortue', TORTUE_ART_SCALE, (u.carapace || 180) - 180)) return false;
  if (u.cannons) for (const c of u.cannons) {
    if (!(c.flash > 0)) continue;
    const mdir = ((u.carapace || 180) + (c.mount || 0)) * Math.PI / 180, r = 24;
    ctx.save(); ctx.fillStyle = '#fff3c4'; ctx.shadowColor = GOLD_D; ctx.shadowBlur = 10;
    ctx.beginPath(); ctx.arc(Math.sin(mdir) * r, -Math.cos(mdir) * r, 4, 0, 7); ctx.fill(); ctx.restore();
  }
  return true;
}

// interpolation linéaire entre deux couleurs hexadécimales
function hexLerp(a, b, t) {
  const p = h => [1, 3, 5].map(i => parseInt(h.slice(i, i + 2), 16));
  const A = p(a), B = p(b);
  return '#' + A.map((v, i) => Math.round(v + (B[i] - v) * t).toString(16).padStart(2, '0')).join('');
}

function plates(ctx, R, t, seam) {
  // dôme acier
  const g = ctx.createRadialGradient(0, -R * 0.3, 2, 0, 0, R);
  g.addColorStop(0, STEEL_HI); g.addColorStop(0.55, STEEL); g.addColorStop(1, STEEL_DK);
  ctx.fillStyle = g; ctx.strokeStyle = STEEL_HI + 'aa'; ctx.lineWidth = 2;
  ctx.beginPath(); ctx.arc(0, 0, R, 0, 7); ctx.fill(); ctx.stroke();
  // 6 écailles (s'écartent légèrement quand déployée)
  const pr = R * 0.62 + 3 * t;
  for (let i = 0; i < 6; i++) {
    const a = (i / 6) * Math.PI * 2 - Math.PI / 2, px = Math.cos(a) * pr, py = Math.sin(a) * pr;
    ctx.save(); ctx.translate(px, py); ctx.rotate(a + Math.PI / 2);
    const pg = ctx.createLinearGradient(0, -8, 0, 8); pg.addColorStop(0, STEEL_HI); pg.addColorStop(0.55, STEEL); pg.addColorStop(1, STEEL_DK);
    ctx.fillStyle = pg; ctx.strokeStyle = STEEL_HI + '55'; ctx.lineWidth = 1;
    ctx.beginPath(); ctx.ellipse(0, 0, 6, 8, 0, 0, 7); ctx.fill(); ctx.stroke();
    ctx.restore();
  }
  ctx.strokeStyle = STEEL_HI + '88'; ctx.lineWidth = 1.2; ctx.beginPath(); ctx.arc(0, 0, R * 0.52, 0, 7); ctx.stroke();
  // liseré vert quand déployée
  if (t > 0.04) { ctx.save(); ctx.globalAlpha = t * 0.85; ctx.strokeStyle = GREEN; ctx.lineWidth = 2; ctx.shadowColor = GREEN; ctx.shadowBlur = 10; ctx.beginPath(); ctx.arc(0, 0, R * 0.8, 0, 7); ctx.stroke(); ctx.restore(); }
}

export function drawUnits(game, ctx, th, t) {
  for (const u of game.ui.placed) {
    if (u.cat !== 'unit') continue;
    const built = u.built !== false, sel = game.ui.selId === u.id;
    const tt = u.t != null ? u.t : (u.deployed ? 1 : 0);   // avancement déploiement
    const dep = tt > 0.5;
    const accent = hexLerp(GOLD, GREEN, tt), accentD = hexLerp(GOLD_D, GREEN_D, tt);

    // aura de soin (déployée) ou cercle de portée (sélectionnée mobile)
    if (built && tt > 0.04) {
      ctx.save();
      const ar = TORTUE.healRadius * (0.6 + 0.4 * tt);
      const g = ctx.createRadialGradient(u.x, u.y, 0, u.x, u.y, ar);
      g.addColorStop(0, GREEN + '20'); g.addColorStop(0.72, 'transparent');
      ctx.globalAlpha = tt; ctx.fillStyle = g; ctx.beginPath(); ctx.arc(u.x, u.y, ar, 0, 7); ctx.fill();
      ctx.setLineDash([6, 8]); ctx.strokeStyle = GREEN + '66'; ctx.lineWidth = 1.5; ctx.beginPath(); ctx.arc(u.x, u.y, ar, 0, 7); ctx.stroke(); ctx.setLineDash([]);
      if (dep) for (let k = 0; k < 5; k++) { const ph = (t * 0.6 + k / 5) % 1, a = k * 1.3, rr = ar * 0.5; const mx = u.x + Math.cos(a) * rr * (0.4 + ph * 0.5), my = u.y + rr * 0.3 - ph * 60; ctx.globalAlpha = (1 - ph) * 0.8; ctx.fillStyle = GREEN; ctx.font = '11px monospace'; ctx.fillText('+', mx, my); }
      ctx.globalAlpha = 1; ctx.restore();
    } else if (built && sel) {
      ctx.save(); ctx.strokeStyle = GOLD + '44'; ctx.lineWidth = 1; ctx.setLineDash([4, 6]); ctx.beginPath(); ctx.arc(u.x, u.y, TORTUE.range, 0, 7); ctx.stroke(); ctx.setLineDash([]); ctx.restore();
    }

    ctx.save(); ctx.translate(u.x, u.y);
    if (!built) ctx.globalAlpha = 0.3 + (u.prog || 0) * 0.5;
    ctx.fillStyle = 'rgba(0,0,0,.45)'; ctx.beginPath(); ctx.ellipse(0, 14, 22, 6, 0, 0, 7); ctx.fill();

    const R = 20, ext = 1 - tt;

    // mobile complète : sprite PNG designé (carapace orientée), sinon corps canvas animé
    const pngBody = built && tt < 0.04 && drawTortueMobileArt(ctx, u);

    // pattes (corps fixe) — rentrent quand déployée
    if (!pngBody && ext > 0.05) {
      ctx.globalAlpha = (built ? 1 : ctx.globalAlpha) * (1 - 0.92 * tt);
      ctx.fillStyle = STEEL; ctx.strokeStyle = STEEL_HI; ctx.lineWidth = 1;
      const legR = R * (1 - 0.35 * tt);
      for (const a of [46, 134, 226, 314]) { const r = a * Math.PI / 180; ctx.save(); ctx.translate(Math.sin(r) * legR, -Math.cos(r) * legR); ctx.rotate(r); ctx.beginPath(); ctx.ellipse(0, 4, 4 * ext + 1, 6 * ext + 1, 0, 0, 7); ctx.fill(); ctx.stroke(); ctx.restore(); }
      ctx.globalAlpha = built ? 1 : 0.3 + (u.prog || 0) * 0.5;
    }

    // tête fixe au nord (ne tourne pas avec la carapace) — rentre quand déployée
    if (!pngBody && ext > 0.05) {
      ctx.save(); ctx.globalAlpha = (built ? 1 : ctx.globalAlpha) * (1 - 0.92 * tt);
      const hy = -R - 1 + 12 * tt;
      ctx.fillStyle = STEEL; ctx.strokeStyle = STEEL_HI; ctx.lineWidth = 1; ctx.beginPath(); ctx.ellipse(0, hy, 6 * ext + 1, 5 * ext + 1, 0, 0, 7); ctx.fill(); ctx.stroke();
      ctx.fillStyle = accent; ctx.shadowColor = accent; ctx.shadowBlur = 6; ctx.fillRect(-3 * ext, hy - 1, 6 * ext, 2); ctx.shadowBlur = 0; ctx.restore();
    }

    // canons (posés sur les écailles, mount tourne avec la carapace, visée indépendante, recul)
    if (!pngBody && ext > 0.05 && u.cannons) {
      for (const c of u.cannons) {
        const mdir = ((u.carapace || 180) + (c.mount || 0)) * Math.PI / 180;
        const bx = Math.sin(mdir) * (R * 0.92), by = -Math.cos(mdir) * (R * 0.92);
        const arad = (c.angle || 0) * Math.PI / 180, ax = Math.sin(arad), ay = -Math.cos(arad);
        const len = (5 + 13 * ext), back = (c.recoil || 0) * 4;
        const tx = bx + ax * (len - back), ty = by + ay * (len - back);
        ctx.globalAlpha = (built ? 1 : 0.3 + (u.prog || 0) * 0.5) * Math.min(1, ext * 1.4);
        // socle
        ctx.fillStyle = STEEL_DK; ctx.strokeStyle = STEEL_HI; ctx.lineWidth = 1; ctx.beginPath(); ctx.arc(bx, by, 4, 0, 7); ctx.fill(); ctx.stroke();
        // fût
        ctx.strokeStyle = '#3a3a45'; ctx.lineWidth = 5; ctx.lineCap = 'round'; ctx.beginPath(); ctx.moveTo(bx, by); ctx.lineTo(tx, ty); ctx.stroke();
        ctx.strokeStyle = STEEL_HI; ctx.lineWidth = 2; ctx.beginPath(); ctx.moveTo(bx, by); ctx.lineTo(tx, ty); ctx.stroke();
        // bouche
        ctx.save(); ctx.translate(tx, ty); ctx.rotate(arad); ctx.fillStyle = STEEL_DK; ctx.strokeStyle = accent; ctx.lineWidth = 1.5; ctx.fillRect(-3, -3, 6, 6); ctx.strokeRect(-3, -3, 6, 6); ctx.restore();
        if (c.flash > 0) { ctx.fillStyle = '#fff3c4'; ctx.shadowColor = GOLD_D; ctx.shadowBlur = 9; ctx.beginPath(); ctx.arc(tx + ax * 3, ty + ay * 3, 3.5, 0, 7); ctx.fill(); ctx.shadowBlur = 0; }
      }
      ctx.globalAlpha = built ? 1 : 0.3 + (u.prog || 0) * 0.5;
    }

    if (!pngBody) {
      // carapace (pivote ; écailles + liseré vert pilotés par tt)
      ctx.save(); ctx.rotate((u.carapace || 180) * Math.PI / 180);
      plates(ctx, R - 2 * tt, tt);
      ctx.restore();

      // cœur central lumineux (grossit + OR→VERT quand déployée)
      const cr = 7 + 2 * tt;
      const cg = ctx.createRadialGradient(0, 0, 0, 0, 0, cr + 2); cg.addColorStop(0, '#fff'); cg.addColorStop(0.4, accent); cg.addColorStop(1, accentD);
      ctx.fillStyle = cg; ctx.shadowColor = accent; ctx.shadowBlur = 12; ctx.beginPath(); ctx.arc(0, 0, cr, 0, 7); ctx.fill(); ctx.shadowBlur = 0;
      ctx.strokeStyle = accent + 'aa'; ctx.lineWidth = 1.5; ctx.beginPath(); ctx.arc(0, 0, cr + 4, 0, 7); ctx.stroke();
    }
    ctx.restore();

    // sélection
    if (sel) { ctx.save(); ctx.strokeStyle = accent; ctx.lineWidth = 2; ctx.setLineDash([6, 6]); ctx.translate(u.x, u.y); ctx.rotate(t * 0.6); ctx.beginPath(); ctx.arc(0, 0, 28, 0, 7); ctx.stroke(); ctx.setLineDash([]); ctx.restore(); }

    // PV (mobile) / badge INCREVABLE (déployé) / % chantier
    if (!built) {
      const bp = Math.max(0, Math.min(1, u.prog || 0)), isSite = game._buildId === u.id;
      ctx.save(); ctx.translate(u.x, u.y); ctx.setLineDash([6, 5]); ctx.strokeStyle = isSite ? th.flame : '#8a96b3'; ctx.lineWidth = 2; ctx.beginPath(); ctx.arc(0, 0, 27, 0, 7); ctx.stroke(); ctx.setLineDash([]);
      ctx.fillStyle = th.flame; ctx.font = "11px 'Chakra Petch', monospace"; ctx.textAlign = 'center'; ctx.textBaseline = 'middle'; ctx.fillText((isSite ? '⚒ ' : '') + Math.round(bp * 100) + '%', 0, 0); ctx.restore();
    } else if (dep) {
      ctx.save(); ctx.globalAlpha = tt; ctx.textAlign = 'center';
      ctx.fillStyle = 'rgba(10,30,18,.85)'; ctx.fillRect(u.x - 32, u.y - 36, 64, 13); ctx.fillStyle = GREEN; ctx.font = "8px 'Chakra Petch', monospace"; ctx.fillText('⛨ INCREVABLE', u.x, u.y - 27); ctx.restore();
    } else {
      const f = Math.max(0, Math.min(1, (u.hp == null ? u.maxHp : u.hp) / (u.maxHp || TORTUE.hp)));
      if (f < 1) { ctx.save(); ctx.globalAlpha = 1 - tt; ctx.fillStyle = 'rgba(0,0,0,.6)'; ctx.fillRect(u.x - 22, u.y - 30, 44, 4); ctx.fillStyle = f > 0.5 ? GOLD : f > 0.25 ? '#ffd66e' : '#ff5d7a'; ctx.fillRect(u.x - 22, u.y - 30, 44 * f, 4); ctx.restore(); }
    }
  }
}
