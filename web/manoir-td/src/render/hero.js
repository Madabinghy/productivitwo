// Le Commander (Majordome-automate) — sprite PNG designé (assets-png/commander.png),
// avec fallback canvas fidèle à apresToken(). S'oriente selon H.dir (degrés boussole).
import { drawArt } from './art.js';
const HERO_SCALE = 0.42;
const GD = '#ff9e3d', B = '#c9a050', BH = '#f0cf86', BD = '#806026',
      S = '#566079', SH = '#8a96b3', DK = '#161220';

function rrect(ctx, x, y, w, h, r) {
  ctx.beginPath();
  ctx.moveTo(x - w / 2 + r, y - h / 2);
  ctx.arcTo(x + w / 2, y - h / 2, x + w / 2, y + h / 2, r);
  ctx.arcTo(x + w / 2, y + h / 2, x - w / 2, y + h / 2, r);
  ctx.arcTo(x - w / 2, y + h / 2, x - w / 2, y - h / 2, r);
  ctx.arcTo(x - w / 2, y - h / 2, x + w / 2, y - h / 2, r);
  ctx.closePath();
}
function glow(ctx, x, y, r, col) {
  const g = ctx.createRadialGradient(x, y, 0, x, y, r);
  g.addColorStop(0, col + 'cc'); g.addColorStop(0.45, col + '44'); g.addColorStop(1, 'transparent');
  ctx.fillStyle = g; ctx.beginPath(); ctx.arc(x, y, r, 0, 7); ctx.fill();
}
// barre de vie du Commander (repère translaté, non tourné)
function drawHpBar(ctx, H) {
  const f = Math.max(0, Math.min(1, (H.hp == null ? 100 : H.hp) / (H.maxHp || 100)));
  if (f >= 1) return;
  ctx.fillStyle = 'rgba(0,0,0,.6)'; ctx.fillRect(-17, -32, 34, 4);
  ctx.fillStyle = f > 0.5 ? '#7bff9b' : f > 0.25 ? '#ffd66e' : '#ff5d7a'; ctx.fillRect(-17, -32, 34 * f, 4);
}
function gear(ctx, x, y, r) {
  ctx.save(); ctx.translate(x, y);
  ctx.fillStyle = BH;
  for (let i = 0; i < 8; i++) { ctx.rotate(Math.PI / 4); ctx.fillRect(-1, -r - 1.5, 2, 3); }
  ctx.fillStyle = B; ctx.beginPath(); ctx.arc(0, 0, r, 0, 7); ctx.fill();
  ctx.fillStyle = BD; ctx.beginPath(); ctx.arc(0, 0, r * 0.4, 0, 7); ctx.fill();
  ctx.restore();
}

