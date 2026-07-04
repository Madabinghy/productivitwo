// Manoir d'Ombrelune — Tower Defense V1
// Constantes d'équilibrage et de design, portées fidèlement du prototype de référence
// (Manoir - Aménagement.dc.html). Valeurs de travail : ajustables.

export const MAP = { W: 2900, H: 1760, L: 40, T: 40, R: 2860, B: 1720 };
export const GRID = 46;
export let VPW = 1080, VPH = 680;            // viewport logique (mobile : épouse l'écran)
// Mobile : la fenêtre de caméra devient la taille CSS réelle du canvas (vue
// zoomée 1:1 qui suit le Commander, pan à 2 doigts) — liaisons vives ES modules.
export function setViewport(w, h) { VPW = Math.round(w); VPH = Math.round(h); }

export const VIS = 200;                       // vision héros (pose de tourelles, laser)
export const CANDLE_VIS = 140;                // vision bougie
// Nuit noire : petite bulle personnelle + cône de vision devant le Commander (lampe).
export const NIGHT_HALO = 92;                 // rayon de la bulle autour du Commander
export const NIGHT_CONE = 380;                // portée du cône de vision (regard)
export const NIGHT_CONE_HALF = 33;            // demi-angle du cône, en degrés

export const HERO = { speed: 185, hp: 100, turnRate: 560, laserCd: 0.5, laserDmg: 7 };

export const MASS_START = 85, MASS_CAP = 150;
export const HARVEST_RATE = 58;
export const CRYST_RECHARGE = 18;
export const BUILD_RANGE = 82;

export const COFFRE = { x: 720, y: 1380 };
export const COFFRE_BREACH = 54;

export const ENEMY = {
  chaseDist: 300, chaseSpeed: 110, contactDist: 24, contactDmg: 20,
  spawnEvery: 5, cap: 26, blowDist: 30, turretFireDist: 175, turretDmg: 7,
};

// Salles du manoir (id, nom, rect, couleur d'accent)
export const ROOMS = [
  { id: 'biblio',  name: 'Bibliothèque',   x: 120,  y: 120,  w: 860, h: 640, ac: '#7d9bff' },
  { id: 'observ',  name: 'Observatoire',   x: 1240, y: 120,  w: 580, h: 580, ac: '#3df0ff' },
  { id: 'galerie', name: 'Galerie',        x: 2060, y: 120,  w: 720, h: 440, ac: '#c77dff' },
  { id: 'entree',  name: "Hall d'entrée",  x: 120,  y: 1000, w: 860, h: 640, ac: '#9fe8ff' },
  { id: 'hall',    name: 'Grand Hall',     x: 1240, y: 940,  w: 720, h: 700, ac: '#ff6b3d' },
  { id: 'bal',     name: 'Salle de bal',   x: 2200, y: 760,  w: 580, h: 880, ac: '#ff3d6e' },
];
export const DOORSIDE = { biblio: 'bottom', observ: 'left', galerie: 'left', entree: 'top', hall: 'left', bal: 'left' };

// Couleurs des éléments (tourelles / soutien)
export const TCOL = {
  brasier: '#ff6b3d', givre: '#3df0ff', fulgur: '#ffe14d', venin: '#6fff5a',
  arcane: '#c77dff', spectre: '#7d9bff', calice: '#ff3d6e', sniper: '#cfe7ff',
  bercail: '#7bff9b', radar: '#46e6b4', satellite: '#ffce5e', bouclier: '#6fa8ff',
};

export const TURRET_ITEMS = [
  { key: 'brasier', name: 'Brasier', el: 'Feu' },
  { key: 'givre',   name: 'Givre',   el: 'Glace' },
  { key: 'fulgur',  name: 'Fulgur',  el: 'Foudre' },
  { key: 'venin',   name: 'Venin',   el: 'Poison' },
  { key: 'arcane',  name: 'Arcane',  el: 'Arcane' },
  { key: 'spectre', name: 'Spectre', el: 'Spectral' },
  { key: 'calice',  name: 'Calice',  el: 'Sang' },
  { key: 'sniper',  name: 'Sniper',  el: 'Précision' },
];
export const SUPPORT_ITEMS = [
  { key: 'bercail',   name: 'Bercail',         el: 'Soin' },
  { key: 'bouclier',  name: 'Bouclier',        el: 'Protection' },
  { key: 'radar',     name: 'Radar des âmes',  el: 'Détection' },
  { key: 'satellite', name: 'Œil-satellite',   el: 'Révélation' },
];
export const UNIT_ITEMS = [
  { key: 'tortue', name: 'Cuirassé-tortue', el: 'Unité' },
];
export const TORTUE = {
  hp: 460, speed: 30, range: 230, dmg: 11, projSpeed: 360,
  cannonInterval: 1.9, carapaceRot: 170, cannonRot: 260, deployTime: 0.6,
  cannonMounts: [-30, 30, -90, 90],  // position des 4 canons sur la carapace (offset depuis l'avant, deg)
  cannonRest: [-6, 6, -45, 45],      // visée de repos des 4 canons : 2 avant + 1 NO + 1 NE (offset depuis l'avant)
  healRadius: 150, healHero: 14, healTurret: 12,
};

