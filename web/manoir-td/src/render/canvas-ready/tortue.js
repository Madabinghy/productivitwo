// ============================================================================
// PACK CANVAS-READY — Cuirassé-tortue (artillerie lourde)
// Source de vérité : « 04 - Rendu Canvas 2D/Tortue Canvas - Comparatif.dc.html ».
// À intégrer TEL QUEL — ne pas réinterpréter.
//
// Géométrie canonique :
//   - Le CORPS (tête + 4 pattes) est FIXE sous la carapace, orienté par `face`
//     (la tortue marche TÊTE EN AVANT — tout le corps tourne vers la direction).
//   - La CARAPACE tourne indépendamment (`shellRot`, degrés) pour orienter les canons.
//   - 4 CANONS posés sur les pétales (mount 240/300/180/0°), chaque canon vise
//     INDÉPENDAMMENT (`aim[i]`, degrés monde) l'ennemi le plus proche de son affût.
//   - Déploiement piloté par t (0 = mobile, 1 = déployée) : pattes/tête/canons
//     rentrent, cœur + liseré OR→VERT, aura de soin, badge INCREVABLE (PV masqués).
//   - Marche : cycle de pattes lent (gaitAmp), vitesse lente.
//
// API :
//   TORTUE_CANNONS : les 4 affûts {mount, aim, ph} — phase de tir décalée.
//   drawTortue(ctx, T, state)
//     state = {
//       t: 0..1 déploiement,     face: rad (orientation du corps, 0 = nord),
//       shellRot: deg,           aim: [deg,deg,deg,deg] (visée monde par canon),
//       recoil: [0..1 ×4],       flashes: [{x,y,a,life}] (repère local tortue),
//       gaitAmp: 0..1 (marche),  clock: s (horloge pattes), scale: ~1.55 en jeu
//     }
//   Repère : appelant fait ctx.translate(x, y) avant l'appel. Taille de base 120px
//   (rayon carapace 33) × scale.
// ============================================================================

const GOLD = '#ffce5e', GOLDD = '#ff9e3d', GREEN = '#6effa8', GREEND = '#1d9c5e';
const STEEL = '#566079', STEELHI = '#8a96b3', DARK = '#161220', SHELLCOL = '#ff8a3d';

export const TORTUE_CANNONS = [
  { mount: 240, aim: 264, ph: 0.00 },
  { mount: 300, aim: 276, ph: 0.26 },
  { mount: 180, aim: 225, ph: 0.52 },
  { mount: 0,   aim: 315, ph: 0.78 },
];

function hexLerp(a, b, t) { const p = h => [1, 3, 5].map(i => parseInt(h.slice(i, i + 2), 16)); const A = p(a), B = p(b); return '#' + A.map((v, i) => Math.round(v + (B[i] - v) * t).toString(16).padStart(2, '0')).join(''); }
function hexA(h, a) { const n = parseInt(h.slice(1), 16); return 'rgba(' + ((n >> 16) & 255) + ',' + ((n >> 8) & 255) + ',' + (n & 255) + ',' + a + ')'; }
function pol(cx, cy, r, a) { const rad = a * Math.PI / 180; return [cx + r * Math.cos(rad), cy + r * Math.sin(rad)]; }
function rr(ctx, x, y, w, h, r) { r = Math.min(r, w / 2, h / 2); ctx.beginPath(); ctx.moveTo(x + r, y); ctx.arcTo(x + w, y, x + w, y + h, r); ctx.arcTo(x + w, y + h, x, y + h, r); ctx.arcTo(x, y + h, x, y, r); ctx.arcTo(x, y, x + w, y, r); ctx.closePath(); }
function box(ctx, cx, cy, w, h, r, deg, fill, stroke, lw) { ctx.save(); ctx.translate(cx, cy); if (deg) ctx.rotate(deg * Math.PI / 180); rr(ctx, -w / 2, -h / 2, w, h, r); if (fill) { ctx.fillStyle = fill; ctx.fill(); } if (stroke) { ctx.strokeStyle = stroke; ctx.lineWidth = lw || 1; ctx.stroke(); } ctx.restore(); }

// cycle de marche d'une patte : les pattes DIAGONALES sont en phase (i%2)
function legPose(i, base, legR, gaitAmp, clock) {
  const amp = gaitAmp || 0; if (amp < 0.01) return { ang: base, r: legR, lift: 0 };
  const p = ((clock * 0.28 + (i % 2) * 0.5) % 1 + 1) % 1;
  let frac, lift;
  if (p < 0.35) { const u = p / 0.35; frac = -1 + 2 * u; lift = Math.sin(u * Math.PI); }
  else { const u = (p - 0.35) / 0.65; frac = 1 - 2 * u; lift = 0; }
  return { ang: base + frac * 10 * amp, r: legR + lift * 1.5 * amp, lift: lift * amp };
}

// position d'affût du canon i (repère local tortue, avant rotation face)
export function tortueCannonMount(i, shellRot) {
  const cn = TORTUE_CANNONS[i]; const mrad = (cn.mount + (shellRot || 0)) * Math.PI / 180;
  const K = 1.15, petalR = 20;
  return { x: Math.cos(mrad) * petalR * K, y: Math.sin(mrad) * petalR * K };
}

