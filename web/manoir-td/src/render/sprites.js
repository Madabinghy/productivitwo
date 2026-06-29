// Sprites dessinés au canvas (pas de formes CSS empilées) : flemmes, coffre, cristaux, héros.
// Vue de dessus stricte ; chaque sprite est dessiné dans son repère local puis transformé.
import { drawArt } from './art.js';

function hpBar(ctx, x, y, w, f) {
  ctx.save();
  ctx.fillStyle = 'rgba(0,0,0,.6)'; ctx.fillRect(x - w / 2, y, w, 4);
  ctx.fillStyle = f > 0.5 ? '#7bff9b' : f > 0.25 ? '#ffd66e' : '#ff5d7a';
  ctx.fillRect(x - w / 2, y, w * f, 4);
  ctx.restore();
}

// Flemme « araignée » : corps incandescent + pattes rayonnantes + yeux.
function drawSpider(ctx, col, chase, t) {
  ctx.save();
  // pattes
  ctx.strokeStyle = col; ctx.lineWidth = 2; ctx.lineCap = 'round';
  for (const a of [58, 82, 106, 130]) {
    for (const sgn of [1, -1]) {
      const rad = (sgn * a) * Math.PI / 180;
      const wob = Math.sin(t * 9 + a) * 0.12;
      const dx = Math.sin(rad + wob), dy = -Math.cos(rad + wob);
      ctx.globalAlpha = 0.7; ctx.beginPath(); ctx.moveTo(0, 0); ctx.lineTo(dx * 15, dy * 15); ctx.stroke();
    }
  }
  ctx.globalAlpha = 1;
  // corps
  const g = ctx.createRadialGradient(0, -2, 1, 0, 0, 9);
  g.addColorStop(0, col); g.addColorStop(0.7, col + '66'); g.addColorStop(1, 'transparent');
  ctx.fillStyle = g; ctx.shadowColor = col; ctx.shadowBlur = 10;
  ctx.beginPath(); ctx.ellipse(0, 0, 7, 8, 0, 0, 7); ctx.fill();
  ctx.shadowBlur = 0;
  // tête
  const g2 = ctx.createRadialGradient(0, -4, 0, 0, -4, 5);
  g2.addColorStop(0, col); g2.addColorStop(1, col + '55');
  ctx.fillStyle = g2; ctx.beginPath(); ctx.ellipse(0, -4, 4.5, 4, 0, 0, 7); ctx.fill();
  // yeux
  ctx.fillStyle = '#fff'; ctx.shadowColor = '#fff'; ctx.shadowBlur = 4;
  ctx.beginPath(); ctx.arc(-2, -4.5, 1.4, 0, 7); ctx.fill();
  ctx.beginPath(); ctx.arc(2, -4.5, 1.4, 0, 7); ctx.fill();
  ctx.shadowBlur = 0;
  if (chase) { ctx.strokeStyle = col + 'cc'; ctx.lineWidth = 1; ctx.beginPath(); ctx.arc(0, 0, 13, 0, 7); ctx.stroke(); }
  ctx.restore();
}

