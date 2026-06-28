// Rendu des bâtiments posés (tourelles + soutien), du fantôme de pose, du faisceau de
// construction doré et des halos de zone de pose.
import { TCOL, GRID, turretStats, radarRadius, VIS, costOf } from '../config.js';
import { rayDist, compass } from '../geometry.js';
import { visionSources, canPlaceAt } from '../systems/vision.js';
import { armMuzzle } from '../systems/hero.js';

const isBuilt = (t) => t.built !== false;

function basePlate(ctx, col) {
  const base = ctx.createRadialGradient(0, -2, 1, 0, 0, 18);
  base.addColorStop(0, '#3a4150'); base.addColorStop(1, '#13161f');
  ctx.fillStyle = base; ctx.strokeStyle = col; ctx.lineWidth = 2;
  ctx.beginPath(); ctx.arc(0, 0, 16, 0, 7); ctx.fill(); ctx.shadowColor = col; ctx.shadowBlur = 8; ctx.stroke(); ctx.shadowBlur = 0;
}

// ── Sprites de tourelles offensives, fidèles à Turret.dc.html ──────────────────
// Forme du cœur par type (clip-path % du proto → coords centrées). null = disque/goutte.
const CORE_CLIP = {
  sniper: '50 2,90 50,50 98,10 50', givre: '50 2,90 50,50 98,10 50',
  brasier: '50 6,94 90,6 90', fulgur: '58 2,30 54,50 54,42 98,76 42,54 42',
  arcane: '50 2,61 38,98 38,68 60,79 96,50 75,21 96,32 60,2 38,39 38',
  calice: '22 4,78 4,98 50,72 96,28 96,2 50',
};
const MUZZLE = { brasier: 'flare', givre: 'crystal', fulgur: 'tesla', venin: 'canister', arcane: 'lens', spectre: 'wisp', calice: 'chalice', sniper: 'tesla' };

function drawCore(ctx, key, r, col, time) {
  ctx.save(); ctx.rotate((time || 0) * 0.6);
  ctx.fillStyle = col; ctx.shadowColor = col; ctx.shadowBlur = 9;
  const clip = CORE_CLIP[key];
  if (clip) {
    const pts = clip.split(',').map(s => s.trim().split(/\s+/).map(Number));
    ctx.beginPath();
    pts.forEach(([x, y], i) => { const px = ((x - 50) / 50) * r, py = ((y - 50) / 50) * r; i ? ctx.lineTo(px, py) : ctx.moveTo(px, py); });
    ctx.closePath(); ctx.fill();
  } else if (key === 'spectre') { ctx.beginPath(); ctx.ellipse(0, 0, r * 0.8, r, 0, 0, 7); ctx.fill(); }
  else { ctx.beginPath(); ctx.arc(0, 0, r * 0.92, 0, 7); ctx.fill(); }
  ctx.restore(); ctx.shadowBlur = 0;
}

