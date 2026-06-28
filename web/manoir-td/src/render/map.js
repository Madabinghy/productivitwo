// Écran « Carte de campagne » (DOM) : nœuds positionnés, arêtes de pré-requis, états
// done/current/locked, clic → lance la mission. Inspiré de la roadmap des protos.
import { NODES, PHASES, nodeById, isDone, isUnlocked } from '../campaign.js';
import { TCOL } from '../config.js';

const SVGNS = 'http://www.w3.org/2000/svg';

export function createCampaign(game, onPlay) {
  const root = document.getElementById('cmap');
  const hint = document.getElementById('cmap-hint');
  root.innerHTML = '';

  // arêtes (SVG) sous les nœuds
  const svg = document.createElementNS(SVGNS, 'svg');
  svg.setAttribute('viewBox', '0 0 1080 470');
  root.appendChild(svg);
  const edges = [];
  for (const n of NODES) for (const r of n.requires) {
    const a = nodeById(r); const line = document.createElementNS(SVGNS, 'line');
    line.setAttribute('x1', a.x); line.setAttribute('y1', a.y); line.setAttribute('x2', n.x); line.setAttribute('y2', n.y);
    line.setAttribute('stroke-width', '3'); line.setAttribute('stroke-linecap', 'round');
    svg.appendChild(line); edges.push({ to: n.id, el: line });
  }

  // libellés de phase
  for (let i = 0; i < PHASES.length; i++) {
    const ns = NODES.filter(n => n.p === i); const cx = ns.reduce((s, n) => s + n.x, 0) / ns.length;
    const lab = document.createElement('div'); lab.className = 'cphase'; lab.textContent = PHASES[i].name;
    lab.style.left = cx + 'px'; lab.style.transform = 'translateX(-50%)'; lab.style.color = PHASES[i].col;
    root.appendChild(lab);
  }

  // nœuds
  const nodeEls = NODES.map(n => {
    const btn = document.createElement('button'); btn.className = 'cnode' + (n.boss ? ' boss' : '');
    btn.style.left = n.x + 'px'; btn.style.top = n.y + 'px';
    const disc = document.createElement('div'); disc.className = 'disc';
    const glyph = document.createElement('span'); disc.appendChild(glyph);
    const rew = document.createElement('div'); rew.className = 'rew-dot';
    const rewKey = n.reward && (n.reward.turret || n.reward.support);
    rew.style.background = TCOL[rewKey] || '#8a6cff'; disc.appendChild(rew);
    const nm = document.createElement('div'); nm.className = 'nm'; nm.textContent = n.name;
    btn.appendChild(disc); btn.appendChild(nm);
    btn.onclick = () => {
      if (!isUnlocked(game.save, n)) { hint.textContent = '🔒 ' + n.name + ' — termine d\'abord la mission précédente.'; return; }
      onPlay(n);
    };
    root.appendChild(btn);
    return { node: n, btn, disc, glyph };
  });

  function refresh() {
    for (const { node, btn, disc, glyph } of nodeEls) {
      const done = isDone(game.save, node.id);
      const open = isUnlocked(game.save, node);
      const cur = open && !done;
      btn.classList.toggle('locked', !open);
      btn.classList.toggle('current', cur);
      const col = node.boss ? (open ? '#8a5cff' : '#5a4a7a') : done ? '#caa44e' : cur ? '#ffe7a0' : '#4a4436';
      disc.style.borderColor = col; disc.style.color = col;
      disc.style.background = done ? 'radial-gradient(circle at 42% 36%,#6a5a36,#2e2716)'
        : cur ? 'radial-gradient(circle at 42% 36%,#5a4d30,#241c10)'
        : node.boss ? 'radial-gradient(circle at 42% 36%,#2e2046,#150d22)' : 'radial-gradient(circle at 42% 36%,#2a2620,#171411)';
      glyph.textContent = node.boss ? '☾' : (done ? '✓' : '');
    }
    for (const e of edges) { const done = isDone(game.save, nodeById(e.to).requires[0] || ''); e.el.setAttribute('stroke', done ? '#caa44e88' : 'rgba(160,150,120,.25)'); }
  }

  refresh();
  return { refresh };
}
