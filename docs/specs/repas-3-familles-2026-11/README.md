# Repas en 3 familles — handoff (2026-11-04)

Spec validée par l'utilisateur (Claude Docs « Repas en 3 familles — spec Productivitwo » + maquette Design
« Repas en 3 familles — maquette » : Composer un repas · Placards par famille · Petit-déjeuner). Trois créneaux
(petit-déj · midi · soir), pas de collation (décision user 2026-11-04).

## Principe

Un repas = des briques prises dans 3 familles : **protéines · féculents · fibres** (légumes, fruits). **Deux
familles sur trois suffisent.** Ce qui n'est dans aucune (ail, oignon, sauces, épices, desserts…) est un
**accompagnement** : affiché, jamais compté. On combine au lieu de créer un plat par combinaison
(côte de porc + pâtes, côte de porc + riz, steak + pâtes…). Zéro gestion : la famille est déduite, corrigée
seulement si elle est fausse. Pas de grammage, de portions, de calories. Un plat complet (`Recipe`) reste un plat.
Légumineuses = féculent ET protéine.

## Intégration à l'existant (Repas et menu, Mes placards)

- Familles par mot : `data/meta.groceries.families {<normLabel>: "proteines" | "feculents,proteines" | …}`,
  comme le rayon (`memory.<mot>.aisle`). Résolution `familiesFor` : retenue → devinée (`guessFamilies`) → rayon non
  alimentaire (Ménager · Hygiène · Boissons) = aucune → sinon accompagnement.
- Repas : on garde `data/meta.meals.plans.<lundi>.<ymd|moment>` (`PlannedMeal`). Lot 2 : `kMealMoments` devient
  `petit-dej · midi · soir` et `PlannedMeal.components [{family, label}]` (sans `recipeId`) ; un repas composé est
  valide s'il couvre ≥ 2 familles. Les restes ne vont toujours qu'aux midis.

## Lots

1. **Familles des produits** (livré) — `utils/meal_families.dart` ↔ `functions/src/meal_families.ts`
   (**garder alignés** : mots-clés, ordre ; le mot-clé le plus long gagne, à égalité la première famille de la liste),
   `Groceries.families`, `AppLogic.setFoodFamilies`, `FirestoreSync.setFoodFamily`, `pantryByFamily`. MCP :
   `record_receipt` lignes `{family}`, `update_pantry {family}` (`""` = automatique), `get_pantry` sans filtre
   ajoute « PAR FAMILLE ». Rien de visible dans l'app.
2. **Petit-déj + composer un repas** (livré, avec les suggestions locales du lot 3) — créneau `petit-dej` (feuille Repas, Les repas de la semaine, `mealWeekView`
   : avant 10 h 30 = petit-déj), `PlannedMeal.components`, écran « Composer un repas » (sélecteur Petit-déj · Midi ·
   Soir ; une rangée de pastilles par famille avec ce qu'on a au placard ; assiette à 3 cases ; « Valider » dès 2
   familles). Petit-déj : rangées limitées aux produits déjà pris le matin (appris), sinon défauts pain · céréales ·
   œufs · yaourt · fruits.
3. **Suggestions + MCP** (suggestions livrées au lot 2 ; reste le MCP) — score local (3 familles +3 / 2 : +1 ; produit Frais ou Fruits et légumes acheté il y a
   > 3 j : +2 ; combinaison déjà validée : +1 ; même protéine qu'au repas précédent : −2, hors petit-déj ;
   identique < 3 j : −3), 3 meilleures, « Je prends » en un tap. MCP `get_meal_options(date, slot)` et
   `plan_meals(meals[], apply)`.
4. **Placards par famille** — compteurs par famille dans Mes placards, rangée vide = « ajouter à la liste ».

Hors périmètre : grammages, portions, calories, macros, recettes pas à pas, planification sans validation.
