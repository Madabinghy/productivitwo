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
| 3 | **Stats** | MA SEMAINE : anneau = engagements d'objectifs tenus (décision 2026-10-26), geste = rapport de la semaine | une ligne par domaine : fait / minimum vital, repère « attendu à ce jour » | fiche domaine : CETTE SEMAINE, 4 DERNIÈRES SEMAINES (barres), activités et routines, réglage du minimum ; fiche « Ma semaine » absorbe Productivité et Élan | à faire |
| 4 | **Aujourd'hui** | MAINTENANT reste la carte (inchangée dans l'esprit) | le programme est la liste ; Routines et Objectifs = deux lignes « en parallèle » dont la fiche ouvre la vue du moment ; plus de pilule à trois segments | fiche du bloc (remplace l'écran bloc) : Projet › Tâche, étapes, « ensuite dans ce bloc », Bloc terminé | à faire |
| 5 | **Objectifs** + harmonisation | déjà le modèle ; la carte « Relevé de la semaine » disparaît (le relevé dû est le geste de la carte) ; archivés en section repliée avec « Réactiver » | migrer la carte Objectif du moment et la carte Routine du moment sur `MomentCard` | — | à faire |

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
