"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.gcalOnScheduleWrite = exports.gcalOauthCallback = exports.gcalApi = void 0;
exports.importGcalDay = importGcalDay;
exports.syncDayToGcal = syncDayToGcal;
const https_1 = require("firebase-functions/v2/https");
const firestore_1 = require("firebase-functions/v2/firestore");
const firestore_2 = require("firebase-admin/firestore");
const crypto_1 = require("crypto");
const db_1 = require("./db");
const execute_1 = require("./execute");
const CALLBACK_URL = "https://gcaloauthcallback-dzos75b65q-uc.a.run.app";
// calendarlist.readonly : uniquement pour LISTER les calendriers (choix du
// calendrier cible) — les connexions antérieures sans ce scope reçoivent
// « rescope » et doivent se reconnecter pour choisir.
const SCOPES = "openid email https://www.googleapis.com/auth/calendar.events https://www.googleapis.com/auth/calendar.calendarlist.readonly";
const GCAL_SECRETS = ["GCAL_CLIENT_ID", "GCAL_CLIENT_SECRET"];
const tokensRef = (uid) => db_1.db.doc(`gcal_tokens/${uid}`);
const calBase = (calId) => `https://www.googleapis.com/calendar/v3/calendars/${encodeURIComponent(calId)}`;
/** Calendrier cible de la sync — « primary » par défaut, modifiable via
 *  l'action setCalendar (agenda principal partagé pour raisons pro → l'app
 *  écrit sur un calendrier dédié). */
async function calendarIdFor(uid) {
    var _a;
    const snap = await tokensRef(uid).get();
    const v = (_a = snap.data()) === null || _a === void 0 ? void 0 : _a.calendarId;
    return typeof v === "string" && v.trim() !== "" ? v.trim() : "primary";
}
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
/** Offset Europe/Paris (minutes) pour un jour donné — fallback quand le fait
 *  tzOffsetMin n'existe pas encore (gère l'heure d'été/hiver). */
