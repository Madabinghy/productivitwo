// ============================================================================
// PACK CANVAS-READY — Tourelles mobiles (à chenilles, sans pieds)
// Source de vérité : « 04 - Rendu Canvas 2D/Tourelles mobiles Canvas - Protos.dc.html ».
// À intégrer TEL QUEL — ne pas réinterpréter.
//
// La tourelle mobile = même tête/socle/cœur que la tourelle fixe (voir turrets.js),
// posée sur un essieu + 2 chenilles roulantes, SANS les pattes des niv 3-4.
//
// RÈGLE chenilles : vue de dessus ⇒ le contact au sol est DESSOUS, donc les
// crampons visibles défilent vers l'AVANT (le sens de marche), vitesse lente
// proportionnelle au déplacement. Orienter tout le châssis (rotate) vers la
// direction de déplacement avant d'appeler drawMobileChassis.
//
// API :
//   drawMobileTurret(ctx, type, lvl, T, opts?)
//     — dessine châssis (ombre + essieu + 2 chenilles) PUIS la tourelle sans pattes.
//     type : 'brasier'|'givre'|'fulgur'|'arcane' (gamme mobile)
//     opts : { size?:104, angle?:0 (visée des fûts, deg), trackSpeed?:0.28 }
//   drawMobileChassis(ctx, s, T, trackSpeed?) — châssis seul.
//   Repère : appelant fait translate(x,y) + rotate(direction de marche).
// ============================================================================

import { TURRET_COLORS, TURRET_CORE, TURRET_MUZZLE } from './turrets.js';

function hexA(h, a) { const n = parseInt(h.slice(1), 16); return 'rgba(' + ((n >> 16) & 255) + ',' + ((n >> 8) & 255) + ',' + (n & 255) + ',' + a + ')'; }
function rr(ctx, x, y, w, h, r) { ctx.beginPath(); ctx.moveTo(x + r, y); ctx.arcTo(x + w, y, x + w, y + h, r); ctx.arcTo(x + w, y + h, x, y + h, r); ctx.arcTo(x, y + h, x, y, r); ctx.arcTo(x, y, x + w, y, r); ctx.closePath(); }

function corePath(ctx, shape, R) {
  ctx.beginPath();
  if (shape === 'tri') { ctx.moveTo(0, -R); ctx.lineTo(R * 0.92, R * 0.78); ctx.lineTo(-R * 0.92, R * 0.78); ctx.closePath(); }
  else if (shape === 'diamond') { ctx.moveTo(0, -R); ctx.lineTo(R, 0); ctx.lineTo(0, R); ctx.lineTo(-R, 0); ctx.closePath(); }
  else if (shape === 'circle') { ctx.arc(0, 0, R, 0, 7); }
  else if (shape === 'star') { for (let i = 0; i < 10; i++) { const rr2 = i % 2 ? R * 0.46 : R; const a = -Math.PI / 2 + i * Math.PI / 5; ctx[i ? 'lineTo' : 'moveTo'](Math.cos(a) * rr2, Math.sin(a) * rr2); } ctx.closePath(); }
  else if (shape === 'bolt') { const p = [[0.12, -1], [-0.42, 0.08], [-0.06, 0.08], [-0.24, 1], [0.5, -0.16], [0.08, -0.16]]; p.forEach((q, i) => ctx[i ? 'lineTo' : 'moveTo'](q[0] * R, q[1] * R)); ctx.closePath(); }
}

