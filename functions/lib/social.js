"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.resolveBattle = exports.resolveInvasion = exports.deployDefense = exports.engageInvasion = exports.releaseInvasion = exports.deployUnit = exports.joinBattle = exports.createBattle = exports.followNuisible = exports.releaseNuisible = exports.superOrionCron = exports.subscribeChallenge = exports.submitChallenge = exports.recomputeLeaderboards = exports.claimPseudo = void 0;
exports.simulateInvasion = simulateInvasion;
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
// Puissance de deck d'invasion = Σ tierStrength(tier) × roster de rouges DISPONIBLES.
// Miroir serveur EXACT de GoldEngine.invasionDeckPower (redPower == tierStrength).
// Source = users/{uid}/data/meta.redRoster (posé par setInvasionArsenal). Les rouges
// déployés sortent du roster → leur puissance disparaît du ladder (auto-équilibrage #6).
function invasionDeckPower(meta) {
    var _a;
    const roster = (_a = meta === null || meta === void 0 ? void 0 : meta.redRoster) !== null && _a !== void 0 ? _a : {};
    let p = 0;
    for (const tier of Object.keys(roster)) {
        p += tierStrength(tier) * (Number(roster[tier]) || 0);
    }
    return p;
}
async function writeLeaderboardEntry(uid, pseudo) {
    var _a, _b;
    const xp = await computeUserXp(uid);
    // Or disponible : sert de départage secondaire quand l'XP est à égalité.
    const meta = await db_1.db.doc(`users/${uid}/data/meta`).get();
    const gold = (_b = (_a = meta.data()) === null || _a === void 0 ? void 0 : _a.gold) !== null && _b !== void 0 ? _b : 0;
    const deckPower = invasionDeckPower(meta.data());
    await db_1.db.collection("leaderboard_entries").doc(uid).set(Object.assign(Object.assign({ pseudo, optedIn: true }, xp), { gold, deckPower, updatedAt: db_1.FieldValue.serverTimestamp() }), { merge: true });
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
// ── « Le Monde » : relâcher / suivre des nuisibles-routines ──────────────────
// POST { id, routineId, name, freq, target, unit?, iconCode?, domainName?, hp, streak }
// Crée un nuisible public (routine relâchée). Le jeton de relâche est consommé
// côté client (modèle « trust client » de la v1). Le pseudo vient du profil.
exports.releaseNuisible = (0, https_1.onRequest)({ cors: true, invoker: "public" }, async (req, res) => {
    var _a, _b, _c, _d, _e, _f, _g, _h, _j, _k, _l;
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
    const b = req.body;
    const id = ((_a = b.id) !== null && _a !== void 0 ? _a : "").trim();
    const name = ((_b = b.name) !== null && _b !== void 0 ? _b : "").trim();
    const freq = (_c = b.freq) !== null && _c !== void 0 ? _c : "daily";
    if (!id) {
        res.status(400).json({ error: "id requis" });
        return;
    }
    if (name.length < 2 || name.length > 60) {
        res.status(400).json({ error: "Nom : 2 à 60 caractères" });
        return;
    }
    if (!["daily", "weekly", "monthly"].includes(freq)) {
        res.status(400).json({ error: "freq invalide" });
        return;
    }
    const profSnap = await db_1.db.collection("profiles").doc(uid).get();
    const pseudo = (_d = profSnap.get("pseudo")) !== null && _d !== void 0 ? _d : "Anonyme";
    const hp = Math.max(1, Math.min(40, Math.floor(Number((_e = b.hp) !== null && _e !== void 0 ? _e : 3))));
    const target = Math.max(1, Math.floor(Number((_f = b.target) !== null && _f !== void 0 ? _f : 1)));
    const streak = Math.max(0, Math.floor(Number((_g = b.streak) !== null && _g !== void 0 ? _g : 0)));
    await db_1.db.collection("world_nuisibles").doc(id).set({
        id,
        ownerUid: uid,
        ownerPseudo: pseudo,
        routineId: (_h = b.routineId) !== null && _h !== void 0 ? _h : "",
        name,
        freq,
        target,
        unit: (_j = b.unit) !== null && _j !== void 0 ? _j : null,
        iconCode: (_k = b.iconCode) !== null && _k !== void 0 ? _k : null,
        domainName: (_l = b.domainName) !== null && _l !== void 0 ? _l : null,
        hp,
        streak,
        spectatorCount: 0,
        active: true,
        createdAt: db_1.FieldValue.serverTimestamp(),
    }, { merge: true });
    res.status(200).json({ success: true, id });
});
// POST { nuisibleId, follow } · suivre/ne plus suivre une routine relâchée.
// Le « droit de suivre » s'obtient en battant le nuisible côté client (v1
// trust client) ; ici on enregistre le suivi + maj le compteur de spectateurs.
exports.followNuisible = (0, https_1.onRequest)({ cors: true, invoker: "public" }, async (req, res) => {
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
    const { nuisibleId, follow } = req.body;
    if (!nuisibleId) {
        res.status(400).json({ error: "nuisibleId requis" });
        return;
    }
    const nRef = db_1.db.collection("world_nuisibles").doc(nuisibleId);
    const n = await nRef.get();
    if (!n.exists) {
        res.status(404).json({ error: "Nuisible introuvable" });
        return;
    }
    if (n.get("ownerUid") === uid) {
        res.status(400).json({ error: "On ne suit pas sa propre routine" });
        return;
    }
    const fRef = db_1.db.collection("users").doc(uid).collection("world_follows").doc(nuisibleId);
    const already = (await fRef.get()).exists;
    if (follow === false) {
        if (already) {
            await fRef.delete();
            await nRef.update({ spectatorCount: db_1.FieldValue.increment(-1) });
        }
    }
    else {
        if (!already) {
            await fRef.set({
                nuisibleId,
                ownerUid: n.get("ownerUid"),
                ownerPseudo: n.get("ownerPseudo"),
                name: n.get("name"),
                followedAt: db_1.FieldValue.serverTimestamp(),
            });
            await nRef.update({ spectatorCount: db_1.FieldValue.increment(1) });
        }
    }
    res.status(200).json({ success: true });
});
function simulateBattle(events, width, lanes, nowTick) {
    var _a;
    const camp = (s) => (s === 0 ? 0 : width - 1);
    const dir = (s) => (s === 0 ? 1 : -1);
    const strength = (t) => (t === "serpent" ? 3 : t === "scorpion" ? 2 : 1);
    const below = (t) => t === "serpent" ? "scorpion" : t === "scorpion" ? "spider" : null;
    const byTick = new Map();
    for (const e of events) {
        const a = (_a = byTick.get(e.tick)) !== null && _a !== void 0 ? _a : [];
        a.push(e);
        byTick.set(e.tick, a);
    }
    const units = [];
    let winnerSide = null;
    let winTick = null;
    for (let t = 0; t <= nowTick; t++) {
        const prev = new Map();
        for (const u of units) {
            if (!u.alive)
                continue;
            prev.set(u.id, u.cell);
            u.cell += dir(u.side);
        }
        const arr = byTick.get(t);
        if (arr) {
            for (const e of arr) {
                const u = { id: e.id, side: e.side, lane: e.lane, isFlame: e.kind === "flame", tier: e.tier, alive: true, cell: camp(e.side) };
                prev.set(u.id, u.cell);
                units.push(u);
            }
        }
        const meet = (a, b) => {
            if (a.cell === b.cell)
                return true;
            const pa = prev.get(a.id);
            const pb = prev.get(b.id);
            if (pa == null || pb == null)
                return false;
            return pa === b.cell && pb === a.cell;
        };
        for (let i = 0; i < units.length; i++) {
            const a = units[i];
            if (!a.alive)
                continue;
            for (let j = i + 1; j < units.length; j++) {
                const b = units[j];
                if (!b.alive)
                    continue;
                if (a.side === b.side || a.lane !== b.lane)
                    continue;
                if (!meet(a, b))
                    continue;
                if (a.isFlame && b.isFlame)
                    continue;
                if (a.isFlame) {
                    b.alive = false;
                    continue;
                }
                if (b.isFlame) {
                    a.alive = false;
                    break;
                }
                const sa = strength(a.tier);
                const sb = strength(b.tier);
                if (sa === sb) {
                    a.alive = false;
                    b.alive = false;
                    break;
                }
                else if (sa > sb) {
                    b.alive = false;
                    const d = below(a.tier);
                    if (d)
                        a.tier = d;
                }
                else {
                    a.alive = false;
                    const d = below(b.tier);
                    if (d)
                        b.tier = d;
                    break;
                }
            }
        }
        let s0 = null;
        let s1 = null;
        for (const u of units) {
            if (!u.alive || u.isFlame)
                continue;
            const crossed = u.side === 0 ? u.cell >= width : u.cell < 0;
            if (crossed) {
                if (u.side === 0)
                    s0 = 0;
                else
                    s1 = 1;
            }
        }
        if (s0 !== null || s1 !== null) {
            winnerSide = s0 !== null ? s0 : s1;
            winTick = t;
            break;
        }
    }
    return { winnerSide, winTick };
}
// ── Invasion : moteur de tower-defense ASYMÉTRIQUE (mirroir de lib/battle_sim.dart
// `simulateInvasion`). Envahisseur = side 0 (force figée, avance, franchit à cell≥width
// = territoire tenu). Défenseur = side 1 (dépose des bloqueurs `pest` + tire des flèches
// `arrow`). Le défenseur gagne UNIQUEMENT par élimination totale (pas de franchissement
// gagnant). Flèche = dégrade d'un cran l'envahisseur le plus avancé de la lane.
const tierStrength = (t) => t === "serpent" ? 3 : t === "scorpion" ? 2 : 1;
const tierBelow = (t) => t === "serpent" ? "scorpion" : t === "scorpion" ? "spider" : null;
// Dégrade d'un cran l'envahisseur (side 0) le plus avancé vivant de `lane`
// (cell max ; égalité → id le plus petit). Spider → mort. No-op si lane vide.
function applyArrow(units, lane) {
    let best = null;
    for (const u of units) {
        if (!u.alive || u.isFlame || u.side !== 0 || u.lane !== lane)
            continue;
        if (best === null) {
            best = u;
            continue;
        }
        if (u.cell > best.cell || (u.cell === best.cell && u.id < best.id))
            best = u;
    }
    if (best === null)
        return;
    const d = tierBelow(best.tier);
    if (d === null)
        best.alive = false;
    else
        best.tier = d;
}
// `export` : utilisé par resolveInvasion (Phase 2) ; évite l'erreur noUnusedLocals
// en attendant. Helper pur — n'est PAS une Cloud Function (index.ts n'exporte que les
// onRequest nommés), donc inerte côté déploiement.
function simulateInvasion(events, width, lanes, nowTick) {
    var _a;
    const camp = (s) => (s === 0 ? 0 : width - 1);
    const dir = (s) => (s === 0 ? 1 : -1);
    const byTick = new Map();
    for (const e of events) {
        const a = (_a = byTick.get(e.tick)) !== null && _a !== void 0 ? _a : [];
        a.push(e);
        byTick.set(e.tick, a);
    }
    const units = [];
    let anyInvader = false;
    let winner = null;
    let winTick = null;
    for (let t = 0; t <= nowTick; t++) {
        const prev = new Map();
        for (const u of units) {
            if (!u.alive)
                continue;
            prev.set(u.id, u.cell);
            u.cell += dir(u.side);
        }
        const arrows = [];
        const arr = byTick.get(t);
        if (arr) {
            for (const e of arr) {
                if (e.kind === "arrow") {
                    arrows.push(e);
                    continue;
                }
                const u = {
                    id: e.id, side: e.side, lane: e.lane, isFlame: e.kind === "flame",
                    tier: e.tier, alive: true, cell: camp(e.side),
                };
                prev.set(u.id, u.cell);
                units.push(u);
                if (e.side === 0 && e.kind !== "flame")
                    anyInvader = true;
            }
        }
        arrows.sort((a, b) => (a.id < b.id ? -1 : a.id > b.id ? 1 : 0));
        for (const a of arrows)
            applyArrow(units, a.lane);
        const meet = (a, b) => {
            if (a.cell === b.cell)
                return true;
            const pa = prev.get(a.id);
            const pb = prev.get(b.id);
            if (pa == null || pb == null)
                return false;
            return pa === b.cell && pb === a.cell;
        };
        for (let i = 0; i < units.length; i++) {
            const a = units[i];
            if (!a.alive)
                continue;
            for (let j = i + 1; j < units.length; j++) {
                const b = units[j];
                if (!b.alive)
                    continue;
                if (a.side === b.side || a.lane !== b.lane)
                    continue;
                if (!meet(a, b))
                    continue;
                if (a.isFlame && b.isFlame)
                    continue;
                if (a.isFlame) {
                    b.alive = false;
                    continue;
                }
                if (b.isFlame) {
                    a.alive = false;
                    break;
                }
                const sa = tierStrength(a.tier);
                const sb = tierStrength(b.tier);
                if (sa === sb) {
                    a.alive = false;
                    b.alive = false;
                    break;
                }
                else if (sa > sb) {
                    b.alive = false;
                    const d = tierBelow(a.tier);
                    if (d)
                        a.tier = d;
                }
                else {
                    a.alive = false;
                    const d = tierBelow(b.tier);
                    if (d)
                        b.tier = d;
                    break;
                }
            }
        }
        let invaderCrossed = false;
        for (const u of units) {
            if (!u.alive || u.isFlame)
                continue;
            if (u.side === 0 && u.cell >= width) {
                invaderCrossed = true;
                break;
            }
        }
        if (invaderCrossed) {
            winner = "invader";
            winTick = t;
            break;
        }
        if (anyInvader) {
            const invadersAlive = units.some((u) => u.alive && !u.isFlame && u.side === 0);
            if (!invadersAlive) {
                winner = "defender";
                winTick = t;
                break;
            }
        }
    }
    return { winner, winTick };
}
const clampInt = (v, lo, hi, def) => {
    const n = Math.floor(Number(v !== null && v !== void 0 ? v : def));
    if (!Number.isFinite(n))
        return def;
    return n < lo ? lo : n > hi ? hi : n;
};
// POST { width?, lanes?, tickMinutes? } → crée une partie en attente d'adversaire.
exports.createBattle = (0, https_1.onRequest)({ cors: true, invoker: "public" }, async (req, res) => {
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
    const b = req.body;
    const width = clampInt(b.width, 3, 12, 7);
    const lanes = clampInt(b.lanes, 1, 8, 5);
    const tickMinutes = clampInt(b.tickMinutes, 1, 1440, 60);
    const prof = await db_1.db.collection("profiles").doc(uid).get();
    const pseudo = (_a = prof.get("pseudo")) !== null && _a !== void 0 ? _a : "Anonyme";
    const ref = db_1.db.collection("battles").doc();
    await ref.set({
        id: ref.id, width, lanes, tickMinutes,
        status: "waiting", players: [uid], sides: { [uid]: 0 },
        pseudos: { [uid]: pseudo }, startAt: null, winnerUid: null,
        createdAt: db_1.FieldValue.serverTimestamp(),
    });
    res.status(200).json({ battleId: ref.id });
});
// POST { battleId } → rejoint une partie en attente (lance l'horloge).
exports.joinBattle = (0, https_1.onRequest)({ cors: true, invoker: "public" }, async (req, res) => {
    var _a, _b, _c;
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
    const battleId = ((_b = (_a = req.body) === null || _a === void 0 ? void 0 : _a.battleId) !== null && _b !== void 0 ? _b : "").trim();
    if (!battleId) {
        res.status(400).json({ error: "battleId requis" });
        return;
    }
    const ref = db_1.db.collection("battles").doc(battleId);
    const out = await db_1.db.runTransaction(async (tx) => {
        var _a, _b;
        const snap = await tx.get(ref);
        if (!snap.exists)
            return { err: "Bataille introuvable", code: 404 };
        const data = snap.data();
        const players = (_a = data.players) !== null && _a !== void 0 ? _a : [];
        if (players.includes(uid))
            return { ok: true };
        if (data.status !== "waiting" || players.length >= 2) {
            return { err: "Bataille déjà complète", code: 400 };
        }
        const prof = await tx.get(db_1.db.collection("profiles").doc(uid));
        const pseudo = (_b = prof.get("pseudo")) !== null && _b !== void 0 ? _b : "Anonyme";
        tx.update(ref, {
            players: [...players, uid],
            [`sides.${uid}`]: 1,
            [`pseudos.${uid}`]: pseudo,
            status: "active",
            startAt: db_1.FieldValue.serverTimestamp(),
        });
        return { ok: true };
    });
    if ("err" in out) {
        res.status((_c = out.code) !== null && _c !== void 0 ? _c : 400).json({ error: out.err });
        return;
    }
    res.status(200).json({ success: true });
});
// POST { battleId, lane, kind, tier } → dépose un nuisible/flamme (tick serveur).
// Valide : partie active, joueur, couloir, max 3 flammes, VERROU de couloir
// (une flamme exige un couloir libre de tes unités ; pas de pose dans le couloir
// d'une de tes flammes en transit). La masse est débitée côté client (trust v1).
exports.deployUnit = (0, https_1.onRequest)({ cors: true, invoker: "public" }, async (req, res) => {
    var _a, _b, _c, _d, _e;
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
    const b = req.body;
    const battleId = ((_a = b.battleId) !== null && _a !== void 0 ? _a : "").trim();
    const lane = Math.floor(Number((_b = b.lane) !== null && _b !== void 0 ? _b : -1));
    const kind = (_c = b.kind) !== null && _c !== void 0 ? _c : "pest";
    const tier = (_d = b.tier) !== null && _d !== void 0 ? _d : "spider";
    if (!battleId) {
        res.status(400).json({ error: "battleId requis" });
        return;
    }
    if (kind !== "pest" && kind !== "flame") {
        res.status(400).json({ error: "kind invalide" });
        return;
    }
    const ref = db_1.db.collection("battles").doc(battleId);
    const out = await db_1.db.runTransaction(async (tx) => {
        var _a, _b, _c, _d, _e, _f, _g, _h, _j;
        const snap = await tx.get(ref);
        if (!snap.exists)
            return { err: "Bataille introuvable", code: 404 };
        const data = snap.data();
        if (data.status !== "active")
            return { err: "Bataille non active", code: 400 };
        const players = (_a = data.players) !== null && _a !== void 0 ? _a : [];
        if (!players.includes(uid))
            return { err: "Tu n'es pas dans cette bataille", code: 403 };
        const sides = (_b = data.sides) !== null && _b !== void 0 ? _b : {};
        const side = (_c = sides[uid]) !== null && _c !== void 0 ? _c : (players[0] === uid ? 0 : 1);
        const width = Number((_d = data.width) !== null && _d !== void 0 ? _d : 7);
        const lanes = Number((_e = data.lanes) !== null && _e !== void 0 ? _e : 5);
        const tickMinutes = Number((_f = data.tickMinutes) !== null && _f !== void 0 ? _f : 60);
        if (lane < 0 || lane >= lanes)
            return { err: "Couloir invalide", code: 400 };
        const startMs = (_j = (_h = (_g = data.startAt) === null || _g === void 0 ? void 0 : _g.toMillis) === null || _h === void 0 ? void 0 : _h.call(_g)) !== null && _j !== void 0 ? _j : Date.now();
        const nowTick = Math.max(0, Math.floor((Date.now() - startMs) / (tickMinutes * 60000)));
        const evSnap = await tx.get(ref.collection("events").where("uid", "==", uid));
        const mine = evSnap.docs.map((d) => d.data());
        const masseCost = (t) => (t === "serpent" ? 15 : t === "scorpion" ? 10 : 5);
        if (kind === "flame") {
            const flames = mine.filter((e) => e.kind === "flame");
            if (flames.length >= 3)
                return { err: "Plus de flammes (3 max)", code: 400 };
            // 1 flamme par tick (pas de triple-flamme d'un coup).
            if (flames.some((e) => Number(e.tick) === nowTick)) {
                return { err: "Une seule flamme par tick", code: 429 };
            }
        }
        else {
            // Anti-déluge : ≤ 15 de masse déployée par tick (= 1 serpent, ou
            // 1 scorpion + 1 araignée, ou 3 araignées). La réserve à vie = ENDURANCE
            // (combien de vagues), pas une frappe instantanée. Empêche
            // « 50 araignées balancées d'un coup en serpents ».
            const spentThisTick = mine
                .filter((e) => e.kind === "pest" && Number(e.tick) === nowTick)
                .reduce((s, e) => { var _a; return s + masseCost(String((_a = e.tier) !== null && _a !== void 0 ? _a : "spider")); }, 0);
            if (spentThisTick + masseCost(tier) > 15) {
                return { err: "Budget de masse du tick atteint (15 max) — attends le prochain tour", code: 429 };
            }
        }
        // « encore en transit » = sur-approximation sûre (durée de vie max = width).
        const liveInLane = mine.filter((e) => Number(e.lane) === lane && Number(e.tick) + width > nowTick);
        if (kind === "flame") {
            if (liveInLane.length > 0) {
                return { err: "Couloir occupé par tes unités — la flamme exige un couloir libre", code: 400 };
            }
        }
        else if (liveInLane.some((e) => e.kind === "flame")) {
            return { err: "Une de tes flammes traverse ce couloir", code: 400 };
        }
        const evRef = ref.collection("events").doc();
        tx.set(evRef, {
            id: evRef.id, uid, side, lane, kind,
            tier: kind === "pest" ? tier : "",
            deployedAt: db_1.FieldValue.serverTimestamp(), tick: nowTick,
        });
        return { ok: true, tick: nowTick, eventId: evRef.id };
    });
    if ("err" in out) {
        res.status((_e = out.code) !== null && _e !== void 0 ? _e : 400).json({ error: out.err });
        return;
    }
    res.status(200).json(out);
});
// ── Invasion / Territoires : les 4 Cloud Functions ───────────────────────────
// release (compose la force + matchmaking ladder), engage (défenseur lance
// l'horloge), deployDefense (bloqueurs + flèches), resolve (re-simule, autoritatif).
// Économie trust-client v1 : le client compose sa force depuis son deck vert et
// décrémente son propre redRoster ; le serveur valide les plafonds et tranche.
const INV_WIDTH = 7;
const INV_LANES = 5;
const INV_TICK_MINUTES = 60;
const invMasseCost = (t) => t === "serpent" ? 15 : t === "scorpion" ? 10 : 5;
const levelOfTier = (t) => t === "serpent" ? 5 : t === "scorpion" ? 3 : 1;
const INV_TIERS = ["serpent", "scorpion", "spider"];
// POST { redTier, force:[{id,tier,lane,tick}], forceMasse } → crée une invasion
// `pending` contre une cible du ladder (~3 rangs au-dessus, sinon wrap). La force
// est FIGÉE inline (side 0). Le rouge (ticket) est décrémenté côté client.
exports.releaseInvasion = (0, https_1.onRequest)({ cors: true, invoker: "public" }, async (req, res) => {
    var _a, _b, _c, _d, _e, _f;
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
    const b = req.body;
    const redTier = (_a = b.redTier) !== null && _a !== void 0 ? _a : "";
    if (!INV_TIERS.includes(redTier)) {
        res.status(400).json({ error: "redTier invalide" });
        return;
    }
    const capStrength = tierStrength(redTier);
    // Force : copie du deck vert ≤ palier du rouge, métrée en vagues (trust-client).
    const rawForce = Array.isArray(b.force) ? b.force : [];
    if (rawForce.length === 0) {
        res.status(400).json({ error: "force vide" });
        return;
    }
    if (rawForce.length > 400) {
        res.status(400).json({ error: "force trop grande (400 max)" });
        return;
    }
    const force = [];
    let i = 0;
    for (const u of rawForce) {
        const o = (u !== null && u !== void 0 ? u : {});
        const tier = (_b = o.tier) !== null && _b !== void 0 ? _b : "spider";
        if (!INV_TIERS.includes(tier)) {
            res.status(400).json({ error: "tier d'unité invalide" });
            return;
        }
        if (tierStrength(tier) > capStrength) {
            res.status(400).json({ error: "une unité dépasse le palier du rouge" });
            return;
        }
        const lane = clampInt(o.lane, 0, INV_LANES - 1, 0);
        const tick = clampInt(o.tick, 0, 9999, 0);
        const id = ((_c = o.id) !== null && _c !== void 0 ? _c : `f${i}`).slice(0, 40);
        force.push({ id, tier, lane, tick });
        i++;
    }
    const forceMasse = force.reduce((s, u) => s + invMasseCost(u.tier), 0);
    // Puissance live de l'attaquant = Σ tierStrength × redRoster (état courant).
    const myMeta = await db_1.db.doc(`users/${uid}/data/meta`).get();
    const myPower = invasionDeckPower(myMeta.data());
    // Matchmaking ladder : ~3 rangs au-dessus ; si l'attaquant est en tête, wrap
    // vers les plus forts juste en dessous. Exclut soi-même + cibles saturées
    // (≥ 3 invasions pending/active déjà reçues).
    const pickAbove = await db_1.db.collection("leaderboard_entries")
        .where("optedIn", "==", true)
        .where("deckPower", ">", myPower)
        .orderBy("deckPower", "asc").limit(5).get();
    let cands = pickAbove.docs.map((d) => d.id).filter((u) => u !== uid);
    if (cands.length === 0) {
        const wrap = await db_1.db.collection("leaderboard_entries")
            .where("optedIn", "==", true)
            .where("deckPower", "<", myPower)
            .orderBy("deckPower", "desc").limit(5).get();
        cands = wrap.docs.map((d) => d.id).filter((u) => u !== uid);
    }
    // Filtre anti-concentration (max 3 invasions actives reçues).
    const valid = [];
    for (const c of cands) {
        if (valid.length >= 3)
            break;
        const recv = await db_1.db.collection("invasions")
            .where("defenderUid", "==", c)
            .where("status", "in", ["pending", "active"]).get();
        if (recv.size < 3)
            valid.push(c);
    }
    if (valid.length === 0) {
        res.status(200).json({ ok: false, reason: "no_target" });
        return;
    }
    const defenderUid = valid[Math.floor(Math.random() * valid.length)];
    const [myProf, defProf] = await Promise.all([
        db_1.db.collection("profiles").doc(uid).get(),
        db_1.db.collection("profiles").doc(defenderUid).get(),
    ]);
    const ref = db_1.db.collection("invasions").doc();
    await ref.set({
        id: ref.id,
        invaderUid: uid,
        invaderPseudo: (_d = myProf.get("pseudo")) !== null && _d !== void 0 ? _d : "Anonyme",
        defenderUid,
        defenderPseudo: (_e = defProf.get("pseudo")) !== null && _e !== void 0 ? _e : "Anonyme",
        redTier, level: levelOfTier(redTier), pestType: redTier,
        status: "pending",
        force, forceMasse,
        width: INV_WIDTH, lanes: INV_LANES, tickMinutes: INV_TICK_MINUTES,
        startAt: null, winner: null, revealedToDefender: false,
        defenderReward: null, resolvedAt: null,
        createdAt: db_1.FieldValue.serverTimestamp(),
    });
    res.status(200).json({
        ok: true, invasionId: ref.id,
        defenderUid, defenderPseudo: (_f = defProf.get("pseudo")) !== null && _f !== void 0 ? _f : "Anonyme",
    });
});
// POST { invasionId } → le DÉFENSEUR engage : pending → active, lance l'horloge.
exports.engageInvasion = (0, https_1.onRequest)({ cors: true, invoker: "public" }, async (req, res) => {
    var _a, _b, _c;
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
    const invasionId = ((_b = (_a = req.body) === null || _a === void 0 ? void 0 : _a.invasionId) !== null && _b !== void 0 ? _b : "").trim();
    if (!invasionId) {
        res.status(400).json({ error: "invasionId requis" });
        return;
    }
    const ref = db_1.db.collection("invasions").doc(invasionId);
    const out = await db_1.db.runTransaction(async (tx) => {
        const snap = await tx.get(ref);
        if (!snap.exists)
            return { err: "Invasion introuvable", code: 404 };
        const data = snap.data();
        if (data.defenderUid !== uid)
            return { err: "Tu n'es pas le défenseur", code: 403 };
        if (data.status === "active")
            return { ok: true, already: true };
        if (data.status !== "pending")
            return { err: "Invasion déjà résolue", code: 400 };
        tx.update(ref, { status: "active", startAt: db_1.FieldValue.serverTimestamp() });
        return { ok: true };
    });
    if ("err" in out) {
        res.status((_c = out.code) !== null && _c !== void 0 ? _c : 400).json({ error: out.err });
        return;
    }
    res.status(200).json(out);
});
// POST { invasionId, lane, kind('pest'|'arrow'), tier } → le DÉFENSEUR dépose un
// bloqueur ou tire une flèche (tick serveur). Budget 15 masse/tick (pest) ; cap
// 3 flèches/tick. Stock débité côté client (trust v1).
exports.deployDefense = (0, https_1.onRequest)({ cors: true, invoker: "public" }, async (req, res) => {
    var _a, _b, _c, _d, _e;
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
    const b = req.body;
    const invasionId = ((_a = b.invasionId) !== null && _a !== void 0 ? _a : "").trim();
    const lane = Math.floor(Number((_b = b.lane) !== null && _b !== void 0 ? _b : -1));
    const kind = (_c = b.kind) !== null && _c !== void 0 ? _c : "pest";
    const tier = (_d = b.tier) !== null && _d !== void 0 ? _d : "spider";
    if (!invasionId) {
        res.status(400).json({ error: "invasionId requis" });
        return;
    }
    if (kind !== "pest" && kind !== "arrow") {
        res.status(400).json({ error: "kind invalide" });
        return;
    }
    if (kind === "pest" && !INV_TIERS.includes(tier)) {
        res.status(400).json({ error: "tier invalide" });
        return;
    }
    const ref = db_1.db.collection("invasions").doc(invasionId);
    const out = await db_1.db.runTransaction(async (tx) => {
        var _a, _b, _c, _d, _e;
        const snap = await tx.get(ref);
        if (!snap.exists)
            return { err: "Invasion introuvable", code: 404 };
        const data = snap.data();
        if (data.defenderUid !== uid)
            return { err: "Tu n'es pas le défenseur", code: 403 };
        if (data.status !== "active")
            return { err: "Invasion non active", code: 400 };
        const lanes = Number((_a = data.lanes) !== null && _a !== void 0 ? _a : INV_LANES);
        const tickMinutes = Number((_b = data.tickMinutes) !== null && _b !== void 0 ? _b : INV_TICK_MINUTES);
        if (lane < 0 || lane >= lanes)
            return { err: "Couloir invalide", code: 400 };
        const startMs = (_e = (_d = (_c = data.startAt) === null || _c === void 0 ? void 0 : _c.toMillis) === null || _d === void 0 ? void 0 : _d.call(_c)) !== null && _e !== void 0 ? _e : Date.now();
        const nowTick = Math.max(0, Math.floor((Date.now() - startMs) / (tickMinutes * 60000)));
        const evSnap = await tx.get(ref.collection("events"));
        const mine = evSnap.docs.map((d) => d.data());
        if (kind === "arrow") {
            const arrowsThisTick = mine.filter((e) => e.kind === "arrow" && Number(e.tick) === nowTick).length;
            if (arrowsThisTick >= 3) {
                return { err: "Plus de flèches ce tour (3 max) — attends le prochain", code: 429 };
            }
        }
        else {
            const spentThisTick = mine
                .filter((e) => e.kind === "pest" && Number(e.tick) === nowTick)
                .reduce((s, e) => { var _a; return s + invMasseCost(String((_a = e.tier) !== null && _a !== void 0 ? _a : "spider")); }, 0);
            if (spentThisTick + invMasseCost(tier) > 15) {
                return { err: "Budget de masse du tick atteint (15 max) — attends le prochain tour", code: 429 };
            }
        }
        const evRef = ref.collection("events").doc();
        tx.set(evRef, {
            id: evRef.id, side: 1, lane, kind,
            tier: kind === "pest" ? tier : "",
            deployedAt: db_1.FieldValue.serverTimestamp(), tick: nowTick,
        });
        return { ok: true, tick: nowTick, eventId: evRef.id };
    });
    if ("err" in out) {
        res.status((_e = out.code) !== null && _e !== void 0 ? _e : 400).json({ error: out.err });
        return;
    }
    res.status(200).json(out);
});
// POST { invasionId } → re-simule côté serveur (autoritatif). invader franchit →
// `held` (prestige, 0 revenu) ; défenseur élimine tout → `repelled` + révélation
// + récompense + grant de suivi + LEDGER de retour du rouge downgradé (idempotent
// par invasionId, appliqué 1× par le client de l'envahisseur). Idempotent.
exports.resolveInvasion = (0, https_1.onRequest)({ cors: true, invoker: "public" }, async (req, res) => {
    var _a, _b, _c;
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
    const invasionId = ((_b = (_a = req.body) === null || _a === void 0 ? void 0 : _a.invasionId) !== null && _b !== void 0 ? _b : "").trim();
    if (!invasionId) {
        res.status(400).json({ error: "invasionId requis" });
        return;
    }
    const ref = db_1.db.collection("invasions").doc(invasionId);
    const out = await db_1.db.runTransaction(async (tx) => {
        var _a, _b, _c, _d, _e, _f, _g, _h, _j, _k;
        const snap = await tx.get(ref);
        if (!snap.exists)
            return { err: "Invasion introuvable", code: 404 };
        const data = snap.data();
        const invaderUid = data.invaderUid;
        const defenderUid = data.defenderUid;
        if (uid !== invaderUid && uid !== defenderUid) {
            return { err: "Tu n'es pas dans cette invasion", code: 403 };
        }
        if (data.status === "repelled" || data.status === "held") {
            return { ok: true, status: data.status, winner: (_a = data.winner) !== null && _a !== void 0 ? _a : null, already: true };
        }
        if (data.status !== "active")
            return { ok: true, ongoing: true, status: data.status };
        const width = Number((_b = data.width) !== null && _b !== void 0 ? _b : INV_WIDTH);
        const lanes = Number((_c = data.lanes) !== null && _c !== void 0 ? _c : INV_LANES);
        const tickMinutes = Number((_d = data.tickMinutes) !== null && _d !== void 0 ? _d : INV_TICK_MINUTES);
        const startMs = (_g = (_f = (_e = data.startAt) === null || _e === void 0 ? void 0 : _e.toMillis) === null || _f === void 0 ? void 0 : _f.call(_e)) !== null && _g !== void 0 ? _g : Date.now();
        const nowTick = Math.max(0, Math.floor((Date.now() - startMs) / (tickMinutes * 60000)));
        const force = (_h = data.force) !== null && _h !== void 0 ? _h : [];
        const evSnap = await tx.get(ref.collection("events"));
        const events = [
            ...force.map((u) => {
                var _a, _b;
                return ({
                    id: u.id, side: 0, lane: Number((_a = u.lane) !== null && _a !== void 0 ? _a : 0),
                    kind: "pest", tier: u.tier || "spider", tick: Number((_b = u.tick) !== null && _b !== void 0 ? _b : 0),
                });
            }),
            ...evSnap.docs.map((d) => {
                var _a, _b, _c, _d;
                const e = d.data();
                return {
                    id: (_a = e.id) !== null && _a !== void 0 ? _a : d.id, side: 1, lane: Number((_b = e.lane) !== null && _b !== void 0 ? _b : 0),
                    kind: (_c = e.kind) !== null && _c !== void 0 ? _c : "pest", tier: e.tier || "spider", tick: Number((_d = e.tick) !== null && _d !== void 0 ? _d : 0),
                };
            }),
        ];
        const sim = simulateInvasion(events, width, lanes, nowTick);
        if (sim.winner === null)
            return { ok: true, ongoing: true };
        if (sim.winner === "invader") {
            tx.update(ref, {
                status: "held", winner: "invader", winTick: sim.winTick,
                resolvedAt: db_1.FieldValue.serverTimestamp(),
            });
            return { ok: true, status: "held", winner: "invader" };
        }
        // défenseur : territoire libéré.
        const redTier = data.redTier || "spider";
        const forceMasse = Number((_j = data.forceMasse) !== null && _j !== void 0 ? _j : 0);
        const defenderReward = 20 * tierStrength(redTier) + Math.min(forceMasse, 100);
        tx.update(ref, {
            status: "repelled", winner: "defender", winTick: sim.winTick,
            revealedToDefender: true, defenderReward,
            resolvedAt: db_1.FieldValue.serverTimestamp(),
        });
        // Grant de suivi (droit de contre-envahir) — espace du défenseur.
        tx.set(db_1.db.collection("users").doc(defenderUid).collection("invasion_follows").doc(invaderUid), {
            invaderUid, invaderPseudo: (_k = data.invaderPseudo) !== null && _k !== void 0 ? _k : "Anonyme",
            invasionId, followedAt: db_1.FieldValue.serverTimestamp(),
        }, { merge: true });
        // Ledger de retour du rouge downgradé (spider → mort, pas de retour).
        const returnTier = tierBelow(redTier);
        tx.set(db_1.db.collection("users").doc(invaderUid).collection("red_returns").doc(invasionId), {
            invasionId, tier: returnTier, fromTier: redTier,
            createdAt: db_1.FieldValue.serverTimestamp(),
        }, { merge: true });
        return { ok: true, status: "repelled", winner: "defender", defenderReward };
    });
    if ("err" in out) {
        res.status((_c = out.code) !== null && _c !== void 0 ? _c : 400).json({ error: out.err });
        return;
    }
    res.status(200).json(out);
});
// POST { battleId } → re-simule côté serveur ; si victoire, fige la partie et
// crédite profiles/{winnerUid}.battleWins (idempotent). Appelé par un client
// quand sa simu locale détecte une victoire ; le serveur tranche.
exports.resolveBattle = (0, https_1.onRequest)({ cors: true, invoker: "public" }, async (req, res) => {
    var _a, _b, _c;
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
    const battleId = ((_b = (_a = req.body) === null || _a === void 0 ? void 0 : _a.battleId) !== null && _b !== void 0 ? _b : "").trim();
    if (!battleId) {
        res.status(400).json({ error: "battleId requis" });
        return;
    }
    const ref = db_1.db.collection("battles").doc(battleId);
    const out = await db_1.db.runTransaction(async (tx) => {
        var _a, _b, _c, _d, _e, _f, _g, _h, _j, _k;
        const snap = await tx.get(ref);
        if (!snap.exists)
            return { err: "Bataille introuvable", code: 404 };
        const data = snap.data();
        if (data.status === "finished") {
            return { ok: true, winnerUid: (_a = data.winnerUid) !== null && _a !== void 0 ? _a : null, already: true };
        }
        const players = (_b = data.players) !== null && _b !== void 0 ? _b : [];
        if (!players.includes(uid))
            return { err: "Tu n'es pas dans cette bataille", code: 403 };
        const evSnap = await tx.get(ref.collection("events"));
        const events = evSnap.docs.map((d) => {
            var _a, _b, _c, _d, _e;
            const e = d.data();
            return {
                id: (_a = e.id) !== null && _a !== void 0 ? _a : d.id, side: Number((_b = e.side) !== null && _b !== void 0 ? _b : 0), lane: Number((_c = e.lane) !== null && _c !== void 0 ? _c : 0),
                kind: (_d = e.kind) !== null && _d !== void 0 ? _d : "pest", tier: e.tier || "spider", tick: Number((_e = e.tick) !== null && _e !== void 0 ? _e : 0),
            };
        });
        const width = Number((_c = data.width) !== null && _c !== void 0 ? _c : 7);
        const lanes = Number((_d = data.lanes) !== null && _d !== void 0 ? _d : 5);
        const tickMinutes = Number((_e = data.tickMinutes) !== null && _e !== void 0 ? _e : 60);
        const startMs = (_h = (_g = (_f = data.startAt) === null || _f === void 0 ? void 0 : _f.toMillis) === null || _g === void 0 ? void 0 : _g.call(_f)) !== null && _h !== void 0 ? _h : Date.now();
        const nowTick = Math.max(0, Math.floor((Date.now() - startMs) / (tickMinutes * 60000)));
        const sim = simulateBattle(events, width, lanes, nowTick);
        if (sim.winnerSide === null)
            return { ok: true, winnerUid: null, ongoing: true };
        const sides = (_j = data.sides) !== null && _j !== void 0 ? _j : {};
        const winnerUid = (_k = Object.keys(sides).find((u) => sides[u] === sim.winnerSide)) !== null && _k !== void 0 ? _k : null;
        tx.update(ref, {
            status: "finished", winnerUid, winTick: sim.winTick,
            resolvedAt: db_1.FieldValue.serverTimestamp(),
        });
        if (winnerUid) {
            tx.set(db_1.db.collection("profiles").doc(winnerUid), { battleWins: db_1.FieldValue.increment(1) }, { merge: true });
        }
        return { ok: true, winnerUid };
    });
    if ("err" in out) {
        res.status((_c = out.code) !== null && _c !== void 0 ? _c : 400).json({ error: out.err });
        return;
    }
    res.status(200).json(out);
});
//# sourceMappingURL=social.js.map