"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.FREE_FOR_ALL = void 0;
exports.effectivePro = effectivePro;
// Statut Pro effectif — logique pure, sans Firestore (testable via node --test).
//
// Ouverture (sept. 2026) : toutes les features Pro sont accessibles à tout le
// monde — l'app est l'outil des coachés, inclus dans le coaching. La mécanique
// d'entitlements (RevenueCat, grants, webhooks) reste en place et prête à être
// rallumée : repasser FREE_FOR_ALL à false pour réactiver l'abonnement
// (phase 3), SERVEUR D'ABORD, puis kFreeForAll côté app.
exports.FREE_FOR_ALL = true;
// Sources combinées d'un doc formation_access (l'une suffit, aucune n'écrase
// l'autre) :
//   - subscriptionUntil : abonné RevenueCat (iOS/Android), posé par le webhook
//   - proUntil          : grant daté (formation / comp admin)
//   - isPro (bool)      : legacy / sans expiration
function effectivePro(d, freeForAll = exports.FREE_FOR_ALL) {
    if (freeForAll)
        return true;
    const now = Date.now();
    const active = (v) => {
        const t = v;
        return !!t && typeof t.toMillis === "function" && t.toMillis() > now;
    };
    return active(d === null || d === void 0 ? void 0 : d.subscriptionUntil) || active(d === null || d === void 0 ? void 0 : d.proUntil) || (d === null || d === void 0 ? void 0 : d.isPro) === true;
}
//# sourceMappingURL=entitlements.js.map