# Handoff — iOS : fusion des onglets « Aujourd'hui » et « Maintenant »

Périmètre : app mobile (`lib/main.dart`, `lib/widgets/today_view.dart`,
`lib/widgets/focus_view.dart`, `lib/widgets/daily_schedule_view.dart`). Le web n'est pas concerné.
Écrit sur `origin/main` au commit `d8478fc`. Implémentation directe, en **3 PR** (§ 6).

Référence visuelle : `design/aujourdhui-ios.dc.html` (390×844, thème sombre, données fictives).
À recréer en Flutter. **Pas de faux status bar** : la maquette laisse l'espace vide en haut.

## 1. Objectif

Aligner l'iPhone sur ce que le web fait depuis la refonte : **un seul onglet « Aujourd'hui »**
= la carte MAINTENANT (bloc en cours + chrono) en tête, puis le programme du jour, puis les
retards. L'onglet « Maintenant » disparaît de la barre. La barre passe de 6 à **5 onglets** :
Objectifs · Stats · Projets · Aujourd'hui · Actions (4 quand `hideProjectsTab`).

Réutiliser la logique partagée déjà en place : `lib/utils/today_logic.dart` (`focusBlock`,
`nextBlockAfter`, `remainingPlannedMin`, `minutesByCategory`), `week_planner.dart`
(`firstFreeSlot`), `project_health.dart`. **Aucune nouvelle logique métier** dans les widgets.

## 2. Ce qui est conservé, déplacé, supprimé

| Aujourd'hui | Sort |
|---|---|
| `FocusView` état 1 (session en cours : chrono / minuteur + checklists sous-actions, actions propres, checklist routine liée) | **conservé**, devient le contenu **déplié** de la carte MAINTENANT (§ 3.2) |
| `FocusView` état 2 (une carte focus bloc en cours / prochain, ▶ ✓) | **remplacé** par la carte MAINTENANT (même données via `focusBlock`) |
| `FocusView` état 3 (« Que souhaites-tu faire maintenant ? » routines / activités) | **conservé** comme état vide de la carte |
| Cartes ORION / coach moments / état d'énergie de `FocusView` (`coach_moment_card`, `energy_cards`) | **conservées**, rendues sous la carte MAINTENANT, mêmes conditions d'affichage |
| Défi ORION (`onChallenge`, `onChallengeAccept`, `onChallengeSchedule`) | **conservé**, accessible depuis l'état vide et le bouton ORION de l'en-tête |
| `TodayView` : programme du jour (`DailyScheduleView`), planif du lendemain, revue du soir | **conservés** tels quels, sous la carte |
| Onglet `_Tab.maintenant` | **supprimé** ; toutes les navigations `_tab = _Tab.maintenant` (widget, Siri, notifications, `onStartTimed`, `_launchScheduledBlock`…) pointent sur `_Tab.aujourdhui` et font défiler en haut |
| Réglage `hideProjectsTab` | inchangé |

## 3. Layout — `design/aujourdhui-ios.dc.html`

Page = `CustomScrollView` / `ListView` avec padding 16, sous la vraie barre système.

