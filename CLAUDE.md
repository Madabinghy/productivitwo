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
├── models.dart          — tous les modèles de données (AppState, DayPlanItem, Activity…)
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
```

---

## Modèles clés (`models.dart`)

| Classe | Collection Firestore | Notes |
|--------|----------------------|-------|
| `Domain` | `domains` | Domaine de vie (Santé, Travail…) |
| `Activity` | `activities` | Tracking temps (`type: time`) ou fréquence (`type: habit`) |
| `RecurringAction` | `recurringActions` | Tâche récurrente sans tracking |
| `DayPlanItem` | `dayPlan` | Action planifiée pour un jour (`yyyymmdd` format YYYYMMDD) |
| `DayBlock` | `blocks` | Blocs de journée (Matin, Midi, Soir…) |
| `Goal` | `goals` | Objectif GTD avec actions |
| `Session` | `sessions` | Session de temps loggué |
| `HabitHit` | `habitHits` | Incrément de routine |
| `Project` | `projects` | Projet Gantt (phases + tasks embarquées) |
| `StrategicObjective` | `strategic_objectives` | Objectif lié à un projet Gantt |
| `Document` | `documents` | Programmes HTML, briefs, livrables |
| `ApiToken` | `api_tokens` | Tokens Bearer pour le MCP |
| `AssistantMessage` | `assistant_messages` | Messages planifiés de l'assistant IA |

Structure Firestore : `users/{uid}/{collection}/{id}` — toujours.

---

## Suppression : soft-delete partout

Ne jamais faire `delete()` direct sauf cas explicite.
Utiliser `deleted: true` (domaines, activités, routines) ou `archived: true / status: archived` (dayPlan).
`FirestoreSync` merge par ID — un doc absent côté Firestore ne supprime rien côté local.

---

## Cloud Functions (`functions/src/index.ts`)

4 exports :

| Fonction | URL | Usage |
|----------|-----|-------|
| `pushGantt` | `https://pushgantt-dzos75b65q-uc.a.run.app` | HTTP endpoint pour le MCP local |
| `pushAssistantMessage` | `https://pushassistantmessage-dzos75b65q-uc.a.run.app` | HTTP endpoint pour le MCP local |
| `getCustomToken` | `https://getcustomtoken-dzos75b65q-uc.a.run.app` | Auth web via token API |
| `mcpHandler` | `https://mcphandler-dzos75b65q-uc.a.run.app` | MCP remote JSON-RPC (claude.ai) |

**Ajouter un outil MCP** = 4 étapes dans `index.ts` :
1. Définir `CONST_TOOL` (inputSchema)
2. Écrire `executeXxx()` async
3. Ajouter dans `tools/list` (tableau dans `mcpHandler`)
4. Ajouter le `else if` dans `tools/call`

Après modification : `npm run build` dans `functions/`, puis `firebase deploy --only functions`.

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

**Status cycle** : `pending` → `shown` → `dismissed` | `expired`

---

## App web (`lib/web/`)

Compilée séparément du mobile. Accès via token API + `getCustomToken`.
Affiche : projets Gantt, documents HTML, assistant IA (à venir).

**Build + deploy web :**
```
flutter build web --release --no-tree-shake-icons
firebase deploy --only hosting
```

---

## Conventions de code

- Pas de commentaires sauf invariant non-évident
- Soft-delete systématique (jamais de `delete()` direct sur domains/activities/recurringActions)
- `yyyymmdd` = string `"20260521"` (pas de tirets) pour les dates de plan
- `YYYY-MM-DD` = format ISO pour tout le reste (projets, sessions, MCP)
- Les documents HTML sont toujours liés à `projectId` + `taskId` quand applicable
- `activityId` obligatoire sur toute routine/action récurrente