// Bouche du canon (repère du canon, pointe vers -y) au bout (0, -len).
function drawMuzzle(ctx, kind, w, col, len) {
  ctx.save(); ctx.translate(0, -len); ctx.fillStyle = col; ctx.strokeStyle = col; ctx.shadowColor = col; ctx.shadowBlur = 7;
  const h = w * 1.1;
  switch (kind) {
    case 'flare': ctx.beginPath(); ctx.moveTo(-w * 0.5, 0); ctx.lineTo(w * 0.5, 0); ctx.lineTo(w * 0.85, -h); ctx.lineTo(-w * 0.85, -h); ctx.closePath(); ctx.fill(); break;
    case 'chalice': ctx.beginPath(); ctx.moveTo(-w * 0.4, 0); ctx.lineTo(w * 0.4, 0); ctx.lineTo(w * 0.8, -h); ctx.lineTo(-w * 0.8, -h); ctx.closePath(); ctx.fill(); break;
    case 'crystal': ctx.beginPath(); ctx.moveTo(0, -h); ctx.lineTo(w * 0.7, -h * 0.5); ctx.lineTo(0, 0); ctx.lineTo(-w * 0.7, -h * 0.5); ctx.closePath(); ctx.fill(); break;
    case 'tesla': ctx.lineWidth = 2; ctx.lineCap = 'round'; ctx.beginPath(); ctx.moveTo(-w * 0.45, 0); ctx.lineTo(-w * 0.45, -h); ctx.moveTo(w * 0.45, 0); ctx.lineTo(w * 0.45, -h); ctx.stroke(); break;
    case 'canister': ctx.beginPath(); ctx.arc(0, -h * 0.5, w * 0.6, 0, 7); ctx.fill(); break;
    case 'lens': ctx.lineWidth = 2; ctx.beginPath(); ctx.arc(0, -h * 0.5, w * 0.55, 0, 7); ctx.stroke(); break;
    case 'wisp': { const g = ctx.createRadialGradient(0, -h * 0.5, 0, 0, -h * 0.5, w * 0.8); g.addColorStop(0, col); g.addColorStop(1, 'transparent'); ctx.fillStyle = g; ctx.beginPath(); ctx.arc(0, -h * 0.5, w * 0.8, 0, 7); ctx.fill(); break; }
  }
  ctx.restore(); ctx.shadowBlur = 0;
}

// Canons selon le niveau (vue de dessus, émanant du centre vers -y).
function barrelSpecs(key, level) {
  const L = 19, W = 5.2;
  if (key === 'sniper') return [{ dx: 0, len: L * 1.95, w: W * 0.62 }];
  if (level <= 1) return [{ dx: 0, len: L, w: W }];
  if (level === 2) return [{ dx: 0, len: L * 1.14, w: W * 1.28 }];
  if (level === 3) return [{ dx: -W * 0.95, len: L * 1.06, w: W * 0.8 }, { dx: W * 0.95, len: L * 1.06, w: W * 0.8 }];
  return [{ dx: 0, len: L * 1.24, w: W * 1.34 }, { dx: -W * 1.55, len: L * 0.84, w: W * 0.62 }, { dx: W * 1.55, len: L * 0.84, w: W * 0.62 }];
}

function drawOffensiveTurret(ctx, key, facing, level, time) {
  const col = TCOL[key];
  // pattes d'ancrage (niv 3+)
  if (level >= 3) {
    const angs = level >= 4 ? [30, 90, 150, 210, 270, 330] : [45, 135, 225, 315];
    for (const a of angs) {
      ctx.save(); ctx.rotate(a * Math.PI / 180);
      ctx.fillStyle = '#1a1426'; ctx.strokeStyle = col + '88'; ctx.lineWidth = 1;
      ctx.beginPath(); ctx.moveTo(-2.2, 7); ctx.lineTo(2.2, 7); ctx.lineTo(1.4, 15); ctx.lineTo(-1.4, 15); ctx.closePath(); ctx.fill(); ctx.stroke();
      ctx.fillStyle = col; ctx.shadowColor = col; ctx.shadowBlur = 6; ctx.beginPath(); ctx.arc(0, 16, 2.2, 0, 7); ctx.fill(); ctx.shadowBlur = 0;
      ctx.restore();
    }
  }
  // canons orientés
  ctx.save(); ctx.rotate(facing * Math.PI / 180);
  for (const b of barrelSpecs(key, level)) {
    const grad = ctx.createLinearGradient(0, 0, 0, -b.len); grad.addColorStop(0, '#352c48'); grad.addColorStop(1, '#1a1426');
    ctx.fillStyle = grad; ctx.strokeStyle = col + '66'; ctx.lineWidth = 1;
    const r = Math.min(b.w * 0.45, 3);
    ctx.beginPath();
    ctx.moveTo(b.dx - b.w / 2, 0); ctx.lineTo(b.dx - b.w / 2, -b.len + r);
    ctx.arcTo(b.dx - b.w / 2, -b.len, b.dx, -b.len, r); ctx.arcTo(b.dx + b.w / 2, -b.len, b.dx + b.w / 2, -b.len + r, r);
    ctx.lineTo(b.dx + b.w / 2, 0); ctx.closePath(); ctx.fill(); ctx.stroke();
    ctx.save(); ctx.translate(b.dx, 0); drawMuzzle(ctx, MUZZLE[key], b.w, col, b.len); ctx.restore();
  }
  ctx.restore();
  // socle central (mount) + cœur typé
  const mg = ctx.createRadialGradient(0, -1, 0, 0, 0, 10); mg.addColorStop(0, '#241b36'); mg.addColorStop(1, '#0c0814');
  ctx.fillStyle = mg; ctx.strokeStyle = col; ctx.lineWidth = 2; ctx.shadowColor = col; ctx.shadowBlur = 9 + level * 2;
  ctx.beginPath(); ctx.arc(0, 0, 9, 0, 7); ctx.fill(); ctx.stroke(); ctx.shadowBlur = 0;
  drawCore(ctx, key, 5 + level * 0.5, col, time);
}