function drawMuzzle(ctx, shape, color, w) {
  const mw = w * 1.7;
  ctx.save(); ctx.shadowBlur = 8; ctx.shadowColor = color; ctx.fillStyle = color; ctx.strokeStyle = color;
  if (shape === 'flare') { const mh = w * 1.35; ctx.beginPath(); ctx.moveTo(-mw * 0.36, mh * 0.5); ctx.lineTo(mw * 0.36, mh * 0.5); ctx.lineTo(mw * 0.5, -mh * 0.5); ctx.lineTo(-mw * 0.5, -mh * 0.5); ctx.closePath(); ctx.fill(); }
  else if (shape === 'crystal') { const r = mw * 0.5; ctx.beginPath(); ctx.moveTo(0, -r); ctx.lineTo(r, 0); ctx.lineTo(0, r); ctx.lineTo(-r, 0); ctx.closePath(); ctx.fill(); }
  else if (shape === 'tesla') { const r = mw * 0.5, hh = w * 0.9; ctx.lineWidth = 3; ctx.lineCap = 'round'; ctx.beginPath(); ctx.moveTo(-r, hh); ctx.lineTo(-r, -hh); ctx.moveTo(r, hh); ctx.lineTo(r, -hh); ctx.stroke(); }
  else if (shape === 'canister') { const r = mw * 0.52; const g = ctx.createRadialGradient(0, -r * 0.3, 0, 0, 0, r); g.addColorStop(0, color); g.addColorStop(1, '#0c0814'); ctx.fillStyle = g; ctx.beginPath(); ctx.arc(0, 0, r, 0, 7); ctx.fill(); ctx.lineWidth = 1.5; ctx.stroke(); }
  else if (shape === 'lens') { const r = mw * 0.5; ctx.lineWidth = 2.5; ctx.beginPath(); ctx.arc(0, 0, r, 0, 7); ctx.stroke(); ctx.shadowBlur = 0; ctx.globalAlpha = .5; ctx.beginPath(); ctx.arc(0, 0, r * 0.6, 0, 7); ctx.stroke(); }
  ctx.restore();
}

// une chenille (x = décalage latéral). Les crampons défilent vers l'AVANT (-y local).
function drawTrack(ctx, x, s, T, speed) {
  const w = s * 0.19, h = s * 0.79, r = w * 0.5;
  ctx.save(); ctx.translate(x, 0);
  rr(ctx, -w / 2, -h / 2, w, h, r); ctx.save(); ctx.clip();
  ctx.fillStyle = '#33333d'; ctx.fillRect(-w / 2, -h / 2, w, h);
  const period = s * 0.23; const off = ((-T * s * (speed == null ? 0.28 : speed)) % period);
  ctx.fillStyle = '#1c1c24';
  for (let y = -h / 2 - period; y < h / 2 + period; y += period) { ctx.fillRect(-w / 2, y + off, w, period * 0.55); }
  ctx.restore();
  ctx.globalAlpha = 0.82; rr(ctx, -w / 2, -h / 2, w, h, r); ctx.lineWidth = 1; ctx.strokeStyle = '#14141a'; ctx.stroke();
  ctx.restore();
}

export function drawMobileChassis(ctx, s, T, trackSpeed) {
  // ombre
  ctx.save(); ctx.globalAlpha = 0.45; ctx.filter = 'blur(4px)'; ctx.fillStyle = '#000'; ctx.beginPath(); ctx.ellipse(0, s * 0.34, s * 0.40, s * 0.13, 0, 0, 7); ctx.fill(); ctx.restore();
  // essieu
  const aw = s * 0.71, ah = s * 0.29; const ag = ctx.createLinearGradient(0, -ah / 2, 0, ah / 2); ag.addColorStop(0, '#5a5e47'); ag.addColorStop(1, 'rgba(52,55,36,0.5)');
  ctx.fillStyle = ag; rr(ctx, -aw / 2, -ah / 2, aw, ah, 4); ctx.fill();
  // 2 chenilles
  drawTrack(ctx, -s * 0.33, s, T, trackSpeed); drawTrack(ctx, s * 0.33, s, T, trackSpeed);
}

