"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.FieldValue = exports.db = void 0;
const admin = require("firebase-admin");
const firestore_1 = require("firebase-admin/firestore");
Object.defineProperty(exports, "FieldValue", { enumerable: true, get: function () { return firestore_1.FieldValue; } });
admin.initializeApp();
exports.db = admin.firestore();
// Ignore les champs undefined à l'écriture (sinon Firestore lève une exception —
// ex: structure.gantt absent en Phase 1, parent/goalMin optionnels).
exports.db.settings({ ignoreUndefinedProperties: true });
//# sourceMappingURL=db.js.map