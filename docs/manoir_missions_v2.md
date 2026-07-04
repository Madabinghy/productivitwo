# Manoir d'Ombrelune — Spec V2 : infiltration, raid, Salle des Ombres, déblocage Gantt

> Statut : **vision validée par l'utilisateur, non implémentée** (sauf briques listées §2).
> Ce doc est la source de vérité de la couche « missions avancées » du Manoir.
> V1 (implémentée) : missions du jour ↔ routines réelles, quête de l'eau, Salle des miroirs,
> PNJ, pont app ⇄ jeu (`ombrelune_sync` / `ManoirBridge`).

---

## 1. La boucle centrale : gagner la prochaine action Gantt

**Principe.** Les projets Gantt sont produits en amont par Claude (via MCP). L'utilisateur
**ne connaît pas leur contenu**. Pour découvrir la **prochaine action** d'un projet, il doit
**la gagner en jeu** : infiltrer une salle, réussir un raid… L'action est la récompense.

La curiosité devient le moteur : « qu'est-ce qui m'attend derrière cette porte ? » remplace
« il faut que je consulte ma liste de tâches ».

**Cycle :**

```
Claude planifie le projet (MCP, invisible pour l'utilisateur)
        │
        ▼
L'app scelle la prochaine action → la pousse au jeu (pont, `ombrelune_next_action`)
        │
        ▼
Le jeu la place dans un coffre au bout d'une mission (infiltration ou raid)
        │
        ▼
Mission réussie → l'action est RÉVÉLÉE (dialogue Lampyre + coffre ouvert)
        │
        ▼
L'utilisateur la fait EN VRAI → cochée dans la Console (Productivitwo)
        │
        ▼
L'app scelle l'action suivante → nouvelle mission disponible
```

**Contrat de données** (pont app → jeu, même mécanisme que `ombrelune_sync`) :

```
ombrelune_next_action = {
  d: "YYYY-MM-DD",              // fraîcheur
  projectId, taskId, actionId,   // pour marquer la révélation côté app
  projectName: "…",              // affichable AVANT révélation (teasing)
  sealed: true,                  // le titre n'est PAS envoyé tant que sealed
  title: null | "…",             // envoyé seulement après révélation
}
```

- Côté app : la « prochaine action » = première `TaskAction` non faite de la première
  tâche `pending` du projet actif (même logique que le widget iOS / `get_user_context`).
- Révélation : le jeu poste `{type:'reveal_action'}` sur `ManoirBridge` → l'app renvoie le
  titre (et le note, ex. champ `revealedAt` sur la TaskAction ou stockage local).
- **Web pur (sans pont)** : pas d'action disponible → la mission donne une récompense
  générique (masse lumineuse / cosmétique). La boucle Gantt est **bridge-only**.

---

## 2. Briques existantes (à réutiliser, ne pas réécrire)

