# Handoff — Espace Coach (Productivitwo)

## Overview

Suivi des coachés **dans** Productivitwo : un rôle « coach » sur le même compte, pas une seconde app.
Le paquet couvre 8 chantiers, tous conçus en thème sombre Productivitwo :

1. les 4 pistes exploratoires de cadrage (tour 1, encore en Soft Pop clair — **hors périmètre d'implémentation**) ;
2. les relances (composer, règles + file d'interception, bibliothèque) ;
3. le constat chiffré + le mot du coach + l'ajustement d'objectifs ;
4. le refus d'un ajustement par le coaché ;
5. le suivi quotidien (fil du jour, journée en cours, soutien perçu) ;
6. le silence (échelle d'escalade, retour sans dette, point de sortie) ;
7. le « coup de main » coach greffé sur le mode à plat existant ;
8. **l'écran coach assemblé (8a) — c'est la cible d'implémentation prioritaire.**

Principe directeur, à préserver dans le code comme dans la copy :
**la donnée est partagée, l'interprétation reste humaine.** L'app n'écrit jamais à la place du coach le sens des chiffres.

## About the design files

Les fichiers de `design/` sont des **références de design réalisées en HTML** : des prototypes qui montrent l'intention visuelle et le comportement. Ce **ne sont pas** des composants à copier tels quels.

Le travail attendu : **recréer ces écrans dans Productivitwo (Flutter / Dart)**, avec les patterns existants du dépôt `Madabinghy/productivitwo` — `ThemeData` sombre de `lib/web/web_app.dart`, composants de `lib/widgets/`, logique pure et testable dans `lib/utils/` comme `energy_state.dart` ou `recovery.dart`. Aucun HTML/CSS ne doit atterrir dans l'app.

Ouvrir `design/Suivi des coachés.dc.html` dans un navigateur pour manipuler les prototypes (ils sont interactifs) ; `support.js` doit rester à côté.

## Fidelity

**High-fidelity.** Couleurs, tailles, graisses, rayons et copy sont définitifs et repris du thème réel de l'app. La copy française est à reprendre **mot pour mot** : elle porte la posture produit (« pas de morale », « rien ne s'empile », « il voit ce que tu as fait, pas tes états »). Les données affichées sont fictives mais réalistes ; elles montrent le format attendu.

---

## Design tokens

Repris de `lib/web/web_app.dart` (`themeMode: ThemeMode.dark`) — ne pas réintroduire de hex web en dur, mapper sur le `ColorScheme`.

| Rôle | Hex | Source Dart |
|---|---|---|
| Fond écran | `#07100D` | `scaffoldBackgroundColor` / `surfaceContainerLowest` |
| Surface carte | `#0C1C14` | `surface` |
| Surface élevée / sélection | `#152B1E` (et `#12241B` pour les états actifs) | `surfaceContainerHighest` |
| Primaire (coach, succès) | `#27C48F` | `_kSeedDark` |
| Primaire foncé | `#1D9E75` | `_kPrimary` (rails de toggles actifs) |
| Texte principal | `#E8F3ED` | `onSurface` |
| Texte secondaire | `#B9CFC4` | `onSurface` .85 |
| Texte tertiaire | `#86A093` | `onSurface` .6 |
| Texte tertiaire faible (min. utilisable) | `#6E8A7B` ≈ 4.5:1 | — |
| Labels de section (10 px, capitales) | `#5E7A6C` ≈ 3.4:1 | — |
| Alerte / retard | `#FF6B5E` | — |
| Attention / proposition | `#F2A93B` | — |
| Violet d'état (à plat) | `#9F8AFF` | `energyViolet(cs)` dark, `lib/widgets/energy_cards.dart` |
| Avatar corail (coaché en difficulté) | fond `#2A1512`, glyphe `#FF8B7E` | — |
| Filet / bordure | `rgba(255,255,255,.07)` | `Divider` |
| Surface légère (bouton secondaire) | `rgba(255,255,255,.07)` | — |

**Contraste — règle non négociable** (trois régressions corrigées pendant le design) : aucun texte sous `#5E7A6C` sur fond sombre, et pas d'`opacity` globale sur un bloc de texte — désaccentuer par la **couleur**, jamais par l'alpha.

### Typographie
Police système de l'app (pas de Google Font ajoutée) : `-apple-system, 'Segoe UI', Roboto, sans-serif`.
Chiffres : **toujours** `font-variant-numeric: tabular-nums` (Flutter : `FontFeature.tabularFigures()`).

| Usage | Taille | Graisse |
|---|---|---|
| Titre d'écran | 20–22 px | 600 |
| Titre de carte | 15–17 px | 600 |
| Corps | 13–14 px (coach) · 14–15 px (coaché) | 400–500 |
| Label de section | 10 px, `letter-spacing: 1.3–1.4px`, CAPITALES | 700 |
| Grand chiffre | 17–22 px | 700 |
| Tertiaire | 11.5–12.5 px | 400 |

### Espacements, rayons, ombres
- Rayons : carte 20 px · bloc interne 14–16 px · puce/pill 999 px · case de grille 9–12 px.
- Padding : carte coach 22–26 px · carte coachée 18–20 px · ligne de liste 11–14 px.
- Gaps : 8–10 px entre items d'une liste, 14 px entre blocs, 18–22 px entre sections.
- Ombre de carte (prototype uniquement, à traduire en `elevation: 0` + bordure dans Flutter) : `0 26px 60px -30px rgba(0,0,0,.9)`.

### Deux registres, un seul thème
- **Coach (desktop, dense)** : 13 px, tableaux, sparklines, labels 10 px.
- **Coaché (mobile, aéré)** : 15 px, une carte à la fois, **cibles tactiles ≥ 44 px** (les boutons dessinés font 48 px de haut).

---

## Écrans

### 8a — Console coach assemblée ★ priorité
`screens/8a-console-coach.png` · 1380 × 917

Barre supérieure 18/24 px : « Espace coach », point vert 7 px + « en direct · vendredi 24 juillet, 14 h 35 », puis à droite trois pills : « 3 à traiter » (corail), « 1 coup de main actif » (vert), « Semaine du 20 juil. » (neutre).

Grille `264px | 1fr | 348px`, hauteur mini 820 px, filets verticaux `rgba(255,255,255,.07)`.

**Colonne 1 — le rail (qui).** Trois filtres (Tous · 7 / À traiter · 3 / Jour · 3). Liste **triée par attention, jamais alphabétique** : avatar 32 px, nom 13.5 px, état en 11.5 px à la couleur de l'état, compteur d'engagements à droite. Ligne sélectionnée : fond `#12241B`, bordure `rgba(39,196,143,.35)`. Pied de colonne : « Trié par ce qui a besoin de toi… ».

**Colonne 2 — le panneau central (quoi).** Structure **identique pour les 7 coachés** :
1. En-tête : avatar 46 px, nom 19 px, périmètre partagé ; à droite les **3 chiffres de l'US-2** — engagements `4 / 5`, tendance `+20 pts`, dernière activité — chacun avec son label 10.5 px.
2. **Bandeau d'état** : pill d'état + titre 14.5 px + 2 à 3 puces + **une action principale colorée par l'état**. C'est la seule partie qui change de nature (voir « Machine à états » plus bas).
3. « SA SEMAINE — CLIQUE POUR METTRE EN AVANT » : grille 2 colonnes des engagements ; cliquer met en avant (fond `#12241B`, bordure verte) ; compteur « n chiffres joints ». Si le coaché ne partage rien : bloc pointillé « Aucun chiffre à joindre : rien n'est partagé, même pas les statuts. »
4. « TON MOT » : textarea 96 px mini, placeholder « Ce que les chiffres ne disent pas. Sans ça, ce n'est qu'un bilan automatique. »
5. « AJUSTER SES OBJECTIFS — ENVOYÉ COMME PROPOSITION » : deux steppers −/+ avec puce « inchangé » ou « 3 → 2 » en ambre. Absent si rien n'est partagé (message dédié).
6. Actions : « Envoyer le constat et le mot » (vert) + « Garder pour la séance ». Si rien n'est partagé, le primaire devient inerte : « Rien à envoyer tant que rien n'est partagé ».

**Colonne 3 — le temps (quand).** Bascule « Aujourd'hui » / « 4 semaines ».
- *Aujourd'hui* : encart « EN CE MOMENT » (bloc en cours + minuteur `27:14`), puis le fil inversé — heure, nom, événement, bouton de réaction en un clic (Bravo / Un mot / Ajuster) qui devient `✓`.
- *4 semaines* : grille compacte S-3 → S, cases 30 px colorées par palier (voir « Échelle de couleur »).
- Bas de colonne : « PART DEMAIN 8 H · TU PEUX INTERVENIR » — file des relances automatiques, chaque item avec « Laisser partir » / « Retenir ».

### 3a / 3b — Constat chiffré, mot du coach, ajustement
`screens/3a-constat-ajustement.png` (682 × 1309) · `screens/3b-constat-cote-coache.png` (362 × 934)

Le composer complet, en quatre temps numérotés : **1 · les chiffres qui parlent** (5 cartes cochables, chacune avec sa phrase, son contexte — « il y a 3 semaines : 3 sur 3 » — et une sparkline 4 barres), **2 · ton mot** (3 tons qui ne changent que la phrase d'intro, jamais le corps : le texte est écrit par le coach), **3 · ajuster ses objectifs** (steppers + bascule « proposition » vs « application directe »), **aperçu** de ce que le coaché recevra.

Symétrie obligatoire côté coaché (3b) : il voit **les cinq chiffres**, pas seulement ceux mis en avant. Les mis en avant portent la sparkline ; les autres apparaissent en dessous sous « LE RESTE DE TA SEMAINE » avec la phrase « Mathieu voit ces chiffres aussi. Rien de plus, rien d'autre. » Puis le bloc d'ajustement à accepter, avec « Tant que tu n'as pas accepté, tes objectifs actuels restent en place. »

### 4a / 4b — Le refus
`screens/4a-refus-cote-coache.png` (362 × 990) · `screens/4b-refus-cote-coach.png` (602 × 712)

Côté coaché : refuser **est** une réponse — motifs multi-sélection, « ce que tu proposes à la place » (le créneau / le format / rien), ses propres chiffres au stepper, un mot facultatif. Pas de bouton gris culpabilisant.
Côté coach : jamais une alerte rouge. Motifs reçus, « ta proposition · la sienne » en vis-à-vis, **« CE QUE L'APP A FAIT TOUTE SEULE »** (objectifs inchangés, règle de relance mise en pause sur le sujet en discussion, ajout en tête de fiche de séance), et un encart d'historique : « 2ᵉ ajustement refusé en 5 semaines. Les deux fois, l'objectif n'a pas été tenu la semaine suivante. »
Deux cas limites à coder : **refus sans motif** (message spécifique, signal fort) et **« rien à changer » deux semaines de suite**.

### 5a / 5b / 5c — Le quotidien
`screens/5a-fil-du-jour.png` (662 × 781) · `screens/5b-journee-en-cours.png` (522 × 997) · `screens/5c-soutien-quotidien-coache.png` (362 × 671)

Deux garde-fous structurels, non négociables : le mode quotidien s'active **coaché par coaché** (« 3 sur 7 »), et le coach voit **qu'un bloc démarre et se termine, jamais son contenu**. Auto-pause le week-end et remise en question toutes les 3 semaines.
5b : la journée heure par heure (états `vide / partiel / hors / sautée / en cours / à venir`), l'ajustement en un tap sur le bloc à risque (décaler / réduire / retirer sans dette), trois mots pré-écrits.
5c : la présence légère côté coaché + le bloc de contrôle avec toggle et les trois lignes de périmètre.

### 6a / 6b / 6c — Le silence
`screens/6a-silence-echelle.png` (622 × 1085) · `screens/6b-retour-sans-dette.png` (362 × 752)

**La distinction qui pilote tout** : *il lit et ne répond pas* (évitement) vs *il n'ouvre plus l'app* (le canal in-app est mort). L'app détermine laquelle est vraie et met en avant la bonne branche.
Échelle à 4 échelons qui **descend en intensité** — ne rien faire 48 h / un mot hors de l'app / proposer une pause officielle / clore — chacun avec sa conséquence et son brouillon. Aucun échelon n'est automatique.
6b est l'écran le plus important du produit : au retour, **série gelée et non cassée**, aucun engagement marqué raté pendant l'absence, messages **groupés en une carte** (jamais une pile de notifications), et le choix « Reprendre doucement » (un seul engagement — celui qui n'a jamais lâché) / « Reprendre comme avant » / « Mettre en pause ». Aucun compteur rouge, aucun « vous avez échoué ».

### 7a / 7b / 7c / 7d — Le coup de main
`screens/7a-mode-a-plat-coup-de-main.png` (362 × 586) · `screens/7b-activer-coup-de-main.png` (382 × 1199)

Le coach ne s'active pas dans un écran de réglages : **la proposition apparaît dans le mode à plat lui-même**, après 2 jours bas (même déclencheur que la remotivation de `lib/utils/recovery.dart`). Le haut de 7a est le mode à plat existant, inchangé — carte d'état violette, « une chose », « Autre chose ↻ », « 5 blocs en attente ».
7b : durée (2 semaines par défaut / 1 mois / **sans limite** — le user coupe quand il veut, sans annoncer combien de temps), périmètre par domaine en **3 états cyclables** (non partagé → statuts seuls → détail), fréquence (avant les séances / un point par semaine / au jour le jour).
7c : le boost est de la **soustraction** — 5 engagements → 2, 6 blocs → 3. Encart violet « CE QUI N'A PAS CHANGÉ » : l'état se déclare toujours en 1 tap, TTL 3 h, « à plat » propose toujours une seule chose, **et le coach ne voit pas les états déclarés**.
7d : côté coach, une seule action attendue (réduire la semaine à 2 engagements) et le rappel de provoquer la sortie.

---

## Machine à états du panneau central (8a)

Un enum côté domaine, une même carte, sept rendus. Couleur, titre, puces et action changent ; **le composer ne bouge jamais** — c'est ce qui rend l'écran apprenable en un geste.

| État | Déclencheur | Ton | Action principale |
|---|---|---|---|
| `silence` | app non ouverte ≥ seuil (défaut 5 j) | `#FF6B5E` | Envoyer un SMS hors de l'app |
| `refus` | ajustement refusé, réponse reçue | `#F2A93B` | Accepter sa contre-proposition |
| `boost` | coup de main activé par le coaché | `#27C48F` | Réduire sa semaine à 2 engagements |
| `bien` | 3 semaines pleines / autonomie | `#27C48F` | Proposer le palier suivant |
| `explo` | < 3 semaines d'usage | `#86A093` | Préparer le bilan exploratoire |
| `rien` | consentement donné, 0 domaine partagé | `#6E8A7B` | Relancer sur le partage |

---

## Interactions & comportements

- **Sélection au rail** → recalcul complet du panneau central (aucune navigation, aucun rechargement).
- **Mise en avant d'un chiffre** : bascule visuelle immédiate ; ne **filtre pas** ce que le coaché voit — elle ordonne.
- **Steppers d'objectifs** : bornés (`min`/`max` par objectif), puce « avant → après » dès que la valeur diffère de la base.
- **Bascule proposition / application directe** : change le contrat, donc la copy des deux côtés. Par défaut **proposition**.
- **Réactions du fil** : optimistes, irréversibles dans la même journée, une seule par événement.
- **File d'interception** : fenêtre de 24 h, « Laisser partir » / « Retenir » ; retenir n'annule pas la règle, ça saute une occurrence.
- **Toggles** (règles, mode quotidien, coup de main) : piste 38×22 px (46×28 côté coaché), pastille blanche 18 px (22 px), `#1D9E75` actif / `rgba(255,255,255,.12)` inactif.
- Transitions : 120–160 ms `ease-out` sur les changements d'état de sélection. Pas d'animation sur les chiffres.
- **Responsive** : sous 1200 px, la colonne droite passe sous le panneau central ; sous 900 px, le rail devient une barre horizontale de filtres + un sélecteur.

## Règles produit à coder (pas seulement à dessiner)

1. **Anti-empilement** : pendant un silence, les relances automatiques se suspendent. Au retour, le fil est normal.
2. **Quota** : au maximum 1 relance par coaché et par semaine, jamais le week-end.
3. **Une règle ne se déclenche jamais deux fois pour le même motif.**
4. **Rien ne s'applique sans accord** quand le mode « proposition » est actif — l'objectif ne change qu'à l'acceptation.
5. **Périmètre** : un domaine non partagé n'apparaît nulle part, **même agrégé**.
6. **Étanchéité des états d'énergie** : les déclarations À fond / Correct / À plat **ne sont jamais** transmises au coach.
7. **Pause automatique** du mode quotidien le week-end, remise en question à 3 semaines.
8. **Gel, pas de casse** : pendant une absence ou une pause, séries gelées et aucun engagement marqué raté.
9. **Sortie nommée** : pause, fin, ou dernier message — dans les trois cas le coaché garde l'app et ses données.

## État & données

État d'écran (côté coach) : `selectedCoachéId`, `vueTemps: jour | semaine`, `chiffresMisEnAvant: Set<engagementId>`, `brouillonMot: String`, `objectifsProposés: Map<objectifId, int>`, `filtreRail`, `réactionsDuJour: Set<eventId>`, `fileInterception: Map<id, laisser|retenir>`.

Côté coaché : `coupDeMainActif: bool`, `durée: 2sem | 1mois | libre`, `périmètre: Map<domaineId, off|statuts|détail>`, `fréquence: séance | semaine | jour`, `réponseAjustement: accepté | refusé | reporté`, `motifsRefus: Set`, `contreProposition`.

Données à agréger (tout existe déjà dans le modèle) : engagements hebdo et leur tenue, séries 4 semaines, dernière activité, blocs planifiés/faits/sautés du jour, domaines partagés et leur niveau, historique des ajustements (proposé par qui, accepté ou non, résultat la semaine suivante), compteur de silence et distinction *notification lue* / *app non ouverte*.

### Échelle de couleur des paliers (utilisée partout)
`≥ 85 %` → `#27C48F` · `60–84 %` → `#F2A93B` · `< 60 %` → `#FF6B5E` · non partagé / inconnu → `#5E7A6C` sur fond `rgba(255,255,255,.06)`.

## Assets

Aucun. Pas d'icône importée, pas d'image, pas d'emoji : les seuls glyphes utilisés sont `✓ · → ↘ ↦ − +` et des puces circulaires. Les avatars sont des initiales sur pastille colorée.

## Fichiers

- `design/Suivi des coachés.dc.html` — tous les prototypes, interactifs. Chaque écran porte un attribut `data-screen-label` qui correspond aux noms de `screens/`.
- `design/support.js` — runtime nécessaire à l'ouverture locale du prototype.
- `screens/*.png` — captures 1× des écrans clés.

Ordre de lecture conseillé : `8a` (la cible), puis `3a`/`3b` (le geste central), puis les cas particuliers `4`, `5`, `6`, `7`.

## Hors périmètre

Le tour 1 du prototype (`1a` à `1d`) est resté en thème clair « Soft Pop » : ce sont des explorations de cadrage, conservées pour la traçabilité. **Ne pas les implémenter.**
