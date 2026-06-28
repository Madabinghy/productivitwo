// État de jeu central (hors rendu). Créé une fois, muté par les systèmes à chaque tick.
import { MASS_START, MASS_CAP, VPW, VPH, ROOMS } from './config.js';
import { buildGraph, buildWalls, buildCandles } from './graph.js';

export function createGame() {
  const { NODES, EDGES, RN, ENTRY } = buildGraph();
  const WALLS = buildWalls();
  const { CANDLES, ROOMCAND } = buildCandles(EDGES);

  const game = {
    ROOMS, NODES, EDGES, RN, ENTRY, WALLS, CANDLES, ROOMCAND,

    // état temps réel
    G: {
      enemies: [], foes: [], beams: [], projectiles: [], mottes: [],
      lit: new Set(), nextId: 10, kills: 0, time: 0,
      mass: MASS_START, massCap: MASS_CAP,
    },
    ai: null,            // commandant adverse (la Veilleuse) — créé au lancement de mission

    HERO: { x: 540, y: 1320, hp: 100, maxHp: 100, inv: 0, dir: 0, trail: [] },
    cam: { fx: 540, fy: 1320 },

    // gisements dans la Bibliothèque (pièce voisine, au-dessus du Hall d'entrée) :
    // il faut s'y déplacer pour récolter (pas de récolte gratuite au spawn).
    CRYSTALS: [
      { x: 480, y: 420, amount: 760, max: 760 },
      { x: 620, y: 410, amount: 760, max: 760 },
      { x: 560, y: 540, amount: 760, max: 760 },
    ],
    STASH: {},
    AIM: {}, CD: {},

    keys: {},
    freeCam: false,

    // état UI
    ui: {
      amb: 'ombrelune', tab: 'turret', sel: null, selId: null,
      heroSelected: true,   // au démarrage : le Commander est sélectionné (clic = déplacement)
      warmth: 0.55, darkMode: false, aimMode: false,
      breached: false, heroDown: false, win: false, report: null,
      owned: {}, enemyOwned: {}, placed: [],
      msg: 'Commander sélectionné — clique un point pour l\'y envoyer. Choisis une tourelle à droite pour en poser une.',
    },

    // flux de jeu (routeur + tuto)
    screen: 'title',   // 'title' | 'mission'
    noSpawn: false,    // suspend l'apparition des flemmes (intro du tuto)
    tutorial: null,

    // éphémères calculés par les systèmes (lecture par le rendu)
    _buildId: null, _buildStall: false, _harvestId: null, _laserTgt: null, _heroCD: 0,
    heroTarget: null,  // ordre de déplacement au clic (RTS) ; annulé par ZQSD
  };

  // vue/camera helpers (bornés aux limites de carte)
  game.clampFx = (v) => Math.max(VPW / 2, Math.min(2900 - VPW / 2, v));
  game.clampFy = (v) => Math.max(VPH / 2, Math.min(1760 - VPH / 2, v));
  return game;
}
