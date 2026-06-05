"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.superOrionCron = exports.subscribeChallenge = exports.submitChallenge = exports.recomputeLeaderboards = exports.claimPseudo = void 0;
// ── Couche sociale (Phase 1) : pseudos + classement XP global ────────────────
// claimPseudo (réservation unique + opt-in) · recomputeLeaderboards (cron).
// L'XP de classement est RECALCULÉ CÔTÉ SERVEUR depuis les données réelles de
// l'utilisateur (anti-triche) — miroir de app_logic.actionXp/xpForDay.
const https_1 = require("firebase-functions/v2/https");
const scheduler_1 = require("firebase-functions/v2/scheduler");
const admin = require("firebase-admin");
const sdk_1 = require("@anthropic-ai/sdk");
const models_1 = require("./models");
const db_1 = require("./db");
const BANNED = ["admin", "fuck", "shit", "putain", "merde", "connard", "nazi"];
// YYYYMMDD en heure de Paris (cohérent avec yyyymmdd côté app).
function parisYmd(d) {
    return new Intl.DateTimeFormat("en-CA", {
        timeZone: "Europe/Paris",
        year: "numeric",
        month: "2-digit",
        day: "2-digit",
    })
        .format(d)
        .replace(/-/g, "");
}
function lastYmds(n) {
    const out = [];
    const now = Date.now();
    for (let i = 0; i < n; i++) {
        out.push(parisYmd(new Date(now - i * 86400000)));
    }
    return out;
}
const LEVEL_THRESHOLDS = [0, 30, 80, 200, 450, 800, 1500, 2500, 4000, 7000];
function levelOf(xp) {
    if (xp >= 7000)
        return 10 + Math.floor((xp - 7000) / 2000);
    let level = 1;
    for (let i = LEVEL_THRESHOLDS.length - 1; i >= 0; i--) {
        if (xp >= LEVEL_THRESHOLDS[i]) {
            level = i + 1;
            break;
        }
    }
    return level;
}
// XP « activité » serveur : temps 1/h · routine complétée 2 · défi 5 · action Gantt 1.
async function computeUserXp(uid) {
    var _a, _b, _c, _d, _e, _f, _g, _h, _j, _k;
    const base = db_1.db.collection("users").doc(uid);
    const [sessSnap, hpSnap, actSnap, metaSnap] = await Promise.all([
        base.collection("sessions").get(),
        base.collection("habitProgress").get(),
        base.collection("activities").get(),
        base.collection("data").doc("meta").get(),
    ]);
    // Cibles routines (approx : habitTarget brut, défaut 1).
    const habitTarget = new Map();
    for (const a of actSnap.docs) {
        if (((_a = a.get("type")) !== null && _a !== void 0 ? _a : "time") === "habit") {
            habitTarget.set(a.id, (_b = a.get("habitTarget")) !== null && _b !== void 0 ? _b : 1);
        }
    }
    // Temps loggué : total + par jour (Paris).
    let totalMin = 0;
    const minByDay = new Map();
    for (const s of sessSnap.docs) {
        const startStr = s.get("startAt");
        const endStr = s.get("endAt");
        if (!startStr)
            continue;
        const start = new Date(startStr);
        const end = endStr ? new Date(endStr) : new Date();
        const min = Math.max(0, Math.round((end.getTime() - start.getTime()) / 60000));
        totalMin += min;
        const ymd = parisYmd(start);
        minByDay.set(ymd, ((_c = minByDay.get(ymd)) !== null && _c !== void 0 ? _c : 0) + min);
    }
    // Routines complétées : total + par jour.
    let routinesTotal = 0;
    const routinesByDay = new Map();
    for (const hp of hpSnap.docs) {
        const aid = hp.get("activityId");
        const tgt = aid ? habitTarget.get(aid) : undefined;
        if (tgt === undefined || tgt <= 0)
            continue;
        const val = (_d = hp.get("value")) !== null && _d !== void 0 ? _d : 0;
        if (val >= tgt) {
            routinesTotal++;
            const ymd = (_e = hp.get("yyyymmdd")) !== null && _e !== void 0 ? _e : "";
            routinesByDay.set(ymd, ((_f = routinesByDay.get(ymd)) !== null && _f !== void 0 ? _f : 0) + 1);
        }
    }
    const meta = (_g = metaSnap.data()) !== null && _g !== void 0 ? _g : {};
    const challengesDone = (_h = meta.challengesDone) !== null && _h !== void 0 ? _h : 0;
    const ganttByDay = (_j = meta.ganttActionsByDay) !== null && _j !== void 0 ? _j : {};
    const challengeWinsByDay = (_k = meta.challengeWinsByDay) !== null && _k !== void 0 ? _k : {};
    const ganttTotal = Object.values(ganttByDay).reduce((a, b) => a + b, 0);
    const xpTotal = Math.floor(totalMin / 60) +
        routinesTotal * 2 +
        challengesDone * 5 +
        ganttTotal;
    const xpForDay = (ymd) => {
        var _a, _b, _c, _d;
        return Math.floor(((_a = minByDay.get(ymd)) !== null && _a !== void 0 ? _a : 0) / 60) +
            ((_b = routinesByDay.get(ymd)) !== null && _b !== void 0 ? _b : 0) * 2 +
            ((_c = challengeWinsByDay[ymd]) !== null && _c !== void 0 ? _c : 0) * 5 +
            ((_d = ganttByDay[ymd]) !== null && _d !== void 0 ? _d : 0);
    };
    const xpWeek = lastYmds(7).reduce((s, y) => s + xpForDay(y), 0);
    const xpMonth = lastYmds(30).reduce((s, y) => s + xpForDay(y), 0);
    return { xpTotal, xpWeek, xpMonth, level: levelOf(xpTotal) };
}
async function writeLeaderboardEntry(uid, pseudo) {
    const xp = await computeUserXp(uid);
    await db_1.db.collection("leaderboard_entries").doc(uid).set(Object.assign(Object.assign({ pseudo, optedIn: true }, xp), { updatedAt: db_1.FieldValue.serverTimestamp() }), { merge: true });
}
// POST { pseudo, optedIn }  ·  Authorization: Bearer <firebase-id-token>
exports.claimPseudo = (0, https_1.onRequest)({ cors: true, invoker: "public" }, async (req, res) => {
    var _a;
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
    let uid;
    try {
        uid = (await admin.auth().verifyIdToken(authHeader.slice(7).trim())).uid;
    }
    catch (_b) {
        res.status(401).json({ error: "Token invalide ou expiré" });
        return;
    }
    const { pseudo, optedIn } = req.body;
    const raw = (pseudo !== null && pseudo !== void 0 ? pseudo : "").trim();
    if (!/^[a-zA-Z0-9_]{3,20}$/.test(raw)) {
        res.status(400).json({ error: "Pseudo invalide (3-20 caractères : lettres, chiffres, _)" });
        return;
    }
    const lower = raw.toLowerCase();
    if (BANNED.some((w) => lower.includes(w))) {
        res.status(400).json({ error: "Pseudo non autorisé" });
        return;
    }
    const pseudoRef = db_1.db.collection("pseudos").doc(lower);
    const profileRef = db_1.db.collection("profiles").doc(uid);
    try {
        await db_1.db.runTransaction(async (tx) => {
            const existing = await tx.get(pseudoRef);
            if (existing.exists && existing.get("uid") !== uid) {
                throw new Error("taken");
            }
            const prof = await tx.get(profileRef);
            const oldLower = prof.get("pseudoLower");
            if (oldLower && oldLower !== lower) {
                tx.delete(db_1.db.collection("pseudos").doc(oldLower));
            }
            tx.set(pseudoRef, { uid });
            tx.set(profileRef, {
                pseudo: raw,
                pseudoLower: lower,
                optedIn: optedIn === true,
                updatedAt: db_1.FieldValue.serverTimestamp(),
            }, { merge: true });
        });
    }
    catch (e) {
        if (e.message === "taken") {
            res.status(409).json({ error: "Ce pseudo est déjà pris" });
            return;
        }
        console.error("claimPseudo failed", e);
        res.status(500).json({ error: "Erreur serveur" });
        return;
    }
    // Entrée de classement immédiate (ou retrait si opt-out).
    try {
        if (optedIn === true) {
            await writeLeaderboardEntry(uid, raw);
        }
        else {
            await db_1.db.collection("leaderboard_entries").doc(uid).set({ optedIn: false, updatedAt: db_1.FieldValue.serverTimestamp() }, { merge: true });
        }
    }
    catch (e) {
        console.error("leaderboard entry failed (non bloquant)", e);
    }
    res.status(200).json({ success: true, pseudo: raw });
});
// Recalcule les classements de tous les profils opt-in (anti-triche serveur).
exports.recomputeLeaderboards = (0, scheduler_1.onSchedule)({ schedule: "every 3 hours", timeZone: "Europe/Paris" }, async () => {
    var _a;
    const profs = await db_1.db.collection("profiles").where("optedIn", "==", true).get();
    for (const p of profs.docs) {
        try {
            await writeLeaderboardEntry(p.id, (_a = p.get("pseudo")) !== null && _a !== void 0 ? _a : "");
        }
        catch (e) {
            console.error("recompute failed", p.id, e);
        }
    }
    console.log(`recomputeLeaderboards: ${profs.size} profils`);
});
// ── Phase 2 : bibliothèque de challenges + super-Orion ───────────────────────
async function authUid(req) {
    var _a;
    const h = (_a = req.headers.authorization) !== null && _a !== void 0 ? _a : "";
    if (!h.startsWith("Bearer "))
        return null;
    try {
        return (await admin.auth().verifyIdToken(h.slice(7).trim())).uid;
    }
    catch (_b) {
        return null;
    }
}
// POST { title, description } · soumet un challenge à la modération super-Orion.
exports.submitChallenge = (0, https_1.onRequest)({ cors: true, invoker: "public" }, async (req, res) => {
    var _a;
    if (req.method === "OPTIONS") {
        res.status(204).send("");
        return;
    }
    if (req.method !== "POST") {
        res.status(405).json({ error: "Method Not Allowed" });
        return;
    }
    const uid = await authUid(req);
    if (!uid) {
        res.status(401).json({ error: "Non autorisé" });
        return;
    }
    const { title, description } = req.body;
    const t = (title !== null && title !== void 0 ? title : "").trim();
    const d = (description !== null && description !== void 0 ? description : "").trim();
    if (t.length < 3 || t.length > 80) {
        res.status(400).json({ error: "Titre : 3 à 80 caractères" });
        return;
    }
    if (d.length > 300) {
        res.status(400).json({ error: "Description : 300 caractères max" });
        return;
    }
    const profSnap = await db_1.db.collection("profiles").doc(uid).get();
    const pseudo = (_a = profSnap.get("pseudo")) !== null && _a !== void 0 ? _a : "Anonyme";
    await db_1.db.collection("challenge_submissions").add({
        uid,
        pseudo,
        title: t,
        description: d,
        status: "pending",
        createdAt: db_1.FieldValue.serverTimestamp(),
    });
    res.status(200).json({ success: true });
});
// POST { libraryId, subscribe } · (dé)abonnement à un challenge de la bibliothèque.
exports.subscribeChallenge = (0, https_1.onRequest)({ cors: true, invoker: "public" }, async (req, res) => {
    if (req.method === "OPTIONS") {
        res.status(204).send("");
        return;
    }
    if (req.method !== "POST") {
        res.status(405).json({ error: "Method Not Allowed" });
        return;
    }
    const uid = await authUid(req);
    if (!uid) {
        res.status(401).json({ error: "Non autorisé" });
        return;
    }
    const { libraryId, subscribe } = req.body;
    if (!libraryId) {
        res.status(400).json({ error: "libraryId requis" });
        return;
    }
    const libRef = db_1.db.collection("challenge_library").doc(libraryId);
    const lib = await libRef.get();
    if (!lib.exists) {
        res.status(404).json({ error: "Challenge introuvable" });
        return;
    }
    const subRef = db_1.db.collection("users").doc(uid).collection("challenge_subs").doc(libraryId);
    const already = (await subRef.get()).exists;
    if (subscribe === false) {
        if (already) {
            await subRef.delete();
            await libRef.update({ subscriberCount: db_1.FieldValue.increment(-1) });
        }
    }
    else {
        if (!already) {
            await subRef.set({
                libraryId,
                title: lib.get("title"),
                subscribedAt: db_1.FieldValue.serverTimestamp(),
            });
            await libRef.update({ subscriberCount: db_1.FieldValue.increment(1) });
        }
    }
    res.status(200).json({ success: true });
});
// Cron quotidien : super-Orion modère/catégorise/dédoublonne les soumissions
// (LLM Haiku) → écrit les challenges approuvés dans challenge_library.
exports.superOrionCron = (0, scheduler_1.onSchedule)({ schedule: "every 24 hours", timeZone: "Europe/Paris", secrets: ["ANTHROPIC_API_KEY"] }, async () => {
    var _a, _b, _c, _d, _e, _f;
    const pending = await db_1.db.collection("challenge_submissions")
        .where("status", "==", "pending")
        .limit(30)
        .get();
    if (pending.empty) {
        console.log("superOrion: rien à traiter");
        return;
    }
    const lib = await db_1.db.collection("challenge_library")
        .where("status", "==", "approved")
        .limit(200)
        .get();
    const existing = lib.docs.map((d) => ({ id: d.id, title: d.get("title") }));
    const subs = pending.docs.map((d) => {
        var _a;
        return ({
            id: d.id,
            title: d.get("title"),
            description: (_a = d.get("description")) !== null && _a !== void 0 ? _a : "",
        });
    });
    const apiKey = process.env.ANTHROPIC_API_KEY;
    if (!apiKey) {
        console.error("superOrion: ANTHROPIC_API_KEY manquante");
        return;
    }
    const client = new sdk_1.default({ apiKey });
    const prompt = `Tu es "super-Orion", le curateur d'une bibliothèque de défis de productivité partagée entre utilisateurs.
Pour chaque soumission, décide :
- "approve" : défi clair, sain, utile → fournis title (nettoyé, <60 car.), description (<200 car.), category (parmi: sport, focus, bien-être, apprentissage, social, créativité, autre), durationMin (5-90), xp (5-50 selon difficulté/effort).
- "reject" : inapproprié, spam, dangereux, vide de sens.
- "merge" : quasi-doublon d'un défi existant → fournis mergeId (l'id existant).

Soumissions :
${JSON.stringify(subs)}

Bibliothèque existante (pour détecter les doublons) :
${JSON.stringify(existing)}

Réponds UNIQUEMENT avec un tableau JSON, un objet par soumission :
[{"id":"<submissionId>","action":"approve|reject|merge","title":"","description":"","category":"","durationMin":0,"xp":0,"mergeId":""}]`;
    const response = await client.messages.create({
        model: models_1.MODELS.HAIKU,
        max_tokens: 4096,
        messages: [{ role: "user", content: prompt }],
    });
    (0, models_1.logTokenUsage)("super_orion", models_1.MODELS.HAIKU, response.usage);
    const text = response.content
        .filter((b) => b.type === "text")
        .map((b) => b.text)
        .join("");
    const jsonStr = text.slice(text.indexOf("["), text.lastIndexOf("]") + 1);
    let decisions;
    try {
        decisions = JSON.parse(jsonStr);
    }
    catch (e) {
        console.error("superOrion: parse JSON échoué", e, text.slice(0, 200));
        return;
    }
    const subById = new Map(pending.docs.map((d) => [d.id, d]));
    let approved = 0, merged = 0, rejected = 0;
    for (const dec of decisions) {
        const subId = dec.id;
        const subDoc = subById.get(subId);
        if (!subDoc)
            continue;
        const action = dec.action;
        if (action === "approve") {
            await db_1.db.collection("challenge_library").add({
                title: (_a = dec.title) !== null && _a !== void 0 ? _a : subDoc.get("title"),
                description: (_b = dec.description) !== null && _b !== void 0 ? _b : "",
                category: (_c = dec.category) !== null && _c !== void 0 ? _c : "autre",
                suggestedDurationMin: (_d = dec.durationMin) !== null && _d !== void 0 ? _d : 15,
                xpReward: (_e = dec.xp) !== null && _e !== void 0 ? _e : 10,
                createdByPseudo: (_f = subDoc.get("pseudo")) !== null && _f !== void 0 ? _f : "Anonyme",
                status: "approved",
                subscriberCount: 0,
                createdAt: db_1.FieldValue.serverTimestamp(),
            });
            await subDoc.ref.update({ status: "approved" });
            approved++;
        }
        else if (action === "merge") {
            const mergeId = dec.mergeId;
            await subDoc.ref.update({ status: "merged", mergedInto: mergeId !== null && mergeId !== void 0 ? mergeId : null });
            merged++;
        }
        else {
            await subDoc.ref.update({ status: "rejected" });
            rejected++;
        }
    }
    console.log(`superOrion: ${approved} approuvés, ${merged} fusionnés, ${rejected} rejetés`);
});
//# sourceMappingURL=social.js.map