/// Ouverture (sept. 2026) : Pro pour tout le monde — Productivitwo est l'outil
/// des coachés, inclus dans le coaching. La mécanique d'abonnement (RevenueCat,
/// grants, paywall) reste dans le code, inactive. Repasser à false pour
/// réactiver le paywall (phase 3) — APRÈS `FREE_FOR_ALL` côté serveur
/// (`functions/src/entitlements.ts`), jamais avant.
const kFreeForAll = true;
