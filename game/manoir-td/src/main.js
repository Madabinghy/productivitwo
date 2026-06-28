// Point d'entrée : boucle de jeu (requestAnimationFrame), assemblage des systèmes.
import { VPW, VPH } from './config.js';
import { createGame } from './state.js';
import { spawnEnemies, updateEnemies } from './systems/enemies.js';
import { updateHeroMove, heroLaser, orientHero } from './systems/hero.js';
import { updateEconomy } from './systems/economy.js';
import { updateTurrets } from './systems/turrets.js';
import { updateConstruction } from './systems/construction.js';
import { updateEffects } from './systems/effects.js';
import { attachInput } from './input.js';
import { draw } from './render/index.js';
import { createPanel } from './render/panel.js';

const game = createGame();
spawnEnemies(game);
window.__game = game; // utile pour le débogage / tests

const canvas = document.getElementById('view');
canvas.width = VPW; canvas.height = VPH;
const ctx = canvas.getContext('2d');
attachInput(game, canvas);
const panel = createPanel(game);

function tick(dt) {
  const { G } = game;
  if (G.lit.size < game.CANDLES.length) G.time = (G.time || 0) + dt;
  if (game.HERO.inv > 0) game.HERO.inv -= dt;

  updateHeroMove(game, dt);
  updateEnemies(game, dt);
  updateTurrets(game, dt);
  updateConstruction(game, dt);
  updateEconomy(game, dt);
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
  massWrap: document.querySelector('.mass'),
  massFill: document.getElementById('hud-massfill'),
  massVal: document.getElementById('hud-massval'),
  massFull: document.getElementById('hud-massfull'),
};
function paintHud() {
  if (hud.alive) hud.alive.textContent = game.G.enemies.length;
  if (hud.chrono) { const s = Math.floor(game.G.time || 0); hud.chrono.textContent = Math.floor(s / 60) + ':' + ('0' + (s % 60)).slice(-2); }
  if (hud.msg) hud.msg.textContent = game.ui.msg;
  const G = game.G; const full = G.mass >= G.massCap;
  if (hud.massFill) hud.massFill.style.width = (Math.max(0, Math.min(1, G.mass / G.massCap)) * 100).toFixed(0) + '%';
  if (hud.massVal) hud.massVal.textContent = Math.round(G.mass) + ' / ' + G.massCap;
  if (hud.massFull) hud.massFull.textContent = full ? '⚠ plein' : '';
  if (hud.massWrap) hud.massWrap.classList.toggle('full', full);
  panel.refresh();
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