// Flemme « mécha » : châssis hexagonal + fente-œil + antenne.
function drawMecha(ctx, eye, chase) {
  ctx.save();
  const m1 = '#454d5e', m2 = '#1b2130', edge = '#828fa6';
  // pattes basses
  ctx.strokeStyle = m1; ctx.lineWidth = 3; ctx.lineCap = 'round';
  for (const dx of [-1, 1]) {
    ctx.beginPath(); ctx.moveTo(dx * 6, 4); ctx.lineTo(dx * 11, 10); ctx.stroke();
    ctx.beginPath(); ctx.moveTo(dx * 7, 1); ctx.lineTo(dx * 13, 4); ctx.stroke();
  }
  // corps hexagonal
  const R = 9;
  ctx.beginPath();
  for (let i = 0; i < 6; i++) { const a = (i / 6) * Math.PI * 2 - Math.PI / 2; const px = Math.cos(a) * R, py = Math.sin(a) * R * 1.05; i ? ctx.lineTo(px, py) : ctx.moveTo(px, py); }
  ctx.closePath();
  const g = ctx.createLinearGradient(0, -R, 0, R); g.addColorStop(0, m1); g.addColorStop(1, m2);
  ctx.fillStyle = g; ctx.fill();
  ctx.strokeStyle = edge; ctx.lineWidth = 1; ctx.stroke();
  // fente-œil
  ctx.fillStyle = eye; ctx.shadowColor = eye; ctx.shadowBlur = 9;
  ctx.fillRect(-6, -2, 12, 3);
  ctx.shadowBlur = 0;
  // antenne
  ctx.strokeStyle = edge; ctx.lineWidth = 1.4; ctx.beginPath(); ctx.moveTo(0, -R); ctx.lineTo(0, -R - 6); ctx.stroke();
  ctx.fillStyle = eye; ctx.shadowColor = eye; ctx.shadowBlur = 6; ctx.beginPath(); ctx.arc(0, -R - 7, 2.4, 0, 7); ctx.fill();
  ctx.shadowBlur = 0;
  if (chase) { ctx.strokeStyle = eye + 'cc'; ctx.lineWidth = 1; ctx.strokeRect(-12, -12, 24, 24); }
  ctx.restore();
}

export function drawEnemy(ctx, e, col, t) {
  ctx.save();
  ctx.translate(e.x, e.y);
  // ombre
  ctx.fillStyle = 'rgba(0,0,0,.4)'; ctx.beginPath(); ctx.ellipse(0, 11, 13, 4, 0, 0, 7); ctx.fill();
  ctx.save();
  ctx.rotate(((e.facing || 0)) * Math.PI / 180);
  if (e.kind === 'mecha') drawMecha(ctx, col, !!e.chase); else drawSpider(ctx, col, !!e.chase, t);
  ctx.restore();
  hpBar(ctx, 0, -18, 26, Math.max(0, Math.min(1, e.hp / (e.maxHp || 50))));
  ctx.restore();
}

// Coffre-fort : caisson métallique + cadran, vue de dessus.
export function drawCoffre(ctx, coffre, th, danger, t) {
  const acc = danger ? '#ff5d7a' : '#e6c074';
  ctx.save();
  ctx.translate(coffre.x, coffre.y);
  // halo
  const hr = 64;
  const hg = ctx.createRadialGradient(0, 0, 0, 0, 0, hr);
  hg.addColorStop(0, acc + '33'); hg.addColorStop(1, 'transparent');
  ctx.globalAlpha = danger ? 0.6 + Math.sin(t * 8) * 0.3 : 0.5;
  ctx.fillStyle = hg; ctx.beginPath(); ctx.arc(0, 0, hr, 0, 7); ctx.fill();
  ctx.globalAlpha = 1;
  // ombre
  ctx.fillStyle = 'rgba(0,0,0,.5)'; ctx.beginPath(); ctx.ellipse(0, 26, 26, 6, 0, 0, 7); ctx.fill();
  // caisson : sprite PNG designé, sinon fallback canvas
  if (danger) { ctx.shadowColor = acc; ctx.shadowBlur = 16; }
  if (!drawArt(ctx, 'coffre', 0.38, 0, { center: true })) {
    const S = 58;
    ctx.save();
    const bg = ctx.createLinearGradient(-S / 2, -S / 2, S / 2, S / 2);
    bg.addColorStop(0, '#3a4150'); bg.addColorStop(1, '#171c27');
    ctx.fillStyle = bg; ctx.strokeStyle = acc; ctx.lineWidth = 2; ctx.shadowColor = acc; ctx.shadowBlur = 14;
    ctx.beginPath(); ctx.rect(-S / 2, -S / 2, S, S); ctx.fill(); ctx.stroke();
    ctx.shadowBlur = 0;
    ctx.fillStyle = '#10141d'; ctx.strokeStyle = acc; ctx.lineWidth = 2;
    ctx.beginPath(); ctx.arc(0, 0, S * 0.25, 0, 7); ctx.fill(); ctx.stroke();
    ctx.strokeStyle = acc + 'aa'; ctx.lineWidth = 2;
    for (const a of [0, 45, 90, 135]) { const r = a * Math.PI / 180; ctx.beginPath(); ctx.moveTo(-Math.sin(r) * S * 0.23, Math.cos(r) * S * 0.23); ctx.lineTo(Math.sin(r) * S * 0.23, -Math.cos(r) * S * 0.23); ctx.stroke(); }
    ctx.fillStyle = acc; ctx.shadowColor = acc; ctx.shadowBlur = 8; ctx.beginPath(); ctx.arc(0, 0, 3.5, 0, 7); ctx.fill();
    ctx.restore();
  }
  ctx.shadowBlur = 0;
  ctx.restore();

  // libellé
  ctx.save();
  ctx.fillStyle = danger ? '#ff8da0' : th.accentText;
  ctx.font = "9px 'Chakra Petch', monospace"; ctx.textAlign = 'center';
  ctx.fillText('COFFRE-FORT', coffre.x, coffre.y + 46);
  ctx.restore();
}

