# Handoff — Refonte de l'app web (septembre 2026)

Cible : `lib/web/` uniquement. Le mobile n'est pas concerné.
**Implémentation directe** : la nouvelle interface REMPLACE le shell actuel. Pas de route
`?proto=`, pas de flag. Une PR par lot (voir « Découpage en PR »), chacune mergeable seule.

Références visuelles : `design/*.dc.html` (prototypes HTML, thème sombre, 1440×900). Ce ne sont
**pas** des composants à copier : recréer en Flutter avec les patterns du dépôt (`ThemeData` de
`lib/web/web_app.dart`, helpers de `lib/utils/`, `FirestoreSync`). Aucun HTML/CSS dans l'app.
Les données affichées dans les prototypes sont fictives.

---

## 0. Tokens et règles visuelles

Identiques au handoff Espace coach (`docs/specs/espace-coach-design/README.md`, section
« Design tokens ») : c'est le **même thème** pour toute l'app web. Rappel des valeurs utilisées :

| Rôle | Hex |
|---|---|
| Fond écran | `#07100D` |
| Barre du haut | `#0A1611` |
| Surface carte | `#0C1C14` |
| Surface élevée | `#152B1E` · état actif/sélection `#12241B` + bordure `rgba(39,196,143,.35)` |
| Primaire | `#27C48F` · foncé `#1D9E75` |
| Texte | `#E8F3ED` · secondaire `#B9CFC4` · tertiaire `#86A093` · minimum `#6E8A7B` |
| Alerte / retard | `#FF6B5E` · attention / échéance proche `#F2A93B` |
| Filet | `rgba(255,255,255,.07)` |
| Catégories de blocs | project `#1D9E75` · routine `#E07B39` · personal `#5B8DEF` · break `#8E9AAF` |

- Police système, chiffres en `FontFeature.tabularFigures()`.
- Labels de section : 10 px, w700, `letterSpacing 1.3`, capitales, couleur `#86A093`.
- Cartes : rayon 20, `elevation 0`, bordure filet. Boutons : `StadiumBorder`, hauteur 40–46
  (primaire plein `#27C48F` sur texte `#07100D` ; secondaire `rgba(255,255,255,.07)`).
- Jamais d'`opacity` sur un bloc de texte : désaccentuer par la couleur.
- Pas d'emoji dans l'UI. Icônes Material outlined.
- **À retirer partout** : `kWebBuildTag` / `kBuildLabel` affichés à l'écran, la carte Vision
  « Passer en Pro » de Focus, le libellé « Arène » du chrono, la palette noir/or du panneau ORION.

---

## 1. Navigation

Barre du haut (64 px) : logo + « Productivitwo » · 5 onglets · à droite `ChronoLauncher`,
« Mon coach », menu ⋯, avatar.

| Onglet | Vue | Remplace |
|---|---|---|
| **Aujourd'hui** (arrivée) | § 2 | Focus (partie programme + retards) |
| **Cette semaine** | § 3 | Focus (grille 7 jours, modale 14 jours) |
| **Projets** | § 4 | Projets + cartes projets de Focus |
| **Actions** | § 5 | Actions (hub avec rail interne) |
| **Bibliothèque** | § 6 | Documents + Organisation |

Menu ⋯ (« Réglages, Claude & aide ») : Agent ORION (l'ancienne vue `_OrionView`, accessible mais
plus un onglet) · Messages ORION (`AssistantHistorySheet`) · Espace coach (si `_isCoach`) ·
Connecter Claude (`_TokensPanel`) · Aide · Déconnexion.

- Sidebar gauche : **supprimée**. Rail interne d'Actions : **supprimé**.
- Panneau ORION flottant (`GlobalAssistantOverlay`) : **supprimé**. Le message ORION prioritaire
  s'affiche dans le bandeau d'Aujourd'hui (§ 2.1) ; l'historique via le menu.
