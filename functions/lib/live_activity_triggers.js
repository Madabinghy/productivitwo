"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.onSessionEndLiveActivity = exports.onSessionStartLiveActivity = void 0;
// Triggers Firestore → push APNs Live Activity (Phase 2 : démarrage/fin distant,
// app fermée). NON BRANCHÉ à index.ts tant que les secrets APNs ne sont pas posés :
// une fois `firebase functions:secrets:set APNS_KEY ...` fait, ajoute dans index.ts
//   export { onSessionStartLiveActivity, onSessionEndLiveActivity } from "./live_activity_triggers";
// puis déploie. Sans cela, rien ne se déploie (et le déploiement existant reste safe).
const firestore_1 = require("firebase-functions/v2/firestore");
const params_1 = require("firebase-functions/params");
const db_1 = require("./db");
const apns_1 = require("./apns");
const APNS_KEY = (0, params_1.defineSecret)("APNS_KEY");
const APNS_KEY_ID = (0, params_1.defineSecret)("APNS_KEY_ID");
const APNS_TEAM_ID = (0, params_1.defineSecret)("APNS_TEAM_ID");
const APNS_BUNDLE_ID = (0, params_1.defineSecret)("APNS_BUNDLE_ID");
const apnsSecrets = [APNS_KEY, APNS_KEY_ID, APNS_TEAM_ID, APNS_BUNDLE_ID];
const DEFAULT_COLOR = 0xff4f8df7;
// Session créée (endAt absent) → DÉMARRE une Live Activity à distance (app fermée)
// via le push‑to‑start token de l'utilisateur.
exports.onSessionStartLiveActivity = (0, firestore_1.onDocumentCreated)({ document: "users/{uid}/sessions/{sessionId}", secrets: apnsSecrets }, async (event) => {
    var _a, _b, _c;
    if (!(0, apns_1.apnsConfigured)())
        return;
    const data = (_a = event.data) === null || _a === void 0 ? void 0 : _a.data();
    if (!data || data.endAt)
        return; // session déjà fermée → rien
    const uid = event.params.uid;
    const laSnap = await db_1.db.doc(`users/${uid}/live_activity/main`).get();
    const token = (_b = laSnap.data()) === null || _b === void 0 ? void 0 : _b.pushToStartToken;
    if (!token)
        return; // pas de token (app jamais ouverte) → pas de start distant
    let name = "Activité";
    try {
        const act = await db_1.db
            .doc(`users/${uid}/activities/${data.activityId}`)
            .get();
        name = ((_c = act.data()) === null || _c === void 0 ? void 0 : _c.name) || name;
    }
    catch (_) {
        /* nom par défaut */
    }
    const startAtMs = Date.parse(data.startAt) || Date.now();
    try {
        const res = await (0, apns_1.pushStartLiveActivity)(token, { name, colorArgb: DEFAULT_COLOR }, { startAtMs, paused: false });
        if (res.status >= 400) {
            console.error("APNs start non-2xx", res.status, res.body);
        }
    }
    catch (e) {
        console.error("APNs start failed", e);
    }
});
// Session fermée (endAt vient d'être posé) → TERMINE la Live Activity via son token
// d'activité (rapporté par l'app dans le doc live_activity/main).
exports.onSessionEndLiveActivity = (0, firestore_1.onDocumentUpdated)({ document: "users/{uid}/sessions/{sessionId}", secrets: apnsSecrets }, async (event) => {
    var _a, _b, _c;
    if (!(0, apns_1.apnsConfigured)())
        return;
    const before = (_a = event.data) === null || _a === void 0 ? void 0 : _a.before.data();
    const after = (_b = event.data) === null || _b === void 0 ? void 0 : _b.after.data();
    if (!before || !after)
        return;
    if (before.endAt || !after.endAt)
        return; // ne réagit qu'à la 1ʳᵉ fermeture
    const uid = event.params.uid;
    const laSnap = await db_1.db.doc(`users/${uid}/live_activity/main`).get();
    const token = (_c = laSnap.data()) === null || _c === void 0 ? void 0 : _c.activityPushToken;
    if (!token)
        return;
    const startAtMs = Date.parse(after.startAt) || Date.now();
    try {
        const res = await (0, apns_1.pushEndLiveActivity)(token, { startAtMs, paused: false });
        if (res.status >= 400) {
            console.error("APNs end non-2xx", res.status, res.body);
        }
    }
    catch (e) {
        console.error("APNs end failed", e);
    }
});
//# sourceMappingURL=live_activity_triggers.js.map