export function drawMobileTurret(ctx, type, lvl, T, opts = {}) {
  const s = opts.size || 104, color = TURRET_COLORS[type];
  drawMobileChassis(ctx, s, T, opts.trackSpeed);

  // ===== tourelle SANS pattes (halo, anneaux, particules, socle, fûts, cœur) =====
  // halo
  const haloDia = s * 1.35, haloOp = (0.12 + lvl * 0.05);
  const pp = 0.5 + 0.5 * Math.sin(T * 2 * Math.PI / (3 + lvl * 0.3));
  const haloScale = 0.96 + 0.09 * pp;
  ctx.save(); ctx.scale(haloScale, haloScale); ctx.globalAlpha = haloOp * (0.5 + 0.5 * pp);
  const hg = ctx.createRadialGradient(0, 0, 0, 0, 0, haloDia / 2); hg.addColorStop(0, hexA(color, 0.2)); hg.addColorStop(0.64, hexA(color, 0));
  ctx.fillStyle = hg; ctx.beginPath(); ctx.arc(0, 0, haloDia / 2, 0, 7); ctx.fill(); ctx.restore();

  // anneaux orbitaux
  const ringCount = [0, 1, 2, 2][lvl - 1];
  for (let i = 0; i < ringCount; i++) {
    const dia = s * (0.64 + i * 0.15), dur = 22 - i * 5, dir = i % 2 ? -1 : 1; const op = lvl >= 4 ? 0.6 : 0.42;
    ctx.save(); ctx.rotate(dir * ((T / dur) % 1) * 2 * Math.PI); ctx.globalAlpha = op; ctx.shadowBlur = 4; ctx.shadowColor = color;
    ctx.strokeStyle = hexA(color, 0.85); ctx.lineWidth = 1.1; const r = dia / 2; const per = 2 * Math.PI * r / 34; ctx.setLineDash([per * 0.5, per * 0.5]);
    ctx.beginPath(); ctx.arc(0, 0, r, 0, 7); ctx.stroke(); ctx.restore();
  }
  const moDia = s * 0.6, moOp = lvl >= 3 ? 0.5 : 0.24;
  ctx.save(); ctx.rotate(((T / 55) % 1) * 2 * Math.PI); ctx.globalAlpha = moOp; ctx.strokeStyle = hexA(color, 0.6); ctx.lineWidth = 0.8;
  const mr = moDia / 2; const mper = 2 * Math.PI * mr / 40; ctx.setLineDash([mper * 0.5, mper * 0.5]);
  ctx.beginPath(); ctx.arc(0, 0, mr, 0, 7); ctx.stroke(); ctx.restore();

  // particules
  const pCount = [0, 1, 2, 4][lvl - 1];
  for (let k = 0; k < pCount; k++) {
    const orbit = s * (0.74 + (k % 2) * 0.12), dur = 5 + k * 1.4, delay = -k * 1.3;
    const th = -Math.PI / 2 + (T + delay) * 2 * Math.PI / dur;
    const px = Math.cos(th) * orbit / 2, py = Math.sin(th) * orbit / 2; const dc = k % 2 ? '#ffffff' : color;
    ctx.save(); ctx.shadowBlur = 12; ctx.shadowColor = color; ctx.fillStyle = dc; ctx.beginPath(); ctx.arc(px, py, 3, 0, 7); ctx.fill(); ctx.restore();
  }

  // socle
  const mDia = s * 0.44;
  ctx.save(); ctx.shadowBlur = 9 + lvl * 4; ctx.shadowColor = hexA(color, 0.53);
  const mg = ctx.createRadialGradient(0, -mDia * 0.14, 0, 0, 0, mDia / 2); mg.addColorStop(0, '#241b36'); mg.addColorStop(0.82, '#0c0814');
  ctx.fillStyle = mg; ctx.beginPath(); ctx.arc(0, 0, mDia / 2, 0, 7); ctx.fill(); ctx.shadowBlur = 0;
  const ig = ctx.createRadialGradient(0, 0, mDia * 0.18, 0, 0, mDia / 2); ig.addColorStop(0, 'rgba(0,0,0,0)'); ig.addColorStop(1, 'rgba(0,0,0,.72)');
  ctx.fillStyle = ig; ctx.beginPath(); ctx.arc(0, 0, mDia / 2, 0, 7); ctx.fill();
  ctx.lineWidth = 2; ctx.strokeStyle = color; ctx.beginPath(); ctx.arc(0, 0, mDia / 2, 0, 7); ctx.stroke(); ctx.restore();

  // fûts (orientés par opts.angle, deg)
  const angle = opts.angle || 0; const baseLen = s * 0.40, baseW = s * 0.086;
  let specs;
  if (lvl === 1) specs = [{ dx: 0, len: baseLen, w: baseW }];
  else if (lvl === 2) specs = [{ dx: 0, len: baseLen * 1.14, w: baseW * 1.28 }];
  else if (lvl === 3) specs = [{ dx: -baseW * 0.95, len: baseLen * 1.06, w: baseW * 0.8 }, { dx: baseW * 0.95, len: baseLen * 1.06, w: baseW * 0.8 }];
  else specs = [{ dx: 0, len: baseLen * 1.24, w: baseW * 1.34 }, { dx: -baseW * 1.55, len: baseLen * 0.84, w: baseW * 0.62 }, { dx: baseW * 1.55, len: baseLen * 0.84, w: baseW * 0.62 }];
  ctx.save(); ctx.rotate(angle * Math.PI / 180);
  for (const b of specs) {
    ctx.save(); ctx.translate(b.dx, 0);
    const g = ctx.createLinearGradient(0, 0, 0, -b.len); g.addColorStop(0, '#1a1426'); g.addColorStop(1, '#352c48');
    ctx.fillStyle = g; ctx.strokeStyle = hexA(color, 0.33); ctx.lineWidth = 1; const rad = b.w * 0.42;
    ctx.beginPath(); ctx.moveTo(-b.w / 2, 0); ctx.lineTo(-b.w / 2, -b.len + rad); ctx.arcTo(-b.w / 2, -b.len, 0, -b.len, rad); ctx.arcTo(b.w / 2, -b.len, b.w / 2, -b.len + rad, rad); ctx.lineTo(b.w / 2, 0); ctx.closePath(); ctx.fill(); ctx.stroke();
    ctx.save(); ctx.beginPath(); ctx.moveTo(-b.w / 2, 0); ctx.lineTo(-b.w / 2, -b.len + rad); ctx.arcTo(-b.w / 2, -b.len, 0, -b.len, rad); ctx.arcTo(b.w / 2, -b.len, b.w / 2, -b.len + rad, rad); ctx.lineTo(b.w / 2, 0); ctx.closePath(); ctx.clip();
    const sh = ctx.createLinearGradient(-b.w / 2, 0, b.w / 2, 0); sh.addColorStop(0, 'rgba(255,255,255,0)'); sh.addColorStop(0.32, 'rgba(255,255,255,.15)'); sh.addColorStop(0.5, 'rgba(255,255,255,.04)'); sh.addColorStop(1, 'rgba(0,0,0,.24)');
    ctx.fillStyle = sh; ctx.fillRect(-b.w / 2, -b.len, b.w, b.len);
    ctx.fillStyle = hexA(color, 0.2); ctx.fillRect(-b.w / 2, -b.len * 0.5 - 1, b.w, 1.6);
    ctx.restore();
    ctx.translate(0, -b.len); drawMuzzle(ctx, TURRET_MUZZLE[type], color, b.w); ctx.restore();
  }
  ctx.restore();

  // cœur
  const cDia = s * 0.17 + lvl * s * 0.012, R = cDia / 2; const gp = 0.78 + 0.22 * (0.5 + 0.5 * Math.sin(T * 2 * Math.PI / 2.4));
  ctx.save(); ctx.globalAlpha = gp * 0.4; const cg = ctx.createRadialGradient(0, 0, 0, 0, 0, R * 1.35); cg.addColorStop(0, hexA(color, 0.45)); cg.addColorStop(1, hexA(color, 0));
  ctx.fillStyle = cg; ctx.beginPath(); ctx.arc(0, 0, R * 1.35, 0, 7); ctx.fill(); ctx.restore();
  ctx.save(); ctx.rotate(((T / 20) % 1) * 2 * Math.PI); ctx.shadowBlur = (5 + lvl * 2); ctx.shadowColor = color; ctx.globalAlpha = gp; ctx.fillStyle = color;
  corePath(ctx, TURRET_CORE[type], R); ctx.fill();
  ctx.shadowBlur = 0; ctx.globalAlpha = Math.min(1, gp + 0.2); ctx.lineWidth = 1.2; ctx.strokeStyle = 'rgba(255,235,210,.7)';
  corePath(ctx, TURRET_CORE[type], R); ctx.stroke(); ctx.restore();
}
