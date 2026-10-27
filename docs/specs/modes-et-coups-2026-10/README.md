# Modes et coups tactiques — handoff (2026-10)

Impressions utilisateur du 2026-10-27, après la refonte « une carte, une fiche » :

> « Changer d'humeur à souhait, passer de flemme à motivé dès que je le sens. Une ambiance de couleur selon
> l'humeur : si t'as la flemme, l'appli valide les choses en mode "malgré tout", et ça se voit. La gamification est
> liée à comment tu agis selon comment tu te sens. Renforcer les graphiques avec des micro-objectifs tactiques en
> plus des stratégiques. Aujourd'hui mon attention est fractionnée : l'appli me pousse à faire un peu de tout tous
> les jours ; je manque de recul pour pousser fort dans un domaine et ne plus y revenir avant plusieurs jours. »

Maquette interactive à valider avant tout code : https://claude.ai/artifact/C9VD9gdUGd1yJG7uy6Y1sM (mode en haut du téléphone, trois écrans). Ce handoff décrit le modèle,
les effets et les lots. **Rien n'est codé tant que la maquette n'est pas validée.**

## 1. Le diagnostic en une phrase

L'app demande la même chose tous les jours (minimums vitaux quotidiens + routines quotidiennes + prochaine action
de chaque projet), quel que soit l'état de l'utilisateur. Elle doit **adapter ce qu'elle demande à l'état du
moment**, et donner le droit de **concentrer** l'effort puis de **mettre en veille**.

## 2. Les trois briques

### 2.1 Le mode (Flemme · Normal · En forme)

- **Un état courant**, changeable à tout moment depuis la carte MAINTENANT (pilule « Mode · Flemme ▾ ») et depuis
  Paramètres. Trois positions, pas cinq : c'est une posture, pas un relevé.
- **Zéro double saisie** : poser un mode ÉCRIT un pointage d'élan (`log_mood kind:"elan"`, `mood_marks`) avec
  `value` 2 / 3 / 4 et le `moment` courant ; le mode courant = **dernier pointage d'élan de la journée vécue**
  (≤ 2 Flemme · 3 Normal · ≥ 4 En forme ; aucun pointage = Normal). Le dashboard coach, `get_user_context.elan` et
  les badges « fenêtres de flemme gagnées » continuent de lire la même donnée.