### 3.1 En-tête
« Lundi 28 » (24 px w700) + « 3 / 9 blocs · 6 h 15 restantes » (13 px `#86A093`,
`remainingPlannedMin`). À droite, deux boutons ronds **44 px** : **Chrono libre** (ouvre le
sélecteur d'activité existant `_showLaunchActivitySheet`) et **ORION** (badge = nombre de messages
en attente ; ouvre l'écran ORION existant `orion_screen.dart`).

### 3.2 Carte MAINTENANT (bordure `kBPrimary .3`, rayon 20, padding 16/18)
Label « MAINTENANT » + point vert ; à droite « jusqu'à 12 h 00 ».
- **Anneau 96 px** (réutiliser `ring_painter.dart`, trait 9) : progression = session ouverte si
  présente (`logic` : chrono ou minuteur `_countdownEndsAt`), sinon temps écoulé dans le créneau
  du bloc focal ; centre = `mm:ss` 19 px w700. Sans bloc ni session : l'heure de début du prochain
  bloc.
- À droite : projet ou activité (pastille catégorie, 12 px), **titre du bloc 17 px w600** (2 lignes
  max), « Ensuite · <bloc suivant> » (`nextBlockAfter`).
- **Boutons 48 px** selon l'état (mêmes règles que le web, `today_view.dart` web comme référence) :
  - session ouverte + bloc en cours → **Terminer** (primaire : stop session + bloc `done` +
    routine liée) · **Pause** (stop session) · **›** (ouvre la source : `_openBlockSource`)
  - session ouverte sans bloc → **Arrêter** · **›**
  - pas de session, bloc chronométrable → **Lancer** (`_launchScheduledBlock`, primaire) · **Fait** · **›**
  - pas de session, bloc non chronométrable → **Marquer fait** (primaire) · **›**
  - aucun bloc restant → état 3 de `FocusView` (« Que souhaites-tu faire maintenant ? » + Mes
    routines / Mes activités / Défi ORION), dans la carte.
- **Déplié** : quand une session est ouverte, un chevron sous les boutons déplie les checklists
  de l'état 1 (sous-actions de la tâche, actions propres, checklist de la routine liée) — le code
  existant de `FocusView`, sans changement de comportement. Replié par défaut ; l'état est mémorisé
  le temps de la session.
- Cocher un bloc lié à une routine : même règle que `daily_schedule_view.dart` (1 incrément, capé,
  1× par bloc).

### 3.3 PROGRAMME DU JOUR
Label + liens **Demain** (planif du lendemain existante de `TodayView`) et **Modifier**
(`showPlanNextSheet` / éditeur existant). Puis `DailyScheduleView` **en mode liste** (pas la frise
`DayTimelineView`) : ligne **48 px min**, heure 13 px, coche 24 px (`updateBlockStatus`), pastille
catégorie 8 px, titre 15 px, durée 12 px à droite. Bloc en cours : fond `#12241B`, bordure
`kBPrimary .35`, heure en primaire w700, coche cerclée de primaire (2026-10 : le point vert seul ne se lisait pas comme une coche). Fait : titre barré
`#86A093`. Swipe gauche = supprimer, long press = réordonner, tap = éditer (existant).
Le toggle liste / frise de `TodayView` (`_timelinePrefKey`) reste disponible via un bouton en fin
de section (« Voir en frise »).

### 3.4 À TRAITER · n
Carte rayon 16 : tâches en retard (même calcul que le web : `endDate < today`, non done/skipped,
projets actifs non en pause), 3 max + « + n autres », date en `kBAlert`. Tap → `project_sheet`
sur la tâche. Lien **Replanifier** → `showPlanNextSheet`. Masquée si vide.

### 3.5 Sous la carte, dans l'ordre, quand ils s'affichent
Carte coach moment · cartes d'énergie · brief ORION (`orion_brief_card`) — conditions inchangées.

### 3.6 Barre d'onglets
`BottomNavigationBar` 5 items : Objectifs (`track_changes_outlined`) · Stats (`query_stats`) ·
Projets (`account_tree_outlined`) · **Aujourd'hui** (icône soleil `wb_sunny_outlined`) · Actions
(`checklist_rtl_outlined`). Onglet d'arrivée : Aujourd'hui. Supprimer `_Tab.maintenant` de l'enum,
de `_visibleTabs` et de `_tabIndex`.

## 4. Thème

Le mobile suit `ThemeMode.system` avec `colorSchemeSeed: Colors.teal`. Ce lot **n'impose pas** le
sombre : les valeurs de la maquette sont les jetons du web (`lib/web/theme_tokens.dart`) et
servent au **mode sombre** ; en mode clair, mapper sur le `ColorScheme` (surface, primary,
onSurface .6 / .85) sans hex en dur. Décision « sombre uniquement sur mobile » : hors périmètre,
à trancher plus tard.

Constantes : cibles tactiles ≥ 44 px, chiffres `tabularFigures`, pas d'emoji dans l'UI (les
emojis des snackbars existantes peuvent rester), pas d'`opacity` sur du texte.

## 5. Ce qu'il ne faut PAS faire

- Ne pas réécrire `FocusView` : extraire ses états 1 et 3 en widgets (`NowSessionPanel`,
  `NowEmptyPanel`) et les monter dans la nouvelle carte ; supprimer le reste du fichier à la fin.
- Ne pas toucher aux widgets iOS (`widget_service.dart`), à Siri ni aux Live Activities, sauf le
  retour d'onglet (`_Tab.maintenant` → `_Tab.aujourdhui`).
- Ne pas dupliquer `focusBlock` / `remainingPlannedMin` : importer `today_logic.dart`.
- Pas de faux status bar, pas de clavier dessiné.

## 6. Découpage en PR

1. **Carte MAINTENANT** — `lib/widgets/now_card.dart` (+ `NowSessionPanel`, `NowEmptyPanel`
   extraits de `FocusView`), montée en tête de `TodayView`. L'onglet Maintenant existe encore.
2. **Onglet unique** — retrait de `_Tab.maintenant`, barre à 5, redirections, en-tête (§ 3.1),
   « À traiter » (§ 3.4), cartes coach / énergie / brief sous la carte. Suppression de
   `focus_view.dart` (garder les panels extraits).
3. **Programme en liste 48 px** — restyle de `DailyScheduleView` (§ 3.3), bouton « Voir en frise ».

Critères : `flutter analyze` propre ; tests existants verts ; build iOS Xcode Cloud OK ; vérifié
sur iPhone SE (375 px) et iPhone 15 Pro Max ; aucune régression sur les widgets, Siri, le chrono,
le mode clair.

## 7. Décisions prises (ne pas rouvrir)

- Un seul onglet Aujourd'hui, carte Maintenant en tête : même lecture que le web.
- Les checklists de session restent, dépliables dans la carte.
- Objectifs et Stats ne changent pas dans ce lot.
- Le mode clair n'est pas supprimé ici.
