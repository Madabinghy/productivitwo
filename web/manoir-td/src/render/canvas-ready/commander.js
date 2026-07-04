// ============================================================================
// PACK CANVAS-READY — Le Commander (Majordome-automate) + infanterie
// Source de vérité : « 04 - Rendu Canvas 2D/Commander Canvas - Protos.dc.html ».
// À intégrer TEL QUEL — ne pas réinterpréter les formes/couleurs/constantes.
//
// API :
//   drawCommander(ctx, s, T, action, facingOverride?)
//     s      : taille de référence (96 dans le proto ; ~s*0.7 en jeu)
//     T      : temps en secondes (Date.now()/1000)
//     action : 'move' | 'build' | 'laser' | 'harvest'
//     facingOverride : radians — orientation vers la cible ; si absent, pose de démo.
//       0 = tête vers -y (nord). Le Commander marche TÊTE EN AVANT.
//   drawInfantry(ctx, s, T, variant, bodyAng, legAng, walking, firing)
//     variant : 'soldat' | 'elite' | 'lampe' | 'lance'
//     bodyAng : orientation du torse-tourelle (vise/tire) ; legAng : orientation jambes.
//     RÈGLE : limiter l'écart torse/jambes à 90° (les pieds pivotent au-delà).
//   Repère : appelant fait ctx.translate(x, y) avant l'appel.
// ============================================================================

const GOLD = '#ffce5e', GOLD_DEEP = '#ff9e3d', PURP = '#b69bff';
const BRASS_HI = '#f0cf86', BRASS = '#c9a050', BRASS_DK = '#806026';
const STEEL = '#566079', STEEL_HI = '#8a96b3', DARK = '#161220';

function hexA(h, a) { const n = parseInt(h.slice(1), 16); return 'rgba(' + ((n >> 16) & 255) + ',' + ((n >> 8) & 255) + ',' + (n & 255) + ',' + a + ')'; }
function rr(ctx, x, y, w, h, r) { ctx.beginPath(); ctx.moveTo(x + r, y); ctx.arcTo(x + w, y, x + w, y + h, r); ctx.arcTo(x + w, y + h, x, y + h, r); ctx.arcTo(x, y + h, x, y, r); ctx.arcTo(x, y, x + w, y, r); ctx.closePath(); }

function flame(ctx, x, y, w, h, T, seed) {
  const f = 0.5 + 0.5 * Math.sin(T * 7 + seed); const hh = h * (0.84 + 0.3 * f);
  ctx.save(); ctx.translate(x, y); ctx.shadowBlur = 9; ctx.shadowColor = GOLD;
  const g = ctx.createLinearGradient(0, hh * 0.4, 0, -hh); g.addColorStop(0, GOLD_DEEP); g.addColorStop(0.55, GOLD); g.addColorStop(1, '#fff');
  ctx.fillStyle = g; ctx.beginPath(); ctx.moveTo(-w / 2, hh * 0.4); ctx.quadraticCurveTo(-w * 0.5, -hh * 0.3, 0, -hh); ctx.quadraticCurveTo(w * 0.5, -hh * 0.3, w / 2, hh * 0.4); ctx.quadraticCurveTo(0, hh * 0.18, -w / 2, hh * 0.4); ctx.closePath(); ctx.fill(); ctx.restore();
}

function soulCore(ctx, x, y, r, T) {
  const p = 0.78 + 0.22 * (0.5 + 0.5 * Math.sin(T * 2.6)); ctx.save(); ctx.translate(x, y);
  ctx.globalAlpha = p * 0.5; const gg = ctx.createRadialGradient(0, 0, 0, 0, 0, r * 1.7); gg.addColorStop(0, hexA(GOLD, 0.6)); gg.addColorStop(1, hexA(GOLD, 0)); ctx.fillStyle = gg; ctx.beginPath(); ctx.arc(0, 0, r * 1.7, 0, 7); ctx.fill();
  ctx.globalAlpha = 1; ctx.fillStyle = BRASS_DK; ctx.beginPath(); ctx.arc(0, 0, r * 1.28, 0, 7); ctx.fill();
  const cg = ctx.createRadialGradient(0, -r * 0.2, 0, 0, 0, r); cg.addColorStop(0, '#fff'); cg.addColorStop(0.4, GOLD); cg.addColorStop(1, GOLD_DEEP); ctx.fillStyle = cg; ctx.shadowBlur = 10; ctx.shadowColor = GOLD; ctx.beginPath(); ctx.arc(0, 0, r, 0, 7); ctx.fill(); ctx.restore();
}