// Sprite d'un bâtiment (dans son repère local), orienté pour les tourelles offensives.
function turretSprite(ctx, key, facing, level, t, time) {
  const col = TCOL[key] || '#8a6cff';

  if (key === 'bercail') {
    // socle de soin sans canon : couronne + croix
    const mg = ctx.createRadialGradient(0, -1, 0, 0, 0, 12); mg.addColorStop(0, '#1c2a20'); mg.addColorStop(1, '#0a140d');
    ctx.fillStyle = mg; ctx.strokeStyle = col; ctx.lineWidth = 2; ctx.shadowColor = col; ctx.shadowBlur = 9;
    ctx.beginPath(); ctx.arc(0, 0, 12, 0, 7); ctx.fill(); ctx.stroke(); ctx.shadowBlur = 0;
    ctx.save(); ctx.rotate((time || 0) * 0.5); ctx.setLineDash([3, 4]); ctx.strokeStyle = col + '88';
    ctx.beginPath(); ctx.arc(0, 0, 8, 0, 7); ctx.stroke(); ctx.setLineDash([]); ctx.restore();
    ctx.fillStyle = col; ctx.shadowColor = col; ctx.shadowBlur = 10;
    ctx.fillRect(-2, -8, 4, 16); ctx.fillRect(-8, -2, 16, 4);
    ctx.shadowBlur = 0; return;
  }
  if (MUZZLE[key]) { drawOffensiveTurret(ctx, key, facing, level, time); return; }
  if (key === 'radar') {
    basePlate(ctx, col);
    ctx.save(); ctx.rotate((time || 0) * 2.6); // balayage tournant
    const g = ctx.createConicGradient ? ctx.createConicGradient(0, 0, 0) : null;
    if (g) { g.addColorStop(0, col + 'cc'); g.addColorStop(0.2, 'transparent'); ctx.fillStyle = g; }
    else ctx.fillStyle = col + '55';
    ctx.beginPath(); ctx.moveTo(0, 0); ctx.arc(0, 0, 14, -1.2, 0); ctx.closePath(); ctx.globalAlpha = 0.85; ctx.fill();
    ctx.restore();
    ctx.fillStyle = col; ctx.shadowColor = col; ctx.shadowBlur = 9; ctx.beginPath(); ctx.arc(0, 0, 4, 0, 7); ctx.fill(); ctx.shadowBlur = 0;
    return;
  }
  if (key === 'satellite') {
    basePlate(ctx, col);
    ctx.save(); ctx.rotate(-0.5);
    const dg = ctx.createRadialGradient(0, -2, 0, 0, 0, 12); dg.addColorStop(0, col + '55'); dg.addColorStop(1, '#0b0a06');
    ctx.fillStyle = dg; ctx.strokeStyle = col; ctx.lineWidth = 1.5;
    ctx.beginPath(); ctx.ellipse(0, 0, 12, 8, 0, 0, 7); ctx.fill(); ctx.stroke();
    ctx.restore();
    ctx.fillStyle = col; ctx.shadowColor = col; ctx.shadowBlur = 8; ctx.beginPath(); ctx.arc(0, 0, 3, 0, 7); ctx.fill(); ctx.shadowBlur = 0;
    return;
  }
  if (key === 'bouclier') {
    // barre-barrière orientée (perpendiculaire au facing)
    ctx.save(); ctx.rotate(facing * Math.PI / 180);
    ctx.fillStyle = '#2a313f'; ctx.fillRect(-3, -2, 6, 14); // pied
    const sg = ctx.createLinearGradient(0, -8, 0, 0); sg.addColorStop(0, col); sg.addColorStop(1, col + '22');
    ctx.fillStyle = sg; ctx.strokeStyle = col; ctx.lineWidth = 2; ctx.shadowColor = col; ctx.shadowBlur = 12;
    ctx.beginPath(); ctx.ellipse(0, -8, 30, 9, 0, Math.PI, 0); ctx.fill(); ctx.stroke();
    ctx.restore(); return;
  }

  // tourelle offensive : socle + canon orienté + cœur + badge niveau
  basePlate(ctx, col);
  ctx.save(); ctx.rotate(facing * Math.PI / 180);
  const bg = ctx.createLinearGradient(-4, 0, 4, 0); bg.addColorStop(0, '#8a96b3'); bg.addColorStop(1, '#3a4150');
  ctx.fillStyle = bg; ctx.strokeStyle = col; ctx.lineWidth = 1;
  ctx.beginPath(); ctx.rect(-4, -20, 8, 22); ctx.fill(); ctx.stroke();
  ctx.fillStyle = col; ctx.shadowColor = col; ctx.shadowBlur = 8; ctx.beginPath(); ctx.arc(0, -20, 3, 0, 7); ctx.fill();
  ctx.restore();
  ctx.fillStyle = col; ctx.shadowColor = col; ctx.shadowBlur = 9; ctx.beginPath(); ctx.arc(0, 0, 4.5, 0, 7); ctx.fill(); ctx.shadowBlur = 0;
  ctx.save(); ctx.translate(11, 11); ctx.fillStyle = '#0d0a18'; ctx.strokeStyle = col; ctx.lineWidth = 1;
  ctx.beginPath(); ctx.arc(0, 0, 7, 0, 7); ctx.fill(); ctx.stroke();
  ctx.fillStyle = col; ctx.font = "9px 'Chakra Petch', monospace"; ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
  ctx.fillText(String(level), 0, 0.5); ctx.restore();
}

