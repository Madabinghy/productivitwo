"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.FieldValue = exports.db = void 0;
exports.effectivePro = effectivePro;
const admin = require("firebase-admin");
const firestore_1 = require("firebase-admin/firestore");
Object.defineProperty(exports, "FieldValue", { enumerable: true, get: function () { return firestore_1.FieldValue; } });
admin.initializeApp();
exports.db = admin.firestore();
// Ignore les champs undefined à l'écriture (sinon Firestore lève une exception —
// ex: structure.gantt absent en Phase 1, parent/goalMin optionnels).
exports.db.settings({ ignoreUndefinedProperties: true });
// Statut Pro effectif depuis un doc d'accès (formation_access). Sources
// combinées (l'une suffit, aucune n'écrase l'autre) :
//   - subscriptionUntil : abonné RevenueCat (iOS/Android), posé par le webhook
//   - proUntil          : grant daté (formation / comp admin)
//   - isPro (bool)      : legacy / sans expiration
function effectivePro(d) {
    const now = Date.now();
    const active = (v) => {
        const t = v;
        return !!t && typeof t.toMillis === "function" && t.toMillis() > now;
    };
    return active(d === null || d === void 0 ? void 0 : d.subscriptionUntil) || active(d === null || d === void 0 ? void 0 : d.proUntil) || (d === null || d === void 0 ? void 0 : d.isPro) === true;
}
//# sourceMappingURL=db.js.map