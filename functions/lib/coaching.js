"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.coacheeApi = exports.coachConsent = exports.coachApi = void 0;
const https_1 = require("firebase-functions/v2/https");
const firestore_1 = require("firebase-admin/firestore");
const admin = require("firebase-admin");
const crypto_1 = require("crypto");
const db_1 = require("./db");
const execute_1 = require("./execute");
const COACHING_STATUSES = ["prospect", "explo", "actif", "autonome", "termine"];
const CONSENT_URL = "https://coachconsent-dzos75b65q-uc.a.run.app";
const coachingRef = (id) => db_1.db.doc(`coaching/${id}`);
function sharingOf(data) {
    var _a;
    const s = ((_a = data.sharing) !== null && _a !== void 0 ? _a : {});
    return {
        domainIds: Array.isArray(s.domainIds) ? s.domainIds.map(String) : [],
        granularity: s.granularity === "detail" ? "detail" : "status",
    };
}
/** Journal RGPD : chaque transition de consentement/périmètre est horodatée,
 *  avec un snapshot du périmètre alors en vigueur. Jamais purgé. */
async function logConsentEvent(coachingId, event, scope) {
    await db_1.db.collection(`coaching/${coachingId}/consent_log`).doc((0, crypto_1.randomUUID)()).set(Object.assign({ event, actor: "coachee", at: firestore_1.FieldValue.serverTimestamp() }, (scope ? { scope } : {})));
}
/** L'appelant (ID token Firebase) est-il un coach actif ? → uid ou null. */
async function coachUidFrom(authHeader) {
    var _a;
    if (!authHeader.startsWith("Bearer "))
        return null;
    try {
        const uid = (await admin.auth().verifyIdToken(authHeader.slice(7).trim())).uid;
        const snap = await db_1.db.doc(`coaches/${uid}`).get();
        return snap.exists && ((_a = snap.data()) === null || _a === void 0 ? void 0 : _a.active) === true ? uid : null;
    }
    catch (_b) {
        return null;
    }
}
/** Résout (et mémorise) l'uid Firebase du coaché à partir de son email. */
async function resolveCoacheeUid(docId, data) {
    if (typeof data.coacheeUid === "string" && data.coacheeUid !== "") {
        return data.coacheeUid;
    }
    try {
        const user = await admin.auth().getUserByEmail(data.email);
        await coachingRef(docId).set({ coacheeUid: user.uid }, { merge: true });
        return user.uid;
    }
    catch (_a) {
        return null; // pas encore de compte — la fiche vit quand même (phase explo)
    }
}
/** Tableau de bord LECTURE d'un coaché : composé côté serveur, jamais de
 *  passe-plat des règles Firestore d'un user vers un autre. Minimisation :
 *  seuls les domaines du périmètre apparaissent — nulle part ailleurs, même
 *  pas agrégés ; le mode "status" omet temps, blocs et boîte à idées. */
