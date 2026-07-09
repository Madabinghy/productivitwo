"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.buildDomainDossier = buildDomainDossier;
const db_1 = require("./db");
const DAY_MS = 86400000;
async function buildDomainDossier(uid, domainName) {
    var _a, _b, _c, _d, _e, _f, _g, _h, _j, _k, _l, _m, _o, _p;
    const now = new Date();
    const sinceIso = new Date(now.getTime() - 42 * DAY_MS).toISOString(); // 6 sem
    const last14 = [];
    for (let i = 1; i <= 14; i++) {
        last14.push(new Date(now.getTime() - i * DAY_MS).toISOString().slice(0, 10));
    }
    const [domainsSnap, actsSnap, sessionsSnap, artsSnap, schedSnaps] = await Promise.all([
        db_1.db.collection(`users/${uid}/domains`).get(),
        db_1.db.collection(`users/${uid}/activities`).get(),
        db_1.db.collection(`users/${uid}/sessions`).where("startAt", ">=", sinceIso).get(),
        db_1.db.collection(`users/${uid}/artifacts`).get(),
        Promise.all(last14.map((d) => db_1.db.doc(`users/${uid}/daily_schedules/${d}`).get())),
    ]);
    const domain = domainsSnap.docs
        .map((d) => d.data())
        .find((v) => {
        var _a;
        return v.deleted !== true &&
            String((_a = v.name) !== null && _a !== void 0 ? _a : "").trim().toLowerCase() ===
                domainName.trim().toLowerCase();
    });
    const domainId = domain ? String((_a = domain.id) !== null && _a !== void 0 ? _a : "") : null;
    // Activités du domaine (les 0 h comptent : c'est la matière de la
    // confrontation déclaré vs réel).
    const domainActs = new Map(); // activityId → nom
    for (const a of actsSnap.docs) {
        const data = a.data();
        if (data.deleted === true)
            continue;
        if (domainId && data.domainId === domainId) {
            domainActs.set(a.id, String((_b = data.name) !== null && _b !== void 0 ? _b : a.id));
        }
    }
    const minutesByAct = new Map();
    for (const s of sessionsSnap.docs) {
        const actId = String((_c = s.get("activityId")) !== null && _c !== void 0 ? _c : "");
        if (!domainActs.has(actId))
            continue;
        const start = new Date(String(s.get("startAt"))).getTime();
        const endRaw = s.get("endAt");
        const end = endRaw ? new Date(String(endRaw)).getTime() : start;
        minutesByAct.set(actId, ((_d = minutesByAct.get(actId)) !== null && _d !== void 0 ? _d : 0) + Math.max(0, (end - start) / 60000));
    }
    // Blocs du domaine sur 14 jours : sautés + motifs, par engagement.
    const skipStats = new Map();
    let domainBlocksSeen = 0;
    for (const snap of schedSnaps) {
        if (!snap.exists)
            continue;
        const blocks = (_e = snap.data().blocks) !== null && _e !== void 0 ? _e : [];
        for (const b of blocks) {
            if (b.status === "deleted" || b.kind === "prep" || b.category === "break")
                continue;
            if (!domainActs.has(String((_f = b.activityId) !== null && _f !== void 0 ? _f : "")))
                continue;
            domainBlocksSeen++;
            if (b.status === "done")
                continue;
            const title = String((_g = b.title) !== null && _g !== void 0 ? _g : "");
            const entry = (_h = skipStats.get(title)) !== null && _h !== void 0 ? _h : { skips: 0, causes: new Map() };
            entry.skips++;
            const cause = String((_j = b.skipReason) !== null && _j !== void 0 ? _j : "").trim();
            if (cause)
                entry.causes.set(cause, ((_k = entry.causes.get(cause)) !== null && _k !== void 0 ? _k : 0) + 1);
            skipStats.set(title, entry);
        }
    }
    const lines = [];
    let totalMinutes = 0;
    for (const [actId, name] of domainActs) {
        const min = Math.round((_l = minutesByAct.get(actId)) !== null && _l !== void 0 ? _l : 0);
        totalMinutes += min;
        const perWeek = Math.round((min / 60 / 6) * 10) / 10;
        lines.push(min > 0
            ? `  · ${name} : ${Math.round(min / 60)} h en 6 semaines (≈ ${perWeek} h/sem)`
            : `  · ${name} : 0 h en 6 semaines`);
    }
    for (const [title, s] of skipStats) {
        if (s.skips < 2)
            continue; // en dessous, pas un motif — du bruit
        let topCause = "";
        let topN = 0;
        s.causes.forEach((n, c) => {
            if (n > topN) {
                topCause = c;
                topN = n;
            }
        });
        lines.push(`  · « ${title} » : sauté ${s.skips} fois en 14 jours` +
            (topCause ? ` — ${topN} fois « ${topCause} »` : ""));
    }
    if (domainId) {
        for (const a of artsSnap.docs) {
            const data = a.data();
            if (data.deleted === true || data.domainId !== domainId)
                continue;
            lines.push(`  · Artefact existant : « ${String((_m = data.title) !== null && _m !== void 0 ? _m : data.kind)} » — À ADOPTER tel quel (le référencer), ne JAMAIS proposer de le régénérer.`);
        }
    }
    const vivant = totalMinutes > 0 || domainBlocksSeen > 0;
    if (vivant)
        return { mode: "vivant", text: lines.join("\n") };
    // ── Sans données : ce qu'on voit EN CREUX (tous domaines confondus) ─────────
    const creux = [];
    const sundays = new Set();
    const workedSundays = new Set();
    const since28 = new Date(now.getTime() - 28 * DAY_MS).toISOString();
    for (const s of sessionsSnap.docs) {
        const startAt = String((_o = s.get("startAt")) !== null && _o !== void 0 ? _o : "");
        if (startAt < since28)
            continue;
        const d = new Date(startAt);
        if (d.getDay() === 0)
            workedSundays.add(startAt.slice(0, 10));
    }
    for (let i = 1; i <= 28; i++) {
        const d = new Date(now.getTime() - i * DAY_MS);
        if (d.getDay() === 0)
            sundays.add(d.toISOString().slice(0, 10));
    }
    if (workedSundays.size > 0) {
        creux.push(`  · ${workedSundays.size} dimanche(s) sur ${sundays.size} travaillé(s) (sessions logguées) — c'est le créneau qui déborde en premier.`);
    }
    let emptyEvenings = 0;
    let daysWithSchedule = 0;
    for (const snap of schedSnaps) {
        if (!snap.exists)
            continue;
        daysWithSchedule++;
        const blocks = (_p = snap.data().blocks) !== null && _p !== void 0 ? _p : [];
        const evening = blocks.some((b) => { var _a; return b.status !== "deleted" && String((_a = b.startTime) !== null && _a !== void 0 ? _a : "") >= "19:00"; });
        if (!evening)
            emptyEvenings++;
    }
    if (daysWithSchedule >= 5 && emptyEvenings > 0) {
        creux.push(`  · Soirées vides dans l'app ${emptyEvenings} jours sur ${daysWithSchedule} — remplies de quoi, en vrai ?`);
    }
    return { mode: "vide", text: creux.join("\n") };
}
//# sourceMappingURL=domain_facts.js.map