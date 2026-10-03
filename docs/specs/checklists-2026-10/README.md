# Onglet « Réalisation » de la fiche projet (web, 2026-10)

Demandes : « Au lieu de Document, mets Checklists et permets de gérer chaque action comme un micro-projet :
granularité encore plus fine, si ça reste pertinent avec une intégration dans l'app mobile. » puis
« De gauche à droite : Vision (à la place de Gantt) | Plan d'action | Réalisation (à la place de Checklists) —
une granularité de plus en plus fine de ce qu'il y a à faire. »

## Onglets de la fiche projet

`Vision · Plan d'action · Réalisation` (`ProjectPlanTab { vision, plan, realisation }`), du plus large au plus
fin : **Vision** = le Gantt (phases, jalons, horizon), **Plan d'action** = tâches et actions (ouverture par
défaut, inchangée), **Réalisation** = les étapes de chaque action. Le code du Gantt garde son nom
(`GanttScreen`, handoff `gantt-projet-2026-10`) ; seul le libellé change.

## Décisions

- **L'onglet Document disparaît** (`lib/web/project_doc_view.dart` supprimé). C'était le « document de
  pilotage » Markdown (catégorie `playbook`) : cases liées aux actions du Gantt, hero, cartes. Son rôle
  (suivre le projet au niveau des actions) est repris par Checklists avec de vraies données. Les documents
  `playbook` restent en base mais ne sont plus affichés (ils ne sont pas des HTML pour le viewer).
- **Pas de 4ᵉ niveau.** « Granularité plus fine » = travailler sérieusement le 3ᵉ niveau existant
  (projet → tâche → action → **étapes** = `TaskAction.checklist`, `ChecklistItem {id,title,done,doneAt}`).
  Le modèle ne change pas, donc : la carte MAINTENANT et l'écran Focus du mobile cochent les mêmes étapes
  pendant un bloc, `mark_checklist_item` (MCP) et la règle « dernière étape cochée = action faite ;
  décocher rouvre » s'appliquent partout. Un niveau de plus aurait exigé modèle + mobile + MCP + Functions
  pour une granularité que le programme horaire n'exploite pas.
- **Grammaire** : la même que le plan d'action (cocher, ajouter à la volée, retirer) plus ce qu'un
  « micro-projet » demande : renommer en place, réordonner, prochaine étape mise en avant, progression,
  marquer faite / rouvrir, navigation précédente / suivante.

## Vue `lib/web/views/project_checklists_view.dart`

- ≥ 1100 px : **navigateur** à gauche (380 px) = phases → tâches → actions, filtres « À faire / Sans étapes /
  Toutes », compteur « n actions · k avec étapes · x / y étapes » ; **espace de travail** à droite pour
  l'action sélectionnée. Sélection par défaut : première action ouverte.
- < 1100 px : la liste seule ; une action ouvre l'espace de travail plein écran avec « ‹ Toutes les actions ».
- Espace de travail : fil d'Ariane phase › tâche, ↑ ↓ entre actions du filtre, titre (clic ou crayon →
  `showEditActionDialog` : titre, contextes, estimation, déplacer…), pastilles (contextes, ≈ estimation,
  ⏱ activité liée, « Faite le »), progression « 3 / 7 étapes · reste 4 » + barre, « Masquer les faites ».
- Étapes : cocher (règle d'achèvement + SnackBar « Action faite / rouverte »), **renommer en place** (clic
  sur le titre, Entrée ou clic ailleurs enregistre, Échap annule), **réordonner** (poignée, désactivée quand
  les faites sont masquées), **retirer** (croix au survol, SnackBar « Annuler » qui réinsère à l'index),
  **ajouter** (champ permanent, Entrée enchaîne), prochaine étape surlignée. Pied : « Marquer l'action
  faite » (coche toutes les étapes) / « Rouvrir l'action » (étapes conservées), compteur d'actions de la tâche.
- Persistance : `saveProjectTasks` puis `onChanged` → la fiche se rebâtit et le shell recharge.

## Logique pure ajoutée (`lib/utils/checklist_logic.dart`, testée)

`renameChecklistItem(a, id, title)` · `moveChecklistItem(a, oldIndex, newIndex)` (sémantique
`ReorderableListView`) · `setActionDone(a, done)` (faite = toutes les étapes cochées ; rouvrir ne touche pas
aux étapes) · `nextChecklistItem(a)`.

## Mobile — livré

- Pendant un bloc : cocher les étapes dans la carte MAINTENANT (`now_card.dart`) et l'écran Focus
  (`focus_screen.dart`), inchangé.
- **Fiche de tâche mobile** (`project_sheet.dart`, `_TaskDetailSheet`) : chaque action porte un compteur
  « 2/5 » et un chevron ; **tap = déplier** ses étapes (`_StepsSection`) : cocher (règle d'achèvement +
  SnackBar « Action faite / rouverte »), **ajouter** (champ permanent, Entrée enchaîne), **appui long** sur une
  étape = renommer ou retirer. Cocher l'action elle-même coche toutes ses étapes (`setActionDone`) ;
  la décocher depuis « Fait » la rouvre sans toucher aux étapes. Pas de réordonnancement sur mobile
  (poignée réservée aux actions). Mêmes helpers purs que le web.
