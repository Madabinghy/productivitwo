# Spec — « Reconquête du temps » & Standard vivant

> Statut : **spécification de design**, non implémentée. Document de référence
> issu de la discussion produit. Aucune ligne de combat ne doit réécrire de
> vraies données : tout ce qui suit est **additif** et **dérivé**.

---

## 1. Le renversement

On passe d'un système de **suivi du temps** (relevé fidèle, backward, immuable) à
un système de **standard défendu** : un plancher d'effort vivant, tenu sur une
fenêtre de 7 jours glissants, qui monte tout seul quand on le dépasse durablement.

- Les apps de streak récompensent la régularité **binaire** (fait / pas fait).
- Ici on récompense le **niveau d'effort soutenu**.

Le trophée n'est plus « j'ai tué N araignées », c'est **« je tiens 22 min/jour
depuis 3 semaines »**. La reconquête du passé n'est qu'un **moyen** de défendre ou
hisser ce plancher.

Pitch : *« la seule app où tu défends un plancher d'effort vivant, et où la
semaine ratée se reconquiert — sans jamais mentir sur tes vraies données. »*

---

## 2. Principe non négociable : deux lentilles étanches

| | Le **Relevé** (vérité) | Le **Jardin** (standard / dette) |
|---|---|---|
| Question | « Qu'as-tu fait ce jour-là ? » | « Quel plancher tiens-tu ? » |
| Sens | backward, **immuable** | forward, **reconquérable** |
| Donnée | `sessions` / `habitHits` réels, datés du vrai jour | **dérivé** (réel + crédits de reconquête) |

Le rapport temps, les budgets et ORION lisent **uniquement** le relevé réel. Les
minutes synthétiques (voir §4) et les crédits de reconquête (voir §6) **n'y
entrent jamais**.

---

## 3. Le Standard vivant (plancher défensif)

Chaque routine / activité porte un `standard` courant (en minutes/jour).

- **Départ bas** : 1 min / 1 hit. Barrière quasi nulle → on commence, point.
- **Montée auto = les 7 cases propres** : si **toutes** les cases de la fenêtre
  glissante (7 j) sont propres (effort du jour **≥ standard courant**, reconquête
  comprise), le standard **monte d'un palier**. Règle binaire et visuelle — pas
  de seuil en % caché. La reconquête du passé devient ainsi le **moteur** de la
  montée (compléter la semaine = souvent reconquérir les vieux jours).
- **Conséquence assumée** : à la montée, le plancher s'élève d'un cran → des
  jours propres au palier précédent repassent **sous** le nouveau standard, donc
  de **petits ennemis réapparaissent** (sinon montée en boucle). Garde-fous :
  paliers petits (écarts faibles, vite ré-nettoyés) + célébration/marque de crue
  (on gagne un niveau, on ne « recule » pas). Visuel = logique.
- **Descente douce** : si on passe sous le standard trop souvent, il **redescend
  d'un cran** — jamais brutalement, jamais sous le plancher.
- **Marque de crue** : le niveau max atteint reste affiché (« max 5 — tu défends
  à 4 »). On ne perd pas le record, juste le buff actif.

Paliers indicatifs : `1 · 2 · 5 · 10 · 15 · 20 · 30 · 45 · 60` (courbe douce au
début, façon *atomic habits*).

Le standard est un **plancher** (« ce que tu tiens à coup sûr »), pas une cible
aspirationnelle. On peut toujours faire plus ; relever un plancher manifestement
dépassé se **mérite**, ça ne **punit** pas.

Amorçage : `compute_time_budget` (MCP, « cible = p90 des jours actifs ») peut
**initialiser** le standard ; le jeu prend ensuite le relais pour la montée /
descente.

---

## 4. Unité unifiée : la minute

Tout le jardin s'exprime en **minutes**, pour un seul barème :

```
standard d'une routine (en min) =
  • temps réel dispo (routine minutée / activité liée)  → vraies minutes
  • sinon (compteur pur, ex. 10 verres d'eau)           → 1 hit = 1 min
```