- Le Gantt hébergé dans le shell (`_shellGantt`) reste : il s'ouvre par-dessus la vue courante.
- Largeur < 1000 px : les colonnes s'empilent (ordre = ordre de lecture ci-dessous).
- `IndexedStack` conservé pour garder l'état des vues.

---

## 2. Aujourd'hui — `design/1-aujourdhui.dc.html`

Trois colonnes : `340 | 1fr | 340`.

### 2.1 En-tête
- Titre « Lundi 28 septembre », sous-titre « n blocs faits sur N · H planifiées restantes »
  (restant = somme des blocs `pending` dont la fin est > maintenant, tronqués à maintenant).
- **Bandeau ORION** (droite, pill 48 px) : `assistantMessagesNotifier.value.first` — texte sur une
  ligne, bouton primaire = `action.label` → `assistantActionHandler`, bouton « +n » / « Historique »
  → `AssistantHistorySheet.show`. Masqué si aucun message.

### 2.2 MAINTENANT (colonne gauche)
Source : `streamDailySchedule(today)` + `streamSessions()`.
- **Bloc focal** = premier bloc `pending` dont le créneau contient l'heure courante ; sinon le
  prochain bloc `pending` ; sinon état vide (« Plus rien au programme » / « Pas de programme »).
- Anneau 200 px (`CustomPainter`, trait 12) : progression = chrono ouvert (`Session.endAt == null`)
  si présent, sinon temps écoulé dans le créneau / durée du bloc. Centre : `mm:ss` ou `h:mm:ss`,
  sous-texte « chrono en cours » / « sur 1 h 30 · chrono arrêté » / « prochain bloc ».
- Sous l'anneau : projet ou activité (pastille catégorie), titre du bloc, « jusqu'à 12 h 00 ·
  ensuite <bloc suivant> ».
- Boutons selon l'état :
  - chrono ouvert + bloc en cours → **Terminer le bloc** (stop session + `updateBlockStatus done`)
    · Pause (stop session seul)
  - chrono ouvert sans bloc → **Arrêter le chrono**
  - pas de chrono, bloc chronométrable (`block.activityId ?? project.linkedActivityId` non null)
    → **Lancer le chrono** / **Commencer maintenant** (crée `Session(activityId, taskId, actionId)`,
    ferme les sessions ouvertes) · Fait
  - sinon → **Marquer comme fait**
- Cocher un bloc lié à une routine incrémente la routine **une fois par bloc, capé à la cible**
  (reprendre `_completeLinkedRoutine` de `daily_schedule_card.dart`).
- Pied de carte « LA JOURNÉE EN UN COUP D'ŒIL » : barre empilée des minutes par catégorie + légende.

### 2.3 PROGRAMME DU JOUR (centre) — frise horaire
- Axe vertical, de `min(premier bloc, maintenant)` à `max(dernier bloc, maintenant)` arrondis à
  l'heure. Échelle : remplit la hauteur, **jamais < 0,75 px/min** (au-delà, scroll).
- Un bloc = rectangle positionné à `startTime`, hauteur = `durationMin` × échelle (min 20 px).
  Fond = couleur catégorie à 13 % (7 % si fait) ; bloc en cours = fond `#12241B` + bordure primaire.
  < 40 px de haut : une ligne (coche · titre · durée). Sinon titre + « 10:30 → 12:00 · projet ».
- Coche = `updateBlockStatus` ; clic sur un bloc de projet = ouvre le Gantt sur `taskId`.
- Ligne « maintenant » rouge `#FF6B5E` avec point, mise à jour chaque minute.
- Lien « Modifier » → ouvre l'éditeur existant du programme.

### 2.4 Colonne droite
- **À TRAITER · n** : tâches `endDate < today`, non done/skipped, projets actifs non en pause, triées
  par échéance, 5 max + « + n autres ». Clic → Gantt sur la tâche. Lien « Replanifier ».
- **CETTE SEMAINE · 7 JOURS** : `rollingWeekEngagements` agrégé par domaine (done capé à target),
  barre couleur domaine + « done / target ».
