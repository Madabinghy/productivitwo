// Pose des items : fantôme de visée, sélection d'une tourelle posée, création d'un chantier.
import { GRID, baseHp, costOf, TURRET_ITEMS, SUPPORT_ITEMS } from '../config.js';
import { compass } from '../geometry.js';
import { canPlaceAt } from './vision.js';

const nameOf = (key) => { const it = TURRET_ITEMS.concat(SUPPORT_ITEMS).find(z => z.key === key); return it ? it.name : key; };

export function setGhost(game, wx, wy) { game._ghostW = { wx, wy }; }
export function clearGhost(game) { game._ghostW = null; }

// Clic / tap dans le monde.
export function actAt(game, wx, wy, touch) {
  const s = game.ui;

  // une tourelle est sélectionnée : re-cibler sa visée ou sélectionner une autre
  if (s.selId) {
    const other = s.placed.find(p => p.cat === 'turret' && p.id !== s.selId && Math.hypot(p.x - wx, p.y - wy) < 30);
    if (other) { s.selId = other.id; s.aimMode = false; return; }
    const selfT = s.placed.find(p => p.id === s.selId && p.cat === 'turret');
    if (selfT) {
      if (selfT.key === 'radar' || selfT.key === 'satellite') return;
      if (Math.hypot(selfT.x - wx, selfT.y - wy) < 16) return;
      selfT.face = compass(wx - selfT.x, wy - selfT.y); s.aimMode = false;
      s.msg = 'Visée fixée vers ce point — la tourelle garde cet angle.'; return;
    }
  }

  // clic sur une tourelle posée → sélection
  const hit = s.placed.find(p => p.cat === 'turret' && Math.hypot(p.x - wx, p.y - wy) < 32);
  if (hit) { s.selId = hit.id; s.aimMode = false; return; }

  if (!s.sel) return;
  if (!canPlaceAt(game, wx, wy)) {
    game._pendingTap = null; clearGhost(game);
    s.msg = 'Hors de ton champ de vision — approche le héros, allume une bougie proche, ou couvre la zone avec une tourelle / un radar.';
    return;
  }
  if (s.sel.cat === 'turret') {
    const cnt = s.placed.filter(p => p.cat === 'turret' && p.key === s.sel.key).length;
    const max = s.sel.key === 'bouclier' ? 3 : 1;
    if (cnt >= max) { s.msg = s.sel.key === 'bouclier' ? "Maximum 3 boucliers — récupères-en un d'abord (Espace dessus)." : "Une seule de ce type — récupère-la d'abord (Espace dessus)."; return; }
  }
  if (touch) {
    const pend = game._pendingTap;
    if (pend && Math.hypot(pend.x - wx, pend.y - wy) < 44) { game._pendingTap = null; clearGhost(game); doPlace(game, wx, wy); }
    else { game._pendingTap = { x: wx, y: wy }; setGhost(game, wx, wy); s.msg = 'Emplacement valide — touchez à nouveau au même endroit pour confirmer.'; }
    return;
  }
  doPlace(game, wx, wy);
}

export function doPlace(game, wx, wy) {
  const s = game.ui;
  const gx = Math.round(wx / GRID) * GRID, gy = Math.round(wy / GRID) * GRID;
  let face = 0;
  if (s.sel.cat === 'turret') { let bd = 1e9; for (const en of game.ENTRY) { const p = game.NODES[en]; const d = Math.hypot(p.x - gx, p.y - gy); if (d < bd) { bd = d; face = compass(p.x - gx, p.y - gy); } } }
  const key = s.sel.key;
  const sv = (s.sel.cat === 'turret' && game.STASH[key]) ? game.STASH[key] : null; if (sv) delete game.STASH[key];
  const mhp = baseHp(key); const isT = s.sel.cat === 'turret'; const chantier = isT && !sv; const c = costOf(key);
  s.placed.push({
    id: game.G.nextId++, cat: s.sel.cat, key, x: gx, y: gy, face,
    level: sv ? sv.level : 1, bonusR: sv ? sv.bonusR : 0, bonusD: sv ? sv.bonusD : 0,
    maxHp: sv ? (sv.maxHp || mhp) : mhp, hp: sv ? sv.hp : mhp,
    built: chantier ? false : true, prog: chantier ? 0 : 1,
  });
  s.msg = isT ? (sv ? 'Tourelle redéployée — niveau & PV conservés.' : '⚒ Chantier posé (' + c.mass + ' masse · ' + c.time + 's) — amène le Commander à côté pour le bâtir.') : 'Décor posé.';
}