async function buildDashboard(coacheeUid, sharing) {
    var _a, _b, _c, _d, _e, _f, _g, _h, _j;
    const detail = sharing.granularity === "detail";
    const sharedDomains = new Set(sharing.domainIds);
    const now = new Date();
    const today = new Date(now.getTime());
    const ymd = `${today.getFullYear()}-${String(today.getMonth() + 1).padStart(2, "0")}-${String(today.getDate()).padStart(2, "0")}`;
    const weekAgo = new Date(now.getTime() - 7 * 86400000);
    const [domSnap, actSnap, schedSnap, sessSnap, capSnap] = await Promise.all([
        db_1.db.collection(`users/${coacheeUid}/domains`).get(),
        db_1.db.collection(`users/${coacheeUid}/activities`).get(),
        db_1.db.doc(`users/${coacheeUid}/daily_schedules/${ymd}`).get(),
        db_1.db.collection(`users/${coacheeUid}/sessions`)
            .where("startAt", ">=", weekAgo.toISOString()).get()
            .catch(() => null),
        db_1.db.collection(`users/${coacheeUid}/captures`)
            .where("status", "==", "pending").get()
            .catch(() => null),
    ]);
    const domains = domSnap.docs
        .map((d) => d.data())
        .filter((v) => v.deleted !== true && sharedDomains.has(String(v.id)))
        .map((v) => {
        var _a, _b;
        return ({
            id: v.id, name: v.name,
            intention: (_a = v.intention) !== null && _a !== void 0 ? _a : null,
            definitionStatus: (_b = v.definitionStatus) !== null && _b !== void 0 ? _b : null,
        });
    });
    // Domaine de CHAQUE activité (partagée ou non) — sert à écarter les blocs
    // rattachés à un domaine hors périmètre.
    const domainOfActivity = {};
    for (const d of actSnap.docs) {
        const v = d.data();
        domainOfActivity[String(v.id)] = String((_a = v.domainId) !== null && _a !== void 0 ? _a : "");
    }
    const activities = actSnap.docs
        .map((d) => d.data())
        .filter((v) => { var _a; return v.deleted !== true && sharedDomains.has(String((_a = v.domainId) !== null && _a !== void 0 ? _a : "")); })
        .map((v) => {
        var _a, _b, _c, _d;
        return ({
            id: v.id, name: v.name, type: (_a = v.type) !== null && _a !== void 0 ? _a : "time",
            domainId: (_b = v.domainId) !== null && _b !== void 0 ? _b : null,
            goalMin: (_c = v.goalMin) !== null && _c !== void 0 ? _c : null,
            habitTarget: (_d = v.habitTarget) !== null && _d !== void 0 ? _d : null,
        });
    });
    const sharedActivityIds = new Set(activities.map((a) => String(a.id)));
    // Minutes loggées sur 7 jours, par activité partagée (mode détail seulement).
    const minutesByActivity = {};
    for (const d of (_b = sessSnap === null || sessSnap === void 0 ? void 0 : sessSnap.docs) !== null && _b !== void 0 ? _b : []) {
        const v = d.data();
        const start = Date.parse(String((_c = v.startAt) !== null && _c !== void 0 ? _c : ""));
        const end = Date.parse(String((_d = v.endAt) !== null && _d !== void 0 ? _d : ""));
        if (!isFinite(start) || !isFinite(end) || end <= start)
            continue;
        const id = String((_e = v.activityId) !== null && _e !== void 0 ? _e : "");
        if (!sharedActivityIds.has(id))
            continue;
        minutesByActivity[id] =
            ((_f = minutesByActivity[id]) !== null && _f !== void 0 ? _f : 0) + Math.round((end - start) / 60000);
    }
    // Blocs du jour (mode détail) — un bloc rattaché à une activité d'un domaine
    // NON partagé est écarté ; les blocs sans rattachement domaine passent.
    const blocks = ((_h = (_g = schedSnap.data()) === null || _g === void 0 ? void 0 : _g.blocks) !== null && _h !== void 0 ? _h : [])
        .filter((b) => b.status !== "deleted")
        .filter((b) => {
        var _a, _b;
        const actId = String((_a = b.activityId) !== null && _a !== void 0 ? _a : "");
        return actId === "" || sharedDomains.has((_b = domainOfActivity[actId]) !== null && _b !== void 0 ? _b : "");
    })
        .map((b) => ({
        startTime: b.startTime, durationMin: b.durationMin,
        title: b.title, status: b.status, challenge: b.challenge === true,
    }));
    return {
        date: ymd,
        granularity: sharing.granularity,
        domains,
        activities,
        todayBlocks: detail ? blocks : null,
        weekMinutesByActivity: detail ? minutesByActivity : null,
        pendingIdeas: detail ? ((_j = capSnap === null || capSnap === void 0 ? void 0 : capSnap.size) !== null && _j !== void 0 ? _j : 0) : null,
    };
}
// ── coachApi : POST + Authorization: Bearer <ID token Firebase du coach> ──────
exports.coachApi = (0, https_1.onRequest)({ cors: true, invoker: "public" }, async (req, res) => {
    var _a, _b, _c;
    if (req.method === "OPTIONS") {
        res.status(204).send("");
        return;
    }
    if (req.method !== "POST") {
        res.status(405).json({ error: "Method Not Allowed" });
        return;
    }
    const coachUid = await coachUidFrom((_a = req.headers.authorization) !== null && _a !== void 0 ? _a : "");
    if (!coachUid) {
        res.status(403).json({ error: "Accès coach requis" });
        return;
    }
    const { action, id, email, name, status, notes, nextSession, text, targetDate } = req.body;
    /** Fiche appartenant à CE coach — null sinon (jamais celle d'un autre). */
    const ownDoc = async (docId) => {
        if (!docId)
            return null;
        const snap = await coachingRef(docId).get();
        const d = snap.data();
        return snap.exists && (d === null || d === void 0 ? void 0 : d.coachUid) === coachUid ? Object.assign(Object.assign({}, d), { id: docId }) : null;
    };
    try {
        if (action === "listClients") {
            const snap = await db_1.db.collection("coaching")
                .where("coachUid", "==", coachUid).get();
            const clients = snap.docs.map((d) => {
                var _a, _b, _c, _d, _e;
                const v = d.data();
                const sharing = sharingOf(v);
                return {
                    id: d.id, email: v.email, name: (_a = v.name) !== null && _a !== void 0 ? _a : null,
                    coacheeUid: (_b = v.coacheeUid) !== null && _b !== void 0 ? _b : null,
                    status: v.status, notes: (_c = v.notes) !== null && _c !== void 0 ? _c : "",
                    nextSession: (_d = v.nextSession) !== null && _d !== void 0 ? _d : null,
                    consent: (_e = v.consent) !== null && _e !== void 0 ? _e : "pending",
                    sharing: {
                        domainCount: sharing.domainIds.length,
                        granularity: sharing.granularity,
                    },
                };
            });
            res.status(200).json({ clients });
            return;
        }
        if (action === "createClient") {
            const em = (email !== null && email !== void 0 ? email : "").trim().toLowerCase();
            if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(em)) {
                res.status(400).json({ error: "Email invalide" });
                return;
            }
            // Une fiche par email et par coach — la phase explo crée la fiche
            // AVANT que le compte du coaché existe.
            const dup = await db_1.db.collection("coaching")
                .where("coachUid", "==", coachUid).where("email", "==", em).get();
            if (!dup.empty) {
                res.status(409).json({ error: "Fiche déjà existante", id: dup.docs[0].id });
                return;
            }
            const docId = (0, crypto_1.randomUUID)();
            await coachingRef(docId).set({
                id: docId,
                coachUid,
                email: em,
                name: (name !== null && name !== void 0 ? name : "").trim() || null,
                coacheeUid: null,
                status: COACHING_STATUSES.includes(status !== null && status !== void 0 ? status : "") ? status : "prospect",
                notes: notes !== null && notes !== void 0 ? notes : "",
                nextSession: null,
                consent: "pending",
                createdAt: firestore_1.FieldValue.serverTimestamp(),
                updatedAt: firestore_1.FieldValue.serverTimestamp(),
            });
            res.status(200).json({ ok: true, id: docId });
            return;
        }
        if (action === "updateClient") {
            const doc = await ownDoc(id);
            if (!doc) {
                res.status(404).json({ error: "Fiche introuvable" });
                return;
            }
            const patch = { updatedAt: firestore_1.FieldValue.serverTimestamp() };
            if (status != null && COACHING_STATUSES.includes(status))
                patch.status = status;
            if (notes != null)
                patch.notes = notes;
            if (name != null)
                patch.name = name.trim() || null;
            if (nextSession != null)
                patch.nextSession = nextSession.trim() || null;
            await coachingRef(doc.id).set(patch, { merge: true });
            res.status(200).json({ ok: true });
            return;
        }
        if (action === "deleteClient") {
            // Suppression DURE assumée (cas explicite : fiche mal créée — mauvais
            // email). Collection racine server-only : aucun merge client ne peut
            // la ressusciter. Nettoie aussi l'allowlist si C'EST CE COACH qui
            // avait invité cet email, et les jetons de consentement du doc.
            const doc = await ownDoc(id);
            if (!doc) {
                res.status(404).json({ error: "Fiche introuvable" });
                return;
            }
            const allowRef = db_1.db.collection("allowlist").doc(doc.email);
            const allowSnap = await allowRef.get();
            if (allowSnap.exists && ((_b = allowSnap.data()) === null || _b === void 0 ? void 0 : _b.addedBy) === `coach:${coachUid}`) {
                await allowRef.delete();
            }
            const toks = await db_1.db.collection("coaching_consents")
                .where("coachingId", "==", doc.id).get();
            await Promise.all(toks.docs.map((t) => t.ref.delete()));
            await coachingRef(doc.id).delete();
            res.status(200).json({ ok: true });
            return;
        }
        if (action === "invite") {
            // Ouvre l'accès app au coaché : allowlist → sendMagicLink passera.
            const doc = await ownDoc(id);
            if (!doc) {
                res.status(404).json({ error: "Fiche introuvable" });
                return;
            }
            await db_1.db.collection("allowlist").doc(doc.email).set({ addedAt: firestore_1.FieldValue.serverTimestamp(), addedBy: `coach:${coachUid}` }, { merge: true });
            res.status(200).json({ ok: true, email: doc.email });
            return;
        }
        if (action === "consentLink") {
            // Lien de consentement PARTAGEABLE (WhatsApp, mail…) — le coaché
            // accepte ou refuse sur une page web, révocable par le même lien.
            const doc = await ownDoc(id);
            if (!doc) {
                res.status(404).json({ error: "Fiche introuvable" });
                return;
            }
            const token = (0, crypto_1.randomUUID)();
            await db_1.db.doc(`coaching_consents/${token}`).set({
                coachingId: doc.id,
                email: doc.email,
                createdAt: firestore_1.FieldValue.serverTimestamp(),
                expiresAt: Date.now() + 14 * 86400000,
            });
            res.status(200).json({ ok: true, url: `${CONSENT_URL}?token=${token}` });
            return;
        }
        if (action === "dashboard") {
            const doc = await ownDoc(id);
            if (!doc) {
                res.status(404).json({ error: "Fiche introuvable" });
                return;
            }
            if (doc.consent !== "granted") {
                res.status(200).json({ ok: false, reason: "consent_required" });
                return;
            }
            const coacheeUid = await resolveCoacheeUid(doc.id, doc);
            if (!coacheeUid) {
                res.status(200).json({ ok: false, reason: "no_account" });
                return;
            }
            const sharing = sharingOf(doc);
            if (sharing.domainIds.length === 0) {
                res.status(200).json({ ok: false, reason: "no_scope" });
                return;
            }
            const dash = await buildDashboard(coacheeUid, sharing);
            res.status(200).json({ ok: true, dashboard: dash });
            return;
        }
        if (action === "message") {
            // Message du coach dans l'app du coaché — même canal qu'ORION
            // (assistant_messages), signé du nom du coach.
            const doc = await ownDoc(id);
            if (!doc) {
                res.status(404).json({ error: "Fiche introuvable" });
                return;
            }
            if (doc.consent !== "granted") {
                res.status(200).json({ ok: false, reason: "consent_required" });
                return;
            }
            const coacheeUid = await resolveCoacheeUid(doc.id, doc);
            if (!coacheeUid) {
                res.status(200).json({ ok: false, reason: "no_account" });
                return;
            }
            const body = (text !== null && text !== void 0 ? text : "").trim();
            if (!body) {
                res.status(400).json({ error: "text requis" });
                return;
            }
            const coachName = (_c = (await admin.auth().getUser(coachUid)).displayName) !== null && _c !== void 0 ? _c : "Ton coach";
            const date = targetDate && /^\d{4}-\d{2}-\d{2}$/.test(targetDate)
                ? targetDate
                : new Date().toISOString().slice(0, 10);
            await (0, execute_1.executePushAssistantMessage)(coacheeUid, {
                targetDate: date,
                text: body,
                condition: { type: "always" },
                characterName: coachName,
                expiresAfterDays: 5,
            });
            res.status(200).json({ ok: true });
            return;
        }
        res.status(400).json({ error: `action inconnue : ${action}` });
    }
    catch (e) {
        console.error("coachApi error:", e);
        res.status(500).json({ error: "Erreur serveur coaching" });
    }
});
// ── coachConsent : page web du coaché (GET, sans compte requis) ───────────────
const consentPage = (title, body) => `<!DOCTYPE html>
<html lang="fr"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>${title}</title>
<style>body{font-family:-apple-system,sans-serif;background:#101418;color:#e8eef2;display:flex;align-items:center;justify-content:center;min-height:100vh;margin:0}
main{text-align:center;padding:32px;max-width:440px}h1{font-size:20px}p{color:#9fb0bb;line-height:1.5}
.btn{display:inline-block;margin:8px;padding:12px 22px;border-radius:12px;text-decoration:none;font-weight:700}
.ok{background:#1a9e6e;color:#fff}.no{background:#2a3440;color:#e8eef2}</style>
</head><body><main><h1>${title}</h1>${body}</main></body></html>`;
exports.coachConsent = (0, https_1.onRequest)({ cors: true, invoker: "public" }, async (req, res) => {
    var _a, _b, _c, _d, _e;
    const token = String((_a = req.query.token) !== null && _a !== void 0 ? _a : "");
    const decision = String((_b = req.query.decision) !== null && _b !== void 0 ? _b : "");
    const fail = (msg) => res.status(400).send(consentPage("Lien invalide", `<p>${msg}</p>`));
    if (!token) {
        fail("Ce lien est incomplet — redemande-le à ton coach.");
        return;
    }
    try {
        const tokSnap = await db_1.db.doc(`coaching_consents/${token}`).get();
        const tok = tokSnap.data();
        if (!tokSnap.exists || Number((_c = tok === null || tok === void 0 ? void 0 : tok.expiresAt) !== null && _c !== void 0 ? _c : 0) < Date.now()) {
            fail("Ce lien a expiré — redemande-le à ton coach.");
            return;
        }
        const docSnap = await coachingRef(tok.coachingId).get();
        if (!docSnap.exists) {
            fail("Fiche introuvable.");
            return;
        }
        const d = docSnap.data();
        const coachName = (_d = (await admin.auth().getUser(d.coachUid)).displayName) !== null && _d !== void 0 ? _d : "Ton coach";
        // Pas de décision → page de choix (jamais d'action sur simple ouverture :
        // les scanners d'emails ouvrent les liens).
        if (decision !== "accept" && decision !== "refuse") {
            res.status(200).send(consentPage("Accompagnement Productivitwo", `<p><b>${coachName}</b> souhaite t'accompagner dans Productivitwo.
           Accepter ouvre le lien, mais <b>ne partage rien</b> : c'est toi qui
           choisiras ensuite, dans l'app (Paramètres → Mon coach), quels
           domaines de vie il peut voir et à quel niveau de détail. Rien n'est
           modifié sans toi, et tu peux tout révoquer à n'importe quel moment.</p>
           <a class="btn ok" href="?token=${token}&decision=accept">J'accepte</a>
           <a class="btn no" href="?token=${token}&decision=refuse">Je refuse</a>`));
            return;
        }
        const granted = decision === "accept";
        // Un seul coach par coaché (V1.1) : refuse l'acceptation si un AUTRE
        // lien est déjà actif pour cet email.
        if (granted) {
            const others = await db_1.db.collection("coaching")
                .where("email", "==", d.email).where("consent", "==", "granted").get();
            if (others.docs.some((o) => o.id !== tok.coachingId)) {
                res.status(200).send(consentPage("Un coach à la fois", `<p>Tu as déjà un accompagnement actif avec un autre coach.
             Révoque d'abord cet accès (depuis ton app : Paramètres → Mon
             coach) avant d'en accepter un nouveau.</p>`));
                return;
            }
        }
        const prevConsent = String((_e = d.consent) !== null && _e !== void 0 ? _e : "pending");
        await coachingRef(tok.coachingId).set(Object.assign({ consent: granted ? "granted" : "revoked", consentAt: firestore_1.FieldValue.serverTimestamp() }, (granted ? { sharing: { domainIds: [], granularity: "status" } } : {})), { merge: true });
        await logConsentEvent(tok.coachingId, granted ? "granted" : prevConsent === "granted" ? "revoked" : "refused", granted ? { domainIds: [], granularity: "status" } : sharingOf(d));
        // Lier l'uid si le compte existe déjà (sinon il se liera plus tard).
        try {
            const user = await admin.auth().getUserByEmail(d.email);
            await coachingRef(tok.coachingId)
                .set({ coacheeUid: user.uid }, { merge: true });
        }
        catch ( /* pas encore de compte */_f) { /* pas encore de compte */ }
        res.status(200).send(consentPage(granted ? "C'est noté ✓" : "Accès refusé", granted
            ? `<p>Le lien avec ${coachName} est actif — mais il ne voit encore
             <b>rien</b> : ouvre ton app (Paramètres → Mon coach) pour choisir
             les domaines à partager et le niveau de détail. Tu peux révoquer
             cet accès à tout moment, depuis l'app ou en rouvrant ce lien.</p>
             <a class="btn no" href="?token=${token}&decision=refuse">Révoquer l'accès</a>`
            : `<p>Aucun accès n'est ouvert. Tu peux changer d'avis avec ce même
             lien.</p>
             <a class="btn ok" href="?token=${token}&decision=accept">Finalement, j'accepte</a>`));
    }
    catch (e) {
        console.error("coachConsent error:", e);
        fail("Erreur serveur — réessaie dans un instant.");
    }
});
// ── coacheeApi : le CÔTÉ COACHÉ du lien (US-1) ────────────────────────────────
//
// POST + Authorization: Bearer <ID token Firebase du coaché>.
// Le coaché gère seul son partage depuis son app : voir le lien (getLink),
// choisir domaines + granularité (updateSharing), tout couper (revoke).
// La fiche racine reste server-only — jamais d'accès Firestore direct.
/** Fiche coaching du coaché appelant : par coacheeUid, sinon par email
 *  (compte créé après la fiche — on mémorise alors l'uid). Lien actif
 *  d'abord, sinon la plus pertinente. */