- **PROCHAINES ÉCHÉANCES** : 3 projets actifs par `endDate` croissant, barre `done/total tâches`,
  date en `#F2A93B` si ≤ 7 jours. Clic → Gantt. Lien « Projets » → onglet Projets.

---

## 3. Cette semaine — `design/2-cette-semaine.dc.html`

Semaine calendaire Lun → Dim, navigable (‹ ›). Sous-titre : « n tâches actives · n faites ·
n à caser · H planifiées sur C ».

### 3.1 TÂCHES DE LA SEMAINE (Gantt, haut de page)
Reprend la grille 7 jours de Focus (`allPairs` groupées par domaine, `_dayLabels`) :
- Grille `250px | 7 colonnes`. En-tête : jour + numéro, aujourd'hui en primaire, week-end en `#6E8A7B`.
- Une ligne par tâche qui chevauche la semaine, sous son domaine (pastille + nom). Coche à gauche
  (`task.status`), titre, badge « retard » si en retard.
- Barre = intervalle `startDate → endDate` tronqué à la semaine, couleur du domaine :
  - **planifiée** (≥ 1 `ScheduleBlock` de la semaine avec ce `taskId`) : pleine, libellé
    « <projet> · n blocs planifiés » ;
  - **non planifiée** : pointillée, libellé « à caser » (rouge si en retard) ;
  - **faite** : fond couleur à 25 %, titre barré.
- Jalon (`isMilestone`) : losange + pill « Mer 30 » en `#F2A93B` sur son jour.
- Bouton « Vue 14 jours » → modale existante (`_showWideGanttModal`).

### 3.2 Organiser la semaine (bas de page) — `250px | 1fr`
- **À CASER · n** : tâches de la semaine (et en retard) sans bloc, retards en premier. Carte
  draggable : titre, « en retard · 30 min estimées » / « reste 1 h 30 · <projet> ».
  Estimation = `estimatedMin` de la tâche si présent, sinon **45 min par défaut** (voir § 8).
  Bouton « Tout caser automatiquement » : place chaque tâche au premier créneau libre du premier
  jour ≥ aujourd'hui non plein, dans l'ordre d'échéance.
- **7 colonnes jour** : en-tête jour + jauge `planifié / capacité` + texte « 3 h 10 / 7 h »
  (jauge `#F2A93B` + « journée bloquée » quand un bloc ≥ 6 h couvre la journée ; « repos » si
  capacité 0). Blocs du `DailySchedule` du jour en chips compactes (heure + titre, couleur
  catégorie, barré si fait, bloc en cours = bordure primaire). Zone « déposer ici » en bas.