- **Expire** à la bascule de journée vécue (on repart en Normal, l'app peut redemander le matin).

### 2.2 L'ambiance et le « malgré tout »

- **Ambiance** : l'accent de l'app suit le mode — Flemme ambre doux, Normal vert (actuel), En forme teal électrique.
  Visible sur la carte du moment (bordure, pastille « MODE FLEMME »), la barre du bas, les boutons pleins. Discret
  ailleurs (pas de fond coloré plein écran).
- **« Malgré tout »** : une chose validée (bloc, action, étape, routine) pendant que le mode est Flemme porte le chip
  « malgré tout » (ambre) dans les listes et le récap du jour. **Dérivé, jamais stocké** : fait entre deux pointages
  d'élan ≤ 2 (même règle que `elan.ts` pour les fenêtres de flemme). Les badges existants comptent déjà ces fenêtres ;
  on ajoute un badge « Malgré tout » (paliers 5 / 20 / 50 validations en mode Flemme).
- **En forme** : les validations pendant un bloc de deep work (≥ 60 min d'affilée sur une source) portent le chip
  « à fond » ; badge « Deep work » (paliers 3 / 10 / 30 blocs).

### 2.3 Les coups tactiques et la veille

- **Un coup** = un objectif **tactique** : 3 à 10 jours, UNE cible (chiffrée ou en minutes), sur un domaine ou un
  projet. Modèle : **`StrategicObjective` avec `horizon: "tactical"`** (nouveau champ, défaut `"strategic"`), même
  `metric` / `readings` / `timeCommitments`, `endDate` obligatoire ≤ 10 j. Donc la même fiche trajectoire, le même
  graphe (droite attendue courte et raide), les mêmes relevés, et `log_objective_reading` / `save_objective` marchent
  déjà. Listés à part : section « COUPS · n » dans Objectifs (au-dessus des stratégiques), carte « COUP EN COURS ».
- **La veille** : lancer un coup propose de mettre d'autres domaines **en veille jusqu'à la fin du coup**
  (`data/meta.restDomains {domainId: "YYYY-MM-DD"}`). Un domaine en veille : ses minimums ne comptent plus dans
  « Ma semaine » ni dans les lignes Stats (chip « en veille jusqu'au 2 nov. »), ses actions sortent de la carte du
  moment et de la section AUJOURD'HUI d'Actions (restent dans « Plus tard »), `plan_day` ne programme rien dessus.
  Les routines « toute la journée » restent (dormir, boire). La veille se lève d'un tap.
- **Budget sur deux semaines** : les minimums de domaine passent d'un attendu quotidien à un **attendu sur 14 jours
  glissants vers l'avant** (`data/meta.budgetWindowDays`, 7 par défaut, 14 conseillé) : pousser 3 jours sur un sujet
  puis le lâcher 5 jours reste « au rythme ». Le repère « attendu aujourd'hui » reste (fenêtre à départ fixe = début
  de la quinzaine).

### 2.4 « Deep work 90 min » : il propose, tu disposes (décision 2026-10-27)

Le bouton ne lance rien tout seul. Il ouvre une mini-fiche **« Sur quoi ? »** avec trois candidats classés, le
premier présélectionné, un tap confirme :

1. le **coup en cours** s'il y en a un ;
2. sinon le **projet le plus en retard sur son plan** avec une séance proche (même logique que PROJET DU MOMENT,
   `rankProjectMoments`) ;
3. sinon **l'objectif le plus en retard sur son rythme** qui a un engagement de temps (`rankObjectiveMoments`).

Plus une ligne « Autre… » (choix libre : projet ou activité). Une fois confirmé : bloc de 90 min à partir de
maintenant sur cette source (action visée = l'action du coup, sinon la prochaine action du projet), chrono lancé
dessus, et la proposition de mettre en veille les domaines non concernés (cases cochables à ce moment-là). Si un
chrono tourne déjà sur une autre activité, on demande avant de le couper.

Deux cas sans question : un coup en cours dont le projet n'a qu'une prochaine action (la fiche affiche « Deep work
sur … · Changer ») ; un second deep work dans la même journée sur la même source (repart direct). Règle commune avec
Enchaîner : **l'app ne lance jamais un chrono sur un bloc qu'elle a fabriqué sans un geste de l'utilisateur.**

## 3. Ce que le mode change sur la carte du moment

| Onglet | Flemme | Normal (actuel) | En forme |
|--------|--------|-----------------|----------|
| Aujourd'hui · MAINTENANT | Le bloc en cours, mais **une seule étape** ; bouton « 10 min, malgré tout » (chrono 10 min) ; « Enchaîner » devient « 3 petites choses » (routines + étapes ≤ 10 min) | inchangé | Le bloc en cours ; propose **« Deep work 90 min »** sur le coup en cours (sinon l'objectif / projet le plus en retard) : crée le bloc, lance le chrono, coupe les relances |
| Actions · ACTION DU MOMENT | la plus courte faisable (`passesTime quarter`), étapes avant actions | priorités actuelles | l'action du coup en cours, sinon la plus longue estimée du projet le plus en retard |
| Objectifs · OBJECTIF DU MOMENT | la routine engagée la plus simple | actuel | le coup en cours, bouton « Bloc de 90 min » |
| Projets · PROJET DU MOMENT | inchangé (la séance prime) | inchangé | projet du coup en cours en tête |
| Stats · MA SEMAINE | sous-titre « journée malgré tout » | actuel | « journée à fond » |

## 4. Modèle et MCP (lot 0)

- `mood_marks` : inchangé (le mode est un pointage d'élan).
- `StrategicObjective.horizon: "strategic" | "tactical"` (Dart + `types.ts`), `save_objective {horizon}`,
  `list_objectives` sépare `coups` / `objectives`, résumé compact → `coup` en cours (titre, cible, j restants,
  trajectoire).
- `data/meta.restDomains {domainId: ymd}`, `data/meta.budgetWindowDays`, outil `set_mode(kind)` (= `log_mood elan`
  avec le moment courant) et `rest_domain(domainId, until | clear)`.
- `get_user_context` / `plan_day` : bloc `mode` (courant, depuis quand) + `coups` + `restDomains` ; règles de
  `plan_day` par mode : Flemme = blocs courts, routines, rien de nouveau ; En forme = un bloc ≥ 90 min sur le coup,
  pas de dispersion ; domaines en veille jamais programmés.
- Logique pure partagée : `lib/utils/mode.dart` ↔ `functions/src/mode.ts` (**garder alignés**) : `modeOf(marks, now,
  dayStartMin)`, `malgreTout(doneAt, marks)`, `isResting(domainId, restDomains, today)`.

## 5. Lots (une PR chacun)

| Lot | Contenu | Visible |
|-----|---------|---------|
| 0 | Modèle + MCP + logique pure (`horizon`, `restDomains`, `budgetWindowDays`, `set_mode`, `rest_domain`, blocs `plan_day`) | non — **livré** |
| 1 | **Mode** : pilule sur MAINTENANT + Paramètres, écrit l'élan ; **ambiance** (accent par mode) ; chips « malgré tout » / « à fond » dans les listes et le récap ; 2 badges | oui — **livré** |
| 2 | **Carte du moment pilotée par le mode** (tableau § 3) : Aujourd'hui, Actions, Objectifs ; « 10 min malgré tout » et « Deep work 90 min » | oui — **livré** |
| 3 | **Coups** : section Objectifs, carte COUP EN COURS, création en 3 champs (quoi · cible · jusqu'à quand) + choix des domaines à mettre en veille ; veille dans Stats / Actions / plan_day | oui |
| 4 | **Budget 14 j** + `plan_day` par jours de focus (un domaine par demi-journée en Normal, un seul en En forme) ; vue « Répartition sur 14 j » dans la fiche Ma semaine | oui |
| 5 | Web : mode dans le menu ⋯, chips, section Coups dans Projets / Aujourd'hui | oui |

## 6. Hors périmètre / décisions

- Pas de changement automatique de mode par l'app (pas de « tu as l'air fatigué ») : l'utilisateur DIT son état.
- Pas de nouvelle collection pour les coups : un objectif tactique EST un objectif (une fiche, un graphe, un MCP).
- La veille n'efface rien : ce qui est en veille reste dans Projets et « Plus tard », sans relance.
- La journée parfaite reste la même règle ; le « malgré tout » est un chip, pas une note.

## Lot 0 — détail (livré)

- **Logique pure** `lib/utils/mode.dart` ↔ `functions/src/mode.ts` (tests `test/mode_test.dart`, `functions/test/mode.test.mjs`) :
  `DayMode low | normal | high`, `modeOf(marks, now, dayStartMin)` = dernier élan de la journée vécue (≤ 2 · 3 · ≥ 4,
  aucun = normal), `modeAt` / `malgreTout` / `aFond` (mode en vigueur AU MOMENT du fait, dérivé), `modeElanValue`
  (2 / 3 / 4), `parseRestDomains` / `isResting` / `activeRests` (veille jusqu'à la date incluse), `parseBudgetWindowDays`
  (7 | 14), côté TS `modeRules(mode)` (texte pour `plan_day`) et `isTactical`.
- **Modèle** : `StrategicObjective.horizon` (`"strategic"` défaut | `"tactical"`, `isTactical`), Dart + `types.ts` ;
  `pickStrategicObjective` valide (`tactical` exige `endDate`). `ObjectiveSummary.horizon`.
- **AppLogic** : `mode` (getter), `setMode(DayMode)` = `logMood(elan, 2|3|4, moment courant)` + `saveMoodMark`,
  `restDomains` / `budgetWindowDays` alimentés par le flux meta (`main.dart`, `_bindDayStart`), `isDomainResting`.
  `FirestoreSync.setRestDomain(domainId, untilYmd | null)`, `setBudgetWindowDays(7 | 14)`.
- **MCP** : `set_mode(kind)` (= `log_mood elan`), `rest_domain(domainId, until | clear)` (≤ 30 j, domaine existant),
  `save_objective {horizon}`, `list_objectives` → `coups` à part, `get_user_context.mode {current, label, since,
  budgetWindowDays, restDomains[{domainId, name, until}]}` + `coups`, `plan_day` → règles par mode
  (`modeFromContext`) après BLOCS / TITRES. Rien de visible dans l'app.

## Lot 1 — détail (livré)

- **Pilule de mode** `ModePill` (`widgets/mode_sheet.dart`) dans l'en-tête de la carte MAINTENANT (« ⌁ Flemme ▾ »),
  et tuile « Mode du jour » dans Paramètres ; même feuille `showModeSheet` : trois postures avec leur description,
  `AppLogic.setMode` (= pointage d'élan 2 / 3 / 4 au moment courant).
- **Ambiance** `utils/mode_colors.dart` : `modeSeed` alimente `colorSchemeSeed` du thème (Flemme ambre, Normal teal,
  En forme cyan) via `AppLogic.modeNotifier` (`ValueNotifier`, mis à jour à chaque `onChange`) écouté par
  `ProductivitwoApp` ; en sombre `NowPalette.primary` suit `modeAccentOverride` (ambre / teal électrique, null en Normal).
- **Chips** `modeChipFor(context, logic, doneAt)` : « malgré tout » (ambre) / « à fond » (teal) d'après `modeAt` au
  moment du fait — bloc fait du programme (`daily_schedule_view.dart`), action faite (`actions_view.dart`), et récap
  d'Enchaîner (« 3 malgré tout · 1 à fond », instants des faits de la session).
- **Badges** : « Malgré tout » existait déjà (famille Discipline, victoires en fenêtre de flemme : même règle) ;
  nouveau **« Deep work »** (`deep-work`, Discipline, paliers 3 / 10 / 30 = chronos terminés ≥ 60 min d'affilée,
  `deepWorkSessions`, symbole `focus`).

## Lot 2 — détail (livré)

- **Logique pure** `lib/utils/mode_moves.dart` (tests `test/mode_moves_test.dart`) : `activeCoups`, `deepWorkCandidates`
  (coup en cours → son projet / prochaine action ou son premier engagement de temps ; puis `projectPick` = projet le plus
  en retard via `rankProjectMoments` ; puis `objectivePick` = objectif le plus en retard avec engagement de temps via
  `rankObjectiveMoments` ; une source n'est proposée qu'une fois), `deepWorkBlock` (90 min à partir de maintenant arrondi
  aux 5 min, sur la source), `smallChain` (« 3 petites choses » : routines, étapes, actions ≤ 10 min).
- **MAINTENANT** (`now_card.dart`) : Flemme → bouton plein « 10 min, malgré tout » (`onLaunchTimed` → `_launchScheduledBlock`
  + `_startCountdown(10)` dans `main.dart`) et « n petites choses, malgré tout » (Enchaîner en mode `small`) ; En forme →
  bouton « Deep work 90 min · sur quoi ? » quand aucun chrono ne tourne.
- **« Sur quoi ? »** `widgets/deep_work_sheet.dart` (`showDeepWorkSheet`) : candidats radio, premier présélectionné,
  « Autre… » (projets actifs / activités-temps), confirmation si un chrono tourne sur autre chose, puis
  `addScheduleBlock` + `onLaunch(bloc)`. Jamais lancé sans geste. La proposition de veille des domaines arrive au lot 3.
- **Actions** : `pickActionMoment(mode:, focusProjectId:)` — chrono / bloc en cours gagnent toujours ; Flemme = la plus
  courte faisable (`passesTime quarter`, étapes d'abord, pastille « la plus courte · malgré tout ») ; En forme = la plus
  longue du projet le plus en retard (`ActionMomentKind.short` / `deep`).
- **Objectifs** : `rankObjectiveMoments(mode:)` — Flemme : la routine engagée avant le chrono (geste + rang) ; En forme :
  le coup en cours (`isTactical`) devant, et la carte propose « Bloc de 90 min · à fond » (feuille présélectionnée).
- **Ma semaine** : sous-ligne préfixée « journée malgré tout · » / « journée à fond · ».
- Non fait ici : « une seule étape » dans MAINTENANT en Flemme (les étapes restent repliées par défaut), Projets « coup en
  tête » (lot 3, avec les coups).
