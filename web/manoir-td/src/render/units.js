// Rendu du Cuirassé-tortue — 100% Canvas via le pack canvas-ready (tortue.js).
// drawTortue dessine corps (tête + 4 pattes orientés par `face`) + carapace (`shellRot`)
// + 4 canons visant chacun (`aim[]`) avec recul, marche (`gaitAmp`) et déploiement (`t`).
// drawTortueAura dessine l'aura de soin en mode déployé.
import { TORTUE, unitStats } from '../config.js';
import { drawTortue, drawTortueAura } from './canvas-ready/tortue.js';
import { drawMobileTurret } from './canvas-ready/turrets-mobiles.js';
import { drawInfantry } from './canvas-ready/commander.js';

const GOLD = '#ffce5e', GREEN = '#6effa8';
const TORTUE_SCALE = 1.25;

export function drawUnits(game, ctx, th, t) {
  for (const u of game.ui.placed) {
    if (u.cat !== 'unit') continue;
    if (u.key === 'tortue') { drawTortueUnit(game, ctx, th, t, u); continue; }
    const st = unitStats(u.key); if (!st) continue;
    if (st.kind === 'mobile') drawMobileUnit(game, ctx, th, t, u, st);
    else if (st.kind === 'infantry') drawInfantryUnit(game, ctx, th, t, u, st);
  }
}

// Fantassin : jambes orientées vers la marche, torse vers la visée (le sprite tire vers son
// +y → on ajoute 180° pour convertir l'angle compass en rotation canvas).
function drawInfantryUnit(game, ctx, th, t, u, st) {
  const built = u.built !== false, sel = game.ui.selId === u.id, col = st.color || '#7fd8ff';
  if (built && sel) {
    ctx.save(); ctx.strokeStyle = col + '44'; ctx.lineWidth = 1; ctx.setLineDash([4, 6]);
    ctx.beginPath(); ctx.arc(u.x, u.y, st.range, 0, 7); ctx.stroke(); ctx.setLineDash([]); ctx.restore();
  }
  ctx.save(); ctx.translate(u.x, u.y);
  if (!built) ctx.globalAlpha = 0.3 + (u.prog || 0) * 0.5;
  const bodyAng = ((u.aim || 0) + 180) * Math.PI / 180, legAng = ((u.bodyDir || u.aim || 0) + 180) * Math.PI / 180;
  drawInfantry(ctx, st.size || 30, t, st.variant, bodyAng, legAng, !!u.walking, (u.firing || 0) > 0);
  ctx.restore();
  if (sel) {
    ctx.save(); ctx.strokeStyle = col; ctx.lineWidth = 2; ctx.setLineDash([6, 6]);
    ctx.translate(u.x, u.y); ctx.rotate(t * 0.6); ctx.beginPath(); ctx.arc(0, 0, 22, 0, 7); ctx.stroke(); ctx.setLineDash([]); ctx.restore();
  }
  const f = Math.max(0, Math.min(1, (u.hp == null ? u.maxHp : u.hp) / (u.maxHp || st.hp)));
  if (built && f < 1) { ctx.save(); ctx.fillStyle = 'rgba(0,0,0,.6)'; ctx.fillRect(u.x - 16, u.y - 26, 32, 3.5); ctx.fillStyle = f > 0.5 ? col : f > 0.25 ? '#ffd66e' : '#ff5d7a'; ctx.fillRect(u.x - 16, u.y - 26, 32 * f, 3.5); ctx.restore(); }
}

// Tourelle mobile (char à chenilles) : châssis orienté vers la marche + tête qui vise.
function drawMobileUnit(game, ctx, th, t, u, st) {
  const built = u.built !== false, sel = game.ui.selId === u.id, col = st.color || GOLD;
  if (built && sel) {
    ctx.save(); ctx.strokeStyle = col + '44'; ctx.lineWidth = 1; ctx.setLineDash([4, 6]);
    ctx.beginPath(); ctx.arc(u.x, u.y, st.range, 0, 7); ctx.stroke(); ctx.setLineDash([]); ctx.restore();
  }
  ctx.save(); ctx.translate(u.x, u.y);
  if (!built) ctx.globalAlpha = 0.3 + (u.prog || 0) * 0.5;
  ctx.rotate((u.bodyDir || 0) * Math.PI / 180);
  drawMobileTurret(ctx, st.type, u.level || 1, t, { size: st.size || 60, angle: (u.aim || 0) - (u.bodyDir || 0), trackSpeed: u.walking ? 0.5 : 0.14 });
  ctx.restore();
  if (sel) {
    ctx.save(); ctx.strokeStyle = col; ctx.lineWidth = 2; ctx.setLineDash([6, 6]);
    ctx.translate(u.x, u.y); ctx.rotate(t * 0.6); ctx.beginPath(); ctx.arc(0, 0, 30, 0, 7); ctx.stroke(); ctx.setLineDash([]); ctx.restore();
  }
  const f = Math.max(0, Math.min(1, (u.hp == null ? u.maxHp : u.hp) / (u.maxHp || st.hp)));
  if (built && f < 1) { ctx.save(); ctx.fillStyle = 'rgba(0,0,0,.6)'; ctx.fillRect(u.x - 22, u.y - 34, 44, 4); ctx.fillStyle = f > 0.5 ? col : f > 0.25 ? '#ffd66e' : '#ff5d7a'; ctx.fillRect(u.x - 22, u.y - 34, 44 * f, 4); ctx.restore(); }
}