- **Drop** d'une tâche sur un jour → `addScheduleBlock(date, ScheduleBlock(category: 'project',
  projectId, taskId, title: task.title, durationMin: estimation, startTime: premier créneau libre
  ≥ 8:00 hors blocs existants))`. Feedback snackbar « Bloc ajouté mardi 9 h 00 ».
  Drag d'une chip d'un jour à l'autre = suppression du bloc (`status: deleted`) + `addScheduleBlock` sur le jour cible à la même heure.
- **Capacité par jour** : nouvelle clé `meta.weekCapacityMin` (`Map<String,int>` par jour
  `mon..sun`, défaut 420 lun→ven, 0 sam/dim) — éditable par un petit dialog « Capacité »
  (icône ⚙ dans l'en-tête). Voir § 8.
- « Planifier la semaine avec ORION » → `orionWebhook` avec l'intention `plan_week` (même
  mécanique que le bouton « Déclencher » de la vue ORION).

---

## 4. Projets — `design/3-projets.dc.html`

### 4.1 En-tête
Titre, sous-titre « n actifs · n à risque · n sans prochaine action », recherche (filtre titre de
projet **et** titre de tâche, insensible à la casse, < 200 ms), bouton **Nouveau projet** (crée un
`Project` vide `status: active` puis ouvre le Gantt — ce bouton n'existe pas aujourd'hui sur le web).

### 4.2 Carte OBJECTIF
Premier `StrategicObjective` actif : libellé, projets liés, barre `computeObjectiveProgress` (`utils/objective_progress.dart`), « 3 / 5 · J-3 ».
Clic → `ObjectiveEditSheet`. Masquée s'il n'y a aucun objectif.

### 4.3 Filtres
Chips domaine (« Tous » + un par domaine, pastille couleur). À droite, liens discrets
« En veille · n » et « Archivés · n » qui basculent la liste sur ces statuts (mêmes actions
qu'aujourd'hui : Réactiver / Supprimer / Restaurer).

### 4.4 Tableau des projets actifs
Colonnes `290 | 170 | 1fr | 110 | 130 | 80`, ligne 76 px, clic sur la ligne → § 4.5 :
- **Projet** : titre + « <domaine> · phase <phase en cours> » (phase courante = phase contenant
  aujourd'hui, sinon « sans phase »).
- **Avancement** : barre + « done / total tâches » (hors `skipped`).
- **Prochaine action** : première `TaskAction` non faite de la première tâche non faite (ordre
  Gantt), coche directe (`action.done = true` + `saveProjectTasks`), sous-texte « tâche en retard depuis le 25/09 » ou
  « planifiée demain 9 h » (bloc de la semaine lié) ou « <tâche> ». Si aucune action ouverte →
  bouton pointillé **Définir la prochaine action** (dialog existant (`_quickAddAction` de `web_actions_view.dart`)).
- **Échéance** : `endDate` + « J-n » (`#F2A93B` si ≤ 7 j, `#FF6B5E` si dépassée, « — » si null).
- **État** (pill, calculé) :
  - `Au point mort · n j` (`#FF6B5E`) : aucune session ni action faite depuis ≥ 7 jours
  - `À risque · n retards` (`#F2A93B`) : ≥ 1 tâche en retard, ou échéance ≤ 7 j avec < 70 % fait
  - `Sans échéance` (neutre) : `endDate == null`
  - `Dans les temps` (`#27C48F`) sinon
- **7 jours** : minutes des `Session` des 7 derniers jours dont `taskId` ∈ tâches du projet, ou
  `activityId == project.linkedActivityId`.

### 4.5 Fiche projet — `design/4-projet-plan-action.dc.html`
Nouvelle vue qui s'ouvre **à la place du Gantt**, dans le shell. Le Gantt et le Document deviennent
les onglets 2 et 3 d'un segmented control « Plan d'action · Gantt · Document » (Gantt = `GanttScreen`
existant, Document = `ProjectDocView`).
- Fil d'Ariane « ‹ Projets », titre, « <domaine> · 14 sept. → 3 oct. », bouton **Ajouter une tâche**
  (dialog existant du Gantt).
- 4 tuiles : AVANCEMENT (`14 / 22 · 64 %`) · EN RETARD (n + « la plus vieille le … ») ·
  TEMPS · 7 JOURS (« 6 h 40 sur 4 sessions ») · PROCHAIN JALON · J-n (bordure `#F2A93B`).
- **PLAN D'ACTION** (`1fr`) : une section par phase (ordre `startDate`), pliable. Phase courante
  dépliée, les autres repliées avec « done / total · terminée / 1 en retard / dates ».
  Dans la phase : une carte par tâche non faite (titre, échéance ou « aujourd'hui · 10 h 30 » si
  un bloc du jour la vise, badge retard, bouton **Planifier** → ajoute un bloc comme § 3.2 sur le
  prochain jour non plein), puis ses actions à cocher avec leurs contextes. Bouton « Masquer le
  fait » (toggle, mémorisé en session).
