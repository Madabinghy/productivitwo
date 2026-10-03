# Handoff — Onglet « Cette semaine » (app web)

> **Complément 2026-10** : la colonne des tâches passe de 320 à **400 px par défaut** et se **redimensionne à la
> souris** (poignée `ColumnResizeHandle` de `lib/web/column_resizer.dart`, 220–640 px, double-clic = défaut),
> largeur persistée (`week_left_col`).
>
> **Correctif 2026-10 — blocs de nuit** : la charge d'un jour (`plannedMin`) et la règle « journée bloquée »
> (`isBlockedDay`, ≥ 6 h) ne comptent que la part des blocs dans la **journée active 8 h – 22 h**
> (`activeMin`, `lib/utils/week_planner.dart`). Un bloc de sommeil 23 h → 7 h ne bloque plus la journée et ne
> remplit plus la jauge ; une formation 9 h → 17 h la bloque toujours. La fenêtre est **réglable** (dialog
> « Capacité par jour et journée active », bouton ⚙ de Cette semaine) : `DayWindow` dans
> `utils/week_capacity.dart`, stockée dans `data/meta.dayWindow {startMin, endMin}` (au moins 4 h d'écart,
> 0 h – 24 h). Un lève-tôt met 4 h → 20 h : ses blocs de 4 h comptent, sa nuit 20 h → 4 h non. Les créneaux
> proposés (« Caser », placement auto) partent du début de la fenêtre et s'arrêtent 2 h avant sa fin ; côté
> serveur, `plan_day` prend ses heures par défaut dans cette fenêtre (`readDayWindowHours`).

Périmètre : **uniquement** la vue de l'onglet « Cette semaine » de l'app web (`lib/web/`).
Ce handoff remplace la section 3 du handoff `refonte-web-2026-09` — si une première version de
la vue existe déjà, la reprendre ; sinon la créer. Implémentation directe, pas de route `?proto=`.

Référence visuelle : `design/cette-semaine.dc.html` (prototype HTML, thème sombre, 1440×900).
À recréer en Flutter avec les patterns du dépôt, pas à copier. Données fictives.

Avant de coder : `git fetch origin main`, brancher depuis `origin/main`, puis **lire l'état actuel**
de `lib/web/` (shell, onglets, vues déjà extraites) et adapter les noms cités ici aux noms
actuels — le code a bougé depuis la rédaction. Ne rien recréer qui existe.

---

## 1. Principe