export function drawPlaced(game, ctx, th, t) {
  for (const p of game.ui.placed) {
    if (p.cat !== 'turret') continue;
    const col = TCOL[p.key] || th.accent;
    const facing = game.AIM[p.id] != null ? game.AIM[p.id] : (p.face || 0);
    const ts = turretStats(p);
    const building = !isBuilt(p); const isSite = game._buildId === p.id; const bprog = Math.max(0, Math.min(1, p.prog || 0));

    const sel = game.ui.selId === p.id;

    // anneaux au sol : radar (révélation), bercail (soin)
    if (!building && p.key === 'radar') {
      const rr = radarRadius(p);
      ctx.save(); ctx.setLineDash([4, 5]); ctx.strokeStyle = col + (sel ? 'aa' : '66'); ctx.lineWidth = 1.5;
      const g = ctx.createRadialGradient(p.x, p.y, 0, p.x, p.y, rr); g.addColorStop(0, col + '12'); g.addColorStop(0.7, 'transparent');
      ctx.fillStyle = g; ctx.beginPath(); ctx.arc(p.x, p.y, rr, 0, 7); ctx.fill(); ctx.beginPath(); ctx.arc(p.x, p.y, rr, 0, 7); ctx.stroke();
      ctx.setLineDash([]); ctx.restore();
    }
    if (!building && ts.heal) {
      ctx.save(); ctx.strokeStyle = '#7bff9b55'; ctx.lineWidth = 1.5;
      const g = ctx.createRadialGradient(p.x, p.y, 0, p.x, p.y, ts.radius); g.addColorStop(0, '#7bff9b16'); g.addColorStop(0.72, 'transparent');
      ctx.fillStyle = g; ctx.beginPath(); ctx.arc(p.x, p.y, ts.radius, 0, 7); ctx.fill(); ctx.beginPath(); ctx.arc(p.x, p.y, ts.radius, 0, 7); ctx.stroke();
      ctx.restore();
    }

    // cône de portée (tourelles bâties, offensives)
    if (!building && !ts.support && !ts.heal && ts.range > 0) {
      const fr = facing * Math.PI / 180; const effR = rayDist(game.WALLS, p.x, p.y, Math.sin(fr), -Math.cos(fr), ts.range);
      ctx.save(); ctx.translate(p.x, p.y); ctx.rotate((facing - 90) * Math.PI / 180);
      const g = ctx.createLinearGradient(0, 0, effR, 0); g.addColorStop(0, col + (sel ? '4a' : '24')); g.addColorStop(0.8, 'transparent');
      ctx.fillStyle = g; ctx.beginPath(); ctx.moveTo(0, 0); ctx.lineTo(effR, -effR * 0.35); ctx.lineTo(effR, effR * 0.35); ctx.closePath(); ctx.fill();
      ctx.restore();
    }

    ctx.save(); ctx.translate(p.x, p.y);
    if (building) { ctx.globalAlpha = 0.28 + bprog * 0.42; }
    turretSprite(ctx, p.key, facing, p.level, p, t);
    ctx.restore();

    // état chantier : anneau + barre + %
    if (building) {
      ctx.save(); ctx.translate(p.x, p.y);
      ctx.setLineDash([6, 5]); ctx.strokeStyle = isSite ? th.flame : '#8a96b3'; ctx.lineWidth = 2;
      if (isSite) { ctx.shadowColor = th.flame; ctx.shadowBlur = 14; }
      ctx.beginPath(); ctx.arc(0, 0, 24, 0, 7); ctx.stroke(); ctx.setLineDash([]); ctx.shadowBlur = 0;
      // barre
      ctx.fillStyle = 'rgba(0,0,0,.65)'; ctx.fillRect(-20, -32, 40, 5);
      const bg = ctx.createLinearGradient(-20, 0, 20, 0); bg.addColorStop(0, '#ff9e3d'); bg.addColorStop(1, th.flame);
      ctx.fillStyle = bg; ctx.fillRect(-20, -32, 40 * bprog, 5);
      // %
      ctx.fillStyle = th.flame; ctx.font = "11px 'Chakra Petch', monospace"; ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
      ctx.fillText((isSite ? (game._buildStall ? '⏸ ' : '⚒ ') : '') + Math.round(bprog * 100) + '%', 0, 0);
      ctx.restore();
    } else {
      // barre de vie tourelle (si endommagée)
      const f = Math.max(0, Math.min(1, (p.hp == null ? p.maxHp : p.hp) / (p.maxHp || 120)));
      if (f < 1) {
        ctx.save(); ctx.translate(p.x, p.y);
        ctx.fillStyle = 'rgba(0,0,0,.6)'; ctx.fillRect(-18, -26, 36, 4);
        ctx.fillStyle = f > 0.5 ? '#7bff9b' : f > 0.25 ? '#ffd66e' : '#ff5d7a'; ctx.fillRect(-18, -26, 36 * f, 4);
        ctx.restore();
      }
    }
  }
}

