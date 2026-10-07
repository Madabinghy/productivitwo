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

## Modèle

```
ProjectIntervention {
  id, title, date (YYYY-MM-DD), startTime, endTime ("HH:mm"), place?, templateId?, docUrl?,
  status: planned | done | cancelled,
  debriefText?, carryOver: ChecklistItem[], debriefAt?
}
ProjectTask += interventionId?, interventionRole? ("prep" | "session" | "closure")
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
3. **Mobile** : écran « séance en cours » plein écran type player (étape en cours, heure prévue, temps
   restant, étape suivante), bilan à la fin.
4. (§ 2.3) « Planifier la prépa » : pousse les actions de prépa dans les trous de la semaine.
