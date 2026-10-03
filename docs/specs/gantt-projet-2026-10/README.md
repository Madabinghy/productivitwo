# Gantt de la fiche projet (web) — audit d'ergonomie et refonte (2026-10)

Écran : onglet « Gantt » de la fiche projet (`lib/web/gantt_screen.dart`, hébergé par
`lib/web/views/project_plan_view.dart`). Audit du 2026-10-03, lots validés par l'utilisateur.

## Constats (avant)

1. **Une image, pas un outil.** Les barres ne réagissaient à rien (ni clic, ni glisser, ni bord, ni
   infobulle) ; seule prise = libellé de gauche → fiche de tâche, où titre et dates n'étaient pas
   modifiables (sauf repousser l'échéance plus tard).
2. **Repérage dans le temps.** `InteractiveViewer` : molette = zoom, pas d'ascenseur, pas de bouton
   Aujourd'hui / Ajuster, ouverture sur le début du projet, en-têtes non figés, vue Jour sans mois ni
   année, semaines alignées sur le début du projet (pas les lundis), plage = début → fin du projet
   + 7 j (tâches hors plage collées au bord). Colonne figée = copie complète de la grille superposée.
3. **Barres muettes** : pas de titre, de progression, de retard, de blocs du programme ; groupes par
   libellé de phase dans l'ordre d'insertion, sans tri ni repli.
4. **Deux en-têtes empilés** (fiche + AppBar du Gantt), thème Material sombre avec gris codés en dur,
   blocs de phase lavande clair, bouton « mode clair » contraire à la spec de la refonte.
5. **Doublons et pièges** : « Ajouter une tâche » en double ; avancement calculé autrement que les
   tuiles du plan d'action ; fiche de tâche seule à offrir statut « ignorée », couleur, description,
   fichiers, déplacement, suppression ; suppression irréversible ; « Valider le plan » sans confirmation ;
   aucune annulation ; le Gantt ne propage pas ses changements (`onChanged` jamais appelé).
6. **Régression** (corrigée PR #471) : construit en arrière-plan par l'IndexedStack, le Gantt ouvrait la
   tâche visée par-dessus le plan d'action.

Valeur propre du Gantt, à préserver : l'**horizon long** (mois) avec les **phases**. Cette semaine couvre
7 / 14 jours ; le Gantt doit devenir l'éditeur de planning du projet, avec la même grammaire de gestes.

## Lot 1 « se repérer » — livré

- Défilement à deux axes avec ascenseurs visibles ; **molette = défilement** (vertical, horizontal au
  trackpad ou avec Maj), **Ctrl / ⌘ + molette ou pincement = zoom** autour du curseur, boutons − / +.
- Boutons **Aujourd'hui** (centre la colonne du jour) et **Ajuster au projet** (toute la plage dans la
  largeur). Ouverture **sur aujourd'hui** quand il est dans la plage, sinon sur le début.
- **En-têtes figés** (phases · mois · jours ou semaines) et **colonne des libellés figée**, sans copie de
  grille : overlays synchronisés sur les contrôleurs de défilement.
- Axe : ligne des **mois** (« octobre 2026 ») ; vue Jour = numéro + initiale du jour, week-ends ombrés ;
  vue Semaine = colonnes **calées sur les lundis** (« lun. 5 oct. »). Colonne d'aujourd'hui surlignée
  avec étiquette « auj. ».
- Plage = lundi précédant min(début projet, 1ʳᵉ tâche) − 7 j → max(fin projet, dernière tâche) + 14 j,
  arrondie à la semaine : aucune tâche hors plage.
- **Un seul en-tête** : l'AppBar du Gantt disparaît (titre, retour, description = en-tête de la fiche) ;
  ligne d'objectif, exports PNG / PDF et changement de domaine passent dans la barre d'outils du Gantt
  (menu ⋯). Fin du mode clair et de `_kGanttLightTheme` ; couleurs = tokens `kB*`.
- « Ajouter une tâche » n'existe plus qu'en en-tête de fiche (doublon retiré).
- Implémentation : axe en logique pure `lib/utils/gantt_axis.dart` (`ganttRange`, `GanttAxis.x/dateAt/
  zoomToFit/monthSegments/weekStarts/scrollToCenter`, testé dans `test/gantt_axis_test.dart`) ; écran =
  `_GanttBody` (deux `ScrollController`, `Listener.onPointerSignal` + `pointerSignalResolver` pour que le
  zoom ne défile pas), `_GanttGrid` (contenu complet dans un `RepaintBoundary` → export PNG intact),
  overlays `_GanttTimeHeader` / `_GanttLabelColumn` + coin fixe. Semaine ↔ Jour garde la date au centre.
  Le PDF (`gantt_pdf_exporter.dart`) n'est pas touché par ce lot.

## Lot 2 « agir sur la barre » — livré

Même grammaire de gestes que Cette semaine :
- **Clic sur la barre** (ou le jalon) → fiche de tâche ; **glisser** = déplacer début + échéance (aperçu
  en direct, bordure blanche) ; **bord droit** = changer l'échéance (jamais avant le début ; une tâche sans
  échéance en reçoit une à partir de sa barre indicative de 7 j) ; pas de 1 jour, arrondi au plus proche.
- **Annulation** : chaque déplacement / redimensionnement affiche une SnackBar « Annuler » (5 s) qui
  restaure les dates d'origine et réenregistre.
