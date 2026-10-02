# Aujourd'hui (web) — carte MAINTENANT en mode actif (2026-10)

Maquette comparée (3 états) : https://claude.ai/artifact/W4UjekyAjcDLuvb8GEEc1j

## Décision

**Disposition A retenue.** Quand le chrono tourne **sur la source du bloc en cours** (règle
`sessionMatchesBlock`, même que la carte mobile), la vue Aujourd'hui échange ses colonnes :
MAINTENANT prend la colonne large, PROGRAMME DU JOUR passe en liste compacte de 340 px, la
colonne de droite (À traiter · Cette semaine · Échéances) ne bouge pas.

- Cas couvert : le **bloc d'activité** (cours, séance, rendez-vous). Le bloc **de tâche** passait
  déjà par la bande Focus pleine largeur : inchangé, la bande Focus garde la priorité.
- Un chrono **hors bloc** reste en disposition de repos : la carte étroite montre « hors bloc »
  et « Pour ce bloc » (PR #463).
- Retour au repos quand le chrono s'arrête, que le bloc est terminé ou que son créneau est dépassé.
- Seuil : largeur ≥ 1280 px (sinon la colonne large ferait moins de 490 px). Sous 1000 px tout
  s'empile comme avant, carte étroite.

**Écartés pour l'instant** :
- Variante B (le projet/tâche en cours à la place du programme) : extension possible de A pour
  les blocs rattachés à un projet ; recouvrement avec la bande Focus à régler avant.
- Changement de vocabulaire (« bloc » → « créneau », ou titre du bloc dans les libellés) : le mot
  « bloc » reste tel quel partout, à revoir plus tard.

## Code (`lib/web/views/today_view.dart`)

- `_liveBlock` : `(block, open)` si la session ouverte correspond au bloc courant, sinon null.
- `build` : branche `live != null && maxWidth >= 1280` → `Row[Expanded(_nowCardWide), 340 _scheduleListCard, 340 _weekColumn]`.
- `_nowCardWide(b, open)` : anneau 240 px (200 si carte < 600 px) avec « sur 2 h · reste 1 h 36 »,
  origine (projet · activité), titre, « 14 h 00 → 16 h 00 · ensuite … », Terminer le bloc / Pause ;
  puis `_stepsPanel` (checklist de l'action visée : sous-action de tâche via `resolveBlockAction`, ou
  action propre d'activité via `Activity.ownActions` + `b.actionId`, cocher/ajouter) et
  `_contextPanel` (minutes du jour sur l'activité et cible `goalMin` si > 1, semaine, dernière session
  terminée sur la même source, documents du projet via `focusDocuments` → `DocumentViewerDialog`) ;
  `_nextStrip` ; `_dayGlance` inchangé.
- `_scheduleListCard` : les blocs avant les trois derniers passés repliés en une ligne, bloc courant
  avec barre de progression et « reste … », suite de la journée ; même tap que la frise (projet →
  fiche, sinon éditeur), coche = fait ; « Modifier » / « + Ajouter un bloc » conservés.
