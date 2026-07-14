"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.gcalOnScheduleWrite = exports.gcalOauthCallback = exports.gcalApi = void 0;
exports.syncDayToGcal = syncDayToGcal;
const https_1 = require("firebase-functions/v2/https");
const firestore_1 = require("firebase-functions/v2/firestore");
const firestore_2 = require("firebase-admin/firestore");
const crypto_1 = require("crypto");
const db_1 = require("./db");
const execute_1 = require("./execute");
const CALLBACK_URL = "https://gcaloauthcallback-dzos75b65q-uc.a.run.app";
const SCOPES = "openid email https://www.googleapis.com/auth/calendar.events";
const CAL_BASE = "https://www.googleapis.com/calendar/v3/calendars/primary";
const GCAL_SECRETS = ["GCAL_CLIENT_ID", "GCAL_CLIENT_SECRET"];
const tokensRef = (uid) => db_1.db.doc(`gcal_tokens/${uid}`);
/** Fuseau VÉCU de l'utilisateur : fait `data/meta.tzOffsetMin` (minutes à
 *  ajouter à l'UTC, ex -240 en Guadeloupe) posé par l'app à l'ouverture.
 *  Null = fait absent → fallback Europe/Paris via userDayParts. */
async function userTzOffset(uid) {
    var _a;
    const snap = await db_1.db.doc(`users/${uid}/data/meta`).get();
    const v = (_a = snap.data()) === null || _a === void 0 ? void 0 : _a.tzOffsetMin;
    return typeof v === "number" && isFinite(v) ? v : null;
}
/** Offset RFC3339 (« -04:00 ») depuis des minutes. */
function offsetStr(offsetMin) {
    const sign = offsetMin < 0 ? "-" : "+";
    const abs = Math.abs(offsetMin);
    return `${sign}${String(Math.floor(abs / 60)).padStart(2, "0")}:${String(abs % 60).padStart(2, "0")}`;
}
// ── Access token : lit le cache, sinon refresh. Null = pas connecté. ────────
async function accessTokenFor(uid) {
    var _a, _b, _c;
    const snap = await tokensRef(uid).get();
    if (!snap.exists)
        return null;
    const d = snap.data();
    if (!d.refreshToken)
        return null;
    if (d.accessToken && typeof d.accessTokenExp === "number" &&
        d.accessTokenExp > Date.now() + 60000) {
        return d.accessToken;
    }
    const res = await fetch("https://oauth2.googleapis.com/token", {
        method: "POST",
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body: new URLSearchParams({
            client_id: (_a = process.env.GCAL_CLIENT_ID) !== null && _a !== void 0 ? _a : "",
            client_secret: (_b = process.env.GCAL_CLIENT_SECRET) !== null && _b !== void 0 ? _b : "",
            refresh_token: d.refreshToken,
            grant_type: "refresh_token",
        }).toString(),
    });
    const body = (await res.json());
    if (!res.ok || !body.access_token) {
        // Accès révoqué côté Google : on le note, le statut app le montrera.
        console.error("gcal refresh failed:", res.status, JSON.stringify(body));
        if (body.error === "invalid_grant") {
            await tokensRef(uid).set({ revoked: true }, { merge: true });
        }
        return null;
    }
    await tokensRef(uid).set({
        accessToken: body.access_token,
        accessTokenExp: Date.now() + (Number((_c = body.expires_in) !== null && _c !== void 0 ? _c : 3600) - 60) * 1000,
        revoked: firestore_2.FieldValue.delete(),
    }, { merge: true });
    return body.access_token;
}
// ── Sync d'un jour : diff programme ↔ agenda (idempotent) ────────────────────
const hmToMin = (hm) => parseInt(hm.slice(0, 2), 10) * 60 + parseInt(hm.slice(3, 5), 10);
/** date + minutes depuis minuit → {ymd, HH:mm} (gère le passage de minuit). */
function dateTimeOf(date, minutes) {
    const dayShift = Math.floor(minutes / 1440);
    const m = ((minutes % 1440) + 1440) % 1440;
    let ymd = date;
    if (dayShift !== 0) {
        const d = new Date(`${date}T12:00:00Z`);
        d.setUTCDate(d.getUTCDate() + dayShift);
        ymd = d.toISOString().slice(0, 10);
    }
    return {
        ymd,
        hm: `${String(Math.floor(m / 60)).padStart(2, "0")}:${String(m % 60).padStart(2, "0")}`,
    };
}
async function syncDayToGcal(uid, date) {
    var _a, _b, _c, _d, _e, _f, _g, _h, _j, _k, _l, _m, _o, _p;
    const none = { created: 0, updated: 0, deleted: 0 };
    if (!/^\d{4}-\d{2}-\d{2}$/.test(date))
        return Object.assign(Object.assign({ ok: false }, none), { reason: "bad_date" });
    const token = await accessTokenFor(uid);
    if (!token)
        return Object.assign(Object.assign({ ok: false }, none), { reason: "not_connected" });
    const auth = { Authorization: `Bearer ${token}` };
    // Les heures du programme sont des heures de MUR du téléphone : l'événement
    // porte l'offset du fuseau vécu (fait) — sinon fallback Europe/Paris.
    const tzOff = await userTzOffset(uid);
    // Blocs vivants du programme (doc absent = tout supprimer côté agenda).
    const snap = await db_1.db.doc(`users/${uid}/daily_schedules/${date}`).get();
    const blocks = ((_b = (_a = snap.data()) === null || _a === void 0 ? void 0 : _a.blocks) !== null && _b !== void 0 ? _b : []).filter((b) => {
        var _a, _b;
        return (b.status === "pending" || b.status === "done") &&
            /^\d{2}:\d{2}$/.test(String((_a = b.startTime) !== null && _a !== void 0 ? _a : "")) &&
            String((_b = b.title) !== null && _b !== void 0 ? _b : "").trim() !== "" &&
            b.id;
    });
    // Événements Productivitwo existants pour CE jour (jamais les personnels).
    const listRes = await fetch(`${CAL_BASE}/events?privateExtendedProperty=${encodeURIComponent(`pwoDate=${date}`)}&maxResults=250&showDeleted=false`, { headers: auth });
    if (!listRes.ok) {
        console.error("gcal list failed:", listRes.status, await listRes.text());
        return Object.assign(Object.assign({ ok: false }, none), { reason: `list_http_${listRes.status}` });
    }
    const listBody = (await listRes.json());
    const existing = new Map();
    for (const ev of (_c = listBody.items) !== null && _c !== void 0 ? _c : []) {
        const bid = (_e = (_d = ev.extendedProperties) === null || _d === void 0 ? void 0 : _d.private) === null || _e === void 0 ? void 0 : _e.pwoBlockId;
        if (bid)
            existing.set(String(bid), ev);
    }
    let created = 0, updated = 0, deleted = 0;
    const seen = new Set();
    for (const b of blocks) {
        const id = String(b.id);
        seen.add(id);
        const startMin = hmToMin(String(b.startTime));
        const dur = Math.max(5, Number((_f = b.durationMin) !== null && _f !== void 0 ? _f : 30));
        const start = dateTimeOf(date, startMin);
        const end = dateTimeOf(date, startMin + dur);
        const desired = {
            summary: String(b.title),
            description: [
                b.subtitle ? String(b.subtitle) : null,
                "source: productivitwo",
            ].filter(Boolean).join("\n"),
            start: tzOff != null
                ? { dateTime: `${start.ymd}T${start.hm}:00${offsetStr(tzOff)}` }
                : { dateTime: `${start.ymd}T${start.hm}:00`, timeZone: "Europe/Paris" },
            end: tzOff != null
                ? { dateTime: `${end.ymd}T${end.hm}:00${offsetStr(tzOff)}` }
                : { dateTime: `${end.ymd}T${end.hm}:00`, timeZone: "Europe/Paris" },
            extendedProperties: { private: { pwo: "1", pwoBlockId: id, pwoDate: date } },
        };
        const ev = existing.get(id);
        if (ev == null) {
            const r = await fetch(`${CAL_BASE}/events`, {
                method: "POST",
                headers: Object.assign(Object.assign({}, auth), { "Content-Type": "application/json" }),
                body: JSON.stringify(desired),
            });
            if (r.ok)
                created++;
            else
                console.error("gcal insert failed:", r.status, await r.text());
        }
        else {
            // Avec offset connu : comparaison d'INSTANTS (Google peut renvoyer la
            // même heure sous une autre représentation). Sinon, heure de mur.
            const sameStart = tzOff != null
                ? Date.parse(String((_h = (_g = ev.start) === null || _g === void 0 ? void 0 : _g.dateTime) !== null && _h !== void 0 ? _h : "")) ===
                    Date.parse(`${start.ymd}T${start.hm}:00${offsetStr(tzOff)}`)
                : String((_k = (_j = ev.start) === null || _j === void 0 ? void 0 : _j.dateTime) !== null && _k !== void 0 ? _k : "").startsWith(`${start.ymd}T${start.hm}`);
            const sameEnd = tzOff != null
                ? Date.parse(String((_m = (_l = ev.end) === null || _l === void 0 ? void 0 : _l.dateTime) !== null && _m !== void 0 ? _m : "")) ===
                    Date.parse(`${end.ymd}T${end.hm}:00${offsetStr(tzOff)}`)
                : String((_p = (_o = ev.end) === null || _o === void 0 ? void 0 : _o.dateTime) !== null && _p !== void 0 ? _p : "").startsWith(`${end.ymd}T${end.hm}`);
            if (ev.summary !== desired.summary || !sameStart || !sameEnd) {
                const r = await fetch(`${CAL_BASE}/events/${ev.id}`, {
                    method: "PATCH",
                    headers: Object.assign(Object.assign({}, auth), { "Content-Type": "application/json" }),
                    body: JSON.stringify(desired),
                });
                if (r.ok)
                    updated++;
                else
                    console.error("gcal patch failed:", r.status, await r.text());
            }
        }
    }
    // Blocs supprimés/sautés du programme → leurs événements partent aussi.
    for (const [bid, ev] of existing) {
        if (seen.has(bid))
            continue;
        const r = await fetch(`${CAL_BASE}/events/${ev.id}`, { method: "DELETE", headers: auth });
        if (r.ok || r.status === 404 || r.status === 410)
            deleted++;
        else
            console.error("gcal delete failed:", r.status, await r.text());
    }
    return { ok: true, created, updated, deleted };
}
// ── API app : status / authUrl / setAutoSync / syncDay / disconnect ──────────
exports.gcalApi = (0, https_1.onRequest)({ cors: true, invoker: "public", secrets: GCAL_SECRETS }, async (req, res) => {
    var _a, _b, _c, _d;
    if (req.method === "OPTIONS") {
        res.status(204).send("");
        return;
    }
    if (req.method !== "POST") {
        res.status(405).json({ error: "Method Not Allowed" });
        return;
    }
    const authHeader = (_a = req.headers.authorization) !== null && _a !== void 0 ? _a : "";
    if (!authHeader.startsWith("Bearer ")) {
        res.status(401).json({ error: "Missing Authorization header" });
        return;
    }
    const { uid, action, date, value } = req.body;
    if (!uid || !action) {
        res.status(400).json({ error: "uid et action requis" });
        return;
    }
    const valid = await (0, execute_1.validateToken)(uid, authHeader.slice(7).trim());
    if (!valid) {
        res.status(401).json({ error: "Token invalide ou révoqué" });
        return;
    }
    try {
        if (action === "status") {
            const snap = await tokensRef(uid).get();
            const d = snap.data();
            res.status(200).json({
                connected: snap.exists && !!(d === null || d === void 0 ? void 0 : d.refreshToken),
                email: (_b = d === null || d === void 0 ? void 0 : d.email) !== null && _b !== void 0 ? _b : null,
                autoSync: (d === null || d === void 0 ? void 0 : d.autoSync) !== false,
                revoked: (d === null || d === void 0 ? void 0 : d.revoked) === true,
            });
            return;
        }
        if (action === "authUrl") {
            const state = (0, crypto_1.randomUUID)();
            await db_1.db.doc(`gcal_oauth_states/${state}`).set({
                uid,
                createdAt: firestore_2.FieldValue.serverTimestamp(),
                expiresAt: Date.now() + 15 * 60000,
            });
            const url = "https://accounts.google.com/o/oauth2/v2/auth?" +
                new URLSearchParams({
                    client_id: (_c = process.env.GCAL_CLIENT_ID) !== null && _c !== void 0 ? _c : "",
                    redirect_uri: CALLBACK_URL,
                    response_type: "code",
                    scope: SCOPES,
                    access_type: "offline",
                    prompt: "consent",
                    state,
                }).toString();
            res.status(200).json({ url });
            return;
        }
        if (action === "setAutoSync") {
            await tokensRef(uid).set({ autoSync: value === true }, { merge: true });
            res.status(200).json({ ok: true, autoSync: value === true });
            return;
        }
        if (action === "syncDay") {
            const d = date && /^\d{4}-\d{2}-\d{2}$/.test(date)
                ? date
                : (0, execute_1.userDayParts)(await userTzOffset(uid)).ymd;
            res.status(200).json(await syncDayToGcal(uid, d));
            return;
        }
        if (action === "disconnect") {
            const snap = await tokensRef(uid).get();
            const refresh = (_d = snap.data()) === null || _d === void 0 ? void 0 : _d.refreshToken;
            if (refresh) {
                // Révocation best-effort — la suppression du doc fait foi.
                await fetch("https://oauth2.googleapis.com/revoke", {
                    method: "POST",
                    headers: { "Content-Type": "application/x-www-form-urlencoded" },
                    body: new URLSearchParams({ token: refresh }).toString(),
                }).catch(() => null);
            }
            await tokensRef(uid).delete();
            res.status(200).json({ ok: true });
            return;
        }
        res.status(400).json({ error: `action inconnue : ${action}` });
    }
    catch (e) {
        console.error("gcalApi error:", e);
        res.status(500).json({ error: "Erreur Google Agenda" });
    }
});
// ── Callback OAuth (navigateur) ───────────────────────────────────────────────
const htmlPage = (title, body) => `<!DOCTYPE html>
<html lang="fr"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>${title}</title>
<style>body{font-family:-apple-system,sans-serif;background:#101418;color:#e8eef2;display:flex;align-items:center;justify-content:center;min-height:100vh;margin:0}
main{text-align:center;padding:32px;max-width:420px}h1{font-size:20px}p{color:#9fb0bb;line-height:1.5}</style>
</head><body><main><h1>${title}</h1><p>${body}</p></main></body></html>`;
exports.gcalOauthCallback = (0, https_1.onRequest)({ cors: true, invoker: "public", secrets: GCAL_SECRETS }, async (req, res) => {
    var _a, _b, _c, _d, _e, _f, _g, _h, _j;
    const code = String((_a = req.query.code) !== null && _a !== void 0 ? _a : "");
    const state = String((_b = req.query.state) !== null && _b !== void 0 ? _b : "");
    const fail = (msg) => res.status(400).send(htmlPage("Connexion impossible", msg));
    if (!code || !state) {
        fail("Paramètres manquants — relance la connexion depuis l'app.");
        return;
    }
    try {
        const stateRef = db_1.db.doc(`gcal_oauth_states/${state}`);
        const stateSnap = await stateRef.get();
        const st = stateSnap.data();
        await stateRef.delete().catch(() => null);
        if (!stateSnap.exists || !(st === null || st === void 0 ? void 0 : st.uid) || Number((_c = st.expiresAt) !== null && _c !== void 0 ? _c : 0) < Date.now()) {
            fail("Lien expiré — relance la connexion depuis l'app.");
            return;
        }
        const uid = String(st.uid);
        const tokenRes = await fetch("https://oauth2.googleapis.com/token", {
            method: "POST",
            headers: { "Content-Type": "application/x-www-form-urlencoded" },
            body: new URLSearchParams({
                code,
                client_id: (_d = process.env.GCAL_CLIENT_ID) !== null && _d !== void 0 ? _d : "",
                client_secret: (_e = process.env.GCAL_CLIENT_SECRET) !== null && _e !== void 0 ? _e : "",
                redirect_uri: CALLBACK_URL,
                grant_type: "authorization_code",
            }).toString(),
        });
        const body = (await tokenRes.json());
        if (!tokenRes.ok || !body.refresh_token) {
            console.error("gcal token exchange failed:", tokenRes.status, JSON.stringify(body));
            fail("Google n'a pas accordé l'accès. Réessaie depuis l'app.");
            return;
        }
        // Email depuis l'id_token (scope openid email) — zéro appel API en plus.
        let email = null;
        try {
            const payload = String((_f = body.id_token) !== null && _f !== void 0 ? _f : "").split(".")[1];
            if (payload) {
                email =
                    (_g = JSON.parse(Buffer.from(payload, "base64url").toString("utf8"))
                        .email) !== null && _g !== void 0 ? _g : null;
            }
        }
        catch (_) { /* l'email est un confort, pas un prérequis */ }
        await tokensRef(uid).set({
            refreshToken: body.refresh_token,
            accessToken: (_h = body.access_token) !== null && _h !== void 0 ? _h : null,
            accessTokenExp: Date.now() + (Number((_j = body.expires_in) !== null && _j !== void 0 ? _j : 3600) - 60) * 1000,
            email,
            autoSync: true,
            connectedAt: firestore_2.FieldValue.serverTimestamp(),
            revoked: firestore_2.FieldValue.delete(),
        }, { merge: true });
        // Première sync immédiate (best-effort) : le programme du jour apparaît.
        await syncDayToGcal(uid, (0, execute_1.userDayParts)(await userTzOffset(uid)).ymd)
            .catch(() => null);
        res.status(200).send(htmlPage("✅ Google Agenda connecté", `Ton programme du jour est synchronisé${email ? ` sur <b>${email}</b>` : ""}. Tu peux fermer cette page et revenir dans Productivitwo.`));
    }
    catch (e) {
        console.error("gcalOauthCallback error:", e);
        fail("Erreur inattendue — réessaie depuis l'app.");
    }
});
// ── Trigger : TOUTE écriture d'un programme synchronise l'agenda ─────────────
//
// Un seul chemin de sync pour tous les écrivains (app, schedule_day,
// add_event, défis ORION, check-in). Jours passés ignorés (l'agenda n'est pas
// un journal). La sync n'écrit jamais dans Firestore → aucune boucle.
exports.gcalOnScheduleWrite = (0, firestore_1.onDocumentWritten)({ document: "users/{uid}/daily_schedules/{date}", secrets: GCAL_SECRETS }, async (event) => {
    const uid = event.params.uid;
    const date = event.params.date;
    if (!/^\d{4}-\d{2}-\d{2}$/.test(date))
        return; // brouillons & docs annexes
    if (date < (0, execute_1.userDayParts)(await userTzOffset(uid)).ymd)
        return; // jour vécu
    const snap = await tokensRef(uid).get();
    const d = snap.data();
    if (!snap.exists || !(d === null || d === void 0 ? void 0 : d.refreshToken) || d.autoSync === false)
        return;
    const r = await syncDayToGcal(uid, date);
    if (!r.ok)
        console.error(`gcal auto-sync ${uid}/${date}:`, r.reason);
});
//# sourceMappingURL=gcal.js.map