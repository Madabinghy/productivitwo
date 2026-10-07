# Interventions — la séance comme objet natif (2026-10)

Issu du brief « Rendre l'onglet Projets opérationnel » (§ 2.2). Constat : l'utilisateur (formateur +
enseignant) travaille par **séances datées** — préparer avant, animer le jour J, clôturer après — encodées
jusqu'ici par convention (émojis 📝 / 🎯 / ✅ + `groupLabel`). L'intervention devient un objet de l'app.

## Décisions

- **Pas de nouvelle collection.** `Project.interventions[]` porte l'objet ; ses trois tâches restent des
  `ProjectTask` ordinaires taguées `interventionId` + `interventionRole` (`prep` · `session` · `closure`).
  Gantt, Actions, programme du jour, mobile, outils MCP existants continuent de fonctionner sans migration
  lourde ; l'app ré-écrit `interventions` tel quel dans `Project.toJson` (ne jamais le perdre).
- **Création côté serveur** (`add_intervention`) : génère 📝 Préparer (J-7 → J-1), 🎯 jalon le jour J
  (action « Dérouler la séance (13h15–15h00) », `estimatedMin` = durée du créneau, déroulé = checklist) et
  ✅ Clôturer (J → J+2), `groupLabel` = titre, phase = celle qui couvre la date.
- **Modèles** (`data/meta.interventionTemplates[]`, outil `manage_intervention_templates`) : créneau et lieu
  par défaut, contexte de la séance, actions de prépa / clôture avec contextes et estimations. « default »
  (intégré) : adapter au bilan précédent · produire les supports · fiche de séquence · imprimer @impression /
  remplir la fiche de séquence · noter le report · déposer.
- **Bilan** (`update_intervention` : `debriefText` + `carryOver[]`) : texte libre **et** points à reprendre ;
  les points deviennent la checklist de l'action « Adapter au bilan précédent » de la séance suivante
  (créée si absente, fusion sans doublon).
- **Migration** (`migrate_interventions`, dryRun par défaut) : détecte les triplets existants par `groupLabel`
  et émojis, lit le créneau dans l'action du jalon puis la description du projet, crée l'objet et tague les
  tâches. Les tâches hors triplet (✍️ Corriger…) gardent leur `groupLabel` sans tag.
- **Lecture côté app** (`lib/utils/interventions.dart`) : natif d'abord, repli sur la convention pour les
  tâches non migrées. Le radar « Cette semaine » (web, 2.1) s'appuie dessus.

## Rattachements (spec « Rattachement des tâches aux interventions », 2026-10)

Après la première migration (37 triplets), des rattachements étaient faux : regroupement par `groupLabel` +
premier jalon trouvé. Corrections :

- **`update_task`** accepte `interventionId` (`""` = détacher) + `interventionRole` (`prep | session | closure |
  extra`). Un rôle principal n'est porté que par une tâche : conflit = refus nommant la tâche en place. Ni statut,
  ni dates, ni actions modifiés ; le décalage de dates reste réservé à `update_intervention` + `date`.
- **`delete_intervention(projectId, interventionId, tasks?)`** : `detach` (défaut, un jalon redevient un jalon
  simple) · `cancel` · `delete` (sur demande explicite). Retourne les tâches touchées.
- **`update_intervention` + `mergeFrom`** : les tâches de la source passent sur la cible ; un rôle principal déjà
  tenu → la tâche entrante devient **`extra`** (décision : pas d'échec, pas de rôles `_extra` multiples — un seul
  rôle secondaire générique) ; bilans concaténés ; source retirée.
