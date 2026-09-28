# Handoff — Ouvrir l'app (plus de Pro, mécanique en sommeil)

Décision (sept. 2026) : Productivitwo n'est plus une app payante pour l'instant — c'est l'outil
d'accompagnement des coachés, inclus dans l'offre de coaching. L'abonnement reviendra en phase 3
(cf. `CLAUDE.md`, cap produit). **On ouvre tout, on ne démonte rien** : la mécanique d'entitlements
(RevenueCat, grants, webhooks) reste en place, désactivée par deux flags, prête à être rallumée.

Écrit sur `origin/main` au commit `d8478fc`. Une PR code + une check-list hors code.

## 1. Deux flags, un seul endroit chacun

### Serveur — `functions/src/db.ts`
```ts
// Ouverture (sept. 2026) : toutes les features Pro sont accessibles à tout le
// monde. Repasser à false pour réactiver l'abonnement (phase 3).
export const FREE_FOR_ALL = true;

export function effectivePro(d) {
  if (FREE_FOR_ALL) return true;
  … (code actuel inchangé)
}
```
Effet immédiat, sans toucher aux appelants : ORION à `ORION_MAX_PRO` cycles/jour pour tous
(`orion.ts:146`), révisions Vision ouvertes (`onboardingChat`), `getVisionAccess` renvoie Pro,
`adminProductivitwo.listUsers` continue d'afficher la source réelle (Abo / Grant / Legacy) —
utile pour savoir qui payait avant.

### Mobile — `lib/pro_manager.dart`
```dart
/// Ouverture (sept. 2026) : Pro pour tous. Repasser à false pour réactiver
/// le paywall et RevenueCat (phase 3).
const kFreeForAll = true;

static void _recompute() =>
    notifier.value = kFreeForAll || _forcePro || _rcPro || _grantPro;
```
`init()` : quand `kFreeForAll`, **ne pas initialiser RevenueCat** (`Purchases.configure`) — pas
d'appel réseau au démarrage, pas de `Purchases.logIn`. Le reste de la classe est conservé.

## 2. UI à nettoyer (le code du paywall reste, il n'est plus appelé)

| Où | Quoi |
|---|---|
| `lib/main.dart:4809` (menu ⋯ → `sync_status`) | ouvrir directement `DevConsoleScreen`, plus de `showPaywallSheet` |
| `lib/widgets/orion_screen.dart:235-240, 722` | limite = `_kLimitPro` ; message d'erreur sans « Passe à Pro » ; retirer le lien vers le paywall |
| `lib/widgets/paywall_sheet.dart:536` | fichier conservé, plus aucun appelant — ajouter un commentaire d'en-tête « inactif tant que `kFreeForAll` » |
| Réglages mobile | retirer l'entrée « Gérer mon abonnement » / « Restaurer les achats » si présente ; garder le code derrière `if (!kFreeForAll)` |
| Web (`lib/web/`) | vérifier qu'aucune carte Vision / « Passer en Pro » n'a survécu au lot 7 (`grep -rn "Passer en Pro\|isPro" lib/web`) |
| Textes | `grep -rn "Pro\b" lib --include=*.dart` : retirer les mentions dans l'UI (badges « Pro », « Fonction Pro »), garder les identifiants techniques |

Ne pas supprimer : `revenueCatWebhook`, `generateFormationAccess`, `setPro` admin, la collection
`formation_access`, `purchases_flutter` dans `pubspec.yaml`. Tout reste déployé et fonctionnel.

## 3. Tests

- `functions/` : test unitaire `effectivePro({}) === true` quand `FREE_FOR_ALL`, et le comportement
  actuel quand `false` (les deux branches restent testées).
- Mobile : `ProManager.isPro == true` au démarrage sans réseau ; aucun appel RevenueCat dans les
  logs au lancement.
- Manuel : ORION 5 cycles/jour sur un compte sans grant ; Vision : deuxième session possible.

## 4. Hors code — à faire par Emeric

1. **App Store Connect → Abonnements** : passer les deux produits (`productivitwo_pro_monthly`,
   `productivitwo_pro_annual`) en « Retiré de la vente » (*Remove from sale*), sans les supprimer :
   ils se réactivent en phase 3 avec leur historique. Sans ça, une mise à jour peut être refusée
   pour IAP déclarés mais inaccessibles (guideline 3.1.1).
2. **RevenueCat** : vérifier s'il reste des abonnés actifs ; un abonné continue d'être facturé tant
   qu'il ne résilie pas. S'il y en a, les prévenir et leur proposer la résiliation (Réglages iOS →
   Abonnements) ; un remboursement se demande via App Store Connect.
3. **Fiche App Store** : retirer la mention des achats intégrés dans la description et les captures
   si elles montrent le paywall ; la métadonnée « Achats intégrés » disparaît d'elle-même une fois
   les produits retirés.
4. **Tunnel systeme.io** (formation à 97 €) : le webhook continue de poser un grant, désormais sans
   effet visible. Décider : mettre le tunnel en pause, ou le garder comme formation seule (le
   contenu de cours reste sa valeur). Rien à changer côté code dans les deux cas.
5. **Landing productivitwo.com** : retirer le bloc tarifs / « Pro » s'il y en a un ; remplacer par
   l'accès via le coaching.
6. **Accès web** : inchangé — l'allowlist reste le seul garde-fou (`sendMagicLink`). Inviter un
   coaché = ajouter son email via `/admin.html`.

## 5. Pour rallumer plus tard (phase 3)

`FREE_FOR_ALL = false` + `kFreeForAll = false`, remettre les produits en vente dans App Store
Connect, rebrancher les deux appels au paywall, déployer functions puis publier l'app. Les grants
et abonnements existants reprennent leur effet tels quels. Ordre à respecter : **serveur d'abord**
(sinon des mobiles à jour verraient un paywall pendant que le serveur ouvre encore tout — ou
l'inverse, plus gênant).

## 6. Décisions prises (ne pas rouvrir)

- Ouverture par flags, pas de suppression : RevenueCat, webhooks, grants, paywall restent dans le
  code, inactifs.
- Aucun changement de modèle Firestore ni de règles.
- L'accès web reste sur allowlist.
