// ============================================================================
// PACK CANVAS-READY — Tourelles fixes (Brasier, Givre, Fulgur, Venin, Arcane, Sniper)
// Source de vérité : « 04 - Rendu Canvas 2D/Tourelle Canvas - Comparatif.dc.html ».
// À intégrer TEL QUEL (mêmes formes, mêmes constantes) — ne pas réinterpréter.
//
// API :
//   drawTurret(ctx, cx, cy, type, lvl, T, opts?)
//     type  : 'brasier'|'givre'|'fulgur'|'venin'|'arcane'|'sniper'
//     lvl   : 1..4  (le design CHANGE par niveau : fûts, anneaux, particules, pattes)
//     T     : temps en secondes (Date.now()/1000)
//     opts  : { size?:150, angle?:0 (deg, orientation des fûts), color?:override }
//   TURRET_COLORS / TURRET_CORE / TURRET_MUZZLE : tables partagées.
// ============================================================================

export const TURRET_COLORS = { brasier:'#ff6b3d', givre:'#3df0ff', fulgur:'#ffe14d', venin:'#6fff5a', arcane:'#c77dff', sniper:'#cfe7ff' };
export const TURRET_CORE   = { brasier:'tri', givre:'diamond', fulgur:'bolt', venin:'circle', arcane:'star', sniper:'diamond' };
export const TURRET_MUZZLE = { brasier:'flare', givre:'crystal', fulgur:'tesla', venin:'canister', arcane:'lens', sniper:'tesla' };

function hexA(h, a) { const n = parseInt(h.slice(1), 16); return 'rgba(' + ((n >> 16) & 255) + ',' + ((n >> 8) & 255) + ',' + (n & 255) + ',' + a + ')'; }

function corePath(ctx, shape, R) {
  ctx.beginPath();
  if (shape === 'tri') { ctx.moveTo(0, -R); ctx.lineTo(R * 0.92, R * 0.78); ctx.lineTo(-R * 0.92, R * 0.78); ctx.closePath(); }
  else if (shape === 'diamond') { ctx.moveTo(0, -R); ctx.lineTo(R, 0); ctx.lineTo(0, R); ctx.lineTo(-R, 0); ctx.closePath(); }
  else if (shape === 'circle') { ctx.arc(0, 0, R, 0, 7); }
  else if (shape === 'star') { for (let i = 0; i < 10; i++) { const rr = i % 2 ? R * 0.46 : R; const a = -Math.PI / 2 + i * Math.PI / 5; ctx[i ? 'lineTo' : 'moveTo'](Math.cos(a) * rr, Math.sin(a) * rr); } ctx.closePath(); }
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
  else if (shape === 'bore') { const r = mw * 0.46; ctx.shadowBlur = 6; const g = ctx.createRadialGradient(0, 0, 0, 0, 0, r); g.addColorStop(0, '#050309'); g.addColorStop(0.62, '#1a1426'); g.addColorStop(1, color); ctx.fillStyle = g; ctx.beginPath(); ctx.arc(0, 0, r, 0, 7); ctx.fill(); ctx.lineWidth = 1.6; ctx.strokeStyle = color; ctx.stroke(); }
  ctx.restore();
}

