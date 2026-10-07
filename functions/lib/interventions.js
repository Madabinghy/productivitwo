"use strict";
// Intervention = objet natif (brief « Projets opérationnel » 2026-10, § 2.2) :
// une séance datée (cours, journée client) + créneau + lieu + déroulé + bilan,
// portée par le projet (`project.interventions[]`). Ses trois tâches
// (📝 Préparer · 🎯 Séance · ✅ Clôturer) restent des ProjectTask ordinaires,
// taguées `interventionId` + `interventionRole` — Gantt, Actions, programme,
// mobile et outils MCP continuent de les voir sans rien changer.
// Logique pure (testée) ; l'accès Firestore vit dans execute.ts.
Object.defineProperty(exports, "__esModule", { value: true });
exports.isClosureTask = exports.isPrepTask = exports.isSessionTask = exports.hmFr = exports.toMin = exports.CARRY_OVER_ACTION = exports.DEFAULT_TEMPLATE = void 0;
exports.addDays = addDays;
exports.dayLabelFr = dayLabelFr;
exports.slotMin = slotMin;
exports.validateInput = validateInput;
exports.phaseForDate = phaseForDate;
exports.buildIntervention = buildIntervention;
exports.buildInterventionTasks = buildInterventionTasks;
exports.shiftTasks = shiftTasks;
exports.retitleTasks = retitleTasks;
exports.applyCarryOver = applyCarryOver;
exports.parseTimeRange = parseTimeRange;
exports.detectTriplets = detectTriplets;
exports.applyTriplet = applyTriplet;
const uuid_1 = require("uuid");
exports.DEFAULT_TEMPLATE = {
    id: "default",
    name: "Séance (défaut)",
    prep: {
        daysBefore: 7,
        endDaysBefore: 1,
        actions: [
            { title: "Adapter au bilan précédent", contexts: ["@ordinateur"], estimatedMin: 15 },
            { title: "Produire les supports", contexts: ["@ordinateur"], estimatedMin: 45 },
            { title: "Fiche de séquence", contexts: ["@ordinateur"], estimatedMin: 15 },
            { title: "Imprimer", contexts: ["@impression"], estimatedMin: 10 },
        ],
    },
    closure: {
        daysAfter: 2,
        actions: [
            { title: "Remplir la fiche de séquence (réalisé + bilan)", contexts: ["@ordinateur"], estimatedMin: 15 },
            { title: "Noter le report (ce qui n'a pas été fait)", contexts: ["@ordinateur"], estimatedMin: 5 },
            { title: "Déposer les documents", contexts: ["@ordinateur"], estimatedMin: 10 },
        ],
    },
};
exports.CARRY_OVER_ACTION = /adapter au bilan/i;
const DAYS = ["Dim", "Lun", "Mar", "Mer", "Jeu", "Ven", "Sam"];
const MONTHS = ["janv.", "févr.", "mars", "avr.", "mai", "juin", "juil.", "août", "sept.", "oct.", "nov.", "déc."];
const toMin = (hm) => {
    const m = /^(\d{1,2}):(\d{2})$/.exec(hm);
    return m ? Number(m[1]) * 60 + Number(m[2]) : NaN;
};
exports.toMin = toMin;
const hmFr = (hm) => {
    const m = /^(\d{1,2}):(\d{2})$/.exec(hm);
    return m ? `${Number(m[1])}h${m[2]}` : hm;
};
exports.hmFr = hmFr;
function addDays(ymd, n) {
    const d = new Date(`${ymd}T00:00:00Z`);
    d.setUTCDate(d.getUTCDate() + n);
    return d.toISOString().slice(0, 10);
}
function dayLabelFr(ymd) {
    const d = new Date(`${ymd}T00:00:00Z`);
    return `${DAYS[d.getUTCDay()]} ${d.getUTCDate()} ${MONTHS[d.getUTCMonth()]}`;
}
function slotMin(startTime, endTime) {
    const a = (0, exports.toMin)(startTime), b = (0, exports.toMin)(endTime);
    return Number.isFinite(a) && Number.isFinite(b) && b > a ? b - a : 0;
}
function validateInput(i) {
    var _a;
    if (!((_a = i.title) === null || _a === void 0 ? void 0 : _a.trim()))
        return "title requis";
    if (!/^\d{4}-\d{2}-\d{2}$/.test(i.date))
        return `date invalide : ${i.date} (YYYY-MM-DD)`;
    if (!Number.isFinite((0, exports.toMin)(i.startTime)))
        return `startTime invalide : ${i.startTime} (HH:mm)`;
    if (!Number.isFinite((0, exports.toMin)(i.endTime)))
        return `endTime invalide : ${i.endTime} (HH:mm)`;
    if (slotMin(i.startTime, i.endTime) <= 0)
        return "endTime doit être après startTime";
    return null;
}
/** Phase dont la plage contient la date ; la plus courte si plusieurs. */
function phaseForDate(phases, ymd) {
    const hits = phases
        .filter((p) => { var _a, _b; return String((_a = p.startDate) !== null && _a !== void 0 ? _a : "").slice(0, 10) <= ymd && ymd <= String((_b = p.endDate) !== null && _b !== void 0 ? _b : "").slice(0, 10); })
        .sort((a, b) => (String(a.endDate).localeCompare(String(a.startDate))) - (String(b.endDate).localeCompare(String(b.startDate))));
    return hits[0] ? String(hits[0].id) : undefined;
}
const nowIso = () => new Date().toISOString();
function action(a) {
    var _a;
    const ctx = ((_a = a.contexts) !== null && _a !== void 0 ? _a : []).filter((c) => typeof c === "string" && c.trim());
    return Object.assign(Object.assign(Object.assign({ id: (0, uuid_1.v4)(), title: a.title, done: false, doneAt: null, createdAt: nowIso() }, (ctx.length ? { contexts: ctx, context: ctx[0] } : {})), (typeof a.estimatedMin === "number" ? { estimatedMin: a.estimatedMin } : {})), { checklist: [] });
}
const sumMin = (as) => as.reduce((n, a) => n + (typeof a.estimatedMin === "number" ? a.estimatedMin : 0), 0);
/** Le document `interventions[]` stocké dans le projet. */
function buildIntervention(i) {
    var _a, _b, _c, _d;
    return {
        id: (_a = i.id) !== null && _a !== void 0 ? _a : (0, uuid_1.v4)(),
        title: i.title.trim(),
        date: i.date,
        startTime: i.startTime,
        endTime: i.endTime,
        place: (_b = i.place) !== null && _b !== void 0 ? _b : null,
        templateId: (_c = i.templateId) !== null && _c !== void 0 ? _c : null,
        docUrl: (_d = i.docUrl) !== null && _d !== void 0 ? _d : null,
        status: "planned",
        debriefText: null,
        carryOver: [],
        debriefAt: null,
        createdAt: nowIso(),
    };
}
/** Les trois tâches d'une intervention, prêtes à être ajoutées au projet. */
function buildInterventionTasks(intervention, tpl, opts = {}) {
    var _a, _b, _c, _d;
    const id = String(intervention.id);
    const title = String(intervention.title);
    const date = String(intervention.date);
    const start = String(intervention.startTime), end = String(intervention.endTime);
    const phaseId = phaseForDate((_a = opts.phases) !== null && _a !== void 0 ? _a : [], date);
    const base = Object.assign(Object.assign({ groupLabel: title }, (phaseId ? { phaseId } : {})), { interventionId: id, color: null, barLabel: null, todayFlag: false });
    const prepActions = (_b = opts.prepActions) !== null && _b !== void 0 ? _b : tpl.prep.actions;
    const closureActions = (_c = opts.closureActions) !== null && _c !== void 0 ? _c : tpl.closure.actions;
    const steps = ((_d = opts.steps) !== null && _d !== void 0 ? _d : []).filter((s) => s.trim());
    const sessionCtx = tpl.sessionContext ? [tpl.sessionContext] : [];
    return {
        prep: Object.assign(Object.assign({}, base), { id: (0, uuid_1.v4)(), title: `📝 Préparer — ${title}`, startDate: addDays(date, -Math.max(1, tpl.prep.daysBefore)), endDate: addDays(date, -Math.max(0, tpl.prep.endDaysBefore)), isMilestone: false, status: "pending", interventionRole: "prep", actions: prepActions.map(action), estimatedMin: sumMin(prepActions) || null }),
        session: Object.assign(Object.assign({}, base), { id: (0, uuid_1.v4)(), title: `🎯 ${dayLabelFr(date)} — ${title}`, startDate: date, endDate: date, isMilestone: true, barLabel: "SÉANCE", status: "pending", interventionRole: "session", actions: [Object.assign(Object.assign({}, action({ title: `Dérouler la séance (${(0, exports.hmFr)(start)}–${(0, exports.hmFr)(end)})`, contexts: sessionCtx, estimatedMin: slotMin(start, end) })), { checklist: steps.map((s) => ({ id: (0, uuid_1.v4)(), title: s, done: false, doneAt: null })) })], estimatedMin: null }),
        closure: Object.assign(Object.assign({}, base), { id: (0, uuid_1.v4)(), title: `✅ Clôturer — ${title}`, startDate: date, endDate: addDays(date, Math.max(0, tpl.closure.daysAfter)), isMilestone: false, status: "pending", interventionRole: "closure", actions: closureActions.map(action), estimatedMin: sumMin(closureActions) || null }),
    };
}
/** Déplace les tâches d'une intervention quand sa date change (même écart). */
function shiftTasks(tasks, interventionId, fromDate, toDate) {
    const delta = Math.round((Date.parse(`${toDate}T00:00:00Z`) - Date.parse(`${fromDate}T00:00:00Z`)) / 86400000);
    if (!delta)
        return tasks;
    const shift = (v) => (typeof v === "string" && v ? addDays(v.slice(0, 10), delta) : v);
    return tasks.map((t) => t.interventionId === interventionId
        ? Object.assign(Object.assign({}, t), { startDate: shift(t.startDate), endDate: shift(t.endDate) }) : t);
}
/** Retitre le jalon quand la date ou le titre change. */
function retitleTasks(tasks, intervention) {
    const id = String(intervention.id), title = String(intervention.title), date = String(intervention.date);
    return tasks.map((t) => {
        if (t.interventionId !== id)
            return t;
        const out = Object.assign(Object.assign({}, t), { groupLabel: title });
        if (t.interventionRole === "prep")
            out.title = `📝 Préparer — ${title}`;
        if (t.interventionRole === "session")
            out.title = `🎯 ${dayLabelFr(date)} — ${title}`;
        if (t.interventionRole === "closure")
            out.title = `✅ Clôturer — ${title}`;
        return out;
    });
}
/**
 * Bilan N → prépa N+1 : les points « à reprendre » deviennent la checklist de
 * l'action « Adapter au bilan précédent » de la prochaine intervention (créée
 * si absente). Les items déjà présents (même titre) sont conservés.
 * Retourne les tâches mises à jour et l'id de l'intervention alimentée.
 */
