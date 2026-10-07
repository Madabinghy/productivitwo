"use strict";
// Intervention = objet natif (brief « Projets opérationnel » 2026-10, § 2.2) :
// une séance datée (cours, journée client) + créneau + lieu + déroulé + bilan,
// portée par le projet (`project.interventions[]`). Ses trois tâches
// (📝 Préparer · 🎯 Séance · ✅ Clôturer) restent des ProjectTask ordinaires,
// taguées `interventionId` + `interventionRole` — Gantt, Actions, programme,
// mobile et outils MCP continuent de les voir sans rien changer.
// Logique pure (testée) ; l'accès Firestore vit dans execute.ts.
var __rest = (this && this.__rest) || function (s, e) {
    var t = {};
    for (var p in s) if (Object.prototype.hasOwnProperty.call(s, p) && e.indexOf(p) < 0)
        t[p] = s[p];
    if (s != null && typeof Object.getOwnPropertySymbols === "function")
        for (var i = 0, p = Object.getOwnPropertySymbols(s); i < p.length; i++) {
            if (e.indexOf(p[i]) < 0 && Object.prototype.propertyIsEnumerable.call(s, p[i]))
                t[p[i]] = s[p[i]];
        }
    return t;
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.isClosureTask = exports.isPrepTask = exports.isSessionTask = exports.hmFr = exports.toMin = exports.CARRY_OVER_ACTION = exports.DEFAULT_TEMPLATE = exports.ROLES = exports.PRIMARY_ROLES = void 0;
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
exports.parseTimeRanges = parseTimeRanges;
exports.slotFromRanges = slotFromRanges;
exports.parseTimeRange = parseTimeRange;
exports.netSlotMin = netSlotMin;
exports.titleHints = titleHints;
exports.detectTriplets = detectTriplets;
exports.applyTriplet = applyTriplet;
exports.attachTask = attachTask;
exports.detachAll = detachAll;
exports.mergeInterventions = mergeInterventions;
const uuid_1 = require("uuid");
/** Rôles PRINCIPAUX (un seul par intervention) ; `extra` = tâche secondaire
 *  rattachée (évaluation 🏁 le jour de la séance, tâche fusionnée en conflit…). */
exports.PRIMARY_ROLES = ["prep", "session", "closure"];
exports.ROLES = [...exports.PRIMARY_ROLES, "extra"];
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
const padHm = (h, mm) => `${h.padStart(2, "0")}:${(mm || "00").padStart(2, "0")}`;
/** Toutes les plages « 8h30–12h30 + 13h30–16h30 » d'un texte, dans l'ordre. */
function parseTimeRanges(text) {
    const out = [];
    const re = new RegExp(TIME_RE.source, "g");
    let m;
    while ((m = re.exec(text)) !== null) {
        out.push({ startTime: padHm(m[1], m[2]), endTime: padHm(m[3], m[4]) });
    }
    return out;
}
/** Créneau global d'une liste de plages : début de la première, fin de la
 *  dernière, pauses entre deux plages (ex. midi). Null sans plage. */
function slotFromRanges(ranges) {
    if (!ranges.length)
        return null;
    const sorted = [...ranges].sort((a, b) => (0, exports.toMin)(a.startTime) - (0, exports.toMin)(b.startTime));
    const breaks = [];
    for (let i = 1; i < sorted.length; i++) {
        if ((0, exports.toMin)(sorted[i].startTime) > (0, exports.toMin)(sorted[i - 1].endTime)) {
            breaks.push({ start: sorted[i - 1].endTime, end: sorted[i].startTime });
        }
    }
    return { startTime: sorted[0].startTime, endTime: sorted[sorted.length - 1].endTime, breaks };
}
/** « 13h15–15h00 » → { "13:15", "15:00" } (première plage) depuis un texte libre. */
function parseTimeRange(text) {
    var _a;
    return (_a = parseTimeRanges(text)[0]) !== null && _a !== void 0 ? _a : null;
}
/** Durée nette (minutes) hors pauses. */
function netSlotMin(slot) {
    var _a;
    const total = slotMin(slot.startTime, slot.endTime);
    const pauses = ((_a = slot.breaks) !== null && _a !== void 0 ? _a : []).reduce((n, b) => n + Math.max(0, (0, exports.toMin)(b.end) - (0, exports.toMin)(b.start)), 0);
    return Math.max(0, total - pauses);
}
const MONTHS_FR = {
    janv: 1, jan: 1, janvier: 1, fev: 2, fevr: 2, fevrier: 2, mars: 3, mar: 3, avr: 4, avril: 4, mai: 5, juin: 6,
    juil: 7, juillet: 7, aout: 8, sept: 9, sep: 9, septembre: 9, oct: 10, octobre: 10, nov: 11, novembre: 11,
    dec: 12, decembre: 12,
};
/** Repères d'un titre : « J3 » → j3 ; « 23/11 », « 15 oct » → d-m. */
function titleHints(title) {
    const t = String(title !== null && title !== void 0 ? title : "").toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "");
    const out = new Set();
    for (const m of t.matchAll(/\bj\s?(\d{1,2})\b/g))
        out.add(`j${Number(m[1])}`);
    for (const m of t.matchAll(/\b(\d{1,2})\s*\/\s*(\d{1,2})\b/g))
        out.add(`${Number(m[1])}-${Number(m[2])}`);
    for (const m of t.matchAll(/\b(\d{1,2})(?:er)?\s+([a-z]{3,9})\.?\b/g)) {
        const mo = MONTHS_FR[m[2]];
        if (mo)
            out.add(`${Number(m[1])}-${mo}`);
    }
    return out;
}
/** Repères d'un jalon : ceux de son titre + sa date. */
function sessionHints(m, date) {
    var _a;
    const h = titleHints(String((_a = m.title) !== null && _a !== void 0 ? _a : ""));
    const [, mo, d] = date.split("-").map(Number);
    h.add(`${d}-${mo}`);
    return h;
}
const sharesHint = (a, b) => [...a].some((k) => b.has(k));
const ymd = (v) => String(v !== null && v !== void 0 ? v : "").slice(0, 10);
/**
 * Repère les interventions implicites. Par `groupLabel` : chaque jalon 🎯 est
 * apparié à la 📝 et à la ✅ qui l'encadrent dans le temps (📝 : endDate la
 * plus proche avant ; ✅ : startDate la plus proche à partir du jalon), un
 * repère de titre commun (« J3 », « 15 oct ») primant sur la proximité ;
 * chaque tâche ne sert qu'une fois. Un 🏁 le jour d'un 🎯 du même groupe
 * devient une tâche secondaire (`extra`) ; un 🏁 seul n'est pas une séance.
 * Un jalon sans 📝 ni ✅ est un orphelin (ignoré sauf includeOrphans).
 */
