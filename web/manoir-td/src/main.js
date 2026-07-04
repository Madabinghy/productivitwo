// Point d'entrée : boucle de jeu (requestAnimationFrame), assemblage des systèmes.
import { VPW, VPH, MASS_START, MASS_CAP } from './config.js';
import { createGame } from './state.js';
import { spawnEnemies, updateEnemies } from './systems/enemies.js';
import { nodeById, completeNode, NODES, applyReward } from './campaign.js';
import { createCampaign } from './render/map.js';
import { initEnemyAI, updateEnemyAI } from './systems/enemy_ai.js';
import { updateUnits } from './systems/units.js';
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

// —— Mode RAID DE JALON (?raid=1&reward=action&seed=N&difficulty=D) ——
// Lancé depuis le portail du manoir quand la prochaine étape est un JALON
// (une tâche entière). Partie directe sur un nœud choisi par la graine,
// roster « comme si » la campagne y était rendue — la SAUVEGARDE de campagne
// n'est jamais touchée (partie transitoire). Victoire → révélation (pont).
const RAID = /(^|[?&])raid=1/.test(window.location.search);
const RAID_SEED = (parseInt((window.location.search.match(/seed=(\d+)/) || [])[1] || '0', 10)) >>> 0;
const RAID_DIFF = Math.max(1, Math.min(3, parseInt((window.location.search.match(/difficulty=(\d)/) || [])[1] || '1', 10)));
const RAID_REWARD = /(^|[?&])reward=action/.test(window.location.search);
function goManoir() { try { window.location.href = './' + encodeURIComponent('Manoir - Exploration.html'); } catch (e) {} }
function raidReveal() {
  try { const na = JSON.parse(localStorage.getItem('ombrelune_next_action') || 'null');
    if (na && na.actionId) { const rev = JSON.parse(localStorage.getItem('ombrelune_revealed') || '[]');
      if (!rev.includes(na.actionId)) { rev.push(na.actionId); localStorage.setItem('ombrelune_revealed', JSON.stringify(rev)); } } } catch (e) {}
  try { if (window.ManoirBridge) window.ManoirBridge.postMessage(JSON.stringify({ type: 'reveal_action' })); } catch (e) {}
}

let save = RAID ? defaultSave() : (loadSave() || defaultSave());
game.save = save;

const canvas = document.getElementById('view');
canvas.width = VPW; canvas.height = VPH;
const ctx = canvas.getContext('2d');
attachInput(game, canvas);
const panel = createPanel(game);

// ---- routeur d'écrans : titre ⇄ carte ⇄ mission ----
const titleOv = document.getElementById('ov-title');
const campaignOv = document.getElementById('ov-campaign');
const tutbar = document.getElementById('tutbar');
const btnContinue = document.getElementById('btn-continue');
btnContinue.hidden = !(hasSave() && save.seenTutorial);

const campaign = createCampaign(game, (node) => startMissionNode(node, { tutorial: false }));

// remet la mission à neuf pour un nœud donné
function resetMission(game, node) {
  const G = game.G;
  G.enemies = []; G.beams = []; G.projectiles = []; G.mottes = [];
  G.lit = new Set(); G.kills = 0; G.time = 0; G.wave = 0;
  G.mass = MASS_START; G.massCap = MASS_CAP; G.nextId = 10;
  for (const cr of game.CRYSTALS) cr.amount = cr.max;
  game.HERO = { x: 540, y: 1320, hp: 100, maxHp: 100, inv: 0, dir: 0, trail: [] };
  game.cam = { fx: 540, fy: 1320 }; game.freeCam = false;
  game.AIM = {}; game.CD = {}; game.STASH = {}; game.heroTarget = null;
  game._spawnT = 0; game._winSaved = false; game.noSpawn = false; game.tutorial = null;
  Object.assign(game.ui, { sel: null, selId: null, heroSelected: true, aimMode: false, breached: false, heroDown: false, win: false, report: null, owned: {}, enemyOwned: {}, placed: [] });
  game.ui.darkMode = !!(node && node.mission.night);
  game.mission = node ? { nodeId: node.id, waves: node.mission.waves, night: node.mission.night } : null;
  initEnemyAI(game);          // commandant adverse (la Veilleuse)
}

function startMissionNode(node, { tutorial }) {
  resetMission(game, node);
  game.screen = 'mission';
  if (tutorial) startTutorial(game);          // tuto : noSpawn jusqu'à l'étape combat
  else game.noSpawn = false;                    // l'IA adverse (Veilleuse) prend le relais
  game.ui.msg = tutorial ? '' : ('Mission : ' + node.name + ' — anéantis la Veilleuse et ses sanctuaires.');
}

document.getElementById('btn-new').onclick = () => {
  save = defaultSave(); game.save = save; writeSave(save);
  startMissionNode(nodeById('m1'), { tutorial: true });
};
btnContinue.onclick = () => { campaign.refresh(); game.screen = 'campaign'; };

// —— démarrage direct du raid : nœud par difficulté (varié par la graine),
// roster = récompenses de tous les nœuds précédents (campagne « rendue là »).
if (RAID) {
  const cands = [['m3', 'm4'], ['m5', 'm6'], ['m7', 'm8']][RAID_DIFF - 1];
  const node = nodeById(cands[RAID_SEED % cands.length]);
  const idx = NODES.indexOf(node);
  for (let i = 0; i < idx; i++) applyReward(save, NODES[i]);
  startMissionNode(node, { tutorial: false });
  game.ui.msg = 'RAID DE JALON — ' + node.name + ' : anéantis la Veilleuse et ses sanctuaires. Le jalon entier est le butin.';
  document.getElementById('btn-win-map').textContent = 'Retour au manoir ✦';
  document.getElementById('btn-down-map').textContent = 'Replier (manoir)';
  document.getElementById('btn-breach-map').textContent = 'Replier (manoir)';
  const wt = document.querySelector('#ov-win .ov-title'); if (wt) wt.textContent = 'JALON CONQUIS';
}

