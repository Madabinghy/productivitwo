// Onboarding — tuto scénarisé de la mission 1, porté par la Veilleuse (la Procrastination).
// File d'étapes : chaque étape attend une condition avant de passer à la suivante.
// Vagues suspendues (game.noSpawn) jusqu'à l'étape de combat. seenTutorial gère le saut.
import { spawnEnemies } from './systems/enemies.js';

const V = '☾ La Veilleuse — ';

function steps(game) {
  return [
    { text: V + 'Bienvenue, petit Majordome. Bouge un peu… ZQSD / WASD (ou clique pour t\'envoyer).',
      enter: (m) => { m.pos = { x: game.HERO.x, y: game.HERO.y }; },
      done: (m) => Math.hypot(game.HERO.x - m.pos.x, game.HERO.y - m.pos.y) > 60 },

    { text: V + 'Ce halo doré, c\'est ta lumière. Approche un gisement de cristaux scintillant…',
      done: () => game.CRYSTALS.some(c => Math.hypot(c.x - game.HERO.x, c.y - game.HERO.y) < 120) },

    { text: V + 'Ton bras droit aspire la masse lumineuse. Regarde-la grimper en haut à gauche.',
      enter: (m) => { m.mass0 = game.G.mass; },
      done: (m) => game.G.mass >= m.mass0 + 12 },

    { text: V + 'Bon… si tu y tiens. Choisis une tourelle (panneau de droite) et pose-la DANS ta lumière.',
      done: () => game.ui.placed.some(p => p.cat === 'turret') },

    { text: V + 'Reste près du chantier : ton bras la bâtit. (La vaisselle attendra, elle.)',
      done: () => game.ui.placed.some(p => p.cat === 'turret' && p.built !== false) },

    { text: V + 'Trop tard pour la sieste : voilà les flemmes ! Tiens la ligne, protège le coffre.',
      enter: () => { spawnEnemies(game); game.noSpawn = false; },
      done: () => (game.G.kills || 0) >= 3 },
  ];
}

export function startTutorial(game) {
  game.noSpawn = true;
  game.tutorial = { active: true, i: 0, steps: steps(game), mark: {}, text: '', closing: 0 };
  const t = game.tutorial; if (t.steps[0].enter) t.steps[0].enter(t.mark);
  t.text = t.steps[0].text;
}

export function updateTutorial(game, dt, onComplete) {
  const t = game.tutorial; if (!t || !t.active) return;
  if (t.closing > 0) { t.closing -= dt; if (t.closing <= 0) { t.active = false; t.text = ''; } return; }
  const step = t.steps[t.i];
  t.text = step.text + '   (' + (t.i + 1) + '/' + t.steps.length + ')';
  if (step.done(t.mark)) {
    t.i++;
    if (t.i >= t.steps.length) {
      t.text = V + 'Tu vois ? La « productivité » paie… dommage. À bientôt, petit Majordome.';
      t.closing = 4; game.noSpawn = false;
      if (onComplete) onComplete();
    } else {
      const next = t.steps[t.i]; if (next.enter) next.enter(t.mark);
    }
  }
}
