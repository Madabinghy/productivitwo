// APNs direct (HTTP/2) pour les Live Activities iOS — push‑to‑start (start) et fin
// (end). FCM ne sait PAS envoyer ce type de push → on parle à APNs en direct, signé
// par un JWT ES256 (clé .p8). Config lue dans l'environnement (secrets) :
//   APNS_KEY (contenu .p8), APNS_KEY_ID, APNS_TEAM_ID, APNS_BUNDLE_ID,
//   APNS_HOST (def: api.push.apple.com ; sandbox: api.sandbox.push.apple.com).
import * as http2 from "http2";
import { createSign } from "crypto";

function b64url(s: string | Buffer): string {
  return Buffer.from(s).toString("base64url");
}

// JWT APNs (ES256) — valable ~1 h, on le régénère à chaque envoi (simple, suffisant).
function apnsJwt(): string {
  const key = (process.env.APNS_KEY || "").replace(/\\n/g, "\n");
  const kid = process.env.APNS_KEY_ID || "";
  const iss = process.env.APNS_TEAM_ID || "";
  const header = b64url(JSON.stringify({ alg: "ES256", kid }));
  const payload = b64url(
    JSON.stringify({ iss, iat: Math.floor(Date.now() / 1000) }),
  );
  const signingInput = `${header}.${payload}`;
  const signer = createSign("SHA256");
  signer.update(signingInput);
  // ieee-p1363 = format JOSE (r||s) attendu par JWT ES256.
  const sig = signer.sign({ key, dsaEncoding: "ieee-p1363" });
  return `${signingInput}.${sig.toString("base64url")}`;
}

export interface ApnsResult {
  status: number;
  body: string;
}

function postLiveActivity(
  token: string,
  payload: Record<string, unknown>,
): Promise<ApnsResult> {
  const bundle = process.env.APNS_BUNDLE_ID || "";
  const host = process.env.APNS_HOST || "https://api.push.apple.com";
  const jwt = apnsJwt();
  return new Promise<ApnsResult>((resolve, reject) => {
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

export interface TimerAttributes {
  name: string;
  colorArgb: number;
}
export interface TimerContentState {
  startAtMs: number;
  paused: boolean;
}

// DÉMARRE une Live Activity à distance (app fermée) via le push‑to‑start token.
export function pushStartLiveActivity(
  pushToStartToken: string,
  attributes: TimerAttributes,
  state: TimerContentState,
): Promise<ApnsResult> {
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
export function pushEndLiveActivity(
  activityToken: string,
  state: TimerContentState,
): Promise<ApnsResult> {
  return postLiveActivity(activityToken, {
    aps: {
      timestamp: Math.floor(Date.now() / 1000),
      event: "end",
      "content-state": state,
      "dismissal-date": Math.floor(Date.now() / 1000),
    },
  });
}

export function apnsConfigured(): boolean {
  return !!(
    process.env.APNS_KEY &&
    process.env.APNS_KEY_ID &&
    process.env.APNS_TEAM_ID &&
    process.env.APNS_BUNDLE_ID
  );
}