function drawTortueUnit(game, ctx, th, t, u) {
  {
    const built = u.built !== false, sel = game.ui.selId === u.id;
    const tt = u.t != null ? u.t : (u.deployed ? 1 : 0);   // avancement déploiement
    const dep = tt > 0.5;

    // aura de soin (déployée) — sinon cercle de portée si sélectionnée (mobile)
    if (built && tt > 0.04) {
      ctx.save(); ctx.translate(u.x, u.y); drawTortueAura(ctx, tt, TORTUE.healRadius, t); ctx.restore();
    } else if (built && sel) {
      ctx.save(); ctx.strokeStyle = GOLD + '44'; ctx.lineWidth = 1; ctx.setLineDash([4, 6]);
      ctx.beginPath(); ctx.arc(u.x, u.y, TORTUE.range, 0, 7); ctx.stroke(); ctx.setLineDash([]); ctx.restore();
    }

    // corps de la tortue (pack canvas-ready)
    ctx.save(); ctx.translate(u.x, u.y);
    if (!built) ctx.globalAlpha = 0.3 + (u.prog || 0) * 0.5;
    const cannons = u.cannons || [];
    drawTortue(ctx, t, {
      t: tt,
      face: ((u.bodyDir || 0)) * Math.PI / 180,      // orientation du corps (marche)
      shellRot: (u.carapace != null ? u.carapace : 180),
      aim: cannons.length ? cannons.map(c => c.angle) : null,
      recoil: cannons.length ? cannons.map(c => c.recoil || 0) : [0, 0, 0, 0],
      gaitAmp: u.moveTarget ? 1 : 0,
      clock: t,
      scale: TORTUE_SCALE,
    });
    ctx.restore();

    // sélection
    if (sel) {
      ctx.save(); ctx.strokeStyle = dep ? GREEN : GOLD; ctx.lineWidth = 2; ctx.setLineDash([6, 6]);
      ctx.translate(u.x, u.y); ctx.rotate(t * 0.6); ctx.beginPath(); ctx.arc(0, 0, 30, 0, 7); ctx.stroke(); ctx.setLineDash([]); ctx.restore();
    }

    // état chantier (%) / badge INCREVABLE (déployé) / barre de PV (mobile)
    if (!built) {
      const bp = Math.max(0, Math.min(1, u.prog || 0)), isSite = game._buildId === u.id;
      ctx.save(); ctx.translate(u.x, u.y); ctx.setLineDash([6, 5]); ctx.strokeStyle = isSite ? th.flame : '#8a96b3'; ctx.lineWidth = 2; ctx.beginPath(); ctx.arc(0, 0, 27, 0, 7); ctx.stroke(); ctx.setLineDash([]);
      ctx.fillStyle = th.flame; ctx.font = "11px 'Chakra Petch', monospace"; ctx.textAlign = 'center'; ctx.textBaseline = 'middle'; ctx.fillText((isSite ? '⚒ ' : '') + Math.round(bp * 100) + '%', 0, 0); ctx.restore();
    } else if (dep) {
      ctx.save(); ctx.globalAlpha = tt; ctx.textAlign = 'center';
      ctx.fillStyle = 'rgba(10,30,18,.85)'; ctx.fillRect(u.x - 32, u.y - 40, 64, 13); ctx.fillStyle = GREEN; ctx.font = "8px 'Chakra Petch', monospace"; ctx.fillText('⛨ INCREVABLE', u.x, u.y - 31); ctx.restore();
    } else {
      const f = Math.max(0, Math.min(1, (u.hp == null ? u.maxHp : u.hp) / (u.maxHp || TORTUE.hp)));
      if (f < 1) { ctx.save(); ctx.fillStyle = 'rgba(0,0,0,.6)'; ctx.fillRect(u.x - 22, u.y - 34, 44, 4); ctx.fillStyle = f > 0.5 ? GOLD : f > 0.25 ? '#ffd66e' : '#ff5d7a'; ctx.fillRect(u.x - 22, u.y - 34, 44 * f, 4); ctx.restore(); }
    }
  }
}