function gearMini(ctx, x, y, r, T, dir) {
  ctx.save(); ctx.translate(x, y); ctx.rotate(dir * T * 0.9); const teeth = 8;
  ctx.fillStyle = BRASS_DK; for (let i = 0; i < teeth; i++) { ctx.rotate(2 * Math.PI / teeth); ctx.fillRect(-1.3, -r - 2, 2.6, 2.8); }
  const g = ctx.createRadialGradient(0, 0, 1, 0, 0, r); g.addColorStop(0, BRASS_HI); g.addColorStop(1, BRASS); ctx.fillStyle = g; ctx.beginPath(); ctx.arc(0, 0, r, 0, 7); ctx.fill();
  ctx.fillStyle = BRASS_DK; ctx.beginPath(); ctx.arc(0, 0, r * 0.32, 0, 7); ctx.fill(); ctx.restore();
}

// faisceau triangulaire (construction = vert, motes vers la cible ; récolte = or, motes vers le commander)
function beamTri(ctx, arm, target, s, col, coreCol, T, dir) {
  const ang = Math.atan2(target.y - arm.y, target.x - arm.x); const len = Math.hypot(target.x - arm.x, target.y - arm.y); const spread = 0.17;
  ctx.save();
  const g = ctx.createLinearGradient(arm.x, arm.y, target.x, target.y); g.addColorStop(0, hexA(col, 0.12)); g.addColorStop(1, hexA(col, 0.55));
  ctx.fillStyle = g; ctx.shadowBlur = 12; ctx.shadowColor = col;
  ctx.beginPath(); ctx.moveTo(arm.x, arm.y); ctx.lineTo(arm.x + Math.cos(ang - spread) * len, arm.y + Math.sin(ang - spread) * len); ctx.lineTo(arm.x + Math.cos(ang + spread) * len, arm.y + Math.sin(ang + spread) * len); ctx.closePath(); ctx.fill();
  for (let i = 0; i < 3; i++) { let f = ((T * 0.7 + i / 3) % 1); if (dir < 0) f = 1 - f; const mx = arm.x + (target.x - arm.x) * f, my = arm.y + (target.y - arm.y) * f; ctx.globalAlpha = 0.95; ctx.fillStyle = coreCol; ctx.shadowBlur = 8; ctx.shadowColor = col; ctx.beginPath(); ctx.arc(mx, my, 2.4, 0, 7); ctx.fill(); }
  ctx.restore();
}

function drawAction(ctx, s, T, action, Rh, Lh, Rt, Lt) {
  if (action === 'build') { // faisceau triangulaire VERT bras droit, motes commander → chantier
    beamTri(ctx, Rh, Rt, s, '#46d27e', '#b6ffd0', T, +1);
    const pulse = 0.6 + 0.4 * Math.sin(T * 6);
    ctx.save(); ctx.globalAlpha = 0.5 + 0.35 * pulse; ctx.shadowBlur = 10; ctx.shadowColor = '#46d27e'; ctx.strokeStyle = '#b6ffd0'; ctx.lineWidth = 1.4; ctx.setLineDash([4, 3]); rr(ctx, Rt.x - s * 0.11, Rt.y - s * 0.11, s * 0.22, s * 0.22, 3); ctx.stroke(); ctx.setLineDash([]); ctx.restore();
  } else if (action === 'harvest') { // faisceau triangulaire OR bras droit, motes cristal → commander
    beamTri(ctx, Rh, Rt, s, '#ffce5e', '#fff2c8', T, -1);
  } else if (action === 'laser') { // petit laser bras gauche
    const tx = Lt.x, ty = Lt.y; const pulse = 0.7 + 0.3 * Math.sin(T * 20);
    ctx.save(); ctx.globalAlpha = pulse; ctx.strokeStyle = '#ff5a7a'; ctx.lineWidth = 2.4; ctx.lineCap = 'round'; ctx.shadowBlur = 12; ctx.shadowColor = '#ff5a7a'; ctx.beginPath(); ctx.moveTo(Lh.x, Lh.y); ctx.lineTo(tx, ty); ctx.stroke();
    ctx.lineWidth = 0.9; ctx.strokeStyle = '#fff'; ctx.beginPath(); ctx.moveTo(Lh.x, Lh.y); ctx.lineTo(tx, ty); ctx.stroke();
    ctx.fillStyle = '#ff5a7a'; ctx.shadowBlur = 14; ctx.beginPath(); ctx.arc(tx, ty, 3 + 1.5 * Math.sin(T * 20), 0, 7); ctx.fill(); ctx.restore();
  }
}

