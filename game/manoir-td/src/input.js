// Saisie clavier : déplacement du héros + raccourcis (G = déposer un gisement, outil de test).
const MOVE = ['arrowup', 'arrowdown', 'arrowleft', 'arrowright', ' '];

export function attachInput(game) {
  const onDown = (e) => {
    const k = (e.key || '').toLowerCase();
    game.keys[k] = true;
    if (MOVE.includes(k) && e.preventDefault) e.preventDefault();
    if (k === 'g') dropCrystal(game);
  };
  const onUp = (e) => { game.keys[(e.key || '').toLowerCase()] = false; };
  window.addEventListener('keydown', onDown, { passive: false });
  window.addEventListener('keyup', onUp);
}

function dropCrystal(game) {
  const H = game.HERO; if (!H) return;
  game.CRYSTALS.push({ x: H.x, y: H.y, amount: 760, max: 760 });
  game.ui.msg = '✦ Gisement de cristaux déposé ici.';
}
