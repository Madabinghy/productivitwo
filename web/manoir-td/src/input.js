// Saisie : clavier (déplacement + raccourcis) et pointeur (pose souris/tactile, pan).
import { VPW, VPH } from './config.js';
import { actAt, setGhost, clearGhost, pickupUnderHero } from './systems/placement.js';

const MOVE = ['arrowup', 'arrowdown', 'arrowleft', 'arrowright', ' '];

export function attachInput(game, canvas) {
  // ---- clavier ----
  const onDown = (e) => {
    const k = (e.key || '').toLowerCase();
    game.keys[k] = true;
    if (MOVE.includes(k) && e.preventDefault) e.preventDefault();
    if (k === 'g') dropCrystal(game);
    if (k === ' ') pickupUnderHero(game);
  };
  const onUp = (e) => { game.keys[(e.key || '').toLowerCase()] = false; };
  window.addEventListener('keydown', onDown, { passive: false });
  window.addEventListener('keyup', onUp);

  if (!canvas) return;

  // écran → monde (gère la mise à l'échelle CSS du canvas)
  const toWorld = (clientX, clientY) => {
    const r = canvas.getBoundingClientRect();
    const sx = (clientX - r.left) * (VPW / r.width), sy = (clientY - r.top) * (VPH / r.height);
    return { wx: sx + (game.cam.fx - VPW / 2), wy: sy + (game.cam.fy - VPH / 2) };
  };

  // ---- souris ----
  canvas.addEventListener('mousemove', (e) => { const { wx, wy } = toWorld(e.clientX, e.clientY); if (game.ui.sel) setGhost(game, wx, wy); });
  canvas.addEventListener('mouseleave', () => clearGhost(game));
  canvas.addEventListener('click', (e) => {
    if (game._suppressClick) return;
    if (game._didPan) { game._didPan = false; return; }
    const { wx, wy } = toWorld(e.clientX, e.clientY); actAt(game, wx, wy, false);
  });
  canvas.addEventListener('wheel', (e) => {
    game.freeCam = true;
    game.cam.fx = game.clampFx(game.cam.fx + e.deltaX);
    game.cam.fy = game.clampFy(game.cam.fy + e.deltaY);
    if (e.preventDefault) e.preventDefault();
  }, { passive: false });

  // ---- tactile : tap = pose en 2 temps ; 2 doigts = pan ----
  canvas.addEventListener('touchstart', (e) => {
    if (e.touches.length === 2) { game._panT = midpoint(e); game._didPan = false; game._tap = null; game.freeCam = true; e.preventDefault(); }
    else if (e.touches.length === 1) { game._panT = null; game._tap = { x: e.touches[0].clientX, y: e.touches[0].clientY }; game._tapMoved = false; }
  }, { passive: false });
  canvas.addEventListener('touchmove', (e) => {
    if (e.touches.length === 1 && game._tap) { const t = e.touches[0]; if (Math.hypot(t.clientX - game._tap.x, t.clientY - game._tap.y) > 12) game._tapMoved = true; return; }
    if (e.touches.length === 2 && game._panT) {
      const m = midpoint(e); const dx = m.x - game._panT.x, dy = m.y - game._panT.y; game._panT = m;
      game.cam.fx = game.clampFx(game.cam.fx - dx); game.cam.fy = game.clampFy(game.cam.fy - dy);
      game._didPan = true; game.freeCam = true; e.preventDefault();
    }
  }, { passive: false });
  const endTouch = (e) => {
    if (game._tap && !game._tapMoved && !game._didPan && e.changedTouches.length) {
      const t = e.changedTouches[0]; const { wx, wy } = toWorld(t.clientX, t.clientY);
      game._suppressClick = true; setTimeout(() => { game._suppressClick = false; }, 500);
      actAt(game, wx, wy, true);
    }
    game._tap = null; if (e.touches.length < 2) game._panT = null;
  };
  canvas.addEventListener('touchend', endTouch, { passive: false });
  canvas.addEventListener('touchcancel', endTouch, { passive: false });
}

function midpoint(e) { return { x: (e.touches[0].clientX + e.touches[1].clientX) / 2, y: (e.touches[0].clientY + e.touches[1].clientY) / 2 }; }

function dropCrystal(game) {
  const H = game.HERO; if (!H) return;
  game.CRYSTALS.push({ x: H.x, y: H.y, amount: 760, max: 760 });
  game.ui.msg = '✦ Gisement de cristaux déposé ici.';
}
