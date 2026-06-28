// Déclin des faisceaux + déplacement des projectiles (à tête chercheuse).
import { killTarget } from './enemies.js';

export function updateEffects(game, dt) {
  const G = game.G;
  for (const b of G.beams) b.life -= dt;
  G.beams = G.beams.filter(b => b.life > 0);

  for (const p of G.projectiles) {
    const e = p.tgt;
    if (!e || e.dead || (G.enemies.indexOf(e) < 0 && (G.foes || []).indexOf(e) < 0)) { p.dead = true; continue; }
    const dx = e.x - p.x, dy = e.y - p.y, d = Math.hypot(dx, dy) || 1;
    p.ang = Math.atan2(dx, -dy) * 180 / Math.PI;
    const st = p.speed * dt;
    if (d <= st + 12) { e.hp -= p.dmg; p.dead = true; if (e.hp <= 0) killTarget(game, e); }
    else { p.x += dx / d * st; p.y += dy / d * st; }
  }
  G.projectiles = G.projectiles.filter(p => !p.dead);
}
