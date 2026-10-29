# Productivitwo — CLAUDE.md

Application de productivité Flutter (iOS/Android/Web). Backend Firebase.
Langue du code : anglais. Langue des commentaires et UI : français.

---

## ⏪ Pivot productivité (2026-07) + points de restauration

**Depuis 2026-07, la couche jeu est ABANDONNÉE** : Productivitwo redevient une pure app de
productivité (cible : power users prêts à payer — Pro via RevenueCat, app web, Gantt).
La refonte « Soft Pop » de 2026-06 (design Fredoka/palette violet-corail + couche jeu
tower-defense XP/⚡/💎) n'est **pas retenue** côté jeu.

État de la couche jeu :
- **Coupée de l'UI** par deux flags à `false` dans `lib/gamification_flags.dart` :
  `kOldGamificationEnabled` (or/combat/donjon/expédition/hub) et `kGameLayerEnabled`
  (Manoir d'Ombrelune, mise du jour). Le code gaté restant est du code mort volontaire.
- **Purgée progressivement** : orphelins mobiles, écrans Flame/Rive, `social.ts` backend
  (leaderboards, batailles, invasions), règles/index Firestore du jeu — déjà supprimés.
  Le reste (`lib/web/unified_world_sheet.dart` etc.) partira par lots.
- Onglets mobiles actuels : **Objectifs / Stats / Projets / Actions / Aujourd'hui** (5 ; 4 avec
  `hideProjectsTab` ; `_Tab` dans `lib/main.dart`, onglet d'arrivée = Aujourd'hui). Ne pas réintroduire d'UI de jeu.
  **Actions mobile** (refonte 2026-10, handoff `docs/specs/actions-mobile-2026-10/README.md`,
  `lib/widgets/actions_view.dart`) : jamais vide, groupée par urgence (Maintenant · Aujourd'hui · En retard · Cette
  semaine · par projet · simples) ou par projet, filtres optionnels J'ai / Je suis / Domaine (le contexte ne verrouille
  plus), tap = feuille d'action (étapes `StepsSection`, chrono, caser, fait), glisser droite = fait / gauche = caser
  demain, capture rapide → boîte d'entrée, et **« n captures à trier en actions »** (2026-10,
  `widgets/capture_triage_sheet.dart`) : une capture à la fois, titre retouchable, destination projet › tâche (« Au fil de
  l'eau » = `flowTaskOf`, `utils/actions_logic.dart`) ou activité-temps ; la capture passe `processed` avec la trace
  « → action … ». Même logique pure que le web (`utils/actions_logic.dart`).
  Chaque carte porte au-dessus du titre « Projet › Tâche » (la tâche seule en vue par projet) ; la feuille d'action
  affiche le porteur puis la tâche EN ENTIER (plus de fil d'Ariane tronqué). **« Rattacher à un projet »** (2026-10, feuille
  d'une action SIMPLE) : choix du projet (actifs, hors dossiers) puis de la tâche ou « Au fil de l'eau » ; l'action quitte
  `ownActions` et entre dans le projet en gardant titre, `note`, contextes, estimation et son activité en `linkedActivityId`
  (chrono) — elle prend le « Pour » du projet (`attachOwnActionToProject`, `utils/actions_logic.dart` ;
  `FirestoreSync.moveOwnActionToProject`). Le « Pour » n'est jamais une étiquette : toujours déduit de la hiérarchie.
  **À venir** (2026-10, mobile et web) : une action dont la TÂCHE n'a pas encore commencé (`startDate` > aujourd'hui,
  `isUpcomingTask`) sort de la liste principale et des compteurs pour une section repliée « À venir · n », triée par
  date de début avec « dès demain / dès jeu. 15 oct. / dès le 2 nov. » (`upcomingActions`, `upcomingLabel`,
  `utils/actions_logic.dart`) ; toujours cochable. Exception mobile : action au programme du jour = reste devant. Web :
  `_taskFilter` exclut toujours les tâches à venir ; un projet dont tout est à venir affiche « Prochaine action dès … »
  au lieu de « Définir la prochaine action ».
  **Date par action** (2026-10, lot 1 = modèle + MCP + logique pure, rien de visible) : `TaskAction.dueDate` (jour, optionnel,
  `YYYY-MM-DD` en base) ; l'échéance EFFECTIVE d'une action = `effectiveDueDate(a, task)` (la sienne, sinon celle de la
  tâche ; `isOverdueAction`, `overdueActionCount` par action) — ne jamais lire `dueDate` ou `task.endDate` seuls. MCP :
  `dueDate` sur les objets action de `push_gantt` / `add_task` / `update_task` (préservée au re-push par titre) et
  `add_activity_action`, `update_action {dueDate | clearDueDate}` (`action_patch.ts`). **Lot 2 (livré)** : mobile —
  tuiles et feuille d'action sur l'échéance effective (« ⚑ » = échéance propre), bouton « Échéance » de la feuille
  (demain · fin de semaine · date · retirer, `_pickDueDate`) ; web — badge « ⚑ éch. … » sur la ligne, champ « Échéance
  propre » du dialog d'édition, filtre « En retard » PAR ACTION (`entryFilter` de `projectActionGroups`, `_entryOk`).
  Étiquettes partagées `actionDueLabel` / `shortDateFr`. **Planificateur de semaine** (`week_planner.dart`, 2026-10) :
  `WeekTask.due` = échéance effective la plus proche des actions ouvertes (sinon la tâche), `overdue` par action, une tâche
  hors fenêtre entre si une action y a sa propre échéance (`actionsDueInWindow`, « ⚑ n » dans la ligne) ; tri, groupe
  « En retard » et prompt Claude sur `due`. **Prochaine action** (`nextAction`, `project_health.dart`) = l'action ouverte
  à l'échéance effective la plus proche (sans date → ordre Gantt, après les datées) : Projets, tête des groupes d'Actions.
  **Dossiers / clients** (2026-10) : un projet racine sans tâche dont d'autres projets dépendent (`parentProjectId`) est un
  *dossier* (`isFolderProject`, `rootProjectOf`, `clientRoots`, `groupByFolder` dans `utils/actions_logic.dart`). Web :
  vue fusionnée (`utils/folder_merge.dart`, Vision/Plan d'action/Réalisation) + regroupement dans Projets + filtre
  « Pour… » dans Actions. Mobile : en-tête de FAMILLE repliable dans Projets (`goals_view.dart`, `groupByRoot` : racine dossier OU projet
  avec ses propres tâches, dont la carte devient « Général » ; plus de mention « sous-projet de ») + filtre « Pour » dans
  Actions ; jamais « Définir la prochaine action » sur un dossier. Filtre « Pour… » (`inClient`, `actions_logic.dart`) :
  un client choisi ne montre QUE ses projets (les actions simples d'activité disparaissent) ; entrée **« Perso »**
  (`kPersoClientId`) = les actions sans projet ; « Tous » = tout.
  **Inbox mobile** (2026-10-30, `widgets/inbox_sheet.dart`) : section « À VALIDER · n » EN TÊTE = les propositions ORION en
attente (`streamProposals`), validables sur place (`ProposalCard` partagée avec `proposals_sheet.dart` : Accepter · Rediriger ·
Refuser) ; une idée « proposée » dont la proposition est affichée n'est plus listée en double ; « TRAITÉ PAR ORION · n » replié
par défaut, 20 plus récents.
  **App bar mobile** (2026-10-30) : titre = pilule 24 h + `ModePill` (dans un `FittedBox`, jamais de débordement) ; `actions`
= Inbox (point ambre si captures) + menu ⋯ (Propositions à valider, Orion, Revue, Filtres, Nouveautés, Catalogue, Paramètres).
La pilule sommeil a été retirée de la barre (le sommeil se lit dans Stats). Ne rien rajouter dans le titre.
**Question d'état retirée** (2026-10-30) : la carte « ORION · ÉTAT » (À fond · Correct · À plat, `EnergyQuestionCard`) n'est plus
posée par `now_coach_zone.dart` (fichier `energy_cards.dart` supprimé) : le mode Flemme / Normal / En forme la remplace.
**Fusion Aujourd'hui + Maintenant** (handoff `docs/specs/ios-aujourdhui-2026-09/README.md`) : la carte
  MAINTENANT (`lib/widgets/now_card.dart`) + zone coach (`now_coach_zone.dart`) sont en tête de
  `lib/widgets/today_view.dart` ; `focus_view.dart` a été supprimé ; programme du jour en liste 48 px
  (`daily_schedule_view.dart`, titre vide = nouveau style) — handoff livré (3 PR). Toute navigation « vers Maintenant » passe par `_goNowTab()` (Aujourd'hui + scroll haut).

**Points de restauration permanents (ne jamais modifier/supprimer) :**

- **`archive/couche-jeu-complete-2026-07`** = état complet AVANT la purge du jeu
  (commit `f72eb3a`). Repêcher : `git checkout archive/couche-jeu-complete-2026-07 -- <chemin>`.
- **`archive/style-actuel-2026-06`** (commit `2f335d1`) = l'app/style AVANT la refonte Soft Pop.
- Rien n'est perdu tant qu'on ne **force-push jamais** sur `main`. ⚠️ Ne **jamais** force-push.
- Note : les **tags** ne sont pas poussables via le proxy git de session (403 politique) — d'où
  l'usage de **branches d'archive** comme repères, créées via l'API GitHub.

---

## 🎯 Cap produit & business (2026-07) — lire avant tout développement

**Référence** : business plan v1.0 → résumé dans `docs/VISION.md` ; spec prioritaire dans
`docs/specs/espace-coach-v1.1.md`.

**Le pari** : le problème n°1 des apps de productivité est l'abandon (~72 % de churn annuel B2C).
Le levier anti-churn est la redevabilité humaine → Productivitwo est l'app quotidienne du coaché,
avec une couche de visibilité pour le coach (**Contrat d'Engagement partagé** : objectifs +
engagements hebdo formalisés en séance, mesurés automatiquement, cockpit coach avec alertes).
Croisement vide sur le marché francophone.

**Séquencement (ne pas développer en avance de phase)** :
1. **Phase 1 (→ oct. 2026)** : coaching augmenté — 5 coachés actifs au 01/10/2026.
2. **Phase 2 (6-18 mois)** : cohortes 8-12 semaines.
3. **Phase 3 (12-36 mois)** : abonnement B2C (essai 14 j, PAS de freemium), puis licence B2B coachs.

**Priorités de dev** (⚠️ gel V1 **levé par l'utilisateur le 2026-07-24** — Export/Import et
Espace Coach peuvent démarrer sans attendre le 17/08) :
1. Finaliser la **V1** (échéance 17/08/2026).
2. **Export / import des données** (lot « Coffre », `docs/specs/export-import-donnees/README.md`) :
   lot 1 = export .json, lot 2 = restauration Fusionner/Remplacer.
3. **Espace Coach V1.1** (`docs/specs/espace-coach-v1.1.md`) : invitation/consentement →
   cockpit multi-coachés → rapport de pré-séance → message coach via ORION → alerte décrochage.
   Design hifi (thème sombre) : `docs/specs/espace-coach-design/README.md` — cible = console
   coach `8a` ; le design dépasse le périmètre V1.1, suivre le MoSCoW de la spec.
4. Parcours de cohorte (T1 2027), puis onboarding self-service + Stripe + essai 14 j (T2-T3 2027).

**Refonte de l'app web (2026-09, lots 0 à 7 livrés)** : handoff dans `docs/specs/refonte-web-2026-09/README.md`
(shell à 5 onglets Aujourd'hui / Cette semaine / Projets / Actions / Bibliothèque, thème vert sombre
de l'Espace coach, 8 lots = 8 PR). La nouvelle interface **remplace** le shell web actuel, sans flag ni
route `?proto=` (le prototype `?proto=pisteb` de la PR #425 a été absorbé au lot 1). Shell :
`lib/web/web_shell.dart` (`WebTab`, `WebTopBar`) · tokens `lib/web/theme_tokens.dart` · vues dans
`lib/web/views/`. ORION n'est plus un onglet (route plein écran via le menu ⋯), plus d'overlay flottant.
Focus a disparu (lot 3) : son contenu est réparti entre Aujourd'hui, Cette semaine (`week_view.dart` +
`lib/utils/week_planner.dart`) et Projets ; la carte Vision vit dans le menu ⋯ (`vision_dialog.dart`).
**Cette semaine v2** (handoff `docs/specs/cette-semaine-2026-09/README.md`, remplace le § 3) : Gantt
7 / 14 jours pleine page, tout se manipule dans la grille (clic sur un jour = popover « caser », points =
blocs du programme, glisser = déplacer les dates, tirer le bord = échéance, clic droit = couleur). Pas de
tableau de colonnes par jour ni de liste « à caser » séparée (décision § 7 du handoff). Audit d'ergonomie 2026-10
(3 lots livrés, détail dans le handoff) : annulation partout, infobulles/curseurs, dates + estimation sur la ligne
(`estimatedMin` éditable depuis le popover), capacité dans le popover, groupe « En retard » en tête, et
« Planifier la semaine avec Claude » (`planWeekPrompt`, `claude_link.dart`) à la place du bouton ORION. Colonne des
tâches **réglable à la souris** (400 px par défaut, persistée), poignée partagée avec le Gantt projet :
`lib/web/column_resizer.dart`.
Aujourd'hui, **disposition active** (2026-10, `docs/specs/maintenant-actif-2026-10/README.md`) : quand le chrono
tourne SUR la source du bloc en cours (`_liveBlock`, bloc d'activité ; les blocs de tâche passent par la bande
Focus), MAINTENANT prend la colonne large (`_nowCardWide` : anneau + reste, déroulé du bloc, contexte, Ensuite)
et le programme passe en liste compacte de 340 px (`_scheduleListCard`). Seuil ≥ 1280 px ; en dessous, repos.
Dès qu'elle est affichée (chrono ou pas), la frise se **recentre sur le trait « maintenant »** (`scrollToNow`,
appelé par `_go(WebTab.today)` du shell ; aussi au premier programme chargé, au changement de jour et quand la
frise revient après la disposition active).
**Aujourd'hui orienté action** (2026-10, `docs/specs/aujourdhui-web-actions-2026-10/README.md`) : carte « Au
programme · concrètement » (`_agendaCard` : blocs à venir dépliables, étapes de l'action visée cochables, actions
possibles d'une activité, +1 de routine, « Définir la prochaine action ») sous MAINTENANT ; ligne concrète dans les
blocs hauts de la frise (`_blockHint`) ; carte « Routines du jour » (`_routinesCard`, logique `utils/routines_today.dart`).
Frise **« Aujourd'hui | Demain »** (`_daySwitch`, `_cardDate` / `_cardBlocks`) : demain dans la même frise, sans trait
« maintenant », ni coche, ni chrono ; **zoom vertical** ×1 → ×8 (`_zoomBy` : Ctrl/⌘ + molette ou pincement autour du curseur,
boutons − / +, repères :30 / :15 quand on zoome, mémorisé en SharedPreferences) ; **clic sur un créneau vide = nouveau bloc** à ce quart
d'heure (fantôme « + HH:MM » au survol, `_addBlock(at:)`) ; **« + » au survol d'un bloc** = bloc en parallèle (même heure,
même durée) ; **glisser un bloc** = le déplacer, **tirer son bord bas** = changer sa durée (pas de 5 min,
heures affichées pendant le geste, annulable ; jamais un miroir agenda — `_canDrag`) ; blocs qui se chevauchent côte à côte (`overlapColumns`) ; Modifier / Ajouter / « Préparer avec Claude » (`planDayPrompt`) agissent sur demain.
**Clic sur un bloc à contenu = ouvert sur place** (`_detailCard`, frise et liste) : « Projet › Tâche », action visée et ses
étapes cochables (`blockWork`), autres actions ouvertes, « Ouvrir le projet » / « Modifier le bloc » / « Bloc terminé ».
Modules de la colonne de droite **repliables en accordéon** (Routines, Chronos, À traiter, Cette semaine, Échéances ;
`_foldHeader`, état mémorisé `today_side_folded` en SharedPreferences).
Bouton « Demain → » à côté de la date = dialog `web/tomorrow_schedule_dialog.dart` (‹ › jours suivants, blocs dépliables).
Projets (lot 4) = tableau `views/projects_view.dart` + `lib/utils/project_health.dart` (état calculé,
prochaine action, 7 jours) ; menu ⋯ d'une ligne : **Terminer le projet** (`status:'done'`, confirmation s'il
reste des tâches ouvertes) → liste « Terminés · n » (Rouvrir / Archiver) ; « Définir la prochaine action » partagé dans `web/quick_add_action_dialog.dart`.
Fiche projet (lot 5) = `views/project_plan_view.dart`, onglets **Vision · Plan d'action · Réalisation** (2026-10, du
plus large au plus fin : Vision = Gantt, Plan d'action = tâches + actions, Réalisation = étapes des actions), hébergée
dans le shell ; **s'ouvre sur Vision** au clic sur un projet (essai 2026-10), sur **Plan d'action** quand elle vise
une tâche (bloc, action : `targetTaskId` → phase de la tâche dépliée) ; « Masquer le fait » actif par défaut ; « Nouvelle tâche » partagé dans `web/add_task_dialog.dart`, visionneuse de
documents dans `web/document_viewer_dialog.dart`. L'onglet **Document** (`ProjectDocView`, playbook Markdown) a été
**retiré** en 2026-10 au profit de **Réalisation** (`views/project_checklists_view.dart`, handoff
`docs/specs/checklists-2026-10/README.md`) : plan phases → tâches → actions à gauche, espace de travail de l'action à
droite (étapes cochables, renommables en place, réordonnables, ajout à la volée, marquer faite / rouvrir). Pas de 4ᵉ
niveau : le modèle `ChecklistItem` est inchangé, donc tout reste cochable sur mobile et par le MCP ; la fiche de tâche
mobile (`widgets/project_sheet.dart`, `_StepsSection`) déplie les étapes au tap (cocher, ajouter, appui long =
renommer / retirer). Helpers purs dans
`utils/checklist_logic.dart` (`setChecklistItem`, `addChecklistItem`, `renameChecklistItem`, `moveChecklistItem`,
`setActionDone`, `nextChecklistItem`). **Fiche de tâche mobile** (2026-10, `widgets/task_fiche_sheet.dart`, `showTaskFiche`,
`showTaskDetail` de `project_sheet.dart` y délègue ; l'ancienne `_TaskDetailSheet` est retirée) : `FicheHeader` (émoji de rôle
📝 / 🎯 / ✅ en petit, titre sans l'émoji, chip faite / chrono en cours / en retard · n j / au programme / à faire, ligne projet ·
phase · dates · k / n actions · ⏱ passées), ACTIONS en `StatusRow` (cocher = fait avec Annuler, tap = fiche d'action
`showActionFicheOfTask` : ÉTAPES `StepsSection`, DÉTAIL note, ÉCHÉANCE propre, ACTIVITÉ LIÉE, Lancer / Marquer faite /
Modifier / Organiser ; appui long = Monter · Descendre · Déplacer · Promouvoir · Supprimer), FAITES repliées, DÉTAIL repliable
(description, dates + phase, activité liée, documents via `showDocList`), `FicheActions` (Lancer la prochaine action si une
activité est liée et `onStartTimer` fourni, sinon Ouvrir ; Arrêter le chrono ; Rouvrir ; + Action · Modifier · ⋯ : Au
programme, Déplacer la tâche, Repousser l'échéance, Documents, Supprimer). Écritures ciblées `patchActionOf` /
`patchTaskFields`, structure par `saveProjectTasks`.
**Gantt projet** (refonte 2026-10, handoff `docs/specs/gantt-projet-2026-10/README.md`, 4 lots) : `gantt_screen.dart`
n'a plus d'AppBar ni de Scaffold (un seul en-tête = celui de la fiche), couleurs `kB*` ; axe de temps en logique
pure `lib/utils/gantt_axis.dart` (`GanttAxis` : plage lundi−7 j → +14 j couvrant toutes les tâches, `x(date)`,
mois, semaines calées sur les lundis, zoom 0,2–3) ; défilement à deux `ScrollController` (molette = défilement,
Ctrl/⌘ + molette ou pincement = zoom autour du curseur), en-têtes et colonne des libellés figés par overlays,
boutons Aujourd'hui / Ajuster au projet ; barres manipulables (glisser = dates, bord droit = échéance,
annulation) ; sections par phase repliables via `phaseSections()` (`utils/project_health.dart`) ; points des
blocs du programme via `FirestoreSync.fetchDailySchedulesRange`. Ne pas réintroduire `InteractiveViewer` ni
de thème clair.
Actions (lot 6) = `views/actions_view.dart` + `lib/utils/actions_logic.dart` (filtres Je suis / J'ai /
Domaine persistés en SharedPreferences, groupes par projet, Possible maintenant) ; CRUD des actions dans
`web/action_dialogs.dart`. `ActionsHubView` et `WebActionsView` ont été supprimés.
⚠️ Clé des docs `daily_schedules` = `ymdOf(d)` (`YYYY-MM-DD`, `utils/engagement_stats.dart`) — PAS
`yyyymmdd(d)` (`YYYYMMDD`, réservé à `habitProgress`).
Modèle (lot 0) : `ProjectTask.estimatedMin` / `TaskAction.estimatedMin` (null = 45 min / passe les
filtres) et `data/meta.weekCapacityMin` (`lib/utils/week_capacity.dart`). **Journée active** (2026-10) :
`data/meta.dayWindow {startMin, endMin}` (`DayWindow`, défaut 8 h → 22 h, réglable dans le dialog Capacité de
Cette semaine) ; seule la part des blocs dans cette fenêtre compte pour la charge, « journée bloquée » (≥ 6 h) et
les créneaux proposés (`activeMin`, `week_planner.dart`) ; `plan_day` (serveur) y prend ses heures par défaut.

**Règles de décision** :
- Privilégier ce qui renforce la boucle coaché → données d'exécution → coach.
- Zéro double saisie : toute donnée montrée au coach vient de l'usage normal de l'app.
- Partage coach-coaché : consentement explicite, granulaire, révocable (RGPD par conception).
- Interface 100 % français ; cible particuliers + entrepreneurs/indépendants francophones.
- Pricing cible : app 9,90 €/mois ou 79 €/an · app+coach 49-69 €/mois · licence coach 29-39 €/mois.

---

## Workflow PR (important)

L'utilisateur **merge chaque PR dès qu'elle est créée**, pour la tester aussitôt
(prototypes via routes cachées `?proto=…`). Conséquences pour Claude :

- **Toujours `git fetch origin main` puis brancher depuis `origin/main` à jour**
  juste avant de créer une PR (le main a souvent bougé entre deux PR).
- **Une PR = une seule fonctionnalité**, et ne committer **que les fichiers
  réellement modifiés** pour elle — ne jamais embarquer une version périmée d'un
  fichier déjà modifié par une autre PR mergée (sinon on l'annule).
- Si des commits sont poussés **après** que la PR a été mergée, ils deviennent
  orphelins : refaire une **PR propre** depuis `origin/main` (n'inclure que les
  fichiers voulus).

---

## Stack

- **Flutter** `>=3.0`, Dart `>=3.0`
- **Firebase** : Auth (Apple Sign-In + anonyme), Firestore, Cloud Functions (Node 22, 2nd Gen — Node 20 décommissionné le 2026-10-30)
- **State management** : `AppLogic` (ChangeNotifier) + `FirestoreSync` pour la persistance
- **Plateforme web** : compilée séparément (`lib/web/`), hébergée sur Firebase Hosting
- **MCP** : serveur remote (Cloud Function) + serveur local stdio (`mcp-server/index.js`)

---

## Structure `lib/`

```
lib/
├── models.dart          — tous les modèles de données (AppState, Activity…)
├── app_logic.dart       — logique métier centrale (ChangeNotifier)
├── firestore_sync.dart  — lecture/écriture Firestore, merge par ID
├── main.dart            — entrée app mobile/desktop
├── storage.dart         — persistance locale JSON (SharedPreferences)
├── notifications.dart   — notifications locales
├── pro_manager.dart     — gestion abonnement RevenueCat
├── web/                 — app web autonome (refonte 2026-09, thème vert sombre)
│   ├── web_home_screen.dart — shell : barre d'onglets (WebTab) + IndexedStack des vues + fiche projet hébergée
│   ├── web_shell.dart / theme_tokens.dart — barre du haut, menu ⋯, tokens kB*
│   ├── views/           — une vue par fichier : today, week, projects, project_plan, project_checklists,
│   │                      actions, library (documents + archives), orion
│   ├── gantt_screen.dart — onglet Vision (Gantt) de la fiche projet (Réalisation = views/project_checklists_view.dart)
│   ├── *_dialog.dart, tokens_panel.dart, vision_dialog.dart — dialogs partagés
│   └── …
└── widgets/             — sheets, tiles, vues partagées mobile
    ├── daily_schedule_view.dart  — timeline programme horaire (onglet Maintenant)
    └── …
```

---

## Modèles clés (`models.dart`)

| Classe | Collection Firestore | Notes |
|--------|----------------------|-------|
| `Domain` | `domains` | Domaine de vie (Santé, Travail…) |
| `Activity` | `activities` | Tracking temps (`type: time`) ou fréquence (`type: habit`) ; `ownActions: TaskAction[]` = actions propres (sans tâche/projet), chrono ciblé via `Session.actionId` |
| `TaskAction.checklist` | (embarqué) | Micro-actions `ChecklistItem[] {id,title,done,doneAt}` (3ᵉ niveau projet → tâche → action → item), cochées pendant un bloc du programme. **Règle : dernier item coché = action faite ; décocher rouvre** (UI web + `mark_checklist_item`). Vide = pas de checklist. |
| `DayBlock` | `blocks` | Blocs de journée (Matin, Midi, Soir…) |
| `Session` | `sessions` | Session de temps loggué |
| `HabitHit` | `habitHits` | Incrément de routine |
| `Project` | `projects` | Projet Gantt (phases + tasks embarquées) ; `parentProjectId?` = hiérarchie (null = racine, adjacency list, arbre reconstruit côté client) |
| `StrategicObjective` | `strategic_objectives` | Objectif lié à un projet Gantt |
| `Document` | `documents` | Programmes HTML, briefs, livrables |
| `ApiToken` | `api_tokens` | Tokens Bearer pour le MCP |
| `AssistantMessage` | `assistant_messages` | Messages planifiés de l'assistant IA |
| `ScheduleBlock` + `DailySchedule` | `daily_schedules` | Programme horaire journalier (voir ci-dessous) |

Structure Firestore : `users/{uid}/{collection}/{id}` — toujours.
Exception `daily_schedules` : doc unique par jour — `users/{uid}/daily_schedules/{YYYY-MM-DD}`.

> **`DayPlanItem` supprimé** — le modèle Flutter, toute la logique associée, ET les anciens outils MCP
> `get_day_plan` / `add_to_day_plan` / `clear_day_plan` / `delete_action` ont été
> **entièrement retirés** (Cloud Functions + orion.ts). La collection Firestore `dayPlan` existe
> encore en base mais n'est plus lue ni écrite. Ne pas recréer de logique autour de `DayPlanItem`.
> Le scheduling est désormais géré par `DailySchedule` + les outils MCP `schedule_day` / `plan_day`.
> ⚠️ Le nouvel outil `plan_day` (agrégateur de contexte) est **sans rapport** avec l'ancien `plan_day` supprimé.

---

## Programme horaire (`DailySchedule`)

Un doc par jour : `users/{uid}/daily_schedules/{YYYY-MM-DD}`

```
DailySchedule {
  date: "YYYY-MM-DD",
  generatedBy: "claude" | "orion",
  generatedAt: timestamp,
  blocks: ScheduleBlock[]
}

ScheduleBlock {
  id, startTime ("HH:mm"), durationMin,
  title, category ("project"|"routine"|"personal"|"break"),
  projectId?, taskId?, activityId?, actionId?,   ← liens vers les objets existants
  status: "pending" | "done" | "skipped" | "deleted",
  doneAt?
}
```

`actionId?` = action ciblée par le bloc (action PROPRE d'une activité avec son `activityId`, OU
sous-action d'une tâche avec `projectId`+`taskId`). Lancer le bloc (▶) démarre un chrono **ciblé**
(`logic.start(activityId, taskId:, actionId:)` → `Session.actionId`).

**Soft-delete des blocs** : swipe dans l'app → `status: "deleted"` (jamais retiré du tableau).
`get_day_schedule` affiche les blocs supprimés avec `❌ [supprimé — ne pas recréer]` pour que
Claude ne les recrée pas lors d'une régénération.
**Sautés / déplacés hors de la vue** (B12, 2026-10) : le programme n'affiche que ce qui reste à faire ou ce qui a été
fait. Un bloc `skipped` (sauté, reporté, déplacé via `update_block {moveTo}`, non relisté par un `schedule_day` de
remplacement → trace `skipReason:"replanifie"`) sort de la vue, mobile et web, et ne laisse qu'un compteur discret
« 2 blocs déplacés · 1 sauté » (pied de liste mobile, en-tête de la carte web ; tap = liste : heure prévue, titre,
destination ou cause — `asideBlocks` / `asideLabel` / `asideDetail`, `utils/today_logic.dart`). Déplacé = `movedTo
{date, startTime, blockId}` sur l'origine (ou `skipReason:"reporte"`). Ces traces n'ont qu'un usage : check-in du soir
(« ↪ DÉPLACÉ → … » / « ❌ SAUTÉ (cause) ») et `estimate_accuracy`. Un miroir 📅 agenda ne se saute ni ne se déplace
depuis l'app (refusé par `update_block`) : il se déplace dans l'agenda.
**Annuler un bloc** (« pas disponible », 2026-10) : sans report ni déplacement — mobile : appui long → « Annuler le
bloc » ; web : « Pas disponible » dans « Modifier le bloc ». `skipped` + `skipReason: kSkipUnavailable`
(`"indisponible"`, `FirestoreSync.setBlockCancelled`) ; compté à part (« 1 annulé », `asideBlocks().cancelled`) et
**rétablissable** depuis la liste « Hors du programme ». Jamais sur un miroir agenda (`canCancelBlock`).

**Outils MCP** :
- `get_day_schedule(date)` — lit le programme du jour
- `schedule_day(date, blocks[])` — crée ou remplace le programme (un bloc peut porter `actionId` → chrono ciblé). **Le vécu
  est immuable** (B10, 2026-10) : en mode remplacement, un bloc **fait**, un bloc sur lequel un **chrono réel** a tourné
  (`blockHasSession`, sessions du jour) et les tombstones (`skipped` / `deleted`) survivent (`isSettledBlock`,
  `schedule_dedupe.ts`) et un entrant qui les chevauche est écarté ; un bloc passé NON fait a sauté : non relisté, il est
  retiré. En mode `fill`, un entrant écarté dit **quel bloc occupe le créneau** (titre, heure, statut, id) et propose le
  prochain créneau libre **vers l'avant** à partir de max(maintenant, heure demandée) pour aujourd'hui, de l'heure demandée
  sinon, jamais depuis 00:00 (B11, `nextFreeSlot`) ; rien de libre ⇒ « aucun créneau de N min libre avant « Sommeil » 23:30 »
- `add_activity_action(activityId, title, context?, contexts?)` — crée une **action propre** (`Activity.ownActions`) sur une activité-temps, programmable ensuite via `schedule_day` (`activityId`+`actionId`)
- `mark_checklist_item(projectId, taskId, actionId, itemId, done)` — coche une micro-action ; `checklist` accepté sur les actions de `push_gantt` / `add_task` / `update_task` (string ou `{title, done?}`, ids préservés au re-push)
- `link_action_to_activity(projectId, taskId, actionId, activityId)` — associe une sous-action de tâche à une activité-temps (`TaskAction.linkedActivityId`) → chrono ciblé. L'IA le **propose** quand une action n'est pas déjà liée et qu'une activité-temps du même domaine existe
- `delete_task(projectId, taskId, force?)` — supprime UNE tâche (et ses actions) comme « Supprimer la tâche » de l'app ;
  libère les blocs À VENIR qui la visent (`deleted`), le vécu ne bouge pas ; tâche principale de séance refusée sans
  `force` (logique pure `functions/src/task_delete.ts`). Garder une trace = `update_task_status skipped`
- `update_action(activityId? | projectId+taskId, actionId, title?, contexts?, addContexts?, removeContexts?, estimatedMin?,
  clearEstimate?, linkedActivityId?, done?, delete?)` — retouche UNE action existante (propre d'une activité ou sous-action de
  projet) sans réécrire les autres ; `done:true` coche aussi la checklist. Logique pure `functions/src/action_patch.ts`.
  Préférer à `update_task` (qui remplace toutes les sous-actions) pour une modification ponctuelle
- `estimate_accuracy(days?, limit?)` — **estimé vs réel** : temps réel = sessions de chrono ciblées (`actionId`,
  tâches via `taskId`), facteur médian réel/estimé sur les actions terminées + par contexte / porteur, actions en cours
  au-delà de l'estimation, actions travaillées sans estimation. `plan_day` en inclut un résumé et demande d'estimer
  (avec ce facteur) puis de poser `estimatedMin` sur toute action programmée sans estimation. Logique pure
  `functions/src/estimates.ts` ; côté app `lib/utils/time_spent.dart` (« ⏱ … passées » : Actions mobile, Réalisation web).
  Handoff `docs/specs/estime-vs-reel-2026-10/README.md`
- `list_sessions(from, to?, activityId?, anomaliesOnly?)` / `delete_sessions(sessionIds)` / `update_session(sessionId, startAt?, endAt?, activityId?)`
  — audit des sessions de chrono (total compté vs temps réel sans chevauchement, doublons, chevauchements, sessions
  longues, chronos ouverts) et correction en **suppression douce** (`deleted:true` ; `update_session` = tombstone +
  nouvelle session). Logique pure `functions/src/sessions_audit.ts` ; toute lecture serveur de stats passe par
  `liveSessionDocs()`. Côté app, `FirestoreSync.mergeSessions` : un remote supprimé ou fermé gagne sur une copie
  locale ouverte (fin des chronos « ressuscités » → semaines > 168 h)
- `update_domain(domainId, name?, goalMinDay?, autoGoal?, colorValue?)` — retouche un domaine (renommage sûr : tout
  référence le domaine par id) ; la fiche intention / minimum vital reste dans `save_domain_definition`, qui ne renomme
  jamais. **Retouches unitaires** (2026-10) : `update_task {description}` (`""` = effacer), `update_project {phases:[{id,
  label?, color?, startDate?, endDate?}]}` (par id, jamais d'ajout / suppression : `push_gantt`), `update_project {linkedActivityId}` (activité-temps liée, `""` = délier), `update_block(date,
  blockId, title?, startTime?, durationMin?, category?, status?, skipReason?, delete?, projectId?, taskId?, activityId?,
  actionId?)` (`""` sur un lien = le retirer ; `status:"skipped"` + `skipReason` ou `delete:true` libèrent le créneau d'un
  bloc passé non fait ; `moveTo {date, startTime}` = déplacement ATOMIQUE (copie à destination, origine tracée
  `movedTo`, refusé si le créneau est occupé) ; le reste du programme est intact)
- `log_mood(kind: elan|effort|mood, value, moment?, blockId?, date?)` — **pointage d'état** (lot 2 badges, 2026-10) : élan avant
  (1 Flemme → 5 Lancé, un par créneau matin / aprem / soir du jour vécu), effort après un bloc (0 Facile · 1 Juste · 2 Dur),
  humeur du jour (0 Bas · 1 Neutre · 2 Bon) → `users/{uid}/mood_marks`, même donnée que l'app (`models/mood.dart`,
  `AppLogic.logMood`). Seulement quand l'utilisateur DIT son état. `get_user_context` (donc `plan_day`) porte un bloc
  `elan` : résumé 7 j (élan moyen, pointages, fenêtres de flemme gagnées, taux de discipline, efforts). Logique pure
  `functions/src/elan.ts` ↔ `lib/utils/elan_logic.dart` (**garder alignés**)
- **Historique des changements d'élan** (2026-10) : chaque changement de mode est un pointage ; un changement < 5 min
  après le précédent du même jour vécu le REMPLACE (`kElanCorrectionMin`, correction d'un clic ; `logMood` supprime le
  document remplacé via `deleteMoodMarks`). `dedupeMoodMarks` (`utils/elan_logic.dart` ↔ `functions/src/elan.ts`,
  **garder alignés**) applique la règle à la lecture (fusion, fenêtres, flux web) ; effort = un par (jour, bloc), humeur =
  un par jour. Moyennes **pondérées par le temps tenu** (`ElanMarkView.minutes`, `ElanDay.mean`, `elanMetrics.mean`,
  `elanSummary.mean`), « créneaux pointés » (`slots`, 3 par jour max) pour Baromètre et les en-têtes, bande horaire du
  jour calculée par quart d'heure (`elanTimeline`, `ElanDayStrip` dans la feuille du mode), valeur DOMINANTE par créneau
  (`todayElanSlots`, `changes`). Rien n'est échantillonné.
- **Voir son élan** (2026-10, maquette « Élan visible », `lib/utils/elan_view.dart`) : `todayElanSlots` (matin · aprem · soir :
  valeur, heure, choses faites dans la fenêtre), `hardestBucket`, `elanMonth` (30 derniers jours : moyenne, jours de flemme
  et gagnés, en forme, série de pointages, `previousMean` sur les 30 d'avant → `trendLabel`), `weeklyMeans`. UI = la
  **feuille du mode** (`showModeSheet(context, logic, badges:)`, `widgets/mode_sheet.dart`) : trois postures en tête, puis
  AUJOURD'HUI, CETTE SEMAINE (`ElanWeekGraph` : un point par pointage, anneau vert = fenêtre de flemme gagnée, trait de
  moyenne), FACE À LA FLEMME, 30 DERNIERS JOURS (`ElanMonthGrid`, tap = le jour) + 3 chiffres + TENDANCE, CE QUE ÇA VAUT
  (Marée haute, Vent contraire, Malgré tout, Baromètre). Programmes via `BadgeCenter.schedules` quand il est passé, sinon
  61 jours relus. **Pilule du mode** (`ModePill`, barre du haut mobile + carte MAINTENANT ; `WebModePill` web, visible
  dès qu'un pointage existe) = mode + traînée `ElanTrail` des trois créneaux du jour (`todayElanValues`). Stats : ligne
  « Élan · 2,9 / 5 » (`_elanRow`, mini-courbe 7 j, tap = feuille) ; la carte « Élan & discipline » n'est plus dans la
  fiche Ma semaine (elle reste sur le web).
- `list_badges()` / `hunt_badge(action: set|remove, badgeId, tier?, targetDate?)` — **badges et chasse** (lot B,
  2026-10) : le deck est calculé par l'APP (`lib/utils/badges_logic.dart`, `BadgeCenter`) qui dépose un instantané dans
  `users/{uid}/data/badges` à chaque recalcul ; le serveur ne recalcule rien (`functions/src/badges_mcp.ts`). Chasses dans
  `data/meta.badgeHunts` (3 max, palier restant, jamais posées sans accord explicite). `get_user_context` porte un bloc
  `badges` (compteur, dernier obtenu, chasses, paliers proches).
- **Ce qu'il manque aujourd'hui** (badges, 2026-10, `lib/utils/badge_today.dart`) : `badgeToday(badge, TodayFacts)` → `BadgeToday`
  (enjeu `TodayStake` en jeu / à portée / tenu / perdu aujourd'hui / rien, chip, jauges fait / suffisant, `GapItem`s = routines
  nommées non atteintes, blocs à faire, pointer l'élan, minutes du rythme, reprise d'Enchaîner, relevés dus, notes de marge).
  Faits du jour vécu composés par `BadgeCenter.todayFacts()` ; section AUJOURD'HUI de la fiche badge (`showBadgeSheet(facts:,
  actions: BadgeTodayActions)` : +1 routine, Pointer, Ouvrir le bloc). Les compteurs restent sur les jours clos (`scoreDays`
  jusqu'à hier vécu) : la journée en cours n'est montrée que « pour l'instant ». `badgesInPlay(deck, facts)` = suites en jeu.
  **Impact du jour sur la jauge** : `BadgeToday.gain` (+1 des journées solides, dont le compteur ne voit que les jours clos)
  → trait jaune « atteignable ce soir » sur la jauge du badge (`BadgeView(todayGain:, todaySecured:)`, `BadgePainter.tick` /
  `provisional`) et segment jaune jusqu'au trait quand la journée tient (`gainSecured`) ; `dayDone / dayTotal` = « faisable
  du jour » (mini-barre des lignes En jeu / À portée de la galerie).
- `manage_contexts(action: list|add|rename|delete, context?, newContext?, detach?)` — contextes GTD : `list` (défauts +
  personnalisés `data/meta.customContexts`, usage ouvertes/faites, orphelins), `add`, `rename` (propagé à toutes les
  actions des projets et des activités, fusion si le nom existe), `delete` (tag orphelin conservé sauf `detach:true`). Les
  6 défauts sont fixes ; « Je suis @… » (`nowContexts`) est local à l'app. Logique pure dans `functions/src/contexts.ts`
- `plan_day(date?, startHour?, endHour?, syncToCalendar?)` — agrège user context + schedule existant + projets actifs en un appel ; retourne le contexte consolidé + workflow pour générer le programme et le syncer dans Google Calendar
- `plan_week(startDate?, syncToCalendar?)` — idem sur 5 jours ouvrés (défaut : lundi prochain)
- `sync_calendar(date?)` — lit le programme existant et retourne les instructions GCal précises (delete + create_event avec colorId et tag `source: productivitwo`)

**Vue Flutter** : `lib/widgets/daily_schedule_view.dart` dans l'onglet Maintenant.
**Toucher un bloc de tâche** (mobile, 2026-10) : ouvre l'écran « bloc » (`widgets/block_work_screen.dart`, logique
`utils/block_work.dart`) — l'action visée (sinon la 1ʳᵉ ouverte) en avant avec ses étapes cochables, les autres actions
repliées, chrono, « Voir la tâche » (fiche), « Bloc terminé ». Bloc de séance (🎯 d'une intervention) → écran séance.
Routage dans `_openBlockSource` (`main.dart`).
**Retouches « action » mobile (2026-10, maquettes validées)** : écran bloc → bouton **« Étape suivante »** (coche l'étape
en cours de l'action en avant, « Ensuite : … ») ; arrêt d'un chrono sans tâche ni action (≥ 3 min, geste user :
`AppLogic.onUserStopped`, jamais au changement de chrono) → feuille **« Ces n min, c'était pour quoi ? »** avec les
actions probables de l'activité (`stopTargetCandidates` : programme du jour, puis échéance, jamais à venir) ; Actions
→ pastille **« NOUVEAU »** + groupe « Arrivées aujourd'hui » pour les tâches qui démarrent le jour même
(`startsToday`) ; programme du jour, à partir de 18 h et 2 blocs passés non faits (hors miroirs) → encart **« Caser
les n demain »** (`blocksToCarry` / `showCarryCard`, annulable via `undoReportToTomorrow`) ; **miroirs récurrents** :
`upsertScheduleBlock` d'un miroir avec activité sans tâche retient `data/meta.mirrorActivities {mirrorKey(titre):
activityId}`, appliqué EN MÉMOIRE aux miroirs libres au chargement (`applyMirrorMemory`, après `linkMirrorsToSessions`
— la séance prime).
**Mode « Enchaîner »** (mobile, 2026-10, lot 1 ; proposition validée : file jusqu'à la fin du programme, débordement
= on laisse tourner et on propose, routines par accroche au lot 2) : bouton « Enchaîner · n choses jusqu'à HH:MM » sur
la carte MAINTENANT → `widgets/chain_screen.dart`, plein écran, une seule chose à la fois. File = logique pure
`utils/chain.dart` (`buildChain` : blocs à faire dont la fin n'est pas passée, dans l'ordre ; bloc de tâche → action
visée puis autres actions ouvertes, une **étape de checklist par écran**, dernière étape = action faite ; bloc de routine
→ carte compteur − x / y + (plusieurs +1 possibles avant « suivante », sautée si la routine est atteinte) ; bloc de séance → « Ouvrir la séance » ; rendez-vous / bloc perso →
carte « Fait ») ; `orderChain` (« Plus tard » = fin de file, « Pas aujourd'hui » = écarté). Le **chrono suit** le bloc
affiché (`onLaunch` du bloc à l'entrée, arrêt à sa sortie) ; bloc épuisé → `updateBlockStatus done` + écran de
transition (« Commencer », « Attendre HH:MM » / « Souffler 5 min » → reprise auto, « Sortir ») ; bloc qui déborde →
bandeau « Décaler la suite de N min » (`overrunMin`, `shiftFollowing` : jamais un miroir agenda) / « Laisser » ; « Sortir »
ou file vide → récap (faits, chrono, reste à faire avec « Caser demain ») ; l'écran reste allumé (`wakelock_plus`). **Session reprenable** (2026-10, `utils/chain_session.dart` ↔ `chain_session_store.dart`, SharedPreferences `chain_pending`) : sortir de l'écran met la session EN ATTENTE (`PendingChain` : compteur, faits, reportés, écartés, blocs épuisés, id de la `ChainRun`) ; MAINTENANT affiche « Reprendre l'enchaînement · n faites » tant que la journée vécue est la même et l'inactivité < 45 min (`isLive`) ; à la reprise, les blocs passés faits et les routines atteintes pendant la pause entrent dans le compte (`resumedDoneAts`) ; la `ChainRun` est réécrite avec le même id (`recordChainRun` upsert). Fin réelle = « Terminer la session » dans le récap, file vide, 45 min ou bascule. **Badge Enchaîneur** : une session compte dès 3 choses faites, sortie ou pas (`chainRunCounts`, paliers 5 / 20 / 50 `kChainTiers`) ; « Plein jour » garde seul la file vidée du premier au dernier bloc ; le récap dit « Session comptée · n choses » / « Encore k … ».
Complément d'Aujourd'hui, pas un remplacement.
**Segment « Actions · Routines »** (mobile, 2026-10, handoff Claude Design « Segment Routines Aujourd'hui », lot 1 — ⚠️ la pilule a été RETIRÉE au lot 4 « une carte, une fiche » : Routines et Objectifs sont deux lignes EN PARALLÈLE sous le programme, dont la fiche héberge les vues décrites ici) :
pilule en tête d'Aujourd'hui (`_segmentBar`, persistée `today_view_segment_routines`). Actions = l'onglet tel quel, où
« Le meilleur à faire » est remplacé par la ligne courte « Routines · 5 / 18 · 3 à faire ce matin → » (`_routinesLine`,
`RoutineDay.shortLine`). Routines = `widgets/routines_day_view.dart` : carte « Routine du moment » (anneau x / y du moment,
+1, −1 si ≥ 1 occurrence, « Pas maintenant ▾ » → plus tard dans le moment / report à un moment plus tard / pas
aujourd'hui ; cible atteinte par le +1 de la carte = la routine **reste en carte** (`_held`, série « Pompes » cible 1 → « ✓ 7 / 1
aujourd'hui »), « Suivante » passe à la file ; les lignes affichent « 7/1 » dès qu'on dépasse la cible ; à côté de la pilule
chrono : ⏱ minuteur (`timerMin` réglé = décompte direct, sinon choix de durée mémorisé ; via `onStartTimed`, routine cochée à
la fin) et réglages = `showRoutineSheet`) puis « La journée par moments » (moment courant ouvert, « Toute la journée » toujours ouverte, lignes coche /
−1 / +1). Logique pure `utils/routine_moments.dart` : le **moment** d'une routine = son `timeContext` effectif
(`effTimeContextOf`, réglé ou deviné) ramené à six cases (`momentKeyOf` : repas → midi, journée → toute la journée, rien →
libre) ; `currentMoment` (creux → suivant) ; `buildRoutineDay` → `RoutineDay` (`queue` = restées des moments passés puis
moment courant, « Pas maintenant » en fin ; `countOf`, `leftoverCountOf`, `laterMoments`). État du jour : « Pas
maintenant » = `nowSkippedByYmd` (ordre = ordre du report), « Pas aujourd'hui » = `nowDoneByYmd`, report à un moment =
`AppState.routinePushedByYmd` (`"id:moment"`, `AppLogic.routinePushed` / `setRoutinePushed`) — synchronisé dans `data/meta` depuis le 2026-10-30 (`_mergePushedByYmd` : le local prime par routine ; avant, perdu à chaque relance) — le `timeContext` n'est
jamais modifié par ces gestes. Ordre manuel dans un moment = `Activity.routineOrder` (null = après, par nom). **Routine répartie** (2026-10-30) : `Activity.splitMoments` (≥ 2 moments horaires ; fiche routine, section unique **« Moments »** depuis le 2026-10-30 — fusion de « Contexte horaire » et « Répartir » : Auto · Matin · Midi · Après-midi · Soir (un = placée, `timeContext` ; plusieurs = répartie, `timeContext` = le premier ; non quotidienne = un seul) · Toute la journée · Libre ; logique pure `pickedMomentsOf` / `toggleMoment`, aperçu « Répartie : 1 ce midi · 1 ce soir ») partage la cible du jour (`momentShareOf` : cible ÷ moments, surplus aux premiers, moment sans part ignoré) ; la routine reste dans le premier moment dont la part cumulée n'est pas atteinte et qui n'est pas fini, puis passe d'elle-même au suivant (un moment fini laisse son reste au suivant) ; `RoutineSlot.share` → « 7 / 10 ce matin » sur la ligne et la carte ; un report manuel prime. Vide = comportement d'avant. MCP : `splitMoments` (clés ou matin / midi / après-midi / soir, [] = retirer) sur `update_activity` et `create_routine` ; `get_user_context` et la liste des routines de `plan_day` disent « répartie : 10 le matin · 10 le soir » (logique pure `functions/src/routine_split.ts` ↔ `routine_moments.dart`, **garder alignés**) ; Claude propose, applique sur demande ou accord (⚠️ `firebase deploy --only functions`).
**Objectif du moment** (mobile, 2026-10, segment Objectifs d'Aujourd'hui, `widgets/objectives_day_view.dart` `_momentCard`) : carte en tête du segment sur le modèle de MAINTENANT / « Routine du moment » — UN objectif, UN geste. Logique pure `rankObjectiveMoments` (`utils/objective_day.dart`) : d'abord l'objectif désigné par la journée (bloc en cours ou chrono qui tourne pour lui), sinon le plus en retard sur son rythme hebdo (`weekPercent`, anneau « n % du rythme ») parmi ceux qui ont encore du travail aujourd'hui, puis relevé dû, puis prochaine action ; `ObjectiveMove` = running (Arrêter) · block (lancer) · time (chrono de l'engagement le plus en retard) · routine (+1) · reading (Noter un relevé → fiche) · nextAction (ouvrir) · none ; « Reste aujourd'hui : 25 min de X · 1 routine · bloc à 14:00 » (`remaining`), bouton « Fiche » = `showObjectiveTrajectorySheet`, pilule « 1 / n · suivant › » fait tourner les objectifs. Les cartes par objectif restent en dessous. **Enchaîner un objectif** : bouton « Enchaîner · n choses pour cet objectif » sur la carte → `showChainScreen(objective:)` (même écran Enchaîner, file `buildObjectiveChain` dans `utils/chain.dart` : routines non atteintes, blocs du programme encore à faire qui servent l'objectif, engagements de temps en retard sur le rythme du jour (bloc fabriqué `~obj-time/…` de la durée restante, chrono dessus), puis LA prochaine action de chaque projet (`~obj-task/…`, étapes une à une) ; rien n'est ajouté en plus de ce qui est déjà posé en bloc ; pas de session Enchaîner enregistrée, pas de « Caser demain » sur les blocs fabriqués ; **le chrono ne se lance jamais tout seul sur un bloc fabriqué** — bouton « Lancer le chrono » (`_chronoButton`, `_enterBlock` pose `_paused`), et un chrono lancé pour lui s'arrête quand la file le quitte).
**« Une carte, une fiche »** (mobile, 2026-10, handoff `docs/specs/une-carte-une-fiche-2026-10/README.md`, 5 lots) : chaque onglet = la *carte du moment* en tête (`widgets/moment_card.dart`, `MomentCard` : étiquette, anneau, titre, ligne d'état, UN bouton plein + « Fiche »), des *lignes* identiques (`widgets/status_row.dart`, `StatusRow` : barre fait / attendu avec repère « attendu aujourd'hui », chip ou écart aux paliers `palier_colors.dart`) — depuis le 2026-10-30 la **chip d'état est EN LIGNE** en tête de la sous-ligne (`StateChip(compact: true)`), le titre a toute la largeur (2 lignes max) ; la colonne de droite ne sert plus qu'à `trailing` / `delta`, et une *fiche* au tap (`widgets/fiche.dart`, `showFiche` + `FicheHeader` / `FicheTitle` / `FicheStep` / `FicheActions`, sections CETTE SEMAINE → DEPUIS LE DÉBUT → RÉSULTAT / PROCHAINE ÉTAPE → gestes). **Lot 1 livré = Projets** : `goals_view.dart` réécrit — PROJET DU MOMENT (`rankProjectMoments`, `utils/project_moment.dart` : séance à 7 j la plus proche, sinon le plus en retard sur son plan `projectPlan` = tâches faites / attendues à ce jour), lignes par projet, sections repliées À venir / En pause / Terminés / En veille, fiche `widgets/project_fiche_sheet.dart` (`showProjectFiche` ; le plan détaillé reste `showProjectSheet`, appui long sur la ligne). Le radar `week_radar_card.dart` n'est plus affiché sur mobile. **Lot 2 livré = Actions** (`actions_view.dart`) : carte ACTION DU MOMENT (`pickActionMoment`, `actions_logic.dart` : chrono en cours → bloc en cours → retard → programme du jour → prochain bloc → semaine → première ; geste = étape suivante / chrono / fait / arrêter), lignes `StatusRow` (barre des étapes, chip d'état, ▶), filtres repliés sous la capture (`_filtersToggle`), fiche d'action sur `showFiche` (ÉTAPES · DÉTAIL · ÉCHÉANCE · gestes). **Lot 3 livré = Stats** : `_buildDashboardBody` (main.dart) n'affiche plus que `widgets/week_stats_view.dart` (`WeekStatsView`) — carte MA SEMAINE (`weekSummary`, `utils/week_stats.dart` : engagements des objectifs, `engagedRoutineIds`, chrono de la semaine calendaire), lignes par domaine (`domainWeeks` : fait / minimum vital × jours écoulés, routines tenues ; tap = page du domaine), fiche « Ma semaine » qui reprend les anciennes cartes (jauges + courbe, Élan, temps, camembert, retards) via `weekDetails`. **Page domaine** (2026-10, `widgets/domain_page.dart`, `showDomainPage`, remplace les 1 300 lignes de `_showDomainDetail` ; `domain` null = toutes les activités / routines) : en-tête = ligne de Stats dépliée (minimum sur la fenêtre de budget, fait, attendu, routines tenues, `ExpectedBar`), segment Temps / Routines, carte ACTIVITÉ DU MOMENT (la plus en retard sur l'attendu, geste selon le mode : Chrono · « 10 min, malgré tout » · « Deep work 90 min » via `showDeepWorkSheet(preferActivityId:)`), lignes `StatusRow` (moyenne 7 j / objectif par jour, barre fait / attendu, chip %, ▶ dans l'icône, appui long = reporter à demain / mettre en pause / supprimer), sections À RATTRAPER (< 95 % de l'attendu) · AU RYTHME · EN PAUSE repliée ; routines : À FAIRE · ATTEINTES avec − / + et 🔥 série, tap = `showRoutineSheet`. « + Nouvelle activité / routine » dans le titre de section (plus de bouton flottant). Courbe 60 j et heatmap partent dans la fiche d'activité. Renvoie `true` quand un chrono est lancé (la racine passe sur Aujourd'hui). **Fiche activité** (2026-10, `widgets/activity_fiche_sheet.dart`, `showActivityFiche`, remplace `_openActivitySheet` de main.dart et le fichier mort `activity_detail_sheet.dart`) : en-tête `FicheHeader` (pastille domaine, chip au rythme / à surveiller / en retard / en pause / domaine en veille, ligne minimum · 7 jours · engagée dans « … »), UN geste selon le mode (Chrono + ⏱ durées 5 → 45 · « 10 min, malgré tout » · « Deep work 90 min » présélectionné · « Arrêter »), CETTE SEMAINE / SUR 14 JOURS (`ExpectedBar` + une barre par jour via `timeByDayForActivity`), ENGAGEMENTS (`CommitmentProgress` de l'activité par objectif, tap = fiche trajectoire), ACTIONS (propres ouvertes + actions de projet liées, cocher, ▶ chrono ciblé, « + ajouter », « lier » = `linkedActivityId` via `patchActionOf`, 3 dernières faites avec chip de mode), DÉROULÉS repliés (éditeur, ▶ `startTemplate`), RÉGLAGES repliés (domaine, cible quotidienne, minuteur par défaut, « Mettre en pause jusqu'à… » / Reprendre, Renommer, Supprimer). DERNIERS CHRONOS (3 dernières sessions, tap = `openEditSessionSheet`, fonction de main.dart partagée avec « Dernières 24 h » : début, fin, activité, bloc, suppression) et TENDANCE repliée (moyennes 7 / 30 j, `MiniAvgLineChart`, heatmap 12 semaines). Les trois PR (page domaine, fiche lot 1, fiche lot 2) sont livrées. **Lot 4 livré = Aujourd'hui** : plus de segment Actions · Routines · Objectifs dans `today_view.dart` ; section EN PARALLÈLE sous le programme (`_parallelSection`) = ligne Routines (`RoutineDay.countAll`, `shortLine`) et ligne Objectifs (`rankObjectiveMoments`, relevés dus), tap = fiche `showFiche` hébergeant `RoutinesDayView` / `ObjectivesDayView` (`_openRoutinesFiche`, `_openObjectivesFiche`) ; `ObjectiveReadingsCard` n'est plus en tête d'Aujourd'hui. L'écran bloc (`showBlockWorkScreen`) est devenu une feuille `showFiche` à `FicheHeader` (▶ chrono, chip en cours / à HH:MM / fait). **Lot 5 livré = Objectifs + harmonisation** : `widgets/objective_moment_card.dart` (`ObjectiveMomentCard`, carte OBJECTIF DU MOMENT sur `MomentCard`, partagée par l'onglet Objectifs et la fiche Objectifs d'Aujourd'hui) ; `objectives_card.dart` = carte du moment + lignes `StatusRow` (temps investi avec repère) + « ARCHIVÉS · n » repliée avec Réactiver ; confirmation sur Archiver (fiche trajectoire) ; `ObjectiveReadingsCard` n'est plus affichée ; la carte Routine du moment est sur `MomentCard` (slots `detail` / `actions`). **Les 5 lots sont livrés.**
**Mur des projets** (2026-10, maquette validée « Mur des projets », largeur des briques ÉGALE, le plan d'action à part est
remplacé par le projet déplié sur place au lot 2) : UNE brique répétée à trois profondeurs — projet = rangée de briques (une par
tâche, remplie par ses actions), tâche = rangée (une par action, remplie par ses étapes), action = points (un par étape). Logique
pure `utils/progress_bricks.dart` (`BrickState` done · started · late · running · todo · upcoming, `projectBricks` / `taskBricks`
→ `BrickRow` avec `expected` = trait « attendu aujourd'hui », `taskFill` / `actionFill`, `runningTargets`, `wallDigest`,
`behindLabel`) ; widgets `widgets/progress_bricks.dart` (`ProgressBricks` painter, tap sur une brique = index ; `StepDots`).
**Lot 1 livré** : onglet Projets mobile (`goals_view.dart`) = trois chiffres (`_digest` — retirés le 2026-10-30 à la demande
de l'user ; `wallDigest` reste en logique pure), carte du moment avec la rangée en détail, lignes `_wallRow` (nom · k / n · écart au plan, briques, prochaine action ; tap brique = fiche de la tâche) — projet dans un
dossier (2026-10-30) : « 📁 Chérubins › » en petit sur la ligne du compteur, le nom du projet seul dessous, pleine largeur.
**Lot 2 livré** : le **projet déplié sur place** remplace le plan d'action — `showProjectSheet` (`project_sheet.dart`, appui long
sur une ligne de Projets, « Déplier le projet » dans la fiche projet) garde l'en-tête éditable (titre, domaine, dates, activité
liée, phases, ajouter tâche / phase, documents) mais sa rangée de briques tient lieu de barre (tap sur une brique = déplie cette
tâche) et chaque tâche est une `WallTask` (`widgets/wall_task.dart`) : titre · k / n · état + rangée des actions ; tap = ses
actions (points des étapes, chip, cocher = `setActionDone` + `patchActionOf`) ; tap sur une action à étapes = ses étapes
cochables (`setChecklistItem`), sans étape = fiche d'action ; ↗ / appui long = fiche de tâche ; l'ancien `_TaskTile` est retiré
(« Au programme » reste dans le ⋯ de la fiche de tâche).
**Lot 3 livré** : la rangée de briques de la TÂCHE (une par action, remplie par ses étapes) sous l'en-tête de la fiche de tâche
mobile ; sur le web, la colonne « avancement » du tableau Projets (`views/projects_view.dart`) est la rangée de briques du
projet (tap sur une brique = fiche projet sur cette tâche). **Les 3 lots sont livrés.**
**Viser une brique** (retour user 2026-10) : sous `kBrickMinTapWidth` (26 px) par brique, le tap ouvre le **sélecteur**
`showBrickPicker` (liste des briques avec carré d'état, titre, k / n, état, séparateur « attendu aujourd'hui ») ; appui long =
toujours le sélecteur ; aide « Touche une brique… » une fois dans Projets (`bricks_hint_seen`) et sous la rangée de la feuille projet.
**Tap = projet déplié** (retour user 2026-10) : dans Projets, le tap sur une ligne ouvre le projet déplié en **pleine page**
(`showProjectSheet`, `initialChildSize: 1.0`, tâches ET actions faites masquées par défaut — « Afficher les faites · n » / « n faites » les ramènent —, description derrière un bouton discret
« Détail ») ; l'appui long ouvre la fiche projet (`showProjectFiche`). `_ExpandableDescription` (« voir plus ») est retiré.
**Un seul niveau dans Projets** (retour user 2026-10, « perdu entre les niveaux ») : la carte PROJET DU MOMENT, ses briques, les
lignes et leurs briques mènent TOUS au projet déplié (`_openPlan(p, taskId:)`, la tâche visée dépliée) ; « Déplier » remplace
« Fiche » sur la carte ; ▶ lance le chrono si une activité est liée, sinon ouvre le projet déplié sur la tâche de la prochaine
action. La fiche projet ne s'ouvre plus que par appui long sur une ligne ; la fiche de tâche depuis le projet déplié (↗).
**Cartes du moment, grammaire de Projets** (maquette validée « Cartes du moment », 2026-10) : chaque carte du moment suit les
cinq couches de PROJET DU MOMENT — étiquette + pilule · anneau + UNE ligne de contexte + titre · un **visuel** pleine largeur à la
place d'une sous-ligne dense (`MomentCard.visual` + `MomentLegend`) · UN bouton de deux ou trois mots sur toute la largeur · une
ligne de liens discrets (fiche · geste secondaire `chainLabel` · « ⋯ Autres » = feuille `showMomentActions` des gestes rares,
`MomentCard.moreActions` de `MomentAction`). Le bouton contour « Fiche » à côté du bouton plein n'existe plus. **Lot 1 livré** :
squelette + ACTION DU MOMENT (sous-ligne = échéance · estimation ; `StepDots` + légende « Étape en cours : … · ⏱ · @contextes » ;
« Étape faite » ; Autres = Chrono · Fait · Caser · Ouvrir le projet). **Lot 2 livré** : ROUTINE DU MOMENT (`routines_day_view.dart`) — un point par routine du moment (atteinte pleine, en avant cerclée),
légende « Les routines ce matin · X en cours · n restent », sous-ligne « 0 / 1 aujourd'hui · ensuite Y », bouton « +1 » (« Suivante »
quand la cible vient d'être atteinte), lien « Enchaîner · n », Autres = −1 · Chrono · Minuteur · Plus tard / moments suivants · Pas
aujourd'hui · Réglages ; la pilule chrono n'apparaît que si un chrono tourne. **Lot 3 livré** : OBJECTIF DU MOMENT (`objective_moment_card.dart`) — les morceaux du jour en briques violettes (`_pieces` : temps
engagés fait / attendu, routines compte / cible, blocs, relevé dû ; `ProgressBricks(accent:)`), légende « Aujourd'hui : … », sous-ligne =
état du rythme · relevé dû, boutons courts (Arrêter · Lancer · HH:MM · Chrono · n min · +1 · X · Noter un relevé · Ouvrir l'action),
lien « Enchaîner · n », Autres = Bloc de 90 min · relevé · chronos des autres temps · +1 des autres routines · prochaines actions.
**Lot 4 livré** : MA SEMAINE (`week_stats_view.dart`) — titre = « k / n au rythme », sous-ligne « attendu à ce jour · chrono · mode »,
sept barres par jour (`WeekSummary.dayHits`, `weekDayHits` dans `utils/week_stats.dart` : occurrences des routines engagées, jour courant
cerclé), légende « à rattraper : n », bouton « Détail », lien « Élan · 2,9 / 5 » (feuille du mode ; la section « ÉLAN · CETTE SEMAINE »
et `_elanRow` sont retirées), Autres = Mode du jour · Gérer les domaines. **Lot 5 livré** : MAINTENANT (`now_card.dart`, carte sur mesure) — titre = l'ACTION du bloc quand il en vise une (`blockWork`), contexte
« Projet › Tâche », sous-ligne « étape : … » ou « bloc 14:00 → 15:00 » ; visuel `_dayStrip` = la journée en blocs (largeur = durée, faits
pleins, bloc en avant marqué d'un trait, légende « le 3ᵉ est en avant · 3 après · jusqu'à 18:00 ») ; bouton principal inchangé (Lancer /
Commencer / « 10 min, malgré tout » en Flemme / Terminer + Pause / Arrêter / Bloc ▾) ; lien « Enchaîner · n » / « n petites choses » /
« Reprendre · k faites » (`_chainLink`) ; « ⋯ Autres » = Lancer sans minuteur ou 10 min malgré tout, Fait, Deep work 90 min, Enchaîner
tout, Voir la source ; « Ton élan, là ? » passe sous les liens. **Les 5 lots sont livrés.**
**« Titre d'abord »** (maquette validée 2026-10-30, `MomentCard`, TOUTES les cartes du moment) : le titre prend toute la largeur
(21 px, 18 au-delà de 60 car.), UNE ligne de contexte dessous = `context_` · `sub` (3 lignes max, jamais d'ellipse du titre),
puis l'anneau en MINIATURE (`MomentRing(size: 30, stroke: 5)`, sans texte dedans) avec « ringBig ringSmall » en minuscules à côté,
puis le `visual` et la légende. Plus de gros anneau à gauche. ACTION DU MOMENT : `sub` = ☀ visée · estimation · contextes
(l'échéance n'apparaît qu'une fois, dans la pilule), légende de progression = étape en cours · ⏱ passé. MAINTENANT
(`now_card.dart`, carte sur mesure) n'est pas concernée.
**Gestes rares en icônes** (2026-10-30) : « ⋯ Autres » est remplacé par `MomentActionIcons` (`moment_card.dart`) — ronds de
`kMomentIconBtn` (42 px) aux icônes DISTINCTES (infobulle = libellé · indice), **sur la même ligne** que la fiche et le geste
secondaire : un `LayoutBuilder` garde ≥ 120 px au geste secondaire (≥ 150 px au lien « Enchaîner » de MAINTENANT) et met autant
de ronds que la largeur permet (`maxInline`, 5 au plus, « ⋯ » compris) ; le reste derrière « ⋯ » → `showMomentActions`. Toutes les cartes du moment et MAINTENANT (`now_card.dart`). **Bouton fiche en icône** (2026-10-30) : `MomentCard.ficheIcon` → bouton rond 52 px (icône seule, `ficheLabel` en infobulle) ; « Détail » = `Icons.description_outlined` sur Action, Objectif, Bloc et Projet (Projet : icône = fiche, bouton « Projet » = projet déplié).
**« Une liste, un seul bloc ouvert »** (maquette validée 2026-10-29, `widgets/moment_item.dart`) : la ligne et la carte du moment
sont deux états du MÊME item (`MomentItem(open, collapsed, expanded, onToggle, onLongPress)`), un seul ouvert par page
(`OpenItem` : le premier du classement par défaut tant que rien n'est touché, puis le choix de l'utilisateur, y compris aucun ;
retoucher le bloc ouvert le referme ; `settle` recale le défilement pour que la ligne touchée ne bouge pas). Trois gestes partout :
**tap = explorer** (ouvrir sur place, rien ne part), **bouton plein = lancer**, **lien = feuille**. Plus de carte du moment à part ni de
doublon dans la liste. **Lot 1 livré = Projets** (`goals_view.dart`) : `_item` = `_wallRow` repliée / `_momentCard` ouverte (étiquette
PROJET DU MOMENT · PROJET · PROJET À VENIR, pilule séance ou écart au plan, liens « Projet » = projet déplié · « Détail » = fiche), appui long = fiche ; la ligne repliée est UN seul geste (ses briques ne sont plus tappables, elles le restent dans le bloc ouvert) ; la pilule
« 1 / n · suivant » disparaît. `MomentCard.chainIcon` (null = lien texte seul). **Lot 2 livré = Actions** (`actions_view.dart`) : plus de carte ACTION DU MOMENT en tête ; `_pickMoment` désigne l'action du moment
(item ouvert par défaut), chaque `_entryTile` = `MomentItem` (ligne `StatusRow` repliée sans ▶ ni chevron, bloc `_momentCardFor`
ouvert : étiquette ACTION DU MOMENT · ACTION EN RETARD · ACTION, pilule d'état, liens « Détail » = feuille d'action · « Projet » =
projet déplié sur la tâche) ; glisser droite / gauche et la coche restent sur la ligne ; appui long = feuille d'action. **Lot 3 livré = Objectifs + Routines** : `rankedObjectiveMoments(logic, objectives)` partagé ; `ObjectiveMomentCard(objectiveId:)` =
bloc ouvert d'UN objectif (étiquette OBJECTIF DU MOMENT / COUP EN COURS si premier, sinon OBJECTIF / COUP, pilule « n % du rythme »,
lien « Détail ») ; `objectives_card.dart` : plus de carte en tête, chaque `_row` = `MomentItem` (appui long = éditer). Routines
(`routines_day_view.dart`) : plus de carte en tête, chaque ligne des sections par moment = `MomentItem` (clé `moment/id`, padding
zéro), bloc ouvert = `_momentCard(pal, day, slot)` (étiquette ROUTINE DU MOMENT si c'est la routine en avant, sinon ROUTINE CE
MATIN…), défaut = la routine en avant de la file ; le nom de la ligne n'ouvre plus la fiche (appui long). **Bloc ouvert = la routine seule** (retour user 2026-10-30, plus de doublon avec l'en-tête de section) : étiquette ROUTINE DU MOMENT / ROUTINE, pilule « atteinte » seulement, anneau = SA progression (part du moment si répartie, sinon jour ou 7 j), contexte domaine · « restée ce matin », plus de pilule du moment, plus de points des routines du moment ni de légende ; l'en-tête de section porte le moment, sa fenêtre (tap = `showMomentsEditor`) et son compte ; « Enchaîner les n routines … » est sur sa propre ligne sous l'en-tête du moment courant (dans l'en-tête, il écrasait la fenêtre). **Reporter à un moment** (« Reporter à ce soir », flèche des gestes rares) demande confirmation puis propose « Annuler » ; une routine reportée a « Annuler le report » dans ses gestes et « reportée · revenir cet après-midi » touchable sur sa ligne (`AppLogic.clearRoutinePushed` : le report annulé reste en base sous `id:-` = `kPushCleared`, sinon la fusion « local prime par routine » le ressusciterait ; `routinePushed` l'ignore). `OpenItem.settle(id, apply,
{scroll})` : sans contrôleur, recale le `Scrollable` englobant. **Lot 4 livré = Aujourd'hui** (`daily_schedule_view.dart`, mode liste) : MAINTENANT reste la ligne ouverte par défaut en tête ; chaque
bloc du programme (hors blocs `session` d'onboarding et prépa) est un `MomentItem` : ligne `_blockLine` repliée (inchangée) / carte
`_blockCard` ouverte (étiquette BLOC · BLOC EN COURS · BLOC FAIT, pilule « à HH:MM » / « en cours · reste n min » / « fait », anneau
durée, « Projet › Tâche », l'action visée et ses étapes, bouton Lancer / Commencer / Fait / Rouvrir, lien « Détail » = fiche de la
source ou feuille du bloc, Autres = Fait · Modifier · Ajuster · Pas disponible · Supprimer) ; aucun bloc ouvert par défaut ; appui
long = ajuster ; glisser gauche = supprimer. La frise (mode timeline) est inchangée. **Les 4 lots sont livrés.**
**Page focus** (maquette validée « Page focus », 2026-10, `widgets/action_focus_screen.dart`, `showActionFocusScreen(logic, action,
project?, task?, ownerActivity?, chronoActivity?)`) : ▶ sur une action ouvre un écran plein (pas un onglet) en trois états — AVANT
(contexte en entier, titre, « ≈ est · déjà passées · k / n étapes », anneau étapes ou temps / estimation, étapes `StepsSection`,
note, bouton « Lancer le chrono » si une activité de chrono existe sinon « Étape faite » / « Action faite », lien « Durée · Deep
work 90 min » = feuille 25 / estimation / 90 → `deepWorkBlock` posé dans le programme du jour puis chrono) ; PENDANT (anneau =
chrono sur l'estimation, étape en cours en avant, `StepDots`, « Ensuite : … », bouton « Étape faite » / « Action faite », liens
Pause · Action faite · Terminer ; écran allumé) ; APRÈS (trace : ce chrono, total sur estimé, étapes ; « La tâche avance » = barre
actions faites + reste ; « C'était comment ? » = `logMood(kMoodEffort)` ; « Enchaîner · action suivante » rouvre la page dessus).
Chrono ciblé `logic.start(activityId, taskId:, actionId:)`, écriture `patchActionOf` / `updateOwnActions`, rien de nouveau en
base. **Grammaire de l'écran séance** (retour user 2026-10-30) : en-tête ✕ + titre + « bloc X · Projet › Tâche » (⏱ en action
quand le chrono peut partir), bandeau « Étape k / n » + temps (≈ estimé · déjà passé, chrono en cours, ou reste du bloc) + barre des étapes
(barre fine du chrono par-dessus), l'étape en cours en GRAND (28 px) + « Ensuite : … », Précédente · Étape suivante / Action faite, la
liste complète des étapes (tap = cocher, ⋯ ou appui long = Renommer · Cocher · Monter · Descendre · Supprimer avec « Annuler », « Ajouter une étape »), DÉTAIL ; en bas : « Lancer le chrono »
/ « Commencer · … » (bloc) puis « Pause » pendant, liens Durée · Deep work / Terminer le bloc / Terminer · bilan / Suivante ›. L'anneau
et `StepsSection` ne sont plus sur cette page. Entrées : ▶ de PROJET DU MOMENT (`_startNext`) et bouton « Focus » d'ACTION DU MOMENT (« Étape faite » / « Arrêter le chrono »
en lien, « Ouvrir le projet » dans les gestes rares ; « Chrono seul » RETIRÉ le 2026-10-30 — sur la carte, le chrono part toujours
de la page focus). ⚠️ `widgets/focus_screen.dart` (écran focus de session, Aujourd'hui)
est un autre fichier.
**Actions = l'essentiel** (décision user 2026-10-29 : « trop de blocs, doublons projets / actions ») : par défaut l'onglet Actions
ne montre que ce qui est à portée de main — actions libres (sans projet), UNE action par projet (`nextAction`, déjà sa plus en
retard) et celles au programme du jour (plus « toutes les en retard » depuis le 2026-10-30 : les autres retards d'un projet
attendent leur tour) ; en vue par urgence, plus de section « Plus tard · par projet » (2026-10-30) : les actions restantes sont des
cartes simples sous « ENSUITE » (« Projet › Tâche » sur chacune), sans en-tête de projet ni « Définir la prochaine action » (vue
par projet et onglet Projets seulement) ; plus de bascule « Tout » depuis le 2026-10-30
(décision user : l'onglet ne montre QUE l'essentiel). Le reste d'un projet se lit dans Projets. Suite prévue (maquette à valider) : Aujourd'hui = blocs
d'ACTIVITÉ et de temps, la page focus lancée depuis un bloc d'activité enchaîne la prochaine action de chaque projet lié ;
`plan_day` posera des blocs d'activité, pas un bloc par action.
**Jour visé** (décision user 2026-10-30, lot 1 livré = modèle + MCP + logique pure + migration) : `TaskAction.focusDate` (jour,
`YYYY-MM-DD` en base) = une INTENTION — « je veux l'avoir sous la main ce jour-là » — jamais une échéance (jamais en retard),
jamais un bloc. C'est la **date par défaut d'une action** ; `dueDate` ne sert qu'aux vraies dates butoirs (séance, rendu,
démarche). Logique pure `utils/actions_logic.dart` : `focusDateOf`, `isFocusedOn(a, day)`, `isStaleFocus` (visée passée, non
faite = « à re-viser », pas rouge), `workDate(a, t)` = jour visé sinon échéance effective (c'est elle qui ORDONNE : `nextAction`,
file d'un bloc, groupes), `focusLabel` (« visée aujourd'hui / demain / hier / il y a n j / 3 nov. ») ; `isOverdueAction` ne
regarde que l'échéance. File d'un bloc (`block_queue.dart`) : visées aujourd'hui (ou avant) EN TÊTE, puis retards, puis par
date de travail (`QueueItem.focus` / `focusedToday` / `work`). Actions mobile : l'essentiel inclut les visées aujourd'hui et
les à re-viser. MCP : `focusDate` sur les objets action de `push_gantt` / `add_task` / `update_task` (préservé au re-push) et
`add_activity_action`, `update_action {focusDate | clearFocusDate}` (`action_patch.ts`), `DATING_RULES` dans `WRITING_RULES`
(`title_style.ts`) ; `plan_day` liste « ACTIONS VISÉES POUR CE JOUR » (`focusedActions`, `focus_dates.ts`) et dit de reporter
par `update_action {focusDate}`, jamais par un bloc ; **`migrate_focus_dates(projectId?, dryRun=true, includeActivities)`** =
`dueDate` → `focusDate` des actions ouvertes hors tâches de séance (`isInterventionTask`), actions propres comprises. **Lot 2 livré
(mobile)** : feuille partagée `widgets/focus_day_sheet.dart` (`pickFocusDay` → `FocusDay` / `FocusClear`, aujourd'hui · demain ·
lundi prochain (`nextMonday`) · date · retirer) ; Actions : sections « VISÉES AUJOURD'HUI » (après Au programme) et « À RE-VISER »
(ambre, jamais rouge), « ☀ visée … » dans la sous-ligne, « CETTE SEMAINE » sur la date de travail, **glisser gauche = « Viser
demain »** (`_focusTomorrow`, annulable — plus « Caser demain »), « Viser un jour » dans Autres et dans la feuille d'action
(section JOUR VISÉ + bouton) ; fiche d'action de la fiche de tâche : section JOUR VISÉ ; file d'un bloc : « ☀ visée … » sur
la ligne. **Lot 3 livré (web)** : dialog d'action (`web/action_dialogs.dart`) champ « Jour visé » (date · Aujourd'hui · Demain · retirer)
au-dessus de « Échéance propre · seulement une vraie date butoir » ; badge « ☀ visée … » sur la ligne d'Actions (ambre si à
re-viser). **Les 3 lots sont livrés** (⚠️ `firebase deploy --only functions` puis `migrate_focus_dates`).
**Blocs d'activité, lot 1 livré** (maquette validée 2026-10-29) : le ▶ d'un bloc d'ACTIVITÉ (activité-temps, sans
`actionId`, hors routine et séance) ouvre la page focus en mode « bloc » (`showBlockFocusScreen`, `BlockFocus`,
`action_focus_screen.dart`) : LA FILE DU BLOC = `blockQueue` (`utils/block_queue.dart` : une action par projet vivant lié à
l'activité — `linkedActivityId` du projet ou d'une action ouverte, `projectServesActivity` —, prochaine action par échéance
effective, en retard d'abord, puis datées, puis actions propres de l'activité ; tâches à venir, dossiers, projets en pause
exclus), tap = choisir, « Commencer · … » = chrono ciblé sur l'activité du bloc, « Suivante › » passe à la prochaine sans
sortir, « Enchaîner · … » après une action faite ; en-tête « bloc · reste n min » (`BlockFocus.remainingMin(now, dayStartMin:)`,
sur la journée vécue : un bloc de la nuit compte +24 h). **Changer d'action = sur place** (2026-10-30) : tap dans la file,
« Suivante » et « Enchaîner » changent `_index` de l'état (`_goTo` → `setState`), jamais de fermeture / réouverture de la page. File vide = chrono
seul comme avant. **Lot 2 livré** : « Terminer le bloc » (lien avant / après, bandeau « Le bloc est fini · le chrono
continue » pendant) → écran BLOC TERMINÉ (`_BlockEndScreen`, `blockOutcome` : temps tenu = sessions de l'activité tronquées
au créneau, actions de la file faites dans la fenêtre avec leurs minutes, étapes cochées, reste de la file — qui ne va nulle
part) ; le bloc passe `done` (`doneBy:"focus"`) dès qu'il a du temps ; « Caser un bloc … demain » = NOUVEAU bloc même
activité / heure / durée sans action (`carriedActivityBlock`, `carriedFromDate`). **Lot 3 livré** : « Nouveau bloc »
mobile ouvre sur des chips BLOC D'ACTIVITÉ (`_pickActivity` : titre = nom, `activityId` seul) ; serveur : `BLOCK_RULES`
(`block_style.ts`) et le workflow de `plan_day` disent « travail de fond = blocs d'activité, jamais un bloc par action,
bloc de tâche réservé au daté », et la liste des activités-temps porte la charge « n projets liés · k actions en retard »
(`activityLoad` / `activityLoadLabel`, pure) ; prompt de la routine auto aligné dans le handoff. **Les 3 lots sont livrés**
(⚠️ `firebase deploy --only functions` à faire).
**Aujourd'hui en enjeux** (maquette validée 2026-10-30, « Aujourd'hui en enjeux », 4 lots) : Aujourd'hui devient une interface de
décision — ce que la journée peut faire gagner ou perdre. **Une ligne = un GESTE** (+1 routine, chrono d'activité, bloc, action), avec
tout ce qu'il rapporte en étiquettes (série de badge, palier ce soir, chasse, objectif en retard sur le rythme, prépa de séance à 7 j,
action visée) ; un même geste n'apparaît qu'une fois (fusion par clé `routine:` / `activity:` / `block:` / `action:`) ; il n'existe pas
de ligne « badge » seule. **Lot 1 livré** : logique pure `utils/stakes.dart` (`buildStakeBoard(deck, facts, hunts, projects,
activities, dayStartMin)` → `StakeBoard {top, rest, won, lost}` ; `StakeGesture`, `StakeGain` (`StakeGainKind` seriesTonight ·
tierTonight · series · hunt · objective · session · focus · routine, poids, jauge), `Stake.score` = Σ poids + 5 par gain de plus −
coût / 6, tri « se perd ce soir » d'abord, coupe `kStakesTop` (5) avec plafond `kStakesFamilyCap` (2) par famille pour les gestes à un
seul gain, `kStakeRestFamilies` pour la ligne dépliée). Sources : `badgeToday` (séries en cours ou chassées, badges chassés), rythme des
`ObjectiveDay` (attendu à ce jour = hebdo × jour / 7), `nextInterventionOf` (prépa), `isFocusedOn` / `isStaleFocus`, routines du jour.
**Lot 2 livré** : `widgets/stakes_section.dart` dans `today_view.dart` (`_stakeBoard()`, calculé une fois par build depuis
`BadgeCenter.deck` + `todayFacts()`, rien sans deck ni sur Demain) — `StakeScoreboard` (sous le programme depuis le 2026-10-30 ; gagnés · en jeu · perdus,
barre « % de la journée passée » 8 h → 22 h, `dayElapsed`) et `StakesList` sous la zone coach : lignes EN JEU = `MomentItem` (titre ·
avancement, chips de gains colorées par nature, bouton +1 / Chrono / Lancer / Focus), ouvert = « CE QUE ÇA RAPPORTE » (une jauge
`StakeGauge` par gain, case de ce soir en clair) + gros bouton + « Tous les badges » ; « + n autres en jeu » replié par famille
(`kStakeRestFamilies`) ; GAGNÉ / PERDU en une ligne. Gestes : `_runStake` (`routinePlusWithUndo`, `logic.start`, `onNowLaunch`,
`showActionFocusScreen`). **Lot 3 livré** : « TON TABLEAU DE BORD » REMPLACE la section EN PARALLÈLE ; depuis le 2026-10-30 (retour user) il est EN TÊTE
d'Aujourd'hui, au-dessus de MAINTENANT ; le tableau du jour « Ta journée » / « Ce soir » est TOUT EN HAUT, sous l'en-tête, à la place de
l'ancienne carte « journée gagnée » (`_dayWinCard`, retirée le 2026-10-30 ; `adaptDayGoalOnOpen` tourne toujours) ; **les enjeux ne sont plus
sur la page** (2026-10-30) : tap sur « Ta journée » (ou sur « Ce soir », compact sur la page : `EveningLedgerCard(compact: true)`) =
feuille `_openStakesSheet` (tableau ou bilan complet du soir + `StakesList` ; un +1 garde la feuille ouverte, chrono / focus la ferment) ; le **programme du jour n'est plus sur la
page** (2026-10-30) : la tuile PROGRAMME (toujours présente, « Rien de prévu » sans bloc) et la jauge du bord gauche ouvrent la
feuille `_openProgramSheet` (`showFiche` + `_programSection` : en-tête, liste ou frise, bascule) ; « Demain » ferme la feuille et
montre le programme de demain sur la page. Le passage auto en « fait » des blocs de routine (`_maybeAutoWin`) ne tourne que feuille ouverte
(`_parallelSection(cs, stakes)` → `widgets/dashboard_tiles.dart` `DashboardTiles`, logique pure `utils/dashboard_tiles.dart`) : PROGRAMME
(`programTile` : bande des blocs, en cours / ensuite ; tap = remonte au programme), ROUTINES (`routinesTile`, tap = fiche Routines),
OBJECTIFS (`objectivesTile` : au rythme ≥ 85 %, relevés dus ; tap = fiche Objectifs), BADGES (`badgesTile` : palier ce soir, séries à
sauver, plus proche ; tap = feuille `BadgesInPlayScreen(sheetScroll:)` sur mobile (2026-10-30, comme les autres tuiles ; écran / dialog web) — SE PERD CE SOIR · PALIER CE SOIR · CHASSES · PROCHES, `badgesInPlay` —, bouton =
le geste, « Tous les badges » = galerie), ACTIONS (`actionsTile` : visées aujourd'hui ; tap mobile = feuille `_openFocusedActionsSheet` depuis le 2026-10-30 — « Ajouter une action visée » (`showNewFocusedAction`, `widgets/focused_action_create.dart` : titre + Libre = action propre d'une activité-temps, ou Projet › tâche / « Au fil de l'eau » via `showTaskPicker` ; créée avec `focusDate` = aujourd'hui), À FAIRE (tap = page focus, ⋯ ou appui long = Viser demain · Ne plus viser · Renommer · Supprimer avec confirmation) · FAITES · lien « Ouvrir l'onglet Actions » ; web = onglet Actions),
PROJETS (`projectsTile(sessions:, skipped:)` : depuis le 2026-10-30 le PROJET DU MOMENT, même classement que l'onglet Projets
(`rankProjectMoments`), raison en tête (séance + prépa, retard sur le plan, prochaine action), `DashTile.targetId` ; tap mobile =
la fiche du projet `showProjectFiche(onSkipToday:)` avec une section DÉCISIONS — Suivant (passé pour aujourd'hui, `project_tile_skipped`
= « ymd|ids » en SharedPreferences, jour vécu), Viser demain (prochaine action `focusDate` = demain + passé), Mettre en pause
(`paused`) ; à la fermeture la tuile se recalcule, le même projet reste s'il est toujours le plus pertinent ; depuis la tuile, `actionsOpenFocus: true` : tap sur une action
de CETTE SEMAINE = la page focus de l'action (`showActionFocusScreen`) ; DÉCISIONS AU-DESSUS de CETTE SEMAINE ; tap web = onglet Projets).
Dans toute fiche projet, le bouton principal porte le TITRE de la prochaine action et ouvre sa page focus (jamais de chrono lancé
d'ici : il se lance explicitement dans le focus), ligne « Prochaine action · Tâche · ouvre la page focus » dessous. **CRUD des actions dans la fiche projet** (2026-10-30) : CETTE SEMAINE liste toutes les actions échues à 7 j (plus de coupe à 6), « Toutes · + n » déplie les autres actions ouvertes, « Ajouter une action » (titre + tâche, défaut = celle de la prochaine action, sinon « Au fil de l'eau » ; estimation par défaut ; tâche choisie dans `showTaskPicker`, `widgets/task_picker_sheet.dart` : tâches ouvertes par phase, émoji en icône, k / n actions · échéance, tâche proposée en avant — même sélecteur pour « Rattacher à un projet » d'Actions) ; appui long sur une action = Renommer · Estimation · Note · Jour visé · Marquer faite (`confirmDone`) · Supprimer (confirmation) — une action par `patchActionOf`, ajout / suppression par `saveProjectTasks` ; `FicheStep.onLongPress`. **Lot 4 livré** :
bilan du soir (`utils/evening_ledger.dart`, `isEvening` = journée vécue ≥ 19 h) — `EveningLedgerCard` remplace le tableau du jour :
gagnés · encore · perdus, AVANCÉ AUJOURD'HUI (paliers obtenus aujourd'hui `tierDates`, séries tenues, actions faites par projet
`doneAt`, temps par activité avec l'objectif servi), LAISSÉ FILER (perdus, engagements de temps en retard sans rien aujourd'hui),
« Demain en jeu » + « Encore possible ce soir » ; la liste devient ENCORE POSSIBLE CE SOIR (`StakesList(evening: true)`, sans
gagné / perdu). **Les 4 lots sont livrés.**
**Web** (2026-10-30, `web/views/today_view.dart`) : même logique, rien de neuf en base — faits du jour composés par
`composeTodayFacts` (`utils/today_facts.dart`, partagé avec `BadgeCenter.todayFacts`), deck partagé avec la carte BADGES
(`WebDeckSource`, `web/badges_web.dart`), tableau recalculé au plus une fois par minute (`_board`, le ticker redessine chaque
seconde). « TON TABLEAU DE BORD » en rangée sous l'en-tête (`DashboardTiles(row: true)` dès 1064 px ; empilé sinon) : Programme =
recentre la frise, Routines / Objectifs = déplient leur module, Badges = dialog « Badges en jeu », Actions / Projets = onglets
(`onOpenActions`). Colonne MAINTENANT : tableau du jour (ou « Ce soir » après 19 h) en tête, puis MAINTENANT, puis la liste EN JEU,
puis « Au programme · concrètement ». Gestes `_runStake` : `_incRoutine`, `_startActivityChrono`, `_startChrono`, chrono sur l'action
(`_startActionChrono`, sinon fiche projet sur la tâche). Pas d'enjeux en disposition active ni en bande Focus.
**Braises** (maquette validée 2026-10-30, « Braises de rattrapage », recommandations retenues) : une **journée parfaite** forge une
braise (réserve `kEmberCap` = 3) ; une braise **rallume une série de routine cassée HIER**, à condition d'atteindre la routine AUJOURD'HUI
(sinon elle ne coûte rien) ; une série ne se rallume qu'une fois tous les 30 jours (`kRekindleCooldownDays`) ; le jour comblé compte pour
la SÉRIE seulement, jamais pour Journée parfaite / solide (donc jamais de braise qui se recharge elle-même) ; séries de routines seulement.
**Lot 1 livré (logique + données)** : logique pure `utils/embers.dart` (`EmberSpend {activityId, lostYmd, spentYmd}`, `emberLedger` rejoue
journées parfaites et rallumages → `EmberLedger {stock, pending, bridged, used, history, perfectYmds}`, `lostYesterday` → `LostSeries`
(rallumable / en attente / bloquée : déjà rallumée · braise déjà en attente · aucune braise), `withRekindle` / `withoutPending`). Stockage
`data/meta.emberSpends` (`FirestoreSync.setEmberSpends`, flux meta → `AppLogic.emberSpends`) ; la réserve n'est JAMAIS stockée.
`computeBadges(emberSpends:)` calcule les journées d'abord, puis le registre, puis les séries avec `bridged` (`routineSeries` /
`routineBadge(bridged:)`, case `TrackCell.bridged` couleur `kEmberColor`, fait « Jours rallumés ») ; `BadgeDeck.embers` ; `BadgeCenter`
pose `logic.embers` ; `AppLogic.bridgedOf`, `emberLedgerNow` (registre frais : un +1 rend effectif un rallumage en attente),
`lostSeriesYesterday`, `rekindle` / `cancelRekindle`. Séries comblées aussi dans la page domaine, la fiche routine (`RoutineTiersLine(bridged:)`),
les routines du jour et le web (`WebHuntStore.emberSpends` → `WebDeckSource.deck(emberSpends:)`). Coach : instantané `data/badges.embers
{stock, rekindled[{name, ymd, domainId}]}` (30 j), filtré par domaine partagé (`badgesForCoach`), résumé `badgesSummary.embers`, ligne
« Braises » du rapport de pré-séance (⚠️ `firebase deploy --only functions`). **Lot 2 livré (écrans, `widgets/embers_view.dart`)** :
`LostYesterdaySection` sous « Ta journée » (page : séries rallumables ou en attente seulement ; feuille des enjeux : toutes, indisponibles
comprises) — `LostSeriesRow` « Pompes · série de 4 j cassée » + « Rallumer · 🔥1 » / en attente « +1 » + ✕ annuler / « Indisponible » +
raison, puis `EmberDots` (réserve) ; `showRekindleSheet` (six derniers jours, hier en braise, Prix · Condition · Résultat · Trace, « Rallumer
avec une braise ») ; `_onEmbersChanged` recharge le deck. « Badges en jeu » (mobile et web) : `EmberLedgerPanel` en tête (réserve, 5
derniers événements). Bilan du soir : « Journée parfaite · une braise » (`isPerfectSoFar(TodayFacts)`, `buildEveningLedger(perfectToday:,
emberStock:)`). Tuile **RECUL** (2026-10-30, mobile, case libre à côté d'Actions, `DashboardTiles.review`) : « Bilan · cap », tap = choix Résumé du jour / Où on va (`_openReviewChoice`) ; les deux boutons du bas d'Aujourd'hui sont retirés. Tuile **JOURNÉE PARFAITE** (2026-10-30, à côté de Routines depuis le 2026-10-30 — Objectifs passe à côté de Badges —, mobile et web ; `perfectDayTile(facts, ledger)`, `utils/dashboard_tiles.dart`) : « Il manque n » (routines non atteintes + blocs à faire) / « Parfaite ✓ », une case par chose à tenir, badge « 🔥 k / 3 » ; tap mobile = feuille `_openPerfectDaySheet` (routines à atteindre = `RoutinesDayView(onlyMissing: true)`, la vue de la fiche Routines par moment filtrée sur les quotidiennes non atteintes ; blocs à faire = `DailyScheduleView(onlyToDo: true)`, la liste du programme sans les blocs faits ni miroirs ; braises `EmberDots` + `EmberLedgerPanel`), web = dialog « Badges en jeu ». La tuile Badges ne parle plus des braises. Pas de rallumage depuis le web (affichage seulement).
**Vision à terme (backlog, user 2026-10-29)** : la carte du moment de chaque onglet prend toute la page par défaut (l'essentiel
pour voir où on en est et agir), et ce qu'il y a autour se découvre de façon fluide ; pour l'instant on améliore l'existant.
**Journée vécue** (2026-10, `utils/lived_day.dart`) : la journée des ROUTINES bascule à `data/meta.dayStartMin` (défaut
5 h, réglable dans Paramètres « La journée commence à », 0 → 12 h ; `AppLogic.dayStartMin`, alimenté par
`FirestoreSync.streamDayStartMin`), pas à minuit : compte du jour (`routinesForToday`, `routineTodayCount`), moment courant
(`buildRoutineDay` → avant la bascule on est encore « ce soir »), clés d'état du jour (`AppLogic.livedYmdNow` pour « pas
maintenant » / « pas aujourd'hui » / reports), `incHabit` sur `livedDate`. **Compte du jour = les hits** (2026-10-30) : `incHabit(+n)` pose n hits (un par unité, plus un seul) ; le lanceur « Lancer une routine » (`_showRoutinesSheet`, main.dart) et le compteur `showHabitCountSheet` lisent `routineTodayCount` / les hits de la journée vécue et écrivent sur `logic.livedToday` — plus le compteur `habitProgress` du jour calendaire. `incHabitWithAssocEvent` pose aussi n hits. **Réconciliation** (`utils/habit_reconcile.dart`, `reconcileHabitStores`, à chaque fusion local + remote dans main.dart, avant le re-push) : compteur et hits alignés jour par jour sur le plus grand des deux (hits manquants à ids `recon-<habit>-<ymd>-<k>`, compteurs créés `recon-<habit>-<ymd>` : deux appareils ne doublent rien), idempotent. Web : « déjà atteinte ? » (Actions, +1 d'un bloc de routine d'Aujourd'hui, `WebDailyScheduleCard`) = `livedHitCount` (`utils/lived_day.dart`, hits de la journée vécue) — le web n'a pas les compteurs `habitProgress` en mémoire. Le programme du jour reste sur la date
calendaire côté STOCKAGE, mais le mobile le lit sur la journée vécue (lot 2, 2026-10) : `AppLogic.livedToday` /
`livedTodayYmd` (programme « d'aujourd'hui » = la veille jusqu'à la bascule : Aujourd'hui, Demain, Actions « au
programme », MAINTENANT, Enchaîner, écran bloc) et `livedNowMinNow` (00:30 → 24 h 30, pour que Sommeil 22:00 → 05:00
soit « en cours » : bloc courant, auto-coche, « Caser demain », trait « maintenant » — masqué dans la frise après
minuit). **La nuit appartient à la journée vécue** (2026-10-30, mobile) : le stockage reste par date calendaire, mais Aujourd'hui
(`daily_schedule_view.dart`, `today_view.dart`) lit DEUX docs — celui du jour vécu et celui du lendemain — et fusionne via
`mergeLivedDay` / `livedDayBlocks` (`utils/lived_day.dart`) : les blocs du lendemain qui commencent AVANT la bascule (la nuit
après minuit) entrent dans la journée vécue avec `ScheduleBlock.dayOffset = 1` et `docDate` (champs RUNTIME, jamais
sérialisés) ; `blockStartMin` ajoute +24 h, donc tri, bloc en cours, trait « maintenant », « Plus tôt » les placent après le
soir ; `startTime` reste « 00:20 » à l'affichage. Les blocs du doc du jour qui commencent avant la bascule appartiennent à la
nuit de la veille et ne sont pas montrés dans sa vue. Toute écriture sur un bloc passe par son doc (`_docOf(b)` =
`b.docDate ?? widget.date`, `_saveBlock` → `upsertScheduleBlock` sur `docDate`) ; un bloc CRÉÉ après minuit va sur le doc du
lendemain à l'heure de l'horloge (`docForNewBlock`). La frise (`day_timeline_view.dart`) reste sur le jour calendaire.
**Web** (2026-10) : le shell suit `data/meta.dayStartMin` (`streamMetaDoc`) et passe `dayStartMin` à Aujourd'hui
(date du flux, minute vécue, Demain, routines, cartes retard / échéances), Cette semaine, Projets et Actions ; les moments
réglés ne sont pas lus par le web (pas d'UI moments). **Moments réglables** : bornes dans `data/meta.momentWindows`
(`timedMomentsWith`, `parseMomentWindows`, `validateMoments` ; `AppLogic.moments` / `allMoments`, `RoutineDay.moments`) ;
sans réglage le **Soir court de 19 h au début de journée** (5 h) — la nuit appartient au soir. Éditeur
`widgets/moments_editor_sheet.dart` (pastille « Soir · 19 h → 5 h » de la carte du moment, Paramètres « Moments de la
journée »). Les contextes horaires des routines (`routine_context.dart`) suivent ces moments via
`AppLogic.timeContexts` (`timeContextsWith`, `effTimeContextOf(contexts:)`, `allows` gère une fenêtre qui passe minuit) :
coach « faisable maintenant » (`computeCoachMoment(timeContexts:)`) et heure proposée par la renégociation. La fiche
routine garde les libellés par défaut (choix du contexte).
**Enchaîner les routines** (lot 2, `widgets/routine_chain_screen.dart`, bouton de la carte du moment) : la file du moment
une routine par écran, compteur − x / y + sur place (`routinePlus` / `routineMinus` / `routineTodayCount`, partagés avec la
vue), « Suivante » selon le compteur (rien : inactif · partiel : « Garder 1 / 2 » · atteinte : « Cible atteinte »),
« Pas maintenant ▾ » (fin de file / report à un moment plus tard), « Pas aujourd'hui » ; progression = routines traitées /
total ; écran de fin « Matin terminé · n sur total » + gardées / reportées + « La suite : à 11 h 30 (midi) » ; écran
allumé. **Organiser** (lot 3, `widgets/routines_organize_screen.dart`, bouton de la vue) : par moment (6 sections, appui
long + glisser vers une autre section = change `timeContext`, ▲▼ = `routineOrder` renuméroté 0..n-1 dans le moment) ou par
domaine (chip du moment sur chaque ligne → rangée des 6 moments) ; écrit via `saveActivity`.
**Un seul Enchaîner** (2026-10) : `buildChain` accroche les routines à la file du programme (`anchorRoutines`, défaut true) —
en tête, la file du moment courant (restées + moment courant, ordre de la vue Routines) ; à l'entrée de chaque moment
suivant (premier bloc qui y commence), ses routines ; après chaque bloc de travail (tâche / action), UNE routine « toute la
journée » non atteinte, à tour de rôle. Portées par des blocs fabriqués (`~morning`, `~<blockId>`, `ChainItem.synthetic` :
ni transition ni écriture) ; une routine déjà posée en bloc n'est pas accrochée en plus ; même état du jour que la vue
Routines (`pushed` / `deferred` / `dismissed`, « Pas aujourd'hui » depuis la file écrit `nowDoneByYmd`).
Actions : tap checkbox → done, tap → éditer, swipe gauche → supprimer, long press → réordonner.

**Lien session ↔ bloc** (`lib/utils/today_logic.dart`) : une `Session` ne pointe PAS vers un bloc, le lien
est recalculé à l'affichage par `sessionMatchesBlock` (tâche du bloc, sinon activité-temps ou activité liée
de la routine, sinon activité liée du projet ; l'action n'est pas regardée). Au `start()` d'un chrono, si le
bloc en cours **ou celui qui commence dans les 15 min** (`blockToAttachAt`, cours de 14 h lancé à 13 h 55)
est sur une autre source, l'UI proposait « Pour ce bloc » = `attachSessionToBlock` → `AttachResult` — **question COUPÉE depuis le
2026-10-30** (`AppLogic.askBlockOnChrono = false`, retour user, sans réglage : au lancement ET au changement de bloc ; le chrono fait
foi, rattachement à la main par « Bloc ▾ » de la carte mobile). **Bloc libre revendiqué** (essai 2026-10-30) : au `start()`, un bloc LIBRE déjà
commencé (`freeBlockToClaim` : à faire, ni projet / tâche / activité / déroulé, `kind` normal, pas une pause, ≤ 3 h — jamais Sommeil)
prend en silence l'activité du chrono (`claimFreeBlock` ; la session garde sa tâche / action) et compte pour lui ; écrit par
`upsertScheduleBlock(rememberMirror: false)` — pas de mémoire « titre → activité » pour un rendez-vous récurrent. **Le chrono
fait foi** (2026-10) : la session GARDE son activité (c'est elle qui alimente les stats, l'utilisateur l'a choisie)
et prend la tâche/action du bloc ; un bloc **sans tâche** sur une autre activité ou **libre** (miroir Google Agenda,
bloc perso, projet sans activité liée) prend l'activité du chrono (`AttachResult.sessionAndBlock`, persisté par
`upsertScheduleBlock`, qui fusionne pour garder `subtitle` des miroirs) ; seule exception, un bloc de ROUTINE fait
basculer la session sur l'activité liée de la routine. Plusieurs sessions peuvent viser un même bloc (le lien vit
sur chaque session) ; limite : un bloc sans tâche ne reconnaît que la dernière activité rattachée. Même action
après coup : menu « Bloc ▾ » de la carte mobile, pilule « Pour ce bloc » de la carte web. La resync Google ne
touche qu'heure/durée/titre, le lien survit. Un miroir d'événement récurrent change d'id chaque occurrence :
rattachement à refaire (mémoire « titre → activité » = piste ultérieure). **Miroir = séance** (2026-10) : un miroir
agenda sans tâche posé le jour d'une intervention native dont le créneau se recouvre (≥ 15 min) reçoit EN MÉMOIRE le
projet et la tâche 🎯 de la séance (`linkMirrorsToSessions`, `utils/interventions.dart`, appelé au chargement du
programme mobile et web) : ▶, écran séance, déroulé, temps attribué — sans rien stocker, donc valable pour chaque
occurrence d'un événement récurrent. **Réveil au changement de bloc** : `BlockTransitionWatcher`
(tick minute `AppLogic.tickBlockTransition` côté mobile → même feuille ; ticker de `TodayView` web → SnackBar
« Pour ce bloc ») signale un bloc qui VIENT de devenir courant pendant un chrono hors source, une fois par
couple session × bloc, jamais à l'ouverture de l'app. Le web n'affiche jamais « Terminer le bloc » pour un chrono
hors bloc (état `aside`, comme le mobile). Passage auto en « fait » = mobile mode liste uniquement
(`_maybeAutoWin`), blocs avec `activityId` ; rien côté serveur. **Depuis 2026-10 : seul un bloc de ROUTINE se coche tout
seul** (cible atteinte = geste explicite). Pour un bloc d'activité ou de tâche, le temps de chrono atteint (≥ 60 % du
bloc dans son créneau) n'est qu'une **proposition** « 1 h 05 fait · Marquer fait ? » (tap = confirmer, bloc de tâche →
feuille « où en est la tâche » ; ✕ = écarter). Un bloc **décoché à la main** porte `noAutoWin` (mobile et web,
`updateBlockStatus(manual: true)`) : plus de coche automatique ni de proposition ; recocher le lève. **Règlement du soir** (2026-10, `utils/day_settle.dart`, `AppLogic.settleFinishedDay`) : à la bascule de journée vécue (ou au premier tick de l'app), les blocs de la VEILLE encore `pending` dont le chrono a couvert ≥ 60 % du créneau (plancher 10 min, heures d'horloge du jour calendaire du programme, Sommeil 22:00 → 05:00 compris) passent `done` avec `doneBy:"chrono"` — la journée est close, plus personne ne peut confirmer ; jamais un bloc `noAutoWin` ni sans source ; une fois par jour et par appareil (`day_settled_ymd`). C'est ce qui rend la journée parfaite atteignable avec un bloc Sommeil. **Rattachement après coup** (2026-10) : une session
TERMINÉE se rattache à un bloc depuis la feuille « Modifier la session » du mobile (ligne « Bloc du programme », feuille
« Dernières 24 h ») et depuis la carte « Chronos du jour » du web (`web/sessions_card.dart` : voir / corriger début, fin,
activité / supprimer / rattacher) — candidats triés par chevauchement (`blockCandidatesForSession`, `today_logic.dart`),
même mutation `attachSessionToBlock` ; côté MCP `update_session {taskId, actionId}` (`""` = détacher).

---

## Programmation automatique (2026-10, `docs/specs/programmation-auto-2026-10/README.md`)

Toggle `data/meta.autoPlan` (mobile : Paramètres ; web : menu ⋯). **Pas de cycle serveur** : une **routine
Claude** quotidienne (6 h Paris, connecteur Productivitwo) appelle `plan_day`, dont la **première bannière**
dit si la programmation automatique est activée ; désactivée ⇒ la routine ne modifie rien (une demande
directe de l'utilisateur n'est pas concernée). Elle écrit le programme en **`schedule_day(mode:"fill",
generatedBy:"auto")`** (garde tout l'existant, remplit les trous — `fillAgainstExisting`) et passe les
changements de projets par `propose_change`. `generatedBy:"auto"` ⇒ « planifiée automatiquement » dans
l'en-tête d'Aujourd'hui (web). Le prompt de la routine est versionné dans le handoff : le modifier là d'abord.

## Écritures ciblées des projets (2026-10)

Cocher une action / une étape, cocher une tâche, changer ses dates ou son estimation depuis le WEB n'écrit plus
tout le tableau `tasks` depuis la copie locale (un onglet resté ouvert écrasait les modifications faites ailleurs —
perte réelle sur « 6e — Mathématiques ») : `FirestoreSync.patchTaskAction` / `patchActionOf` (UNE action) et
`patchTaskFields` (quelques champs d'une tâche) relisent le projet dans une transaction et ne remplacent que ça
(logique pure `utils/project_patch.dart`, sous-projet d'origine pour un dossier fusionné). Branchés : Aujourd'hui,
Actions, Projets, Plan d'action, Réalisation, Cette semaine, aperçu de séance. **Tout le reste** (éditions
structurelles web, Gantt, fiche projet, tout le mobile) passe par `saveProjectTasks` / `saveProject`, qui
**fusionnent à trois voies** au lieu d'écraser (`utils/project_merge.dart`) : empreinte de chaque tâche et des champs
du projet posée au chargement (`_loadedProject` : `fetchProjects`, `streamProjects`, `_loadProject` ; copies de la vue
fusionnée via `copyTaskBase`), transaction qui relit le serveur ; tâche/champ modifié ici → local, inchangé ici →
serveur, tâche ajoutée ailleurs → gardée, supprimée ici (id connu de la liste locale) → retirée. Liste sans ids connus
(projet jamais chargé, liste reconstruite) = comportement historique. Les deux appareils modifient la MÊME tâche →
la dernière écriture gagne pour cette tâche. Hors connexion / transaction > 10 s : repli sur l'écriture directe
d'avant (`_mergedOrDirect`), mise en file par Firestore — le mobile reste utilisable sans réseau. Bande Focus web : « Arrêter le chrono » (geste principal, l'action reste ouverte) ≠
« ✓ Action faite » (coche + arrête, annulable).

**Fiche routine glissable** (2026-10-30) : `showRoutineSheet` passe par `showFiche` (85 %, tirer vers le bas = fermer), comme la fiche activité et la page domaine. **Lanceur de routines (FAB)** (maquette validée 2026-10-30, `widgets/routine_launcher_sheet.dart`, `showRoutineLauncher` / `RoutineLauncher`,
appelé par `_showRoutinesSheet` de main.dart) : en-tête « Routines » + Nouvelle, « 15 / 30 aujourd'hui · n à faire cet après-midi · 🔥 n
séries en cours » + barre, recherche ; routines À FAIRE rangées par domaine (couleur, compte du domaine), « Faites · n » replié en bas (atteintes
et « pas aujourd'hui »). Données = `buildRoutineDay` (même état que la vue Routines). Une ligne = anneau (compte, « + » si rien) qui ouvre le
**compteur** (− compte + au jour ou aux 7 j, part du moment, puis Chrono sur l'activité liée · Minuteur · Mettre au / Retirer du programme ·
Réglages), nom + UNE ligne d'infos (compte, part du moment « 0 / 10 ce soir » ou moment, « 🔥 n j ») qui ouvre la fiche routine, au plus UN
lanceur (▶ activité liée, sinon ⏱ minuteur) ; appui long = compteur. Plus de ☆, pastille « Quotidien » ni flammes répétées sur la ligne ; seules les routines FAITES (repli « Faites ») gardent − / + sur la ligne (retour user 2026-10-30 : corriger sans ouvrir la fiche).

**Sélecteur d'activité partagé** (2026-10-30, retour user « partout où je choisis une activité ») : `widgets/activity_picker.dart` —
`groupActivitiesByDomain` (ordre des domaines, domaine préféré en tête, « Sans domaine » à la fin), `ActivityDomainHeader` (pastille de
couleur), `showActivityPicker` (feuille défilante, coche sur l'activité courante, entrées « Aucune » / « Juste cocher » via
`ActivityPickerExtra`), `groupedActivityItems` (liste déroulante web). Branché : Modifier la session (Dernières 24 h), chrono d'un bloc de
projet, « Où tracer le temps » d'une routine, activité liée (projet, routine, action de tâche), action propre depuis la frise, action visée
libre, deep work « Autre », tri d'une capture, chrono d'une action (feuille d'action d'Actions : un bouton au lieu de 8 puces), nouvelle
action simple, Nouveau bloc (« Toutes »), web : « Modifier le chrono » et « Action simple ». Tout nouveau choix d'activité passe par lui.

**Lanceur d'activités (FAB)** (maquette validée 2026-10-30, `widgets/activity_launcher_sheet.dart`, `showActivityLauncher` /
`ActivityLauncher`, appelé par `_showLaunchActivitySheet` de main.dart) : « n chronométré aujourd'hui · k en retard », carte EN COURS (seul
élément hero : nom, temps qui défile, domaine · depuis, Arrêter · Fiche), recherche, puis par domaine (plus de section « À rattraper » depuis le 2026-10-30, retour user :
on vient lancer une activité déjà choisie ; une activité en retard — minimum ≥ 5 min / j et < 95 % de l'attendu sur la fenêtre de budget,
`launcherRows` / `LauncherRow` — le dit dans sa ligne, jauge orange) (temps du jour dans l'en-tête), « Peu
utilisées » repliées (aucun chrono sur 30 j). Ligne = icône du domaine, nom + infos + jauge (tap = fiche), **▶ lance le chrono tout de suite**
(■ si elle tourne) ; appui long = Lancer · 10 / 20 / 30 / 45 min · Deep work 90 (`showDeepWorkSheet(preferActivityId:)`) · Fiche. Activités en
pause exclues. **Défi ORION retiré** (2026-10-30, jamais utilisé) : plus de bouton doré « Challenge me », de puce « Défi ORION » dans MAINTENANT,
de proposition de défi dans la carte coach, ni de notification « Défi du jour » (annulée au démarrage, `cancelById(4)`, réglage retiré). Les
champs `challenge*` restent en base ; les défis déjà programmés (blocs 🔥) et `_programChallenge` (carte de combat) ne bougent pas.

## Confirmation avant de cocher (2026-10-30)

Toute coche d'un SIMPLE TAP d'une action ou d'une tâche (rond d'une ligne d'Actions, feuille d'action, bouton « Fait », projet
déplié, fiche de tâche, fiche d'action, fiche d'activité, écran bloc) passe par `confirmDone(context, title:, task:)`
(`widgets/confirm_done.dart` : « Action faite ? / Tâche faite ? » · Annuler · « Oui, c'est fait »). Exceptions : le glisser vers la
droite dans Actions (geste délibéré qui propose déjà « Annuler », `_toggleDone(confirm: false)`), « Étape faite » et les écrans
d'exécution (page focus, Enchaîner, séance). Décocher ne demande jamais confirmation.

## Suppression : soft-delete partout

Ne jamais faire `delete()` direct sauf cas explicite.
Utiliser `deleted: true` (domaines, activités, routines) ou `status: archived/deleted`.
`FirestoreSync` merge par ID — un doc absent côté Firestore ne supprime rien côté local.

---

## Cloud Functions (`functions/src/index.ts`)

~18 Cloud Functions HTTP (Node 20, 2nd Gen), groupées par rôle (👤 = action user, 🔌 = webhook/cron/MCP, 🛠 = admin).
`markPlanItemDone` (dayPlan mort) et les 16 fonctions sociales/jeu de `social.ts` ont été **supprimées** (pivot productivité).
Auth `mcpHandler` : header `Authorization: Bearer <token>` recommandé (l'URL `/mcp/{uid}/{token}` reste supportée en legacy).
Secrets : toute comparaison passe par `secretsMatch()` (temps constant) — jamais `===` sur un secret brut.

**MCP & Gantt** — `mcpHandler` (MCP remote JSON-RPC, connecteur claude.ai) · `pushGantt`, `pushAssistantMessage` (endpoints du MCP local) · `structureProject`
**Coaching** (`coaching.ts` — ⚠️ la brique Espace Coach EXISTE, ne pas recréer de lien coach-coaché côté client) — `coachApi` 👤 (coach : listClients/createClient/updateClient/deleteClient/invite/consentLink/dashboard/message ; droit coach = doc `coaches/{uid}.active`, posé via admin) · `coachConsent` 🔌 (page web de consentement du coaché, lien 14 j révocable) · `coacheeApi` 👤 (coaché : getLink/updateSharing/revoke). Fiches `coaching/{id}` + journal `consent_log` = collections racine **server-only** (aucune règle Firestore). Le dashboard est composé côté serveur, minimisé au périmètre consenti (`sharing.domainIds` opt-in + granularité statuts/détail). **Granularité « état »** (2026-10, `sharing.state`, opt-in à part dans « Mon coach ») : l'élan de la semaine (`elan` du dashboard, via `functions/src/elan.ts`) n'est composé que si elle est accordée ; les **badges** (`badges`, depuis l'instantané `data/badges`, séries filtrées aux domaines partagés) sont des faits toujours joints. Rapport de pré-séance et console web 8a les affichent. UI : console web 8a (`lib/web/coach_console_screen.dart`, bouton 🎓) + pipeline fiches (`coaching_screen.dart`) · mobile coaché « Mon coach » (`lib/widgets/coach_space_sheet.dart`).
**ORION** — `orionWebhook` 👤 (cycle sur demande) · `orionCron` 🔌 (cycle auto) · `orionBrief`, `orionRunCount`, `orionSaveConfig`
**Auth & accès web** — `sendMagicLink` 👤 (**gaté** : allowlist / compte existant / acheteur formation) · `getCustomToken` · `getVisionAccess` (statut Vision/Pro)
**Pro / Entitlements** — `revenueCatWebhook` 🔌 (RevenueCat iOS+Android → écrit `subscriptionUntil`)
**Formation / Onboarding** — `generateFormationAccess` 🔌 (webhook systeme.io) · `applyFormationProfile` · `onboardingChat` (Vision)
**Admin / Dev** — `adminProductivitwo` 🛠 (UI `/admin.html` ; actions globales `listUsers`, `addAllowlist`, `removeAllowlist`, `deleteUser`, `checkAccess`, `setPro` + édition Gantt par uid) · `githubWebhook` 🔌 (notif PR)

**Fichiers Cloud Functions** :

| Fichier | Rôle |
|---------|------|
| `index.ts` | Tous les exports HTTP (MCP, ORION, auth, Pro, admin, webhooks) |
| `execute.ts` | Implémentation de chaque outil MCP |
| `tools.ts` | Définitions inputSchema des outils MCP |
| `models.ts` | Constantes `MODELS` (Haiku/Sonnet), `getModel(taskType)`, `logTokenUsage()` |
| `orion.ts` | Cycle ORION (boucle LLM + tools) |
| `orion_tasks.ts` | Tâches déterministes ORION (sans LLM) |
| `prompts.ts` | Prompts MCP et template HTML document |
| `db.ts` | Instance Firestore admin + helper **`effectivePro(data)`** (statut Pro) |
| `types.ts` | Types TypeScript partagés |

**Ajouter un outil MCP** = 4 étapes :
1. Définir `CONST_TOOL` dans `tools.ts` (inputSchema)
2. Écrire `executeXxx()` async dans `execute.ts` + l'ajouter au bloc `export {}`
3. Ajouter dans `tools/list` (tableau dans `mcpHandler` — `index.ts`)
4. Ajouter le `else if` dans `tools/call` (`index.ts`) + importer depuis `execute.ts`

Après modification : `npm run build` dans `functions/`, puis `firebase deploy --only functions`.

**Trajectoire des objectifs** (2026-10, lot 1 = modèle + MCP + logique pure, rien de visible) : `StrategicObjective.metric
{label, unit, startValue, targetValue}` (version chiffrée de `kpiTarget`, qui reste le texte), `readings[] {id, date
YYYY-MM-DD, value, note}` (un par jour, le dernier remplace), `checkInEvery` (jours, défaut 7). Logique pure
`lib/utils/objective_trajectory.dart` ↔ `functions/src/objective_trajectory.ts` (**garder alignés**) : MOYENS = minutes
cumulées sur les activités engagées depuis le début (`startDate`, sinon `createdAt`) vs Σ `weeklyMin` × semaines écoulées ;
RÉSULTAT = dernier relevé vs droite `startValue → targetValue` sur [start, end] ; statut ≥ 110 % ahead · ≥ 85 % onTrack ·
sinon behind ; `readingDue` = dernier relevé (ou début) ≥ `checkInEvery` j. La jauge hebdo (`objective_progress.dart`) ne
change pas. MCP : `save_objective {metric | null, checkInEvery}`, `log_objective_reading(objectiveId, value, date?, note?)`,
`list_objectives` → `trajectory` + 12 derniers `readings`, résumé compact (`get_user_context`, `plan_day`) → `metric`
avec dernier relevé + `readingDue`, `weekly_review` (donc `plan_week` étape 0) liste les relevés dus. **Lot 2 (livré)** :
fiche objectif mobile `widgets/objective_trajectory_sheet.dart` (tap sur un objectif dans Objectifs) = jauge hebdo des
engagements, « Depuis le début · temps investi » (barre fait / total, repère « attendu aujourd'hui », avance / retard),
« Résultat » (graphe `fl_chart` : droite attendue pointillée, relevés, cible, trait aujourd'hui ; « Noter un relevé » =
valeur + date + note, `upsertReading`), Atteint / Archiver / Éditer ; les sessions sont relues depuis le début de
l'objectif (`fetchRecentSessions`). L'édition (`objective_edit_sheet.dart`, étape Mesurable) pose la métrique
(libellé, unité, aujourd'hui → cible) et le rythme de relevé (3 / 7 / 14 / 30 j) et conserve les relevés. **Lot 3 (livré)** :
carte « Relevé de la semaine · n » (`widgets/objective_readings_card.dart`, en tête d'Objectifs et sous la ligne Routines
d'Aujourd'hui, segment Actions) : objectifs dont un relevé est dû (`isReadingDue`), saisie en place (valeur + ✓ →
`upsertReading`, SnackBar avance / retard), tap sur le titre = fiche ; invisible quand rien n'est dû. La liste d'Objectifs
(`objectives_card.dart`) montre par objectif la **barre « temps investi »** (fait / total de l'horizon, repère vertical =
attendu aujourd'hui, écart « +1h05 / −2h18 » à droite ; sessions relues depuis le début le plus ancien) dès qu'il a un
engagement de temps, la jauge hebdo sinon. Pas de notification
en plus : le rappel côté Claude passe par `weekly_review` / `plan_week`.

**Interventions** (2026-10, handoff `docs/specs/interventions-2026-10/README.md`) : séance datée portée par le projet
(`Project.interventions[]`, `ProjectIntervention`) ; ses trois tâches 📝 / 🎯 / ✅ sont des `ProjectTask` taguées
`interventionId` + `interventionRole`. Outils `add_intervention` (génère les trois tâches depuis un modèle),
`update_intervention` (date → décalage des tâches ; bilan `debriefText` + `carryOver` → checklist « Adapter au bilan
précédent » de la séance suivante), `manage_intervention_templates` (`data/meta.interventionTemplates`),
`migrate_interventions` (triplets existants → natif, appariement temporel par jalon, dryRun), `delete_intervention` (détache par défaut), `update_task {interventionId, interventionRole}` (rattacher / détacher ; rôle principal unique, `extra` = secondaire), `update_intervention {mergeFrom}` (fusion), `plan_prep` (prépa dans les trous : veille au soir d'abord, impression sur place collée à la séance ; `apply:false` = proposition ; logique pure `functions/src/prep_planner.ts` ; bouton web « Planifier la prépa avec Claude » sur la 📝 dans Réalisation), `weekly_review` (revue des orphelins, ne modifie rien ; logique pure `functions/src/project_audit.ts` ; étape 0 de `plan_week` ; `archive_project` avertit des séances à venir, `push_gantt` signale un doublon probable). Logique pure `functions/src/interventions.ts` ; côté app
`lib/utils/interventions.dart` (natif d'abord, repli convention émojis + `groupLabel`) alimente le radar « Cette semaine » (web `projects_view.dart`, mobile `widgets/week_radar_card.dart` en tête de Projets). Mobile : écran « séance en cours » `widgets/session_player_screen.dart` (étape en cours, heure prévue, bilan → prépa suivante), ouvert depuis le jalon (fiche projet), le ▶ du radar ou un bloc du programme visant un jalon de séance.

**Titres lisibles + détail d'action** (A + B, 2026-10) : diagnostic = Claude écrivait des titres « cahier des charges »
(codes, coefs, consignes, parenthèses) affichés tels quels dans Aujourd'hui. Règle : **un titre = verbe + objet, ≤ 8 mots,
sans code ni parenthèse** ; le détail va dans **`TaskAction.note`** (nouveau, optionnel, ≤ 2000 car. ; affiché au tap dans
la feuille d'action mobile, l'écran bloc et l'espace Réalisation web, édité dans le dialog d'action web) ou
`ProjectTask.description` ; pas d'emoji / date dans le titre d'une tâche de séance (la structure les porte). Côté MCP :
`WRITING_RULES` (`functions/src/title_style.ts`) dans les descriptions de `push_gantt` / `add_task` / `update_task` /
`update_action` / `add_activity_action` / `schedule_day` ; `note` accepté sur les objets action (`normalizeTasks`),
`update_action {note | clearNote}` (`action_patch.ts`), `add_activity_action {note}` ; `checkTitle` / `titleAdvice` ajoutent
« ✍️ Titres à alléger » (4 lignes max) à la réponse des outils — **jamais de réécriture automatique**. Les tâches de séance
gardent leur émoji de rôle (📝 / 🎯 / ✅ : repère visuel de l'app) en forme courte « 📝 Préparer — Séance du 12 oct » ;
`isPrepTask` / `isClosureTask` / `isMilestoneTask` (`utils/interventions.dart`) lisent `interventionRole` d'abord, l'émoji
en repli. **D (livré)** : `BLOCK_RULES` (`functions/src/block_style.ts`) dans `schedule_day` et le workflow de `plan_day` —
bloc de travail ≥ 30 min, actions consécutives d'une même tâche = UN bloc nommé par la tâche (`actionId` = la première,
l'écran bloc enchaîne) ; routines, pauses, prep, rendez-vous exemptés ; `blockAdvice` ajoute « ⏱ Programme haché » à la
réponse de `schedule_day` (blocs courts, suites fusionnables). Nettoyage de données fait à la main sur « CM — Nombres et
calculs » (actions ouvertes : titres courts + `note`).

**Estimations par défaut** (2.4, 2026-10) : une action créée sans `estimatedMin` en reçoit une d'après son verbe / objet
(`functions/src/default_estimates.ts` côté MCP, `lib/utils/default_estimate.dart` côté app — **garder alignés**).
`ActionsSort.milestone` trie les projets par prochaine séance (`urgencyOf`), automatique avec un filtre « J'ai … ».
`estimateFactor` (`utils/time_spent.dart`) affiche « Réel ≈ n× l'estimé » dans Actions. B4 : `update_actions(updates[])`
(lot de 50) et rate limit MCP à 300 appels / h.

**Phases par libellé** (B1, 2026-10, `functions/src/phase_resolve.ts`) : `push_gantt` / `add_task` / `update_task` résolvent
`groupLabel` ou un `phaseId` égal au libellé d'une phase → vrai `phaseId` (mono-phase : tâche sans indication → la phase
unique). `mark_action_done` est idempotent (`done` omis = true, jamais de bascule).

**Attention** : `executePushGantt` dans `execute.ts` doit toujours appeler `normalizeTasks()`
pour convertir les actions `string[]` en `TaskAction` maps — ne pas faire de spread direct `{ ...t }`.

---

## Pro / Entitlements & Accès web

> **⚠️ Ouverture (sept. 2026, handoff `docs/specs/ouvrir-app-2026-09/README.md`)** : l'app n'est plus
> payante pour l'instant (outil des coachés, inclus dans le coaching). **Tout est ouvert par deux flags,
> rien n'est démonté** : `FREE_FOR_ALL = true` (`functions/src/entitlements.ts`, `effectivePro` renvoie
> true) et `kFreeForAll = true` (`lib/entitlements_flags.dart`, `ProManager.isPro` vaut true sans
> RevenueCat). Le paywall (`paywall_sheet.dart`) n'a plus d'appelant. Pour rallumer (phase 3) : serveur
> d'abord, puis app. Le reste de cette section décrit la mécanique **en sommeil**.

**Statut Pro** — source de vérité serveur : collection `formation_access/{uid}` (nom historique). 3 sources combinées par `effectivePro(data)` (`db.ts`) — l'une suffit, aucune n'écrase l'autre :
- `subscriptionUntil` (Timestamp) — abonné **RevenueCat**, posé par `revenueCatWebhook` (iOS+Android, un seul webhook ; `app_user_id` = Firebase uid via `Purchases.logIn`).
- `proUntil` (Timestamp) — **grant daté** (comp admin via `setPro`, ou formation). ⚠️ un grant ne pose QUE `proUntil` (jamais `isPro:true`, sinon il n'expirerait jamais).
- `isPro` (bool) — **legacy** / sans expiration. À éviter.

`isPro effectif = subscriptionUntil>now OU proUntil>now OU isPro===true`.

**Lecteurs** : `getVisionAccess` + `onboardingChat` (web/serveur) · **`ProManager`** mobile (`isPro = RevenueCat OU grant` ; lit `formation_access/{uid}.proUntil`, règle Firestore self-read) · `adminProductivitwo.listUsers` (affiche la source : Abo / Grant / Legacy).

> ⚠️ `ProManager.init()` lit le grant Firestore → **doit tourner APRÈS `Firebase.initializeApp()`** (sinon crash/écran blanc au démarrage). Ordre garanti dans `main.dart`.

**Limites ORION** : enforcées **côté serveur** dans `runOrionCycle` via `effectivePro` (free 1/j, pro 5/j) — pas seulement côté client.

**Accès web (beta)** : `sendMagicLink` n'envoie le lien que si l'email est autorisé = compte Firebase existant OU doc dans la collection **`allowlist`** (id = email minuscule). Inviter un beta = créer `allowlist/{email}` (via `/admin.html`). Inconnu → 403.

**Vision** : 1ʳᵉ session gratuite (tous) ; **révisions Vision = Pro** (gate serveur dans `onboardingChat` sur `effectivePro`).

**Offre** : Free (Vision 1ʳᵉ session, tracking, ORION 1/j) · Pro (Vision révisions, ORION 5/j, stats, rapport temps, app web) · Formation = cours premium + grant Pro. **Règle : une feature = un TIER, jamais un canal d'achat.**

---

## Model Routing (`functions/src/models.ts`)

Toujours importer depuis `models.ts` — ne jamais écrire les noms de modèle en dur.

```typescript
import { MODELS, getModel, logTokenUsage } from "./models";

// Routing par type de tâche
getModel("orion_cycle")       // → MODELS.HAIKU
getModel("structure_project") // → MODELS.OPUS  (création de projet — moment "wow", 5/j max)
getModel("structure_preview") // → MODELS.HAIKU (mindmap live onboarding, appels fréquents)
getModel("chat")              // → MODELS.SONNET
getModel("generate_document") // → MODELS.SONNET
// Haiku par défaut pour toute nouvelle tâche automatique
```

`logTokenUsage(taskType, model, usage)` — log JSON structuré dans Cloud Logging.
À appeler après chaque `client.messages.create()` ou équivalent.
Tâches automatiques (JSON structuré) → Haiku. Conversations / génération riche → Sonnet.
Exception : `structure_project` → Opus (feature vitrine payante, volume faible et plafonné).

---

## Version iOS (pubspec = source de vérité)

`pubspec.yaml` `version: X.Y.Z+N` alimente `Runner` (`FLUTTER_BUILD_NAME/NUMBER`). L'extension
widget (`ProductivitwoWidgetExtension`) n'a pas de `Generated.xcconfig` : son `MARKETING_VERSION`
est **littéral** dans `ios/Runner.xcodeproj/project.pbxproj` et doit suivre — sinon
ITMS-90473 (« CFBundleShortVersionString Mismatch », vu sur la 1.0.6 build 510). Le script
`ios/ci_scripts/ci_pre_xcodebuild.sh` réaligne toutes les `MARKETING_VERSION` sur le pubspec avant
chaque build Xcode Cloud ; en montant la version, mettre quand même le pbxproj à jour (build locale).

## Mac (Apple Silicon, « Conçue pour iPhone »)

Le widget iPhone relayé sur le Mac ne peut pas ouvrir l'app en UE (Recopie de l'iPhone indisponible,
DMA). Réponse retenue : rendre le **même binaire iOS** installable sur Mac via App Store Connect
(Tarifs et disponibilité → « Apps iPhone et iPad sur Mac avec puce Apple », **déjà cochée**),
pas de cible Catalyst ni `flutter build macos`.
Procédure, test TestFlight Mac et audit des plugins : `docs/mac_designed_for_iphone.md`.
Sur Mac, `Platform.isIOS` reste vrai ; côté natif, tester `ProcessInfo.processInfo.isiOSAppOnMac`.

## Siri (App Intents, iOS 16+)

Raccourcis vocaux dans `ios/Runner/SiriIntents.swift` (target Runner — un
`AppShortcutsProvider` doit vivre dans le target app principal, pas le widget).
Pas de ré-auth : réutilise `mcp_uid` + `mcp_token` de l'App Group (posés par
`WidgetService.provisionAuth`). Lectures servies depuis l'App Group (hors-ligne) ;
écritures via `mcpHandler` (même endpoint que les boutons de widget).

- `TodayScheduleIntent` / `FocusTaskIntent` — lecture (programme, tâche du jour)
- `LogRoutineSiriIntent` (+ `RoutineAppEntity`/`RoutineEntityQuery`) — coche une routine par nom
- Bouton in-app : Paramètres → « Siri & Raccourcis » (`lib/siri_service.dart`)

Les intents du widget (`MarkRoutineDoneIntent`…) restent séparés (boutons de widget).
Détails et étapes Xcode : `docs/siri_integration.md`.

---

## MCP local (`mcp-server/index.js`)

Serveur stdio pour Claude Desktop. Variables d'env requises :
- `PRODUCTIVITWO_TOKEN` — token API Bearer
- `PRODUCTIVITWO_UID` — UID Firebase de l'utilisateur
- `PRODUCTIVITWO_API_URL` — (optionnel) override URL pushGantt
- `PRODUCTIVITWO_ASSISTANT_API_URL` — (optionnel) override URL pushAssistantMessage

---

## Assistant IA (`assistant_messages`)

Messages planifiés par Claude, évalués localement dans l'app web.

Schema Firestore :
```
{
  id, targetDate (YYYY-MM-DD), text, characterName,
  condition: { type, ...params },
  expiresAfterDays, priority, action?, status, createdAt, createdBy, shownAt
}
```

**20 types de conditions** (évalués côté Flutter le jour J) :
- `always` · `overdue_count(min)` · `day_plan_empty` · `day_plan_overloaded(min)`
- `project_inactive_days(projectId, days)` · `project_deadline_near(projectId, daysBefore)`
- `project_milestone_today(projectId)` · `activity_behind_target(activityId)`
- `activity_streak(activityId, minDays)` · `no_activity_logged_today`
- `goal_undone_actions(activityId, min)` · `goal_near_deadline(goalId, daysBefore)`
- `habit_streak_broken(habitId)` · `routine_completion_low(maxPercent)`
- `inbox_overflow(min)` · `no_now_focus(beforeHour)`
- `week_start` · `week_end` · `first_open_of_day` · `custom_date(date)`

> `day_plan_empty` et `day_plan_overloaded` sont définis mais **non évalués** (dayPlan supprimé).
> Idem pour `goal_undone_actions` et `goal_near_deadline` (modèle GTD `Goal` supprimé — Full Firestore).
> Ces conditions retournent `false` systématiquement dans `assistant_engine.dart`.

**Status cycle** : `pending` → `shown` → `dismissed` | `expired`

---

## App web (`lib/web/`)

Compilée séparément du mobile. Accès via token API + `getCustomToken`.
Affiche : projets Gantt, documents HTML, assistant IA.

**Build + deploy web :**
```
flutter build web --release --no-tree-shake-icons --pwa-strategy=none
firebase deploy --only hosting
```
**Sans service worker** depuis 2026-10 (`--pwa-strategy=none`, `web/flutter_bootstrap.js` :
`serviceWorkerSettings: null`) : Firebase Hosting sert `index.html` / bootstrap / `main.dart.js` sans cache,
chaque ouverture charge la version en ligne ; `index.html` désinscrit les anciens SW et vide leurs caches.
Version visible : dernière ligne du menu ⋯ (`kBuildLabel`, `lib/build_info.dart`, injectée par le CI).

---

## Mini-spec des tâches de développement Gantt

Les sous-actions (`actions[]`) d'une tâche Gantt de type dev doivent suivre ce format en **4 lignes** :

```
actions: [
  "Objectif : <ce que la tâche doit accomplir — 1 phrase>",
  "Fichiers : <chemins ou zones concernés, ex: lib/web/gantt_screen.dart, functions/src/execute.ts>",
  "Critères : <critères d'acceptation vérifiables, séparés par ' · '>",
  "Contraintes : <limites techniques, dépendances interdites, rétrocompatibilité requise>"
]
```

**Exemple concret :**
```
actions: [
  "Objectif : ajouter un filtre de recherche en temps réel sur la liste des projets",
  "Fichiers : lib/web/web_home_screen.dart, lib/web/gantt_screen.dart",
  "Critères : filtre réactif < 200ms · vide = affiche tout · insensible à la casse · résultat vide = message explicite",
  "Contraintes : pas de dépendance externe · utiliser TextField Flutter existant · ne pas casser l'état de navigation"
]
```

> Ce format s'applique uniquement aux tâches de développement logiciel.  
> Pour les tâches non-dev (séances sport, réunions, livrables…), utiliser 2-4 étapes courtes avec verbe d'action.

---

## Conventions de code

- Pas de commentaires sauf invariant non-évident
- Soft-delete systématique (jamais de `delete()` direct sur domains/activities)
- `YYYY-MM-DD` = format ISO pour tout (projets, sessions, MCP)
- Les documents HTML sont toujours liés à `projectId` + `taskId` quand applicable
- Routine = `Activity` `type: habit`, mesurable (`habitFreq` + `habitTarget`), rattachée à un domaine ; `activityId` (lien vers une activité temps) **optionnel** — full routines, plus de « recurring action »
- Les actions de tâches Gantt (`ProjectTask.actions`) sont des `TaskAction` maps en Firestore —
  `ProjectTask.from()` gère les deux formats (string et map) pour compatibilité ascendante
- **Contextes GTD d'une action** : `contexts` (multi) est la référence, `context` (mono, legacy) =
  `contexts[0]`. Lire via `allContexts` / `primaryContext` — **jamais `context` seul**. Les deux champs se
  complètent à la lecture (`TaskAction.from`) et à l'écriture MCP (`withBothContexts`, execute.ts) ;
  migration one-shot des données : `adminProductivitwo` action `migrateContexts` (`payload.uid?`, `dryRun?`).
- **Édition structurelle directe autorisée** (le dogme « tout par l'IA » est levé pour la
  structure) : déplacer une tâche entre projets, une action entre tâches, promouvoir une
  action en sous-projet. Helpers centralisés dans `FirestoreSync` (`moveTaskToProject`,
  `moveActionToTask`, `promoteActionToSubproject`, `setProjectParent`) — réutilisés par les
  fiches tâche web (`gantt_screen.dart`) et mobile (`project_sheet.dart`). L'IA (Orion
  autonome) **propose**, l'utilisateur dispose ; le chemin MCP/conversation à la demande
  garde le write direct.

---

## Backlog mémorisé (demandes user, à faire plus tard)

- **« Ma semaine » = routines d'objectifs** (décidé 2026-10-26) : la carte « Ma semaine » (mobile, web, dashboard coach)
  ne juge que les routines rattachées à un objectif en cours (`engagedRoutineIds`, `utils/engagement_stats.dart`) ; aucune
  → toutes. Engagement « tenu » dès 80 % de la cible (`kKeptRatio`), pourcentage = moyenne des parts faites.
  **Au prorata du jour** (2026-10, mobile) : la carte, les lignes de domaine et la fiche jugent sur l'attendu À CE JOUR
  (`expectedToDate` = cible × jour / 7, arrondi ; `WeekSummary.pct` / `kept` / `onTrack`), la semaine entière reste en
  rappel (`pctWeek`, `keptWeek`). La fiche « Ma semaine » est en sections repliables (`FicheTitle(onToggle:)`,
  `WeekDetailSection` nommées par `main.dart`, état `week_fiche_open`).
- **Objectifs archivés** (noté 2026-10-21) : « Archiver » dans la fiche objectif est la seule suppression (soft, sans
  confirmation) et aucun écran ne liste les archivés. À faire : liste « Archivés · n » repliée en bas de l'onglet Objectifs
  avec « Réactiver », et une confirmation sur « Archiver ».

- **Modes et coups tactiques** (noté 2026-10-27, handoff `docs/specs/modes-et-coups-2026-10/README.md`, maquette à valider) : mode Flemme / Normal / En forme changeable à tout moment (= pointage d'élan), ambiance par mode, chips « malgré tout » / « à fond » dérivés, coups = `StrategicObjective.horizon:"tactical"` (3–10 j, même fiche / graphe), veille de domaines `data/meta.restDomains`, budget de domaine sur 14 j, carte du moment pilotée par le mode, `plan_day` par jours de focus. Maquette validée le 2026-10-27. **Lot 0 livré** : `lib/utils/mode.dart` ↔ `functions/src/mode.ts` (`modeOf` = dernier élan du jour vécu, `malgreTout` / `aFond` dérivés, `isResting`, `parseBudgetWindowDays`), `StrategicObjective.horizon`, `AppLogic.mode` / `setMode` / `restDomains` / `budgetWindowDays`, MCP `set_mode`, `rest_domain`, `save_objective {horizon}`, `list_objectives.coups`, `get_user_context.mode`, règles `plan_day` par mode. **Lot 1 livré** : `ModePill` / `showModeSheet` / `modeChipFor` (`widgets/mode_sheet.dart`), `utils/mode_colors.dart` (thème par `AppLogic.modeNotifier`, `NowPalette.primary` sombre par mode), chips « malgré tout » / « à fond » (programme, actions faites, récap Enchaîner), badge « Deep work » (`deepWorkSessions(sessions, schedules)` : **strict depuis le 2026-10-27** — seul un bloc `kind:"deepwork"` posé par « Deep work 90 min » et couvert ≥ 60 min par un chrono de sa source compte ; jamais un chrono long seul). **Lot 2 livré** : `utils/mode_moves.dart` (`deepWorkCandidates`, `deepWorkBlock`, `smallChain`), feuille « Sur quoi ? » `widgets/deep_work_sheet.dart` (propose, jamais de chrono sans geste), MAINTENANT « 10 min, malgré tout » / « n petites choses » / « Deep work 90 min », `pickActionMoment(mode:, focusProjectId:)`, `rankObjectiveMoments(mode:)`, « Bloc de 90 min » sur la carte Objectif. **Lot 3 livré** : `utils/coups.dart` (`coupLabel`, `validateCoup`, `coupProjectIds`…), section « COUPS · n » + `widgets/coup_sheet.dart` (quoi · cible · jusqu'à quand · pour) + `widgets/rest_sheet.dart` (veille par domaine, `liftRest`), veille dans Stats (`domainWeeks(rest:)`), Actions (section « EN VEILLE »), Projets (`rankProjectMoments(priorityIds:)`), deep work et `plan_day` (`restLines`). **Lot 4 livré** : `utils/budget_window.dart` (`budgetWindowStart` 7 = lundi / 14 = quinzaine à départ fixe, `dailyMinutesByDomain`), `domainWeeks(windowDays:)`, Stats sur la fenêtre + section « Répartition sur n j » de la fiche Ma semaine, tuile Paramètres « Budget des minimums », `plan_day` jours de focus (`modeRules`) + `budgetRules`. **Lot 5 livré (web)** : `lib/web/mode_web.dart` (`moodMarkForMode`, `showWebModeDialog`, `WebModePill`, `webModeChip`), « Mode du jour » dans le menu ⋯ + pilule de la barre, chips sur les blocs faits d'Aujourd'hui, coups en tête de la carte Objectifs du jour et cartes « COUP » dans Projets. **Les 6 lots sont livrés.**
- **Export / import des données** (noté 2026-07-19, **cadré 2026-07-24**) : handoff design + produit
  dans `docs/specs/export-import-donnees/README.md` (lot « Coffre » : sauvegarde .json complète +
  restauration Fusionner/Remplacer ; export CSV et import de migration **écartés**, ne pas les
  implémenter). Specs de tâches 4 lignes incluses (lot 1 = export seul, lot 2 = restauration).
  Calendrier : gel V1 levé le 2026-07-24 → **en cours d'implémentation**, avant l'Espace Coach V1.1.
