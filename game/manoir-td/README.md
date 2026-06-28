# Manoir d'Ombrelune — Tower Defense (V1)

Réimplémentation **V1** du prototype `Manoir - Aménagement.dc.html` (handoff design) dans un
vrai moteur. Tower defense / SupCom-lite en vue de dessus : on défend un coffre-fort contre
les « flemmes ». Thème : productivité vs procrastination.

## Moteur retenu

**Canvas 2D + `requestAnimationFrame`, vanilla JS (modules ES), zéro dépendance.**

Pourquoi (cf. recommandations du README de handoff) :
- Le prototype est déjà en JS — la logique (tick, BFS, collisions) se porte ~1:1.
- Jeu 2D temps réel léger : pas besoin d'un moteur complet (Phaser) ni d'un build.
- Les **sprites sont redessinés au canvas** (chemins/dégradés), pas en `<div>` CSS empilés.
- Testable sans dépendances ni build (Chromium headless).

Le **monde** est rendu au canvas (sprites dessinés) ; le **HUD/panneaux** sont une surcouche
HTML/CSS (lisible, accessible, facile à maintenir).

## Lancer

Servir le dossier en HTTP (les modules ES exigent http, pas `file://`) :

```
cd game/manoir-td
python3 -m http.server 8099    # ou: npx serve
# puis ouvrir http://localhost:8099/
```

## Structure

```
index.html            — page + fonts (Cinzel / Chakra Petch) + HUD + canvas
src/
  config.js           — toutes les constantes (carte, coûts, couleurs, thèmes, stats)
  state.js            — état de jeu central (G, HERO, ui, CRYSTALS…)
  geometry.js         — collisions murs, ligne de vue, distance de rayon
  graph.js            — graphe de nav, murs, bougies, BFS
  main.js             — boucle de jeu (rAF) + assemblage des systèmes
  systems/
    enemies.js        — flemmes : spawn, errance BFS, chasse, tir tourelles
    turrets.js        — tourelles (étoffé étape 5)
  render/
    index.js          — orchestrateur (caméra + monde + entités)
    world.js          — sol, salles, couloirs, murs, portes, portails, bougies
    sprites.js        — flemmes, coffre, cristaux
    hero.js           — le Commander
```

## Périmètre V1 (étapes 1→7) — complet ✅

1. ✅ Carte manoir + collisions + pathfinding ennemi (BFS).
2. ✅ Commander jouable (déplacement, orientation, 3 actions par bras).
3. ✅ Économie : masse plafonnée + mottes + gisements rechargeables.
4. ✅ Construction « occupée » à portée de vision (faisceau doré).
5. ✅ Tourelles payantes orientables (+ balayage 180°) + 4 bâtiments de soutien.
6. ✅ Vision jour/nuit + brouillard + minimap.
7. ✅ Vagues d'ennemis + conditions victoire/défaite + rapport.

## Contrôles

- **Déplacement** : ZQSD / WASD / flèches.
- **Souris** : survol = fantôme de pose ; clic = poser / sélectionner ; molette = pan.
- **Espace** : récupérer la tourelle sous le héros. **G** : déposer un gisement (test).
- **Tactile** : pose en 2 temps (tap fantôme → tap confirmer) ; pan à 2 doigts.
- Panneau droit : choisir tourelle/soutien. Bouton **☀/☾** : bascule jour/nuit.

## Hors V1 (V2)

Multi-constructeurs / Ingénieur, Cuirassé-tortue déployable, Cercle d'invocation (usine),
Stockage (plafond+), la Veilleuse comme boss + messages tentateurs, campagne/donjon,
postures d'unités. (Réfs dans `protos-reference/` du handoff — non implémentées.)