function parisOffsetMin(ymd) {
    const utcNoon = new Date(`${ymd}T12:00:00Z`);
    // sv-SE → « YYYY-MM-DD HH:mm » ; l'écart avec midi UTC = l'offset.
    const wall = utcNoon.toLocaleString("sv-SE", { timeZone: "Europe/Paris" });
    const h = parseInt(wall.slice(11, 13), 10);
    const m = parseInt(wall.slice(14, 16), 10);
    return (h - 12) * 60 + m;
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
// ── Import agenda → programme (blocs MIROIRS) ────────────────────────────────
//
// Les événements de l'agenda qui ne viennent PAS de nous deviennent des blocs
// « miroirs » (gcalEventId) dans le programme : le coach les voit (trous,
// horizon, proposition AUTOUR). L'AGENDA est leur source de vérité — déplacé
// dans GCal → le bloc suit ; supprimé dans GCal → le bloc part ; swipé dans
// l'app → masqué SANS toucher au vrai rendez-vous (jamais recréé). La sync
// sortante les ignore : chaque objet ne se supprime que chez son propriétaire.
async function importGcalDay(uid, date) {
    var _a, _b, _c, _d, _e, _f, _g, _h, _j, _k;
    const none = { imported: 0, updated: 0, removed: 0 };
    if (!/^\d{4}-\d{2}-\d{2}$/.test(date))
        return Object.assign(Object.assign({ ok: false }, none), { reason: "bad_date" });
    const token = await accessTokenFor(uid);
    if (!token)
        return Object.assign(Object.assign({ ok: false }, none), { reason: "not_connected" });
    const base = calBase(await calendarIdFor(uid));
    const tzOff = (_a = (await userTzOffset(uid))) !== null && _a !== void 0 ? _a : parisOffsetMin(date);
    const off = offsetStr(tzOff);
    const listRes = await fetch(`${base}/events?` +
        new URLSearchParams({
            timeMin: `${date}T00:00:00${off}`,
            timeMax: `${date}T23:59:59${off}`,
            singleEvents: "true",
            orderBy: "startTime",
            maxResults: "100",
        }).toString(), { headers: { Authorization: `Bearer ${token}` } });
    if (!listRes.ok) {
        console.error("gcal import list failed:", listRes.status, await listRes.text());
        return Object.assign(Object.assign({ ok: false }, none), { reason: `list_http_${listRes.status}` });
    }
    const items = (_b = (await listRes.json()).items) !== null && _b !== void 0 ? _b : [];
    // Événements retenus : PAS les nôtres (pwo), avec une heure (pas de
    // « journée entière » en v1), non annulés, non refusés par l'utilisateur.
    const events = new Map();
    for (const ev of items) {
        if (ev.status === "cancelled")
            continue;
        if (((_d = (_c = ev.extendedProperties) === null || _c === void 0 ? void 0 : _c.private) === null || _d === void 0 ? void 0 : _d.pwo) === "1")
            continue;
        const startIso = (_e = ev.start) === null || _e === void 0 ? void 0 : _e.dateTime;
        const endIso = (_f = ev.end) === null || _f === void 0 ? void 0 : _f.dateTime;
        if (!startIso || !endIso)
            continue; // journée entière
        const self = ((_g = ev.attendees) !== null && _g !== void 0 ? _g : []).find((a) => a.self === true);
        if ((self === null || self === void 0 ? void 0 : self.responseStatus) === "declined")
            continue;
        const startMs = Date.parse(startIso);
        const endMs = Date.parse(endIso);
        if (!isFinite(startMs) || !isFinite(endMs))
            continue;
        const local = new Date(startMs + tzOff * 60000).toISOString();
        if (local.slice(0, 10) !== date)
            continue; // instance d'un autre jour vécu
        events.set(String(ev.id), {
            title: String((_h = ev.summary) !== null && _h !== void 0 ? _h : "(Sans titre)").trim() || "(Sans titre)",
            startMin: parseInt(local.slice(11, 13), 10) * 60 + parseInt(local.slice(14, 16), 10),
            durationMin: Math.max(5, Math.round((endMs - startMs) / 60000)),
        });
    }
    // Merge dans le doc du jour — écrit UNIQUEMENT si quelque chose change.
    const ref = db_1.db.doc(`users/${uid}/daily_schedules/${date}`);
    const snap = await ref.get();
    const blocks = ((_k = (_j = snap.data()) === null || _j === void 0 ? void 0 : _j.blocks) !== null && _k !== void 0 ? _k : []).slice();
    let imported = 0, updated = 0, removed = 0;
    for (let i = blocks.length - 1; i >= 0; i--) {
        const b = blocks[i];
        if (!b.gcalEventId)
            continue;
        const ev = events.get(String(b.gcalEventId));
        if (ev == null) {
            blocks.splice(i, 1); // l'événement a disparu de l'agenda → le miroir part
            removed++;
            continue;
        }
        events.delete(String(b.gcalEventId)); // déjà représenté
        if (b.status === "deleted")
            continue; // swipé : masqué, on respecte
        const hm = `${String(Math.floor(ev.startMin / 60)).padStart(2, "0")}:${String(ev.startMin % 60).padStart(2, "0")}`;
        if (b.startTime !== hm || b.durationMin !== ev.durationMin || b.title !== ev.title) {
            b.startTime = hm;
            b.durationMin = ev.durationMin;
            b.title = ev.title;
            updated++;
        }
    }
    for (const [eventId, ev] of events) {
        blocks.push({
            id: `gcal-${eventId}`,
            startTime: `${String(Math.floor(ev.startMin / 60)).padStart(2, "0")}:${String(ev.startMin % 60).padStart(2, "0")}`,
            durationMin: ev.durationMin,
            title: ev.title,
            category: "personal",
            projectId: null,
            taskId: null,
            activityId: null,
            actionId: null,
            status: "pending",
            doneAt: null,
            subtitle: "Agenda Google",
            gcalEventId: eventId,
        });
        imported++;
    }
    if (imported + updated + removed > 0) {
        if (snap.exists) {
            await ref.update({ blocks });
        }
        else {
            await ref.set({
                date,
                generatedBy: "gcal",
                generatedAt: firestore_2.FieldValue.serverTimestamp(),
                blocks,
            });
        }
    }
    return { ok: true, imported, updated, removed };
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
    const base = calBase(await calendarIdFor(uid));
    // Les heures du programme sont des heures de MUR du téléphone : l'événement
    // porte l'offset du fuseau vécu (fait) — sinon fallback Europe/Paris.
    const tzOff = await userTzOffset(uid);
    // Blocs vivants du programme (doc absent = tout supprimer côté agenda).
    // Les MIROIRS (gcalEventId) sont ignorés : l'événement existe déjà dans
    // l'agenda et lui appartient — jamais re-poussé, jamais dupliqué.
    const snap = await db_1.db.doc(`users/${uid}/daily_schedules/${date}`).get();
    const blocks = ((_b = (_a = snap.data()) === null || _a === void 0 ? void 0 : _a.blocks) !== null && _b !== void 0 ? _b : []).filter((b) => {
        var _a, _b;
        return !b.gcalEventId &&
            (b.status === "pending" || b.status === "done") &&
            /^\d{2}:\d{2}$/.test(String((_a = b.startTime) !== null && _a !== void 0 ? _a : "")) &&
            String((_b = b.title) !== null && _b !== void 0 ? _b : "").trim() !== "" &&
            b.id;
    });
    // Événements Productivitwo existants pour CE jour (jamais les personnels).
    const listRes = await fetch(`${base}/events?privateExtendedProperty=${encodeURIComponent(`pwoDate=${date}`)}&maxResults=250&showDeleted=false`, { headers: auth });
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
            const r = await fetch(`${base}/events`, {
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
                const r = await fetch(`${base}/events/${ev.id}`, {
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
        const r = await fetch(`${base}/events/${ev.id}`, { method: "DELETE", headers: auth });
        if (r.ok || r.status === 404 || r.status === 410)
            deleted++;
        else
            console.error("gcal delete failed:", r.status, await r.text());
    }
    return { ok: true, created, updated, deleted };
}
// ── API app : status / authUrl / setAutoSync / syncDay / disconnect ──────────
exports.gcalApi = (0, https_1.onRequest)({ cors: true, invoker: "public", secrets: GCAL_SECRETS }, async (req, res) => {
    var _a, _b, _c, _d, _e, _f, _g, _h, _j;
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
    const { uid, action, date, value, calendarId, calendarSummary, eventId, startTime, durationMin, title } = req.body;
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
                calendarId: (_c = d === null || d === void 0 ? void 0 : d.calendarId) !== null && _c !== void 0 ? _c : "primary",
                calendarSummary: (_d = d === null || d === void 0 ? void 0 : d.calendarSummary) !== null && _d !== void 0 ? _d : null,
            });
            return;
        }
        // Calendriers ACCESSIBLES EN ÉCRITURE du compte — pour choisir la cible
        // de la sync (agenda principal partagé → calendrier dédié). Connexions
        // antérieures sans le scope calendarlist → « rescope » (reconnexion).
        if (action === "listCalendars") {
            const token = await accessTokenFor(uid);
            if (!token) {
                res.status(200).json({ ok: false, reason: "not_connected" });
                return;
            }
            const r = await fetch("https://www.googleapis.com/calendar/v3/users/me/calendarList?minAccessRole=writer&maxResults=100", { headers: { Authorization: `Bearer ${token}` } });
            if (r.status === 403) {
                res.status(200).json({ ok: false, reason: "rescope" });
                return;
            }
            if (!r.ok) {
                res.status(200).json({ ok: false, reason: `http_${r.status}` });
                return;
            }
            const body = (await r.json());
            res.status(200).json({
                ok: true,
                current: await calendarIdFor(uid),
                calendars: ((_e = body.items) !== null && _e !== void 0 ? _e : []).map((c) => {
                    var _a, _b;
                    return ({
                        id: c.id,
                        summary: (_b = (_a = c.summaryOverride) !== null && _a !== void 0 ? _a : c.summary) !== null && _b !== void 0 ? _b : c.id,
                        primary: c.primary === true,
                    });
                }),
            });
            return;
        }
        if (action === "setCalendar") {
            const newId = typeof calendarId === "string" && calendarId.trim() !== ""
                ? calendarId.trim()
                : "primary";
            const oldId = await calendarIdFor(uid);
            // Nettoyage best-effort de l'ANCIEN calendrier sur la fenêtre de sync
            // (aujourd'hui + demain) : sans lui, les événements Productivitwo
            // existeraient en double après la re-sync sur le nouveau.
            if (newId !== oldId) {
                const token = await accessTokenFor(uid);
                if (token) {
                    const auth = { Authorization: `Bearer ${token}` };
                    const today = (0, execute_1.userDayParts)(await userTzOffset(uid)).ymd;
                    const tmr = new Date(`${today}T12:00:00Z`);
                    tmr.setUTCDate(tmr.getUTCDate() + 1);
                    for (const d of [today, tmr.toISOString().slice(0, 10)]) {
                        try {
                            const lr = await fetch(`${calBase(oldId)}/events?privateExtendedProperty=${encodeURIComponent(`pwoDate=${d}`)}&maxResults=250&showDeleted=false`, { headers: auth });
                            if (!lr.ok)
                                continue;
                            const items = (_f = (await lr.json()).items) !== null && _f !== void 0 ? _f : [];
                            for (const ev of items) {
                                await fetch(`${calBase(oldId)}/events/${ev.id}`, {
                                    method: "DELETE",
                                    headers: auth,
                                }).catch(() => null);
                            }
                        }
                        catch ( /* best-effort */_k) { /* best-effort */ }
                    }
                }
            }
            await tokensRef(uid).set({ calendarId: newId, calendarSummary: calendarSummary !== null && calendarSummary !== void 0 ? calendarSummary : null }, { merge: true });
            res.status(200).json({ ok: true, calendarId: newId });
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
                    client_id: (_g = process.env.GCAL_CLIENT_ID) !== null && _g !== void 0 ? _g : "",
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
            // Bidirectionnel : import (agenda → miroirs) PUIS push (programme →
            // agenda) — l'import écrit le doc, le trigger re-poussera de toute
            // façon, mais on répond avec l'état complet tout de suite.
            const d = date && /^\d{4}-\d{2}-\d{2}$/.test(date)
                ? date
                : (0, execute_1.userDayParts)(await userTzOffset(uid)).ymd;
            const imp = await importGcalDay(uid, d);
            const push = await syncDayToGcal(uid, d);
            res.status(200).json(Object.assign(Object.assign({}, push), { imported: imp.imported, updatedFromCal: imp.updated, removedFromCal: imp.removed }));
            return;
        }
        // ── WYSIWYG bidirectionnel (test) : éditer/supprimer un ÉVÉNEMENT réel
        // de l'agenda depuis l'app — le miroir modifié dans la timeline pousse
        // sa nouvelle heure/durée/titre sur le vrai rendez-vous.
        if (action === "updateEvent") {
            if (!eventId || !date || !/^\d{4}-\d{2}-\d{2}$/.test(date) ||
                !startTime || !/^\d{2}:\d{2}$/.test(startTime) ||
                typeof durationMin !== "number" || durationMin < 1) {
                res.status(400).json({ ok: false, reason: "bad_args" });
                return;
            }
            const token = await accessTokenFor(uid);
            if (!token) {
                res.status(200).json({ ok: false, reason: "not_connected" });
                return;
            }
            const base = calBase(await calendarIdFor(uid));
            const tzOff = (_h = (await userTzOffset(uid))) !== null && _h !== void 0 ? _h : parisOffsetMin(date);
            const startMin = hmToMin(startTime);
            const start = dateTimeOf(date, startMin);
            const end = dateTimeOf(date, startMin + Math.round(durationMin));
            const patch = {
                start: { dateTime: `${start.ymd}T${start.hm}:00${offsetStr(tzOff)}` },
                end: { dateTime: `${end.ymd}T${end.hm}:00${offsetStr(tzOff)}` },
            };
            if (typeof title === "string" && title.trim() !== "") {
                patch.summary = title.trim();
            }
            const r = await fetch(`${base}/events/${encodeURIComponent(eventId)}`, {
                method: "PATCH",
                headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
                body: JSON.stringify(patch),
            });
            if (!r.ok)
                console.error("gcal updateEvent failed:", r.status, await r.text());
            res.status(200).json({ ok: r.ok, status: r.status });
            return;
        }
        if (action === "deleteEvent") {
            if (!eventId) {
                res.status(400).json({ ok: false, reason: "bad_args" });
                return;
            }
            const token = await accessTokenFor(uid);
            if (!token) {
                res.status(200).json({ ok: false, reason: "not_connected" });
                return;
            }
            const base = calBase(await calendarIdFor(uid));
            const r = await fetch(`${base}/events/${encodeURIComponent(eventId)}`, {
                method: "DELETE",
                headers: { Authorization: `Bearer ${token}` },
            });
            const ok = r.ok || r.status === 404 || r.status === 410;
            if (!ok)
                console.error("gcal deleteEvent failed:", r.status, await r.text());
            res.status(200).json({ ok, status: r.status });
            return;
        }
        if (action === "disconnect") {
            const snap = await tokensRef(uid).get();
            const refresh = (_j = snap.data()) === null || _j === void 0 ? void 0 : _j.refreshToken;
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
        // Première sync immédiate (best-effort), dans les deux sens : le
        // programme du jour apparaît dans l'agenda ET les rendez-vous du jour
        // apparaissent dans le programme.
        const ymd0 = (0, execute_1.userDayParts)(await userTzOffset(uid)).ymd;
        await importGcalDay(uid, ymd0).catch(() => null);
        await syncDayToGcal(uid, ymd0).catch(() => null);
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