"use strict";
// ── Jour visé (2026-10-30) — logique pure, pas d'I/O ─────────────────────────
// `focusDate` = l'intention (« je veux l'avoir sous la main ce jour-là »),
// jamais une échéance : dépassé, jamais en retard. C'est la date par défaut
// d'une action ; `dueDate` ne sert qu'aux vraies dates butoirs (séance, rendu,
// démarche). Migration des données existantes : les `dueDate` posées comme
// « quand je compte le faire » deviennent des `focusDate`, sauf dans les tâches
// de séance (📝 / 🎯 / ✅ gardent leur échéance).
Object.defineProperty(exports, "__esModule", { value: true });
exports.DATING_RULES = void 0;
exports.isInterventionTask = isInterventionTask;
exports.migrateTaskFocusDates = migrateTaskFocusDates;
exports.migrateOwnFocusDates = migrateOwnFocusDates;
exports.focusedActions = focusedActions;
exports.DATING_RULES = "DATES D'UNE ACTION : `focusDate` (YYYY-MM-DD) = le JOUR VISÉ, quand l'utilisateur veut l'avoir sous la main — " +
    "c'est la date par défaut, une intention, jamais en retard, jamais un bloc. `dueDate` = une VRAIE échéance " +
    "(séance, rendu, démarche administrative) et rien d'autre : dépassée, l'action est en retard. Quand tu " +
    "programmes « quand » faire une chose, pose focusDate ; ne pose dueDate que si une date butoir existe vraiment.";
const lead = (t, re) => typeof t.title === "string" && re.test(t.title.trim());
/** Tâche de séance (intervention native ou convention émojis) : ses actions
 *  gardent leur échéance, la date est une vraie date butoir. */
function isInterventionTask(t) {
    if (typeof t.interventionId === "string" && t.interventionId)
        return true;
    if (t.isMilestone === true)
        return true;
    return lead(t, /^(📝|🎯|🏁|✅)/);
}
/** Dans les tâches d'un projet : `dueDate` → `focusDate` pour chaque action
 *  ouverte sans jour visé, hors tâches de séance. Renvoie les tâches réécrites
 *  (copies) et un compte rendu ligne à ligne. */
function migrateTaskFocusDates(tasks, projectTitle) {
    const out = { moved: 0, skippedIntervention: 0, alreadyFocused: 0, tasks: [], lines: [] };
    for (const t of tasks) {
        const actions = Array.isArray(t.actions) ? t.actions : [];
        const intervention = isInterventionTask(t);
        const next = actions.map((raw) => {
            if (typeof raw !== "object" || raw === null)
                return raw;
            const a = raw;
            const due = typeof a.dueDate === "string" && a.dueDate ? a.dueDate : null;
            if (!due || a.done === true)
                return a;
            if (intervention) {
                out.skippedIntervention++;
                return a;
            }
            if (typeof a.focusDate === "string" && a.focusDate) {
                out.alreadyFocused++;
                return a;
            }
            out.moved++;
            out.lines.push(`  · ${projectTitle} › ${String(t.title)} › ${String(a.title)} : échéance ${due} → visée ${due}`);
            return Object.assign(Object.assign({}, a), { focusDate: due, dueDate: null });
        });
        out.tasks.push(Object.assign(Object.assign({}, t), { actions: next }));
    }
    return out;
}
/** Actions propres d'une activité : même règle, sans tâche de séance. */
function migrateOwnFocusDates(own, activityName) {
    let moved = 0;
    const lines = [];
    const next = own.map((a) => {
        const due = typeof a.dueDate === "string" && a.dueDate ? a.dueDate : null;
        if (!due || a.done === true || (typeof a.focusDate === "string" && a.focusDate))
            return a;
        moved++;
        lines.push(`  · ${activityName} › ${String(a.title)} : échéance ${due} → visée ${due}`);
        return Object.assign(Object.assign({}, a), { focusDate: due, dueDate: null });
    });
    return { moved, own: next, lines };
}
/** « Actions visées pour [ymd] » dans des projets (données brutes) : titre,
 *  projet, tâche — pour `plan_day`. Les visées AVANT [ymd] et non faites
 *  comptent aussi (à re-viser). */
function focusedActions(projects, ymd) {
    const lines = [];
    for (const p of projects) {
        if (p.status !== "active" || p.paused === true)
            continue;
        const tasks = Array.isArray(p.tasks) ? p.tasks : [];
        for (const t of tasks) {
            if (t.status === "done" || t.status === "skipped")
                continue;
            const actions = Array.isArray(t.actions) ? t.actions : [];
            for (const raw of actions) {
                if (typeof raw !== "object" || raw === null)
                    continue;
                const a = raw;
                if (a.done === true || typeof a.focusDate !== "string" || !a.focusDate)
                    continue;
                if (a.focusDate > ymd)
                    continue;
                const when = a.focusDate === ymd ? "aujourd'hui" : `visée le ${a.focusDate}, à re-viser`;
                lines.push(`  · "${String(a.title)}" — ${String(p.title)} › ${String(t.title)} (${when}${a.estimatedMin ? ` · ≈ ${a.estimatedMin} min` : ""})`);
            }
        }
    }
    return lines;
}
//# sourceMappingURL=focus_dates.js.map