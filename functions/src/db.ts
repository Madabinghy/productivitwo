import * as admin from "firebase-admin";
import { FieldValue } from "firebase-admin/firestore";

admin.initializeApp();
export const db = admin.firestore();
// Ignore les champs undefined à l'écriture (sinon Firestore lève une exception —
// ex: structure.gantt absent en Phase 1, parent/goalMin optionnels).
db.settings({ ignoreUndefinedProperties: true });
export { FieldValue };

// Statut Pro effectif depuis un doc d'accès (formation_access). Sources
// combinées (l'une suffit, aucune n'écrase l'autre) :
//   - subscriptionUntil : abonné RevenueCat (iOS/Android), posé par le webhook
//   - proUntil          : grant daté (formation / comp admin)
//   - isPro (bool)      : legacy / sans expiration
export function effectivePro(d: Record<string, unknown> | undefined): boolean {
  const now = Date.now();
  const active = (v: unknown): boolean => {
    const t = v as { toMillis?: () => number } | undefined;
    return !!t && typeof t.toMillis === "function" && t.toMillis() > now;
  };
  return active(d?.subscriptionUntil) || active(d?.proUntil) || d?.isPro === true;
}
