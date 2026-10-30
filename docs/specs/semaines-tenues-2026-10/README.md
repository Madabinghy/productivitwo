# Semaines tenues (lot 2 de la gamification moyen terme, 2026-10-30)

Maquette validée : canvas « Semaines tenues » (3 écrans mobiles, design system « Badges Productivitwo »).
But : la boucle coaché → contrat → coach. La série de semaines où le Contrat d'Engagement est tenu est le
badge qui compte pour le coaching ; chaque semaine tenue forge une braise (deuxième source, plus accessible
que la journée parfaite).

## Règles

- **Semaine tenue** = semaine calendaire close (lundi → dimanche, jours vécus) où la moyenne des parts faites
  des routines engagées atteint **80 %** (`kKeptRatio`, même calcul que Ma semaine sur la semaine entière).
- **Routines engagées** d'une semaine = celles des objectifs (actifs ou atteints, pas archivés) dont la période
  couvre la semaine (`startDate ?? createdAt` → `endDate`) ; aucune → toutes les routines quotidiennes /
  hebdo qui existaient (`createdAt`). Approximation assumée : l'app ne garde pas l'historique des objectifs.
- **Veille** : les jours gelés réduisent la cible (quotidienne = cible × jours ouverts, hebdo = au prorata,
  arrondi au-dessus) ; une semaine sans rien à tenir est **neutre** (enjambée par la série).
- **Braise** : une semaine tenue forge une braise à la bascule du dimanche (`heldWeekYmds` = dimanches),
  même réserve plafonnée à 3, même règle de rallumage.
- Distinct de « Semaine solide » (7 journées solides d'affilée).

## Où ça se voit

1. Badge `semaines-tenues` (famille Objectifs, symbole `week`, paliers 4 / 12 / 26 / 52), bande des 12
   dernières semaines (tenue · sous 80 % · en veille · en cours).
2. Carte MA SEMAINE (`week_stats_view.dart`) : « SEMAINES TENUES · n d'affilée · record », 10 dernières
   semaines, « Cette semaine : 71 % du contrat · encore n coches d'ici dimanche ».
3. Ta journée, le dimanche : gain `StakeGainKind.week` « semaine tenue ce soir » sur le +1 des routines
   engagées non atteintes (si les coches restantes suffisent) ; « Semaine tenue » dans GAGNÉ quand c'est fait.
4. Bilan du soir du dimanche : « Semaine tenue · n d'affilée · une braise ».
5. Historique des braises : « Semaine tenue ».

Logique pure `lib/utils/held_weeks.dart` (`heldWeeks`, `engagedForWeek`, `weekTargetFor`, `missingHits`),
`BadgeDeck.weeks`. Rien de neuf en base, rien côté serveur (le badge part dans l'instantané coach).