function applyCarryOver(tasks, interventions, fromId, carryOver) {
    var _a;
    const from = interventions.find((i) => i.id === fromId);
    const items = carryOver.map((s) => s.trim()).filter(Boolean);
    if (!from || !items.length)
        return { tasks, nextId: null };
    const next = interventions
        .filter((i) => i.id !== fromId && i.status !== "cancelled" && String(i.date) > String(from.date))
        .sort((a, b) => String(a.date).localeCompare(String(b.date)))[0];
    if (!next)
        return { tasks, nextId: null };
    const idx = tasks.findIndex((t) => t.interventionId === next.id && t.interventionRole === "prep");
    if (idx < 0)
        return { tasks, nextId: null };
    const prep = Object.assign({}, tasks[idx]);
    const actions = ((_a = prep.actions) !== null && _a !== void 0 ? _a : []).slice();
    let ai = actions.findIndex((a) => exports.CARRY_OVER_ACTION.test(String(a.title)));
    if (ai < 0) {
        actions.unshift(action({ title: "Adapter au bilan précédent", contexts: ["@ordinateur"], estimatedMin: 15 }));
        ai = 0;
    }
    const a = Object.assign({}, actions[ai]);
    const list = (Array.isArray(a.checklist) ? a.checklist : []).slice();
    const have = new Set(list.map((c) => String(c.title).trim().toLowerCase()));
    for (const s of items) {
        if (!have.has(s.toLowerCase()))
            list.push({ id: (0, uuid_1.v4)(), title: s, done: false, doneAt: null });
    }
    a.checklist = list;
    if (a.done === true && list.some((c) => c.done !== true)) {
        a.done = false;
        a.doneAt = null;
    }
    actions[ai] = a;
    prep.actions = actions;
    const out = tasks.slice();
    out[idx] = prep;
    return { tasks: out, nextId: String(next.id) };
}
// ── Migration des triplets existants (convention émojis + groupLabel) ────────
const lead = (t, re) => { var _a; return re.test(String((_a = t.title) !== null && _a !== void 0 ? _a : "").trimStart()); };
const isSessionTask = (t) => t.isMilestone === true || lead(t, /^(🎯|🏁)/);
exports.isSessionTask = isSessionTask;
const isPrepTask = (t) => lead(t, /^📝/);
exports.isPrepTask = isPrepTask;
const isClosureTask = (t) => lead(t, /^✅/);
exports.isClosureTask = isClosureTask;
const TIME_RE = /(\d{1,2})\s?h\s?(\d{0,2})\s*(?:–|-|—|à)\s*(\d{1,2})\s?h\s?(\d{0,2})/;
/** « 13h15–15h00 » → { "13:15", "15:00" } depuis un texte libre. */
function parseTimeRange(text) {
    const m = TIME_RE.exec(text);
    if (!m)
        return null;
    const pad = (h, mm) => `${h.padStart(2, "0")}:${(mm || "00").padStart(2, "0")}`;
    return { startTime: pad(m[1], m[2]), endTime: pad(m[3], m[4]) };
}
/** Repère les interventions implicites : un jalon (non annulé, non déjà tagué)
 *  + sa 📝 et sa ✅ de même groupLabel. Le créneau vient de l'action du jalon,
 *  sinon de la description du projet, sinon du défaut donné. */