export function drawTortue(ctx, T, st) {
  const t = st.t || 0, ext = 1 - t, Kc = 1.15;
  const core = hexLerp(GOLD, GREEN, t), coreD = hexLerp(GOLDD, GREEND, t);
  ctx.save();
  if (st.scale) ctx.scale(st.scale, st.scale);
  ctx.rotate(st.face || 0); // TOUT le corps s'oriente vers la direction de marche

  // ombre
  ctx.save(); ctx.translate(0, 5); ctx.scale(1, 56 / 78); ctx.filter = 'blur(6px)'; ctx.fillStyle = 'rgba(0,0,0,.45)'; ctx.beginPath(); ctx.arc(0, 0, 39, 0, 7); ctx.fill(); ctx.filter = 'none'; ctx.restore();

  // pattes (fixes au corps) — rentrent quand déployée
  { const legR = 34 - 12 * t, legSz = 13 - 5 * t, legOp = 1 - 0.92 * t;
    if (legOp > 0.02) {
      ctx.save(); ctx.globalAlpha = legOp; const legs = [46, 134, 226, 314];
      for (let i = 0; i < 4; i++) {
        const p = legPose(i, legs[i], legR, st.gaitAmp, st.clock || T);
        const [lx, ly] = pol(0, 0, p.r, p.ang); const sz = legSz * (1 + 0.14 * p.lift);
        const g = ctx.createRadialGradient(lx - 2.5, ly - 2.5, 0, lx, ly, sz * 0.72);
        g.addColorStop(0, '#aeb8d4'); g.addColorStop(0.55, STEELHI); g.addColorStop(1, STEEL);
        box(ctx, lx, ly, sz, sz, 5, 0, g, hexA(STEELHI, 0.6), 0.8);
      }
      ctx.restore();
    } }

  // tête (fixe au corps, vers l'avant) — rentre quand déployée
  { const headY = -32 + 14 * t, headOp = 1 - 0.92 * t;
    if (headOp > 0.02) {
      ctx.save(); ctx.globalAlpha = headOp;
      const hg = ctx.createRadialGradient(0, headY - 3, 0, 0, headY, 11); hg.addColorStop(0, STEELHI); hg.addColorStop(1, STEEL);
      box(ctx, 0, headY, 18 - 6 * t, 16 - 6 * t, 8, 0, hg);
      ctx.shadowBlur = 8; ctx.shadowColor = core; box(ctx, 0, headY - 2, 11 - 4 * t, 4, 2, 0, core);
      ctx.restore();
    } }

  // carapace (tourne indépendamment du corps)
  ctx.save(); ctx.rotate(((st.shellRot || 0) * Math.PI / 180) - (st.face || 0)); // shellRot est en repère monde
  const dg = ctx.createRadialGradient(0, -66 * 0.16, 0, 0, 0, 33); dg.addColorStop(0, STEELHI); dg.addColorStop(0.5, STEEL); dg.addColorStop(1, DARK);
  ctx.fillStyle = dg; ctx.beginPath(); ctx.arc(0, 0, 33, 0, 7); ctx.fill();
  const ig = ctx.createRadialGradient(0, -13, 2, 0, 4, 33); ig.addColorStop(0, 'rgba(255,255,255,.18)'); ig.addColorStop(0.5, 'rgba(255,255,255,0)'); ig.addColorStop(1, 'rgba(0,0,0,.6)');
  ctx.fillStyle = ig; ctx.beginPath(); ctx.arc(0, 0, 33, 0, 7); ctx.fill();
  ctx.lineWidth = 2; ctx.strokeStyle = hexA(STEELHI, 0.67); ctx.beginPath(); ctx.arc(0, 0, 33, 0, 7); ctx.stroke();
  // 6 écailles-pétales (s'écartent quand déployée)
  for (const a of [0, 60, 120, 180, 240, 300]) {
    const pr = 20 + 3 * t; const [px, py] = pol(0, 0, pr, a);
    ctx.save(); ctx.translate(px, py); ctx.rotate(a * Math.PI / 180);
    const pg = ctx.createLinearGradient(0, -9, 0, 9); pg.addColorStop(0, hexA(STEELHI, 0.8)); pg.addColorStop(0.55, STEEL); pg.addColorStop(1, DARK);
    rr(ctx, -8, -9, 16, 18, 5); ctx.fillStyle = pg; ctx.fill(); ctx.strokeStyle = hexA(STEELHI, 0.33); ctx.lineWidth = 1; ctx.stroke();
    ctx.restore();
  }
  ctx.strokeStyle = hexA(STEELHI, 0.53); ctx.lineWidth = 1.5; ctx.beginPath(); ctx.arc(0, 0, 17, 0, 7); ctx.stroke();
  // liseré vert (déployée)
  if (t > 0.04) { ctx.save(); ctx.globalAlpha = t * 0.85; ctx.shadowBlur = 12; ctx.shadowColor = core; ctx.strokeStyle = core; ctx.lineWidth = 2; ctx.beginPath(); ctx.arc(0, 0, 26, 0, 7); ctx.stroke(); ctx.restore(); }
  // cœur central OR→VERT
  ctx.save(); ctx.shadowBlur = 16; ctx.shadowColor = core;
  const cg = ctx.createRadialGradient(0, -2, 0, 0, 0, 11); cg.addColorStop(0, '#fff'); cg.addColorStop(0.55, core); cg.addColorStop(1, coreD);
  ctx.fillStyle = cg; ctx.beginPath(); ctx.arc(0, 0, 11, 0, 7); ctx.fill();
  ctx.shadowBlur = 0; ctx.globalAlpha = 0.9; ctx.fillStyle = '#fff'; ctx.beginPath(); ctx.arc(0, 0, 4.5, 0, 7); ctx.fill(); ctx.restore();
  ctx.restore(); // fin rotation carapace

  // canons (affûts sur les pétales — visée indépendante par canon, recul au tir)
  // NB : dessinés dans le repère APRÈS rotate(face) ; mount/aim sont en repère monde,
  //      donc on compense face ci-dessous.
  const faceDeg = (st.face || 0) * 180 / Math.PI;
  if (ext > 0.05) {
    for (let i = 0; i < TORTUE_CANNONS.length; i++) {
      const m = tortueCannonMount(i, (st.shellRot || 0) - faceDeg);
      const a = ((st.aim && st.aim[i] != null) ? st.aim[i] : TORTUE_CANNONS[i].aim + (st.shellRot || 0)) - faceDeg;
      const rec = (st.recoil && st.recoil[i]) || 0; const back = rec * 4 * Kc; const len = (4 + 11 * ext) * Kc; const arad = a * Math.PI / 180;
      const bx = m.x, by = m.y;
      const tx = bx + Math.cos(arad) * (len - back), ty = by + Math.sin(arad) * (len - back);
      const mx = (bx + tx) / 2, my = (by + ty) / 2;
      ctx.save(); ctx.globalAlpha = ext;
      const bg = ctx.createRadialGradient(bx - 1.5, by - 1.5, 0, bx, by, 6); bg.addColorStop(0, STEELHI); bg.addColorStop(0.65, STEEL); bg.addColorStop(1, DARK);
      box(ctx, bx, by, 10 * Kc, 10 * Kc, 3, 0, bg);
      const blg = ctx.createLinearGradient(0, -3, 0, 3); blg.addColorStop(0, STEELHI); blg.addColorStop(0.55, STEEL); blg.addColorStop(1, DARK);
      box(ctx, mx, my, len, 6 * Kc, 2, a, blg, hexA(STEELHI, 0.53), 1);
      box(ctx, tx, ty, 7 * Kc, 8 * Kc, 2, a, DARK, core, 1.5);
      ctx.restore();
    }
  }

  // flashes de bouche (repère local tortue, {x,y} relatifs au centre, a = deg monde)
  for (const f of (st.flashes || [])) {
    const k = f.life / 0.10; const arad = (f.a - faceDeg) * Math.PI / 180;
    ctx.save(); ctx.globalAlpha = k * ext; ctx.translate(f.x, f.y); ctx.rotate(arad);
    const fg = ctx.createRadialGradient(-8, 0, 0, 0, 0, 13); fg.addColorStop(0, '#fff'); fg.addColorStop(0.55, SHELLCOL); fg.addColorStop(0.78, 'rgba(255,138,61,0)');
    ctx.fillStyle = fg; ctx.beginPath(); ctx.ellipse(0, 0, 11, 7, 0, 0, 7); ctx.fill(); ctx.restore();
  }

  ctx.restore();
}

