# « Une carte, une fiche » — simplification de l'app mobile (2026-10)

Retour utilisateur (2026-10-27) : « J'aime beaucoup le système de bloc principal avec la fiche qui s'ouvre, et le
style de la fiche objectif. J'aurais aimé retrouver le même fonctionnement dans les autres onglets. » Maquette
validée : https://claude.ai/artifact/B2jkmPnATVzJgKwVphRJex (téléphone interactif, 5 onglets, fiches).

## La grammaire (invariants)

1. **La carte du moment** en tête de chaque onglet : étiquette en capitales + pastille, anneau à gauche, titre,
   ligne « reste / état », UN bouton plein et « Fiche ». Une seule chose, un seul geste. Jamais deux cartes qui se
   disputent le haut de l'écran. Widget partagé `widgets/moment_card.dart` (`MomentCard`, `MomentRing`).
2. **Les lignes** : icône · titre · sous-ligne chiffrée · barre fait / attendu avec le repère vertical « attendu
   aujourd'hui » · état à droite (chip ou écart). La même ligne pour un objectif, un projet, une action, un domaine.
   Widget partagé `widgets/status_row.dart` (`StatusRow`, `StateChip`, `ExpectedBar`, `ListSectionTitle`).
3. **La fiche** au tap : feuille à 85 %, en-tête + chip d'état + ligne repère, puis des sections en capitales dans
   le même ordre partout — CETTE SEMAINE → DEPUIS LE DÉBUT → RÉSULTAT / PROCHAINE ÉTAPE → gestes. Ossature partagée
   `widgets/fiche.dart` (`showFiche`, `FicheHeader`, `FicheTitle`, `FicheDelta`, `FicheStep`, `FicheNote`,
   `FicheActions`). La fiche objectif (`objective_trajectory_sheet.dart`) est le modèle.
4. **Trois couleurs d'état** partout : vert ≥ 85 % du rythme · ambre ≥ 60 % · corail en dessous
   (`utils/palier_colors.dart`, déjà utilisé par la jauge objectif). Une question par écran : suis-je au rythme ?