function detectTriplets(tasks, opts = {}) {
    var _a, _b, _c, _d, _e, _f, _g, _h;
    const out = [];
    for (const m of tasks) {
        if (m.status === "skipped" || m.interventionId || !(0, exports.isSessionTask)(m))
            continue;
        const g = String((_a = m.groupLabel) !== null && _a !== void 0 ? _a : "").trim();
        const siblings = g ? tasks.filter((t) => { var _a; return t !== m && !t.interventionId && String((_a = t.groupLabel) !== null && _a !== void 0 ? _a : "").trim() === g; }) : [];
        const fromTask = parseTimeRange([...((_b = m.actions) !== null && _b !== void 0 ? _b : []).map((a) => { var _a; return String((_a = a.title) !== null && _a !== void 0 ? _a : ""); }), String((_c = m.title) !== null && _c !== void 0 ? _c : "")].join(" "));
        const fromDesc = fromTask ? null : parseTimeRange((_d = opts.description) !== null && _d !== void 0 ? _d : "");
        const slot = (_e = fromTask !== null && fromTask !== void 0 ? fromTask : fromDesc) !== null && _e !== void 0 ? _e : { startTime: (_f = opts.defaultStart) !== null && _f !== void 0 ? _f : "09:00", endTime: (_g = opts.defaultEnd) !== null && _g !== void 0 ? _g : "12:00" };
        out.push({
            groupLabel: g || String(m.title).replace(/^(🎯|🏁)\s*/, ""),
            session: m,
            prep: siblings.find((t) => t.status !== "skipped" && (0, exports.isPrepTask)(t)),
            closure: siblings.find((t) => t.status !== "skipped" && (0, exports.isClosureTask)(t)),
            date: String((_h = m.endDate) !== null && _h !== void 0 ? _h : m.startDate).slice(0, 10),
            startTime: slot.startTime,
            endTime: slot.endTime,
            timeSource: fromTask ? "task" : fromDesc ? "description" : "default",
        });
    }
    return out.sort((a, b) => a.date.localeCompare(b.date));
}
/** Applique une détection : crée l'intervention et tague les trois tâches. */
function applyTriplet(tasks, t) {
    var _a, _b;
    const intervention = buildIntervention({
        title: t.groupLabel, date: t.date, startTime: t.startTime, endTime: t.endTime,
    });
    const tag = (task, role) => task ? Object.assign(Object.assign({}, task), { interventionId: intervention.id, interventionRole: role }) : undefined;
    const map = new Map();
    for (const [task, role] of [[t.session, "session"], [t.prep, "prep"], [t.closure, "closure"]]) {
        const tagged = tag(task, role);
        if (task && tagged)
            map.set(task.id, tagged);
    }
    const done = t.session.status === "done" ||
        (((_a = t.session.actions) !== null && _a !== void 0 ? _a : []).length > 0 && ((_b = t.session.actions) !== null && _b !== void 0 ? _b : []).every((a) => a.done === true));
    if (done)
        intervention.status = "done";
    return { tasks: tasks.map((x) => { var _a; return (_a = map.get(x.id)) !== null && _a !== void 0 ? _a : x; }), intervention };
}
//# sourceMappingURL=interventions.js.map