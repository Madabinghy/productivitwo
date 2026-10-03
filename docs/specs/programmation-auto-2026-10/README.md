# Programmation automatique de la journée (2026-10)

Décision utilisateur (2026-10-03) : **une routine Claude quotidienne via le connecteur
Productivitwo**, pas de cycle serveur (zéro coût Cloud Functions, qualité Claude, trace lisible).
ORION n'est pas touché. Heure : **6 h, heure de Paris**. Écritures : **programme en direct** (mode
compléter), **changements de projets en proposition** (« À valider »).

## Le toggle

- `users/{uid}/data/meta.autoPlan` (bool) + `autoPlanUpdatedAt`. `false`/absent = mode manuel.
- Mobile : Paramètres → interrupteur « Programmation automatique » (`_showSettingsSheet`, `main.dart`).
- Web : menu ⋯ → « Programmation automatique · activée/désactivée » (`WebMenuItem.autoPlan`, bascule
  dans `web_home_screen.dart`, état streamé par `FirestoreSync.streamAutoPlan`).
- Côté MCP : `plan_day` ouvre par une bannière `🤖 PROGRAMMATION AUTOMATIQUE : ACTIVÉE|DÉSACTIVÉE`
  avec la consigne pour la routine ; `get_user_context` expose `autoPlan.enabled`.
  **Désactivé ⇒ la routine ne modifie rien.** Une demande directe de l'utilisateur n'est pas concernée.

## `schedule_day` mode « compléter »

`schedule_day(date, blocks, mode:"fill", generatedBy:"auto")` : le programme existant est gardé **tel
quel** (blocs faits, manuels, reportés, tombstones), un entrant n'est posé que s'il ne chevauche aucun
bloc qui occupe son créneau (ni supprimé, ni sauté) — `fillAgainstExisting` (`schedule_dedupe.ts`,
testé). Les doublons de miroirs Google restent écartés. Le doc porte `generatedBy:"auto"` → l'en-tête
d'Aujourd'hui (web) affiche « · planifiée automatiquement ». Défaut inchangé : `mode:"replace"`.

## La routine (Routines Claude, session neuve chaque matin, connecteur Productivitwo)

Prompt versionné ci-dessous — c'est lui qui est posé dans la routine. Toute évolution du déroulé se fait
ICI puis dans la routine.

```
Tu es la routine de programmation automatique de Productivitwo. Tu n'as besoin que du connecteur
Productivitwo : n'ouvre aucun fichier, ne touche pas au dépôt, ne pose aucune question (personne ne lit
en direct). Date = aujourd'hui, heure de Paris.

1. Appelle plan_day(). Lis la première bannière « PROGRAMMATION AUTOMATIQUE » :
   - DÉSACTIVÉE → arrête-toi là, ne modifie rien, réponds en une ligne.
   - ACTIVÉE → continue.
2. Relis hier : get_day_schedule(hier). Note les blocs faits, sautés, non traités, et le temps logué
   (recentActivity du contexte).
3. Alimente les en-cours, SANS écrire sur les projets :
   - pour chaque projet actif qui n'a plus de prochaine action ouverte, ou dont une tâche travaillée
     hier mérite un changement de statut, utilise propose_change (jamais update_task_status / add_task /
     push_gantt en direct) ;
   - les blocs d'hier non faits et encore pertinents sont à reprogrammer aujourd'hui (pas de rattrapage
     en double : un seul bloc par chose).
4. Planifie aujourd'hui : 3 à 6 blocs, autour des rendez-vous Google (📅, déjà présents), des routines du
   matin/soir et des blocs déjà posés ; tâche la plus proche de l'échéance d'abord ; engagements en
   retard (onTrack:false) prioritaires ; regroupe par contexte GTD ; un bloc = une routine/activité avec
   son activityId ; ne recrée jamais un bloc [supprimé par l'utilisateur]. Puis
   schedule_day(date, blocks, mode:"fill", generatedBy:"auto"). Jamais mode "replace".
5. Termine par UN push_assistant_message (targetDate = aujourd'hui, condition always, characterName
   "ORION") : « Journée planifiée automatiquement · N blocs — <3 titres max> ». Rien d'autre.
Si un outil échoue, réponds en une ligne ce qui a échoué et arrête-toi.
```

Désactiver : le toggle dans l'app (la routine s'arrête d'elle-même), ou la routine elle-même dans
les Routines Claude. Les deux sont réversibles.

## Hors périmètre / pistes

- Replanification en cours de journée (la routine ne passe qu'au matin).
- Validation des propositions de projets côté web (la feuille « À valider » n'existe que sur mobile).
- Heure de passage réglable depuis l'app (fixe à 6 h pour le test).