> `1 hit = 1 min` est une **unité de jeu** (standard + tourelle), pas du temps
> tracké. Un verre d'eau = 0 minute dans le rapport temps, +1 « min » de standard
> dans le jardin. (v1 : facteur plat ; un poids « minutes par hit » par routine
> reste possible plus tard pour distinguer pompes ≠ verre d'eau.)

**Granularité des PV** : temps → 1 PV = 5 min ; compteur → 1 hit = 1 PV (garde le
geste visible).

---

## 5. L'ennemi

L'araignée / scorpion d'un jour = **ce jour est sous le standard courant**.

```
PV(jour) = max(0, standard − effort_réel(jour) − crédits_reconquête(jour))
```

Quand le standard monte, des jours « ok » au vieux palier peuvent repasser sous le
nouveau → la barre se relève d'elle-même. On défend un niveau qui grandit, pas un
objectif fixe.

---

## 6. La reconquête (crédit, jamais téléportation)

Décision structurante : **créditer ≠ téléporter**.

- ❌ Téléporter = backdater la vraie session sur le jour passé → les minutes du
  jour disparaissent des stats du jour (confusion) **et** corrompent le rapport.
- ✅ Créditer = l'effort se loggue **aujourd'hui** (vérité, visible) **et** émet un
  **crédit** sur le jour passé reconquis (registre séparé).

### Ciblage automatique (pas de viseur manuel)

> On tape sur **aujourd'hui**. Aujourd'hui soldé → on tape sur le **plus ancien
> jour en dette de cette lane**. Plus rien en dette → l'effort se loggue quand
> même (et peut se stocker en munition future).

Conséquence élégante : « aujourd'hui d'abord » fait que **seul le surplus** part
dans le passé, sans règle de surplus dédiée. Comptablement généreux (tout se
loggue), comportementalement sain (règle ta journée avant de reconquérir).

> Note : en pure fenêtre glissante (sans rien écrire) on **ne peut pas** faire
> tomber un ennemi passé avec l'effort d'aujourd'hui (la fenêtre d'un jour passé
> n'inclut pas aujourd'hui). Le registre de crédits est **nécessaire** pour ça.

### Modèle de données

```
Collection : users/{uid}/redemptions/{id}
Redemption {
  id,
  activityId,
  type: "habit" | "time",
  targetDate: "YYYY-MM-DD",     // le jour passé reconquis
  amount: int,                   // habit → hits · time → minutes
  sourceDate: "YYYY-MM-DD",     // le jour de l'effort (= aujourd'hui)
  createdAt,
  status: "active" | "deleted"  // soft-delete, réversible
}
```

Aucune mutation de `sessions` / `habitHits`. FirestoreSync merge par id.

### Nouvelles fonctions

- `redeemPastDay(activityId, type, targetDate, amount)` → écrit une `Redemption`.
- `redemptionCreditsOn(activityId, date)` → somme des crédits actifs ce jour.
- Branchement (seul point d'intégration), dans `gold_engine` :
  - `activityTimeTokens` / `enemyHp` (scorpion) : `hp = max(0, déficit − crédits)`
  - `routineWeekTokens` / `enemyHp` (araignée) :
    `valueEffectif(jour) = habitValueOn(jour) + crédits(jour)`

---

## 7. La tourelle = le niveau

La tourelle d'une lane **visualise le standard** : elle monte de niveau avec lui.
C'est le trophée visible. Un tir = un tir (pas d'arsenal à étages, voir §9).

Quand le standard redescend, la tourelle se **fêle** (marque de crue conservée),
elle ne s'effondre pas.

---

## 8. Score / Or

Puisque « ce qui compte = le standard tenu », les récompenses suivent le
**standard** (tenir / relever un palier), **pas les kills** — sinon on farme des
ennemis au lieu de monter en niveau. La reconquête n'est qu'un outil pour
défendre le plancher.

---

## 9. Écarté (volontairement, pour rester simple)

- ❌ 3 calibres de tir (−1 / −5 / −15 min) et la salve
- ❌ déblocage d'arsenal par niveau
- ❌ viseur manuel pour choisir la colonne-jour

---

## 10. Garde-fous

- On ne reconquiert qu'un jour **passé en dette** (jamais le futur, jamais un jour
  déjà tenu).
- `amount` plafonné au déficit factuel **de ce jour-là** (pas de sur-reconquête).
- Fenêtre limitée (7 j, ou la « fenêtre de pardon ») — un ennemi qui sort de la
  fenêtre expire.
- Idempotence : un crédit = un doc, soft-delete réversible (annuler une
  reconquête).
- Les minutes synthétiques (§4) et les crédits (§6) ne fuient **jamais** dans le
  rapport temps / budgets / ORION.
