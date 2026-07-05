// Panneau latéral (DOM) : onglets Tourelles / Soutien, cartes d'items sélectionnables,
// et fiche détail/amélioration de la tourelle sélectionnée.
import { TURRET_ITEMS, SUPPORT_ITEMS, UNIT_ITEMS, BUILDING_ITEMS, PRODUCES, UNITS, TCOL, DESC, costOf, turretStats } from '../config.js';
import { setTab, selectItem, upgrade, upSniper, removeSel, setAim, clearSel } from '../systems/placement.js';
import { upgradeCost } from '../config.js';
import { deployUnit } from '../systems/units.js';
import { trainUnit } from '../systems/production.js';

const TABS = [{ k: 'turret', label: 'Tourelles' }, { k: 'support', label: 'Soutien' }, { k: 'building', label: 'Bâtiments' }, { k: 'unit', label: 'Unités' }];
const UCOL = { tortue: '#9ad06a' };

function chip(col) { const d = document.createElement('span'); d.className = 'dot'; d.style.background = col; d.style.boxShadow = '0 0 9px ' + col; return d; }

export function createPanel(game) {
  const root = document.getElementById('panel');
  let sig = '';

  function signature() {
    const s = game.ui;
    const placed = s.placed.map(p => p.id + ':' + p.key + ':' + p.level + ':' + (p.built ? 1 : 0) + ':' + (p.deployed ? 1 : 0)).join(',');
    const sel = s.selId ? (() => { const t = s.placed.find(p => p.id === s.selId); return t ? t.id + t.key + t.level + (t.bonusR || 0) + (t.bonusD || 0) + (t.upgrading ? 'u' + Math.round((t.upProg || 0) * 20) : '') + (t._trainCd ? 'c' + Math.ceil(t._trainCd * 4) : '') : ''; })() : '';
    // masse (par paliers) : rafraîchit l'état actif/grisé des boutons de fabrication d'un producteur
    const massBucket = (s.selId && PRODUCES[(s.placed.find(p => p.id === s.selId) || {}).key]) ? Math.round((game.G.mass || 0) / 8) : 0;
    const snCd = s.selId ? Math.ceil(Math.max(0, ((s.placed.find(p => p.id === s.selId) || {})._next || 0) - (game.G.time || 0))) : 0;
    const roster = game.save ? game.save.roster.turrets.join(',') : '';
    return [s.tab, s.sel && s.sel.key, s.selId, s.aimMode, placed, sel, snCd, massBucket, Object.keys(game.STASH).join(''), roster].join('|');
  }

  function build() {
    root.innerHTML = '';
    const s = game.ui;
    const selT = s.placed.find(p => p.id === s.selId && (p.cat === 'turret' || p.cat === 'unit'));
    if (selT) { (selT.cat === 'unit' ? buildUnitDetail : buildDetail)(root, game, selT); return; }

    // onglets
    const tabs = document.createElement('div'); tabs.className = 'tabs';
    for (const t of TABS) {
      const b = document.createElement('button'); b.className = 'tab' + (s.tab === t.k ? ' on' : ''); b.textContent = t.label;
      b.onclick = () => setTab(game, t.k); tabs.appendChild(b);
    }
    root.appendChild(tabs);

    const roster = game.save ? game.save.roster.turrets : null;
    const isUnit = s.tab === 'unit'; const isBuilding = s.tab === 'building'; const cat = isUnit ? 'unit' : 'turret';
    const items = s.tab === 'support' ? SUPPORT_ITEMS : isBuilding ? BUILDING_ITEMS : isUnit ? UNIT_ITEMS : TURRET_ITEMS;
    for (const it of items) {
      const locked = isBuilding ? false : (roster ? !roster.includes(it.key) : false);
      const cnt = s.placed.filter(p => p.cat === cat && p.key === it.key).length;
      const max = it.key === 'satellite' ? 1 : Infinity; const dep = cnt >= max;
      const c = costOf(it.key); const col = UCOL[it.key] || TCOL[it.key] || '#8a6cff';
      const card = document.createElement('div');
      card.className = 'card' + (s.sel && s.sel.key === it.key ? ' on' : '') + ((dep || locked) ? ' dim' : '');
      const ico = document.createElement('div'); ico.className = 'ico'; ico.appendChild(chip(locked ? '#5a5566' : col));
      const txt = document.createElement('div');
      const nm = document.createElement('div'); nm.className = 'nm'; nm.textContent = (locked ? '🔒 ' : '') + it.name;
      const mt = document.createElement('div'); mt.className = 'mt';
      mt.textContent = locked ? 'À débloquer en campagne'
                     : dep ? (max > 1 ? cnt + '/' + max + ' déployés · ⎵ pour récupérer' : 'Déployée · ⎵ pour récupérer')
                           : ('✦' + c.mass + ' · ' + c.time + 's · ' + (DESC[it.key] || ''));
      txt.appendChild(nm); txt.appendChild(mt);
      card.appendChild(ico); card.appendChild(txt);
      if (locked) card.onclick = () => { game.ui.msg = '🔒 « ' + it.name + ' » se débloque en gagnant une mission de campagne.'; };
      else if (dep) card.onclick = () => { game.ui.msg = 'Déjà déployé — récupère-le (Espace sur la tourelle).'; };
      else card.onclick = () => selectItem(game, cat, it.key, it.name);
      root.appendChild(card);
    }

    const hint = document.createElement('div'); hint.className = 'hint';
    hint.textContent = isUnit
      ? "Pose un Cuirassé-tortue dans ta lumière, le Commander le bâtit. Clique-le pour le sélectionner : clic = déplacement (artillerie qui tire en roulant), bouton Déployer = increvable + aura de soin (désarmé)."
      : isBuilding
      ? "Pose un bâtiment (Atelier → chars à chenilles, Caserne → infanterie) dans ta lumière ; le Commander le bâtit. Sélectionne-le ensuite pour fabriquer des unités à la demande (chaque unité coûte de la masse, puis se commande au clic)."
      : s.tab === 'turret'
      ? "Sélectionne une tourelle puis clique dans le halo du héros (ou d'une bougie) pour poser un chantier. Le Commander le bâtit en restant à portée de vision."
      : 'Bercail : soigne héros & tourelles. Bouclier : oriente-le pour encaisser les tirs ennemis. Radar : révèle les flemmes voisines. Œil-satellite : révèle toute la carte (un seul).';
    root.appendChild(hint);
  }

  function buildProducerDetail(root, game, t, col) {
    const it = BUILDING_ITEMS.find(x => x.key === t.key);
    const card = document.createElement('div'); card.className = 'detail'; card.style.borderColor = col + '88';
    const h = document.createElement('div'); h.className = 'dh'; h.textContent = it ? it.name : t.key; card.appendChild(h);
    const st = document.createElement('div'); st.className = 'ds';
    const role = t.key === 'caserne' ? '⚔ Entraîne de l\'infanterie' : '⚙ Fabrique des tourelles mobiles';
    st.textContent = t.built === false ? '⚒ En construction… ' + Math.round((t.prog || 0) * 100) + '%'
      : role + '   ♥ ' + Math.round(t.hp || 0) + '/' + (t.maxHp || 0);
    card.appendChild(st);
    const dd = document.createElement('div'); dd.className = 'dd'; dd.textContent = DESC[t.key] || ''; card.appendChild(dd);
    if (t.built !== false) {
      const cd = Math.max(0, t._trainCd || 0);
      for (const uk of (PRODUCES[t.key] || [])) {
        const u = UNITS[uk], cost = costOf(uk).mass, busy = cd > 0.05, poor = (game.G.mass || 0) < cost;
        const b = document.createElement('button'); b.className = 'act btn-up' + (busy || poor ? ' max' : '');
        b.textContent = busy ? ('⏳ Occupé (' + cd.toFixed(1) + 's)') : ((u ? u.name : uk) + ' · ' + cost + ' ✦');
        b.onclick = () => trainUnit(game, t, uk);
        card.appendChild(b);
      }
    }
    const rm = document.createElement('button'); rm.className = 'act btn-rm'; rm.textContent = 'Récupérer'; rm.onclick = () => removeSel(game); card.appendChild(rm);
    const back = document.createElement('button'); back.className = 'act btn-back'; back.textContent = '← Retour'; back.onclick = () => clearSel(game); card.appendChild(back);
    root.appendChild(card);
  }

  function buildDetail(root, game, t) {
    const ds = turretStats(t); const col = TCOL[t.key] || '#8a6cff';
    if (PRODUCES[t.key]) { buildProducerDetail(root, game, t, col); return; }
    const it = TURRET_ITEMS.concat(SUPPORT_ITEMS).find(x => x.key === t.key);
    const noAim = t.key === 'radar' || t.key === 'satellite';
    const maxed = (t.key !== 'sniper' && t.level >= 4) || t.key === 'satellite' || t.key === 'bouclier';
    const card = document.createElement('div'); card.className = 'detail'; card.style.borderColor = col + '88';

    const h = document.createElement('div'); h.className = 'dh'; h.textContent = it ? it.name : t.key; card.appendChild(h);
    const st = document.createElement('div'); st.className = 'ds';
    st.textContent = t.key === 'radar' ? '◎ Révèle les flemmes ≤ ' + Math.round(ds.range) + ' px sur le plan'
      : t.key === 'satellite' ? '✦ Révèle toutes les flemmes'
      : t.key === 'bouclier' ? '⛨ Bloque les tirs ennemis · laisse passer les vôtres'
      : ds.heal ? '✚ Soigne héros & tourelles · rayon ' + Math.round(ds.radius)
      : '⚔ ' + Math.round(ds.dmg) + '   ◎ ' + Math.round(ds.range);
    card.appendChild(st);
    const dd = document.createElement('div'); dd.className = 'dd'; dd.textContent = DESC[t.key] || ''; card.appendChild(dd);

    if (!noAim && !ds.support && !ds.heal) {
      const a = document.createElement('button'); a.className = 'act btn-aim' + (game.ui.aimMode ? ' on' : '');
      a.textContent = game.ui.aimMode ? 'Clique un point à viser…' : '◎ Viser (définir le focus)';
      a.onclick = () => setAim(game); card.appendChild(a);
    }
    if (t.key === 'sniper') {
      const ready = (game.G.time || 0) >= (t._next || 0); const cd = Math.max(0, Math.ceil((t._next || 0) - (game.G.time || 0)));
      const row = document.createElement('div'); row.className = 'row2';
      const br = document.createElement('button'); br.className = 'act btn-up'; br.textContent = ready ? '+1 portée' : '⏳ ' + cd + 's'; br.onclick = () => upSniper(game, 'r');
      const bd = document.createElement('button'); bd.className = 'act btn-up'; bd.textContent = ready ? '+10 dégâts' : '⏳ ' + cd + 's'; bd.onclick = () => upSniper(game, 'd');
      row.appendChild(br); row.appendChild(bd); card.appendChild(row);
    } else {
      const u = document.createElement('button'); u.className = 'act btn-up' + (maxed ? ' max' : '');
      if (t.upgrading) { u.className = 'act btn-up'; u.textContent = '⚒ Amélioration ' + Math.round((t.upProg || 0) * 100) + '%…'; }
      else if (t.key === 'satellite') u.textContent = 'Révélation totale';
      else if (t.key === 'bouclier') u.textContent = 'Barrière fixe';
      else if (maxed) u.textContent = 'Niveau maximum';
      else { const uc = upgradeCost(t.key, t.level); const label = t.key === 'radar' ? 'Élargir le rayon' : 'Améliorer';
        u.textContent = label + ' (niv ' + t.level + '→' + (t.level + 1) + ') · ' + uc.mass + ' ✦'; u.onclick = () => upgrade(game); }
      card.appendChild(u);
    }
    const rm = document.createElement('button'); rm.className = 'act btn-rm'; rm.textContent = 'Récupérer'; rm.onclick = () => removeSel(game); card.appendChild(rm);
    const back = document.createElement('button'); back.className = 'act btn-back'; back.textContent = '← Retour'; back.onclick = () => clearSel(game); card.appendChild(back);
    root.appendChild(card);
  }

  function buildUnitDetail(root, game, u) {
    const ud = UNITS[u.key];
    const col = UCOL[u.key] || (ud && ud.color) || '#9ad06a';
    const card = document.createElement('div'); card.className = 'detail'; card.style.borderColor = col + '88';
    const h = document.createElement('div'); h.className = 'dh'; h.textContent = ud ? ud.name : 'Cuirassé-tortue'; card.appendChild(h);
    const st = document.createElement('div'); st.className = 'ds';
    if (ud) {
      const kindLabel = ud.kind === 'infantry' ? '⚔ Infanterie · clique pour la déplacer' : '⚔ Tourelle mobile · clique pour la déplacer';
      st.textContent = (u.built === false ? '⚒ En construction…' : kindLabel) + '   ♥ ' + Math.round(u.hp || 0) + '/' + (u.maxHp || 0);
    } else {
      st.textContent = u.built === false ? '⚒ En construction…' : (u.deployed ? '⛨ Déployé — increvable · aura de soin · désarmé' : '⚔ Artillerie mobile · 4 canons · clique pour le déplacer') + '   ♥ ' + Math.round(u.hp || 0) + '/' + (u.maxHp || 0);
    }
    card.appendChild(st);
    const dd = document.createElement('div'); dd.className = 'dd'; dd.textContent = ud ? (DESC[u.key] || '') : DESC.tortue; card.appendChild(dd);
    if (!ud && u.built !== false) {
      const dpl = document.createElement('button'); dpl.className = 'act btn-aim' + (u.deployed ? ' on' : '');
      dpl.textContent = u.deployed ? '⤺ Replier (artillerie mobile)' : '⛨ Déployer (increvable + aura de soin)';
      dpl.onclick = () => deployUnit(game, u); card.appendChild(dpl);
    }
    const rm = document.createElement('button'); rm.className = 'act btn-rm'; rm.textContent = 'Récupérer'; rm.onclick = () => removeSel(game); card.appendChild(rm);
    const back = document.createElement('button'); back.className = 'act btn-back'; back.textContent = '← Retour'; back.onclick = () => clearSel(game); card.appendChild(back);
    root.appendChild(card);
  }

  build();
  return { refresh() { const ns = signature(); if (ns !== sig) { sig = ns; build(); } } };
}