// Gisement de cristaux de masse : amas d'éclats, brille selon le remplissage.
export function drawCrystal(ctx, cr, t) {
  const f = Math.max(0, cr.amount / cr.max);
  ctx.save();
  ctx.translate(cr.x, cr.y);
  // halo
  const gr = 23 + f * 29;
  const g = ctx.createRadialGradient(0, -6, 0, 0, -6, gr);
  g.addColorStop(0, 'rgba(150,200,255,' + (0.14 + f * 0.22).toFixed(2) + ')'); g.addColorStop(1, 'transparent');
  ctx.fillStyle = g; ctx.beginPath(); ctx.arc(0, -6, gr, 0, 7); ctx.fill();
  ctx.globalAlpha = 0.6 + f * 0.4;
  // sprite PNG designé (brille selon le remplissage), sinon fallback canvas
  if (drawArt(ctx, 'gisement', 0.32 + f * 0.12, 0, { center: true })) { ctx.restore(); return; }
  const sc = 0.72 + f * 0.5; ctx.scale(sc, sc);
  // socle
  ctx.fillStyle = 'rgba(0,0,0,.42)'; ctx.beginPath(); ctx.ellipse(0, 10, 18, 5, 0, 0, 7); ctx.fill();
  const base = ctx.createLinearGradient(0, 0, 0, 12); base.addColorStop(0, '#3a3550'); base.addColorStop(1, '#1b1730');
  ctx.fillStyle = base; ctx.beginPath(); ctx.ellipse(0, 6, 13, 6, 0, 0, 7); ctx.fill();
  // éclats
  const shard = (x, y, w, h, rot, c1, c2) => {
    ctx.save(); ctx.translate(x, y); ctx.rotate(rot * Math.PI / 180);
    const sg = ctx.createLinearGradient(0, -h / 2, 0, h / 2); sg.addColorStop(0, c1); sg.addColorStop(1, c2);
    ctx.fillStyle = sg; ctx.shadowColor = c1; ctx.shadowBlur = 7;
    ctx.beginPath(); ctx.moveTo(0, -h / 2); ctx.lineTo(w / 2, h * 0.18); ctx.lineTo(0, h / 2); ctx.lineTo(-w / 2, h * 0.18); ctx.closePath(); ctx.fill();
    ctx.restore();
  };
  shard(-7, -2, 10, 22, -16, '#d7c6ff', '#7a5fc0');
  shard(8, -1, 9, 18, 15, '#bfeaff', '#4f7fc8');
  shard(0, -8, 14, 30, 0, '#d8f3ff', '#5a8fd6');
  ctx.fillStyle = '#eaffff'; ctx.shadowColor = '#bfeaff'; ctx.shadowBlur = 7;
  ctx.beginPath(); ctx.arc(0, -12, 2.5, 0, 7); ctx.fill();
  ctx.restore();
}
