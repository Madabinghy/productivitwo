import * as admin from "firebase-admin";
import { FieldValue } from "firebase-admin/firestore";

admin.initializeApp();
export const db = admin.firestore();
// Ignore les champs undefined à l'écriture (sinon Firestore lève une exception —
// ex: structure.gantt absent en Phase 1, parent/goalMin optionnels).
db.settings({ ignoreUndefinedProperties: true });
export { FieldValue };