C'est le **Gantt 7 jours de l'ancien onglet Focus** (`_FocusView` : groupes par domaine, barres
colorées, colonne « aujourd'hui » surlignée, jalons ◆, clic = fiche tâche, clic droit = couleur),
mis en pleine page et enrichi pour **organiser la semaine sans quitter la grille** :

1. chaque barre affiche les blocs du programme qui la concernent ;
2. une tâche sans bloc (ou en retard) est une barre pointillée « à caser » ;
3. un clic sur un jour de la ligne crée un bloc dans le `DailySchedule` de ce jour ;
4. l'en-tête de chaque jour montre la charge planifiée / capacité.

Pas de panneau latéral, pas de liste séparée : tout se lit et se manipule dans le Gantt.

---

## 2. Layout — `design/cette-semaine.dc.html`

Sous la barre du haut du shell :

**En-tête de page** (ligne unique) : ‹ › navigation de semaine · titre « Semaine du 28 septembre »
+ sous-titre « 3 / 9 tâches actives faites · 2 en retard · 3 à caser » · segmented **7 jours /
14 jours** (remplace la modale `_showWideGanttModal`) · bouton « Masquer le fait » (toggle) ·
bouton « Planifier avec ORION ».

**Carte Gantt** (rayon 20, remplit la hauteur restante, scroll vertical interne) :

- Grille `320px | 7 × 1fr` (14 jours : `320px | 14 × 1fr`, même logique).
- **En-tête jours** : « Lun 28 » (aujourd'hui en primaire sur fond `rgba(39,196,143,.1)`,
  week-end en `#6E8A7B`), jauge 4 px, texte 11 px « 3 h 10 / 7 h · 3 blocs ». Jauge ambre + « journée
  bloquée » si un bloc ≥ 6 h couvre la journée ; « repos » si capacité 0.
- **Fond** : colonne aujourd'hui dégradé `rgba(39,196,143,.13) → .05` bordé `.25` ; séparateurs
  verticaux `rgba(255,255,255,.06)` ; week-end `rgba(255,255,255,.015)`.
- **En-tête de domaine** (24 px, fond couleur domaine à 10 %) : pastille, NOM en 11 px w700
  couleur domaine, puis « · 2 / 6 faites · 12 h 40 planifiées ». Clic = replie le domaine.
- **Ligne tâche** (40 px) : colonne gauche = titre **14 px, 2 lignes max** (`maxLines: 2`),
  précédé d'une coche verte si fait (titre en `#86A093`) ; à droite du titre, compteur d'actions
  « 2/3 » (12 px `#86A093`) ou badge « −3 j » (11 px w700, fond `rgba(255,107,94,.18)`, texte
  `#FF6B5E`) ou « jalon » (`#F2A93B`).
- **Barre** (24 px, rayon 6, marge 3 px) : `startDate → endDate` tronqué à la fenêtre, couleur =
  `task.color ?? phase.color ?? domaine`, opacité **.75** (faite : **.35**, titre barré). Contenu :
  un **point 6 px + durée** par bloc de la semaine lié à la tâche (`ScheduleBlock.taskId ==
  task.id`), ex. « ● 1 h 30  ● 1 h ». S'il reste du temps estimé non couvert : « reste 1 h 30 à
  caser » en `rgba(7,16,13,.6)`. Poignée 6 px à droite (`cursor: ew-resize`).
- **Barre « à caser »** : tâche non faite **sans bloc** dans la fenêtre → pointillé 1,5 px couleur
  domaine (**`#FF6B5E` si en retard**), texte « à caser · 30 min ». Positionnée sur son
  `startDate` (aujourd'hui si passé), largeur 1 jour. Les cellules suivantes de la ligne montrent
  un « + » discret au survol.
- **Jalon** : losange 12 px `#F2A93B` (vert si fait) centré sur son jour, pas de barre.
- **Pied de carte** : légende (tâche prévue · bloc dans le programme · à caser · jalon) et rappel
  « Clic sur un jour = caser · glisser une barre = déplacer · tirer le bord = étendre · clic droit
  = couleur ».

---

## 3. Interactions

| Geste | Effet |
|---|---|
| Clic sur le **titre** | `showGanttTaskDetailDialog` (fiche tâche existante) |
| Clic sur une **cellule jour** de la ligne (barre ou vide) | **Popover** (250 px, fond `#152B1E`, bordure primaire) : titre, « Mardi 29 · premier créneau libre 9 h 45 », boutons **Caser 30 min** (primaire) · **Choisir l'heure** (ouvre le time picker), liens « Ouvrir la tâche » · « Marquer faite » |
| **Caser** | `addScheduleBlock(date, ScheduleBlock(category: 'project', projectId, taskId, title: task.title, durationMin: estimation, startTime: premier créneau libre))` → snackbar « Bloc ajouté mardi 9 h 45 » ; la barre gagne un point |
| Clic sur un **point** de la barre | mini-menu : heure du bloc · « Déplacer à demain » (`reportBlockToTomorrow`) · « Retirer » (`status: deleted`) |
| **Glisser** la barre horizontalement | décale `startDate` et `endDate` du même nombre de jours → `saveProjectTasks` ; les blocs existants ne bougent pas (snackbar « n blocs restent à leur date ») |
| **Tirer** la poignée droite | change `endDate` |
| **Clic droit** sur la barre | `_showColorPicker` existant |
| Coche titre (tâche faite) | inchangé (`task.status = done`, `saveProjectTasks`) |
| Clic **en-tête de domaine** | replie / déplie (état en `SharedPreferences` web, clé `week_collapsed_domains`) |
| **Masquer le fait** | filtre `status == done` (persisté) |
| **7 / 14 jours** | change la fenêtre (14 j = à partir d'aujourd'hui, comme la modale actuelle) |
| **Planifier avec ORION** | même appel que le bouton « Déclencher » de la vue ORION, avec l'intention `plan_week` |

**Premier créneau libre** = à partir de 8 h 00 (ou de maintenant si c'est aujourd'hui), premier
intervalle de `estimation` minutes sans chevauchement avec les blocs non supprimés du jour, avant
20 h ; sinon 8 h 00 avec avertissement « la journée est pleine ».

**Estimation** = `task.estimatedMin` si présent, sinon **45 min** ; « reste à caser » =
estimation − somme des `durationMin` des blocs liés (jamais négatif).

---

## 4. Données

Sources : `fetchProjects` / `streamProjects` (tâches, phases, couleurs), `streamDailySchedule`
pour **chaque jour de la fenêtre** (7 ou 14 streams, ou un `fetchDailySchedule` par jour rafraîchi
après chaque écriture), `domains`, `fetchRecentSessions(7)` pour les heures planifiées vs faites
(optionnel).

Ajouts rétrocompatibles si absents du modèle :

| Champ | Où | Défaut | Usage |
|---|---|---|---|
| `estimatedMin: int?` | `ProjectTask` | null → 45 | estimation, « reste à caser » |
| `weekCapacityMin: Map<String,int>` | `users/{uid}/meta/settings` | mon–fri 420, sat–sun 0 | jauges de l'en-tête ; dialog « Capacité » (icône ⚙ en en-tête) |

Exposer `estimatedMin` dans `push_gantt` / `update_task` (`tools.ts` + `normalizeTasks()`).
Aucun autre changement backend.

---

## 5. Fichiers

- `lib/web/views/week_view.dart` — la vue (extraire de `web_home_screen.dart` ce qui reste de
  `_FocusView` / `_buildTaskBarRow` / `_buildDomainGroupRows` / `_buildDayHeader` et le supprimer
  ensuite de l'ancien fichier).
- `lib/utils/week_planner.dart` — logique pure et testée : fenêtre, tâches par domaine, blocs par
  tâche, premier créneau libre, reste à caser, charge par jour.
- `lib/web/views/week_task_popover.dart` — le popover.

## 6. Critères

- `flutter analyze` propre sur `lib/web/` et `lib/utils/`.
- Tests unitaires sur `week_planner.dart` (créneau libre, reste à caser, charge, fenêtre 14 j).
- Vérifié à 1000 px et 1440 px ; un domaine de 12 tâches défile sans casser l'en-tête (en-tête
  jours **sticky**).
- Aucune régression : fiche tâche, couleur de barre, Gantt projet, mode démo.
- Interface 100 % français, pas d'emoji, pas d'`opacity` sur du texte.

## 7. Décisions prises (ne pas rouvrir)

- Le Gantt Focus est conservé tel quel dans son esprit ; pas de vue « colonnes par jour ».
- Titres de tâches 14 px sur 2 lignes, colonne 320 px : la lisibilité prime sur la densité.
- Un clic sur un jour crée un bloc au premier créneau libre ; l'heure se change ensuite.
- Capacité = réglage par jour de semaine, pas déduite des `DayBlock`.


---

## Audit d'ergonomie (2026-10-03) et lots retenus

Inventaire complet du code fait le 2026-10-03 ; constats et décisions, par ordre de traitement.

**Constats**
1. Gestes invisibles : seule aide = ligne de légende 11 px ; barres au curseur flèche ; menu du point
   (reporter / retirer) signalé nulle part ; aucune infobulle sur barres, points, poignée, jauges.
2. Actions irréversibles ou muettes : glisser, étirer, couleur, « Marquer faite » sans annulation ni
   retour ; aperçu du glisser non borné ; blocs non déplacés avec la tâche. **Bug** : « Déplacer à
   demain » depuis un point copiait le bloc sur demain mais laissait l'original en attente côté serveur
   (le mobile le marque sauté · reporté).
3. La ligne de tâche ne montre ni dates ni estimation ; `estimatedMin` n'est éditable nulle part dans
   l'UI ; points de blocs sans état (fait / sauté / à venir) et rognés en silence ; tâches en retard hors
   fenêtre toutes posées en colonne 0.
4. « Caser » ignore la capacité du jour (le popover de la fiche projet, lui, grise les jours pleins) ;
   `autoPlace` existe et n'est appelé nulle part ; « repos » affiché même avec des blocs le week-end.
5. En-tête : compteurs insensibles à « Masquer le fait » ; rien ne replie sous ~1100 px ; 7 jours part
   du lundi, 14 jours d'aujourd'hui ; tout masquer = liste vide sans message ; jauges à 0 pendant le
   chargement.
6. « Planifier avec ORION » relance le dernier `userNeeds` d'ORION sans intention `plan_week`.
7. Aucune passerelle vers la fiche projet ni Aujourd'hui (`onOpenProject` branché mais inutilisé).

**Lot 1 « confiance » — livré (PR du 2026-10-03)**
- Annulation (« Annuler » dans le bandeau) sur : glisser, étirer, couleur, Marquer faite, Retirer du
  programme. Retour visible sur l'étirement (« Échéance : jeudi 9 »).
- « Déplacer à demain » corrigé : original → `skipped` + `skipReason: reporte`, comme le mobile.
- Curseur main sur les barres (poing pendant le glisser), infobulles : barre (dates, estimation, blocs,
  reste à caser, rappel des gestes), point (jour, heure, durée, état, menu), poignée, jauge du jour.
- Points par état : plein = fait, anneau = à venir, barré et atténué = sauté ; « +N » au lieu du rognage.
- État vide quand tout est masqué (« Tout est fait sur cette période. » + Afficher le fait) ;
  « repos · n blocs » le week-end ; légende complétée (point = bloc (menu)).

**Lot 2 « information » — livré (PR du 2026-10-03)**
- Ligne de tâche : « 3 j · 2 h » sous le marqueur (≈ = estimation par défaut, non saisie) ; un jalon
  n'a que sa date.
- Popover « caser » : ligne de charge du jour (« Charge 3 h 10 / 7 h », « Journée pleine : 6 h 30 + 1 h
  > 7 h », « Jour de repos ») via `dayLoad`, lien « jeu. 9 tient → » vers le premier jour de la fenêtre
  qui tient (`firstFittingDay`) ; ligne « Tâche estimée 2 h » / « non estimée » avec « Estimer à <durée
  sélectionnée> » (écrit `estimatedMin`, annulable) — aussi dans le popover « Planifier » de la fiche projet.
- En-tête : sous 1100 px les commandes passent sous le titre (Wrap) ; titre et résumé tronqués proprement ;
  avec « Masquer le fait » le résumé devient « N à faire · … · M faites masquées ».
- Fenêtre affichée mémorisée **le jour même** (`week_window_start` + `week_window_saved_on`) : un
  rechargement garde la semaine regardée, le lendemain repart de la semaine courante.

**Lot 3 « navigation » — livré (PR du 2026-10-03)**
- « Planifier la semaine avec Claude » remplace le bouton ORION : ouvre claude.ai/new avec
  `planWeekPrompt` (plan_week sur la fenêtre affichée, retards cités, capacité par jour, pas d'écriture
  Google Agenda, proposer puis schedule_day). `triggerOrionCycle` n'est plus appelé depuis la vue.
- Popover « caser » : lien « Fiche projet » (`onOpenProject` → fiche hébergée, Plan d'action, tâche visée).
- Groupe **En retard** en tête de la grille (clé `_late`, repliable, trié par échéance, « la plus
  ancienne : mar. 30 ») ; les tâches en retard sortent de leur domaine. Barre « à caser » d'une tâche en
  retard : « éch. mar. 30 » écrit dessus ; hors fenêtre, à droite si on regarde le passé, à gauche sinon.
