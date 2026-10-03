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

## Lot 2 « agir sur la barre » — à faire

Clic sur la barre → fiche ; glisser = déplacer les dates ; bord droit = échéance ; annulation ; infobulle
(dates, estimation, progression) ; curseurs ; titre et dates modifiables dans la fiche.

## Lot 3 « lire l'état » — à faire

Titre et progression sur la barre, marque de retard, points des blocs du programme (comme Cette semaine),
groupes par `phaseId` triés par date et repliables, tableau de bord aligné sur `project_health`.

## Lot 4 « nettoyage » — à faire

Confirmation de « Valider le plan », annulation à la suppression, propagation `onChanged`, commentaires
orphelins, `_shellGantt` renommé.
