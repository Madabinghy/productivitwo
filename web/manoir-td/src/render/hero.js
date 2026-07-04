// Le Commander (Majordome-automate) — rendu 100% Canvas via le pack canvas-ready.
// drawCommander dessine corps + bras + faisceaux d'action ; s'oriente selon H.dir (boussole).
import { drawCommander } from './canvas-ready/commander.js';

const HERO_SIZE = 54;

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

// action courante du Commander (pose + faisceau du bras concerné)
function heroAction(game) {
  if (game._buildId != null) return 'build';
  if (game._harvestId != null) return 'harvest';
  return 'move';
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

  glow(ctx, 0, 0, 26, g);   // halo de lanterne (ambiance dorée)

  const hurt = (H.inv || 0) > 0.6;
  ctx.save();
  if (hurt) ctx.globalAlpha = 0.6 + 0.4 * Math.sin(t * 30);
  drawCommander(ctx, HERO_SIZE, t, heroAction(game), (H.dir || 0) * Math.PI / 180, !!game._heroMoving, H.stepPhase || 0);
  ctx.restore();

  drawHpBar(ctx, H);
  ctx.restore();
}
