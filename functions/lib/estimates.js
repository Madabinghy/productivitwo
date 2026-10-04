"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.MAX_SESSION_MIN = void 0;
exports.sessionMinutes = sessionMinutes;
exports.spentMaps = spentMaps;
exports.timeEntries = timeEntries;
exports.median = median;
exports.roundFactor = roundFactor;
exports.measured = measured;
exports.calibrate = calibrate;
exports.overBudget = overBudget;
exports.workedUnestimated = workedUnestimated;
exports.fmtMin = fmtMin;
exports.fmtFactor = fmtFactor;
exports.refLabel = refLabel;
exports.adviceLine = adviceLine;
exports.calibrationHeadline = calibrationHeadline;
/** Estimé vs réel — logique pure, testée.
 *  Le temps réel d'une action = somme des sessions de chrono CIBLÉES sur elle
 *  (`Session.actionId`) ; d'une tâche = sessions portant son `taskId`. Les
 *  blocs du programme ne comptent pas (temps prévu, pas mesuré). Une session
 *  encore ouverte ou de plus de 12 h (chrono oublié) est ignorée. */
const contexts_1 = require("./contexts");
exports.MAX_SESSION_MIN = 12 * 60;
function toMs(v) {
    if (typeof v === "string") {
        const t = Date.parse(v);
        return Number.isNaN(t) ? null : t;
    }
    if (v && typeof v === "object" && typeof v.toDate === "function") {
        return (v.toDate()).getTime();
    }
    return null;
}
/** Minutes d'une session fermée ; 0 si ouverte, invalide ou > 12 h. */
function sessionMinutes(s) {
    const a = toMs(s.startAt), b = toMs(s.endAt);
    if (a === null || b === null || b <= a)
        return 0;
    const min = Math.round((b - a) / 60000);
    return min > exports.MAX_SESSION_MIN ? 0 : min;
}
function spentMaps(sessions) {
    var _a, _b;
    const byAction = new Map();
    const byTask = new Map();
    for (const s of sessions) {
        const m = sessionMinutes(s);
        if (m <= 0)
            continue;
        if (typeof s.actionId === "string" && s.actionId) {
            byAction.set(s.actionId, ((_a = byAction.get(s.actionId)) !== null && _a !== void 0 ? _a : 0) + m);
        }
        if (typeof s.taskId === "string" && s.taskId) {
            byTask.set(s.taskId, ((_b = byTask.get(s.taskId)) !== null && _b !== void 0 ? _b : 0) + m);
        }
    }
    return { byAction, byTask };
}
function estimate(v) {
    return typeof v === "number" && Number.isFinite(v) && v > 0 ? Math.round(v) : null;
}
const arr = (v) => (Array.isArray(v) ? v : []);
/** Toutes les actions (projets + activités) et tâches, avec estimé et réel. */
function timeEntries(projects, activities, sessions) {
    var _a, _b, _c, _d, _e, _f, _g, _h, _j, _k, _l, _m, _o, _p, _q;
    const { byAction, byTask } = spentMaps(sessions);
    const out = [];
    for (const p of projects) {
        if (p.status === "deleted")
            continue;
        const pid = String((_a = p.id) !== null && _a !== void 0 ? _a : "");
        for (const t of arr(p.tasks)) {
            const tid = String((_b = t.id) !== null && _b !== void 0 ? _b : "");
            if (t.isMilestone === true)
                continue;
            for (const a of arr(t.actions)) {
                const aid = String((_c = a.id) !== null && _c !== void 0 ? _c : "");
                out.push({
                    ref: { kind: "project", projectId: pid, taskId: tid, actionId: aid },
                    title: String((_d = a.title) !== null && _d !== void 0 ? _d : ""),
                    holder: `${(_e = p.title) !== null && _e !== void 0 ? _e : pid} › ${(_f = t.title) !== null && _f !== void 0 ? _f : tid}`,
                    contexts: (0, contexts_1.contextsOf)(a),
                    estimatedMin: estimate(a.estimatedMin),
                    spentMin: (_g = byAction.get(aid)) !== null && _g !== void 0 ? _g : 0,
                    done: a.done === true,
                    doneAt: typeof a.doneAt === "string" ? a.doneAt : null,
                });
            }
            out.push({
                ref: { kind: "task", projectId: pid, taskId: tid },
                title: String((_h = t.title) !== null && _h !== void 0 ? _h : ""),
                holder: String((_j = p.title) !== null && _j !== void 0 ? _j : pid),
                contexts: [],
                estimatedMin: estimate(t.estimatedMin),
                spentMin: (_k = byTask.get(tid)) !== null && _k !== void 0 ? _k : 0,
                done: t.status === "done",
                doneAt: typeof t.doneAt === "string" ? t.doneAt : null,
            });
        }
    }
    for (const act of activities) {
        if (act.deleted === true)
            continue;
        const actId = String((_l = act.id) !== null && _l !== void 0 ? _l : "");
        for (const a of arr(act.ownActions)) {
            const aid = String((_m = a.id) !== null && _m !== void 0 ? _m : "");
            out.push({
                ref: { kind: "activity", activityId: actId, actionId: aid },
                title: String((_o = a.title) !== null && _o !== void 0 ? _o : ""),
                holder: `activité ${(_p = act.name) !== null && _p !== void 0 ? _p : actId}`,
                contexts: (0, contexts_1.contextsOf)(a),
                estimatedMin: estimate(a.estimatedMin),
                spentMin: (_q = byAction.get(aid)) !== null && _q !== void 0 ? _q : 0,
                done: a.done === true,
                doneAt: typeof a.doneAt === "string" ? a.doneAt : null,
            });
        }
    }
    return out;
}
function median(xs) {
    if (xs.length === 0)
        return null;
    const s = [...xs].sort((a, b) => a - b);
    const m = Math.floor(s.length / 2);
    return s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2;
}
/** Facteur réel / estimé arrondi au 0,05, borné [0,25 ; 4]. */
function roundFactor(r) {
    const c = Math.min(4, Math.max(0.25, r));
    return Math.round(c * 20) / 20;
}
/** Mesurées = terminées, estimées et chronométrées (actions seulement). */
function measured(entries, sinceMs = null) {
    return entries.filter((e) => e.ref.kind !== "task" && e.done && e.estimatedMin !== null && e.spentMin > 0 &&
        (sinceMs === null || e.doneAt === null || (Date.parse(e.doneAt) || 0) >= sinceMs));
}
function calibrate(measuredEntries, minGroup = 3) {
    const ratios = measuredEntries.map((e) => e.spentMin / e.estimatedMin);
    const f = median(ratios);
    const group = (keyOf) => {
        var _a;
        const g = new Map();
        for (const e of measuredEntries) {
            for (const k of keyOf(e)) {
                const l = (_a = g.get(k)) !== null && _a !== void 0 ? _a : [];
                l.push(e.spentMin / e.estimatedMin);
                g.set(k, l);
            }
        }
        return [...g.entries()]
            .filter(([, l]) => l.length >= minGroup)
            .map(([k, l]) => ({ key: k, n: l.length, factor: roundFactor(median(l)) }))
            .sort((a, b) => b.n - a.n);
    };
    return {
        n: ratios.length,
        factor: f === null ? null : roundFactor(f),
        accurate: ratios.filter((r) => Math.abs(r - 1) <= 0.25).length,
        under: ratios.filter((r) => r > 1.25).length,
        over: ratios.filter((r) => r < 0.8).length,
        byContext: group((e) => e.contexts).map((x) => ({ context: x.key, n: x.n, factor: x.factor })),
        byHolder: group((e) => [e.holder]).map((x) => ({ holder: x.key, n: x.n, factor: x.factor })),
    };
}
/** Ouvertes, estimées, et déjà au-delà de l'estimation. */
function overBudget(entries) {
    return entries
        .filter((e) => e.ref.kind !== "task" && !e.done && e.estimatedMin !== null && e.spentMin > e.estimatedMin)
        .sort((a, b) => b.spentMin / b.estimatedMin - a.spentMin / a.estimatedMin);
}
/** Ouvertes, déjà travaillées, sans estimation : à estimer en priorité. */
function workedUnestimated(entries) {
    return entries
        .filter((e) => e.ref.kind !== "task" && !e.done && e.estimatedMin === null && e.spentMin > 0)
        .sort((a, b) => b.spentMin - a.spentMin);
}
// ── Rendu texte ──────────────────────────────────────────────────────────────
function fmtMin(m) {
    if (m < 60)
        return `${m} min`;
    const h = Math.floor(m / 60), r = m % 60;
    return r === 0 ? `${h} h` : `${h} h ${String(r).padStart(2, "0")}`;
}
function fmtFactor(f) {
    return `×${f.toFixed(2).replace(/0$/, "").replace(".", ",")}`;
}
function refLabel(r) {
    switch (r.kind) {
        case "project": return `projectId=${r.projectId} taskId=${r.taskId} actionId=${r.actionId}`;
        case "activity": return `activityId=${r.activityId} actionId=${r.actionId}`;
        case "task": return `projectId=${r.projectId} taskId=${r.taskId}`;
    }
}
function adviceLine(c) {
    if (c.factor === null)
        return "Pas encore de mesure : estime au jugé et lance le chrono ciblé sur l'action pour mesurer.";
    if (c.n < 3)
        return `Seulement ${c.n} mesure(s) : facteur ${fmtFactor(c.factor)} indicatif, pas encore fiable.`;
    if (c.factor >= 1.15)
        return `Tu sous-estimes : multiplie ta première intuition par ~${fmtFactor(c.factor).slice(1)}.`;
    if (c.factor <= 0.85)
        return `Tu surestimes : réduis ta première intuition (facteur ~${fmtFactor(c.factor).slice(1)}).`;
    return `Tes estimations sont justes (facteur ${fmtFactor(c.factor)}) : garde-les telles quelles.`;
}
function calibrationHeadline(c) {
    if (c.n === 0)
        return "Aucune action terminée, estimée et chronométrée sur la période.";
    return `${c.n} action(s) mesurée(s) · réel/estimé médian ${fmtFactor(c.factor)} · ` +
        `${c.accurate} juste(s) à ±25 % · ${c.under} sous-estimée(s) · ${c.over} surestimée(s)`;
}
//# sourceMappingURL=estimates.js.map