// Panneau latéral (DOM) : onglets Tourelles / Soutien, cartes d'items sélectionnables,
// et fiche détail/amélioration de la tourelle sélectionnée.
import { TURRET_ITEMS, SUPPORT_ITEMS, TCOL, DESC, costOf, turretStats } from '../config.js';
import { setTab, selectItem, upgrade, upSniper, removeSel, setAim, clearSel } from '../systems/placement.js';

const TABS = [{ k: 'turret', label: 'Tourelles' }, { k: 'support', label: 'Soutien' }];

function chip(col) { const d = document.createElement('span'); d.className = 'dot'; d.style.background = col; d.style.boxShadow = '0 0 9px ' + col; return d; }

export function createPanel(game) {
  const root = document.getElementById('panel');
  let sig = '';

  function signature() {
    const s = game.ui;
    const placed = s.placed.map(p => p.id + ':' + p.key + ':' + p.level + ':' + (p.built ? 1 : 0)).join(',');
    const sel = s.selId ? (() => { const t = s.placed.find(p => p.id === s.selId); return t ? t.id + t.key + t.level + (t.bonusR || 0) + (t.bonusD || 0) : ''; })() : '';
    const snCd = s.selId ? Math.ceil(Math.max(0, ((s.placed.find(p => p.id === s.selId) || {})._next || 0) - (game.G.time || 0))) : 0;
    return [s.tab, s.sel && s.sel.key, s.selId, s.aimMode, placed, sel, snCd, Object.keys(game.STASH).join('')].join('|');
  }

  function build() {
    root.innerHTML = '';
    const s = game.ui;
    const selT = s.placed.find(p => p.id === s.selId && p.cat === 'turret');
    if (selT) { buildDetail(root, game, selT); return; }

    // onglets
    const tabs = document.createElement('div'); tabs.className = 'tabs';
    for (const t of TABS) {
      const b = document.createElement('button'); b.className = 'tab' + (s.tab === t.k ? ' on' : ''); b.textContent = t.label;
      b.onclick = () => setTab(game, t.k); tabs.appendChild(b);
    }
    root.appendChild(tabs);

    const items = s.tab === 'support' ? SUPPORT_ITEMS : TURRET_ITEMS;
    for (const it of items) {
      const cnt = s.placed.filter(p => p.cat === 'turret' && p.key === it.key).length;
      const max = it.key === 'bouclier' ? 3 : 1; const dep = cnt >= max;
      const c = costOf(it.key);
      const card = document.createElement('div');
      card.className = 'card' + (s.sel && s.sel.key === it.key ? ' on' : '') + (dep ? ' dim' : '');
      const ico = document.createElement('div'); ico.className = 'ico'; ico.appendChild(chip(TCOL[it.key] || '#8a6cff'));
      const txt = document.createElement('div');
      const nm = document.createElement('div'); nm.className = 'nm'; nm.textContent = it.name;
      const mt = document.createElement('div'); mt.className = 'mt';
      mt.textContent = dep ? (max > 1 ? cnt + '/' + max + ' déployés · ⎵ pour récupérer' : 'Déployée · ⎵ pour récupérer')
                           : ('✦' + c.mass + ' · ' + c.time + 's · ' + (it.key === 'bouclier' ? cnt + '/3 — ' : '') + (DESC[it.key] || ''));
      txt.appendChild(nm); txt.appendChild(mt);
      card.appendChild(ico); card.appendChild(txt);
      if (dep) card.onclick = () => { game.ui.msg = 'Déjà déployé — récupère-le (Espace sur la tourelle).'; };
      else card.onclick = () => selectItem(game, s.tab === 'support' ? 'turret' : 'turret', it.key, it.name);
      root.appendChild(card);
    }

    const hint = document.createElement('div'); hint.className = 'hint';
    hint.textContent = s.tab === 'turret'
      ? "Sélectionne une tourelle puis clique dans le halo du héros (ou d'une bougie) pour poser un chantier. Le Commander le bâtit en restant à portée de vision."
      : 'Bercail : soigne héros & tourelles. Bouclier (3 max) : oriente-le pour encaisser les tirs ennemis. Radar : révèle les flemmes voisines. Œil-satellite : révèle toute la carte.';
    root.appendChild(hint);
  }

  function buildDetail(root, game, t) {
    const ds = turretStats(t); const col = TCOL[t.key] || '#8a6cff';
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
      u.textContent = t.key === 'satellite' ? 'Révélation totale' : t.key === 'bouclier' ? 'Barrière fixe'
        : maxed ? 'Niveau maximum' : (t.key === 'radar' ? 'Élargir le rayon (niv ' + t.level + '→' + (t.level + 1) + ')' : 'Améliorer (niv ' + t.level + '→' + (t.level + 1) + ')');
      if (!maxed) u.onclick = () => upgrade(game);
      card.appendChild(u);
    }
    const rm = document.createElement('button'); rm.className = 'act btn-rm'; rm.textContent = 'Récupérer'; rm.onclick = () => removeSel(game); card.appendChild(rm);
    const back = document.createElement('button'); back.className = 'act btn-back'; back.textContent = '← Retour'; back.onclick = () => clearSel(game); card.appendChild(back);
    root.appendChild(card);
  }

  build();
  return { refresh() { const ns = signature(); if (ns !== sig) { sig = ns; build(); } } };
}