- **Migration** : appariement temporel par jalon 🎯 (📝 dont `endDate` est la plus proche avant, ✅ dont
  `startDate` est la plus proche à partir du jalon, chaque tâche une seule fois), un repère de titre commun
  (« J3 », « 23/11 », « 15 oct ») primant sur la proximité ; un 🏁 le jour d'un 🎯 du même groupe devient `extra`,
  un 🏁 seul n'est pas une séance ; jalon sans 📝 ni ✅ = orphelin, ignoré sauf `includeOrphans:true` ; créneau
  multi-plages (`8h30–12h30 + 13h30–16h30` → 8h30–16h30, `breaks: [{start, end}]` stocké, durée nette pour
  l'action « Dérouler ») ; dry run : ⚠️ 📝 / ✅ sans partenaire et jours à deux interventions.
- Décisions sur les questions ouvertes : (1) conflit de fusion → `extra` ; (2) une intervention porte UNE tâche
  `session`, les autres jalons du jour sont `extra` ; (3) la pause est stockée (`breaks`), début/fin restent la
  plage globale.

## Modèle

```
ProjectIntervention {
  id, title, date (YYYY-MM-DD), startTime, endTime ("HH:mm"), breaks?: [{start, end}], place?, templateId?, docUrl?,
  status: planned | done | cancelled,
  debriefText?, carryOver: ChecklistItem[], debriefAt?
}
ProjectTask += interventionId?, interventionRole? ("prep" | "session" | "closure" | "extra")
InterventionTemplate { id, name, startTime?, endTime?, place?, sessionContext?,
  prep: { daysBefore, endDaysBefore, actions[] }, closure: { daysAfter, actions[] } }
```

Logique pure serveur : `functions/src/interventions.ts` (tests `functions/test/interventions.test.mjs`).

## Lots

1. **Modèle + MCP** (ce lot) : objet, quatre outils, migration, modèle Dart, lecture native dans le radar.
2. **Web** (livré) : bouton « Nouvelle séance » dans l'en-tête de la fiche projet
   (`web/add_intervention_dialog.dart` : titre, modèle, date, créneau, lieu, déroulé une étape par ligne) —
   port Dart de la génération dans `lib/utils/intervention_builder.dart` (`buildInterventionTasks`,
   `parseInterventionTemplates`, `applyCarryOver`, tests `test/intervention_builder_test.dart`), modèles lus par
   `FirestoreSync.fetchInterventionTemplates`. Dans **Réalisation**, l'action d'une tâche ✅ Clôturer affiche la
   carte « Bilan de la séance » (texte libre + points « à reprendre », bouton Enregistrer → `saveProject` + report
   dans la prépa suivante) ; une tâche 📝 Préparer rappelle le bilan de la séance précédente ; le jalon affiche
   date · créneau · lieu. Les modèles se créent toujours via le MCP (pas d'éditeur web pour l'instant).
3. **Mobile** (livré) : écran « séance en cours » (`widgets/session_player_screen.dart`, route plein écran) :
   étape en cours en grand (heure prévue lue dans le libellé « 13h45 … », fin prévue = heure de l'étape
   suivante, retard affiché), reste du créneau, « Étape suivante » / « Précédente », liste complète cochable,
   ajout d'étape, chrono optionnel ; « Terminer la séance » → feuille de bilan (texte + points à reprendre,
   chips « Non fait : … » pour les étapes sautées) → jalon et action faits, `status: done`, report dans la prépa
   suivante, `saveProject`. Entrées : bouton « Séance en cours » sur le jalon dans la fiche projet mobile, ▶ du
   radar « Cette semaine » (`widgets/week_radar_card.dart`, en tête de l'onglet Projets, même logique que le web)
   pour une séance du jour, et lancement d'un bloc du programme qui vise un jalon de séance (après le chrono).
   Les étapes sont la checklist de l'action « Dérouler la séance » : identiques web / MCP.
4. **« Planifier la prépa »** (§ 2.3, livré) : outil MCP `plan_prep(projectId, interventionId, apply?, eveningFrom?)`
   — logique pure `functions/src/prep_planner.ts` (tests `prep_planner.test.mjs`) : les actions ouvertes de la 📝
   vont dans les trous du programme, **la veille au soir d'abord** (dès 18 h, `eveningFrom`), puis les soirs
   précédents, puis les journées (le plus tard possible), puis le jour même avant la séance ; l'**impression**
   (@impression / « Imprimer ») est posée **sur place**, collée au début du créneau (15 min de marge, reculée si un
   bloc gêne) ; blocs existants (miroirs Google Agenda compris), journée active (`data/meta.dayWindow`) et heure
   locale (`tzOffsetMin`) respectés ; jamais avant le début de la tâche 📝 ni avant maintenant. `apply:false`
   (défaut) = proposition ; `apply:true` = `schedule_day(mode:"fill")` jour par jour avec chrono ciblé
   (`projectId` + `taskId` de la 📝 + `actionId`). Une action sans trou est signalée avec deux créneaux de repli.
   Web : bouton « Planifier la prépa avec Claude » sur la tâche 📝 dans Réalisation (`planPrepPrompt`,
   `claude_link.dart`) — Claude propose, l'utilisateur valide, Claude relance avec `apply:true`.
5. **Revue hebdo des orphelins** (§ 2.5 + B5 + B7, livré) : outil MCP `weekly_review(horizonDays?)`, logique pure
   `functions/src/project_audit.ts` (tests `project_audit.test.mjs`). Ne modifie rien : chaque constat vient avec
   l'appel qui le corrige. Constats : tâches sans phase · tâches hors des dates de leur phase · jalons passés non
   cochés · clôtures non faites · projets en veille / archivés avec des séances à venir (B5) · projets actifs sans
   séance à 14 jours (mise en veille à proposer, règle d'usage § 5 du brief ; dossiers et projets sans jalon
   ignorés) · doublons de projets (B7 : ≥ 60 % de mots utiles communs, « 6e » / « cm1 » comptent, périodes qui se
   chevauchent) · triplets non migrés. `plan_week` demande la revue en étape 0 (la tâche programmée « Préparer la
   semaine » l'exécute donc chaque dimanche). `archive_project` avertit des séances à venir (B5) ; `push_gantt`
   signale un doublon probable à la création (B7).