- **Infobulle** sur la barre : titre, dates + durée en jours, estimation (`plannedMin`), progression des
  actions, statut, rappel des gestes ; pendant le glisser, l'infobulle suit les dates prévisualisées.
- **Curseurs** : main ouverte / fermée sur la barre, double flèche sur la poignée.
- **Fiche** : le titre se renomme au clic, la ligne des dates ouvre un sélecteur de plage (début → échéance ;
  date simple pour un jalon) ; l'ancien « Repousser la deadline » (date postérieure uniquement) devient
  « Modifier les dates ».
- **Description** (retour utilisateur après livraison) : la fiche affiche le texte complet jusqu'à 8 lignes
  puis « Voir toute la description » (zone défilante plafonnée) ; édition **en place** (plus de dialog) :
  champ 6 → 24 lignes, Ctrl / ⌘ + Entrée enregistre, Échap annule, « Effacer » ; panneau latéral élargi de
  420 à 480 px.
- Implémentation : état `_BarDrag` (tâche, poignée, dx cumulé) dans `_GanttBodyState`, `_TaskBarCell`
  stateless rendu avec l'aperçu ; persistance et annulation dans `_GanttScreenState._shiftTask/_resizeTask`
  (`saveProjectTasks`). Le glisser à la souris gagne l'arène contre le défilement (le `ScrollView` web
  n'accepte pas la souris comme périphérique de glisser).

## Lot 3 « lire l'état » — livré

- **Barre parlante** : titre (ou `barLabel`) dessus, déporté à droite quand la barre fait moins de 72 px ;
  **progression** = voile clair sur la part d'actions cochées ; **retard** (ouverte, échéance passée) =
  contour et halo `kBAlert`, triangle dans la colonne des libellés, « EN RETARD » dans l'infobulle.
- **Points des blocs du programme** sous la barre, à la date de chaque bloc (plein = fait, vide = à venir,
  grisé = sauté ; infobulle date · heure · durée · état) ; résumé « n blocs · durée · k faits » dans
  l'infobulle de la barre. Source : une requête `fetchDailySchedulesRange` sur la plage de l'axe
  (`FieldPath.documentId` entre deux `YYYY-MM-DD`), blocs supprimés exclus, filtrés sur les `taskId`
  du projet. Lecture seule (reporter / retirer un bloc reste dans Cette semaine).
- **Sections par phase** = `phaseSections(p)` (`lib/utils/project_health.dart`, partagé avec le plan
  d'action : phases triées par date de début, tâches en ordre Gantt, « Sans phase » pour les orphelines ;
  liste plate si le projet n'a aucune phase). Ligne de phase **repliable** (chevron, compte fait/total,
  « n en retard »), avec un trait résumé première → dernière tâche et sa progression, lisible replié.
  L'ancien groupement par `groupLabel` disparaît.
- **Bandeau d'état** (`_GanttDashboard`) : une ligne de pastilles alignée sur `project_health`
  (`taskProgress`, `overdueTasks`, `currentPhase`, `nextMilestone`, `daysLeftLabel`) — mêmes chiffres que
  l'onglet Projets et les tuiles du plan d'action. Les anciennes cartes « Suivi stratégique » (avancement
  hors jalons, chips par phase, liste des jalons) sont retirées : les phases et jalons se lisent dans la
  grille.
- `isTaskOverdue(t, today)` extrait dans `project_health.dart` (utilisé par `overdueTasks`).

## Lot 4 « nettoyage » — livré

- **« Valider le plan »** demande confirmation (titre du projet, nombre de tâches, ce que « actif » implique).
- **Suppression d'une tâche** : le texte « irréversible » disparaît ; après suppression, SnackBar « Annuler »
  (6 s) qui réinsère la tâche à son index d'origine et réenregistre (le messager est capturé avant la
  fermeture de la fiche).
- **Propagation** : `GanttScreen.onChanged` est appelé après chaque enregistrement (glisser, échéance,
  annulations, titre, dates, statut, phase, domaine, suppression, validation) ; la fiche projet le relaie au
  shell (`_load`) et se rebâtit, donc le plan d'action et l'onglet Projets reflètent le Gantt sans recharger.
- `_shellGantt` → `_shellProject` dans `web_home_screen.dart` (c'est la fiche entière qui est hébergée) ;
  commentaires « lot n » orphelins retirés de `gantt_screen.dart`.

## Complément (retour utilisateur) — colonne des libellés réglable

La colonne de gauche passe de 280 à **360 px par défaut** et se **redimensionne à la souris** (poignée sur
la frontière, 220–640 px, double-clic = défaut), largeur persistée en SharedPreferences (`gantt_label_w`).
Poignée partagée avec Cette semaine : `lib/web/column_resizer.dart` (`ColumnResizeHandle`,
`clampColumnWidth`).

## État final (après les 4 lots)

Le Gantt est l'éditeur de planning du projet : même grammaire de gestes que Cette semaine (glisser, bord
droit, clic = fiche, clic sur phase = renommer), repères temporels (mois, lundis, aujourd'hui), état lisible
(progression, retards, blocs du programme, phases repliables), et un seul en-tête. Pistes non retenues pour
l'instant : reporter / retirer un bloc depuis le Gantt (reste dans Cette semaine), dépendances entre tâches,
glisser une tâche d'une phase à l'autre (passe par la fiche).