- Colonne droite (360) : **CETTE SEMAINE DANS MON PROGRAMME** (blocs de la semaine liés au projet,
  + « n tâches du projet ne sont pas encore planifiées ») · **JALONS** (losange plein si fait,
  ambre si ≤ 7 j) · **DOCUMENTS** (3 derniers documents du projet, lien « Tout voir » →
  Bibliothèque filtrée).

---

## 5. Actions — `design/5-actions.dc.html`

Trois colonnes `250 | 1fr | 340`. Le rail interne (`ActionsHubView`) disparaît.

### 5.1 Filtres (gauche) — tous cumulatifs, persistés en `SharedPreferences` web
- **JE SUIS…** : chips des contextes (`kDefaultGtdContexts` ∪ contextes rencontrés). Multi-sélection.
  Une action passe le filtre si `action.allContexts ∩ sélection ≠ ∅` ou si elle n'a aucun contexte.
- **J'AI…** : 15 min / 1 h / Plus. Filtre sur `estimatedMin` de l'action (voir § 8) ; une action
  sans estimation passe toujours.
- **DOMAINE** : Tous + un par domaine, avec compteur.
- Bouton **Action simple** (dialog existant), lien « En pause · n » (bascule la liste sur les projets
  `paused`, avec « Reprendre »).

### 5.2 Liste (centre)
- **POSSIBLE MAINTENANT** (carte bordure primaire, visible seulement si un chrono est ouvert) :
  actions dont `linkedActivityId == session.activityId`, ou dont le projet a
  `linkedActivityId == session.activityId`. Titre « … · CHRONO « <activité> » EN COURS ».
- **PAR PROJET · PROCHAINE ACTION EN TÊTE** : un groupe par projet actif non en pause (tri par
  échéance, bouton « Trier » : échéance / domaine / alphabétique). Ligne projet : pastille
  domaine, titre, « J-n », lien « Ouvrir » (→ § 4.5). Première ligne = **prochaine action** (fond
  `rgba(255,255,255,.03)`, w600, hauteur 42), puis les autres actions ouvertes (hauteur 38, texte
  secondaire), 3 max + « + n autres actions » (déplie). Menu ⋯ = actions existantes (éditer,
  monter/descendre, déplacer vers une autre tâche, supprimer).
  Projet sans action ouverte → **Définir la prochaine action** + « Sans action, le projet n'avance pas. »
- **Actions simples** : `Activity.ownActions` non faites, groupe gris en fin de liste.

### 5.3 Colonne droite
- **MES ENGAGEMENTS · 7 JOURS** : contenu de l'ancien « Ma semaine » condensé :
  `kept / total` en 26 px, delta « +12 pts vs S-1 » (`fourWeekTrend`), une ligne par engagement
  (`rollingWeekEngagements`, « 7 / 7 » en primaire si tenu), mini-barres S-3 → 7 j.
- **ROUTINES DU JOUR** : routines `habitFreq == daily` non atteintes aujourd'hui en premier, coche =
  `incHabit` + persistance (même code que § 2.2), heure du bloc du jour lié si présent.

---

## 6. Bibliothèque

Vue simple : deux pills « Documents » / « Organisation » en haut, `IndexedStack` des vues existantes
`_DocumentsView` et `_ArchivesView`, **inchangées** dans ce lot (elles seront reprises plus tard).
Accepte un filtre `projectId` en entrée (lien « Tout voir » de la fiche projet).

---

## 7. Ce qui est supprimé

| Élément | Fichier | Sort |
|---|---|---|
| `_FocusView` + `_SidebarCard`, cartes projets, carte Vision | `web_home_screen.dart` | supprimés après livraison des lots 1–2 |
| `_sidebar` / `_navTile` | `web_home_screen.dart` | supprimés (lot 1) |
| `ActionsHubView` (rail Actions / Ma semaine / domaines) | `coachee_dashboard_view.dart` | supprimé (lot 5) ; la vue par domaine repart dans une itération ultérieure |
| `GlobalAssistantOverlay` + `AssistantOverlay` | `assistant_widget.dart` | supprimés (lot 1) ; garder `assistantMessagesNotifier` / `assistantActionHandler` |
| `_OrionView` comme onglet | `web_home_screen.dart` | déplacée derrière le menu ⋯ (route plein écran) |
| Tampon `kWebBuildTag` / `kBuildLabel` à l'écran | `web_app.dart`, `web_home_screen.dart` | retirés de l'UI (garder le `debugPrint` au démarrage) |
| Routes `?softpop=…` et `MobilePreviewScreen` sur `?softpop=app` | `web_app.dart` | inchangées (hors périmètre) |

