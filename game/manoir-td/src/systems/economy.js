// Économie façon Supreme Commander : masse plafonnée (overflow perdu), mottes ramassées au
// passage, gisements de cristaux rechargeables récoltés au faisceau (bras droit).
import { HARVEST_RATE, CRYST_RECHARGE, VIS } from '../config.js';
import { blocked } from '../geometry.js';

export function updateEconomy(game, dt) {
  const G = game.G, H = game.HERO;

  // mottes : ramassées par le Commander à < 34 px ; déclinent sinon (overflow perdu)
  if (G.mottes.length) {
    for (const m of G.mottes) {
      m.life -= dt;
      if (Math.hypot(m.x - H.x, m.y - H.y) < 34) {
        const room = Math.max(0, G.massCap - G.mass);
        G.mass += Math.min(m.val, room);
        m.life = 0;
      }
    }
    G.mottes = G.mottes.filter(m => m.life > 0);
  }

  // recharge des gisements (ne s'épuisent jamais définitivement)
  game._harvestId = null;
  for (const cr of game.CRYSTALS) if (cr.amount < cr.max) cr.amount = Math.min(cr.max, cr.amount + CRYST_RECHARGE * dt);

  // récolte (bras droit) : s'arrête si on bâtit (priorité chantier) ou si la masse est pleine
  if (game._buildId == null && G.mass < G.massCap) {
    let nc = null, nd = 1e9;
    for (const cr of game.CRYSTALS) {
      if (cr.amount <= 0) continue;
      const d = Math.hypot(cr.x - H.x, cr.y - H.y);
      if (d <= VIS && !blocked(game.WALLS, H.x, H.y, cr.x, cr.y) && d < nd) { nd = d; nc = cr; }
    }
    if (nc) {
      game._harvestId = game.CRYSTALS.indexOf(nc);
      const room = Math.max(0, G.massCap - G.mass);
      const take = Math.min(HARVEST_RATE * dt, nc.amount, room);
      nc.amount -= take; G.mass += take;
    }
  }
}
