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
      enemies: [], beams: [], projectiles: [], mottes: [],
      lit: new Set(), nextId: 10, kills: 0, time: 0,
      mass: MASS_START, massCap: MASS_CAP,
    },

    HERO: { x: 540, y: 1320, hp: 100, maxHp: 100, inv: 0, dir: 0, trail: [] },
    cam: { fx: 540, fy: 1320 },

    CRYSTALS: [
      { x: 700, y: 1250, amount: 760, max: 760 },
      { x: 430, y: 1235, amount: 760, max: 760 },
      { x: 880, y: 1350, amount: 760, max: 760 },
    ],
    STASH: {},
    AIM: {}, CD: {},

    keys: {},
    freeCam: false,

    // état UI
    ui: {
      amb: 'ombrelune', tab: 'turret', sel: { cat: 'turret', key: 'givre' }, selId: null,
      heroSelected: false,
      warmth: 0.55, darkMode: false, aimMode: false,
      breached: false, heroDown: false, win: false, report: null,
      owned: {}, placed: [],
      msg: "Bienvenue. Allume les bougies du Hall d'entrée pour le conquérir, puis explore. Pose des tourelles dans ta lumière (clic).",
    },

    // éphémères calculés par les systèmes (lecture par le rendu)
    _buildId: null, _buildStall: false, _harvestId: null, _laserTgt: null, _heroCD: 0,
    heroTarget: null,  // ordre de déplacement au clic (RTS) ; annulé par ZQSD
  };

  // vue/camera helpers (bornés aux limites de carte)
  game.clampFx = (v) => Math.max(VPW / 2, Math.min(2900 - VPW / 2, v));
  game.clampFy = (v) => Math.max(VPH / 2, Math.min(1760 - VPH / 2, v));
  return game;
}
