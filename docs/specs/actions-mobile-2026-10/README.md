# Onglet « Actions » mobile — refonte (2026-10)

Retour utilisateur : « Je n'utilise quasiment pas l'onglet Actions du mobile. » Audit du 2026-10-04,
3 lots validés et livrés en une PR. Fichier : `lib/widgets/actions_view.dart` (+ `steps_section.dart`
partagé avec la fiche de tâche). Logique pure réutilisée : `lib/utils/actions_logic.dart` (web),
`checklist_logic.dart`, `today_logic.dart`.

## Constats (avant)

1. **Vide par défaut** : aucun contexte « Je suis @… » coché ⇒ aucune action affichée, avec un
   message demandant de choisir où l'on est. Plus un filtre Domaine au-dessus : deux décisions avant de
   voir une ligne.
2. **Tuiles muettes** : titre + contextes. Pas d'échéance, de retard, d'estimation, d'étapes, ni
   d'indice « déjà au programme ».
3. **Tap = assigner les contextes** (process GTD), fiche projet en appui long. Le geste « agir » n'existait
   pas.
4. **Groupement par projet seulement**, sans lecture d'urgence ; pas de « J'ai 15 min » ni de « Possible
   maintenant » contrairement au web.
5. **Deux dérivations** (web `actions_logic.dart` vs mobile maison) qui divergeaient.

## Lot 1 « une liste qui répond tout de suite »

- Plus jamais vide : toutes les actions ouvertes des projets actifs non en pause (prochaine action du
  projet en tête, ordre Gantt ensuite) + actions simples des activités, via `projectActionGroups` /
  `ownActionGroups` (web).
- **Groupement par urgence** (défaut) : *Maintenant* (lot 3) · *Aujourd'hui · au programme* (actions
  portées par un bloc du jour) · *En retard* (échéance de la tâche passée, triées) · *Cette semaine*
  (≤ 7 j) · *Plus tard · par projet* (ordre d'échéance des projets, « Définir la prochaine action » pour
  un projet sans action) · *Actions simples*. Bascule **par projet** (icône dossier / horloge),
  persistée (`actions_by_project`).
- **Filtres optionnels** sur une ligne défilante : « J'ai 15 min · 1 h · Plus » (`passesTime`,
  persisté `actions_time_filter`), « Je suis @… » (`passesContexts`, multi, partagé avec Maintenant via
  `nowContexts`, **ne verrouille plus**), Domaine (persisté). Une ligne « n actions masquées par les
  filtres » et un bouton « Tout afficher » quand rien ne passe.
- **Tuile** : titre + ligne de détail (porteur dans les sections d'urgence, échéance « éch. 7 oct. » /
  « −3 j » rouge / « demain », « ≈ 45 min », « 2/5 étapes », contextes), point vert « au programme
  d'aujourd'hui », bordure rouge si en retard, ▶ chrono si une activité est liée.

## Lot 2 « agir en un geste »

- **Tap = feuille d'action** (bottom sheet) : fil d'Ariane projet › tâche (ou activité), case faite,
  pastilles (échéance, estimation, contextes, « au programme »), **étapes** (`StepsSection` : cocher avec la
  règle d'achèvement, ajouter, appui long = renommer / retirer ; action faite ⇒ la feuille se ferme),
  boutons **Chrono** · **Caser** (feuille date / heure / durée existante, durée = estimation) ·
  **Contextes (& chrono)** (ancien « process ») · **Projet**.
- **Glisser à droite = fait** (SnackBar « Annuler »), **à gauche = caser demain** (feuille préréglée sur
  demain 9 h). Les deux laissent la tuile en place (`confirmDismiss` → false) : la liste se recompose.
  Appui long = fiche projet, inchangé.
- **Capture rapide** en tête : champ « Capturer une idée… » → `CaptureItem` (boîte d'entrée existante,
  badge du menu, traitée par ORION / revue hebdo). Aucune activité à choisir : capturer d'abord, trier
  ensuite.

## Lot 3 « maintenant »

Section en tête de la liste par urgence, qui suit l'état :
- **chrono en cours** → « Possible maintenant · <activité> » = `possibleNow` (actions liées à cette
  activité, directement ou par le projet, + ses actions simples) ;
- sinon **bloc en cours** ou **prochain bloc** du programme (`focusBlock` sur le flux du jour,
  `resolveBlockAction` ou `actionId` du bloc) → l'action visée, étiquetée « Bloc en cours · 14:00 » /
  « Prochain bloc · 15:30 ».
Le programme du jour est écouté en flux (`streamDailySchedule`) : les points « au programme » et la
section Maintenant suivent le programme sans rechargement.

## Non fait / pistes

- Réordonner les étapes sur mobile (poignée réservée aux actions).
- Trier les sections d'urgence par estimation quand « J'ai » est actif.
- Une capture qui devient action en un geste depuis la boîte d'entrée (aujourd'hui : traitement ORION /
  revue hebdo).
