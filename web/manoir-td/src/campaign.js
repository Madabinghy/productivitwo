// Carte de campagne — données des nœuds (mission → récompense → déblocage) et logique.
// Structure inspirée de protos-reference/Carte de campagne - Roadmap.dc.html (phases + nœuds),
// modèle de nœud du FLUX-DE-JEU (requires / reward / mission).
export const PHASES = [
  { name: 'PHASE I — FONDATIONS', col: '#9ad06a' },
  { name: 'PHASE II — MURAILLES', col: '#e7c98a' },
  { name: 'PHASE III — LA VEILLEUSE', col: '#c79bff' },
];

// x/y dans un repère 1080×420 (carte DOM).
export const NODES = [
  { id: 'm1', p: 0, x: 110, y: 300, name: "Hall d'entrée", requires: [], reward: { turret: 'fulgur' }, mission: { waves: 4, night: false } },
  { id: 'm2', p: 0, x: 240, y: 170, name: 'Bibliothèque', requires: ['m1'], reward: { turret: 'venin' }, mission: { waves: 5, night: false } },
  { id: 'm3', p: 0, x: 360, y: 300, name: 'Observatoire', requires: ['m2'], reward: { support: 'radar' }, mission: { waves: 5, night: false } },
  { id: 'm4', p: 1, x: 500, y: 300, name: 'Galerie', requires: ['m3'], reward: { turret: 'arcane' }, mission: { waves: 6, night: false } },
  { id: 'm5', p: 1, x: 615, y: 165, name: 'Grand Hall', requires: ['m4'], reward: { turret: 'spectre' }, mission: { waves: 6, night: true } },
  { id: 'm6', p: 1, x: 735, y: 295, name: 'Salle de bal', requires: ['m5'], reward: { support: 'bercail' }, mission: { waves: 7, night: false } },
  { id: 'm7', p: 2, x: 870, y: 295, name: 'Sanctum', requires: ['m6'], reward: { turret: 'calice' }, mission: { waves: 7, night: true } },
  { id: 'm8', p: 2, x: 965, y: 165, name: 'Atelier', requires: ['m7'], reward: { support: 'bouclier' }, mission: { waves: 8, night: false } },
  { id: 'm9', p: 2, x: 1040, y: 285, name: 'La Veilleuse', requires: ['m8'], reward: { turret: 'sniper', support: 'satellite' }, mission: { waves: 10, night: true }, boss: true },
];

export function nodeById(id) { return NODES.find(n => n.id === id); }
export function isDone(save, id) { return save.done.includes(id); }
export function isUnlocked(save, node) { return node.requires.every(r => save.done.includes(r)); }

// Applique la récompense d'un nœud au roster (clés de tourelles + soutien confondues).
export function applyReward(save, node) {
  const add = (k) => { if (k && !save.roster.turrets.includes(k)) save.roster.turrets.push(k); };
  if (node.reward) { add(node.reward.turret); add(node.reward.support); }
}

// Marque un nœud réussi + débloque ce qui devient jouable.
export function completeNode(save, node) {
  if (!save.done.includes(node.id)) save.done.push(node.id);
  applyReward(save, node);
  for (const n of NODES) if (!save.unlocked.includes(n.id) && isUnlocked(save, n)) save.unlocked.push(n.id);
}
