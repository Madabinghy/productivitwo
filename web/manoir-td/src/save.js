// Sauvegarde locale (localStorage, 1 clé JSON) — Lot 1 du flux de jeu.
// V1 : on persiste surtout seenTutorial + stats + roster (la progression de campagne
// viendra avec la carte aux lots suivants).
const KEY = 'manoir_save_v1';

export function defaultSave() {
  return {
    version: 1,
    currentNode: 'm1',
    done: [], unlocked: ['m1'],
    roster: { turrets: ['brasier', 'givre', 'tortue'], units: [], upgrades: [] },
    stats: { kills: 0, missionsWon: 0 },
    seenTutorial: false,
  };
}

export function loadSave() {
  try {
    const raw = localStorage.getItem(KEY);
    if (!raw) return null;
    const s = JSON.parse(raw);
    return (s && s.version === 1) ? s : null;
  } catch (e) { return null; }
}

export function writeSave(s) {
  try { localStorage.setItem(KEY, JSON.stringify(s)); } catch (e) { /* mode privé : on ignore */ }
}

export function hasSave() { return !!loadSave(); }
