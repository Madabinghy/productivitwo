// Le Commander (Majordome-automate) — sprite dessiné au canvas, vue de dessus.
// S'oriente selon H.dir (degrés boussole). Laiton + acier + lanterne dorée.
export function drawHero(game, ctx, th, t) {
  const H = game.HERO; if (!H) return;
  const g = th.flame, gd = '#ff9e3d', B = '#c9a050', BH = '#f0cf86', BD = '#806026',
        S = '#566079', SH = '#8a96b3', DK = '#161220';

  ctx.save();
  ctx.translate(H.x, H.y);

  // halo de lanterne (sous le sprite, non tourné)
  const lr = 26;
  const lg = ctx.createRadialGradient(0, 0, 0, 0, 0, lr);
  lg.addColorStop(0, g + '55'); lg.addColorStop(0.5, g + '18'); lg.addColorStop(1, 'transparent');
  ctx.fillStyle = lg; ctx.beginPath(); ctx.arc(0, 0, lr, 0, 7); ctx.fill();

  // ombre
  ctx.fillStyle = 'rgba(0,0,0,.45)'; ctx.beginPath(); ctx.ellipse(0, 16, 18, 5, 0, 0, 7); ctx.fill();

  const hurt = (H.inv || 0) > 0.6;
  ctx.save();
  ctx.rotate(((H.dir || 0)) * Math.PI / 180);
  if (hurt) ctx.globalAlpha = 0.6 + 0.4 * Math.sin(t * 30);

  // corps (dôme laiton) — le héros « mène » vers le haut local
  const body = ctx.createRadialGradient(0, -3, 1, 0, 0, 16);
  body.addColorStop(0, BH); body.addColorStop(0.55, B); body.addColorStop(1, BD);
  ctx.fillStyle = body; ctx.strokeStyle = BD; ctx.lineWidth = 2;
  ctx.beginPath(); ctx.ellipse(0, 4, 16, 18, 0, 0, 7); ctx.fill(); ctx.stroke();

  // épaulières
  for (const dx of [-1, 1]) {
    ctx.save(); ctx.translate(dx * 13, 2); ctx.rotate(dx * 12 * Math.PI / 180);
    const sg = ctx.createLinearGradient(0, -7, 0, 7); sg.addColorStop(0, BH); sg.addColorStop(1, BD);
    ctx.fillStyle = sg; ctx.strokeStyle = BH; ctx.lineWidth = 1;
    ctx.beginPath(); ctx.ellipse(0, 0, 8, 7, 0, 0, 7); ctx.fill(); ctx.stroke();
    ctx.fillStyle = BD; ctx.beginPath(); ctx.arc(0, 0, 1.5, 0, 7); ctx.fill();
    ctx.restore();
  }

  // cœur-lanterne doré
  ctx.fillStyle = g; ctx.shadowColor = g; ctx.shadowBlur = 10;
  ctx.beginPath(); ctx.arc(0, 6, 5.5, 0, 7); ctx.fill();
  ctx.shadowBlur = 0;
  ctx.fillStyle = gd; ctx.beginPath(); ctx.arc(0, 6, 2.5, 0, 7); ctx.fill();

  // tête (acier) avec fente-œil dorée vers l'avant
  const hg = ctx.createLinearGradient(0, -16, 0, -4); hg.addColorStop(0, SH); hg.addColorStop(0.55, S); hg.addColorStop(1, DK);
  ctx.fillStyle = hg; ctx.strokeStyle = B; ctx.lineWidth = 1.5;
  ctx.beginPath(); ctx.ellipse(0, -9, 11, 12, 0, 0, 7); ctx.fill(); ctx.stroke();
  ctx.fillStyle = '#07050f'; ctx.beginPath(); ctx.ellipse(0, -10, 8, 5, 0, 0, 7); ctx.fill();
  ctx.fillStyle = g; ctx.shadowColor = g; ctx.shadowBlur = 9;
  ctx.fillRect(-7, -13, 14, 3);
  ctx.shadowBlur = 0;

  // flamme de coiffe (à l'avant)
  const pulse = 1 + Math.sin(t * 4) * 0.12;
  ctx.fillStyle = '#fff'; ctx.shadowColor = g; ctx.shadowBlur = 9;
  ctx.beginPath(); ctx.ellipse(0, -22, 3, 5 * pulse, 0, 0, 7); ctx.fill();
  ctx.fillStyle = g; ctx.beginPath(); ctx.ellipse(0, -21, 2, 3 * pulse, 0, 0, 7); ctx.fill();
  ctx.shadowBlur = 0;

  ctx.restore(); // fin rotation

  // barre de vie (non tournée)
  const f = Math.max(0, Math.min(1, (H.hp == null ? 100 : H.hp) / (H.maxHp || 100)));
  if (f < 1) {
    ctx.save();
    ctx.fillStyle = 'rgba(0,0,0,.6)'; ctx.fillRect(-17, -30, 34, 4);
    ctx.fillStyle = f > 0.5 ? '#7bff9b' : f > 0.25 ? '#ffd66e' : '#ff5d7a';
    ctx.fillRect(-17, -30, 34 * f, 4);
    ctx.restore();
  }
  ctx.restore();
}