export function drawCommander(ctx, s, T, action, facingOverride, moving, stepPhase) {
  // `moving`/`stepPhase` fournis par le jeu : l'anim de marche ne joue QUE si le héros
  // se déplace, et sa cadence suit la distance parcourue (pas le temps) → pas de « moonwalk »
  // ni de jambes/bras qui bougent à l'arrêt. Sans ces args (démo) : ancien comportement.
  const walk = moving === undefined ? (action === 'move') : !!moving;
  const ph = (moving !== undefined && stepPhase != null) ? stepPhase : T * 4.2;
  const FACE = { move: 0, build: Math.PI - 0.30, harvest: Math.PI - 0.62, laser: Math.PI + 0.34 };
  const facing = facingOverride != null ? facingOverride : (FACE[action] || 0);

  // ombre au sol (à plat, avant rotation)
  ctx.save(); ctx.globalAlpha = 0.42; ctx.filter = 'blur(4px)'; ctx.fillStyle = '#000'; ctx.beginPath(); ctx.ellipse(0, s * 0.34, s * 0.34, s * 0.13, 0, 0, 7); ctx.fill(); ctx.restore();

  ctx.save(); ctx.rotate(facing); // s'oriente vers sa cible — tête en avant

  // pieds (cycle de marche)
  for (const side of [-1, 1]) {
    const sw = walk ? Math.sin(ph + (side < 0 ? 0 : Math.PI)) : 0; const fy = s * 0.30 + sw * s * 0.07; const fx = side * s * 0.14;
    ctx.save(); ctx.fillStyle = DARK; rr(ctx, fx - s * 0.05, fy - s * 0.05, s * 0.10, s * 0.13, 3); ctx.fill();
    ctx.fillStyle = hexA(STEEL_HI, 0.5); rr(ctx, fx - s * 0.05, fy - s * 0.05, s * 0.10, s * 0.045, 2); ctx.fill(); ctx.restore();
  }

  // épaules + mains (extrémités d'avant-bras) — faisceaux/tirs sortent des mains
  const Rsh = { x: s * 0.30, y: -s * 0.02 }, Lsh = { x: -s * 0.30, y: -s * 0.02 };
  const swing = walk ? Math.sin(ph) * s * 0.075 : 0;
  let Rhand, Lhand;
  if (action === 'build' || action === 'harvest') { Rhand = { x: s * 0.17, y: s * 0.31 }; Lhand = { x: -s * 0.18, y: s * 0.13 }; }
  else if (action === 'laser') { Lhand = { x: -s * 0.17, y: s * 0.31 }; Rhand = { x: s * 0.18, y: s * 0.13 }; }
  else { Rhand = { x: s * 0.29, y: s * 0.11 + swing }; Lhand = { x: -s * 0.29, y: s * 0.11 - swing }; }
  const norm = (a, b) => { const dx = b.x - a.x, dy = b.y - a.y, m = Math.hypot(dx, dy) || 1; return { x: dx / m, y: dy / m }; };
  const Rdir = norm(Rsh, Rhand), Ldir = norm(Lsh, Lhand);
  const Rlen = action === 'harvest' ? s * 0.48 : s * 0.60, Llen = s * 0.58;
  const Rtgt = { x: Rhand.x + Rdir.x * Rlen, y: Rhand.y + Rdir.y * Rlen };
  const Ltgt = { x: Lhand.x + Ldir.x * Llen, y: Lhand.y + Ldir.y * Llen };
  drawAction(ctx, s, T, action, Rhand, Lhand, Rtgt, Ltgt);

  // corps / anneau d'épaule laiton (vu de dessus)
  ctx.save();
  const bodyG = ctx.createRadialGradient(0, -s * 0.06, 2, 0, 0, s * 0.27); bodyG.addColorStop(0, BRASS_HI); bodyG.addColorStop(0.55, BRASS); bodyG.addColorStop(1, BRASS_DK);
  ctx.fillStyle = bodyG; ctx.strokeStyle = BRASS_DK; ctx.lineWidth = 2; rr(ctx, -s * 0.24, -s * 0.22, s * 0.48, s * 0.46, s * 0.17); ctx.fill(); ctx.stroke();
  ctx.fillStyle = BRASS_DK; for (const rx of [-1, 1]) for (const ry of [-1, 1]) { ctx.beginPath(); ctx.arc(rx * s * 0.17, ry * s * 0.15, 1.7, 0, 7); ctx.fill(); }
  ctx.strokeStyle = hexA(DARK, 0.55); ctx.lineWidth = 1.4;
  ctx.beginPath(); ctx.moveTo(-s * 0.20, -s * 0.02); ctx.lineTo(s * 0.20, -s * 0.02); ctx.stroke();
  ctx.beginPath(); ctx.moveTo(0, -s * 0.20); ctx.lineTo(0, -s * 0.05); ctx.stroke();
  ctx.fillStyle = hexA(BRASS_HI, 0.45); rr(ctx, -s * 0.185, -s * 0.215, s * 0.37, s * 0.085, s * 0.045); ctx.fill();
  ctx.fillStyle = hexA(DARK, 0.4); rr(ctx, -s * 0.205, s * 0.10, s * 0.41, s * 0.10, s * 0.05); ctx.fill();
  ctx.restore();

  // gros tubes dorés (avant-bras) avec bouche blindée double-fût (look ACU)
  const tube = (sx, sy, hx, hy) => {
    const ang = Math.atan2(hy - sy, hx - sx); const len = Math.hypot(hx - sx, hy - sy); const w = s * 0.135;
    ctx.save(); ctx.translate(sx, sy); ctx.rotate(ang);
    const g = ctx.createLinearGradient(0, -w / 2, 0, w / 2); g.addColorStop(0, BRASS_HI); g.addColorStop(0.45, BRASS); g.addColorStop(1, BRASS_DK);
    ctx.fillStyle = g; ctx.strokeStyle = BRASS_DK; ctx.lineWidth = 1.4; rr(ctx, -w * 0.3, -w / 2, len + w * 0.3, w, w * 0.42); ctx.fill(); ctx.stroke();
    ctx.fillStyle = hexA(BRASS_DK, 0.8); for (const fr of [0.4, 0.66]) ctx.fillRect(len * fr, -w / 2, w * 0.1, w);
    ctx.fillStyle = hexA('#ffffff', 0.28); rr(ctx, 0, -w * 0.4, len * 0.9, w * 0.18, w * 0.09); ctx.fill();
    ctx.fillStyle = BRASS_DK; rr(ctx, len - w * 0.25, -w * 0.66, w * 0.95, w * 1.32, w * 0.2); ctx.fill();
    const mg = ctx.createLinearGradient(0, -w * 0.6, 0, w * 0.6); mg.addColorStop(0, BRASS_HI); mg.addColorStop(0.5, BRASS); mg.addColorStop(1, BRASS_DK);
    ctx.fillStyle = mg; ctx.strokeStyle = BRASS_DK; ctx.lineWidth = 1.2; rr(ctx, len - w * 0.18, -w * 0.58, w * 0.78, w * 1.16, w * 0.16); ctx.fill(); ctx.stroke();
    ctx.fillStyle = '#1a1206'; ctx.beginPath(); ctx.arc(len + w * 0.2, -w * 0.16, w * 0.3, 0, 7); ctx.fill(); ctx.strokeStyle = BRASS_HI; ctx.lineWidth = 1.3; ctx.stroke();
    ctx.fillStyle = '#1a1206'; ctx.beginPath(); ctx.arc(len + w * 0.2, w * 0.28, w * 0.16, 0, 7); ctx.fill(); ctx.strokeStyle = hexA(BRASS_HI, 0.7); ctx.lineWidth = 1; ctx.stroke();
    ctx.restore();
  };
  tube(Lsh.x, Lsh.y, Lhand.x, Lhand.y);
  tube(Rsh.x, Rsh.y, Rhand.x, Rhand.y);

  // épaulières blindées en plaques
  for (const side of [-1, 1]) {
    ctx.save(); ctx.translate(side * s * 0.28, -s * 0.05); ctx.rotate(side * 0.30);
    ctx.fillStyle = BRASS_DK; rr(ctx, -s * 0.135, -s * 0.115, s * 0.27, s * 0.23, s * 0.05); ctx.fill();
    const pg = ctx.createLinearGradient(0, -s * 0.11, 0, s * 0.11); pg.addColorStop(0, BRASS_HI); pg.addColorStop(0.5, BRASS); pg.addColorStop(1, BRASS_DK);
    ctx.fillStyle = pg; ctx.strokeStyle = BRASS_HI; ctx.lineWidth = 1.2; rr(ctx, -s * 0.115, -s * 0.10, s * 0.23, s * 0.18, s * 0.045); ctx.fill(); ctx.stroke();
    ctx.strokeStyle = hexA(DARK, 0.6); ctx.lineWidth = 1.2; ctx.beginPath(); ctx.moveTo(-s * 0.05, -s * 0.09); ctx.lineTo(-s * 0.05, s * 0.075); ctx.stroke();
    ctx.fillStyle = DARK; ctx.beginPath(); ctx.arc(s * 0.05, 0, s * 0.02, 0, 7); ctx.fill();
    ctx.restore();
  }

  // engrenage rotatif au bout du tube droit (mécanique)
  gearMini(ctx, Rhand.x, Rhand.y, s * 0.06, T, 1);

  // cœur-âme
  soulCore(ctx, 0, s * 0.04, s * 0.085, T);

  // heaume (tête vue de dessus)
  ctx.save();
  const hg = ctx.createLinearGradient(0, -s * 0.2, 0, s * 0.05); hg.addColorStop(0, STEEL_HI); hg.addColorStop(0.55, STEEL); hg.addColorStop(1, DARK);
  ctx.fillStyle = hg; ctx.strokeStyle = BRASS; ctx.lineWidth = 1.5; rr(ctx, -s * 0.16, -s * 0.20, s * 0.32, s * 0.28, s * 0.12); ctx.fill(); ctx.stroke();
  ctx.fillStyle = '#070510'; rr(ctx, -s * 0.12, -s * 0.16, s * 0.24, s * 0.13, s * 0.06); ctx.fill();
  ctx.save(); ctx.shadowBlur = 10; ctx.shadowColor = GOLD; ctx.fillStyle = GOLD; rr(ctx, -s * 0.10, -s * 0.135, s * 0.20, s * 0.05, s * 0.025); ctx.fill(); ctx.restore();
  ctx.strokeStyle = BRASS_HI; ctx.lineWidth = 2; ctx.beginPath(); ctx.arc(-s * 0.07, -s * 0.11, s * 0.035, 0, 7); ctx.stroke();
  ctx.restore();

  // flammèche de crête (à l'avant)
  flame(ctx, 0, -s * 0.24, s * 0.12, s * 0.16, T, 0);
  ctx.restore(); // fin rotation facing
}

