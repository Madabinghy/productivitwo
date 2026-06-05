"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.recomputeLeaderboards = exports.claimPseudo = void 0;
// ── Couche sociale (Phase 1) : pseudos + classement XP global ────────────────
// claimPseudo (réservation unique + opt-in) · recomputeLeaderboards (cron).
// L'XP de classement est RECALCULÉ CÔTÉ SERVEUR depuis les données réelles de
// l'utilisateur (anti-triche) — miroir de app_logic.actionXp/xpForDay.
const https_1 = require("firebase-functions/v2/https");
const scheduler_1 = require("firebase-functions/v2/scheduler");
const admin = require("firebase-admin");
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
//# sourceMappingURL=social.js.map