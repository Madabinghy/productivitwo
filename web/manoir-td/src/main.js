// Point d'entrée : boucle de jeu (requestAnimationFrame), assemblage des systèmes.
import { VPW, VPH } from './config.js';
import { createGame } from './state.js';
import { spawnEnemies, updateEnemies } from './systems/enemies.js';
import { updateHeroMove, heroLaser, orientHero } from './systems/hero.js';
import { updateEconomy } from './systems/economy.js';
import { updateTurrets } from './systems/turrets.js';
import { updateConstruction } from './systems/construction.js';
import { updateEffects } from './systems/effects.js';
import { updateObjectives, resume } from './systems/objectives.js';
import { attachInput } from './input.js';
import { draw } from './render/index.js';
import { createPanel } from './render/panel.js';
import { loadSave, writeSave, defaultSave, hasSave } from './save.js';
import { startTutorial, updateTutorial } from './tutorial.js';

const game = createGame();
window.__game = game; // utile pour le débogage / tests

let save = loadSave() || defaultSave();
game.save = save;

const canvas = document.getElementById('view');
canvas.width = VPW; canvas.height = VPH;
const ctx = canvas.getContext('2d');
attachInput(game, canvas);
const panel = createPanel(game);

// ---- routeur d'écrans : titre → mission ----
const titleOv = document.getElementById('ov-title');
const tutbar = document.getElementById('tutbar');
const btnContinue = document.getElementById('btn-continue');
btnContinue.hidden = !(hasSave() && save.seenTutorial);

function startMission({ tutorial }) {
  game.screen = 'mission';
  titleOv.hidden = true;
  game.G.kills = 0; game._spawnT = 0;
  if (tutorial) { startTutorial(game); }
  else { game.noSpawn = false; spawnEnemies(game); }
}

document.getElementById('btn-new').onclick = () => {
  save = defaultSave(); game.save = save; writeSave(save);
  startMission({ tutorial: true });
};
btnContinue.onclick = () => startMission({ tutorial: false });

function tick(dt) {
  const { G } = game;
  if (G.lit.size < game.CANDLES.length) G.time = (G.time || 0) + dt;
  if (game.HERO.inv > 0) game.HERO.inv -= dt;

  updateTutorial(game, dt, () => { save.seenTutorial = true; writeSave(save); });

  updateHeroMove(game, dt);
  updateEnemies(game, dt);
  updateTurrets(game, dt);
  updateConstruction(game, dt);
  updateEconomy(game, dt);
  heroLaser(game, dt);
  orientHero(game, dt);
  updateEffects(game, dt);
  updateObjectives(game);

  if (!game.freeCam) { game.cam.fx = game.clampFx(game.HERO.x); game.cam.fy = game.clampFy(game.HERO.y); }
}

// HUD minimal (étoffé aux étapes suivantes)
// overlays de fin
const ov = { win: document.getElementById('ov-win'), down: document.getElementById('ov-down'), breach: document.getElementById('ov-breach'), report: document.getElementById('report') };
document.getElementById('btn-down').onclick = () => resume(game);
document.getElementById('btn-breach').onclick = () => resume(game);

const darkBtn = document.getElementById('hud-dark');
darkBtn.onclick = () => {
  game.ui.darkMode = !game.ui.darkMode;
  game.ui.msg = game.ui.darkMode ? 'Nuit noire — le plan ne révèle que les flemmes éclairées (héros, bougies, radar, satellite).' : 'Mode exploration rétabli (jour).';
};

const hud = {
  alive: document.getElementById('hud-alive'),
  lit: document.getElementById('hud-lit'),
  owned: document.getElementById('hud-owned'),
  chrono: document.getElementById('hud-chrono'),
  dark: darkBtn,
  msg: document.getElementById('hud-msg'),
  massWrap: document.querySelector('.mass'),
  massFill: document.getElementById('hud-massfill'),
  massVal: document.getElementById('hud-massval'),
  massFull: document.getElementById('hud-massfull'),
};
function paintHud() {
  if (hud.alive) hud.alive.textContent = game.G.enemies.length;
  if (hud.lit) hud.lit.textContent = game.G.lit.size + '/' + game.CANDLES.length;
  if (hud.owned) hud.owned.textContent = Object.keys(game.ui.owned).length + '/' + game.ROOMS.length;
  if (hud.dark) { hud.dark.textContent = game.ui.darkMode ? '☾ Nuit noire' : '☀ Exploration'; hud.dark.classList.toggle('on', game.ui.darkMode); }
  if (hud.chrono) { const s = Math.floor(game.G.time || 0); hud.chrono.textContent = Math.floor(s / 60) + ':' + ('0' + (s % 60)).slice(-2); }
  if (hud.msg) hud.msg.textContent = game.ui.msg;
  const G = game.G; const full = G.mass >= G.massCap;
  if (hud.massFill) hud.massFill.style.width = (Math.max(0, Math.min(1, G.mass / G.massCap)) * 100).toFixed(0) + '%';
  if (hud.massVal) hud.massVal.textContent = Math.round(G.mass) + ' / ' + G.massCap;
  if (hud.massFull) hud.massFull.textContent = full ? '⚠ plein' : '';
  if (hud.massWrap) hud.massWrap.classList.toggle('full', full);
  panel.refresh();

  // bandeau de tuto (Veilleuse)
  const tut = game.tutorial;
  if (tut && tut.active && tut.text) { tutbar.hidden = false; tutbar.textContent = tut.text; } else { tutbar.hidden = true; }

  // persistance des stats à la victoire
  if (game.ui.win && !game._winSaved) { game._winSaved = true; save.stats.missionsWon = (save.stats.missionsWon || 0) + 1; save.stats.kills = (save.stats.kills || 0) + (game.G.kills || 0); writeSave(save); }

  // overlays de fin de partie
  ov.win.hidden = !game.ui.win;
  ov.down.hidden = !(game.ui.heroDown && !game.ui.breached);
  ov.breach.hidden = !game.ui.breached;
  if (game.ui.breached && game.ui.report && ov.report.dataset.id !== game.ui.report.id) {
    const r = game.ui.report; ov.report.dataset.id = r.id;
    ov.report.innerHTML =
      '<div class="tag">◆ Données interceptées — ' + r.id + '</div>' +
      '<div class="l1">Utilisateur anonyme ' + r.id + '</div>' +
      '<div class="l2">a atteint le niveau ' + r.level + ' en « ' + r.domain + ' » grâce à l\'appli.</div>' +
      '<div class="bar"><i style="width:' + r.pct + '%"></i></div>' +
      '<div class="foot">Progression du parcours : ' + r.pct + '%   ·   réf. dossier ' + r.id + '</div>';
  }
}

let last = performance.now();
function frame(now) {
  let dt = (now - last) / 1000; last = now;
  if (dt > 0.05) dt = 0.05; if (dt <= 0) dt = 0.016;
  if (game.screen === 'mission') tick(dt);
  draw(game, ctx, game.G.time || 0);
  paintHud();
  requestAnimationFrame(frame);
}
requestAnimationFrame(frame);