| Brique | Fichier | État |
|---|---|---|
| Infiltration stealth complète (gardes à cônes de vision balayants, patrouilles, jauge de détection, cachettes derrière meubles, clé → porte, lampe à baisser) | `web/manoir-td/Compagnon - Infiltration.html` (« La Galerie des ombres ») | ✅ codée, **orpheline** (aucun lien n'y mène) |
| Puzzle miroirs (rotation, faisceau, victoire) | `Compagnon - Énigme optique.html` | ✅ en prod (Mission 2) |
| **Moteur de raid complet** (Commander jouable, économie de masse, construction occupée, tourelles + soutiens, Cuirassé-tortue, commandant ennemi, campagne, brouillard) | `index.html` + `src/` | ✅ codé, hors parcours — **c'est LE mode raid des missions** |
| Mini-vague « résister aux vagues » (`?waves=&routine=`) | `Mini-vague - Jouable.html` | ✅ relié à l'Accueil — side-game léger, **PAS le mode raid** |
| Salle `sanctuaire` (+ escalier « Crypte rituelle ») | `Manoir - Exploration.html` | ✅ en prod |
| Pont app ⇄ jeu (`ombrelune_sync`, `ManoirBridge`) | `lib/widgets/manoir_screen.dart` (PR #225) | ✅ codé |
| Écrans annexes : Déduction, Évasion, Choix du soir | `Compagnon - *.html` | ✅ codés, orphelins |

---

## 3. Le portail du Sanctuaire → « La Salle des Ombres » (mission « 007 »)

**Accès.** Dans le Sanctuaire de l'Exploration, un **portail** (POI, rendu type cercle
d'invocation) ne s'active que si une action scellée existe (`ombrelune_next_action`).
Lampyre : « Derrière ce portail, l'ennemi garde le prochain pas de ton projet _{projectName}_. »

**La salle.** Une carte dédiée (nouvel écran vanilla, réutilisant le moteur de la Galerie
des ombres) qui **mixe les trois mécaniques** :

1. **Caméras à éviter** — les cônes balayants des gardes de l'Infiltration, montés sur
   pivots muraux ; zones d'ombre = sûres ; jauge de détection globale.
2. **Tourelles / pièges à poser** — budget limité de « masse lumineuse » gagnée par les
   missions du jour (lien avec la V1 : mieux tu vis, mieux tu t'équipes). Une tourelle
   posée aveugle une caméra ou bloque une patrouille ; un piège fige un garde quelques
   secondes. Repris du panneau de pose du TD (`src/systems/turrets.js` simplifié).
3. **Miroirs intégrés à la map** — des miroirs pivotables (mécanique de l'énigme optique,
   posée sur la grille de la salle) redirigent un faisceau de lumière : ouvrir la porte
   blindée du coffre ET/OU éblouir une caméra un instant. Tap sur le miroir = rotation.

**Structure de la salle (3 actes, ~3-5 min) :**

- Acte 1 — entrer : éviter 2 caméras, atteindre la console de pose (choisir ses pièges).
- Acte 2 — traverser : patrouilles + caméras ; utiliser pièges/tourelles posés.
- Acte 3 — le coffre : puzzle miroirs sous pression (une caméra balaie la zone du puzzle) ;
  faisceau aligné → coffre ouvert → **révélation de l'action Gantt** (bridge `reveal_action`).

**Échec** (détection pleine) : renvoyé au portail, l'action reste scellée — réessayable à
volonté (jamais punitif, ton Soft Pop). Les pièges déjà posés persistent pendant la session.

**Alternative « raid »** : certains projets/actions sont gardés par un **raid** plutôt
qu'une infiltration. ⚠️ **Le raid = le moteur complet** (`index.html` + `src/`) — le mode
évolué : Commander jouable, économie de masse, pose de tourelles/soutiens, Cuirassé-tortue,
**commandant ennemi à vaincre** (objectif offensif : détruire sa base / son coffre, pas
« résister aux vagues »). La Mini-vague reste un side-game de l'Accueil, elle n'est **pas**
un type de mission. Lancement : `index.html?raid=1&reward=action` (carte/nœud de campagne
dédié) ; victoire = `reveal_action`. Variété : infiltration = projets « réflexion »,
raid = projets « exécution » (heuristique simple, ou aléatoire V1).

---

## 4. Phasage proposé

- **V2.1 — brancher l'existant (petit)** : portail au Sanctuaire → `Compagnon -
  Infiltration.html` telle quelle ; victoire = révélation de l'action scellée (pont) ;
  app : sceller/pousser `ombrelune_next_action`, répondre à `reveal_action`.
  → La boucle Gantt complète tourne avec 0 nouveau gameplay.
- **V2.2 — la Salle des Ombres** : nouvel écran mixant caméras + pose de pièges (budget =
  missions du jour) ; le portail y mène ; l'Infiltration Galerie reste une mission secondaire.
- **V2.3 — miroirs dans la map + raids** : puzzle miroirs intégré (acte 3), et branchement
  du **moteur de raid complet** (`index.html?raid=1&reward=action` : mission offensive,
  vaincre le commandant ennemi → révélation) en alternance avec l'infiltration, puis
  variété (Déduction/Évasion réintégrées comme types de missions).

---

## 5bis. Lampyre-tamagotchi : le soin réfléchi

**Principe (validé).** Lampyre est un tamagotchi dont on prend soin — mais on ne le nourrit
pas directement : **prendre soin de soi, C'EST prendre soin de lui**. Boire un verre d'eau
réel → il boit avec toi (gorgée animée). Accomplir ses missions du jour → il rayonne.

- **Vitalité** = f(hydratation 0→10, missions du jour accomplies). Rayonnant : flamme haute,
  halo ample, bob vif, rit souvent. Négligé : **somnolent** (flamme basse, paupières lourdes,
  bob lent, rires rares) — **jamais malade, jamais mourant** (ton Soft Pop, pas de chantage).
- **Moments de lien** : chaque verre réel déclenche « Lampyre boit avec toi 💧 » (goutte +
  flamme qui bondit + petit rire), dans l'Exploration comme à l'Accueil.
- **Croissance (évolutions, implémentée)** : Lampyre naît **Étincelle** (flammèche sans corps)
  et grandit avec l'**XP des soins réels** — +1/verre, +5/mission du jour, +5/25 min trackées,
  créditée une fois par jour et par soin (`ombrelune_lampyre` = {xp, stage, credited}).
  Stades : Étincelle (0) → Lueur (30) → Lampyre (100) → Veilleur (250) → Flamme gardienne (450).
  Visuels : taille qui monte, **la mèche pousse** (trait → brin courbé → brin fier avec pousse),
  braises fidèles en orbite aux hauts stades. Montée de niveau = flash + toast + rire.
  Rythme : ~35 XP/journée pleine → Lueur au 1er jour, Lampyre vers le 3e, Gardienne ≈ 2 semaines.
- **V1 implémentée** (Exploration + Accueil) : vitalité dérivée de `ombrelune_water` +
  `ombrelune_sync` (aucun nouveau stockage). Extensions possibles : lecture → il raconte des
  histoires (variété de dialogues), méditation → flamme stable, sommeil, humeurs persistantes,
  soin du portrait dans les Accueils.

---

## 5. Garde-fous (hérités des missions V1)

- Jamais punitif : échec = retour au portail, rien de perdu.
- Toujours lisible dans le noir : halo permanent, cônes de vision dessinés.
- Le RÉEL prime : la révélation donne l'action, mais **la cocher se fait dans la Console**
  (Productivitwo) après l'avoir réellement faite — le jeu ne « fait » jamais le travail.
- Une mission = 3-5 min max ; réessayable immédiatement.

## 6. Moteur de génération procédurale (`web/manoir-td/js/ombrelune-gen.js`)

Principe : **découpler le contenu de jeu des actions IRL**. On ne rejoue jamais deux fois
la même partie — le contenu est généré ; l'IRL augmente la puissance/complexité globale
(éveil du manoir, et bientôt l'arbre de talents), pas au goutte-à-goutte.

- **PRNG à graine** (mulberry32) : même `seed` + même `difficulty` = même partie.
  - Mission du portail → graine dérivée de l'id de l'action Gantt (reproductible, pas de re-tirage en cas d'échec).
  - Partie libre → graine aléatoire à chaque lancement.
- **`genMirror(seed, diff)`** : énigme de miroirs **prouvée résoluble par construction**
  (on trace le chemin du rayon d'abord, chaque virage pose un miroir, la fin devient le sceau ;
  puis brouillage des orientations + leurres et murs HORS chemin solution). Difficulté 1/2/3 :
  2/3/4 miroirs actifs, 1/2/3 leurres, 0/2/4 murs.
- **Consommation** (`Compagnon - Énigme optique.html`) : `?reward=action|?free=1` + `seed` + `difficulty`
  → plateau généré. `?free=1` = partie **sans enjeu** : n'écrit NI `ombrelune_mirror_quest` NI
  `ombrelune_revealed` ; pied de page « Une autre énigme ↺ / Retour au manoir ». La mission 2
  classique (sans paramètre) garde le plateau historique fixe.
- **Rejeu diégétique** : la table de la Salle des miroirs (quête résolue) propose « Jouer une
  énigme des miroirs » → partie libre générée, difficulté = `guardDiff()` (éveil du manoir).
- La difficulté des gardiens du portail vient désormais de **l'éveil** (`guardDiff()` :
  palier 0-1 → 1, 2-3 → 2, 4 → 3), plus du compteur de trophées.
- À venir : `genEnquete` (pools + contraintes logiques, unicité du coupable vérifiée) puis
  `genOmbres` (segments de map + placement caméras/gardes + validation de faisabilité), et
  l'arbre de talents (« Établi ») alimenté par l'XP.