export const SHOT = {
  brasier: { kind: 'proj', shot: 'fireball' }, givre: { kind: 'beam', beam: 'laser' },
  fulgur:  { kind: 'beam', beam: 'bolt' },     venin: { kind: 'proj', shot: 'glob' },
  arcane:  { kind: 'proj', shot: 'sigil' },    spectre: { kind: 'proj', shot: 'wisp' },
  calice:  { kind: 'proj', shot: 'drop' },     sniper: { kind: 'beam', beam: 'laser' },
};

export const COST = {
  brasier: { mass: 48, time: 6 },  givre: { mass: 34, time: 4.5 }, fulgur: { mass: 60, time: 7 },
  venin: { mass: 30, time: 4 },    arcane: { mass: 66, time: 7.5 }, spectre: { mass: 54, time: 6.5 },
  calice: { mass: 58, time: 7 },   sniper: { mass: 80, time: 9 },   bercail: { mass: 50, time: 6 },
  bouclier: { mass: 40, time: 5 }, radar: { mass: 46, time: 5.5 },  satellite: { mass: 110, time: 12 },
  tortue: { mass: 95, time: 11 },
};
export function costOf(key) { return COST[key] || { mass: 40, time: 5 }; }
// Améliorer une tourelle EN mission : chantier occupé (masse + temps), coût qui
// grimpe avec le niveau visé — plus jamais gratuit/instantané.
export function upgradeCost(key, level) { const c = costOf(key); return { mass: Math.round(c.mass * 0.6 * level), time: c.time * 0.7 }; }

export const DESC = {
  brasier: 'Boule de feu explosive — grosse frappe rapprochée à cadence soutenue.',
  givre: 'Rayon de glace qui transperce et fige la cible sur sa ligne.',
  fulgur: 'Éclair de foudre — longue portée et cadence très élevée.',
  venin: 'Projectile de poison à bas coût qui ronge les flemmes.',
  arcane: 'Sceau arcanique lourd à tête chercheuse, dégâts élevés.',
  spectre: 'Projectile fantôme perçant qui ignore les obstacles légers.',
  calice: 'Chaque tir de sang draine une flemme en plus du butin.',
  sniper: "Précision : portée immense et gros dégâts, mais lent. Deux axes d'amélioration (portée / dégâts).",
  bercail: 'Soin : régénère le héros et les tourelles dans son aura. Ne tire pas.',
  radar: 'Détection : révèle les flemmes proches sur le plan. Son rayon grandit à chaque niveau.',
  satellite: 'Révélation : dévoile toutes les flemmes de la carte, sur le plan et à l\'écran.',
  bouclier: 'Barrière orientable : encaisse les tirs ennemis et laisse passer les vôtres. 3 maximum.',
  tortue: 'Cuirassé-tortue : artillerie blindée. Mobile, sa carapace pivote et ses 4 canons fauchent les flemmes. Déployée : increvable & aura de soin, mais désarmée (au choix : tirer ou soigner).',
};

// 3 thèmes d'ambiance — couleurs principales pour le rendu canvas
export const THEMES = {
  ombrelune: { label: 'Néon',    bg: '#0b0816', stage: '#0a0714', accent: '#8a6cff', accentText: '#cdbfff', ink: '#e9e4f2', inkMuted: '#8a80a6', flame: '#ffcf6e', rug: '#8a6cff', roomBg: 'rgba(26,20,46,.5)', enemy: '#ff5d7a' },
  sanctum:   { label: 'Or',      bg: '#160f07', stage: '#130c05', accent: '#e0b461', accentText: '#f2d79a', ink: '#efe4cf', inkMuted: '#a8966f', flame: '#ffcf6e', rug: '#a8543e', roomBg: 'rgba(40,30,16,.5)', enemy: '#ff6b81' },
  verriere:  { label: 'Vitrail', bg: '#08131d', stage: '#06101a', accent: '#67cfe6', accentText: '#bfeaf3', ink: '#dcebf2', inkMuted: '#7c98a6', flame: '#9fe8ff', rug: '#3a7fa0', roomBg: 'rgba(14,40,54,.5)', enemy: '#ff6b81' },
};

export function baseHp(key) {
  return key === 'tortue' ? TORTUE.hp : key === 'sniper' ? 45 : key === 'bercail' ? 90 : key === 'radar' ? 75
       : key === 'satellite' ? 85 : key === 'bouclier' ? 160 : 120;
}
export function radarRadius(t) { return 360 + (((t && t.level) || 1) - 1) * 200; }

// Stats d'une tourelle selon son type et son niveau
export function turretStats(t) {
  if (t.key === 'radar') return { range: radarRadius(t), dmg: 0, interval: 0, half: 0, support: true };
  if (t.key === 'satellite') return { range: 0, dmg: 0, interval: 0, half: 0, support: true, sat: true };
  if (t.key === 'bouclier') return { range: 0, dmg: 0, interval: 0, half: 0, support: true, shield: true };
  if (t.key === 'sniper') return { range: 540 + (t.bonusR || 0) * 46, dmg: 42 + (t.bonusD || 0) * 10, interval: 1.7, half: 13 };
  if (t.key === 'bercail') return { range: 0, dmg: 0, interval: 0, half: 0, heal: true, radius: 215 };
  return { range: 210 + (t.level - 1) * 55, dmg: 9 + t.level * 5, interval: 0.6, half: 34 };
}
