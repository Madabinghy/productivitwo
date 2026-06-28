// Brouillard de nuit (veil) + minimap tactique. Dessinés en repère écran (après la caméra).
import { VPW, VPH, VIS, CANDLE_VIS, MAP, COFFRE, TCOL, radarRadius, turretStats } from '../config.js';
import { hasSatellite, enemyRevealed } from '../systems/vision.js';

const isBuilt = (t) => t.built !== false;

// Voile de nuit : sombre partout, troué par les sources de vision (destination-out).
export function drawFog(game, ctx, th, tx, ty) {
  if (!game.ui.darkMode) return;                 // de jour : pas de brouillard
  if (hasSatellite(game)) return;                // œil-satellite : révélation totale
  const H = game.HERO;
  ctx.save();
  ctx.fillStyle = 'rgba(5,4,11,.86)'; ctx.fillRect(0, 0, VPW, VPH);
  ctx.globalCompositeOperation = 'destination-out';
  const punch = (wx, wy, r) => {
    const sx = wx + tx, sy = wy + ty;
    if (sx < -r || sy < -r || sx > VPW + r || sy > VPH + r) return;
    const g = ctx.createRadialGradient(sx, sy, 0, sx, sy, r);
    g.addColorStop(0, 'rgba(0,0,0,1)'); g.addColorStop(0.72, 'rgba(0,0,0,1)'); g.addColorStop(1, 'rgba(0,0,0,0)');
    ctx.fillStyle = g; ctx.beginPath(); ctx.arc(sx, sy, r, 0, 7); ctx.fill();
  };
  if (H) punch(H.x, H.y, VIS);                                   // halo du Commander
  for (const idx of game.G.lit) { const c = game.CANDLES[idx]; punch(c.x, c.y, CANDLE_VIS); } // bougies
  // champ de vision des bâtiments : tourelles (leur portée), radar, soin/bouclier
  for (const t of game.ui.placed) {
    if (t.cat !== 'turret' || !isBuilt(t)) continue;
    const ts = turretStats(t);
    const r = t.key === 'radar' ? radarRadius(t) : (ts.range > 0 ? ts.range : 170);
    punch(t.x, t.y, r);
  }
  ctx.restore();
}

// Minimap « PLAN » en haut à droite du viewport.
export function drawMinimap(game, ctx, th) {
  const s = game.ui; const sat = hasSatellite(game);
  const W = 176, mxs = W / MAP.W, Hm = MAP.H * mxs;
  const PX = VPW - W - 14, PY = 14, pad = 7;

  ctx.save();
  // cadre
  ctx.fillStyle = th.bg + 'd0'; ctx.strokeStyle = th.accent + '44'; ctx.lineWidth = 1;
  roundRect(ctx, PX - pad, PY - pad - 12, W + pad * 2, Hm + pad * 2 + 12, 10); ctx.fill(); ctx.stroke();
  ctx.fillStyle = th.inkMuted; ctx.font = "8px 'Chakra Petch', monospace"; ctx.textBaseline = 'alphabetic';
  ctx.fillText('PLAN' + (s.darkMode ? ' — NUIT' : ''), PX, PY - 4);

  ctx.beginPath(); roundRect(ctx, PX, PY, W, Hm, 6); ctx.clip();
  ctx.fillStyle = th.stage; ctx.fillRect(PX, PY, W, Hm);
  const mx = (x) => PX + x * mxs, my = (y) => PY + y * mxs;

  // satellite : teinte de révélation totale
  if (sat) { ctx.fillStyle = TCOL.satellite + '18'; ctx.fillRect(PX, PY, W, Hm); }

  // salles
  for (const r of game.ROOMS) {
    ctx.fillStyle = s.owned[r.id] ? r.ac + '55' : 'rgba(120,120,150,.10)';
    ctx.strokeStyle = s.owned[r.id] ? r.ac : 'rgba(120,120,150,.25)'; ctx.lineWidth = 1;
    ctx.fillRect(mx(r.x), my(r.y), r.w * mxs, r.h * mxs); ctx.strokeRect(mx(r.x), my(r.y), r.w * mxs, r.h * mxs);
  }
  // zones radar
  for (const t of game.ui.placed) {
    if (t.cat === 'turret' && t.key === 'radar' && isBuilt(t)) {
      const rr = radarRadius(t) * mxs; const g = ctx.createRadialGradient(mx(t.x), my(t.y), 0, mx(t.x), my(t.y), rr);
      g.addColorStop(0, TCOL.radar + '33'); g.addColorStop(0.6, TCOL.radar + '10'); g.addColorStop(1, 'transparent');
      ctx.fillStyle = g; ctx.beginPath(); ctx.arc(mx(t.x), my(t.y), rr, 0, 7); ctx.fill();
    }
  }
  // bougies allumées
  for (let i = 0; i < game.CANDLES.length; i++) { if (game.G.lit.has(i)) { const c = game.CANDLES[i]; ctx.fillStyle = th.flame; ctx.beginPath(); ctx.arc(mx(c.x), my(c.y), 1.5, 0, 7); ctx.fill(); } }
  // tourelles + cônes
  for (const t of game.ui.placed) {
    if (t.cat !== 'turret') continue; const col = TCOL[t.key] || th.accent; const ts = turretStats(t);
    const facing = game.AIM[t.id] != null ? game.AIM[t.id] : (t.face || 0);
    if (!ts.support && !ts.heal && ts.range > 0 && isBuilt(t)) {
      ctx.save(); ctx.translate(mx(t.x), my(t.y)); ctx.rotate((facing - 90) * Math.PI / 180);
      const R = ts.range * mxs; const g = ctx.createLinearGradient(0, 0, R, 0); g.addColorStop(0, col + '66'); g.addColorStop(0.8, 'transparent');
      ctx.fillStyle = g; ctx.beginPath(); ctx.moveTo(0, 0); ctx.lineTo(R, -R * 0.3); ctx.lineTo(R, R * 0.3); ctx.closePath(); ctx.fill(); ctx.restore();
    }
    ctx.fillStyle = col; ctx.beginPath(); ctx.arc(mx(t.x), my(t.y), 2.5, 0, 7); ctx.fill();
  }
  // coffre
  ctx.fillStyle = '#e6c074'; ctx.fillRect(mx(COFFRE.x) - 3, my(COFFRE.y) - 3, 6, 6);
  // flemmes révélées
  for (const e of game.G.enemies) {
    const show = !s.darkMode || sat || enemyRevealed(game, e); if (!show) continue;
    ctx.fillStyle = th.enemy; ctx.beginPath(); ctx.arc(mx(e.x), my(e.y), 2.5, 0, 7); ctx.fill();
  }
  // héros
  ctx.fillStyle = th.flame; ctx.shadowColor = th.flame; ctx.shadowBlur = 6; ctx.beginPath(); ctx.arc(mx(game.HERO.x), my(game.HERO.y), 3, 0, 7); ctx.fill();
  ctx.restore();
}

function roundRect(ctx, x, y, w, h, r) {
  ctx.beginPath(); ctx.moveTo(x + r, y);
  ctx.arcTo(x + w, y, x + w, y + h, r); ctx.arcTo(x + w, y + h, x, y + h, r);
  ctx.arcTo(x, y + h, x, y, r); ctx.arcTo(x, y, x + w, y, r); ctx.closePath();
}