function detectTriplets(tasks, opts = {}) {
    var _a, _b, _c, _d, _e, _f, _g, _h, _j, _k;
    const live = tasks.filter((t) => t.status !== "skipped" && !t.interventionId);
    const groups = new Map();
    for (const t of live) {
        const g = String((_a = t.groupLabel) !== null && _a !== void 0 ? _a : "").trim() || `__${t.id}`;
        groups.set(g, [...((_b = groups.get(g)) !== null && _b !== void 0 ? _b : []), t]);
    }
    const triplets = [];
    const warnings = [];
    const isFlag = (t) => lead(t, /^🏁/);
    const isTarget = (t) => (0, exports.isSessionTask)(t) && !isFlag(t);
    for (const [g, members] of groups) {
        const sessions = members.filter(isTarget).sort((a, b) => { var _a, _b; return ymd((_a = a.endDate) !== null && _a !== void 0 ? _a : a.startDate).localeCompare(ymd((_b = b.endDate) !== null && _b !== void 0 ? _b : b.startDate)); });
        const flags = members.filter(isFlag);
        const preps = members.filter(exports.isPrepTask);
        const closures = members.filter(exports.isClosureTask);
        const usedPrep = new Set(), usedClosure = new Set();
        const label = g.startsWith("__") ? "" : g;
        const picks = sessions.map((m) => { var _a, _b; return ({ m, date: ymd((_a = m.endDate) !== null && _a !== void 0 ? _a : m.startDate), hints: sessionHints(m, ymd((_b = m.endDate) !== null && _b !== void 0 ? _b : m.startDate)), prep: undefined, closure: undefined }); });
        // Passe 1 : repères de titre.
        for (const p of picks) {
            p.prep = preps.find((t) => !usedPrep.has(t.id) && sharesHint(titleHints(String(t.title)), p.hints));
            if (p.prep)
                usedPrep.add(p.prep.id);
            p.closure = closures.find((t) => !usedClosure.has(t.id) && sharesHint(titleHints(String(t.title)), p.hints));
            if (p.closure)
                usedClosure.add(p.closure.id);
        }
        // Passe 2 : proximité temporelle (📝 avant, ✅ à partir du jalon).
        for (const p of picks) {
            if (!p.prep) {
                const c = preps
                    .filter((t) => { var _a; return !usedPrep.has(t.id) && ymd((_a = t.endDate) !== null && _a !== void 0 ? _a : t.startDate) <= p.date; })
                    .sort((a, b) => { var _a, _b; return ymd((_a = b.endDate) !== null && _a !== void 0 ? _a : b.startDate).localeCompare(ymd((_b = a.endDate) !== null && _b !== void 0 ? _b : a.startDate)); })[0];
                if (c) {
                    p.prep = c;
                    usedPrep.add(c.id);
                }
            }
            if (!p.closure) {
                const c = closures
                    .filter((t) => !usedClosure.has(t.id) && ymd(t.startDate) >= p.date)
                    .sort((a, b) => ymd(a.startDate).localeCompare(ymd(b.startDate)))[0];
                if (c) {
                    p.closure = c;
                    usedClosure.add(c.id);
                }
            }
        }
        for (const p of picks) {
            const orphan = !p.prep && !p.closure;
            if (orphan && !opts.includeOrphans)
                continue;
            const extras = flags.filter((f) => { var _a; return ymd((_a = f.endDate) !== null && _a !== void 0 ? _a : f.startDate) === p.date; });
            const text = [...((_c = p.m.actions) !== null && _c !== void 0 ? _c : []).map((a) => { var _a; return String((_a = a.title) !== null && _a !== void 0 ? _a : ""); }), String((_d = p.m.title) !== null && _d !== void 0 ? _d : "")].join(" ");
            const fromTask = slotFromRanges(parseTimeRanges(text));
            const fromDesc = fromTask ? null : slotFromRanges(parseTimeRanges((_e = opts.description) !== null && _e !== void 0 ? _e : ""));
            const slot = (_f = fromTask !== null && fromTask !== void 0 ? fromTask : fromDesc) !== null && _f !== void 0 ? _f : { startTime: (_g = opts.defaultStart) !== null && _g !== void 0 ? _g : "09:00", endTime: (_h = opts.defaultEnd) !== null && _h !== void 0 ? _h : "12:00", breaks: [] };
            triplets.push({
                groupLabel: label || String(p.m.title).replace(/^(🎯|🏁)\s*/, ""),
                session: p.m, prep: p.prep, closure: p.closure, extras,
                date: p.date, startTime: slot.startTime, endTime: slot.endTime, breaks: slot.breaks,
                timeSource: fromTask ? "task" : fromDesc ? "description" : "default",
                orphan,
            });
        }
        for (const t of preps)
            if (!usedPrep.has(t.id))
                warnings.push({ kind: "unpaired_prep", text: `📝 sans jalon apparié : « ${t.title} » (${ymd(t.startDate)} → ${ymd((_j = t.endDate) !== null && _j !== void 0 ? _j : t.startDate)}, groupe « ${label || "—"} »)` });
        for (const t of closures)
            if (!usedClosure.has(t.id))
                warnings.push({ kind: "unpaired_closure", text: `✅ sans jalon apparié : « ${t.title} » (${ymd(t.startDate)}, groupe « ${label || "—"} »)` });
    }
    triplets.sort((a, b) => a.date.localeCompare(b.date));
    const byDay = new Map();
    for (const t of triplets)
        byDay.set(t.date, ((_k = byDay.get(t.date)) !== null && _k !== void 0 ? _k : 0) + 1);
    for (const [d, n] of byDay)
        if (n > 1)
            warnings.push({ kind: "same_day", text: `${n} interventions le ${d} dans ce projet — vérifie (update_intervention mergeFrom pour fusionner)` });
    return { triplets, warnings };
}
/** Applique une détection : crée l'intervention et tague ses tâches. */
function applyTriplet(tasks, t) {
    var _a, _b;
    const intervention = buildIntervention({
        title: t.groupLabel, date: t.date, startTime: t.startTime, endTime: t.endTime,
    });
    if (t.breaks.length)
        intervention.breaks = t.breaks;
    const tag = (task, role) => task ? Object.assign(Object.assign({}, task), { interventionId: intervention.id, interventionRole: role }) : undefined;
    const map = new Map();
    const pairs = [[t.session, "session"], [t.prep, "prep"], [t.closure, "closure"], ...t.extras.map((e) => [e, "extra"])];
    for (const [task, role] of pairs) {
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
// ── Rattachement manuel, suppression, fusion ─────────────────────────────────
/**
 * Rattache une tâche à une intervention (ou la détache : interventionId "").
 * Un rôle principal n'est porté que par une tâche : conflit = erreur nommant
 * la tâche en place. Ne touche ni statut, ni dates, ni actions.
 */
function attachTask(tasks, interventions, taskId, interventionId, role) {
    const idx = tasks.findIndex((t) => t.id === taskId);
    if (idx < 0)
        throw new Error(`Tâche introuvable : ${taskId}`);
    if (!interventionId) {
        const out = tasks.slice();
        const _a = out[idx], { interventionId: _i, interventionRole: _r } = _a, rest = __rest(_a, ["interventionId", "interventionRole"]);
        out[idx] = rest;
        return { tasks: out, note: "détachée de son intervention" };
    }
    const target = interventions.find((i) => i.id === interventionId);
    if (!target)
        throw new Error(`Intervention introuvable dans ce projet : ${interventionId}`);
    if (!role || !exports.ROLES.includes(role)) {
        throw new Error(`interventionRole requis : ${exports.ROLES.join(" | ")}`);
    }
    if (exports.PRIMARY_ROLES.includes(role)) {
        const holder = tasks.find((t) => t.id !== taskId && t.interventionId === interventionId && t.interventionRole === role);
        if (holder) {
            throw new Error(`Le rôle ${role} de « ${target.title} » est déjà tenu par « ${holder.title} » (${holder.id}) — détache-la d'abord ou utilise le rôle extra.`);
        }
    }
    const out = tasks.slice();
    out[idx] = Object.assign(Object.assign({}, out[idx]), { interventionId, interventionRole: role });
    return { tasks: out, note: `rattachée à « ${target.title} » (${role})` };
}
/** Détache toutes les tâches d'une intervention (statut, dates, actions intacts). */
function detachAll(tasks, interventionId) {
    const touched = [];
    const out = tasks.map((t) => {
        if (t.interventionId !== interventionId)
            return t;
        touched.push(t);
        const { interventionId: _i, interventionRole: _r } = t, rest = __rest(t, ["interventionId", "interventionRole"]);
        return rest;
    });
    return { tasks: out, touched };
}
/**
 * Fusion : les tâches de `from` passent sur `target` ; un rôle principal déjà
 * tenu → la tâche entrante devient `extra` ; bilans concaténés ; `from`
 * retirée. Retourne l'état et le détail des rôles attribués.
 */
function mergeInterventions(tasks, interventions, targetId, fromId) {
    var _a, _b, _c;
    if (targetId === fromId)
        throw new Error("mergeFrom doit désigner une autre intervention");
    const target = interventions.find((i) => i.id === targetId);
    const from = interventions.find((i) => i.id === fromId);
    if (!target)
        throw new Error(`Intervention introuvable : ${targetId}`);
    if (!from)
        throw new Error(`Intervention à fusionner introuvable : ${fromId}`);
    const held = new Set(tasks.filter((t) => t.interventionId === targetId).map((t) => String(t.interventionRole)));
    const moved = [];
    const out = tasks.map((t) => {
        var _a;
        if (t.interventionId !== fromId)
            return t;
        const wanted = String((_a = t.interventionRole) !== null && _a !== void 0 ? _a : "extra");
        const demoted = exports.PRIMARY_ROLES.includes(wanted) && held.has(wanted);
        const role = demoted ? "extra" : wanted;
        if (exports.PRIMARY_ROLES.includes(role))
            held.add(role);
        const nt = Object.assign(Object.assign({}, t), { interventionId: targetId, interventionRole: role });
        moved.push({ task: nt, role, demoted });
        return nt;
    });
    const text = [target.debriefText, from.debriefText].filter((x) => typeof x === "string" && x.trim()).join("\n\n");
    const carry = [...((_a = target.carryOver) !== null && _a !== void 0 ? _a : []), ...((_b = from.carryOver) !== null && _b !== void 0 ? _b : [])];
    const mergedTarget = Object.assign(Object.assign(Object.assign({}, target), { debriefText: text || null, carryOver: carry }), (target.debriefAt || from.debriefAt ? { debriefAt: (_c = target.debriefAt) !== null && _c !== void 0 ? _c : from.debriefAt } : {}));
    const nextInterventions = interventions.filter((i) => i.id !== fromId).map((i) => (i.id === targetId ? mergedTarget : i));
    return { tasks: out, interventions: nextInterventions, moved };
}
//# sourceMappingURL=interventions.js.map