export function drawTurret(ctx, cx, cy, type, lvl, T, opts = {}) {
  const s = opts.size || 150, color = opts.color || TURRET_COLORS[type];
  ctx.save(); ctx.translate(cx, cy);

  // halo (pulse « respiration »)
  const haloDia = s * 1.35, haloOp = (0.12 + lvl * 0.05);
  const pp = 0.5 + 0.5 * Math.sin(T * 2 * Math.PI / (3 + lvl * 0.3));
  const haloScale = 0.96 + 0.09 * pp;
  ctx.save(); ctx.scale(haloScale, haloScale); ctx.globalAlpha = haloOp * (0.5 + 0.5 * pp);
  const hg = ctx.createRadialGradient(0, 0, 0, 0, 0, haloDia / 2);
  hg.addColorStop(0, hexA(color, 0.2)); hg.addColorStop(0.64, hexA(color, 0));
  ctx.fillStyle = hg; ctx.beginPath(); ctx.arc(0, 0, haloDia / 2, 0, 7); ctx.fill(); ctx.restore();

  // anneaux orbitaux (traits fins, rotation lente, sens alterné)
  const ringCount = [0, 1, 2, 2][lvl - 1];
  for (let i = 0; i < ringCount; i++) {
    const dia = s * (0.64 + i * 0.15), dur = 22 - i * 5, dir = i % 2 ? -1 : 1; const op = lvl >= 4 ? 0.6 : 0.42;
    ctx.save(); ctx.rotate(dir * ((T / dur) % 1) * 2 * Math.PI); ctx.globalAlpha = op; ctx.shadowBlur = 4; ctx.shadowColor = color;
    ctx.strokeStyle = hexA(color, 0.85); ctx.lineWidth = 1.1;
    const r = dia / 2; const per = 2 * Math.PI * r / 34; ctx.setLineDash([per * 0.5, per * 0.5]);
    ctx.beginPath(); ctx.arc(0, 0, r, 0, 7); ctx.stroke(); ctx.restore();
  }
  // anneau pointillé externe du socle
  const moDia = s * 0.6, moOp = lvl >= 3 ? 0.5 : 0.24;
  ctx.save(); ctx.rotate(((T / 55) % 1) * 2 * Math.PI); ctx.globalAlpha = moOp; ctx.strokeStyle = hexA(color, 0.6); ctx.lineWidth = 0.8;
  const mr = moDia / 2; const mper = 2 * Math.PI * mr / 40; ctx.setLineDash([mper * 0.5, mper * 0.5]);
  ctx.beginPath(); ctx.arc(0, 0, mr, 0, 7); ctx.stroke(); ctx.restore();

  // particules orbitales
  const pCount = [0, 1, 2, 4][lvl - 1];
  for (let k = 0; k < pCount; k++) {
    const orbit = s * (0.74 + (k % 2) * 0.12), dur = 5 + k * 1.4, delay = -k * 1.3;
    const th = -Math.PI / 2 + (T + delay) * 2 * Math.PI / dur;
    const px = Math.cos(th) * orbit / 2, py = Math.sin(th) * orbit / 2; const dc = k % 2 ? '#ffffff' : color;
    ctx.save(); ctx.shadowBlur = 12; ctx.shadowColor = color; ctx.fillStyle = dc; ctx.beginPath(); ctx.arc(px, py, 3, 0, 7); ctx.fill(); ctx.restore();
  }

  // pattes (niv ≥ 3) avec halo nuageux au pied
  if (lvl >= 3) {
    const angs = lvl >= 4 ? [30, 90, 150, 210, 270, 330] : [45, 135, 225, 315];
    const legLen = s * (lvl >= 4 ? 0.20 : 0.16); const lw = s * (lvl >= 4 ? 0.062 : 0.05); const innerR = s * 0.44 * 0.32;
    for (const a of angs) {
      ctx.save(); ctx.rotate(a * Math.PI / 180);
      const cr = lw * 2.2, cy0 = innerR + legLen;
      ctx.save(); const clg = ctx.createRadialGradient(0, cy0, 0, 0, cy0, cr);
      clg.addColorStop(0, hexA(color, 0.3)); clg.addColorStop(0.5, hexA(color, 0.1)); clg.addColorStop(1, hexA(color, 0));
      ctx.fillStyle = clg; ctx.beginPath(); ctx.arc(0, cy0, cr, 0, 7); ctx.fill(); ctx.restore();
      const g = ctx.createLinearGradient(0, innerR, 0, innerR + legLen); g.addColorStop(0, '#2c2440'); g.addColorStop(1, '#14101f');
      ctx.fillStyle = g; ctx.strokeStyle = hexA(color, 0.33); ctx.lineWidth = 1;
      ctx.beginPath(); ctx.moveTo(-lw * 0.32, innerR); ctx.lineTo(lw * 0.32, innerR); ctx.lineTo(lw * 0.14, innerR + legLen); ctx.lineTo(-lw * 0.14, innerR + legLen); ctx.closePath(); ctx.fill();
      const fw = lw * 1.5;
      ctx.save(); ctx.shadowBlur = 8; ctx.shadowColor = color;
      const fg = ctx.createRadialGradient(0, innerR + legLen, 0, 0, innerR + legLen, fw / 2); fg.addColorStop(0, '#241b36'); fg.addColorStop(1, '#0c0814');
      ctx.fillStyle = fg; ctx.beginPath(); ctx.arc(0, innerR + legLen, fw / 2, 0, 7); ctx.fill(); ctx.lineWidth = 1.5; ctx.strokeStyle = color; ctx.stroke(); ctx.restore();
      ctx.save(); ctx.shadowBlur = 6; ctx.shadowColor = color; ctx.fillStyle = color; ctx.beginPath(); ctx.arc(0, innerR, lw * 0.4, 0, 7); ctx.fill(); ctx.restore();
      ctx.restore();
    }
  }

  // socle
  const mDia = s * 0.44;
  ctx.save(); ctx.shadowBlur = 9 + lvl * 4; ctx.shadowColor = hexA(color, 0.53);
  const mg = ctx.createRadialGradient(0, -mDia * 0.14, 0, 0, 0, mDia / 2); mg.addColorStop(0, '#241b36'); mg.addColorStop(0.82, '#0c0814');
  ctx.fillStyle = mg; ctx.beginPath(); ctx.arc(0, 0, mDia / 2, 0, 7); ctx.fill(); ctx.shadowBlur = 0;
  const ig = ctx.createRadialGradient(0, 0, mDia * 0.18, 0, 0, mDia / 2); ig.addColorStop(0, 'rgba(0,0,0,0)'); ig.addColorStop(1, 'rgba(0,0,0,.72)');
  ctx.fillStyle = ig; ctx.beginPath(); ctx.arc(0, 0, mDia / 2, 0, 7); ctx.fill();
  ctx.lineWidth = 2; ctx.strokeStyle = color; ctx.beginPath(); ctx.arc(0, 0, mDia / 2, 0, 7); ctx.stroke(); ctx.restore();

  // tête (fûts) orientée — angle en degrés, 0 = nord
  const angle = opts.angle || 0; const baseLen = s * 0.40, baseW = s * 0.086;
  let specs;
  if (lvl === 1) specs = [{ dx: 0, len: baseLen, w: baseW }];
  else if (lvl === 2) specs = [{ dx: 0, len: baseLen * 1.14, w: baseW * 1.28 }];
  else if (lvl === 3) specs = [{ dx: -baseW * 0.95, len: baseLen * 1.06, w: baseW * 0.8 }, { dx: baseW * 0.95, len: baseLen * 1.06, w: baseW * 0.8 }];
  else specs = [{ dx: 0, len: baseLen * 1.24, w: baseW * 1.34 }, { dx: -baseW * 1.55, len: baseLen * 0.84, w: baseW * 0.62 }, { dx: baseW * 1.55, len: baseLen * 0.84, w: baseW * 0.62 }];
  if (type === 'sniper') { specs = [{ dx: 0, len: baseLen * 2.05, w: baseW * 0.60 }]; }
  ctx.save(); ctx.rotate(angle * Math.PI / 180);
  for (const b of specs) {
    ctx.save(); ctx.translate(b.dx, 0);
    const g = ctx.createLinearGradient(0, 0, 0, -b.len); g.addColorStop(0, '#1a1426'); g.addColorStop(1, '#352c48');
    ctx.fillStyle = g; ctx.strokeStyle = hexA(color, 0.33); ctx.lineWidth = 1; const rad = b.w * 0.42;
    ctx.beginPath(); ctx.moveTo(-b.w / 2, 0); ctx.lineTo(-b.w / 2, -b.len + rad); ctx.arcTo(-b.w / 2, -b.len, 0, -b.len, rad); ctx.arcTo(b.w / 2, -b.len, b.w / 2, -b.len + rad, rad); ctx.lineTo(b.w / 2, 0); ctx.closePath(); ctx.fill(); ctx.stroke();
    // reflet cylindrique + bande discrète au tiers
    ctx.save(); ctx.beginPath(); ctx.moveTo(-b.w / 2, 0); ctx.lineTo(-b.w / 2, -b.len + rad); ctx.arcTo(-b.w / 2, -b.len, 0, -b.len, rad); ctx.arcTo(b.w / 2, -b.len, b.w / 2, -b.len + rad, rad); ctx.lineTo(b.w / 2, 0); ctx.closePath(); ctx.clip();
    const sh = ctx.createLinearGradient(-b.w / 2, 0, b.w / 2, 0); sh.addColorStop(0, 'rgba(255,255,255,0)'); sh.addColorStop(0.32, 'rgba(255,255,255,.15)'); sh.addColorStop(0.5, 'rgba(255,255,255,.04)'); sh.addColorStop(1, 'rgba(0,0,0,.24)');
    ctx.fillStyle = sh; ctx.fillRect(-b.w / 2, -b.len, b.w, b.len);
    ctx.fillStyle = hexA(color, 0.2); ctx.fillRect(-b.w / 2, -b.len * 0.5 - 1, b.w, 1.6);
    ctx.restore();
    ctx.translate(0, -b.len); drawMuzzle(ctx, TURRET_MUZZLE[type], color, b.w); ctx.restore();
  }
  ctx.restore();

  // cœur (forme par type, rotation + pulse)
  const cDia = s * 0.17 + lvl * s * 0.012, R = cDia / 2; const gp = 0.78 + 0.22 * (0.5 + 0.5 * Math.sin(T * 2 * Math.PI / 2.4));
  ctx.save(); ctx.globalAlpha = gp * 0.4; const cg = ctx.createRadialGradient(0, 0, 0, 0, 0, R * 1.35); cg.addColorStop(0, hexA(color, 0.45)); cg.addColorStop(1, hexA(color, 0));
  ctx.fillStyle = cg; ctx.beginPath(); ctx.arc(0, 0, R * 1.35, 0, 7); ctx.fill(); ctx.restore();
  ctx.save(); ctx.rotate(((T / 20) % 1) * 2 * Math.PI); ctx.shadowBlur = (5 + lvl * 2); ctx.shadowColor = color; ctx.globalAlpha = gp; ctx.fillStyle = color;
  corePath(ctx, TURRET_CORE[type], R); ctx.fill();
  ctx.shadowBlur = 0; ctx.globalAlpha = Math.min(1, gp + 0.2); ctx.lineWidth = 1.2; ctx.strokeStyle = 'rgba(255,235,210,.7)';
  corePath(ctx, TURRET_CORE[type], R); ctx.stroke(); ctx.restore();

  ctx.restore();
}
