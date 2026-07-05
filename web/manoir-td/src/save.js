// Sauvegarde du jeu (1 clé JSON) — persiste seenTutorial + stats + roster + progression.
// Passe par l'adaptateur store.js (localStorage aujourd'hui, Firestore demain sans
// changer cette API).
import { load, save } from './store.js';
const KEY = 'manoir_save_v1';

export function defaultSave() {
  return {
    version: 1,
    currentNode: 'm1',
    done: [], unlocked: ['m1'],
    roster: { turrets: ['brasier', 'givre', 'tortue', 'atelier'], units: [], upgrades: [] },
    stats: { kills: 0, missionsWon: 0 },
    seenTutorial: false,
  };
}

export function loadSave() {
  const s = load(KEY);
  return (s && s.version === 1) ? s : null;
}

export function writeSave(s) { save(KEY, s); }

export function hasSave() { return !!loadSave(); }
