# Productivitwo — CLAUDE.md

Application de productivité Flutter (iOS/Android/Web). Backend Firebase.
Langue du code : anglais. Langue des commentaires et UI : français.

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
| `Activity` | `activities` | Tracking temps (`type: time`) ou fréquence (`type: habit`) |
| `RecurringAction` | `recurringActions` | Tâche récurrente sans tracking |
| `DayBlock` | `blocks` | Blocs de journée (Matin, Midi, Soir…) |
| `Goal` | `goals` | Objectif GTD avec actions |
| `Session` | `sessions` | Session de temps loggué |
| `HabitHit` | `habitHits` | Incrément de routine |
| `Project` | `projects` | Projet Gantt (phases + tasks embarquées) |
| `StrategicObjective` | `strategic_objectives` | Objectif lié à un projet Gantt |
| `Document` | `documents` | Programmes HTML, briefs, livrables |
| `ApiToken` | `api_tokens` | Tokens Bearer pour le MCP |
| `AssistantMessage` | `assistant_messages` | Messages planifiés de l'assistant IA |
| `ScheduleBlock` + `DailySchedule` | `daily_schedules` | Programme horaire journalier (voir ci-dessous) |

Structure Firestore : `users/{uid}/{collection}/{id}` — toujours.
Exception `daily_schedules` : doc unique par jour — `users/{uid}/daily_schedules/{YYYY-MM-DD}`.

> **`DayPlanItem` supprimé** — le modèle Flutter et toute la logique associée ont été retirés.
> La collection Firestore `dayPlan` et les outils MCP `plan_day` / `get_day_plan` /
> `add_to_day_plan` / `clear_day_plan` restent déployés mais **aucune vue Flutter ne les lit**.
> Ne pas recréer de logique autour de `DayPlanItem`. Le scheduling est désormais géré par
> `DailySchedule` + l'outil MCP `schedule_day`.

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
  projectId?, taskId?, activityId?,   ← liens vers les objets existants
  status: "pending" | "done" | "skipped" | "deleted",
  doneAt?
}
```

**Soft-delete des blocs** : swipe dans l'app → `status: "deleted"` (jamais retiré du tableau).
`get_day_schedule` affiche les blocs supprimés avec `❌ [supprimé — ne pas recréer]` pour que
Claude ne les recrée pas lors d'une régénération.

**Outils MCP** :
- `get_day_schedule(date)` — lit le programme du jour
- `schedule_day(date, blocks[])` — crée ou remplace le programme entier

**Vue Flutter** : `lib/widgets/daily_schedule_view.dart` dans l'onglet Maintenant.
Actions : tap checkbox → done, tap → éditer, swipe gauche → supprimer, long press → réordonner.

---

## Suppression : soft-delete partout

Ne jamais faire `delete()` direct sauf cas explicite.
Utiliser `deleted: true` (domaines, activités, routines) ou `status: archived/deleted`.
`FirestoreSync` merge par ID — un doc absent côté Firestore ne supprime rien côté local.

---

## Cloud Functions (`functions/src/index.ts`)

4 exports HTTP :

| Fonction | URL | Usage |
|----------|-----|-------|
| `pushGantt` | `https://pushgantt-dzos75b65q-uc.a.run.app` | HTTP endpoint pour le MCP local |
| `pushAssistantMessage` | `https://pushassistantmessage-dzos75b65q-uc.a.run.app` | HTTP endpoint pour le MCP local |
| `getCustomToken` | `https://getcustomtoken-dzos75b65q-uc.a.run.app` | Auth web via token API |
| `mcpHandler` | `https://mcphandler-dzos75b65q-uc.a.run.app` | MCP remote JSON-RPC (claude.ai) |

**Ajouter un outil MCP** = 4 étapes :
1. Définir `CONST_TOOL` dans `tools.ts` (inputSchema)
2. Écrire `executeXxx()` async dans `execute.ts` + l'ajouter au bloc `export {}`
3. Ajouter dans `tools/list` (tableau dans `mcpHandler` — `index.ts`)
4. Ajouter le `else if` dans `tools/call` (`index.ts`) + importer depuis `execute.ts`

Après modification : `npm run build` dans `functions/`, puis `firebase deploy --only functions`.

**Attention** : `executePushGantt` dans `execute.ts` doit toujours appeler `normalizeTasks()`
pour convertir les actions `string[]` en `TaskAction` maps — ne pas faire de spread direct `{ ...t }`.

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
> Ils retournent `false` systématiquement dans `assistant_engine.dart`.

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

## Conventions de code

- Pas de commentaires sauf invariant non-évident
- Soft-delete systématique (jamais de `delete()` direct sur domains/activities/recurringActions)
- `YYYY-MM-DD` = format ISO pour tout (projets, sessions, MCP)
- Les documents HTML sont toujours liés à `projectId` + `taskId` quand applicable
- `activityId` obligatoire sur toute routine/action récurrente
- Les actions de tâches Gantt (`ProjectTask.actions`) sont des `TaskAction` maps en Firestore —
  `ProjectTask.from()` gère les deux formats (string et map) pour compatibilité ascendante
