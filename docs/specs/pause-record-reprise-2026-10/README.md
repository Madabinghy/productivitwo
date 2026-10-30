# Pause, record et reprise (lot 1 de la gamification moyen terme, 2026-10-30)

Maquette validée : canvas « Pause, record et reprise » (4 écrans mobiles, design system « Badges
Productivitwo »). Objectif : contre l'abandon. Une absence prévue ne coûte pas une série, une série
cassée ne fait pas oublier le chemin parcouru, et revenir après une coupure est récompensé.

## Règles

| Situation | Réponse |
| --- | --- |
| Domaine en veille | Les jours de veille sont **gelés** pour les séries de ses routines : ils ne cassent rien et ne comptent pas dans la longueur. Une routine faite quand même compte. |
| 1 jour manqué | Les **braises** (inchangées) : une braise rallume la série cassée hier. |
| 2 jours manqués ou plus | La série repart ; tenir la routine **3 jours d'affilée** = une **reprise**. |
| Record | La série la plus longue se lit en face de la série en cours : « Encore 5 j pour égaler ton record (21 j) » / « Record en cours · 21 j ». |

- Une veille commence aujourd'hui au plus tôt, **jamais rétroactive** (sinon elle effacerait n'importe
  quelle cassure). Pour hier, il y a les braises.
- Jour gelé ≠ jour rallumé : le rallumé compte dans la longueur (la braise a été gagnée par une journée
  parfaite), le gelé non (la veille est gratuite).
- Une reprise par coupure. Les jours gelés ne comptent pas comme manqués.
- Badge **Reprise** : famille Discipline, symbole `rebound` (trois quarts de cercle, tête pleine à
  12 h), paliers 1 / 5 / 15.

## Données

- `data/meta.restPeriods` = `[{domainId, from, to}]` (jours inclus, 60 gardés). `restDomains` reste la
  source de « en veille maintenant ». Une veille sans période (posée avant ce lot) gèle aujourd'hui.
- Logique pure `lib/utils/rest_periods.dart` ↔ `functions/src/rest_periods.ts` (**garder alignés**) :
  `withRestSet`, `withRestLifted`, `frozenDaysOf`.
- Reprises : `lib/utils/reprise.dart` (`reprisesOf(held, frozen, today)` → événements + `RepriseNow`),
  jamais stocké.

## Où ça se voit

1. Feuille de veille (`rest_sheet.dart`) : « 3 séries gelées : Méditation 34 j, Pompes 12 j… » sous chaque
   domaine, la règle en une phrase ; écrit `restPeriods` (et à la levée).
2. Fiche routine (`RoutineTiersLine`) : ligne du record (`recordLine`), case « gelé (veille) » dans la
   bande ; fiche du badge de série : « Pour égaler le record », « Jours gelés (veille) ».
3. Ta journée (`stakes.dart`) : gain `StakeGainKind.reprise` sur le +1 de la routine (« reprise · 1 / 3 »,
   « reprise ce soir », jauge sur 3) ; « Reprise X » dans GAGNÉ le jour où elle tombe. Jamais de ligne
   « badge » seule.
4. Deck : badge Reprise (mobile, web, instantané coach).
5. MCP `rest_domain` écrit aussi `restPeriods` (transaction). ⚠️ `firebase deploy --only functions`.

## Hors lot

- Pause d'une routine seule (« Mettre en pause jusqu'à… ») : ne gèle pas encore sa série.
- Journée parfaite pendant une veille : les routines du domaine restent dues (comportement d'avant).