export function drawPlaceHalos(game, ctx, th) {
  if (!(game.ui.sel && !game.ui.selId)) return;
  for (const sv of visionSources(game)) {
    const col = sv.kind === 'radar' ? TCOL.radar : th.flame;
    ctx.save(); ctx.setLineDash([6, 6]); ctx.strokeStyle = col + '66'; ctx.lineWidth = 1.5;
    const g = ctx.createRadialGradient(sv.x, sv.y, 0, sv.x, sv.y, sv.r);
    g.addColorStop(0, col + '12'); g.addColorStop(0.7, 'transparent');
    ctx.fillStyle = g; ctx.beginPath(); ctx.arc(sv.x, sv.y, sv.r, 0, 7); ctx.fill(); ctx.stroke();
    ctx.setLineDash([]); ctx.restore();
  }
}

export function drawGhost(game, ctx, th, t) {
  if (!(game.ui.sel && !game.ui.selId) || !game._ghostW) return;
  const { wx, wy } = game._ghostW; const gx = Math.round(wx / GRID) * GRID, gy = Math.round(wy / GRID) * GRID;
  const ok = canPlaceAt(game, wx, wy); const key = game.ui.sel.key; const vc = ok ? '#7bff9b' : '#ff5d7a';
  let face = 0, bd = 1e9; for (const en of game.ENTRY) { const p = game.NODES[en]; const d = Math.hypot(p.x - gx, p.y - gy); if (d < bd) { bd = d; face = compass(p.x - gx, p.y - gy); } }
  ctx.save(); ctx.translate(gx, gy); ctx.globalAlpha = 0.75;
  // anneau de validité
  ctx.setLineDash(ok ? [] : [6, 5]); ctx.strokeStyle = vc; ctx.lineWidth = 2; ctx.shadowColor = vc; ctx.shadowBlur = 12;
  const g = ctx.createRadialGradient(0, 0, 0, 0, 0, 40); g.addColorStop(0, vc + '26'); g.addColorStop(0.7, 'transparent');
  ctx.fillStyle = g; ctx.beginPath(); ctx.arc(0, 0, 40, 0, 7); ctx.fill(); ctx.beginPath(); ctx.arc(0, 0, 40, 0, 7); ctx.stroke();
  ctx.setLineDash([]); ctx.shadowBlur = 0;
  // silhouette
  turretSprite(ctx, key, face, 1, { key, level: 1 }, t);
  ctx.restore();
  // coût
  const c = costOf(key);
  ctx.save(); ctx.translate(gx, gy - 50);
  ctx.font = "10px 'Chakra Petch', monospace"; ctx.textAlign = 'center';
  const label = '✦ ' + c.mass + ' · ' + c.time + 's'; const w = ctx.measureText(label).width + 14;
  ctx.fillStyle = 'rgba(8,6,14,.82)'; ctx.strokeStyle = vc + '88'; ctx.lineWidth = 1;
  ctx.beginPath(); ctx.rect(-w / 2, -11, w, 18); ctx.fill(); ctx.stroke();
  ctx.fillStyle = ok ? '#bfe6c2' : '#ffb3c1'; ctx.textBaseline = 'middle'; ctx.fillText(label, 0, -1.5);
  ctx.restore();
}

export function drawBuildBeam(game, ctx, t) {
  if (game._buildId == null) return;
  const site = game.ui.placed.find(p => p.id === game._buildId); if (!site) return;
  const H = game.HERO; const m = armMuzzle(H, site.x, site.y, 1); const j = 0.6 + 0.4 * Math.sin(t * 13);
  ctx.save(); ctx.lineCap = 'round'; ctx.shadowColor = '#ffce5e'; ctx.shadowBlur = 7;
  ctx.strokeStyle = '#ffce5e'; ctx.globalAlpha = 0.28 * j; ctx.lineWidth = 7;
  ctx.beginPath(); ctx.moveTo(m.x, m.y); ctx.lineTo(site.x, site.y); ctx.stroke();
  ctx.strokeStyle = '#fff3cf'; ctx.globalAlpha = 0.7 + 0.3 * j; ctx.lineWidth = 2.4;
  ctx.beginPath(); ctx.moveTo(m.x, m.y); ctx.lineTo(site.x, site.y); ctx.stroke();
  ctx.restore();
}
