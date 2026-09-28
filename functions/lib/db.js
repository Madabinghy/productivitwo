"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.effectivePro = exports.FREE_FOR_ALL = exports.FieldValue = exports.db = void 0;
const admin = require("firebase-admin");
const firestore_1 = require("firebase-admin/firestore");
Object.defineProperty(exports, "FieldValue", { enumerable: true, get: function () { return firestore_1.FieldValue; } });
admin.initializeApp();
exports.db = admin.firestore();
// Ignore les champs undefined à l'écriture (sinon Firestore lève une exception —
// ex: structure.gantt absent en Phase 1, parent/goalMin optionnels).
exports.db.settings({ ignoreUndefinedProperties: true });
// Statut Pro effectif (formation_access) — logique dans entitlements.ts, avec
// l'interrupteur FREE_FOR_ALL (ouverture sept. 2026).
var entitlements_1 = require("./entitlements");
Object.defineProperty(exports, "FREE_FOR_ALL", { enumerable: true, get: function () { return entitlements_1.FREE_FOR_ALL; } });
Object.defineProperty(exports, "effectivePro", { enumerable: true, get: function () { return entitlements_1.effectivePro; } });
//# sourceMappingURL=db.js.map