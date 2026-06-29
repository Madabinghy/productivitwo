// Chargement et rendu des sprites PNG designés (assets-png/ → ./sprites/art/).
// Vue de dessus : barillet/tête vers le HAUT (nord = facing 0). Le pivot de rotation
// est la base (≈ centre-bas), pas le centre de l'image.
const SRC = './sprites/art/';
const cache = {};

function img(name) {
  if (cache[name]) return cache[name];
  const i = new Image(); i.src = SRC + name + '.png'; i._ready = false;
  i.onload = () => { i._ready = true; };
  cache[name] = i; return i;
}

export function artReady(name) { const i = cache[name]; return !!(i && i._ready); }

// Dessine un sprite centré sur l'origine du repère courant, pivotant autour de sa base.
// scale : px écran par px natif · rot : degrés (0 = vers le haut) · alpha : opacité.
// opt.pivotY : pivot depuis le HAUT en px natifs (défaut = h - w/2, base au centre-bas).
// Renvoie false si l'image n'est pas encore chargée (→ le fallback canvas prend le relais).
export function drawArt(ctx, name, scale, rot, opt = {}) {
  const i = img(name); if (!i._ready) return false;
  const w = i.width, h = i.height;
  const pivotX = w / 2, pivotY = opt.center ? h / 2 : (opt.pivotY != null ? opt.pivotY : (h - w / 2));
  ctx.save();
  if (opt.alpha != null) ctx.globalAlpha *= opt.alpha;
  if (rot) ctx.rotate(rot * Math.PI / 180);
  ctx.scale(scale, scale);
  ctx.drawImage(i, -pivotX, -pivotY, w, h);
  ctx.restore();
  return true;
}
