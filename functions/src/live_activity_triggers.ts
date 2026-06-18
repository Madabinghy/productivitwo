// Triggers Firestore → push APNs Live Activity (Phase 2 : démarrage/fin distant,
// app fermée). NON BRANCHÉ à index.ts tant que les secrets APNs ne sont pas posés :
// une fois `firebase functions:secrets:set APNS_KEY ...` fait, ajoute dans index.ts
//   export { onSessionStartLiveActivity, onSessionEndLiveActivity } from "./live_activity_triggers";
// puis déploie. Sans cela, rien ne se déploie (et le déploiement existant reste safe).
import { onDocumentCreated, onDocumentUpdated } from "firebase-functions/v2/firestore";
import { defineSecret } from "firebase-functions/params";
import { db } from "./db";
import {
  pushStartLiveActivity,
  pushEndLiveActivity,
  apnsConfigured,
} from "./apns";

const APNS_KEY = defineSecret("APNS_KEY");
const APNS_KEY_ID = defineSecret("APNS_KEY_ID");
const APNS_TEAM_ID = defineSecret("APNS_TEAM_ID");
const APNS_BUNDLE_ID = defineSecret("APNS_BUNDLE_ID");
const apnsSecrets = [APNS_KEY, APNS_KEY_ID, APNS_TEAM_ID, APNS_BUNDLE_ID];

const DEFAULT_COLOR = 0xff4f8df7;

// Session créée (endAt absent) → DÉMARRE une Live Activity à distance (app fermée)
// via le push‑to‑start token de l'utilisateur.
export const onSessionStartLiveActivity = onDocumentCreated(
  { document: "users/{uid}/sessions/{sessionId}", secrets: apnsSecrets },
  async (event) => {
    if (!apnsConfigured()) return;
    const data = event.data?.data();
    if (!data || data.endAt) return; // session déjà fermée → rien
    const uid = event.params.uid as string;

    const laSnap = await db.doc(`users/${uid}/live_activity/main`).get();
    const token = laSnap.data()?.pushToStartToken as string | undefined;
    if (!token) return; // pas de token (app jamais ouverte) → pas de start distant

    let name = "Activité";
    try {
      const act = await db
        .doc(`users/${uid}/activities/${data.activityId}`)
        .get();
      name = (act.data()?.name as string) || name;
    } catch (_) {
      /* nom par défaut */
    }
    const startAtMs = Date.parse(data.startAt) || Date.now();

    try {
      const res = await pushStartLiveActivity(
        token,
        { name, colorArgb: DEFAULT_COLOR },
        { startAtMs, paused: false },
      );
      if (res.status >= 400) {
        console.error("APNs start non-2xx", res.status, res.body);
      }
    } catch (e) {
      console.error("APNs start failed", e);
    }
  },
);

// Session fermée (endAt vient d'être posé) → TERMINE la Live Activity via son token
// d'activité (rapporté par l'app dans le doc live_activity/main).
export const onSessionEndLiveActivity = onDocumentUpdated(
  { document: "users/{uid}/sessions/{sessionId}", secrets: apnsSecrets },
  async (event) => {
    if (!apnsConfigured()) return;
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after) return;
    if (before.endAt || !after.endAt) return; // ne réagit qu'à la 1ʳᵉ fermeture
    const uid = event.params.uid as string;

    const laSnap = await db.doc(`users/${uid}/live_activity/main`).get();
    const token = laSnap.data()?.activityPushToken as string | undefined;
    if (!token) return;
    const startAtMs = Date.parse(after.startAt) || Date.now();

    try {
      const res = await pushEndLiveActivity(token, { startAtMs, paused: false });
      if (res.status >= 400) {
        console.error("APNs end non-2xx", res.status, res.body);
      }
    } catch (e) {
      console.error("APNs end failed", e);
    }
  },
);
