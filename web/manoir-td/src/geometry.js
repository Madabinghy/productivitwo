// Géométrie : collisions de murs (segments), ligne de vue (LOS), distance de rayon.
// Porté fidèlement du prototype.
import { ROOMS } from './config.js';

export const hyp = (dx, dy) => Math.hypot(dx, dy);
export const clamp = (v, a, b) => Math.max(a, Math.min(b, v));

function ccw(ax, ay, bx, by, cx, cy) { return (cy - ay) * (bx - ax) > (by - ay) * (cx - ax); }

function segHit(x1, y1, x2, y2, w) {
  return ccw(x1, y1, w.x1, w.y1, w.x2, w.y2) !== ccw(x2, y2, w.x1, w.y1, w.x2, w.y2)
      && ccw(x1, y1, x2, y2, w.x1, w.y1) !== ccw(x1, y1, x2, y2, w.x2, w.y2);
}

// Un segment traverse-t-il un mur ?
export function blocked(walls, x1, y1, x2, y2) {
  for (const w of walls) if (segHit(x1, y1, x2, y2, w)) return true;
  return false;
}

// Ligne de vue : la trajectoire ne doit pas traverser l'intérieur d'une salle (sauf exId).
export function los(x1, y1, x2, y2, exId) {
  for (let k = 1; k < 10; k++) {
    const t = k / 10, px = x1 + (x2 - x1) * t, py = y1 + (y2 - y1) * t;
    for (const r of ROOMS) {
      if (r.id === exId) continue;
      if (px > r.x && px < r.x + r.w && py > r.y && py < r.y + r.h) return false;
    }
  }
  return true;
}

// Distance jusqu'au premier mur le long d'un rayon (pour rogner les cônes de portée).
export function rayDist(walls, ox, oy, dx, dy, maxR) {
  let best = maxR; const bx = ox + dx * maxR, by = oy + dy * maxR;
  for (const w of walls) {
    const den = (bx - ox) * (w.y2 - w.y1) - (by - oy) * (w.x2 - w.x1);
    if (den === 0) continue;
    const t = ((w.x1 - ox) * (w.y2 - w.y1) - (w.y1 - oy) * (w.x2 - w.x1)) / den;
    const u = ((w.x1 - ox) * (by - oy) - (w.y1 - oy) * (bx - ox)) / den;
    if (t >= 0 && t <= 1 && u >= 0 && u <= 1) { const d = t * maxR; if (d < best) best = d; }
  }
  return best;
}

export function roomAt(x, y) {
  for (const r of ROOMS) if (x > r.x && x < r.x + r.w && y > r.y && y < r.y + r.h) return r;
  return null;
}

// Angle « boussole » en degrés : 0 = haut, 90 = droite (atan2(dx, -dy)).
export const compass = (dx, dy) => ((Math.atan2(dx, -dy) * 180 / Math.PI) % 360 + 360) % 360;
// Différence d'angle signée la plus courte dans [-180, 180].
export const angDiff = (a, b) => ((a - b + 540) % 360) - 180;
