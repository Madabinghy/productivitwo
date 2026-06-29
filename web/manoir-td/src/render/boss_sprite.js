// Chargement et rendu de l'araignée-boss (sprites pré-rendus du repo, copiés dans ./sprites/).
// Spritesheets 256 px : idle 6×4 (24 f), walk_XXX 4×4 (16 f), attack 5×4 (20 f).
// Directions : 0=haut, 90=droite, 180=bas, 270=gauche (boussole horaire).
const FRAME = 256, SRC = './sprites/';
function load(name) { const i = new Image(); i.src = SRC + name + '.png'; i._ready = false; i.onload = () => { i._ready = true; }; return i; }

const IMG = {
  idle: load('boss_spider_idle'), shadow: load('boss_spider_idle_shadow'), attack: load('boss_spider_attack'),
  walk: { 0: load('boss_spider_walk_000'), 45: load('boss_spider_walk_045'), 90: load('boss_spider_walk_090'), 135: load('boss_spider_walk_135'), 180: load('boss_spider_walk_180'), 225: load('boss_spider_walk_225'), 270: load('boss_spider_walk_270'), 315: load('boss_spider_walk_315') },
};
const GRID = { idle: { c: 6, r: 4, fps: 10 }, attack: { c: 5, r: 4, fps: 16 }, walk: { c: 4, r: 4, fps: 12 } };
const dirImg = (deg) => IMG.walk[(Math.round((((deg % 360) + 360) % 360) / 45) * 45) % 360] || IMG.walk[180];

export function bossReady() { return IMG.idle._ready; }

// Cache des feuilles teintées (clé = nom+couleur) — teinte une fois, réutilise.
const TINT = {};
function tinted(img, name, color) {
  if (!img || !img._ready) return null;
  const key = name + color;
  if (TINT[key]) return TINT[key];
  const c = document.createElement('canvas'); c.width = img.width; c.height = img.height;
  const x = c.getContext('2d');
  x.drawImage(img, 0, 0);
  x.globalCompositeOperation = 'source-atop'; x.globalAlpha = 0.5; x.fillStyle = color;
  x.fillRect(0, 0, c.width, c.height);
  x.globalAlpha = 1; x.globalCompositeOperation = 'source-over';
  TINT[key] = c; return c;
}

// Sbire « araignée » : réutilise les vrais sprites isométriques du boss, réduits et teintés.
// foe.facing (boussole, deg) choisit la feuille directionnelle ; renvoie false si pas encore prête.
export function drawSbireSpider(ctx, foe, t, size, tint) {
  const deg = (Math.round(((((foe.facing != null ? foe.facing : foe.dir) || 180) % 360) + 360) % 360 / 45) * 45) % 360;
  const im = IMG.walk[deg] || IMG.walk[180];
  if (!im || !im._ready) return false;
  const grid = GRID.walk, frames = grid.c * grid.r;
  const f = Math.floor(t * grid.fps + (foe._ph || 0)) % frames;
  const sx = (f % grid.c) * FRAME, sy = Math.floor(f / grid.c) * FRAME;
  const src = tint ? tinted(im, 'w' + deg, tint) : im;
  if (!src) return false;
  ctx.drawImage(src, sx, sy, FRAME, FRAME, -size / 2, -size / 2, size, size);
  return true;
}

// Dessine le boss centré sur (0,0) (repère déjà translaté). size = taille à l'écran.
export function drawBossSpider(ctx, foe, t, size = 96) {
  const anim = foe.anim || 'idle';
  let im, grid;
  if (anim === 'attack') { im = IMG.attack; grid = GRID.attack; }
  else if (anim === 'walk') { im = dirImg(foe.dir || 180); grid = GRID.walk; }
  else { im = IMG.idle; grid = GRID.idle; }
  if (!im || !im._ready) return false;

  const frames = grid.c * grid.r;
  let f;
  if (anim === 'attack' && foe.animT != null) { const prog = 1 - Math.max(0, foe.animT) / (foe.animDur || 0.6); f = Math.min(frames - 1, Math.floor(prog * frames)); }
  else f = Math.floor(t * grid.fps) % frames;
  const sx = (f % grid.c) * FRAME, sy = Math.floor(f / grid.c) * FRAME;

  if (IMG.shadow._ready) {
    const g2 = GRID.idle, sf = Math.floor(t * g2.fps) % (g2.c * g2.r);
    ctx.globalAlpha = 0.5; ctx.drawImage(IMG.shadow, (sf % g2.c) * FRAME, Math.floor(sf / g2.c) * FRAME, FRAME, FRAME, -size / 2, -size / 2 + 8, size, size); ctx.globalAlpha = 1;
  }
  ctx.drawImage(im, sx, sy, FRAME, FRAME, -size / 2, -size / 2, size, size);
  return true;
}
