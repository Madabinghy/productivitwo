# 🌈 FLUO ADVENTURE
### *mets de la couleur dans ta vie*

> Concept de gamification pour Productivitwo — vision consolidée.
> Statut : exploration / prototypes jouables. Ce document fige la direction.

---

## Pitch (une phrase)

**Un jeu d'aventure néon où ta productivité réelle est la seule ressource : faire tes
routines et logguer ton temps colore le monde, fait évoluer ton héros, débloque des
niveaux et alimente des combats — lâche, et tout se grise.**

---

## Le fil rouge

Une app de vie ne doit pas *afficher* ta productivité (tableau de bord) — elle doit la
**transformer en jeu**. Le nom dit la mécanique : **ta vraie vie met de la couleur dans
l'aventure.**

- Tu logges une séance / coches une routine → **le monde s'illumine**, ton héros est
  joyeux, tu avances, tes tourelles pètent.
- Tu négliges → **le monde se grise**, le héros s'endort, les défenses faiblissent.

Couplage **lâche** : la productivité est le **carburant** d'un vrai jeu (avec agency,
enjeu, fun propre) — pas un visuel passif. C'est ce qui fait la différence avec un
dashboard déguisé.

---

## Les 4 piliers

| Pilier | Ce que c'est | Verbe |
|--------|--------------|-------|
| 🗺 **Overworld** | Carte-monde de nœuds néon ; un **héros fluo** qu'on déplace de nœud en nœud. Le HUB. | explorer, avancer |
| 🏠 **Niveaux / cartes** | Lieux à explorer (style top-down néon) : loot, énigmes, ennemis. | fouiller, résoudre |
| ⚔️ **Combats** | **Tower-defense néon** : on pose/évolue des tourelles, les vagues montent. | défendre, composer |
| 🌌 **Cosmos** | Tes **domaines de vie = planètes** qui grandissent avec ton temps. | faire croître |

Le **héros** porte l'émotion : 5 humeurs (surexcité → joyeux → content → triste →
endormi) qui **réagissent à ta régularité pour t'encourager**.

---

## La boucle de jeu

```
   Vraie vie (séance / routine)
            │  = carburant (or, énergie, couleur)
            ▼
   OVERWORLD ──tape un nœud──► NIVEAU / COMBAT (TD tourelles)
        ▲                              │
        │        gagner = débloque la suite, loot, XP
        └──────────────────────────────┘
            │
            ▼
   le héros + les planètes ÉVOLUENT, on va « de plus en plus loin »
```

Aversion à la perte intégrée : streaks, défenses qui faiblissent, monde qui se grise.

---

## Comment la productivité l'alimente (data → jeu)

| Donnée (déjà collectée) | → | Effet de jeu |
|---|---|---|
| séance loggée / routine cochée | → | carburant (or/énergie), recharge des tourelles |
| **streak** par domaine | → | niveau/évolution des tourelles, humeur du héros |
| récence d'activité | → | couleur du monde (vif ↔ grisé), héros joyeux/endormi |
| temps total par domaine | → | croissance de la planète (cosmos) |
| régularité globale | → | progression sur l'overworld, déblocage de niveaux |

> Tout est déjà dans `AppState` (domains, sessions, routines/habitHits). Aucune
> nouvelle saisie utilisateur.

---

## Identité visuelle

**Néon / dark punchy + fluo coloré.** Fond sombre, glow partout, couleurs vives et
saturées, juice (traînées, explosions, particules). Chaleureux par la couleur, nerveux
par le juice. Dessiné en code (zéro asset requis pour démarrer ; pixel-art/Rive possible
ensuite).

---

## Déjà prototypé (jouable, routes cachées web)

| Brique | Route | État |
|---|---|---|
| Overworld + héros déplaçable | `?proto=world` | ✅ |
| Héros — 5 humeurs | (maquette) | ✅ |
| Tower-defense (drag-drop, vagues, boss, roster, 3 cartes) | `?proto=td` | ✅ |
| Cosmos (planètes/domaines) | `?proto=orbit` | ✅ (en prod) |
| Carte de niveau néon (Repaire) | (maquette) | ✅ |

---

## Pourquoi c'est différenciant

- **Personne** ne fait « ta vraie productivité **fuel** un vrai jeu d'aventure/TD ».
- Profondeur (TD, exploration) **sans** stratégie lourde → accessible.
- Émotion (héros qui t'encourage) **+** gameplay (agency, enjeu) dans le même objet.

---

## Prochaines étapes (assemblage)

1. **Relier overworld → combat** : taper un nœud ⚔ ouvre le TD ; gagner débloque la suite.
2. **État partagé** : or/XP/progression persistés entre les écrans.
3. **Brancher sur les vraies données** : carburant = sessions/routines réelles.
4. **Héros évolutif** + humeurs branchées sur le streak.
5. Plus tard : roster de tourelles étendu, arbres de compétences, mécanique
   d'emboîtement/fusion des tourelles (packing + merge), maps infinies.

---

## À creuser / idées en réserve

- Tourelles **1×1 / 1×2 / 2×1** à emboîter (packing-puzzle) ; **drag une tourelle sur
  une identique = fusion + level up** (merge à la 2048).
- Couche **enquête / détective** optionnelle pour les niveaux non-combat.
- Cartes qui s'étendent à l'infini (« de plus en plus loin dans les vagues »).
