// Graphe de navigation (pathfinding ennemi BFS), murs bloquants, bougies.
// Porté fidèlement du prototype.
import { ROOMS, DOORSIDE, MAP } from './config.js';

export function door(r) {
  const cx = r.x + r.w / 2, cy = r.y + r.h / 2, side = DOORSIDE[r.id] || 'left';
  if (side === 'top') return { x: cx, y: r.y };
  if (side === 'bottom') return { x: cx, y: r.y + r.h };
  if (side === 'right') return { x: r.x + r.w, y: cy };
  return { x: r.x, y: cy };
}

// Construit le graphe : 4 nœuds de bord + 4 coins par salle, anneau de couloir,
// liaisons inter-salles, et 2 portails d'entrée à droite de la carte.
export function buildGraph() {
  const d = 70; const NODES = [], EDGES = [], RN = {};
  const add = (x, y, kind, room) => { NODES.push({ x, y, kind, room, nbr: [] }); return NODES.length - 1; };
  const link = (i, j) => {
    if (i === j) return;
    if (!NODES[i].nbr.includes(j)) NODES[i].nbr.push(j);
    if (!NODES[j].nbr.includes(i)) NODES[j].nbr.push(i);
    EDGES.push({ x1: NODES[i].x, y1: NODES[i].y, x2: NODES[j].x, y2: NODES[j].y });
  };
  const linkND = (i, j) => {
    if (!NODES[i].nbr.includes(j)) NODES[i].nbr.push(j);
    if (!NODES[j].nbr.includes(i)) NODES[j].nbr.push(i);
  };
  for (const r of ROOMS) {
    const t = add(r.x + r.w / 2, r.y - d, 'e'), b = add(r.x + r.w / 2, r.y + r.h + d, 'e'),
          l = add(r.x - d, r.y + r.h / 2, 'e'), ri = add(r.x + r.w + d, r.y + r.h / 2, 'e');
    const tl = add(r.x - d, r.y - d, 'c'), tr = add(r.x + r.w + d, r.y - d, 'c'),
          bl = add(r.x - d, r.y + r.h + d, 'c'), br = add(r.x + r.w + d, r.y + r.h + d, 'c');
    link(t, tr); link(tr, ri); link(ri, br); link(br, b); link(b, bl); link(bl, l); link(l, tl); link(tl, t);
    const cc = add(r.x + r.w / 2, r.y + r.h / 2, 'center', r.id);
    const ds = DOORSIDE[r.id]; const dn = { top: t, bottom: b, left: l, right: ri }[ds] || l;
    linkND(dn, cc);
    RN[r.id] = { t, b, l, ri, tl, tr, bl, br, c: cc };
  }
  const adj = [
    ['biblio', 'observ', 'ri', 'l'], ['observ', 'galerie', 'ri', 'l'], ['biblio', 'entree', 'b', 't'],
    ['observ', 'hall', 'b', 't'], ['hall', 'bal', 'ri', 'l'], ['galerie', 'bal', 'b', 't'],
    ['entree', 'hall', 'ri', 'l'],
  ];
  for (const [a, b2, na, nb] of adj) link(RN[a][na], RN[b2][nb]);
  const e1 = add(MAP.R, 200, 'entry'), e2 = add(MAP.R, 1400, 'entry');
  link(e1, RN['galerie'].tr); link(e2, RN['bal'].br);
  return { NODES, EDGES, RN, ENTRY: [e1, e2] };
}

// Murs : périmètre de chaque salle, troué d'un gap de 150px au droit de la porte.
export function buildWalls() {
  const WALLS = []; const gap = 150;
  const seg = (x1, y1, x2, y2) => WALLS.push({ x1, y1, x2, y2 });
  for (const r of ROOMS) {
    const dr = door(r); const x2 = r.x + r.w, y2 = r.y + r.h; const side = DOORSIDE[r.id];
    if (side === 'top') { seg(r.x, r.y, dr.x - gap, r.y); seg(dr.x + gap, r.y, x2, r.y); } else seg(r.x, r.y, x2, r.y);
    if (side === 'bottom') { seg(r.x, y2, dr.x - gap, y2); seg(dr.x + gap, y2, x2, y2); } else seg(r.x, y2, x2, y2);
    if (side === 'left') { seg(r.x, r.y, r.x, dr.y - gap); seg(r.x, dr.y + gap, r.x, y2); } else seg(r.x, r.y, r.x, y2);
    if (side === 'right') { seg(x2, r.y, x2, dr.y - gap); seg(x2, dr.y + gap, x2, y2); } else seg(x2, r.y, x2, y2);
  }
  return WALLS;
}

// Bougies : une par arête de couloir (milieu) + 5 par salle. ROOMCAND mappe salle → indices.
export function buildCandles(EDGES) {
  const CANDLES = []; const ROOMCAND = {};
  for (const e of EDGES) CANDLES.push({ x: (e.x1 + e.x2) / 2, y: (e.y1 + e.y2) / 2, room: null });
  const pts = [[0.3, 0.3], [0.7, 0.3], [0.5, 0.5], [0.3, 0.7], [0.7, 0.7]];
  for (const r of ROOMS) {
    ROOMCAND[r.id] = [];
    for (const p of pts) { ROOMCAND[r.id].push(CANDLES.length); CANDLES.push({ x: r.x + r.w * p[0], y: r.y + r.h * p[1], room: r.id }); }
  }
  return { CANDLES, ROOMCAND };
}

export function nearestNode(NODES, x, y) {
  let bi = 0, bd = 1e9;
  for (let i = 0; i < NODES.length; i++) { const n = NODES[i]; const d = Math.hypot(n.x - x, n.y - y); if (d < bd) { bd = d; bi = i; } }
  return bi;
}

// BFS : chemin de nœuds du départ au but (exclut le départ).
export function bfsPath(NODES, start, goal) {
  if (start === goal) return [goal];
  const prev = {}; const q = [start]; prev[start] = -1;
  while (q.length) {
    const c = q.shift();
    for (const n of NODES[c].nbr) {
      if (prev[n] === undefined) {
        prev[n] = c;
        if (n === goal) { const path = []; let k = goal; while (k !== -1) { path.unshift(k); k = prev[k]; } path.shift(); return path; }
        q.push(n);
      }
    }
  }
  return null;
}
