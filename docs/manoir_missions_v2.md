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

## 5ter. Couche de SIGNAUX : le manoir consomme du général, pas du spécifique

**Principe (validé).** On ne binde JAMAIS les routines/actions spécifiques du user sur des
mécanismes dédiés (impossible à l'échelle, friction). L'app calcule des **métriques
générales, agnostiques des domaines**, et le manoir évolue sur l'agrégat.

- **`ombrelune_signals`** (poussé par le pont, `lib/widgets/manoir_screen.dart` `_pushSync`) :
  `{ d, routinesDone, routinesActive, focusMin }` — routines tenues / actives **tous domaines
  confondus** (pas les 5 du scénario), focus réel du jour.
- **`creditSignals()`** (`Manoir - Exploration.html`) : XP GÉNÉRALE — +4 / routine tenue,
  +5 / tranche de 25 min de focus. Idempotent par jour (`L.credited.sigR` / `.focus`).
  Repli focus sur `ombrelune_sync` en web pur.
- **`creditCare()`** réduit au **soin de soi** (eau — hook tamagotchi). Le focus et les
  « missions » spécifiques ne créditent plus d'XP en double : les 5 routines-scénario
  restent une **couche de saveur** (célébration + croissance de salle via `checkCelebrations`),
  plus le moteur d'XP. `_applyXp()` factorise la montée de stade.
- Découplage : ce que le user fait EXACTEMENT (ses domaines, ses routines) ne pilote plus
  directement le jeu — le manoir consomme un signal normalisé.

**Baptême des salles — auto-mapping (socle, sans friction).** L'app pousse `ombrelune_domains`
(`[{name,color}]`, domaines réels non supprimés). Le manoir (`applyConsecration()`) mappe chaque
domaine sur sa salle par **affinité de mots-clés** (`DOM_KEYWORDS` par méta-domaine : « muscu »
→ Atelier, « guitare » → Bibliothèque…), affiche le vrai nom du user comme sous-titre de salle
(`consecratedName`) et le récapitule dans le Journal (« Tes domaines dans le manoir »). Un
override manuel (`ombrelune_consecration`, roomK→nom) est prioritaire — le **baptême explicite**
(dialogue Lampyre à l'éveil) viendra l'éditer ; d'ici là, auto-mapping intelligent, zéro config.
Domaines non reconnus : simplement pas consacrés (la salle garde son méta-domaine générique).

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
- **`genEnquete(seed, diff)`** : enquête à contraintes logiques — suspects tirés d'un pool
  avec **traits visibles** (mains/parfum/pas, étiquettes sur les cartes), indices = filtres
  machine (`elim: {type:'trait'|'alibi'}`), **unicité du coupable vérifiée par force brute**
  (`enqueteSurvivors`). Difficulté 1/2/3 : 3/4/5 suspects, 3/3/4 indices. Crimes doux
  (bougies, clé d'argent, confiture…), réfutations et verdict générés.
- **Consommation** (`Compagnon - Déduction.html`) : reward/`?free=1` + `seed` + `difficulty`
  → enquête générée ; classique (chaîne Compagnon) = cas historique fixe. `?free=1` :
  pied de page « Une autre enquête ↺ / Retour au manoir ».
- **Rejeu diégétique** : « Dossier d'enquête » à la Bibliothèque (éveillée jour 1) → enquête
  libre générée. Patron `talkSpot` : un spot porteur de `href`/`hrefFn` dialogue puis navigue.
- **Enquête incarnée** (`Manoir - Exploration.html`) : les enquêtes générées se jouent
  DANS le manoir — suspects = PNJ temporaires (silhouettes teintées + étiquette de nom),
  indices = objets lumineux posés dans les salles éveillées (positions déterministes par
  graine, ancres par salle). Interaction = **vue de face** (`#hud-face`, carte plein écran :
  portrait, traits, examiner/accuser/réfutation/verdict). État persisté `ombrelune_enquete`
  {seed, diff, mode:free|reward, collected[], state} — le spec est régénéré à chaque
  chargement (déterminisme). Entrées : « Dossier d'enquête » (biblio) = libre ; gardien
  Déduction du portail = reward (révèle l'action à la conclusion). La page
  `Compagnon - Déduction.html` reste pour la chaîne classique (et accepte toujours free/reward).
- **Butin persistant** (`ombrelune_butin`) : chaque enquête résolue laisse l'objet du crime
  (clé d'argent, pot de confiture…) posé À DEMEURE dans la salle du coupable — inspectable
  en vue de face (nom, date, histoire) ; `creditRoom` sur la salle (le butin fait grandir).
  À étendre aux autres types de missions.
- **La Fouille** (couche 1 « escape game ») : les meubles des salles ÉVEILLÉES se
  fouillent en vue de face (« Regarder sous le lit », « Ouvrir la caisse »…) — rien n'est
  affiché sur la carte, on fouine. Butin du jour déterministe (graine = date, reset
  quotidien, `ombrelune_fouille`) : la **loupe 🔍** (une fois — `ombrelune_tools`), une
  fiole d'huile (+5 min, `ombrelune_oil` — réserve pour la lanterne à venir), une poussière
  de lumière (+2 XP), une breloque (`creditRoom`). Enquêtes : à partir de la difficulté 2,
  des indices sont CACHÉS dans les meubles (`l.hidden`, assignés par la graine d'enquête) ;
  à 3, l'un exige la loupe (`l.needsLoupe`). Décision : la fouille opère DANS l'espace
  éveillé (l'éveil = macro-gating ; la croissance ajoute des meubles = des caches).
- **La Lanterne** (couche 2) : noir quasi-total (halo de base 130) mais TOUJOURS traversable
  — la lanterne (bouton HUD 🏮) déploie un cône directionnel (suivant la marche) et consomme
  l'**huile en minutes réelles** (`ombrelune_oil`). Sources : don de bienvenue (10 min),
  fioles de fouille (+5), **focus réel** (30 min → +5, crédité via `ombrelune_sync`), don
  quotidien de Lampyre à sec (+3, jamais bloqué). **Fouiller exige la lanterne allumée.**
- **Serrures & clés** (couche 3) : 3 coffrets verrouillés (biblio/office/cabinet,
  `ombrelune_chests`) — les clés se GAGNENT par le réel : cuivre = missions du jour toutes
  faites, fer = journée à 10 verres, or = 3 trophées (`checkKeys` sur les reloads).
  Butins : **lampe UV 🔦**, +15 min d'huile, Sceau du fondateur (+5 XP + butin).
- **Runes UV** : 3 runes visibles UNIQUEMENT lampe UV en main ET lanterne éteinte (le noir
  complet, geste inverse de la fouille). +3 XP chacune ; les 3 → butin « Triptyque des
  runes » au Grand Hall (`ombrelune_runes`).
- **Journal de bord** : tap sur la bannière → vue de face consolidée (enquêtes en cours avec
  progression + bouton « Ranger ↩ » sans pénalité, missions du jour, état du portail, besace
  huile/outils/clés).
- **Multi-enquêtes** : jusqu'à **2 enquêtes en parallèle** (`ombrelune_enquetes`, liste ;
  migration auto de l'ancien slot unique). Chaque entité (suspect/indice/indice caché) porte
  son index `q` ; progressions, verdicts et butins indépendants. Une seule mission du portail
  à la fois ; le portail ne peut jamais écraser une enquête en cours. Le noir d'expédition
  s'applique si l'une des enquêtes actives est une expédition.
- **`genOmbres(seed, diff)`** : génération de MAP pour la Salle des Ombres — assemblage
  vertical de **segments dessinés à la main** (6 gabarits 560×200, mélangés + miroir
  gauche/droite), budget caméras/gardes par difficulté (3/4/6 cams, 1/1/2 gardes,
  3/4/5 bandes), **puzzle de faisceau généré** avec son dilemme préservé (capteur → coffre
  OU aveugler la caméra du coffre), et **validation avant de servir** : faisceau-solution
  dégagé, un abri par caméra, un socle de glu sur chaque ronde, points clés hors meubles
  (80 tirages max → repli sur le plan historique). Consommation : `?seed=N` (la graine de
  mission voyage dans l'URL du gardien — échec = même plan) ; sans seed = plan fixe.
  ⚠️ application du plan APRÈS toutes les déclarations `var` (hissage).
- **Raid de jalon** (`index.html?raid=1&reward=action&seed=N&difficulty=D`) : quand la
  prochaine étape est une **tâche entière** (sentinelle `task:` = jalon), le gardien du
  portail est un **RAID avec le moteur TD complet** — mission directe sur un nœud de
  campagne choisi par la graine (d1 m3/m4, d2 m5/m6, d3 m7/m8), roster « comme si » la
  campagne y était rendue, **sauvegarde de campagne jamais touchée** (partie transitoire).
  Victoire (« JALON CONQUIS ») → révélation immédiate (même flux pont/`ombrelune_revealed`),
  « Retour au manoir ✦ » ; défaite → reprendre à volonté ou se replier au manoir.
- **Butin de jeu → enquêtes** (`ombrelune_minigame_loot`) : les mini-jeux joués en LIBRE
  (énigme optique `?free=1`, Salle des Ombres sans reward via la « Brèche d'entraînement »
  du Sanctuaire) déposent un jeton à la victoire. Au retour, l'Exploration le convertit :
  un indice délogé pour l'enquête EN COURS, sinon une nouvelle affaire réveillée au tiroir
  (sinon +3 XP si le manoir est saturé). Jamais bloquant — le loot fait AVANCER, la
  CONCLUSION reste gatée par l'IRL (lumière d'expédition ← focus, révélation ← action réelle).
- **L'Établi des talents** (`Manoir - Exploration.html`) : la PUISSANCE globale forgée par
  l'XP (donc par l'IRL). **1 point ◆ tous les 25 XP** de Lampyre (`pcTotal/pcSpent/pcAvail`),
  dépensés dans un arbre (branche Infiltration) persisté dans `ombrelune_skills` {spent:{…}} :
  ⚡ Masse lumineuse (3 rangs, +1 ⚡ de départ/rang), 🕸️ Glu tenace (2 rangs, gel 6→9→12 s),
  🌑 Pas d'ombre (2 rangs, détection −15 %/rang). UI = vue de face (POI « L'Établi des talents »
  dans l'Atelier) ; ligne de rappel dans le Journal ; teaser « branche · Tours » pour les raids.
- **Consommation** (`Manoir - Salle des Ombres.html`, `skillLvl(k)` sur `ombrelune_skills`) :
  `G.masse = min(4, 1+masse)` (remplace la masse au goutte-à-goutte des missions du jour),
  glu `frozen = 6+3·glu`, `DET_RATE ×= [1,.85,.7][ombre]`. Découplage : l'effort quotidien
  nourrit l'XP → les ◆ → une puissance PERMANENTE, plus un bonus jetable par jour.
