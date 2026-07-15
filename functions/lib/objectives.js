"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.summarizeObjectives = summarizeObjectives;
const weekly_report_1 = require("./weekly_report");
function parisDayOf(v) {
    try {
        let d = null;
        if (v instanceof Date)
            d = v;
        else if (typeof v === "string")
            d = new Date(v);
        else if (v && typeof v.toDate === "function") {
            d = v.toDate();
        }
        if (!d || isNaN(d.getTime()))
            return null;
        return d.toLocaleDateString("sv-SE", { timeZone: "Europe/Paris" });
    }
    catch (_a) {
        return null;
    }
}
/** Cible hebdo équivalente d'une routine (habitFreq stocké en index Dart :
 *  0 = daily, 1 = weekly, 2 = monthly ; tolère aussi les libellés). */
function weeklyRoutineTarget(habitFreq, habitTarget) {
    const target = Math.max(1, Math.round(Number(habitTarget) || 1));
    const freq = typeof habitFreq === "string" ? habitFreq
        : habitFreq === 0 ? "daily" : habitFreq === 1 ? "weekly" : "monthly";
    if (freq === "daily")
        return target * 7;
    if (freq === "weekly")
        return target;
    return Math.max(1, Math.round((target * 7) / 30)); // monthly
}
/**
 * Résume les objectifs actifs avec leur progression hebdo, à partir de
 * snapshots déjà fetchés (sessions/habitHits des 7 derniers jours suffisent :
 * lundi ⊂ fenêtre 7 jours — zéro lecture Firestore supplémentaire).
 */
function summarizeObjectives(objectives, activities, sessions, habitHits, todayStr) {
    const monday = (0, weekly_report_1.mondayOf)(todayStr);
    const weekday = ((new Date(`${todayStr}T12:00:00Z`).getUTCDay() + 6) % 7) + 1; // 1 = lundi … 7 = dimanche
    const prorate = (weekday / 7) * 0.7;
    const activityById = new Map();
    for (const a of activities)
        activityById.set(String(a.id), a);
    // Minutes loggées depuis lundi, par activité
    const minSinceMonday = new Map();
    for (const s of sessions) {
        if (!s.endAt)
            continue;
        const day = parisDayOf(s.startAt);
        if (!day || day < monday)
            continue;
        const start = new Date(String(s.startAt));
        const end = new Date(String(s.endAt));
        const mins = Math.round((end.getTime() - start.getTime()) / 60000);
        if (mins > 0) {
            const id = String(s.activityId);
            minSinceMonday.set(id, (minSinceMonday.get(id) || 0) + mins);
        }
    }
    // Hits de routine depuis lundi, par routine
    const hitsSinceMonday = new Map();
    for (const h of habitHits) {
        const day = parisDayOf(h.ts);
        if (!day || day < monday)
            continue;
        const id = String(h.habitId);
        hitsSinceMonday.set(id, (hitsSinceMonday.get(id) || 0) + 1);
    }
    return objectives.map((o) => {
        var _a, _b, _c, _d, _e, _f;
        const commitments = [];
        const pcts = [];
        const timeCommitments = Array.isArray(o.timeCommitments) ? o.timeCommitments : [];
        for (const c of timeCommitments) {
            const activityId = String((_a = c.activityId) !== null && _a !== void 0 ? _a : "");
            const weeklyMin = Math.max(1, Math.round(Number(c.weeklyMin) || 1));
            const a = activityById.get(activityId);
            const done = minSinceMonday.get(activityId) || 0;
            pcts.push(Math.min(done / weeklyMin, 1));
            commitments.push({
                type: "time",
                activityId,
                name: String((_b = a === null || a === void 0 ? void 0 : a.name) !== null && _b !== void 0 ? _b : activityId),
                weeklyMin,
                weekDone: done,
                onTrack: done >= weeklyMin * prorate,
            });
        }
        const routineCommitments = Array.isArray(o.routineCommitments) ? o.routineCommitments : [];
        for (const c of routineCommitments) {
            const activityId = String((_c = c.activityId) !== null && _c !== void 0 ? _c : "");
            const a = activityById.get(activityId);
            const weeklyTarget = weeklyRoutineTarget(a === null || a === void 0 ? void 0 : a.habitFreq, a === null || a === void 0 ? void 0 : a.habitTarget);
            const done = hitsSinceMonday.get(activityId) || 0;
            pcts.push(Math.min(done / weeklyTarget, 1));
            commitments.push({
                type: "routine",
                activityId,
                name: String((_d = a === null || a === void 0 ? void 0 : a.name) !== null && _d !== void 0 ? _d : activityId),
                weeklyTarget,
                weekDone: done,
                onTrack: done >= weeklyTarget * prorate,
            });
        }
        const endDate = typeof o.endDate === "string" ? o.endDate : null;
        let daysLeft = null;
        if (endDate) {
            daysLeft = Math.round((new Date(`${endDate}T12:00:00Z`).getTime() -
                new Date(`${todayStr}T12:00:00Z`).getTime()) / 86400000);
        }
        return {
            id: String((_e = o.id) !== null && _e !== void 0 ? _e : ""),
            title: String((_f = o.title) !== null && _f !== void 0 ? _f : ""),
            kpiTarget: typeof o.kpiTarget === "string" ? o.kpiTarget : null,
            horizonLabel: typeof o.horizonLabel === "string" ? o.horizonLabel : null,
            endDate,
            daysLeft,
            weekPercent: pcts.length > 0
                ? Math.round((pcts.reduce((s, p) => s + p, 0) / pcts.length) * 100)
                : null,
            commitments,
        };
    });
}
//# sourceMappingURL=objectives.js.map