// Aura de soin (déployée) — à dessiner AVANT drawTortue, en repère monde centré tortue.
export function drawTortueAura(ctx, t, healRadius, T) {
  if (t < 0.04) return;
  ctx.save();
  const ar = healRadius * (0.6 + 0.4 * t);
  const g = ctx.createRadialGradient(0, 0, 0, 0, 0, ar);
  g.addColorStop(0, GREEN + '20'); g.addColorStop(0.72, 'transparent');
  ctx.globalAlpha = t; ctx.fillStyle = g; ctx.beginPath(); ctx.arc(0, 0, ar, 0, 7); ctx.fill();
  ctx.setLineDash([6, 8]); ctx.strokeStyle = GREEN + '66'; ctx.lineWidth = 1.5; ctx.beginPath(); ctx.arc(0, 0, ar, 0, 7); ctx.stroke(); ctx.setLineDash([]);
  if (t > 0.5) for (let k = 0; k < 5; k++) {
    const ph = (T * 0.6 + k / 5) % 1, a = k * 1.3, rr2 = ar * 0.5;
    const mx = Math.cos(a) * rr2 * (0.4 + ph * 0.5), my = rr2 * 0.3 - ph * 60;
    ctx.globalAlpha = (1 - ph) * 0.8; ctx.fillStyle = GREEN; ctx.font = '11px monospace'; ctx.fillText('+', mx, my);
  }
  ctx.globalAlpha = 1; ctx.restore();
}