async function coacheeFiche(uid, email) {
    let snap = await db_1.db.collection("coaching").where("coacheeUid", "==", uid).get();
    if (snap.empty && email) {
        snap = await db_1.db.collection("coaching")
            .where("email", "==", email.toLowerCase()).get();
    }
    if (snap.empty)
        return null;
    const rank = (v) => v.consent === "granted" ? 0 : v.consent === "pending" ? 1 : 2;
    const doc = [...snap.docs].sort((a, b) => rank(a.data()) - rank(b.data()))[0];
    if (doc.data().coacheeUid !== uid) {
        await doc.ref.set({ coacheeUid: uid }, { merge: true });
    }
    return { id: doc.id, data: doc.data() };
}
exports.coacheeApi = (0, https_1.onRequest)({ cors: true, invoker: "public" }, async (req, res) => {
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
        res.status(401).json({ error: "Authorization requis" });
        return;
    }
    let uid;
    let email;
    try {
        const decoded = await admin.auth().verifyIdToken(authHeader.slice(7).trim());
        uid = decoded.uid;
        email = (_b = decoded.email) !== null && _b !== void 0 ? _b : "";
    }
    catch (_e) {
        res.status(401).json({ error: "Token invalide ou expiré" });
        return;
    }
    const { action, domainIds, granularity } = req.body;
    try {
        const fiche = await coacheeFiche(uid, email);
        if (action === "getLink") {
            if (!fiche) {
                res.status(200).json({ linked: false });
                return;
            }
            const coachName = (_c = (await admin.auth().getUser(fiche.data.coachUid))
                .displayName) !== null && _c !== void 0 ? _c : "Ton coach";
            res.status(200).json({
                linked: true,
                coachName,
                consent: (_d = fiche.data.consent) !== null && _d !== void 0 ? _d : "pending",
                sharing: sharingOf(fiche.data),
            });
            return;
        }
        if (action === "updateSharing") {
            if (!fiche || fiche.data.consent !== "granted") {
                res.status(400).json({ error: "Aucun lien coach actif" });
                return;
            }
            const gran = granularity === "detail" ? "detail" : "status";
            const wanted = Array.isArray(domainIds) ? domainIds.map(String) : [];
            // Uniquement des domaines existants (non supprimés) du coaché.
            const domSnap = await db_1.db.collection(`users/${uid}/domains`).get();
            const valid = new Set(domSnap.docs
                .map((d) => d.data())
                .filter((v) => v.deleted !== true)
                .map((v) => String(v.id)));
            const sharing = {
                domainIds: [...new Set(wanted.filter((id) => valid.has(id)))],
                granularity: gran,
            };
            await coachingRef(fiche.id).set({ sharing, updatedAt: firestore_1.FieldValue.serverTimestamp() }, { merge: true });
            await logConsentEvent(fiche.id, "sharing_updated", sharing);
            res.status(200).json({ ok: true, sharing });
            return;
        }
        if (action === "revoke") {
            if (!fiche) {
                res.status(400).json({ error: "Aucun lien coach" });
                return;
            }
            await coachingRef(fiche.id).set({
                consent: "revoked",
                consentAt: firestore_1.FieldValue.serverTimestamp(),
            }, { merge: true });
            await logConsentEvent(fiche.id, "revoked", sharingOf(fiche.data));
            res.status(200).json({ ok: true });
            return;
        }
        res.status(400).json({ error: `action inconnue : ${action}` });
    }
    catch (e) {
        console.error("coacheeApi error:", e);
        res.status(500).json({ error: "Erreur serveur coaching" });
    }
});
//# sourceMappingURL=coaching.js.map