// ===== INFANTERIE (torse-tourelle découplé des jambes) =====
export function drawInfantry(ctx, s, T, variant, bodyAng, legAng, walking, firing) {
  const accent = variant === 'lampe' ? GOLD : variant === 'lance' ? PURP : variant === 'elite' ? '#9fe9ff' : '#7fd8ff';
  bodyAng = bodyAng || 0; legAng = legAng || 0;
  const ph = T * 5.0; const bob = Math.sin(ph * 2) * s * 0.012;

  ctx.save(); ctx.translate(0, bob);
  ctx.save(); ctx.globalAlpha = 0.4; ctx.filter = 'blur(3px)'; ctx.fillStyle = '#000'; ctx.beginPath(); ctx.ellipse(0, s * 0.30, s * 0.27, s * 0.11, 0, 0, 7); ctx.fill(); ctx.restore();

  // jambes (orientées vers le déplacement)
  ctx.save(); ctx.rotate(legAng);
  for (const side of [-1, 1]) {
    const sw = walking ? Math.sin(ph + (side < 0 ? 0 : Math.PI)) : 0; const fy = s * 0.24 + Math.max(0, sw) * s * 0.06; const lift = Math.max(0, sw); const fx = side * s * 0.11;
    ctx.save(); ctx.globalAlpha = 1 - lift * 0.25; ctx.fillStyle = DARK; rr(ctx, fx - s * 0.045, fy - s * 0.05, s * 0.09, s * 0.12, 2.5); ctx.fill();
    ctx.fillStyle = hexA(STEEL_HI, 0.55); rr(ctx, fx - s * 0.045, fy - s * 0.05, s * 0.09, s * 0.04, 2); ctx.fill(); ctx.restore();
  }
  ctx.fillStyle = hexA(DARK, 0.6); rr(ctx, -s * 0.10, s * 0.12, s * 0.20, s * 0.10, s * 0.04); ctx.fill();
  ctx.restore();

  // torse / tourelle (pivote pour viser & tirer)
  ctx.save(); ctx.rotate(bodyAng);
  for (const side of [-1, 1]) { ctx.save(); ctx.fillStyle = STEEL; rr(ctx, side * s * 0.20 - s * 0.035, -s * 0.02, s * 0.07, s * 0.16, 3); ctx.fill(); ctx.restore(); }
  if (variant === 'lance') { ctx.save(); ctx.strokeStyle = BRASS_HI; ctx.lineWidth = 2.4; ctx.lineCap = 'round'; ctx.beginPath(); ctx.moveTo(s * 0.20, -s * 0.10); ctx.lineTo(s * 0.20, s * 0.34); ctx.stroke(); ctx.fillStyle = PURP; ctx.shadowBlur = 8; ctx.shadowColor = PURP; ctx.beginPath(); ctx.moveTo(s * 0.20, s * 0.42); ctx.lineTo(s * 0.235, s * 0.32); ctx.lineTo(s * 0.165, s * 0.32); ctx.closePath(); ctx.fill(); ctx.restore(); }
  if (variant === 'lampe') { ctx.save(); ctx.translate(-s * 0.24, -s * 0.06); const gg = ctx.createRadialGradient(0, 0, 0, 0, 0, s * 0.13); gg.addColorStop(0, hexA(GOLD, 0.7)); gg.addColorStop(1, hexA(GOLD, 0)); ctx.fillStyle = gg; ctx.beginPath(); ctx.arc(0, 0, s * 0.13, 0, 7); ctx.fill(); ctx.fillStyle = GOLD; ctx.strokeStyle = BRASS_HI; ctx.lineWidth = 1; rr(ctx, -s * 0.03, -s * 0.04, s * 0.06, s * 0.08, 2); ctx.fill(); ctx.stroke(); ctx.restore(); }
  ctx.save(); const bg = ctx.createLinearGradient(0, -s * 0.16, 0, s * 0.18); bg.addColorStop(0, STEEL_HI); bg.addColorStop(0.5, STEEL); bg.addColorStop(1, DARK); ctx.fillStyle = bg; ctx.strokeStyle = hexA(BRASS, 0.7); ctx.lineWidth = 1.5; rr(ctx, -s * 0.18, -s * 0.16, s * 0.36, s * 0.34, s * 0.12); ctx.fill(); ctx.stroke(); ctx.restore();
  ctx.save(); ctx.fillStyle = accent; ctx.shadowBlur = 8; ctx.shadowColor = accent; ctx.beginPath(); ctx.arc(0, s * 0.02, s * 0.05, 0, 7); ctx.fill(); ctx.restore();
  ctx.save(); const hg = ctx.createLinearGradient(0, -s * 0.18, 0, 0); hg.addColorStop(0, STEEL_HI); hg.addColorStop(1, DARK); ctx.fillStyle = hg; ctx.strokeStyle = hexA(BRASS, 0.8); ctx.lineWidth = 1.2; rr(ctx, -s * 0.12, -s * 0.17, s * 0.24, s * 0.22, s * 0.10); ctx.fill(); ctx.stroke();
  ctx.fillStyle = '#070510'; rr(ctx, -s * 0.09, -s * 0.14, s * 0.18, s * 0.10, s * 0.04); ctx.fill();
  ctx.fillStyle = hexA(STEEL_HI, 0.45); rr(ctx, -s * 0.055, -s * 0.125, s * 0.11, s * 0.028, 1.5); ctx.fill();
  ctx.restore();
  const eo = s * 0.13;
  ctx.save(); ctx.shadowBlur = firing ? 14 : 9; ctx.shadowColor = accent; ctx.fillStyle = accent; rr(ctx, -s * 0.07, eo - s * 0.018, s * 0.14, s * 0.036, 2); ctx.fill(); ctx.restore();
  if (firing && variant === 'soldat') {
    const reach = s * 1.25, n = 3, bw = s * 0.05, bh = s * 0.13;
    ctx.save(); ctx.shadowBlur = 10; ctx.shadowColor = '#5fd0ff';
    for (let i = 0; i < n; i++) {
      const f = ((T * 1.6 + i / n) % 1); const by = eo + 0.04 * s + f * reach; const fade = Math.min(1, (1 - f) / 0.25);
      ctx.globalAlpha = fade; const g = ctx.createLinearGradient(0, by - bh / 2, 0, by + bh / 2); g.addColorStop(0, '#fff'); g.addColorStop(0.45, '#5fd0ff'); g.addColorStop(1, hexA('#5fd0ff', 0.15));
      ctx.fillStyle = g; rr(ctx, -bw / 2, by - bh / 2, bw, bh, bw * 0.45); ctx.fill();
    }
    const mf = 1 - ((T * 1.6) % 1); ctx.globalAlpha = mf * 0.9; ctx.fillStyle = '#dff6ff'; ctx.shadowBlur = 12; ctx.beginPath(); ctx.arc(0, eo, s * 0.03 + s * 0.02 * mf, 0, 7); ctx.fill();
    ctx.restore();
  } else if (firing && variant === 'elite') {
    const ty = s * 1.3; const pulse = 0.7 + 0.3 * Math.sin(T * 30);
    ctx.save(); ctx.globalAlpha = pulse; ctx.lineCap = 'round'; ctx.shadowBlur = 14; ctx.shadowColor = '#9fe9ff';
    ctx.strokeStyle = '#9fe9ff'; ctx.lineWidth = 3.4; ctx.beginPath(); ctx.moveTo(0, eo); ctx.lineTo(0, ty); ctx.stroke();
    ctx.strokeStyle = '#fff'; ctx.lineWidth = 1.2; ctx.beginPath(); ctx.moveTo(0, eo); ctx.lineTo(0, ty); ctx.stroke();
    ctx.fillStyle = '#fff'; ctx.shadowBlur = 16; ctx.beginPath(); ctx.arc(0, ty, 3 + 1.6 * Math.sin(T * 30), 0, 7); ctx.fill(); ctx.restore();
  }
  if (variant === 'lampe') {
    const apex = eo, len = s * 1.05, spread = 0.42;
    ctx.save(); ctx.globalAlpha = 0.5 + 0.15 * Math.sin(T * 4); const g = ctx.createLinearGradient(0, apex, 0, apex + len); g.addColorStop(0, hexA(GOLD, 0.5)); g.addColorStop(1, hexA(GOLD, 0));
    ctx.fillStyle = g; ctx.shadowBlur = 10; ctx.shadowColor = GOLD; ctx.beginPath(); ctx.moveTo(0, apex); ctx.lineTo(Math.sin(-spread) * len, apex + Math.cos(spread) * len); ctx.lineTo(Math.sin(spread) * len, apex + Math.cos(spread) * len); ctx.closePath(); ctx.fill(); ctx.restore();
  }
  ctx.restore();

  ctx.restore();
}
