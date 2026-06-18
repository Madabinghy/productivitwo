"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.pushStartLiveActivity = pushStartLiveActivity;
exports.pushEndLiveActivity = pushEndLiveActivity;
exports.apnsConfigured = apnsConfigured;
// APNs direct (HTTP/2) pour les Live Activities iOS — push‑to‑start (start) et fin
// (end). FCM ne sait PAS envoyer ce type de push → on parle à APNs en direct, signé
// par un JWT ES256 (clé .p8). Config lue dans l'environnement (secrets) :
//   APNS_KEY (contenu .p8), APNS_KEY_ID, APNS_TEAM_ID, APNS_BUNDLE_ID,
//   APNS_HOST (def: api.push.apple.com ; sandbox: api.sandbox.push.apple.com).
const http2 = require("http2");
const crypto_1 = require("crypto");
function b64url(s) {
    return Buffer.from(s).toString("base64url");
}
// JWT APNs (ES256) — valable ~1 h, on le régénère à chaque envoi (simple, suffisant).
function apnsJwt() {
    const key = (process.env.APNS_KEY || "").replace(/\\n/g, "\n");
    const kid = process.env.APNS_KEY_ID || "";
    const iss = process.env.APNS_TEAM_ID || "";
    const header = b64url(JSON.stringify({ alg: "ES256", kid }));
    const payload = b64url(JSON.stringify({ iss, iat: Math.floor(Date.now() / 1000) }));
    const signingInput = `${header}.${payload}`;
    const signer = (0, crypto_1.createSign)("SHA256");
    signer.update(signingInput);
    // ieee-p1363 = format JOSE (r||s) attendu par JWT ES256.
    const sig = signer.sign({ key, dsaEncoding: "ieee-p1363" });
    return `${signingInput}.${sig.toString("base64url")}`;
}
function postLiveActivity(token, payload) {
    const bundle = process.env.APNS_BUNDLE_ID || "";
    const host = process.env.APNS_HOST || "https://api.push.apple.com";
    const jwt = apnsJwt();
    return new Promise((resolve, reject) => {
        const client = http2.connect(host);
        client.on("error", reject);
        const req = client.request({
            ":method": "POST",
            ":path": `/3/device/${token}`,
            authorization: `bearer ${jwt}`,
            "apns-topic": `${bundle}.push-type.liveactivity`,
            "apns-push-type": "liveactivity",
            "apns-priority": "10",
        });
        let status = 0;
        let data = "";
        req.on("response", (h) => {
            status = Number(h[":status"]) || 0;
        });
        req.setEncoding("utf8");
        req.on("data", (c) => {
            data += c;
        });
        req.on("end", () => {
            client.close();
            resolve({ status, body: data });
        });
        req.on("error", (e) => {
            client.close();
            reject(e);
        });
        req.write(JSON.stringify(payload));
        req.end();
    });
}
// DÉMARRE une Live Activity à distance (app fermée) via le push‑to‑start token.
function pushStartLiveActivity(pushToStartToken, attributes, state) {
    return postLiveActivity(pushToStartToken, {
        aps: {
            timestamp: Math.floor(Date.now() / 1000),
            event: "start",
            "attributes-type": "TimerActivityAttributes",
            attributes,
            "content-state": state,
            alert: { title: attributes.name, body: "Minuteur lancé ⏱" },
        },
    });
}
// TERMINE une Live Activity via son token d'activité (rapporté par l'app).
function pushEndLiveActivity(activityToken, state) {
    return postLiveActivity(activityToken, {
        aps: {
            timestamp: Math.floor(Date.now() / 1000),
            event: "end",
            "content-state": state,
            "dismissal-date": Math.floor(Date.now() / 1000),
        },
    });
}
function apnsConfigured() {
    return !!(process.env.APNS_KEY &&
        process.env.APNS_KEY_ID &&
        process.env.APNS_TEAM_ID &&
        process.env.APNS_BUNDLE_ID);
}
//# sourceMappingURL=apns.js.map