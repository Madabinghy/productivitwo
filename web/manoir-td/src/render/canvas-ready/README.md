# Pack canvas-ready — rendu 100% Canvas 2D (source de vérité)

Ces modules sont **extraits mot pour mot des protos validés** du projet de design
(dossier « 04 - Rendu Canvas 2D »). Ils remplacent **définitivement** le rendu PNG.

## Règle absolue

- **Supprimer le chemin PNG** : retirer `src/render/art.js`, le dossier `sprites/art/`
  et tous les appels `drawArt(...)`. Le canvas n'est plus un fallback, c'est LE rendu.
- **Ne pas réinterpréter** : mêmes formes, mêmes constantes, mêmes couleurs, mêmes
  vitesses d'animation. Toute divergence visuelle = régression.
- Intégration = brancher l'état du jeu (positions, angles, niveaux, t de déploiement)
  sur les paramètres de ces fonctions. Rien d'autre.

## Modules

| Fichier | Remplace | API principale |
|---|---|---|
| `turrets.js` | tourelles fixes de `buildings.js` | `drawTurret(ctx,cx,cy,type,lvl,T,{size,angle})` |
| `turrets-mobiles.js` | unités-tourelles à chenilles | `drawMobileTurret(ctx,type,lvl,T,{size,angle,trackSpeed})` |
| `commander.js` | `render/hero.js` (PNG commander) | `drawCommander(ctx,s,T,action,facing)` + `drawInfantry(...)` |
| `tortue.js` | tortue de `render/units.js` (PNG) | `drawTortue(ctx,T,state)` + `drawTortueAura(...)` + `TORTUE_CANNONS` |

Toutes les fonctions dessinent **centrées sur l'origine** : faire `ctx.translate(x,y)`
(et éventuellement `rotate`) avant l'appel. `T` = temps en secondes (`Date.now()/1000`).

## Points de comportement à respecter (canon du jeu)

### Tourelles (fixes et mobiles)
- Le design CHANGE par niveau 1→4 : 1 fût → fût large → 2 fûts + 4 pattes → 3 fûts + 6 pattes.
- Sniper : fût unique très long (`len ×2.05`, `w ×0.60`).
- Mobiles : mêmes tourelles SANS pattes, sur essieu + 2 chenilles. Les crampons
  défilent vers l'AVANT (vue de dessus = contact au sol dessous), lentement,
  et tout le châssis pivote vers la direction de déplacement.

### Commander
- Marche TÊTE EN AVANT (facing = direction de déplacement), pieds animés.
- `action='build'` : faisceau triangulaire VERT du bras droit, motes → chantier,
  carré pointillé qui pulse sur le chantier. Portée = sa vue (il ne touche pas le chantier).
- `action='harvest'` : faisceau triangulaire OR du bras droit, motes cristal → commander.
- `action='laser'` : petit laser rose du bras gauche (défense).
- Il s'oriente vers sa cible (passer `facingOverride` en radians).

### Cuirassé-tortue
- Corps (tête + 4 pattes) orienté par `face` = direction de marche (toute la tortue
  tourne, PAS seulement la carapace).
- Carapace tourne indépendamment (`shellRot`) pour présenter les canons à la menace.
- 4 canons sur les pétales (mounts 240/300/180/0°), **chaque canon vise
  indépendamment** l'ennemi le plus proche de son affût (`aim[i]`, cap de rotation
  ~260°/s), recul au tir, tirs décalés (phases 0/.26/.52/.78).
- Marche lente, pattes en cycle diagonal (`gaitAmp` 0→1, horloge `clock`).
- Déployée (`t→1`, ~1s de latence puis 1.1s de transition) : pattes/tête/canons
  rentrés, cœur + liseré OR→VERT, aura de soin (`drawTortueAura`), INCREVABLE
  (masquer la barre de PV), zone de chantier ouverte.

### Infanterie
- Torse-tourelle découplé des jambes : le torse vise/tire, les jambes marchent.
- Écart torse/jambes limité à 90° — au-delà, les pieds pivotent pour rattraper.
- Variantes : `soldat` (rafales rectangles), `elite` (laser continu),
  `lampe` (cône de lumière, éclaireur), `lance` (pointe runique).
