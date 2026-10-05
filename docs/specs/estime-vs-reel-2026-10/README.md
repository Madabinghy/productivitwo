# Estimé vs réel — temps passé sur les actions et calibration des estimations (2026-10)

Demandes : « Peut-on attribuer un temps à une action, manuellement ou à l'appréciation de Claude ? » puis
« Rajouter le temps effectivement passé sur les actions, et permettre à Claude de savoir combien de temps
j'ai passé par rapport à l'estimé, pour affiner ses futures estimations. »

## Principe

- **Estimé** = `TaskAction.estimatedMin` (déjà au modèle, aussi `ProjectTask.estimatedMin`).
- **Réel** = somme des **sessions de chrono ciblées** sur l'action (`Session.actionId`, posé quand on lance ▶
  sur un bloc, une action ou via « Pour ce bloc ») ; pour une tâche, sessions portant son `taskId`.
  Aucun nouveau champ : tout se calcule depuis les sessions. Une session ouverte ou de plus de 12 h (chrono
  oublié) est ignorée ; un bloc coché sans chrono ne compte pas (temps prévu, pas mesuré).
- **Calibration** = médiane de réel / estimé sur les actions **terminées, estimées et chronométrées**,
  arrondie au 0,05 et bornée [0,25 ; 4]. Détail par contexte et par projet/activité dès 3 mesures.

## Serveur (MCP)

- Logique pure `functions/src/estimates.ts` (+ `functions/test/estimates.test.mjs`) : `sessionMinutes`,
  `spentMaps`, `timeEntries`, `measured`, `calibrate`, `overBudget`, `workedUnestimated`, rendu texte.
- Nouvel outil **`estimate_accuracy(days?=90, limit?=15)`** : facteur médian + conseil (« tu sous-estimes :
  multiplie ta première intuition par ~1,4 »), par contexte / porteur, tâches terminées, mesures récentes,
  actions **en cours déjà au-delà** de l'estimation et actions **travaillées sans estimation**, avec leurs ids
  pour `update_action`.
- **`plan_day`** inclut un bloc compact « ESTIMÉ vs RÉEL (90 j) » et une consigne dans le workflow : toute
  action/tâche programmée sans `estimatedMin` est estimée avec le facteur puis **posée** (`update_action` /
  `update_task`), la durée du bloc = cette estimation ; une action déjà au-delà → prévoir le reste. La routine
  du matin enrichit donc les estimations au fil de l'eau, sans changer son prompt.
- `add_activity_action` accepte `estimatedMin` ; `get_user_context` expose `estimatedMin` et `contexts` des
  actions propres ; les descriptions de `add_task` / `update_task` / `push_gantt` mentionnent `estimatedMin`
  sur les actions.
- Estimation manuelle : `update_action(estimatedMin | clearEstimate)` (PR #478) ou l'app.

## App

- Helper pur `lib/utils/time_spent.dart` (`closedSessionMin`, `spentByAction`, `spentLabel`), même règle que
  le serveur, testé (`test/time_spent_test.dart`).
- **Mobile, onglet Actions** : ligne de détail des tuiles et feuille d'action → « ⏱ 35 min passées », en rouge
  au-delà de l'estimation (sessions locales, tout l'historique).
- **Web, onglet Réalisation** : pastille « ⏱ … passées » dans l'espace de travail de l'action (sessions des
  365 derniers jours).

## Pistes

- Saisie manuelle d'un temps passé sans chrono (nécessiterait un champ modèle `spentMinManual`, côté Dart
  aussi pour ne pas être effacé par les sauvegardes de l'app).
- Proposer l'estimation calibrée dans l'app elle-même (popover « Caser », création d'action).