export function drawHero(game, ctx, th, t) {
  const H = game.HERO; if (!H) return;
  const g = th.flame || '#ffce5e';

  ctx.save();
  ctx.translate(H.x, H.y);

  // anneau de sélection (clic sur le Commander)
  if (game.ui.heroSelected) {
    ctx.save(); ctx.rotate((t || 0) * 0.6); ctx.setLineDash([6, 6]);
    ctx.strokeStyle = g; ctx.lineWidth = 2; ctx.shadowColor = g; ctx.shadowBlur = 10;
    ctx.beginPath(); ctx.arc(0, 4, 30, 0, 7); ctx.stroke(); ctx.setLineDash([]); ctx.restore();
  }

  glow(ctx, 0, 0, 26, g);                                              // halo de lanterne
  ctx.fillStyle = 'rgba(0,0,0,.45)'; ctx.beginPath(); ctx.ellipse(0, 18, 22, 6, 0, 0, 7); ctx.fill(); // ombre

  const hurt = (H.inv || 0) > 0.6;
  ctx.save();
  if (hurt) ctx.globalAlpha = 0.6 + 0.4 * Math.sin(t * 30);

  // sprite PNG designé (orienté ; +180 = avance épaulières/bras en avant comme le proto)
  if (drawArt(ctx, 'commander', HERO_SCALE, (H.dir || 0) + 180, { center: true })) { ctx.restore(); drawHpBar(ctx, H); ctx.restore(); return; }

  // — fallback canvas (fidèle à apresToken) —
  ctx.rotate(((H.dir || 0) + 180) * Math.PI / 180);

  // anneau d'épaule laiton (corps vu de dessus)
  const body = ctx.createRadialGradient(0, -4, 1, 0, 6, 22);
  body.addColorStop(0, BH); body.addColorStop(0.55, B); body.addColorStop(1, BD);
  ctx.fillStyle = body; ctx.strokeStyle = BD; ctx.lineWidth = 2;
  ctx.beginPath(); ctx.ellipse(0, 6, 22, 19, 0, 0, 7); ctx.fill(); ctx.stroke();

  // épaulières + rivets
  for (const dx of [-1, 1]) {
    ctx.save(); ctx.translate(dx * 20, 8); ctx.rotate(dx * 12 * Math.PI / 180);
    const sg = ctx.createLinearGradient(0, -7, 0, 7); sg.addColorStop(0, BH); sg.addColorStop(0.6, B); sg.addColorStop(1, BD);
    ctx.fillStyle = sg; ctx.strokeStyle = BH; ctx.lineWidth = 1; rrect(ctx, 0, 0, 17, 14, 6); ctx.fill(); ctx.stroke();
    ctx.fillStyle = BD; ctx.beginPath(); ctx.arc(0, 0, 1.6, 0, 7); ctx.fill();
    ctx.restore();
  }
  gear(ctx, -18, 10, 4.5);                                             // engrenage (mécanique)

  // plastron / col
  const cg = ctx.createLinearGradient(0, 8, 0, 22); cg.addColorStop(0, SH); cg.addColorStop(0.5, S); cg.addColorStop(1, DK);
  ctx.fillStyle = cg; ctx.strokeStyle = SH; ctx.lineWidth = 1; rrect(ctx, 0, 15, 24, 14, 7); ctx.fill(); ctx.stroke();

  // cœur-âme doré
  glow(ctx, 0, 10, 11, g);
  ctx.fillStyle = g; ctx.shadowColor = g; ctx.shadowBlur = 10; ctx.beginPath(); ctx.arc(0, 10, 5.5, 0, 7); ctx.fill();
  ctx.shadowBlur = 0; ctx.fillStyle = GD; ctx.beginPath(); ctx.arc(0, 10, 2.4, 0, 7); ctx.fill();

  // heaume (tête vue de dessus)
  const hg = ctx.createLinearGradient(0, -22, 0, -2); hg.addColorStop(0, SH); hg.addColorStop(0.55, S); hg.addColorStop(1, DK);
  ctx.fillStyle = hg; ctx.strokeStyle = B; ctx.lineWidth = 1.5; rrect(ctx, 0, -9, 30, 26, 12); ctx.fill(); ctx.stroke();
  ctx.fillStyle = '#08060f'; rrect(ctx, 0, -7, 22, 12, 7); ctx.fill();
  // visière (fente dorée)
  ctx.fillStyle = g; ctx.shadowColor = g; ctx.shadowBlur = 9; rrect(ctx, 0, -10, 20, 5, 2.5); ctx.fill(); ctx.shadowBlur = 0;
  // monocle
  ctx.strokeStyle = BH; ctx.lineWidth = 2; ctx.beginPath(); ctx.arc(-8, -9, 3.5, 0, 7); ctx.stroke();

  // flamme de crête (à l'avant)
  const pulse = 1 + Math.sin(t * 5) * 0.14;
  glow(ctx, 0, -22, 7, g);
  ctx.fillStyle = '#fff'; ctx.shadowColor = g; ctx.shadowBlur = 9;
  ctx.beginPath(); ctx.ellipse(0, -22, 3, 5 * pulse, 0, 0, 7); ctx.fill();
  ctx.fillStyle = g; ctx.beginPath(); ctx.ellipse(0, -21, 2, 3 * pulse, 0, 0, 7); ctx.fill();
  ctx.shadowBlur = 0;

  // lanterne tenue (bras relevé, vue de dessus)
  glow(ctx, -19, -16, 8, g);
  ctx.fillStyle = g; ctx.strokeStyle = BH; ctx.lineWidth = 1; ctx.shadowColor = g; ctx.shadowBlur = 8;
  rrect(ctx, -19, -16, 7, 7, 2); ctx.fill(); ctx.stroke(); ctx.shadowBlur = 0;

  ctx.restore(); // fin rotation

  drawHpBar(ctx, H);
  ctx.restore();
}