Ce qui disparaît : les en-têtes explicatifs, les cartes secondaires empilées au-dessus du contenu, les tableaux à
colonnes, les segments à trois positions. Ce qui reste : les gestes rapides sur la ligne (▶, +1, coche), les filtres
repliés sous la liste, les écrans existants derrière les fiches (plan d'action, écran séance, Enchaîner).

## Lots (une PR chacun, mergée aussitôt)

| Lot | Onglet | Carte du moment | Ligne | Fiche | État |
|-----|--------|-----------------|-------|-------|------|
| 1 | **Projets** | PROJET DU MOMENT = séance à 7 j la plus proche, sinon le plus en retard sur son plan (`rankProjectMoments`, `utils/project_moment.dart`) ; anneau = tâches faites / total ; geste = prochaine action (chrono si activité liée, sinon plan à la tâche) | tâches faites avec repère « attendu aujourd'hui » (tâches dont l'échéance — sinon le début — est passée), chip au rythme / à surveiller / en retard / au point mort / à venir | `widgets/project_fiche_sheet.dart` : CETTE SEMAINE (actions à 7 j + prépa de la séance) · DEPUIS LE DÉBUT · AVANCEMENT · PROCHAINE SÉANCE (▶ écran séance, état de la prépa) · Prochaine action / Plan d'action / Terminer / Mettre en veille / Rouvrir | **livré** |
| 2 | **Actions** | ACTION DU MOMENT = action du bloc en cours, sinon la plus urgente faisable ici ; anneau = étapes faites ; geste = Étape suivante ou ▶ Chrono | groupes par urgence en sections d'une seule liste ; filtres J'ai / Je suis / Pour repliés dessous | fiche action : porteur + tâche en entier, ÉTAPES, DÉTAIL (note), ÉCHÉANCE, gestes (Chrono · Caser demain · Fait · Rattacher) | **livré** |
| 3 | **Stats** | MA SEMAINE : anneau = engagements d'objectifs tenus (décision 2026-10-26), geste = rapport de la semaine | une ligne par domaine : fait / minimum vital, repère « attendu à ce jour » | fiche domaine : la feuille existante (`_showDomainDetail`) pour l'instant ; fiche « Ma semaine » absorbe jauges du jour, courbe de la semaine, Élan, temps, camembert, retards | **livré** |
| 4 | **Aujourd'hui** | MAINTENANT reste la carte (inchangée dans l'esprit) | le programme est la liste ; Routines et Objectifs = deux lignes « en parallèle » dont la fiche ouvre la vue du moment ; plus de pilule à trois segments | fiche du bloc (l'écran bloc devient une feuille `showFiche`) : Projet › Tâche, étapes, « ensuite dans cette tâche », Bloc terminé | **livré** |
| 5 | **Objectifs** + harmonisation | déjà le modèle ; la carte « Relevé de la semaine » disparaît (le relevé dû est le geste de la carte) ; archivés en section repliée avec « Réactiver » | carte Objectif du moment partagée (`ObjectiveMomentCard`) et carte Routine du moment migrées sur `MomentCard` | fiche trajectoire inchangée + confirmation sur Archiver | **livré** |

## Lot 1 — détail (livré)

- `lib/utils/project_moment.dart` : `projectPlan` (faites / total / attendues à ce jour, hors `gtd-flow` et sautées),
  `ProjectMoment` (plan, santé `projectHealth`, prochaine séance `nextInterventionOf`, actions de la semaine =
  échéance effective ≤ 7 j ou dépassée + actions de la prépa, `nextAction`, `upcoming`, racine « Pour … »),
  `rankProjectMoments` (séance à 7 j → retard de plan → prochaine action → à venir → reste ; dossiers, archivés, en
  pause exclus), `sessionLabel`. Tests `test/project_moment_test.dart`.
- `lib/widgets/goals_view.dart` réécrit (1 580 → 300 lignes) : carte du moment (pastille « 1 / n · suivant › »),
  TOUS LES PROJETS, sections repliées À VENIR / EN PAUSE / TERMINÉS / EN VEILLE (état `projects_sections_folded`),
  tap = fiche, appui long = plan d'action. Le radar « Cette semaine » (`week_radar_card.dart`) n'est plus affiché sur
  mobile : la séance la plus proche porte la carte du moment, les autres sont dans la sous-ligne. Les cartes projet
  détaillées (phases, tâches, fil de l'eau) sont remplacées par la fiche + le plan d'action existant.
- `GoalsView` reçoit `sessions` (santé du projet) ; `main.dart` les passe.

## Lot 2 — détail (livré)

- `pickActionMoment` (`utils/actions_logic.dart`, testé) : l'ACTION DU MOMENT = celle que vise le chrono en cours →
  celle du bloc en cours → la plus en retard → la première au programme du jour → celle du prochain bloc → la plus
  proche échéance à 7 j → la première de la liste. La carte (`MomentCard`) prend la pastille correspondante
  (« bloc en cours · 14:00 », « en retard · −3 j »…), l'anneau = étapes faites (sinon temps passé sur l'estimation),
  « Projet › Tâche » en contexte, et UN geste : « Étape faite : … » (coche l'étape suivante), ▶ Chrono (activité liée),
  Fait, ou « Arrêter le chrono » en contour. « Fiche » = la fiche d'action.
- **Lignes** (`_entryTile` sur `StatusRow`) : titre · « Projet › Tâche · ⚑ éch. · ≈ 45 min · ⏱ passées · @ctx » ·
  barre des étapes quand il y en a · chip (en cours / nouveau / au programme / « −3 j » corail) · ▶ si une activité
  est liée. Swipes inchangés (droite = fait, gauche = caser demain), appui long = plan du projet.
- **Sections** : titres en capitales au même gabarit que les autres onglets (`_sectionLabel`, `ListSectionTitle`).
- **Filtres repliés** sous la capture : ligne « FILTRES · J'AI · JE SUIS · DOMAINE · POUR » (ouverte d'office au
  premier affichage quand un filtre est actif, avec le compte des masquées).
- **Fiche d'action** (`_openActionSheet` sur `showFiche`) : en-tête (coche + titre + chip d'état : faite / chrono en
  cours / en retard / au programme / échéance / à faire) + ligne repère (porteur › tâche · contextes · estimation ·
  passées), ÉTAPES (`StepsSection`), DÉTAIL (note), ÉCHÉANCE (propre ⚑ ou de la tâche), gestes : Chrono ou Fait (plein),
  Caser, Échéance, Contextes, Projet, Rattacher à un projet.

## Lot 3 — détail (livré)

- `utils/week_stats.dart` (testé) : semaine CALENDAIRE (lundi → maintenant). `domainWeeks` = par domaine : minutes
  faites (`minutesByActivity`, session ouverte comprise), minimum vital quotidien (`domainGoalMinDay` : réglé à la main,
  sinon Σ des objectifs des activités-temps), attendu à ce jour = minimum × jours écoulés, routines tenues
  (`weekEngagements`, seuil `kKeptRatio`) ; tri = les plus en retard d'abord. `weekSummary` = engagements des objectifs
  en cours (`engagedRoutineIds` ; aucun → toutes les routines), chrono de la semaine, `pct` = `engagementPct`.
