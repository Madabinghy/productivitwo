// Sources de vision et règle de pose « là où j'ai du champ de vision ».
import { VIS, CANDLE_VIS, NIGHT_HALO, NIGHT_CONE, NIGHT_CONE_HALF, turretStats, radarRadius } from '../config.js';
import { blocked, compass, angDiff } from '../geometry.js';

const isBuilt = (t) => !t || t.built !== false;

export function hasSatellite(game) { return game.ui.placed.some(p => p.cat === 'turret' && p.key === 'satellite' && isBuilt(p)); }

// Vision de nuit du Commander = petite bulle + cône devant lui (aligné sur le rendu du brouillard).
export function heroNightSees(game, x, y) {
  const H = game.HERO; if (!H) return false;
  if (blocked(game.WALLS, H.x, H.y, x, y)) return false;
  const d = Math.hypot(x - H.x, y - H.y);
  if (d <= NIGHT_HALO) return true;                                       // bulle personnelle
  return d <= NIGHT_CONE && Math.abs(angDiff(compass(x - H.x, y - H.y), H.dir || 0)) <= NIGHT_CONE_HALF; // cône avant
}

// Une flemme est-elle révélée ? (œil-satellite, bulle+cône du héros, bougie allumée+LOS, radar)
export function enemyRevealed(game, e) {
  if (hasSatellite(game)) return true;
  if (heroNightSees(game, e.x, e.y)) return true;
  for (const idx of game.G.lit) { const c = game.CANDLES[idx]; if (Math.hypot(e.x - c.x, e.y - c.y) < CANDLE_VIS && !blocked(game.WALLS, c.x, c.y, e.x, e.y)) return true; }
  for (const t of game.ui.placed) { if (t.cat === 'turret' && t.key === 'radar' && isBuilt(t) && Math.hypot(e.x - t.x, e.y - t.y) <= radarRadius(t)) return true; }
  return false;
}

// Une tourelle offensive a-t-elle la flemme dans sa portée + arc + LOS ?
export function turretSees(game, e) {
  for (const t of game.ui.placed) {
    if (t.cat !== 'turret' || !isBuilt(t)) continue;
    const ts = turretStats(t); if (ts.support || ts.heal || !(ts.range > 0)) continue;
    const d = Math.hypot(e.x - t.x, e.y - t.y); if (d > ts.range || blocked(game.WALLS, t.x, t.y, e.x, e.y)) continue;
    const fc = game.AIM[t.id] != null ? game.AIM[t.id] : (t.face || 0);
    if (Math.abs(angDiff(compass(e.x - t.x, e.y - t.y), fc)) <= ts.half) return true;
  }
  return false;
}

// Halo héros + bougies allumées + radars construits.
export function visionSources(game) {
  const src = []; const H = game.HERO;
  if (H) src.push({ x: H.x, y: H.y, r: VIS, kind: 'hero' });
  if (game.G.lit && game.CANDLES) for (const idx of game.G.lit) { const c = game.CANDLES[idx]; src.push({ x: c.x, y: c.y, r: CANDLE_VIS, kind: 'candle' }); }
  for (const t of game.ui.placed) { if (t.cat !== 'turret' || !isBuilt(t)) continue; if (t.key === 'radar') src.push({ x: t.x, y: t.y, r: radarRadius(t), kind: 'radar' }); }
  return src;
}

// Peut-on poser en (x,y) ? Vision directe d'une source, OU couverture d'un cône de tourelle,
// OU œil-satellite posé (lève la contrainte).
export function canPlaceAt(game, x, y) {
  const placed = game.ui.placed;
  if (placed.some(p => p.cat === 'turret' && p.key === 'satellite' && isBuilt(p))) return true;
  for (const sv of visionSources(game)) if (Math.hypot(x - sv.x, y - sv.y) <= sv.r && !blocked(game.WALLS, sv.x, sv.y, x, y)) return true;
  for (const t of placed) {
    if (t.cat !== 'turret' || !isBuilt(t)) continue;
    const ts = turretStats(t); if (ts.support || ts.heal || !(ts.range > 0)) continue;
    const d = Math.hypot(x - t.x, y - t.y); if (d > ts.range || blocked(game.WALLS, t.x, t.y, x, y)) continue;
    const fc = game.AIM[t.id] != null ? game.AIM[t.id] : (t.face || 0);
    if (Math.abs(angDiff(compass(x - t.x, y - t.y), fc)) <= ts.half) return true;
  }
  return false;
}