`web_home_screen.dart` fait 6 600 lignes : **sortir chaque vue dans son fichier** au fur et à mesure
(`lib/web/views/today_view.dart`, `week_view.dart`, `projects_view.dart`, `project_plan_view.dart`,
`actions_view.dart`, `library_view.dart`, `web_shell.dart`). Logique pure et testable dans
`lib/utils/` (`project_health.dart`, `week_planner.dart`).

---

## 8. Données : ce qui manque au modèle

Ajouts **rétrocompatibles** (absent = comportement par défaut), à faire dans le lot 0 :

| Champ | Où | Défaut | Usage |
|---|---|---|---|
| `estimatedMin: int?` | `ProjectTask` | null → 45 | § 3.2 « à caser », § 4.5 « Planifier » |
| `estimatedMin: int?` | `TaskAction` | null → passe tous les filtres | § 5.1 « J'ai… » |
| `weekCapacityMin: Map<String,int>` | `users/{uid}/meta` (doc `settings`) | mon–fri 420, sat–sun 0 | § 3.2 jauges |

Exposer `estimatedMin` dans `push_gantt` / `update_task` (MCP) : ajouter la clé dans `tools.ts` +
`normalizeTasks()`. Pas d'autre changement backend.

---

## 9. Découpage en PR (une fonctionnalité par PR, depuis `origin/main` à jour)

0. **Modèle** — `estimatedMin` (tâche, action), `weekCapacityMin`, exposition MCP. Tests unitaires.
1. **Shell** — barre du haut à 5 onglets, menu ⋯, suppression sidebar / overlay ORION / build tag ;
   les onglets pointent provisoirement sur les vues existantes (Focus sous « Aujourd'hui », Focus
   aussi sous « Cette semaine », Documents+Organisation sous « Bibliothèque »).
2. **Aujourd'hui** — `today_view.dart` (§ 2). Retire `_FocusView`.
3. **Cette semaine** — `week_view.dart` + `week_planner.dart` (§ 3), drag & drop, capacité.
4. **Projets** — tableau (§ 4.1–4.4) + `project_health.dart`, bouton Nouveau projet.
5. **Fiche projet** — `project_plan_view.dart` + segmented Plan / Gantt / Document (§ 4.5).
6. **Actions** — `actions_view.dart` (§ 5). Retire `ActionsHubView`.
7. **Nettoyage** — code mort restant, extraction des dernières vues, `flutter analyze` propre.

Critères communs : `flutter analyze` sans warning sur `lib/web/` · aucune régression sur le Gantt,
le chrono global, le mode démo (`?demo=true`) et la console coach · largeur 1000 px et 1440 px
vérifiées · interface 100 % français.

---

## 10. Décisions déjà prises (ne pas rouvrir)

- Thème vert sombre unique, aligné sur l'Espace coach. Pas de mode clair.
- Focus n'est pas conservé comme onglet : son contenu est réparti entre Aujourd'hui, Cette semaine
  et Projets.
- ORION : une seule entrée visible (bandeau d'Aujourd'hui) ; le reste derrière le menu.
- Drop d'une tâche sur un jour = bloc au premier créneau libre, modifiable ensuite dans Aujourd'hui.
- Capacité par jour = réglage simple par jour de semaine, pas déduite des `DayBlock`.
- Documents et Organisation ne sont pas redessinés dans ce lot.