// retour à la carte (depuis résultats) — applique la récompense si victoire
function backToMap({ won }) {
  if (RAID) { goManoir(); return; } // raid : on rentre au manoir, la campagne n'est pas touchée
  if (won && game.mission) {
    const node = nodeById(game.mission.nodeId);
    completeNode(save, node); save.currentNode = node.id;
    save.stats.missionsWon = (save.stats.missionsWon || 0) + 1; save.stats.kills = (save.stats.kills || 0) + (game.G.kills || 0);
    writeSave(save);
  }
  game.mission = null; game.screen = 'campaign'; campaign.refresh();
}
document.getElementById('btn-win-map').onclick = () => backToMap({ won: true });
document.getElementById('btn-down-map').onclick = () => backToMap({ won: false });
document.getElementById('btn-breach-map').onclick = () => backToMap({ won: false });

function tick(dt) {
  const { G } = game;
  if (G.lit.size < game.CANDLES.length) G.time = (G.time || 0) + dt;
  if (game.HERO.inv > 0) game.HERO.inv -= dt;

  updateTutorial(game, dt, () => { save.seenTutorial = true; writeSave(save); });

  updateHeroMove(game, dt);
  updateEnemies(game, dt);
  updateEnemyAI(game, dt);
  updateTurrets(game, dt);
  updateUnits(game, dt);
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
const ov = { win: document.getElementById('ov-win'), down: document.getElementById('ov-down'), breach: document.getElementById('ov-breach'), report: document.getElementById('report'), winRecap: document.getElementById('win-recap'), winReward: document.getElementById('win-reward') };
function retry() {
  if (game.mission) startMissionNode(nodeById(game.mission.nodeId), { tutorial: false });
  else resume(game);
}
document.getElementById('btn-down').onclick = retry;
document.getElementById('btn-breach').onclick = retry;

const darkBtn = document.getElementById('hud-dark');
darkBtn.onclick = () => {
  game.ui.darkMode = !game.ui.darkMode;
  game.ui.msg = game.ui.darkMode ? 'Nuit noire — le plan ne révèle que les flemmes éclairées (héros, bougies, radar, satellite).' : 'Mode exploration rétabli (jour).';
};

// Quitter la mission en cours → retour à la carte (double-clic de confirmation)
const quitBtn = document.getElementById('hud-quit');
let quitArm = 0;
quitBtn.onclick = () => {
  if (game.screen !== 'mission') return;
  if (quitArm) { quitArm = 0; quitBtn.textContent = '✕ Quitter'; backToMap({ won: false }); }
  else { quitArm = 1; quitBtn.textContent = '✕ Confirmer ?'; setTimeout(() => { quitArm = 0; quitBtn.textContent = '✕ Quitter'; }, 2000); }
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
const hudWrap = document.querySelector('.hud');
const panelEl = document.getElementById('panel');
const msgbarEl = document.querySelector('.msgbar');
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

  // visibilité des écrans (titre / carte cachent l'UI de mission)
  const inMission = game.screen === 'mission';
  titleOv.hidden = game.screen !== 'title';
  campaignOv.hidden = game.screen !== 'campaign';
  hudWrap.style.visibility = inMission ? 'visible' : 'hidden';
  panelEl.style.visibility = inMission ? 'visible' : 'hidden';
  msgbarEl.style.visibility = inMission ? 'visible' : 'hidden';

  // bandeau de tuto (Veilleuse)
  const tut = game.tutorial;
  if (inMission && tut && tut.active && tut.text) { tutbar.hidden = false; tutbar.textContent = tut.text; } else { tutbar.hidden = true; }

  // résultats de victoire : récap + récompense débloquée
  if (game.ui.win && ov.win.dataset.shown !== '1') {
    ov.win.dataset.shown = '1';
    const w = Math.max(0, game.mission ? game.mission.waves : 0);
    ov.winRecap.textContent = (game.mission ? game.mission.waves + ' vagues repoussées · ' : '') + (game.G.kills || 0) + ' flemmes vaincues · masse ' + Math.round(game.G.mass);
    if (RAID) {
      // le butin du raid = le JALON : révélation immédiate (comme les autres gardiens)
      if (RAID_REWARD && !game._raidRevealed) { game._raidRevealed = true; raidReveal(); }
      let pn = ''; try { const na = JSON.parse(localStorage.getItem('ombrelune_next_action') || 'null'); if (na && na.projectName) pn = ' · ' + na.projectName; } catch (e) {}
      ov.winReward.hidden = false;
      ov.winReward.textContent = '✦ Le jalon se descelle' + pn + ' — ta Console te lira la prochaine étape.';
    } else {
      const node = game.mission ? nodeById(game.mission.nodeId) : null;
      const rewKey = node && node.reward && (node.reward.turret || node.reward.support);
      if (rewKey) { ov.winReward.hidden = false; ov.winReward.textContent = '✦ Débloqué : ' + rewKey.charAt(0).toUpperCase() + rewKey.slice(1); }
      else ov.winReward.hidden = true;
    }
  }
  if (!game.ui.win) ov.win.dataset.shown = '';

  // overlays de fin de partie (seulement en mission)
  ov.win.hidden = !(inMission && game.ui.win);
  ov.down.hidden = !(inMission && game.ui.heroDown && !game.ui.breached);
  ov.breach.hidden = !(inMission && game.ui.breached);
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
