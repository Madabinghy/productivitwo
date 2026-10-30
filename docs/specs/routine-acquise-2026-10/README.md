# Routine acquise (2026-10-30)

Maquette validée : canvas « Routine acquise » (3 écrans). Idée : la gamification sert à installer une
habitude ; une fois installée, le jeu recule et libère la place pour la suivante. Aucun badge.

## Règles

- **Proposition** au palier de 66 jours (plus longue série ≥ 66), une seule fois par routine (`acquireAsked`) :
  carte dans Aujourd'hui « 66 JOURS · L'HABITUDE EST INSTALLÉE » — Passer en acquise / La garder comme maintenant.
  Interrupteur « Routine acquise » dans la fiche routine (à la main, dans les deux sens).
- **Une acquise** (à partir du jour du passage, jamais rétroactif) : sort de la journée parfaite et solide
  (`scoreDay`), des faits du jour (`composeTodayFacts` → tuile Journée parfaite, enjeux, bilan et rappel du
  soir), du compte du matin et des routines par moment (`buildRoutineDay(exclude:)`). Elle reste cochable
  (section ACQUISES de la fiche Routines, lanceur de routines), sa série et ses paliers continuent, et elle
  **compte toujours dans le contrat** de son objectif (Ma semaine, semaines tenues, coach).
- **Décrochage** : deux semaines closes d'affilée sous 4 / 7 jours tenus (après le passage) → carte « UNE ACQUISE
  DÉCROCHE » avec les 4 dernières semaines : La remettre en routine active / C'est voulu (silence 4 semaines).

## Données

`data/meta.acquired {activityId: {since, quietUntil?}}` (écrit en `mergeFields`, la map est remplacée) et
`data/meta.acquireAsked [ids]`. Logique pure `lib/utils/acquired.dart` ; écrans `lib/widgets/acquired_view.dart`
(`AcquiredPrompts`, `AcquiredSection`). Web : la journée parfaite et les enjeux suivent (`WebHuntStore.acquired`) ;
pas de carte ni d'interrupteur sur le web. Enchaîner peut encore accrocher une acquise (non filtré).
