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
- Onglets mobiles actuels : **Accueil / Projets / Aujourd'hui (programme + demain) /
  Maintenant (focus/chrono)**. Ne pas réintroduire d'UI de jeu.

**Points de restauration permanents (ne jamais modifier/supprimer) :**

- **`archive/couche-jeu-complete-2026-07`** = état complet AVANT la purge du jeu
  (commit `f72eb3a`). Repêcher : `git checkout archive/couche-jeu-complete-2026-07 -- <chemin>`.
- **`archive/style-actuel-2026-06`** (commit `2f335d1`) = l'app/style AVANT la refonte Soft Pop.
- Rien n'est perdu tant qu'on ne **force-push jamais** sur `main`. ⚠️ Ne **jamais** force-push.
- Note : les **tags** ne sont pas poussables via le proxy git de session (403 politique) — d'où
  l'usage de **branches d'archive** comme repères, créées via l'API GitHub.

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
├── web/                 — app web autonome (Gantt, auth, assistant)
│   ├── web_home_screen.dart
│   ├── gantt_screen.dart
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
- `schedule_day(date, blocks[])` — crée ou remplace le programme entier (un bloc peut porter `actionId` → chrono ciblé)
- `add_activity_action(activityId, title)` — crée une **action propre** (`Activity.ownActions`) sur une activité-temps, programmable ensuite via `schedule_day` (`activityId`+`actionId`)
- `link_action_to_activity(projectId, taskId, actionId, activityId)` — associe une sous-action de tâche à une activité-temps (`TaskAction.linkedActivityId`) → chrono ciblé. L'IA le **propose** quand une action n'est pas déjà liée et qu'une activité-temps du même domaine existe
- `plan_day(date?, startHour?, endHour?, syncToCalendar?)` — agrège user context + schedule existant + projets actifs en un appel ; retourne le contexte consolidé + workflow pour générer le programme et le syncer dans Google Calendar
- `plan_week(startDate?, syncToCalendar?)` — idem sur 5 jours ouvrés (défaut : lundi prochain)
- `sync_calendar(date?)` — lit le programme existant et retourne les instructions GCal précises (delete + create_event avec colorId et tag `source: productivitwo`)

**Vue Flutter** : `lib/widgets/daily_schedule_view.dart` dans l'onglet Maintenant.
Actions : tap checkbox → done, tap → éditer, swipe gauche → supprimer, long press → réordonner.

---

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

**Attention** : `executePushGantt` dans `execute.ts` doit toujours appeler `normalizeTasks()`
pour convertir les actions `string[]` en `TaskAction` maps — ne pas faire de spread direct `{ ...t }`.

---

## Pro / Entitlements & Accès web

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
flutter build web --release --no-tree-shake-icons
firebase deploy --only hosting
```

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
- **Édition structurelle directe autorisée** (le dogme « tout par l'IA » est levé pour la
  structure) : déplacer une tâche entre projets, une action entre tâches, promouvoir une
  action en sous-projet. Helpers centralisés dans `FirestoreSync` (`moveTaskToProject`,
  `moveActionToTask`, `promoteActionToSubproject`, `setProjectParent`) — réutilisés par les
  fiches tâche web (`gantt_screen.dart`) et mobile (`project_sheet.dart`). L'IA (Orion
  autonome) **propose**, l'utilisateur dispose ; le chemin MCP/conversation à la demande
  garde le write direct.

---

## Backlog mémorisé (demandes user, à faire plus tard)

- **Export / import des données** (noté 2026-07-19) : demandé par l'utilisateur, reporté volontairement — à cadrer avant d'implémenter (portée : backup complet JSON ? migration ? partage ?).
