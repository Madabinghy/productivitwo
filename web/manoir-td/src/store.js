// Adaptateur de persistance du Manoir — point unique à débrancher pour passer en
// full Firebase plus tard, SANS toucher aux appelants.
//
// Aujourd'hui : localStorage (synchrone).
// Demain : Firestore `users/{uid}/manoir/*` — on hydratera un cache mémoire dans
//   initStore() (await au démarrage), et load()/save()/remove() garderont la même
//   signature synchrone (lecture depuis le cache, écriture cache + push async).
// Seul ce fichier connaît le backend : le reste du jeu ne voit que load/save/remove.

const backend = {
  read(key) { try { return localStorage.getItem(key); } catch (e) { return null; } },
  write(key, raw) { try { localStorage.setItem(key, raw); } catch (e) { /* mode privé */ } },
  remove(key) { try { localStorage.removeItem(key); } catch (e) { /* mode privé */ } },
};

// Point d'entrée async pour l'avenir : hydrater le cache depuis Firestore ici.
// No-op tant qu'on est en localStorage (rien à précharger).
export async function initStore() { /* Firebase: hydrater le cache depuis users/{uid}/manoir ici */ }

// Lit une valeur JSON (ou null si absente / illisible).
export function load(key) {
  const raw = backend.read(key);
  if (raw == null) return null;
  try { return JSON.parse(raw); } catch (e) { return null; }
}

// Écrit une valeur JSON.
export function save(key, val) { backend.write(key, JSON.stringify(val)); }

// Supprime une clé.
export function remove(key) { backend.remove(key); }