- `widgets/week_stats_view.dart` (`WeekStatsView`) : carte MA SEMAINE (anneau « n % tenus », pastille « mer. · jour 3 / 7 »,
  contexte « Engagements des objectifs », titre Semaine au rythme / à tenir / en retard, sous-ligne chrono + tenus,
  geste « Détail de la semaine ») ; lignes `StatusRow` par domaine (fait · minimum · attendu, barre avec repère,
  « n % », routines tenues ; tap = feuille du domaine, appui long = ses routines) ; « Gérer » = feuille des domaines.
- Fiche « Ma semaine » (`showFiche`) : ENGAGEMENTS DES OBJECTIFS (une étape par routine, tenue = cochée), puis
  AUJOURD'HUI ET LA SEMAINE = les anciennes cartes de l'onglet, passées telles quelles par `main.dart` (`weekDetails`) :
  jauges Activités / Routines / Projets + courbe de la semaine, Élan & discipline, temps par domaine, camembert du jour,
  compteur de retards. `_buildDashboardBody` ne garde que le cache par tick et `WeekStatsView` ;
  `_buildDomainListLive` supprimé.

## Lot 4 — détail (livré)

- **Plus de pilule Actions · Routines · Objectifs** (`_segmentBar`, `_setSegment`, préférence `today_view_segment`
  retirés) : Aujourd'hui = MAINTENANT (inchangée) + programme + section **EN PARALLÈLE** sous le programme
  (`_parallelSection`) : ligne **Routines · 5 / 18** (`StatusRow`, barre faites / total, chip « n à faire » / « à jour »,
  sous-ligne = `RoutineDay.shortLine`) et ligne **Objectifs · n** (objectif du moment : titre · n % du rythme · reste …,
  chip « n relevés à noter » ; `rankObjectiveMoments`). Tap = fiche (`showFiche`) qui héberge la vue existante :
  `RoutinesDayView` (carte Routine du moment, journée par moments, Enchaîner, Organiser) et `ObjectivesDayView`
  (carte Objectif du moment, badges visés, cartes par objectif, Enchaîner un objectif). La carte « Relevé de la
  semaine » n'est plus en tête d'Aujourd'hui : le relevé dû est signalé par le chip de la ligne Objectifs et se note
  depuis la carte Objectif du moment. `_routinesLine` supprimée.
- **Fiche du bloc** (`block_work_screen.dart`, `showBlockWorkScreen`) : même contenu qu'avant (action visée avec ses
  étapes, « Étape suivante », ensuite dans cette tâche, faites, Voir la tâche, Bloc terminé) mais en feuille
  `showFiche` avec `FicheHeader` (▶ chrono en tête, titre de la tâche, chip « en cours · reste 52 min » / « à 14:00 » /
  « fait », ligne projet · créneau). Routage inchangé (`_openBlockSource`, `main.dart`).

## Lot 5 — détail (livré)

- `widgets/objective_moment_card.dart` (`ObjectiveMomentCard`) : la carte OBJECTIF DU MOMENT sur `MomentCard`, partagée
  par l'onglet Objectifs (`objectives_card.dart`, sans blocs du programme) et la fiche Objectifs d'Aujourd'hui
  (`objectives_day_view.dart`, avec les blocs). Même geste qu'avant (`ObjectiveMove`), « Fiche » = trajectoire,
  « Enchaîner · n choses » quand un `onChainObjective` est fourni.
- **Onglet Objectifs** (`objectives_card.dart`) : carte du moment en tête, section « OBJECTIFS · n » avec « + Nouveau »,
  une ligne `StatusRow` par objectif (barre temps investi fait / total avec repère « attendu aujourd'hui », sinon
  jauge hebdo ; écart « −2h18 » / « +0h40 » / « n % » ; sous-ligne investi · attendu · j restants · relevé à noter ; tap
  = fiche, appui long = éditer), et **« ARCHIVÉS · n »** repliée (atteints + archivés, bouton **Réactiver**, tap = fiche).
  La carte « Relevé de la semaine » (`objective_readings_card.dart`) n'est plus affichée nulle part (le relevé dû est le
  geste de la carte du moment et une mention dans la ligne) ; le fichier reste.
- **Confirmation sur Archiver** dans la fiche trajectoire (`_setStatus`).
- **Routine du moment** (`routines_day_view.dart`) : la carte passe sur `MomentCard` (nouveaux slots `detail` = pilule
  chrono + ⏱ + réglages, `actions` = rangée +1 / −1 / Suivante / Pas maintenant ▾ + menu + Enchaîner) ; comportement
  inchangé. `MomentCard` gagne `detail` et `actions`.
