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
  demain, capture rapide → boîte d'entrée. Même logique pure que le web (`utils/actions_logic.dart`).
  **Dossiers / clients** (2026-10) : un projet racine sans tâche dont d'autres projets dépendent (`parentProjectId`) est un
  *dossier* (`isFolderProject`, `rootProjectOf`, `clientRoots`, `groupByFolder` dans `utils/actions_logic.dart`). Web :
  vue fusionnée (`utils/folder_merge.dart`, Vision/Plan d'action/Réalisation) + regroupement dans Projets + filtre
  « Pour… » dans Actions. Mobile : en-tête de dossier repliable dans Projets (`goals_view.dart`) + filtre « Pour » dans
  Actions ; jamais « Définir la prochaine action » sur un dossier. Filtre « Pour… » (`inClient`, `actions_logic.dart`) :
  un client choisi ne montre QUE ses projets (les actions simples d'activité disparaissent) ; entrée **« Perso »**
  (`kPersoClientId`) = les actions sans projet ; « Tous » = tout.
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
Projets (lot 4) = tableau `views/projects_view.dart` + `lib/utils/project_health.dart` (état calculé,
prochaine action, 7 jours) ; « Définir la prochaine action » partagé dans `web/quick_add_action_dialog.dart`.
Fiche projet (lot 5) = `views/project_plan_view.dart`, onglets **Vision · Plan d'action · Réalisation** (2026-10, du
plus large au plus fin : Vision = Gantt, Plan d'action = tâches + actions, Réalisation = étapes des actions), hébergée
dans le shell ; **s'ouvre toujours sur Plan d'action**, y compris depuis un bloc ou une
action (`targetTaskId` → phase de la tâche dépliée) ; « Nouvelle tâche » partagé dans `web/add_task_dialog.dart`, visionneuse de
documents dans `web/document_viewer_dialog.dart`. L'onglet **Document** (`ProjectDocView`, playbook Markdown) a été
**retiré** en 2026-10 au profit de **Réalisation** (`views/project_checklists_view.dart`, handoff
`docs/specs/checklists-2026-10/README.md`) : plan phases → tâches → actions à gauche, espace de travail de l'action à
droite (étapes cochables, renommables en place, réordonnables, ajout à la volée, marquer faite / rouvrir). Pas de 4ᵉ
niveau : le modèle `ChecklistItem` est inchangé, donc tout reste cochable sur mobile et par le MCP ; la fiche de tâche
mobile (`widgets/project_sheet.dart`, `_StepsSection`) déplie les étapes au tap (cocher, ajouter, appui long =
renommer / retirer). Helpers purs dans
`utils/checklist_logic.dart` (`setChecklistItem`, `addChecklistItem`, `renameChecklistItem`, `moveChecklistItem`,
`setActionDone`, `nextChecklistItem`).
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
- **Firebase** : Auth (Apple Sign-In + anonyme), Firestore, Cloud Functions (Node 20, 2nd Gen)
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

**Outils MCP** :
- `get_day_schedule(date)` — lit le programme du jour
- `schedule_day(date, blocks[])` — crée ou remplace le programme (un bloc peut porter `actionId` → chrono ciblé). **Le passé
  est immuable** (2026-10) : en mode remplacement, les blocs déjà vécus (faits, sautés, commencés avant maintenant dans la
  journée de l'utilisateur, tombstones passés compris — `isSettledBlock`, `schedule_dedupe.ts`) survivent et un entrant
  qui les chevauche est écarté ; seul l'avenir est remplacé
- `add_activity_action(activityId, title, context?, contexts?)` — crée une **action propre** (`Activity.ownActions`) sur une activité-temps, programmable ensuite via `schedule_day` (`activityId`+`actionId`)
- `mark_checklist_item(projectId, taskId, actionId, itemId, done)` — coche une micro-action ; `checklist` accepté sur les actions de `push_gantt` / `add_task` / `update_task` (string ou `{title, done?}`, ids préservés au re-push)
- `link_action_to_activity(projectId, taskId, actionId, activityId)` — associe une sous-action de tâche à une activité-temps (`TaskAction.linkedActivityId`) → chrono ciblé. L'IA le **propose** quand une action n'est pas déjà liée et qu'une activité-temps du même domaine existe
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
  label?, color?, startDate?, endDate?}]}` (par id, jamais d'ajout / suppression : `push_gantt`), `update_block(date,
  blockId, title?, startTime?, durationMin?, category?, status?, projectId?, taskId?, activityId?, actionId?)` (`""` sur
  un lien = le retirer ; le reste du programme est intact)
- `manage_contexts(action: list|add|rename|delete, context?, newContext?, detach?)` — contextes GTD : `list` (défauts +
  personnalisés `data/meta.customContexts`, usage ouvertes/faites, orphelins), `add`, `rename` (propagé à toutes les
  actions des projets et des activités, fusion si le nom existe), `delete` (tag orphelin conservé sauf `detach:true`). Les
  6 défauts sont fixes ; « Je suis @… » (`nowContexts`) est local à l'app. Logique pure dans `functions/src/contexts.ts`
- `plan_day(date?, startHour?, endHour?, syncToCalendar?)` — agrège user context + schedule existant + projets actifs en un appel ; retourne le contexte consolidé + workflow pour générer le programme et le syncer dans Google Calendar
- `plan_week(startDate?, syncToCalendar?)` — idem sur 5 jours ouvrés (défaut : lundi prochain)
- `sync_calendar(date?)` — lit le programme existant et retourne les instructions GCal précises (delete + create_event avec colorId et tag `source: productivitwo`)

**Vue Flutter** : `lib/widgets/daily_schedule_view.dart` dans l'onglet Maintenant.
Actions : tap checkbox → done, tap → éditer, swipe gauche → supprimer, long press → réordonner.

**Lien session ↔ bloc** (`lib/utils/today_logic.dart`) : une `Session` ne pointe PAS vers un bloc, le lien
est recalculé à l'affichage par `sessionMatchesBlock` (tâche du bloc, sinon activité-temps ou activité liée
de la routine, sinon activité liée du projet ; l'action n'est pas regardée). Au `start()` d'un chrono, si le
bloc en cours **ou celui qui commence dans les 15 min** (`blockToAttachAt`, cours de 14 h lancé à 13 h 55)
est sur une autre source, l'UI propose « Pour ce bloc » = `attachSessionToBlock` → `AttachResult`. **Le chrono
fait foi** (2026-10) : la session GARDE son activité (c'est elle qui alimente les stats, l'utilisateur l'a choisie)
et prend la tâche/action du bloc ; un bloc **sans tâche** sur une autre activité ou **libre** (miroir Google Agenda,
bloc perso, projet sans activité liée) prend l'activité du chrono (`AttachResult.sessionAndBlock`, persisté par
`upsertScheduleBlock`, qui fusionne pour garder `subtitle` des miroirs) ; seule exception, un bloc de ROUTINE fait
basculer la session sur l'activité liée de la routine. Plusieurs sessions peuvent viser un même bloc (le lien vit
sur chaque session) ; limite : un bloc sans tâche ne reconnaît que la dernière activité rattachée. Même action
après coup : menu « Bloc ▾ » de la carte mobile, pilule « Pour ce bloc » de la carte web. La resync Google ne
touche qu'heure/durée/titre, le lien survit. Un miroir d'événement récurrent change d'id chaque occurrence :
rattachement à refaire (mémoire « titre → activité » = piste ultérieure). **Réveil au changement de bloc** : `BlockTransitionWatcher`
(tick minute `AppLogic.tickBlockTransition` côté mobile → même feuille ; ticker de `TodayView` web → SnackBar
« Pour ce bloc ») signale un bloc qui VIENT de devenir courant pendant un chrono hors source, une fois par
couple session × bloc, jamais à l'ouverture de l'app. Le web n'affiche jamais « Terminer le bloc » pour un chrono
hors bloc (état `aside`, comme le mobile). Passage auto en « fait » = mobile mode liste uniquement
(`_maybeAutoWin`), blocs avec `activityId` ; rien côté serveur. **Rattachement après coup** (2026-10) : une session
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
**Coaching** (`coaching.ts` — ⚠️ la brique Espace Coach EXISTE, ne pas recréer de lien coach-coaché côté client) — `coachApi` 👤 (coach : listClients/createClient/updateClient/deleteClient/invite/consentLink/dashboard/message ; droit coach = doc `coaches/{uid}.active`, posé via admin) · `coachConsent` 🔌 (page web de consentement du coaché, lien 14 j révocable) · `coacheeApi` 👤 (coaché : getLink/updateSharing/revoke). Fiches `coaching/{id}` + journal `consent_log` = collections racine **server-only** (aucune règle Firestore). Le dashboard est composé côté serveur, minimisé au périmètre consenti (`sharing.domainIds` opt-in + granularité statuts/détail). UI : console web 8a (`lib/web/coach_console_screen.dart`, bouton 🎓) + pipeline fiches (`coaching_screen.dart`) · mobile coaché « Mon coach » (`lib/widgets/coach_space_sheet.dart`).
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

**Interventions** (2026-10, handoff `docs/specs/interventions-2026-10/README.md`) : séance datée portée par le projet
(`Project.interventions[]`, `ProjectIntervention`) ; ses trois tâches 📝 / 🎯 / ✅ sont des `ProjectTask` taguées
`interventionId` + `interventionRole`. Outils `add_intervention` (génère les trois tâches depuis un modèle),
`update_intervention` (date → décalage des tâches ; bilan `debriefText` + `carryOver` → checklist « Adapter au bilan
précédent » de la séance suivante), `manage_intervention_templates` (`data/meta.interventionTemplates`),
`migrate_interventions` (triplets existants → natif, appariement temporel par jalon, dryRun), `delete_intervention` (détache par défaut), `update_task {interventionId, interventionRole}` (rattacher / détacher ; rôle principal unique, `extra` = secondaire), `update_intervention {mergeFrom}` (fusion), `plan_prep` (prépa dans les trous : veille au soir d'abord, impression sur place collée à la séance ; `apply:false` = proposition ; logique pure `functions/src/prep_planner.ts` ; bouton web « Planifier la prépa avec Claude » sur la 📝 dans Réalisation), `weekly_review` (revue des orphelins, ne modifie rien ; logique pure `functions/src/project_audit.ts` ; étape 0 de `plan_week` ; `archive_project` avertit des séances à venir, `push_gantt` signale un doublon probable). Logique pure `functions/src/interventions.ts` ; côté app
`lib/utils/interventions.dart` (natif d'abord, repli convention émojis + `groupLabel`) alimente le radar « Cette semaine » (web `projects_view.dart`, mobile `widgets/week_radar_card.dart` en tête de Projets). Mobile : écran « séance en cours » `widgets/session_player_screen.dart` (étape en cours, heure prévue, bilan → prépa suivante), ouvert depuis le jalon (fiche projet), le ▶ du radar ou un bloc du programme visant un jalon de séance.

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

- **Export / import des données** (noté 2026-07-19, **cadré 2026-07-24**) : handoff design + produit
  dans `docs/specs/export-import-donnees/README.md` (lot « Coffre » : sauvegarde .json complète +
  restauration Fusionner/Remplacer ; export CSV et import de migration **écartés**, ne pas les
  implémenter). Specs de tâches 4 lignes incluses (lot 1 = export seul, lot 2 = restauration).
  Calendrier : gel V1 levé le 2026-07-24 → **en cours d'implémentation**, avant l'Espace Coach V1.1.