// ---- actions UI (panneau latéral) ----
export function setTab(game, t) {
  const cat = t === 'decor' ? 'decor' : 'turret';
  const key = t === 'turret' ? 'givre' : t === 'support' ? 'radar' : 'bookshelf';
  game.ui.tab = t; game.ui.sel = { cat, key }; game.ui.selId = null;
}
export function selectItem(game, cat, key, name) {
  game._pendingTap = null; clearGhost(game);
  game.ui.sel = { cat, key }; game.ui.selId = null;
  game.ui.msg = '« ' + name + ' » prêt — clique (ou touchez) dans ton champ de vision pour le déposer.';
}
export function clearSel(game) { game.ui.selId = null; game.ui.aimMode = false; }
export function setAim(game) {
  game.ui.aimMode = !game.ui.aimMode;
  game.ui.msg = game.ui.aimMode ? 'Clique un point dans la portée pour orienter la visée de la tourelle.' : 'Visée annulée.';
}
export function upgrade(game) {
  const t = game.ui.placed.find(x => x.id === game.ui.selId); if (!t) return;
  if (t.key === 'sniper' || t.key === 'satellite' || t.key === 'bouclier') return;
  if (t.level < 4) { t.level++; game.ui.msg = 'Amélioré (niv ' + t.level + ').'; }
}
export function upSniper(game, kind) {
  const t = game.ui.placed.find(x => x.id === game.ui.selId); if (!t || t.key !== 'sniper') return;
  if ((game.G.time || 0) < (t._next || 0)) { game.ui.msg = 'Prochaine amélioration bientôt disponible.'; return; }
  t._next = (game.G.time || 0) + 60;
  if (kind === 'r') { t.bonusR = (t.bonusR || 0) + 1; game.ui.msg = 'Sniper : +1 carré de portée.'; }
  else { t.bonusD = (t.bonusD || 0) + 1; game.ui.msg = 'Sniper : +10 dégâts.'; }
}
export function removeSel(game) {
  const t = game.ui.placed.find(x => x.id === game.ui.selId); if (!t) return;
  const unbuilt = t.built === false;
  if (t.cat === 'turret' && !unbuilt) game.STASH[t.key] = { level: t.level, bonusR: t.bonusR || 0, bonusD: t.bonusD || 0, hp: t.hp, maxHp: t.maxHp };
  game.ui.placed = game.ui.placed.filter(x => x.id !== game.ui.selId); game.ui.selId = null;
  game.ui.msg = unbuilt ? 'Chantier annulé.' : 'Tourelle récupérée (niveau & PV conservés).';
}

// Espace : récupère la tourelle sous le héros (chantier → annulé ; bâtie → rangée dans STASH).
export function pickupUnderHero(game) {
  const H = game.HERO, s = game.ui;
  const t = s.placed.find(p => p.cat === 'turret' && Math.hypot(p.x - H.x, p.y - H.y) < 42); if (!t) return;
  if (t.built === false) { s.placed = s.placed.filter(x => x.id !== t.id); s.selId = null; s.msg = 'Chantier annulé.'; return; }
  game.STASH[t.key] = { level: t.level, bonusR: t.bonusR || 0, bonusD: t.bonusD || 0, hp: t.hp, maxHp: t.maxHp };
  s.placed = s.placed.filter(x => x.id !== t.id); s.selId = null;
  s.msg = 'Tourelle « ' + nameOf(t.key) + ' » récupérée (niveau & PV conservés).';
}
