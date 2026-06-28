// Point d'entrée : boucle de jeu (requestAnimationFrame), assemblage des systèmes.
import { VPW, VPH } from './config.js';
import { createGame } from './state.js';
import { spawnEnemies, updateEnemies } from './systems/enemies.js';
import { updateHeroMove, heroLaser, orientHero } from './systems/hero.js';
import { updateEffects } from './systems/effects.js';
import { attachInput } from './input.js';
import { draw } from './render/index.js';

const game = createGame();
spawnEnemies(game);
attachInput(game);
window.__game = game; // utile pour le débogage / tests

const canvas = document.getElementById('view');
canvas.width = VPW; canvas.height = VPH;
const ctx = canvas.getContext('2d');

function tick(dt) {
  const { G } = game;
  if (G.lit.size < game.CANDLES.length) G.time = (G.time || 0) + dt;
  if (game.HERO.inv > 0) game.HERO.inv -= dt;

  updateHeroMove(game, dt);
  updateEnemies(game, dt);
  heroLaser(game, dt);
  orientHero(game, dt);
  updateEffects(game, dt);

  if (!game.freeCam) { game.cam.fx = game.clampFx(game.HERO.x); game.cam.fy = game.clampFy(game.HERO.y); }
}

// HUD minimal (étoffé aux étapes suivantes)
const hud = {
  alive: document.getElementById('hud-alive'),
  chrono: document.getElementById('hud-chrono'),
  msg: document.getElementById('hud-msg'),
};
function paintHud() {
  if (hud.alive) hud.alive.textContent = game.G.enemies.length;
  if (hud.chrono) { const s = Math.floor(game.G.time || 0); hud.chrono.textContent = Math.floor(s / 60) + ':' + ('0' + (s % 60)).slice(-2); }
  if (hud.msg) hud.msg.textContent = game.ui.msg;
}

let last = performance.now();
function frame(now) {
  let dt = (now - last) / 1000; last = now;
  if (dt > 0.05) dt = 0.05; if (dt <= 0) dt = 0.016;
  tick(dt);
  draw(game, ctx, game.G.time || 0);
  paintHud();
  requestAnimationFrame(frame);
}
requestAnimationFrame(frame);
