"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.sendFcmPush = sendFcmPush;
exports.withBothContexts = withBothContexts;
exports.executeAddIntervention = executeAddIntervention;
exports.executeUpdateIntervention = executeUpdateIntervention;
exports.executeDeleteIntervention = executeDeleteIntervention;
exports.executePlanPrep = executePlanPrep;
exports.executeWeeklyReview = executeWeeklyReview;
exports.executeUpdateActions = executeUpdateActions;
exports.executeManageInterventionTemplates = executeManageInterventionTemplates;
exports.executeMigrateInterventions = executeMigrateInterventions;
exports.executeListSessions = executeListSessions;
exports.executeDeleteSessions = executeDeleteSessions;
exports.executeUpdateSession = executeUpdateSession;
exports.executeManageContexts = executeManageContexts;
exports.executeEstimateAccuracy = executeEstimateAccuracy;
exports.executeUpdateAction = executeUpdateAction;
exports.executePushAssistantMessage = executePushAssistantMessage;
exports.validateToken = validateToken;
exports.executeGetUserContext = executeGetUserContext;
exports.executeGetOrionContext = executeGetOrionContext;
exports.executeUpdateActivityGoal = executeUpdateActivityGoal;
exports.executeSetActivityTargets = executeSetActivityTargets;
exports.executeCreateRoutine = executeCreateRoutine;
exports.executeGetDayBlocks = executeGetDayBlocks;
exports.executeCreateActivity = executeCreateActivity;
exports.executeGetDocumentTemplate = executeGetDocumentTemplate;
exports.executeSaveDocument = executeSaveDocument;
exports.executeGetDocuments = executeGetDocuments;
exports.executeGetArchives = executeGetArchives;
exports.executeGetShoppingList = executeGetShoppingList;
exports.executeAddShoppingItem = executeAddShoppingItem;
exports.executeCheckShoppingItem = executeCheckShoppingItem;
exports.executeRestoreItem = executeRestoreItem;
exports.executeCreateDomain = executeCreateDomain;
exports.executeUpdateDomain = executeUpdateDomain;
exports.executeDeleteDomain = executeDeleteDomain;
exports.executeDeleteActivity = executeDeleteActivity;
exports.executeUpdateProject = executeUpdateProject;
exports.executeUpdateTaskStatus = executeUpdateTaskStatus;
exports.executeUpdateActivity = executeUpdateActivity;
exports.executeDeleteRoutine = executeDeleteRoutine;
exports.executeArchiveProject = executeArchiveProject;
exports.executeDeleteProject = executeDeleteProject;
exports.executeListProjects = executeListProjects;
exports.executeGetProject = executeGetProject;
exports.executePushGantt = executePushGantt;
exports.executeAddTask = executeAddTask;
exports.executeUpdateTask = executeUpdateTask;
exports.executeMarkActionDone = executeMarkActionDone;
exports.executeMarkChecklistItem = executeMarkChecklistItem;
exports.executeLinkActionToActivity = executeLinkActionToActivity;
exports.executeAddActivityAction = executeAddActivityAction;
exports.executeLogRoutineHit = executeLogRoutineHit;
exports.executeMarkBlockDone = executeMarkBlockDone;
exports.executeUpdateBlock = executeUpdateBlock;
exports.executeGetAssistantMessages = executeGetAssistantMessages;
exports.executeDeleteAssistantMessage = executeDeleteAssistantMessage;
exports.executeGetOrionQueue = executeGetOrionQueue;
exports.executeDeleteOrionQueueItem = executeDeleteOrionQueueItem;
exports.executeGetInbox = executeGetInbox;
exports.executeProcessInboxItem = executeProcessInboxItem;
exports.executeProposeChange = executeProposeChange;
exports.executeGenerateWeeklyReport = executeGenerateWeeklyReport;
exports.executeListSessionTemplates = executeListSessionTemplates;
exports.executeCreateSessionTemplate = executeCreateSessionTemplate;
exports.executeUpdateSessionTemplate = executeUpdateSessionTemplate;
exports.executeGetDaySchedule = executeGetDaySchedule;
exports.executeScheduleDay = executeScheduleDay;
exports.executeAddPrepBlock = executeAddPrepBlock;
exports.executeAddEvent = executeAddEvent;
exports.executeSaveDomainDefinition = executeSaveDomainDefinition;
exports.executeListObjectives = executeListObjectives;
exports.executeSaveObjective = executeSaveObjective;
exports.executeUpdateScheduleBlock = executeUpdateScheduleBlock;
exports.executeComputeTimeBudget = executeComputeTimeBudget;
exports.executePlanDay = executePlanDay;
exports.executePlanWeek = executePlanWeek;
exports.executeSyncCalendar = executeSyncCalendar;
exports.pickProject = pickProject;
exports.pickStrategicObjective = pickStrategicObjective;
exports.checkRateLimit = checkRateLimit;
exports.todayInParis = todayInParis;
exports.userDayParts = userDayParts;
exports.nowInParis = nowInParis;
const schedule_dedupe_1 = require("./schedule_dedupe");
const phase_resolve_1 = require("./phase_resolve");
const schedule_dedupe_2 = require("./schedule_dedupe");
const interventions_1 = require("./interventions");
const prep_planner_1 = require("./prep_planner");
const default_estimates_1 = require("./default_estimates");
const project_audit_1 = require("./project_audit");
const contexts_1 = require("./contexts");
const action_patch_1 = require("./action_patch");
const estimates_1 = require("./estimates");
const db_1 = require("./db");
const uuid_1 = require("uuid");
const sessions_audit_1 = require("./sessions_audit");
const admin = require("firebase-admin");
const crypto_1 = require("crypto");
const weekly_report_1 = require("./weekly_report");
const objectives_1 = require("./objectives");
// ── Date helpers ──────────────────────────────────────────────────────────────
/** Retourne YYYY-MM-DD dans le fuseau Europe/Paris. */
function todayInParis(d = new Date()) {
    return d.toLocaleDateString("sv-SE", { timeZone: "Europe/Paris" });
}
/** Jour + heure VÉCUS par l'utilisateur : fuseau du téléphone posé en fait par
 *  l'app (`data/meta.tzOffsetMin`, minutes à ajouter à l'UTC — ex : -240 pour
 *  la Guadeloupe). Fallback Europe/Paris (comportement historique) tant que le
 *  fait n'existe pas. Tout le serveur (agenda, proposition, ORION) doit passer
 *  par ici — jamais de « Paris » en dur pour un raisonnement utilisateur. */
function userDayParts(offsetMin, d = new Date()) {
    if (typeof offsetMin === "number" && isFinite(offsetMin)) {
        const t = new Date(d.getTime() + offsetMin * 60000);
        const iso = t.toISOString();
        return { ymd: iso.slice(0, 10), hm: iso.slice(11, 16) };
    }
    return {
        ymd: todayInParis(d),
        hm: d.toLocaleTimeString("fr-FR", {
            timeZone: "Europe/Paris", hour: "2-digit", minute: "2-digit", hour12: false,
        }),
    };
}
/** Heure actuelle dans le fuseau Europe/Paris. */
function nowInParis() {
    const hm = new Date().toLocaleTimeString("fr-FR", {
        timeZone: "Europe/Paris", hour: "2-digit", minute: "2-digit", hour12: false,
    });
    const [hour, minute] = hm.split(":").map(Number);
    return { hm, hour, minute };
}
/** Prochain quart d'heure ≥ maintenant (Paris), format HH:mm — plancher de
 *  planification pour la date du jour (on ne planifie jamais le passé). */
function nextQuarterHour() {
    const { hour, minute } = nowInParis();
    const q = Math.ceil(minute / 15) * 15;
    const h = q === 60 ? hour + 1 : hour;
    const m = q === 60 ? 0 : q;
    const pad = (n) => String(n).padStart(2, "0");
    return `${pad(Math.min(h, 23))}:${pad(m)}`;
}
// ── Rate limiting ─────────────────────────────────────────────────────────────
const HOUR_MS = 60 * 60 * 1000;
async function checkRateLimit(uid, key, maxPerHour) {
    var _a, _b;
    const ref = db_1.db.doc(`users/${uid}/rate_limits/endpoints`);
    const now = Date.now();
    const snap = await ref.get();
    const data = ((_a = snap.data()) !== null && _a !== void 0 ? _a : {});
    const entry = (_b = data[key]) !== null && _b !== void 0 ? _b : { count: 0, windowStart: now };
    const windowExpired = now - entry.windowStart >= HOUR_MS;
    const count = windowExpired ? 0 : entry.count;
    const windowStart = windowExpired ? now : entry.windowStart;
    if (count >= maxPerHour) {
        const retryAfterSecs = Math.ceil((entry.windowStart + HOUR_MS - now) / 1000);
        return { limited: true, retryAfterSecs: Math.max(1, retryAfterSecs) };
    }
    await ref.set({ [key]: { count: count + 1, windowStart } }, { merge: true });
    return { limited: false };
}
// ── Validation helpers ────────────────────────────────────────────────────────
const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;
const TASK_STATUSES = new Set(["pending", "done", "skipped"]);
const PROJECT_STATUSES = new Set(["active", "archived", "completed"]);
function assertDate(value, field) {
    if (typeof value !== "string" || !DATE_RE.test(value))
        throw new Error(`${field} : format attendu YYYY-MM-DD, reçu "${value}"`);
}
function clampStr(value, maxLen, field) {
    if (typeof value !== "string")
        throw new Error(`${field} doit être une chaîne`);
    if (value.length > maxLen)
        throw new Error(`${field} dépasse ${maxLen} caractères (reçu ${value.length})`);
    return value;
}
function pickPhase(p) {
    const label = clampStr(p.label, 200, "phase.label");
    assertDate(p.startDate, "phase.startDate");
    assertDate(p.endDate, "phase.endDate");
    return Object.assign({ id: typeof p.id === "string" ? p.id : (0, uuid_1.v4)(), label, startDate: p.startDate, endDate: p.endDate }, (typeof p.color === "string" ? { color: p.color } : {}));
}
function pickTask(t) {
    const title = clampStr(t.title, 200, "task.title");
    assertDate(t.startDate, "task.startDate");
    if (t.endDate !== undefined)
        assertDate(t.endDate, "task.endDate");
    const rawStatus = typeof t.status === "string" ? t.status : "pending";
    if (!TASK_STATUSES.has(rawStatus))
        throw new Error(`task.status invalide : "${rawStatus}"`);
    const rawActions = Array.isArray(t.actions) ? t.actions : [];
    // TaskAction map normalisée dans les DEUX cas : string (nouvelle action) et
    // objet (round-trip get_project → push_gantt, OU action neuve avec
    // linkedActivityId/contexts posés directement — même effet que
    // link_action_to_activity). id/done/doneAt/createdAt sont préservés quand
    // fournis pour ne jamais perdre la progression au re-push.
    // Estimation par défaut (§ 2.4) quand aucune n'est fournie : déduite du
    // verbe / de l'objet (imprimer 10, fiche de séquence 15, corriger 45…).
    const actions = rawActions.map((a) => {
        var _a, _b, _c;
        if (typeof a === "string") {
            const def = (0, default_estimates_1.defaultEstimateFor)(a);
            return Object.assign({ id: (0, uuid_1.v4)(), title: a, done: false, doneAt: null, createdAt: new Date().toISOString() }, (def !== null ? { estimatedMin: def } : {}));
        }
        const o = typeof a === "object" && a !== null
            ? a : {};
        const ctxs = Array.isArray(o.contexts) ? o.contexts.filter((c) => typeof c === "string")
            : typeof o.context === "string" ? [o.context] : [];
        const est = (_b = (_a = estimatedMinOrUndefined(o.estimatedMin)) !== null && _a !== void 0 ? _a : (0, default_estimates_1.defaultEstimateFor)(o.title, ctxs)) !== null && _b !== void 0 ? _b : undefined;
        return withBothContexts(Object.assign(Object.assign(Object.assign(Object.assign(Object.assign({ id: typeof o.id === "string" ? o.id : (0, uuid_1.v4)(), title: typeof o.title === "string" ? o.title : String((_c = o.title) !== null && _c !== void 0 ? _c : ""), done: o.done === true, doneAt: typeof o.doneAt === "string" ? o.doneAt : null, createdAt: typeof o.createdAt === "string"
                ? o.createdAt : new Date().toISOString() }, (typeof o.linkedActivityId === "string" && o.linkedActivityId
            ? { linkedActivityId: o.linkedActivityId } : {})), (typeof o.context === "string" ? { context: o.context } : {})), (Array.isArray(o.contexts)
            ? { contexts: o.contexts.filter((c) => typeof c === "string") } : {})), (est !== undefined ? { estimatedMin: est } : {})), (Array.isArray(o.checklist) ? { checklist: normalizeChecklist(o.checklist) } : {})));
    });
    const estimatedMin = estimatedMinOrUndefined(t.estimatedMin);
    return Object.assign(Object.assign(Object.assign(Object.assign(Object.assign(Object.assign(Object.assign(Object.assign(Object.assign({ id: typeof t.id === "string" ? t.id : (0, uuid_1.v4)(), title, startDate: t.startDate }, (typeof t.endDate === "string" ? { endDate: t.endDate } : {})), (typeof t.phaseId === "string" ? { phaseId: t.phaseId } : {})), (typeof t.groupLabel === "string" ? { groupLabel: t.groupLabel } : {})), (typeof t.color === "string" ? { color: t.color } : {})), (typeof t.barLabel === "string" ? { barLabel: t.barLabel } : {})), (typeof t.interventionId === "string" && t.interventionId ? { interventionId: t.interventionId } : {})), (typeof t.interventionRole === "string" && ["prep", "session", "closure"].includes(t.interventionRole)
        ? { interventionRole: t.interventionRole } : {})), { isMilestone: t.isMilestone === true, status: rawStatus, actions }), (estimatedMin !== undefined ? { estimatedMin } : {}));
}
// Checklist d'une action : string (item neuf) ou objet — id/done/doneAt
// préservés quand fournis (round-trip get_project → push_gantt).
/** `context` (legacy mono) et `contexts` (multi) se complètent toujours :
 *  contexts fourni → context = contexts[0] ; context seul → contexts = [context].
 *  Sans ça, une action créée via le MCP tombait dans « Sans contexte » côté app. */
function withBothContexts(a) {
    const multi = Array.isArray(a.contexts)
        ? a.contexts.filter((c) => typeof c === "string" && c.trim() !== "")
        : [];
    const legacy = typeof a.context === "string" && a.context.trim() !== "" ? a.context : null;
    if (multi.length > 0)
        return Object.assign(Object.assign({}, a), { contexts: multi, context: multi[0] });
    if (legacy)
        return Object.assign(Object.assign({}, a), { contexts: [legacy], context: legacy });
    return a;
}
function normalizeChecklist(raw) {
    return raw.flatMap((c) => {
        var _a;
        if (typeof c === "string") {
            const title = c.trim();
            return title ? [{ id: (0, uuid_1.v4)(), title, done: false, doneAt: null }] : [];
        }
        if (typeof c !== "object" || c === null)
            return [];
        const o = c;
        const title = typeof o.title === "string" ? o.title.trim() : String((_a = o.title) !== null && _a !== void 0 ? _a : "").trim();
        if (!title)
            return [];
        return [{
                id: typeof o.id === "string" ? o.id : (0, uuid_1.v4)(),
                title,
                done: o.done === true,
                doneAt: typeof o.doneAt === "string" ? o.doneAt : null,
            }];
    });
}
// Durée estimée en minutes : entier > 0, sinon undefined (absent/0/négatif/
// type inattendu = « pas d'estimation », l'app applique son défaut).
function estimatedMinOrUndefined(raw) {
    const n = typeof raw === "number" ? raw : Number(raw);
    return Number.isInteger(n) && n > 0 ? n : undefined;
}
function pickProject(p) {
    var _a, _b;
    const title = clampStr(p.title, 200, "project.title");
    const description = p.description !== undefined
        ? clampStr(p.description, 5000, "project.description") : undefined;
    assertDate(p.startDate, "project.startDate");
    if (p.endDate !== undefined)
        assertDate(p.endDate, "project.endDate");
    const phases = (_a = p.phases) !== null && _a !== void 0 ? _a : [];
    const tasks = (_b = p.tasks) !== null && _b !== void 0 ? _b : [];
    if (phases.length > 20)
        throw new Error(`Trop de phases : ${phases.length} (max 20)`);
    if (tasks.length > 200)
        throw new Error(`Trop de tâches : ${tasks.length} (max 200)`);
    const pickedPhases = phases.map((ph) => pickPhase(ph));
    return Object.assign(Object.assign(Object.assign(Object.assign({ title, startDate: p.startDate }, (description !== undefined ? { description } : {})), (p.endDate !== undefined ? { endDate: p.endDate } : {})), (p.domainId !== undefined ? { domainId: p.domainId } : {})), { phases: pickedPhases, tasks: (0, phase_resolve_1.resolvePhaseIds)(pickedPhases, tasks.map((t) => pickTask(t))).tasks });
}
function pickStrategicObjective(so) {
    const title = clampStr(so.title, 200, "strategicObjective.title");
    const description = so.description !== undefined
        ? clampStr(so.description, 5000, "strategicObjective.description") : undefined;
    if (so.startDate !== undefined)
        assertDate(so.startDate, "strategicObjective.startDate");
    if (so.endDate !== undefined)
        assertDate(so.endDate, "strategicObjective.endDate");
    const timeCommitments = so.timeCommitments !== undefined
        ? pickTimeCommitments(so.timeCommitments) : undefined;
    const routineCommitments = so.routineCommitments !== undefined
        ? pickRoutineCommitments(so.routineCommitments) : undefined;
    const status = so.status !== undefined ? String(so.status) : undefined;
    if (status !== undefined && !["active", "done", "archived"].includes(status)) {
        throw new Error(`strategicObjective.status invalide : ${status}`);
    }
    return Object.assign(Object.assign(Object.assign(Object.assign(Object.assign(Object.assign(Object.assign(Object.assign(Object.assign({ title }, (description !== undefined ? { description } : {})), (so.domainId !== undefined ? { domainId: so.domainId } : {})), (so.kpiTarget !== undefined ? { kpiTarget: so.kpiTarget } : {})), (so.horizonLabel !== undefined ? { horizonLabel: so.horizonLabel } : {})), (so.startDate !== undefined ? { startDate: so.startDate } : {})), (so.endDate !== undefined ? { endDate: so.endDate } : {})), (status !== undefined ? { status } : {})), (timeCommitments !== undefined ? { timeCommitments } : {})), (routineCommitments !== undefined ? { routineCommitments } : {}));
}
function pickTimeCommitments(raw) {
    if (!Array.isArray(raw))
        throw new Error("timeCommitments doit être un tableau");
    if (raw.length > 20)
        throw new Error(`Trop de timeCommitments : ${raw.length} (max 20)`);
    return raw.map((c, i) => {
        var _a;
        const activityId = String((_a = c === null || c === void 0 ? void 0 : c.activityId) !== null && _a !== void 0 ? _a : "").trim();
        if (!activityId)
            throw new Error(`timeCommitments[${i}].activityId manquant`);
        const weeklyMin = Math.round(Number(c === null || c === void 0 ? void 0 : c.weeklyMin));
        if (!Number.isFinite(weeklyMin) || weeklyMin < 1 || weeklyMin > 3000) {
            throw new Error(`timeCommitments[${i}].weeklyMin invalide (attendu 1..3000)`);
        }
        return { activityId, weeklyMin };
    });
}
function pickRoutineCommitments(raw) {
    if (!Array.isArray(raw))
        throw new Error("routineCommitments doit être un tableau");
    if (raw.length > 20)
        throw new Error(`Trop de routineCommitments : ${raw.length} (max 20)`);
    return raw.map((c, i) => {
        var _a;
        const activityId = String((_a = c === null || c === void 0 ? void 0 : c.activityId) !== null && _a !== void 0 ? _a : "").trim();
        if (!activityId)
            throw new Error(`routineCommitments[${i}].activityId manquant`);
        return { activityId };
    });
}
async function executePushAssistantMessage(uid, args) {
    var _a, _b, _c, _d, _e;
    if (!/^\d{4}-\d{2}-\d{2}$/.test(args.targetDate)) {
        return `Date invalide : ${args.targetDate}. Format attendu : YYYY-MM-DD`;
    }
    const validTypes = [
        "always", "overdue_count", "day_plan_empty", "project_inactive_days",
        "activity_behind_target", "habit_streak_broken",
        "inbox_overflow", "project_deadline_near", "no_now_focus",
        "routine_completion_low", "day_plan_overloaded", "no_activity_logged_today",
        "project_milestone_today", "week_start", "week_end",
        "activity_streak", "first_open_of_day", "custom_date",
    ];
    if (!validTypes.includes(args.condition.type)) {
        return `Type de condition inconnu : ${args.condition.type}`;
    }
    const id = (0, uuid_1.v4)();
    await db_1.db.collection(`users/${uid}/assistant_messages`).doc(id).set({
        id,
        targetDate: args.targetDate,
        text: args.text,
        condition: args.condition,
        expiresAfterDays: (_a = args.expiresAfterDays) !== null && _a !== void 0 ? _a : 2,
        characterName: (_b = args.characterName) !== null && _b !== void 0 ? _b : "ORION",
        priority: (_c = args.priority) !== null && _c !== void 0 ? _c : 1,
        action: (_d = args.action) !== null && _d !== void 0 ? _d : null,
        requiresReply: (_e = args.requiresReply) !== null && _e !== void 0 ? _e : false,
        status: "pending",
        createdAt: db_1.FieldValue.serverTimestamp(),
        createdBy: "claude",
        shownAt: null,
    });
    // Notification push FCM — fire and forget
    sendOrionPushNotification(uid, args.text).catch(() => { });
    return (`✅ Message assistant programmé pour le ${args.targetDate}.\n` +
        `• Condition : ${args.condition.type}\n` +
        `• Texte : "${args.text.slice(0, 60)}${args.text.length > 60 ? "…" : ""}"\n` +
        `• messageId : ${id}`);
}
// Push FCM générique — réutilise le fcmToken stocké dans orion_config/main.
async function sendFcmPush(uid, title, body, data = {}) {
    var _a;
    const configSnap = await db_1.db.collection(`users/${uid}/orion_config`).doc("main").get();
    if (!configSnap.exists)
        return;
    const fcmToken = (_a = configSnap.data()) === null || _a === void 0 ? void 0 : _a.fcmToken;
    if (!fcmToken)
        return;
    const preview = body.length > 120 ? body.slice(0, 120) + "…" : body;
    await admin.messaging().send({
        token: fcmToken,
        notification: { title, body: preview },
        data,
        apns: { payload: { aps: { sound: "default", badge: 1 } } },
        android: { notification: { channelId: "orion_messages", priority: "high" } },
    });
}
async function sendOrionPushNotification(uid, text) {
    var _a;
    const configSnap = await db_1.db.collection(`users/${uid}/orion_config`).doc("main").get();
    if (!configSnap.exists)
        return;
    const fcmToken = (_a = configSnap.data()) === null || _a === void 0 ? void 0 : _a.fcmToken;
    if (!fcmToken)
        return;
    const preview = text.length > 120 ? text.slice(0, 120) + "…" : text;
    await admin.messaging().send({
        token: fcmToken,
        notification: {
            title: "◉ ORION",
            body: preview,
        },
        data: {
            type: "orion_message",
        },
        apns: {
            payload: {
                aps: {
                    sound: "default",
                    badge: 1,
                },
            },
        },
        android: {
            notification: {
                channelId: "orion_messages",
                priority: "high",
            },
        },
    });
}
async function validateToken(uid, rawToken) {
    const hash = (0, crypto_1.createHash)("sha256").update(rawToken).digest("hex");
    const q = await db_1.db
        .collection(`users/${uid}/api_tokens`)
        .where("tokenHash", "==", hash)
        .where("active", "==", true)
        .limit(1)
        .get();
    if (!q.empty) {
        q.docs[0].ref.update({ lastUsedAt: db_1.FieldValue.serverTimestamp() });
        return true;
    }
    return false;
}
/** Réglage « Programmation automatique » (toggle de l'app → data/meta.autoPlan). */
async function readAutoPlan(uid) {
    const snap = await db_1.db.doc(`users/${uid}/data/meta`).get();
    return snap.exists && snap.data().autoPlan === true;
}
/** Journée active réglée dans l'app (`data/meta.dayWindow {startMin, endMin}`),
 * en heures entières (début arrondi en bas, fin en haut). Null si absente ou
 * incohérente : plan_day garde alors ses défauts 7 h – 20 h. */
async function readDayWindowHours(uid) {
    const snap = await db_1.db.doc(`users/${uid}/data/meta`).get();
    const raw = snap.exists ? snap.data().dayWindow : null;
    if (!raw || typeof raw !== "object")
        return null;
    const { startMin, endMin } = raw;
    if (typeof startMin !== "number" || typeof endMin !== "number")
        return null;
    if (startMin < 0 || endMin > 24 * 60 || endMin - startMin < 4 * 60)
        return null;
    return { startHour: Math.floor(startMin / 60), endHour: Math.ceil(endMin / 60) };
}
function autoPlanBanner(enabled, date) {
    return enabled
        ? [
            `🤖 PROGRAMMATION AUTOMATIQUE : ACTIVÉE (réglage de l'app).`,
            `   Routine quotidienne : tu peux écrire le programme — schedule_day("${date}", blocks,`,
            `   mode:"fill", generatedBy:"auto") : complète les trous, ne remplace rien.`,
        ]
        : [
            `🤖 PROGRAMMATION AUTOMATIQUE : DÉSACTIVÉE (réglage de l'app).`,
            `   Si tu es la routine automatique quotidienne : NE MODIFIE RIEN et réponds`,
            `   « Programmation automatique désactivée dans l'app ». (Une demande directe`,
            `   de l'utilisateur n'est pas concernée : planifie normalement.)`,
        ];
}
/** Agenda Google connecté nativement (OAuth serveur, sync auto active) : l'app
 *  écrit elle-même chaque bloc dans l'agenda — Claude ne doit jamais le faire
 *  via son connecteur (sinon doublons, jusqu'à ×4 constatés le 2026-10-04). */
async function nativeGcalSync(uid) {
    try {
        const d = (await db_1.db.doc(`gcal_tokens/${uid}`).get()).data();
        return !!(d === null || d === void 0 ? void 0 : d.refreshToken) && d.autoSync !== false;
    }
    catch (_a) {
        return false;
    }
}
async function executeGetUserContext(uid) {
    var _a, _b;
    // Fenêtre glissante : 7 derniers jours
    const now = new Date();
    const sevenDaysAgo = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000);
    const todayStr = todayInParis(now);
    const [domainsSnap, activitiesSnap, habitHitsSnap, sessionsSnap, projectsSnap, scheduleSnap, inboxSnap, objectivesSnap] = await Promise.all([
        db_1.db.collection(`users/${uid}/domains`).get(),
        db_1.db.collection(`users/${uid}/activities`).get(),
        // Incréments de routines/habitudes sur 7 jours
        // ⚠️ ts est stocké en CHAÎNE ISO (mobile + log_routine_hit) : comparer
        // à un Timestamp ne matche RIEN (constaté : habitCompletion vide).
        db_1.db.collection(`users/${uid}/habitHits`)
            .where("ts", ">=", sevenDaysAgo.toISOString())
            .get(),
        // Sessions de temps loggué sur 7 jours
        db_1.db.collection(`users/${uid}/sessions`)
            .where("startAt", ">=", sevenDaysAgo.toISOString())
            .get(),
        // Projets — TOUS, filtrés en code : un `where status == active` exclurait
        // les docs legacy SANS champ status (constaté : activeProjects vide alors
        // que des projets actifs existent — l'app les traite comme actifs).
        db_1.db.collection(`users/${uid}/projects`).get(),
        // Programme du jour
        db_1.db.doc(`users/${uid}/daily_schedules/${todayStr}`).get(),
        // Inbox (idées en attente)
        db_1.db.collection(`users/${uid}/captures`).where("status", "==", "pending").get(),
        // Objectifs stratégiques (filtre actif en code : docs legacy sans champ status)
        db_1.db.collection(`users/${uid}/strategic_objectives`).get(),
    ]);
    const autoPlanEnabled = await readAutoPlan(uid);
    const domains = domainsSnap.docs
        .map((d) => d.data())
        .filter((v) => !v.deleted)
        .map((v) => ({ id: v.id, name: v.name }));
    // activityMap inclut TOUTES les activités (y compris archivées) pour résoudre les noms dans timeLogged/habitCompletion
    const activityMap = new Map();
    activitiesSnap.docs.forEach((d) => {
        const v = d.data();
        activityMap.set(v.id, v.deleted ? `${v.name} (archivé)` : v.name);
    });
    const activities = activitiesSnap.docs
        .map((d) => d.data())
        .filter((v) => !v.deleted)
        .map((v) => {
        // Actions PROPRES de l'activité (TaskAction sans tâche/projet) — les
        // ouvertes, avec `done:false` et `estimatedMin` (null = pas d'estimation)
        // explicites (B8, brief 2026-10) ; les faites sont juste comptées.
        const allOwn = Array.isArray(v.ownActions) ? v.ownActions : [];
        const ownDone = allOwn.filter((a) => (a === null || a === void 0 ? void 0 : a.done) === true).length;
        const ownActions = allOwn
            .filter((a) => (a === null || a === void 0 ? void 0 : a.done) !== true)
            .map((a) => {
            var _a;
            return (Object.assign({ id: a.id, title: a.title, done: false, estimatedMin: (_a = estimatedMinOrUndefined(a.estimatedMin)) !== null && _a !== void 0 ? _a : null }, ((0, contexts_1.contextsOf)(a).length > 0 ? { contexts: (0, contexts_1.contextsOf)(a) } : {})));
        });
        return Object.assign(Object.assign({ id: v.id, name: v.name, type: v.type, domainId: v.domainId, goalMin: v.goalMin, habitFreq: v.habitFreq, habitTarget: v.habitTarget }, (ownActions.length > 0 ? { ownActions } : {})), (ownDone > 0 ? { ownActionsDone: ownDone } : {}));
    });
    // ── Réalisé des 7 derniers jours ──────────────────────────────────────────
    // Taux de complétion des habitudes/routines (habitHits groupés par habitId)
    const hitsByHabit = new Map();
    for (const doc of habitHitsSnap.docs) {
        const v = doc.data();
        hitsByHabit.set(v.habitId, (hitsByHabit.get(v.habitId) || 0) + 1);
    }
    // Une session/hit peut référencer une activité DUREMENT supprimée (doc
    // disparu) : un nom lisible plutôt qu'un id brut dans le contexte.
    const nameOf = (id) => activityMap.get(id) || `(activité supprimée · ${id.slice(0, 8)}…)`;
    const habitCompletion = Array.from(hitsByHabit.entries()).map(([id, count]) => ({
        activityId: id,
        name: nameOf(id),
        hitsLast7Days: count,
    }));
    // Temps loggué par activité (sessions)
    const minByActivity = new Map();
    for (const doc of (0, sessions_audit_1.liveSessionDocs)(sessionsSnap)) {
        const v = doc.data();
        if (!v.endAt)
            continue;
        const start = new Date(v.startAt);
        const end = new Date(v.endAt);
        const mins = Math.round((end.getTime() - start.getTime()) / 60000);
        if (mins > 0) {
            minByActivity.set(v.activityId, (minByActivity.get(v.activityId) || 0) + mins);
        }
    }
    const timeLogged = Array.from(minByActivity.entries()).map(([id, mins]) => ({
        activityId: id,
        name: nameOf(id),
        minutesLast7Days: mins,
        hoursLast7Days: Math.round(mins / 6) / 10, // arrondi 1 décimale
    }));
    const recentActivity = {
        period: "7 derniers jours",
        habitCompletion,
        timeLogged,
    };
    // ── Projets actifs (résumé) ────────────────────────────────────────────────
    const today = new Date(todayStr);
    const isActive = (p) => { var _a; return String((_a = p.status) !== null && _a !== void 0 ? _a : "active") === "active"; }; // legacy sans status = actif
    const activeProjects = projectsSnap.docs
        .filter((d) => isActive(d.data()) && d.data().paused !== true)
        .map((d) => {
        var _a, _b;
        const p = d.data();
        const tasks = (p.tasks || []);
        const realTasks = tasks.filter((t) => !t.isMilestone);
        const tasksDone = realTasks.filter((t) => t.status === "done").length;
        const tasksOverdue = realTasks.filter((t) => t.status !== "done" && t.status !== "skipped" &&
            t.endDate && new Date(t.endDate) < today).length;
        const nextDeadline = (_a = realTasks
            .filter((t) => t.status !== "done" && t.status !== "skipped" && t.endDate)
            .sort((a, b) => a.endDate.localeCompare(b.endDate))
            .map((t) => t.endDate)[0]) !== null && _a !== void 0 ? _a : null;
        return {
            id: p.id,
            title: p.title,
            endDate: (_b = p.endDate) !== null && _b !== void 0 ? _b : null,
            tasksDone,
            tasksTotal: realTasks.length,
            tasksOverdue,
            nextDeadline,
        };
    });
    // Projets actifs mais EN PAUSE : hors radar de planification, mais cités
    // pour que l'IA sache qu'ils existent (sinon « projet invisible »).
    const pausedProjects = projectsSnap.docs
        .filter((d) => isActive(d.data()) && d.data().paused === true)
        .map((d) => ({ id: d.data().id, title: d.data().title, paused: true }));
    // ── Programme du jour ──────────────────────────────────────────────────────
    const scheduleData = scheduleSnap.exists ? scheduleSnap.data() : null;
    const todaySchedule = scheduleData
        ? {
            date: todayStr,
            generatedBy: (_a = scheduleData.generatedBy) !== null && _a !== void 0 ? _a : null,
            blocks: ((_b = scheduleData.blocks) !== null && _b !== void 0 ? _b : [])
                .filter((b) => b.status !== "deleted")
                .map((b) => ({
                startTime: b.startTime,
                title: b.title,
                durationMin: b.durationMin,
                category: b.category,
                status: b.status,
            }))
                // Ordre chronologique garanti (le tableau Firestore est en ordre
                // d'insertion — constaté : 07:00 après 08:30).
                .sort((a, b) => a.startTime.localeCompare(b.startTime)),
        }
        : null;
    // ── Inbox (idées en attente) ───────────────────────────────────────────────
    const inboxItems = inboxSnap.docs.map((d) => {
        var _a, _b, _c;
        const v = d.data();
        return { id: (_a = v.id) !== null && _a !== void 0 ? _a : d.id, text: (_c = (_b = v.text) !== null && _b !== void 0 ? _b : v.content) !== null && _c !== void 0 ? _c : "" };
    }).filter((v) => v.text);
    // ── Objectifs stratégiques actifs + progression hebdo ─────────────────────
    const objectivesRaw = objectivesSnap.docs
        .map((d) => { var _a; return (Object.assign(Object.assign({}, d.data()), { id: (_a = d.data().id) !== null && _a !== void 0 ? _a : d.id })); })
        .filter((v) => { var _a; return String((_a = v.status) !== null && _a !== void 0 ? _a : "active") === "active"; })
        .slice(0, 10);
    const objectives = objectivesRaw.length > 0
        ? (0, objectives_1.summarizeObjectives)(objectivesRaw, activitiesSnap.docs.map((d) => d.data()), (0, sessions_audit_1.liveSessionDocs)(sessionsSnap).map((d) => d.data()), habitHitsSnap.docs.map((d) => d.data()), todayStr)
        : null;
    // Règles calendrier selon le mode : agenda natif connecté → Claude n'écrit
    // JAMAIS dans Google Agenda (l'app s'en charge) ; sinon l'ancien parcours
    // connecteur (proposer puis create_event après accord) reste valable.
    const nativeGcal = await nativeGcalSync(uid);
    const calendarRules = nativeGcal
        ? [
            "GOOGLE AGENDA CONNECTÉ DANS L'APP : chaque bloc posé via schedule_day / add_event / add_prep_block apparaît TOUT SEUL dans l'agenda, et les rendez-vous de l'agenda arrivent dans le programme (blocs 📅). Tu ne dois JAMAIS appeler create_event, update_event ni delete_event pour un bloc ou un programme Productivitwo — même si l'utilisateur demande « mets-le dans mon agenda » : pose-le dans le programme et dis que l'agenda suit automatiquement. list_events reste permis pour LIRE (trouver un créneau libre).",
        ]
        : [
            "QUAND l'utilisateur demande un programme (musculation, nutrition, formation, journée…) : demande-lui d'abord s'il veut que tu vérifies son agenda pour intégrer des créneaux concrets. Si oui : list_events → propose des créneaux → create_event après accord (UN seul appel par événement — vérifie avec list_events qu'il n'existe pas déjà avant de le créer).",
        ];
    const coachingRules = {
        _instructions: [
            ...calendarRules,
            "AVANT de commencer tout travail long (programme, bilan, alignement Gantt) : annonce à l'utilisateur que ça prend ~1-2 min et que tu envoies une notification quand c'est prêt.",
            "APRÈS chaque save_document : envoie une push_notification pour informer l'utilisateur.",
            "QUAND tu modifies un projet Gantt (push_gantt, update_project, update_task_status) : appelle get_documents(projectId) et mets à jour le programme HTML associé via save_document en passant le documentId existant (évite les doublons).",
            "POUR créer un programme : appelle toujours get_document_template d'abord, génère le HTML, montre-le à l'utilisateur et attends sa validation avant de créer quoi que ce soit dans Productivitwo.",
            "CONVENTION CALENDRIER : quand tu crées un événement Google Calendar dans le cadre d'une session Productivitwo, ajoute ' - Productivitwo' à la fin du titre (ex: 'Séance musculation - Productivitwo'). Cela te permet d'identifier les events que tu peux modifier librement lors d'une réorganisation. Les events sans ' - Productivitwo' ont été créés par l'utilisateur ou hors contexte Productivitwo : ne les modifie pas sans demander confirmation explicite.",
            "FICHIERS DE TÂCHE : quand tu crées ou sauvegardes un document avec save_document, associe-le toujours à la tâche Gantt concernée via taskId (obtenu depuis get_project → tasks[].id). Choisis la category appropriée : 'programme' pour un plan structuré, 'brief' pour un cahier des charges, 'recherche' pour une analyse/veille, 'livrable' pour un output final, 'notes' pour des notes de travail. Avant de créer un nouveau document, vérifie via get_documents(taskId) si un document de même category existe déjà pour éviter les doublons — si oui, mets-le à jour via documentId.",
            "DESCRIPTIONS DE PROJET CONCISES : la description d'un projet (push_gantt, update_project) fait 2-3 phrases MAX (~300 caractères) — le cap, pas le dossier. Tout détail (audit, spec, historique, décisions) va dans un DOCUMENT lié au projet via save_document (category 'notes' ou 'brief'). La fiche mobile tronque la description à 4 lignes.",
            "PRIORITÉ ABSOLUE : réponds d'abord à la demande de l'utilisateur. Ne fais jamais d'actions non demandées (schedule_day, push_assistant_message, modification Gantt…) avant d'avoir répondu. Les actions proactives viennent APRÈS la réponse, jamais à la place.",
            "OBJECTIFS STRATÉGIQUES : le bloc objectives[] de ce contexte donne la progression hebdo des engagements (temps d'activités, routines) de chaque objectif actif. Quand tu planifies (schedule_day, plan_day) ou arbitres des priorités, favorise les activités/routines dont l'engagement est en retard (onTrack:false). Si un engagement semble irréaliste plusieurs semaines de suite, propose à l'utilisateur de le réviser via save_objective — ne le modifie jamais sans accord.",
            "ACTIONS D'ACTIVITÉ : une activité-temps peut avoir ses propres actions (champ ownActions de chaque activité dans ce contexte) — des sous-actions sans tâche/projet. Tu peux en créer via add_activity_action(activityId, title) puis les PROGRAMMER dans schedule_day en passant activityId + actionId (le chrono du bloc sera ciblé sur l'action). Quand tu programmes une action concrète qui correspond à une activité-temps existante, préfère la rattacher (action propre) plutôt qu'un bloc vague.",
            "LIER UNE ACTION À UNE ACTIVITÉ : quand tu vois une sous-action de tâche Gantt qui n'est PAS déjà liée à une activité (pas de linkedActivityId) et qu'une activité-temps du même domaine existe, PROPOSE à l'utilisateur de l'y associer via link_action_to_activity(projectId, taskId, actionId, activityId) — ainsi le temps passé dessus sera chronométré sur la bonne activité. Propose, n'impose pas ; ne touche pas à une action déjà liée.",
            "PROPOSITIONS DE FIN DE SESSION : après avoir terminé une action significative (programme créé, Gantt mis à jour, bilan fait, messages ORION programmés…), propose toujours 2 à 3 suites logiques sous forme de liste numérotée courte. " +
                "Adapte les options à ce qui vient d'être fait. Exemples pertinents selon le contexte : " +
                "• 'Programme ton plan du jour' (si pas encore fait aujourd'hui) " +
                "• 'Mettre à jour tes priorités Gantt' (si des tâches sont en retard) " +
                "• 'Faire le bilan de la semaine' (si c'est vendredi ou fin de sprint) " +
                "• 'Programmer des messages ORION pour la semaine' (si pas encore fait) " +
                "• 'Créer les routines liées à ce programme' (si un programme vient d'être créé) " +
                (nativeGcal ? "" : "• 'Aligner ton agenda Google Calendar' (si des créneaux sont à bloquer) ") +
                "• 'Voir les projets en veille' (si tu as archivé quelque chose) " +
                "Formule-les en une ligne, sans description. Ne propose pas une option déjà réalisée dans la session.",
            "MESSAGES PROACTIFS (optionnel, après la réponse) : si la demande est un bilan, une analyse ou une planification, tu peux programmer 1 à 2 messages ORION pertinents via push_assistant_message — uniquement si ça apporte une vraie valeur. Vérifie d'abord get_assistant_messages pour éviter les doublons. Ne programme jamais de messages pour une demande simple (action ponctuelle, question, suppression). " +
                "Pour chaque message avec une tâche ou projet précis, ajoute une action ciblée : " +
                "• open_gantt_task(projectId, taskId) pour une tâche Gantt urgente ; " +
                "• open_project(projectId) pour une deadline de projet ; " +
                "• open_schedule pour le programme du jour. " +
                "Ne programme jamais deux messages avec la même condition pour la même période.",
        ],
    };
    return JSON.stringify(Object.assign(Object.assign(Object.assign(Object.assign({}, coachingRules), { today: todayStr, autoPlan: { enabled: autoPlanEnabled }, domains,
        activities,
        objectives,
        activeProjects }), (pausedProjects.length > 0 ? { pausedProjects } : {})), { todaySchedule, inboxItems: inboxItems.length > 0 ? inboxItems : null, recentActivity }), null, 2);
}
async function executeUpdateActivityGoal(uid, activityId, updates) {
    var _a, _b;
    const ref = db_1.db.collection(`users/${uid}/activities`).doc(activityId);
    const snap = await ref.get();
    if (!snap.exists)
        return `Activité introuvable : ${activityId}`;
    const patch = {};
    if (updates.goalMin !== undefined)
        patch.goalMin = updates.goalMin;
    if (updates.habitTarget !== undefined)
        patch.habitTarget = updates.habitTarget;
    if (updates.habitFreq !== undefined)
        patch.habitFreq = updates.habitFreq;
    await ref.update(patch);
    const name = (_b = (_a = snap.data()) === null || _a === void 0 ? void 0 : _a.name) !== null && _b !== void 0 ? _b : activityId;
    return `✅ Objectif de "${name}" mis à jour. Visible dans Productivitwo à la prochaine synchronisation.`;
}
async function executeSetActivityTargets(uid, args) {
    var _a, _b, _c;
    const targets = (_a = args.targets) !== null && _a !== void 0 ? _a : [];
    if (targets.length === 0)
        return "Aucune cible fournie.";
    const set = [];
    const pinned = [];
    const missing = [];
    for (const t of targets) {
        const ref = db_1.db.collection(`users/${uid}/activities`).doc(t.activityId);
        const snap = await ref.get();
        if (!snap.exists) {
            missing.push(t.activityId);
            continue;
        }
        const data = (_b = snap.data()) !== null && _b !== void 0 ? _b : {};
        const name = (_c = data.name) !== null && _c !== void 0 ? _c : t.activityId;
        if (data.targetSource === "user") {
            pinned.push(name);
            continue;
        }
        const goalMin = Math.max(1, Math.round(t.goalMin));
        await ref.set({ goalMin, targetSource: "orion" }, { merge: true });
        set.push(`${name} → ${goalMin} min/j`);
    }
    const lines = [];
    if (set.length)
        lines.push(`✅ Intentions posées : ${set.join(", ")}.`);
    if (pinned.length)
        lines.push(`🔒 Ignorées (épinglées par l'utilisateur) : ${pinned.join(", ")}.`);
    if (missing.length)
        lines.push(`⚠️ Introuvables : ${missing.join(", ")}.`);
    lines.push("Visible dans Productivitwo à la prochaine synchronisation.");
    return lines.join("\n");
}
async function executeCreateRoutine(uid, args) {
    var _a, _b, _c, _d;
    const id = (0, uuid_1.v4)();
    await db_1.db.collection(`users/${uid}/activities`).doc(id).set({
        id,
        name: args.name,
        domainId: args.domainId,
        activityId: (_a = args.activityId) !== null && _a !== void 0 ? _a : null, // lien optionnel vers une activité temps
        type: "habit",
        role: "generic",
        goalMin: 1,
        unit: (_b = args.unit) !== null && _b !== void 0 ? _b : null,
        habitFreq: (_c = args.habitFreq) !== null && _c !== void 0 ? _c : 0,
        habitTarget: (_d = args.habitTarget) !== null && _d !== void 0 ? _d : 1,
        manualTarget: false,
        autoTune: true,
        createdAt: db_1.FieldValue.serverTimestamp(),
        lastTuneAt: null,
        order: 0,
        iconCode: null,
        deleted: false,
    });
    return `✅ Routine "${args.name}" créée (tracking habitude). Elle apparaîtra dans Productivitwo à la prochaine synchronisation.`;
}
async function executeGetDayBlocks(uid) {
    const snap = await db_1.db.collection(`users/${uid}/blocks`).orderBy("order").get();
    if (snap.empty)
        return "Aucun bloc de journée configuré.";
    const blocks = snap.docs.map((d) => {
        var _a, _b;
        const v = d.data();
        return {
            id: v.id,
            name: v.name,
            emoji: v.emoji || null,
            order: v.order,
            startHour: (_a = v.startHour) !== null && _a !== void 0 ? _a : null,
            startMinute: (_b = v.startMinute) !== null && _b !== void 0 ? _b : null,
            activityIds: v.activityIds || [],
        };
    });
    return JSON.stringify({ blocks }, null, 2);
}
async function executeCreateActivity(uid, args) {
    var _a;
    const id = (0, uuid_1.v4)();
    await db_1.db.collection(`users/${uid}/activities`).doc(id).set({
        id,
        name: args.name,
        domainId: args.domainId,
        type: "time",
        role: "generic",
        goalMin: (_a = args.goalMin) !== null && _a !== void 0 ? _a : 1,
        unit: null,
        habitFreq: null,
        habitTarget: null,
        manualTarget: false,
        autoTune: true,
        createdAt: db_1.FieldValue.serverTimestamp(),
        lastTuneAt: null,
        order: 0,
        iconCode: null,
        deleted: false,
    });
    return `✅ Activité "${args.name}" créée (tracking temps). Elle apparaîtra dans Productivitwo à la prochaine synchronisation.`;
}
function executeGetDocumentTemplate() {
    return `<!DOCTYPE html>
<html lang="fr"><head>
<meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1.0">
<title>{{TITRE}}</title>
<link href="https://fonts.googleapis.com/css2?family=Bebas+Neue&family=DM+Sans:ital,wght@0,300;0,400;0,600;1,400&display=swap" rel="stylesheet">
<style>
:root{--bg:#0f0f0f;--surf:#181818;--card:#1f1f1f;--gold:{{COULEUR_ACCENT}};--red:#ff5c35;--txt:#f0ece0;--muted:#747070;--border:#2a2a2a}
/* COULEUR_ACCENT = adapter au domaine : sport=#e8c94a | business=#4ae8b0 | santé=#e84a7a | mental=#7a8fe8 */
*{margin:0;padding:0;box-sizing:border-box}body{background:var(--bg);color:var(--txt);font-family:'DM Sans',sans-serif;font-size:15px;line-height:1.65}
.hero{background:var(--surf);border-bottom:1px solid var(--border);padding:52px 20px 40px;position:relative;overflow:hidden}
.hero::after{content:'';position:absolute;top:-60px;right:-60px;width:280px;height:280px;background:radial-gradient(circle,rgba(var(--gold-rgb),.13) 0%,transparent 70%);pointer-events:none}
.hero-tag{font-family:'Bebas Neue',sans-serif;font-size:11px;letter-spacing:4px;color:var(--gold);margin-bottom:10px}
.hero-title{font-family:'Bebas Neue',sans-serif;font-size:clamp(54px,14vw,96px);line-height:.9;margin-bottom:16px}
.hero-title em{color:var(--gold);font-style:normal}
.hero-sub{color:var(--muted);font-size:14px;max-width:420px}
.stats{display:flex;border-bottom:1px solid var(--border);overflow-x:auto;scrollbar-width:none}
.s{flex:1;min-width:90px;padding:18px 12px;border-right:1px solid var(--border);text-align:center}
.s:last-child{border-right:none}
.sv{font-family:'Bebas Neue',sans-serif;font-size:30px;color:var(--gold);display:block;line-height:1}
.sl{font-size:10px;letter-spacing:1.5px;text-transform:uppercase;color:var(--muted);margin-top:3px}
.wrap{max-width:660px;margin:0 auto;padding:28px 18px 60px}
.sec{margin-bottom:36px}
.sec-head{display:flex;align-items:center;gap:10px;margin-bottom:14px;padding-bottom:8px;border-bottom:1px solid var(--border)}
.sec-n{font-family:'Bebas Neue',sans-serif;font-size:11px;letter-spacing:3px;color:var(--gold)}
.sec-t{font-family:'Bebas Neue',sans-serif;font-size:20px;letter-spacing:1px}
.grid2{display:grid;grid-template-columns:1fr 1fr;gap:9px;margin-bottom:12px}
.ic{background:var(--card);border:1px solid var(--border);border-radius:8px;padding:14px}
.ic.gold{border-color:rgba(232,201,74,.3);background:rgba(232,201,74,.05)}
.ic-tag{font-size:10px;letter-spacing:1.5px;text-transform:uppercase;color:var(--muted);margin-bottom:6px}
.ic-val{font-family:'Bebas Neue',sans-serif;font-size:28px;color:var(--gold);line-height:1}
.ic-sub{font-size:12px;color:var(--muted);margin-top:3px}
.note{background:rgba(232,201,74,.06);border:1px solid rgba(232,201,74,.2);border-radius:8px;padding:14px 16px;font-size:13px;color:var(--txt)}
.note strong{color:var(--gold)}
.phase{background:var(--card);border:1px solid var(--border);border-radius:10px;margin-bottom:10px;overflow:hidden}
.ph{display:flex;align-items:center;gap:12px;padding:15px 16px;cursor:pointer;user-select:none}
.pn{font-family:'Bebas Neue',sans-serif;font-size:12px;letter-spacing:2px;color:var(--gold);background:rgba(232,201,74,.1);border:1px solid rgba(232,201,74,.2);padding:2px 10px;border-radius:4px;white-space:nowrap}
.pt{font-weight:600;flex:1;font-size:14px}.pd{font-size:12px;color:var(--muted)}.pa{color:var(--muted);font-size:11px;transition:transform .2s}
.phase.open .pa{transform:rotate(180deg)}.pb{display:none;padding:0 16px 16px;border-top:1px solid var(--border)}.phase.open .pb{display:block}
.tabs{display:flex;gap:6px;margin:14px 0 10px;overflow-x:auto;scrollbar-width:none;padding-bottom:2px}.tabs::-webkit-scrollbar{display:none}
.tab{font-size:12px;font-weight:600;padding:5px 14px;border-radius:4px;border:1px solid var(--border);background:transparent;color:var(--muted);cursor:pointer;white-space:nowrap;font-family:'DM Sans',sans-serif;transition:all .15s}
.tab.on{background:var(--gold);color:#0f0f0f;border-color:var(--gold)}.wc{display:none}.wc.on{display:block}
.day{background:var(--surf);border:1px solid var(--border);border-radius:8px;margin-bottom:10px;overflow:hidden}
.dh{display:flex;align-items:center;gap:10px;padding:9px 14px;border-bottom:1px solid var(--border)}
.db{font-family:'Bebas Neue',sans-serif;font-size:11px;letter-spacing:1px;padding:2px 10px;border-radius:3px;background:var(--red);color:#fff}
.dn{font-weight:600;font-size:14px}.df{font-size:12px;color:var(--muted)}
table{width:100%;border-collapse:collapse;font-size:13px}
th{text-align:left;padding:6px 14px;font-size:10px;letter-spacing:1.5px;text-transform:uppercase;color:var(--muted);font-weight:500}
td{padding:8px 14px;border-top:1px solid var(--border);vertical-align:top}
tr:hover td{background:rgba(255,255,255,.02)}
.en{font-weight:500}.et{font-size:11px;color:var(--muted);margin-top:2px}
.sr{font-family:'Bebas Neue',sans-serif;font-size:16px;color:var(--gold);white-space:nowrap}.rt{font-size:12px;color:var(--muted);white-space:nowrap}
.tl{list-style:none}.tl li{display:flex;gap:10px;padding:8px 0;border-bottom:1px solid var(--border);font-size:14px}.tl li:last-child{border-bottom:none}
.ti{color:var(--gold);flex-shrink:0;font-size:16px}
.timeline{display:flex;flex-direction:column;gap:0}.trow{display:flex;align-items:stretch;gap:0}
.tline{display:flex;flex-direction:column;align-items:center;width:32px;flex-shrink:0}
.tdot{width:12px;height:12px;border-radius:50%;background:var(--gold);flex-shrink:0;margin-top:4px}.tbar{flex:1;width:2px;background:var(--border)}
.trow:last-child .tbar{display:none}.tcont{flex:1;padding:0 0 20px 14px}
.tmonth{font-family:'Bebas Neue',sans-serif;font-size:18px;letter-spacing:1px;color:var(--gold);line-height:1}
.tdesc{font-size:13px;color:var(--muted);margin-top:4px}.tkg{font-size:13px;color:var(--txt);margin-top:2px}
.footer{text-align:center;padding:28px 18px;color:var(--muted);font-size:12px;border-top:1px solid var(--border)}
</style></head><body>

<!-- HERO : adapter TITRE, SOUS-TITRE, TAG -->
<div class="hero">
  <div class="hero-tag">■ {{TAG}}</div>
  <h1 class="hero-title">{{TITRE_LIGNE1}}<br>{{TITRE_LIGNE2_EM}}</h1>
  <p class="hero-sub">{{SOUS_TITRE_PROFIL}}</p>
</div>

<!-- STATS : 5 métriques clés du programme -->
<div class="stats">
  <div class="s"><span class="sv">{{S1_VAL}}</span><div class="sl">{{S1_LABEL}}</div></div>
  <div class="s"><span class="sv">{{S2_VAL}}</span><div class="sl">{{S2_LABEL}}</div></div>
  <div class="s"><span class="sv">{{S3_VAL}}</span><div class="sl">{{S3_LABEL}}</div></div>
  <div class="s"><span class="sv">{{S4_VAL}}</span><div class="sl">{{S4_LABEL}}</div></div>
  <div class="s"><span class="sv">{{S5_VAL}}</span><div class="sl">{{S5_LABEL}}</div></div>
</div>

<div class="wrap">
<!-- SECTIONS : reproduire le pattern sec-head + contenu adapté au programme -->
<!-- Phases avec .phase.open + accordéons toggle() + onglets switchTab() -->
<!-- Timeline mois par mois + règles d'or en liste .tl -->
</div>

<div class="footer">{{FOOTER_TEXT}}</div>

<script>
function toggle(id){document.getElementById(id).classList.toggle('open')}
function switchTab(phase,key,btn){
  document.querySelectorAll('#'+phase+' .wc').forEach(w=>w.classList.remove('on'));
  btn.parentElement.querySelectorAll('.tab').forEach(t=>t.classList.remove('on'));
  btn.classList.add('on');
  var t=document.getElementById(phase+'-'+key);if(t)t.classList.add('on');
}
window.addEventListener('load',function(){
  var dots=document.querySelectorAll('.tdot');
  dots.forEach((d,i)=>{d.style.opacity='0';d.style.transform='scale(0)';d.style.transition='opacity .3s,transform .3s';setTimeout(()=>{d.style.opacity='1';d.style.transform='scale(1)'},200+i*120)});
});
</script></body></html>

INSTRUCTIONS D'ADAPTATION :
- Remplacer tous les {{PLACEHOLDER}} par le contenu réel
- {{COULEUR_ACCENT}} : sport=#e8c94a | business=#4ae8b0 | santé=#e84a7a | mental=#7a8fe8 | général=#e8c94a
- Reproduire la structure complète : hero + stats + sections numérotées + phases accordéon + timeline + règles
- Chaque phase doit avoir ses onglets avec les détails complets (exercices, séries, repos)
- NE PAS simplifier — le programme complet, pas un résumé`;
}
async function executeSaveDocument(uid, args) {
    const id = args.documentId || (0, uuid_1.v4)();
    const isUpdate = !!args.documentId;
    await db_1.db.collection(`users/${uid}/documents`).doc(id).set(Object.assign({ id, title: args.title, content: args.content, projectId: args.projectId || null, taskId: args.taskId || null, category: args.category || "notes", domainId: args.domainId || null, subtitle: args.subtitle || null, type: "html" }, (isUpdate ? { updatedAt: db_1.FieldValue.serverTimestamp() } : { createdAt: db_1.FieldValue.serverTimestamp() })), { merge: true });
    return `✅ Document "${args.title}" ${isUpdate ? "mis à jour" : "sauvegardé"} (id: ${id}, category: ${args.category || "notes"}${args.taskId ? `, taskId: ${args.taskId}` : ""}).`;
}
async function executeGetDocuments(uid, projectId, taskId) {
    const snap = await db_1.db.collection(`users/${uid}/documents`).orderBy("createdAt", "desc").get();
    if (snap.empty)
        return "Aucun document sauvegardé.";
    const docs = snap.docs
        .map((d) => d.data())
        .filter((d) => !projectId || d.projectId === projectId)
        .filter((d) => !taskId || d.taskId === taskId)
        .map((d) => {
        var _a, _b, _c, _d, _e, _f, _g, _h;
        return ({
            id: d.id,
            title: d.title,
            subtitle: d.subtitle || null,
            category: d.category || "notes",
            projectId: d.projectId || null,
            taskId: d.taskId || null,
            createdAt: ((_d = (_c = (_b = (_a = d.createdAt) === null || _a === void 0 ? void 0 : _a.toDate) === null || _b === void 0 ? void 0 : _b.call(_a)) === null || _c === void 0 ? void 0 : _c.toISOString) === null || _d === void 0 ? void 0 : _d.call(_c)) || null,
            updatedAt: ((_h = (_g = (_f = (_e = d.updatedAt) === null || _e === void 0 ? void 0 : _e.toDate) === null || _f === void 0 ? void 0 : _f.call(_e)) === null || _g === void 0 ? void 0 : _g.toISOString) === null || _h === void 0 ? void 0 : _h.call(_g)) || null,
            content: d.content,
        });
    });
    if (!docs.length)
        return taskId ? "Aucun document pour cette tâche." : "Aucun document pour ce projet.";
    return JSON.stringify(docs, null, 2);
}
function normLabel(s) {
    return s.toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "").trim();
}
async function latestMenu(uid) {
    var _a;
    const snap = await db_1.db.collection(`users/${uid}/artifacts`).get();
    let best = null;
    for (const d of snap.docs) {
        const data = d.data();
        if (data.kind !== "weekly_menu" || data.deleted === true)
            continue;
        const at = String((_a = data.generatedAt) !== null && _a !== void 0 ? _a : "");
        if (!best || at > best.at)
            best = { ref: d.ref, data, at };
    }
    return best ? { ref: best.ref, data: best.data } : null;
}
async function executeGetShoppingList(uid) {
    var _a, _b;
    const menu = await latestMenu(uid);
    if (!menu) {
        return "Aucun menu de la semaine — la liste de courses vit sur l'artefact menu (générable depuis l'app).";
    }
    const items = (_a = menu.data.shoppingList) !== null && _a !== void 0 ? _a : [];
    const at = String((_b = menu.data.generatedAt) !== null && _b !== void 0 ? _b : "").slice(0, 10);
    if (!items.length)
        return `Menu du ${at} : liste de courses vide.`;
    const remaining = items.filter((s) => s.checked !== true).length;
    const lines = items.map((s) => {
        var _a, _b;
        const qty = ((_a = s.qty) !== null && _a !== void 0 ? _a : "").trim();
        return `${s.checked === true ? "☑" : "☐"} ${(_b = s.label) !== null && _b !== void 0 ? _b : "?"}${qty ? ` ${qty}` : ""}`;
    });
    return (`Liste de courses — menu du ${at} (${remaining} restant${remaining > 1 ? "s" : ""} sur ${items.length}) :\n` +
        lines.join("\n"));
}
async function executeAddShoppingItem(uid, label, qty) {
    var _a;
    const clean = (label !== null && label !== void 0 ? label : "").trim();
    if (!clean)
        return "❌ label vide.";
    const menu = await latestMenu(uid);
    if (!menu) {
        return "❌ Aucun menu de la semaine : impossible d'ajouter (la liste vit sur l'artefact menu, générable depuis l'app).";
    }
    const items = ((_a = menu.data.shoppingList) !== null && _a !== void 0 ? _a : []).slice();
    if (items.some((s) => { var _a; return normLabel(String((_a = s.label) !== null && _a !== void 0 ? _a : "")) === normLabel(clean); })) {
        return `Déjà sur la liste : « ${clean} ».`;
    }
    items.push({ label: clean, qty: (qty !== null && qty !== void 0 ? qty : "").trim(), checked: false });
    await menu.ref.update({ shoppingList: items });
    return `✅ Ajouté à la liste de courses : ${clean}${qty ? ` ${qty}` : ""} (${items.filter((s) => s.checked !== true).length} restants).`;
}
async function executeCheckShoppingItem(uid, label, checked) {
    var _a;
    const needle = normLabel(label !== null && label !== void 0 ? label : "");
    if (!needle)
        return "❌ label vide.";
    const menu = await latestMenu(uid);
    if (!menu)
        return "❌ Aucun menu de la semaine (donc pas de liste de courses).";
    const items = ((_a = menu.data.shoppingList) !== null && _a !== void 0 ? _a : []).slice();
    const exact = items.filter((s) => { var _a; return normLabel(String((_a = s.label) !== null && _a !== void 0 ? _a : "")) === needle; });
    const partial = exact.length
        ? exact
        : items.filter((s) => { var _a; return normLabel(String((_a = s.label) !== null && _a !== void 0 ? _a : "")).includes(needle); });
    if (!partial.length)
        return `❌ Introuvable sur la liste : « ${label} ».`;
    if (partial.length > 1) {
        return (`❓ Plusieurs articles correspondent à « ${label} » — précise :\n` +
            partial.map((s) => `• ${s.label}`).join("\n"));
    }
    partial[0].checked = checked;
    await menu.ref.update({ shoppingList: items });
    const remaining = items.filter((s) => s.checked !== true).length;
    return `✅ ${partial[0].label} ${checked ? "coché" : "décoché"} — ${remaining} restant${remaining > 1 ? "s" : ""}.`;
}
async function executeGetArchives(uid) {
    const [domainsSnap, activitiesSnap] = await Promise.all([
        db_1.db.collection(`users/${uid}/domains`).where("deleted", "==", true).get(),
        db_1.db.collection(`users/${uid}/activities`).where("deleted", "==", true).get(),
    ]);
    const domains = domainsSnap.docs.map((d) => ({ id: d.id, name: d.data().name }));
    const activities = activitiesSnap.docs.map((d) => {
        var _a;
        return ({
            id: d.id, name: d.data().name, domainId: (_a = d.data().domainId) !== null && _a !== void 0 ? _a : null,
        });
    });
    if (!domains.length && !activities.length)
        return "Aucun élément archivé — tout est propre.";
    return JSON.stringify({ domains, activities }, null, 2);
}
async function executeRestoreItem(uid, collection, itemId) {
    var _a, _b, _c, _d;
    const ref = db_1.db.collection(`users/${uid}/${collection}`).doc(itemId);
    const snap = await ref.get();
    if (!snap.exists)
        return `Élément introuvable : ${itemId}`;
    const label = (_d = (_b = (_a = snap.data()) === null || _a === void 0 ? void 0 : _a.name) !== null && _b !== void 0 ? _b : (_c = snap.data()) === null || _c === void 0 ? void 0 : _c.title) !== null && _d !== void 0 ? _d : itemId;
    await ref.update({ deleted: false });
    return `✅ "${label}" restauré dans ${collection}.`;
}
async function executeCreateDomain(uid, args) {
    var _a, _b, _c;
    const id = (0, uuid_1.v4)();
    await db_1.db.collection(`users/${uid}/domains`).doc(id).set({
        id,
        name: args.name,
        goalMinDay: (_a = args.goalMinDay) !== null && _a !== void 0 ? _a : null,
        autoGoal: (_b = args.autoGoal) !== null && _b !== void 0 ? _b : true,
        colorValue: (_c = args.colorValue) !== null && _c !== void 0 ? _c : null,
        createdAt: db_1.FieldValue.serverTimestamp(),
    });
    return `✅ Domaine "${args.name}" créé (id: ${id}). Il apparaîtra dans Productivitwo à la prochaine synchronisation.`;
}
async function executeUpdateDomain(uid, domainId, updates) {
    var _a, _b, _c, _d;
    const ref = db_1.db.collection(`users/${uid}/domains`).doc(domainId);
    const snap = await ref.get();
    if (!snap.exists || ((_a = snap.data()) === null || _a === void 0 ? void 0 : _a.deleted) === true)
        return `Domaine introuvable : ${domainId}`;
    const patch = {};
    if (updates.name !== undefined) {
        const name = clampStr(updates.name, 80, "name").trim();
        if (!name)
            return "name vide.";
        patch.name = name;
    }
    if (updates.goalMinDay !== undefined)
        patch.goalMinDay = updates.goalMinDay > 0 ? updates.goalMinDay : null;
    if (updates.autoGoal !== undefined)
        patch.autoGoal = updates.autoGoal;
    if (updates.colorValue !== undefined)
        patch.colorValue = updates.colorValue;
    if (!Object.keys(patch).length)
        return "Rien à modifier (name, goalMinDay, autoGoal ou colorValue).";
    await ref.update(patch);
    const before = String((_c = (_b = snap.data()) === null || _b === void 0 ? void 0 : _b.name) !== null && _c !== void 0 ? _c : domainId);
    const after = String((_d = patch.name) !== null && _d !== void 0 ? _d : before);
    return patch.name !== undefined && after !== before
        ? `✅ Domaine « ${before} » renommé « ${after} »${Object.keys(patch).length > 1 ? " (+ autres champs)" : ""}.`
        : `✅ Domaine « ${before} » mis à jour (${Object.keys(patch).join(", ")}).`;
}
async function executeDeleteDomain(uid, domainId) {
    var _a, _b;
    const ref = db_1.db.collection(`users/${uid}/domains`).doc(domainId);
    const snap = await ref.get();
    if (!snap.exists)
        return `Domaine introuvable : ${domainId}`;
    const name = (_b = (_a = snap.data()) === null || _a === void 0 ? void 0 : _a.name) !== null && _b !== void 0 ? _b : domainId;
    await ref.update({ deleted: true });
    // Cascade : soft-delete toutes les activités du domaine
    const activitiesSnap = await db_1.db.collection(`users/${uid}/activities`)
        .where("domainId", "==", domainId)
        .get();
    let deletedActivities = 0;
    if (!activitiesSnap.empty) {
        const actBatch = db_1.db.batch();
        for (const doc of activitiesSnap.docs)
            actBatch.update(doc.ref, { deleted: true });
        await actBatch.commit();
        deletedActivities = activitiesSnap.size;
    }
    const details = [
        deletedActivities > 0 ? `${deletedActivities} activité(s)` : null,
    ].filter(Boolean).join(", ");
    return `✅ Domaine "${name}" supprimé${details ? ` (cascade : ${details})` : ""}.`;
}
async function executeDeleteActivity(uid, activityId) {
    var _a, _b;
    const ref = db_1.db.collection(`users/${uid}/activities`).doc(activityId);
    const snap = await ref.get();
    if (!snap.exists)
        return `Activité introuvable : ${activityId}`;
    const name = (_b = (_a = snap.data()) === null || _a === void 0 ? void 0 : _a.name) !== null && _b !== void 0 ? _b : activityId;
    await ref.update({ deleted: true });
    return `✅ Activité "${name}" supprimée.`;
}
async function executeUpdateProject(uid, projectId, updates) {
    var _a, _b, _c, _d, _e, _f, _g;
    const ref = db_1.db.collection(`users/${uid}/projects`).doc(projectId);
    const snap = await ref.get();
    if (!snap.exists)
        return `Projet introuvable : ${projectId}`;
    // Phases : retouche unitaire par id (libellé, couleur, dates) — jamais
    // d'ajout ni de suppression ici (push_gantt), les tâches ne bougent pas.
    let phasesPatch;
    let phasesNote = "";
    if (updates.phases !== undefined) {
        if (!Array.isArray(updates.phases) || !updates.phases.length)
            return `❌ phases : tableau non vide attendu.`;
        const current = ((_b = (_a = snap.data()) === null || _a === void 0 ? void 0 : _a.phases) !== null && _b !== void 0 ? _b : []).map((p) => (Object.assign({}, p)));
        const touched = [];
        for (const u of updates.phases) {
            const ph = current.find((p) => p.id === u.id);
            if (!ph)
                return `❌ Phase introuvable : ${u.id} (get_project → phases[].id).`;
            try {
                if (u.label !== undefined)
                    ph.label = clampStr(u.label, 200, "phase.label");
                if (u.startDate !== undefined) {
                    assertDate(u.startDate, "phase.startDate");
                    ph.startDate = u.startDate;
                }
                if (u.endDate !== undefined) {
                    assertDate(u.endDate, "phase.endDate");
                    ph.endDate = u.endDate;
                }
                if (u.color !== undefined)
                    ph.color = u.color;
            }
            catch (e) {
                return `❌ ${e.message}`;
            }
            if (String(ph.startDate) > String(ph.endDate))
                return `❌ Phase « ${ph.label} » : début après la fin.`;
            touched.push(String(ph.label));
        }
        phasesPatch = current;
        phasesNote = ` · phase(s) retouchée(s) : ${touched.join(", ")}`;
    }
    // Parent (hiérarchie client / dossier) : existe, pas lui-même, pas un de
    // ses propres descendants (sinon boucle). "" ou null = détacher.
    if (updates.parentProjectId !== undefined) {
        const pid = updates.parentProjectId;
        if (pid) {
            if (pid === projectId)
                return `❌ Un projet ne peut pas être son propre parent.`;
            const all = (await db_1.db.collection(`users/${uid}/projects`).get()).docs
                .map((d) => ({ id: d.id, parent: d.data().parentProjectId }));
            if (!all.some((p) => p.id === pid))
                return `❌ Projet parent introuvable : ${pid}`;
            let cur = pid;
            const seen = new Set();
            while (cur && !seen.has(cur)) {
                if (cur === projectId)
                    return `❌ ${pid} dépend déjà de ce projet : rattachement circulaire refusé.`;
                seen.add(cur);
                cur = (_d = (_c = all.find((p) => p.id === cur)) === null || _c === void 0 ? void 0 : _c.parent) !== null && _d !== void 0 ? _d : null;
            }
        }
    }
    const title = (_e = updates.title) !== null && _e !== void 0 ? _e : ((_g = (_f = snap.data()) === null || _f === void 0 ? void 0 : _f.title) !== null && _g !== void 0 ? _g : projectId);
    if (updates.status !== undefined && !PROJECT_STATUSES.has(updates.status))
        return `❌ status invalide : "${updates.status}". Valeurs acceptées : active, archived, completed`;
    const patch = { updatedAt: db_1.FieldValue.serverTimestamp() };
    if (updates.domainId !== undefined)
        patch.domainId = updates.domainId;
    if (updates.title !== undefined)
        patch.title = clampStr(updates.title, 200, "title");
    if (updates.description !== undefined)
        patch.description = clampStr(updates.description, 5000, "description");
    if (updates.status !== undefined)
        patch.status = updates.status;
    if (updates.parentProjectId !== undefined)
        patch.parentProjectId = updates.parentProjectId || null;
    if (phasesPatch !== undefined)
        patch.phases = phasesPatch;
    await ref.update(patch);
    return `✅ Projet "${title}" mis à jour${phasesNote}.`;
}
async function executeUpdateTaskStatus(uid, projectId, taskId, status) {
    var _a;
    if (!TASK_STATUSES.has(status))
        return `❌ status invalide : "${status}". Valeurs acceptées : pending, done, skipped`;
    const ref = db_1.db.collection(`users/${uid}/projects`).doc(projectId);
    const snap = await ref.get();
    if (!snap.exists)
        return `Projet introuvable : ${projectId}`;
    const data = snap.data();
    const tasks = (data.tasks || []);
    const idx = tasks.findIndex((t) => t.id === taskId);
    if (idx === -1)
        return `Tâche introuvable : ${taskId}`;
    tasks[idx] = Object.assign(Object.assign({}, tasks[idx]), { status });
    await ref.update({ tasks, updatedAt: db_1.FieldValue.serverTimestamp() });
    const taskTitle = (_a = tasks[idx].title) !== null && _a !== void 0 ? _a : taskId;
    const emoji = status === "done" ? "✅" : status === "skipped" ? "⏭️" : "🔄";
    return `${emoji} Tâche "${taskTitle}" → ${status}.`;
}
async function executeUpdateActivity(uid, activityId, updates) {
    var _a, _b, _c, _d, _e;
    const ref = db_1.db.collection(`users/${uid}/activities`).doc(activityId);
    const snap = await ref.get();
    if (!snap.exists)
        return `Activité introuvable : ${activityId}`;
    const currentName = (_b = (_a = snap.data()) === null || _a === void 0 ? void 0 : _a.name) !== null && _b !== void 0 ? _b : activityId;
    const patch = {};
    if (updates.name !== undefined)
        patch.name = updates.name;
    if (updates.domainId !== undefined)
        patch.domainId = updates.domainId;
    if (updates.goalMin !== undefined)
        patch.goalMin = updates.goalMin;
    if (updates.unit !== undefined)
        patch.unit = updates.unit;
    if (updates.habitFreq !== undefined)
        patch.habitFreq = updates.habitFreq;
    if (updates.habitTarget !== undefined)
        patch.habitTarget = updates.habitTarget;
    if (updates.timeContext !== undefined) {
        // Fenêtre naturelle de la routine — chaîne vide = retour à l'auto.
        patch.timeContext = updates.timeContext.trim() === "" ? null : updates.timeContext.trim();
    }
    if (updates.finalTarget !== undefined) {
        // Cap de progression : habitTarget devient le palier courant. Nouveau cap
        // = nouveau départ — l'évaluation hebdo attend une semaine pleine.
        patch.finalTarget = updates.finalTarget > 0 ? updates.finalTarget : null;
        patch.stepUpdatedWeek = null;
    }
    await ref.update(patch);
    if (updates.finalTarget !== undefined && updates.finalTarget > 0) {
        return `✅ Activité "${currentName}" mise à jour — progression vers ${updates.finalTarget}/j, palier courant ${(_e = (_c = updates.habitTarget) !== null && _c !== void 0 ? _c : (_d = snap.data()) === null || _d === void 0 ? void 0 : _d.habitTarget) !== null && _e !== void 0 ? _e : 1}/j (évalué chaque lundi sur les hits réels).`;
    }
    return `✅ Activité "${currentName}" mise à jour.`;
}
async function executeDeleteRoutine(uid, routineId) {
    var _a, _b;
    const ref = db_1.db.collection(`users/${uid}/activities`).doc(routineId);
    const snap = await ref.get();
    if (!snap.exists)
        return `Routine introuvable : ${routineId}`;
    const title = (_b = (_a = snap.data()) === null || _a === void 0 ? void 0 : _a.name) !== null && _b !== void 0 ? _b : routineId;
    // Soft-delete pour que le merge Flutter respecte la suppression
    await ref.update({ deleted: true });
    return `✅ Routine "${title}" supprimée.`;
}
async function executeArchiveProject(uid, projectId, restore) {
    var _a, _b;
    const ref = db_1.db.collection(`users/${uid}/projects`).doc(projectId);
    const snap = await ref.get();
    if (!snap.exists)
        return `Projet introuvable : ${projectId}`;
    const title = (_b = (_a = snap.data()) === null || _a === void 0 ? void 0 : _a.title) !== null && _b !== void 0 ? _b : projectId;
    const newStatus = restore ? "active" : "archived";
    await ref.update({ status: newStatus, updatedAt: db_1.FieldValue.serverTimestamp() });
    if (restore)
        return `✅ Projet "${title}" réactivé — il apparaît à nouveau dans le focus.`;
    // B5 : archiver un projet qui porte encore des séances à venir n'est pas silencieux.
    const warn = await upcomingWarning(uid, projectId, snap.data());
    return `✅ Projet "${title}" mis en veille — visible dans la section Archives du web app.${warn}`;
}
async function executeDeleteProject(uid, projectId, deleteObjective) {
    var _a;
    const projectRef = db_1.db.collection(`users/${uid}/projects`).doc(projectId);
    const projectSnap = await projectRef.get();
    if (!projectSnap.exists) {
        return `Projet introuvable : ${projectId}`;
    }
    const projectData = projectSnap.data();
    const title = (_a = projectData.title) !== null && _a !== void 0 ? _a : projectId;
    const objId = projectData.strategicObjectiveId;
    await projectRef.delete();
    if (deleteObjective && objId) {
        // Soft-delete : l'objectif est archivé, jamais supprimé physiquement.
        await db_1.db.collection(`users/${uid}/strategic_objectives`).doc(objId)
            .set({ status: "archived", updatedAt: db_1.FieldValue.serverTimestamp() }, { merge: true });
        return `✅ Projet "${title}" supprimé et son objectif stratégique archivé.`;
    }
    return `✅ Projet "${title}" supprimé.`;
}
async function executeListProjects(uid) {
    const snap = await db_1.db.collection(`users/${uid}/projects`).get();
    if (snap.empty)
        return "Aucun projet trouvé dans Productivitwo.";
    // Statut visible sur chaque ligne, actifs d'abord (puis pause, brouillons,
    // archivés/terminés) — sans ça il fallait un get_project par projet.
    const rank = (d) => {
        var _a;
        const status = String((_a = d.status) !== null && _a !== void 0 ? _a : "active");
        if (status === "active")
            return d.paused === true ? 1 : 0;
        return status === "draft" ? 2 : 3;
    };
    const docs = [...snap.docs].sort((a, b) => rank(a.data()) - rank(b.data()));
    const lines = docs.map((doc) => {
        var _a, _b;
        const d = doc.data();
        const taskCount = (d.tasks || []).length;
        const start = d.startDate || "?";
        const end = d.endDate || "?";
        const domain = d.domainId ? ` · domaine:${d.domainId}` : '';
        const status = String((_a = d.status) !== null && _a !== void 0 ? _a : "active");
        const badge = status !== "active"
            ? ` · ${(_b = { archived: "ARCHIVÉ", draft: "BROUILLON",
                completed: "TERMINÉ" }[status]) !== null && _b !== void 0 ? _b : status.toUpperCase()}`
            : d.paused === true ? " · EN PAUSE" : "";
        return `• [${d.id}] ${d.title} (${start} → ${end}, ${taskCount} tâche(s)${domain}${badge})`;
    });
    return `Projets Productivitwo (${snap.size}) :\n${lines.join("\n")}`;
}
async function executeGetProject(uid, projectId) {
    const doc = await db_1.db.collection(`users/${uid}/projects`).doc(projectId).get();
    if (!doc.exists)
        return `Projet introuvable : ${projectId}`;
    const d = doc.data();
    // Retourner le JSON complet pour que Claude puisse le modifier
    return JSON.stringify(d, null, 2);
}
async function executePushGantt(uid, input, 
// draftOnCreate : le cycle ORION autonome crée en brouillon (l'IA propose,
// l'utilisateur dispose) ; le chemin MCP conversationnel crée ACTIF — le
// user vient de le demander, un draft invisible dans activeProjects avait
// été pris pour un bug (test connecteur 2026-09).
opts) {
    var _a, _b, _c;
    const { project, strategicObjective } = input;
    let pickedProject;
    let pickedSO;
    try {
        pickedProject = pickProject(project);
        if (strategicObjective)
            pickedSO = pickStrategicObjective(strategicObjective);
    }
    catch (e) {
        return `❌ Payload invalide : ${e instanceof Error ? e.message : String(e)}`;
    }
    let strategicObjectiveId;
    if (strategicObjective && pickedSO) {
        const objId = strategicObjective.id || (0, uuid_1.v4)();
        strategicObjectiveId = objId;
        await db_1.db.collection(`users/${uid}/strategic_objectives`).doc(objId).set(Object.assign(Object.assign({}, pickedSO), { id: objId, status: "active", updatedAt: db_1.FieldValue.serverTimestamp(), createdAt: db_1.FieldValue.serverTimestamp() }), { merge: true });
    }
    const projectId = project.id || (0, uuid_1.v4)();
    await db_1.db.collection(`users/${uid}/projects`).doc(projectId).set(Object.assign(Object.assign(Object.assign(Object.assign(Object.assign(Object.assign(Object.assign({}, pickedProject), { id: projectId, createdBy: uid, sourceType: "claude_mcp" }), ((opts === null || opts === void 0 ? void 0 : opts.source) ? { source: opts.source } : {})), ((opts === null || opts === void 0 ? void 0 : opts.originIdeas) && opts.originIdeas.length
        ? { originIdeas: db_1.FieldValue.arrayUnion(...opts.originIdeas) }
        : {})), (project.id ? {} : { status: (opts === null || opts === void 0 ? void 0 : opts.draftOnCreate) ? "draft" : "active" })), (strategicObjectiveId ? { strategicObjectiveId } : {})), { updatedAt: db_1.FieldValue.serverTimestamp(), createdAt: db_1.FieldValue.serverTimestamp() }), { merge: true });
    if (strategicObjectiveId) {
        await db_1.db.collection(`users/${uid}/strategic_objectives`).doc(strategicObjectiveId)
            .update({ projectIds: db_1.FieldValue.arrayUnion(projectId) });
    }
    const isUpdate = !!project.id;
    // B7 : à la création, signaler un projet actif au titre proche sur la même période.
    let dupWarning = "";
    if (!isUpdate) {
        try {
            const all = (await loadAuditProjects(uid)).filter((p) => p.status === "active" && !p.paused && p.id !== projectId);
            const me = toAuditProject(projectId, Object.assign(Object.assign({}, pickedProject), { status: "active" }));
            const twins = (0, project_audit_1.similarProjects)(me, all);
            if (twins.length) {
                dupWarning = `⚠️ Doublon possible : ${twins.map((t) => `« ${t.title} » (${t.id})`).join(", ")} couvre la même période avec un titre proche. ` +
                    `Si c'est le même projet, fusionne (déplace les tâches puis archive_project) ou rattache l'un à l'autre (update_project parentProjectId).\n`;
            }
        }
        catch ( /* la détection ne doit jamais bloquer la création */_d) { /* la détection ne doit jamais bloquer la création */ }
    }
    const pickedPhaseIds = new Set(((_a = pickedProject.phases) !== null && _a !== void 0 ? _a : []).map((p) => String(p.id)));
    const unphased = ((_b = pickedProject.tasks) !== null && _b !== void 0 ? _b : [])
        .filter((t) => { var _a; return pickedPhaseIds.size > 0 && !pickedPhaseIds.has(String((_a = t.phaseId) !== null && _a !== void 0 ? _a : "")); });
    const phaseWarning = unphased.length
        ? `⚠️ ${unphased.length} tâche(s) sans phase (groupLabel ≠ libellé d'une phase) : ` +
            `${unphased.slice(0, 5).map((t) => `« ${t.title} »`).join(", ")}${unphased.length > 5 ? "…" : ""}. ` +
            `Reprends-les avec update_task {phaseId: <libellé ou id de phase>}.\n`
        : "";
    const descLen = ((_c = project.description) !== null && _c !== void 0 ? _c : "").length;
    const verboseWarning = descLen > 600
        ? `⚠️ Description longue (${descLen} caractères) — la fiche la tronque à 4 lignes. ` +
            `Déplace le détail dans un document du projet (save_document, category 'notes').\n`
        : "";
    const statusLine = isUpdate
        ? ""
        : `• statut : ${(opts === null || opts === void 0 ? void 0 : opts.draftOnCreate)
            ? "brouillon (à valider dans l'app)" : "actif"}\n`;
    return (`✅ Projet "${project.title}" ${isUpdate ? "mis à jour" : "créé"} dans Productivitwo !\n` +
        verboseWarning + phaseWarning + dupWarning +
        `• ${(project.tasks || []).length} tâche(s) · ${(project.phases || []).length} phase(s)\n` +
        statusLine +
        `• Voir sur : https://app.productivitwo.com\n` +
        `• projectId : ${projectId}`);
}
async function executeAddTask(uid, projectId, task) {
    var _a;
    const ref = db_1.db.collection(`users/${uid}/projects`).doc(projectId);
    const snap = await ref.get();
    if (!snap.exists)
        return `Projet introuvable : ${projectId}`;
    let newTask;
    try {
        newTask = pickTask(task);
    }
    catch (e) {
        return `❌ Tâche invalide : ${e instanceof Error ? e.message : String(e)}`;
    }
    // phaseId par libellé (ou groupLabel) : voir phase_resolve.ts.
    const phases = (_a = snap.data().phases) !== null && _a !== void 0 ? _a : [];
    const res = (0, phase_resolve_1.resolvePhaseIds)(phases, [newTask]);
    newTask = res.tasks[0];
    const phaseNote = res.unknown.length
        ? ` ⚠️ phaseId « ${res.unknown[0]} » inconnu — tâche sans phase (libellés : ${phases.map((p) => p.label).join(", ")}).`
        : phases.length > 0 && !newTask.phaseId ? " ⚠️ sans phase (passe phaseId = libellé ou id d'une phase)." : "";
    // arrayUnion est atomique et ne nécessite pas de lire/réécrire le tableau entier
    await ref.update({
        tasks: db_1.FieldValue.arrayUnion(newTask),
        updatedAt: db_1.FieldValue.serverTimestamp(),
    });
    return `✅ Tâche "${newTask.title}" ajoutée au projet (id: ${newTask.id}).${phaseNote}`;
}
async function executeUpdateTask(uid, projectId, taskId, updates) {
    var _a, _b, _c, _d, _e, _f, _g, _h, _j, _l;
    const ref = db_1.db.collection(`users/${uid}/projects`).doc(projectId);
    const snap = await ref.get();
    if (!snap.exists)
        return `Projet introuvable : ${projectId}`;
    const data = snap.data();
    // Sanitize Timestamps → ISO strings pour éviter les erreurs de re-sérialisation
    const rawTasks = (data.tasks || []);
    let interventionNote = "";
    let tasks = rawTasks.map((t) => JSON.parse(JSON.stringify(t, (_k, v) => v && typeof v === "object" && typeof v.toDate === "function"
        ? v.toDate().toISOString()
        : v)));
    const idx = tasks.findIndex((t) => t.id === taskId);
    if (idx === -1)
        return `Tâche introuvable : ${taskId}`;
    try {
        const patch = {};
        if (updates.title !== undefined)
            patch.title = clampStr(updates.title, 200, "title");
        if (updates.description !== undefined) {
            const d = clampStr(updates.description, 5000, "description");
            patch.description = d.trim() ? d : null;
        }
        if (updates.startDate !== undefined) {
            assertDate(updates.startDate, "startDate");
            patch.startDate = updates.startDate;
        }
        if (updates.endDate !== undefined) {
            assertDate(updates.endDate, "endDate");
            patch.endDate = updates.endDate;
        }
        if (updates.status !== undefined) {
            if (!TASK_STATUSES.has(updates.status))
                throw new Error(`status invalide : "${updates.status}"`);
            patch.status = updates.status;
        }
        if (updates.phaseId !== undefined) {
            const phases = (_a = data.phases) !== null && _a !== void 0 ? _a : [];
            const r = (0, phase_resolve_1.resolvePhaseIds)(phases, [{ phaseId: updates.phaseId }]);
            if (r.unknown.length) {
                throw new Error(`phaseId inconnu : "${updates.phaseId}" (phases : ${phases.map((p) => `${p.label} = ${p.id}`).join(" · ") || "aucune"})`);
            }
            patch.phaseId = r.tasks[0].phaseId;
        }
        if (updates.groupLabel !== undefined)
            patch.groupLabel = updates.groupLabel;
        if (updates.isMilestone !== undefined)
            patch.isMilestone = updates.isMilestone;
        if (updates.color !== undefined)
            patch.color = updates.color;
        if (updates.barLabel !== undefined)
            patch.barLabel = updates.barLabel;
        // null = effacer l'estimation (retour au défaut de l'app).
        if (updates.estimatedMin !== undefined) {
            patch.estimatedMin = (_b = estimatedMinOrUndefined(updates.estimatedMin)) !== null && _b !== void 0 ? _b : null;
        }
        if (updates.actions !== undefined) {
            // Remplace les sous-actions, mais préserve l'état done par match de titre
            // pour ne pas perdre la progression de l'utilisateur en cas de simple
            // renommage ou réordonnancement.
            const rawActions = Array.isArray(updates.actions) ? updates.actions : [];
            const oldActions = (_c = tasks[idx].actions) !== null && _c !== void 0 ? _c : [];
            const oldByTitle = {};
            for (const a of oldActions) {
                const t = (_d = a.title) !== null && _d !== void 0 ? _d : "";
                if (t) {
                    oldByTitle[t] = {
                        done: (_e = a.done) !== null && _e !== void 0 ? _e : false,
                        doneAt: (_f = a.doneAt) !== null && _f !== void 0 ? _f : null,
                        id: a.id,
                        linkedActivityId: (_g = a.linkedActivityId) !== null && _g !== void 0 ? _g : null,
                        context: (_h = a.context) !== null && _h !== void 0 ? _h : null,
                        contexts: Array.isArray(a.contexts) ? a.contexts : [],
                        estimatedMin: (_j = estimatedMinOrUndefined(a.estimatedMin)) !== null && _j !== void 0 ? _j : null,
                        checklist: Array.isArray(a.checklist)
                            ? a.checklist : [],
                    };
                }
            }
            patch.actions = rawActions.map((a) => {
                var _a, _b, _c, _d, _e, _f, _g, _h, _j, _l, _m;
                const obj = typeof a === "object" && a !== null ? a : null;
                const title = typeof a === "string"
                    ? a
                    : (obj && "title" in obj ? String(obj.title) : "");
                const previous = oldByTitle[title];
                return withBothContexts({
                    id: (_a = previous === null || previous === void 0 ? void 0 : previous.id) !== null && _a !== void 0 ? _a : (0, uuid_1.v4)(),
                    title,
                    done: (_b = previous === null || previous === void 0 ? void 0 : previous.done) !== null && _b !== void 0 ? _b : false,
                    doneAt: (_c = previous === null || previous === void 0 ? void 0 : previous.doneAt) !== null && _c !== void 0 ? _c : null,
                    createdAt: new Date().toISOString(),
                    // Préserve le lien chrono et le contexte GTD d'une action conservée
                    // (le payload peut aussi poser linkedActivityId/context explicites).
                    linkedActivityId: (_e = (_d = obj === null || obj === void 0 ? void 0 : obj.linkedActivityId) !== null && _d !== void 0 ? _d : previous === null || previous === void 0 ? void 0 : previous.linkedActivityId) !== null && _e !== void 0 ? _e : null,
                    context: (_g = (_f = obj === null || obj === void 0 ? void 0 : obj.context) !== null && _f !== void 0 ? _f : previous === null || previous === void 0 ? void 0 : previous.context) !== null && _g !== void 0 ? _g : null,
                    contexts: Array.isArray(obj === null || obj === void 0 ? void 0 : obj.contexts)
                        ? obj === null || obj === void 0 ? void 0 : obj.contexts
                        : (_h = previous === null || previous === void 0 ? void 0 : previous.contexts) !== null && _h !== void 0 ? _h : [],
                    estimatedMin: (_l = (_j = estimatedMinOrUndefined(obj === null || obj === void 0 ? void 0 : obj.estimatedMin)) !== null && _j !== void 0 ? _j : previous === null || previous === void 0 ? void 0 : previous.estimatedMin) !== null && _l !== void 0 ? _l : (0, default_estimates_1.defaultEstimateFor)(title, Array.isArray(obj === null || obj === void 0 ? void 0 : obj.contexts) ? obj.contexts : []),
                    // Checklist fournie → normalisée ; sinon celle de l'action conservée.
                    checklist: Array.isArray(obj === null || obj === void 0 ? void 0 : obj.checklist)
                        ? normalizeChecklist(obj.checklist)
                        : (_m = previous === null || previous === void 0 ? void 0 : previous.checklist) !== null && _m !== void 0 ? _m : [],
                });
            });
        }
        tasks[idx] = Object.assign(Object.assign({}, tasks[idx]), patch);
        // Rattachement à une intervention (spec 2026-10) : "" = détacher ; un rôle
        // principal déjà tenu = refus nommant la tâche en place ; dates intactes.
        const u = updates;
        if (u.interventionId !== undefined) {
            const r = (0, interventions_1.attachTask)(tasks, sanitizeTasks(data.interventions), taskId, String((_l = u.interventionId) !== null && _l !== void 0 ? _l : ""), u.interventionRole);
            tasks = r.tasks;
            interventionNote = ` · ${r.note}`;
        }
        else if (u.interventionRole !== undefined && tasks[idx].interventionId) {
            const r = (0, interventions_1.attachTask)(tasks, sanitizeTasks(data.interventions), taskId, String(tasks[idx].interventionId), u.interventionRole);
            tasks = r.tasks;
            interventionNote = ` · rôle ${u.interventionRole}`;
        }
    }
    catch (e) {
        return `❌ Mise à jour invalide : ${e instanceof Error ? e.message : String(e)}`;
    }
    await ref.update({ tasks, updatedAt: db_1.FieldValue.serverTimestamp() });
    return `✅ Tâche "${tasks[idx].title}" mise à jour.${interventionNote}`;
}
async function executeMarkActionDone(uid, projectId, taskId, actionId, done) {
    var _a, _b;
    const ref = db_1.db.collection(`users/${uid}/projects`).doc(projectId);
    const snap = await ref.get();
    if (!snap.exists)
        return `Projet introuvable : ${projectId}`;
    const data = snap.data();
    // Sanitize Timestamps → ISO strings pour éviter les erreurs de re-sérialisation
    const rawTasks = (data.tasks || []);
    const tasks = rawTasks.map((t) => JSON.parse(JSON.stringify(t, (_k, v) => v && typeof v === "object" && typeof v.toDate === "function"
        ? v.toDate().toISOString()
        : v)));
    const taskIdx = tasks.findIndex((t) => t.id === taskId);
    if (taskIdx === -1)
        return `Tâche introuvable : ${taskId}`;
    const actions = ((_a = tasks[taskIdx].actions) !== null && _a !== void 0 ? _a : []).slice();
    const actionIdx = actions.findIndex((a) => a.id === actionId);
    if (actionIdx === -1)
        return `Sous-action introuvable : ${actionId}`;
    const actionTitle = (_b = actions[actionIdx].title) !== null && _b !== void 0 ? _b : actionId;
    const wasDone = actions[actionIdx].done === true;
    if (wasDone === done) {
        return `✅ Sous-action "${actionTitle}" déjà ${done ? "faite" : "ouverte"} — inchangée.`;
    }
    actions[actionIdx] = Object.assign(Object.assign({}, actions[actionIdx]), { done, doneAt: done ? new Date().toISOString() : null });
    tasks[taskIdx] = Object.assign(Object.assign({}, tasks[taskIdx]), { actions });
    await ref.update({ tasks, updatedAt: db_1.FieldValue.serverTimestamp() });
    return `✅ Sous-action "${actionTitle}" ${done ? "marquée faite" : "rouverte"}.`;
}
// Coche/décoche un item de checklist. Règle d'achèvement : tous les items
// cochés → l'action passe faite ; décocher un item d'une action faite la rouvre.
async function executeMarkChecklistItem(uid, projectId, taskId, actionId, itemId, done) {
    var _a, _b;
    const ref = db_1.db.collection(`users/${uid}/projects`).doc(projectId);
    const snap = await ref.get();
    if (!snap.exists)
        return `Projet introuvable : ${projectId}`;
    const data = snap.data();
    const rawTasks = (data.tasks || []);
    const tasks = rawTasks.map((t) => JSON.parse(JSON.stringify(t, (_k, v) => v && typeof v === "object" && typeof v.toDate === "function"
        ? v.toDate().toISOString()
        : v)));
    const taskIdx = tasks.findIndex((t) => t.id === taskId);
    if (taskIdx === -1)
        return `Tâche introuvable : ${taskId}`;
    const actions = ((_a = tasks[taskIdx].actions) !== null && _a !== void 0 ? _a : []).slice();
    const actionIdx = actions.findIndex((a) => a.id === actionId);
    if (actionIdx === -1)
        return `Sous-action introuvable : ${actionId}`;
    const items = (Array.isArray(actions[actionIdx].checklist)
        ? actions[actionIdx].checklist : []).slice();
    const itemIdx = items.findIndex((c) => c.id === itemId);
    if (itemIdx === -1)
        return `Item de checklist introuvable : ${itemId}`;
    const now = new Date().toISOString();
    items[itemIdx] = Object.assign(Object.assign({}, items[itemIdx]), { done, doneAt: done ? now : null });
    const allDone = items.length > 0 && items.every((c) => c.done === true);
    const wasDone = actions[actionIdx].done === true;
    const action = Object.assign(Object.assign({}, actions[actionIdx]), { checklist: items });
    let note = "";
    if (allDone && !wasDone) {
        action.done = true;
        action.doneAt = now;
        note = " · tous les items cochés → action marquée faite";
    }
    else if (!done && wasDone) {
        action.done = false;
        action.doneAt = null;
        note = " · action rouverte";
    }
    actions[actionIdx] = action;
    tasks[taskIdx] = Object.assign(Object.assign({}, tasks[taskIdx]), { actions });
    await ref.update({ tasks, updatedAt: db_1.FieldValue.serverTimestamp() });
    const title = (_b = items[itemIdx].title) !== null && _b !== void 0 ? _b : itemId;
    const n = items.filter((c) => c.done === true).length;
    return `✅ Item "${title}" ${done ? "coché" : "décoché"} (${n}/${items.length})${note}.`;
}
// Associe une sous-action de tâche (TaskAction) à une activité-temps : pose
// linkedActivityId → le chrono lancé depuis cette action est ciblé (la session
// pointe dessus). À proposer quand une action n'est pas déjà liée et qu'une
// activité-temps du même domaine existe.
async function executeLinkActionToActivity(uid, projectId, taskId, actionId, activityId) {
    var _a, _b, _c, _d;
    const actSnap = await db_1.db.collection(`users/${uid}/activities`).doc(activityId).get();
    if (!actSnap.exists)
        return `Activité introuvable : ${activityId}`;
    const actData = actSnap.data();
    if (actData.deleted === true)
        return `Activité supprimée : ${activityId}`;
    if (actData.type !== "time")
        return `L'activité "${(_a = actData.name) !== null && _a !== void 0 ? _a : activityId}" n'est pas une activité-temps — impossible de chronométrer une action dessus.`;
    const ref = db_1.db.collection(`users/${uid}/projects`).doc(projectId);
    const snap = await ref.get();
    if (!snap.exists)
        return `Projet introuvable : ${projectId}`;
    const data = snap.data();
    const rawTasks = (data.tasks || []);
    const tasks = rawTasks.map((t) => JSON.parse(JSON.stringify(t, (_k, v) => v && typeof v === "object" && typeof v.toDate === "function" ? v.toDate().toISOString() : v)));
    const taskIdx = tasks.findIndex((t) => t.id === taskId);
    if (taskIdx === -1)
        return `Tâche introuvable : ${taskId}`;
    const actions = ((_b = tasks[taskIdx].actions) !== null && _b !== void 0 ? _b : []).slice();
    const actionIdx = actions.findIndex((a) => a.id === actionId);
    if (actionIdx === -1)
        return `Sous-action introuvable : ${actionId}`;
    actions[actionIdx] = Object.assign(Object.assign({}, actions[actionIdx]), { linkedActivityId: activityId });
    tasks[taskIdx] = Object.assign(Object.assign({}, tasks[taskIdx]), { actions });
    await ref.update({ tasks, updatedAt: db_1.FieldValue.serverTimestamp() });
    const actionTitle = (_c = actions[actionIdx].title) !== null && _c !== void 0 ? _c : actionId;
    return `🔗 Action "${actionTitle}" liée à l'activité "${(_d = actData.name) !== null && _d !== void 0 ? _d : activityId}" — le chrono lancé dessus sera ciblé.`;
}
async function loadTimeInsights(uid, days) {
    const sinceMs = Date.now() - days * 86400000;
    // Les sessions remontent 60 j avant la fenêtre : une action terminée dans la
    // période a pu être commencée avant.
    const sessionsSince = new Date(sinceMs - 60 * 86400000).toISOString();
    const [projSnap, actSnap, sessSnap] = await Promise.all([
        db_1.db.collection(`users/${uid}/projects`).get(),
        db_1.db.collection(`users/${uid}/activities`).get(),
        db_1.db.collection(`users/${uid}/sessions`).where("startAt", ">=", sessionsSince).get(),
    ]);
    const entries = (0, estimates_1.timeEntries)(projSnap.docs.map((d) => { var _a; return (Object.assign(Object.assign({}, d.data()), { id: (_a = d.data().id) !== null && _a !== void 0 ? _a : d.id })); }), actSnap.docs.map((d) => { var _a; return (Object.assign(Object.assign({}, d.data()), { id: (_a = d.data().id) !== null && _a !== void 0 ? _a : d.id })); }), (0, sessions_audit_1.liveSessionDocs)(sessSnap).map((d) => d.data()));
    const measuredEntries = (0, estimates_1.measured)(entries, sinceMs);
    return { days, entries, measuredEntries, calibration: (0, estimates_1.calibrate)(measuredEntries) };
}
function entryLine(e, withRef) {
    const est = e.estimatedMin === null ? "sans estimation" : `estimé ${(0, estimates_1.fmtMin)(e.estimatedMin)}`;
    const ratio = e.estimatedMin ? ` (${(0, estimates_1.fmtFactor)(Math.round((e.spentMin / e.estimatedMin) * 100) / 100)})` : "";
    const ctx = e.contexts.length ? ` · ${e.contexts.join(" ")}` : "";
    return `- « ${e.title} » (${e.holder}) : ${est} · réel ${(0, estimates_1.fmtMin)(e.spentMin)}${ratio}${ctx}` +
        (withRef ? ` [${(0, estimates_1.refLabel)(e.ref)}]` : "");
}
async function executeEstimateAccuracy(uid, args) {
    var _a, _b;
    const days = Math.min(365, Math.max(7, Math.round((_a = args.days) !== null && _a !== void 0 ? _a : 90)));
    const limit = Math.min(50, Math.max(1, Math.round((_b = args.limit) !== null && _b !== void 0 ? _b : 15)));
    const ti = await loadTimeInsights(uid, days);
    const c = ti.calibration;
    const recent = [...ti.measuredEntries]
        .sort((a, b) => { var _a, _b; return ((_a = b.doneAt) !== null && _a !== void 0 ? _a : "").localeCompare((_b = a.doneAt) !== null && _b !== void 0 ? _b : ""); })
        .slice(0, limit);
    const over = (0, estimates_1.overBudget)(ti.entries).slice(0, limit);
    const unest = (0, estimates_1.workedUnestimated)(ti.entries).slice(0, limit);
    const doneTasks = ti.entries.filter((e) => e.ref.kind === "task" && e.done && e.estimatedMin !== null && e.spentMin > 0);
    const lines = [
        `⏱️ ESTIMÉ vs RÉEL — ${days} derniers jours`,
        `Temps réel = chrono ciblé sur l'action (sessions). Les blocs cochés sans chrono ne comptent pas.`,
        ``,
        (0, estimates_1.calibrationHeadline)(c),
        `→ ${(0, estimates_1.adviceLine)(c)}`,
    ];
    if (c.byContext.length) {
        lines.push(`Par contexte (≥ 3 mesures) : ${c.byContext.map((x) => `${x.context} ${(0, estimates_1.fmtFactor)(x.factor)} (${x.n})`).join(" · ")}`);
    }
    if (c.byHolder.length) {
        lines.push(`Par projet/activité (≥ 3 mesures) : ${c.byHolder.map((x) => `${x.holder} ${(0, estimates_1.fmtFactor)(x.factor)} (${x.n})`).join(" · ")}`);
    }
    if (doneTasks.length) {
        lines.push(``, `Tâches terminées (estimation de tâche vs temps chronométré sur la tâche) :`, ...doneTasks.slice(0, limit).map((e) => entryLine(e, false)));
    }
    lines.push(``, `Mesures récentes :`, ...(recent.length ? recent.map((e) => entryLine(e, false)) : ["- (aucune)"]));
    if (over.length) {
        lines.push(``, `En cours, déjà au-delà de l'estimation (réestimer le reste via update_action) :`, ...over.map((e) => entryLine(e, true)));
    }
    if (unest.length) {
        lines.push(``, `Travaillées sans estimation (poser estimatedMin via update_action) :`, ...unest.map((e) => entryLine(e, true)));
    }
    return lines.join("\n");
}
/** Bloc compact pour plan_day : facteur + consignes d'estimation. */
async function planDayTimeBlock(uid) {
    try {
        const ti = await loadTimeInsights(uid, 90);
        const c = ti.calibration;
        const over = (0, estimates_1.overBudget)(ti.entries).slice(0, 5);
        const unest = (0, estimates_1.workedUnestimated)(ti.entries).slice(0, 5);
        return [
            ``,
            `── ESTIMÉ vs RÉEL (90 j, chrono ciblé) ──`,
            (0, estimates_1.calibrationHeadline)(c),
            `→ ${(0, estimates_1.adviceLine)(c)}`,
            ...(c.byContext.length
                ? [`Par contexte : ${c.byContext.map((x) => `${x.context} ${(0, estimates_1.fmtFactor)(x.factor)}`).join(" · ")}`]
                : []),
            ...(over.length ? [`Déjà au-delà de l'estimation :`, ...over.map((e) => entryLine(e, true))] : []),
            ...(unest.length ? [`Travaillées sans estimation :`, ...unest.map((e) => entryLine(e, true))] : []),
        ];
    }
    catch (_a) {
        return [];
    }
}
/** B4 : plusieurs retouches d'actions en UN appel (un seul tick de rate limit).
 *  Chaque entrée = les arguments d'update_action ; les erreurs n'arrêtent pas le lot. */
async function executeUpdateActions(uid, args) {
    const list = Array.isArray(args.updates) ? args.updates : [];
    if (!list.length)
        return "❌ updates[] requis (1 à 50 entrées, mêmes champs qu'update_action).";
    if (list.length > 50)
        return `❌ 50 entrées max par appel (${list.length} reçues) — découpe en plusieurs lots.`;
    const out = [];
    let ok = 0;
    for (const [i, u] of list.entries()) {
        try {
            const r = await executeUpdateAction(uid, u);
            if (r.startsWith("✏️") || r.startsWith("🗑") || r.includes("rien à changer"))
                ok++;
            out.push(`${i + 1}. ${r}`);
        }
        catch (e) {
            out.push(`${i + 1}. ❌ ${e instanceof Error ? e.message : String(e)}`);
        }
    }
    return `📦 Lot de ${list.length} retouche(s) — ${ok} appliquée(s) :\n${out.join("\n")}`;
}
async function executeUpdateAction(uid, args) {
    var _a, _b, _c, _d, _e, _f, _g;
    if (!args.actionId)
        return "actionId requis.";
    const own = !!args.activityId;
    if (!own && !(args.projectId && args.taskId)) {
        return "Cible requise : activityId (action propre) OU projectId + taskId (sous-action de projet).";
    }
    const patch = {};
    if (args.title !== undefined)
        patch.title = args.title;
    if (args.contexts !== undefined)
        patch.contexts = args.contexts;
    if (args.addContexts !== undefined)
        patch.addContexts = args.addContexts;
    if (args.removeContexts !== undefined)
        patch.removeContexts = args.removeContexts;
    if (args.clearEstimate === true)
        patch.estimatedMin = null;
    else if (args.estimatedMin !== undefined)
        patch.estimatedMin = args.estimatedMin;
    if (args.done !== undefined)
        patch.done = args.done;
    if (args.linkedActivityId !== undefined) {
        if (own)
            return "linkedActivityId ne s'applique qu'aux sous-actions de projet (une action propre est déjà portée par son activité).";
        patch.linkedActivityId = args.linkedActivityId;
    }
    if (patch.linkedActivityId) {
        const actSnap = await db_1.db.collection(`users/${uid}/activities`).doc(patch.linkedActivityId).get();
        const actData = actSnap.exists ? actSnap.data() : null;
        if (!actData || actData.deleted === true)
            return `Activité introuvable : ${patch.linkedActivityId}`;
        if (actData.type !== "time")
            return `L'activité "${(_a = actData.name) !== null && _a !== void 0 ? _a : patch.linkedActivityId}" n'est pas une activité-temps.`;
    }
    const sanitize = (v) => JSON.parse(JSON.stringify(v, (_k, x) => x && typeof x === "object" && typeof x.toDate === "function" ? x.toDate().toISOString() : x));
    const summary = (title, changes, holder) => changes.length
        ? `✏️ « ${title} » (${holder}) : ${changes.join(" · ")}.`
        : `« ${title} » (${holder}) : rien à changer.`;
    if (own) {
        const ref = db_1.db.collection(`users/${uid}/activities`).doc(args.activityId);
        const snap = await ref.get();
        if (!snap.exists)
            return `Activité introuvable : ${args.activityId}`;
        const data = snap.data();
        if (data.deleted === true)
            return `Activité supprimée : ${args.activityId}`;
        const list = sanitize(Array.isArray(data.ownActions) ? data.ownActions : []);
        const idx = list.findIndex((a) => a.id === args.actionId);
        if (idx === -1)
            return `Action propre introuvable : ${args.actionId}`;
        const title = (_b = list[idx].title) !== null && _b !== void 0 ? _b : args.actionId;
        const holder = `activité ${(_c = data.name) !== null && _c !== void 0 ? _c : args.activityId}`;
        if (args.delete === true) {
            list.splice(idx, 1);
            await ref.update({ ownActions: list });
            return `🗑️ Action propre « ${title} » supprimée (${holder}).`;
        }
        const r = (0, action_patch_1.applyActionPatch)(list[idx], patch);
        if (r.changes.length === 0)
            return summary(title, [], holder);
        list[idx] = r.action;
        await ref.update({ ownActions: list });
        return summary(title, r.changes, holder);
    }
    const ref = db_1.db.collection(`users/${uid}/projects`).doc(args.projectId);
    const snap = await ref.get();
    if (!snap.exists)
        return `Projet introuvable : ${args.projectId}`;
    const data = snap.data();
    const tasks = sanitize(Array.isArray(data.tasks) ? data.tasks : []);
    const taskIdx = tasks.findIndex((t) => t.id === args.taskId);
    if (taskIdx === -1)
        return `Tâche introuvable : ${args.taskId}`;
    const actions = ((_d = tasks[taskIdx].actions) !== null && _d !== void 0 ? _d : []).slice();
    const actionIdx = actions.findIndex((a) => a.id === args.actionId);
    if (actionIdx === -1)
        return `Sous-action introuvable : ${args.actionId}`;
    const title = (_e = actions[actionIdx].title) !== null && _e !== void 0 ? _e : args.actionId;
    const holder = `${(_f = data.title) !== null && _f !== void 0 ? _f : args.projectId} › ${(_g = tasks[taskIdx].title) !== null && _g !== void 0 ? _g : args.taskId}`;
    if (args.delete === true) {
        actions.splice(actionIdx, 1);
        tasks[taskIdx] = Object.assign(Object.assign({}, tasks[taskIdx]), { actions });
        await ref.update({ tasks, updatedAt: db_1.FieldValue.serverTimestamp() });
        return `🗑️ Sous-action « ${title} » supprimée (${holder}).`;
    }
    const r = (0, action_patch_1.applyActionPatch)(actions[actionIdx], patch);
    if (r.changes.length === 0)
        return summary(title, [], holder);
    actions[actionIdx] = r.action;
    tasks[taskIdx] = Object.assign(Object.assign({}, tasks[taskIdx]), { actions });
    await ref.update({ tasks, updatedAt: db_1.FieldValue.serverTimestamp() });
    return summary(title, r.changes, holder);
}
// ── Contextes GTD : list / add / rename / delete ─────────────────────────────
async function executeManageContexts(uid, args) {
    const metaRef = db_1.db.doc(`users/${uid}/data/meta`);
    const metaSnap = await metaRef.get();
    const meta = (metaSnap.exists ? metaSnap.data() : {});
    const customs = (Array.isArray(meta.customContexts) ? meta.customContexts : [])
        .filter((c) => typeof c === "string" && c.trim() !== "")
        .filter((c) => !contexts_1.DEFAULT_GTD_CONTEXTS.includes(c));
    const known = [...contexts_1.DEFAULT_GTD_CONTEXTS, ...customs];
    // Toutes les actions : projets (tâches) + activités (actions propres).
    const [projSnap, actSnap] = await Promise.all([
        db_1.db.collection(`users/${uid}/projects`).get(),
        db_1.db.collection(`users/${uid}/activities`).get(),
    ]);
    const projectDocs = projSnap.docs.map((d) => ({ ref: d.ref, data: d.data() }));
    const activityDocs = actSnap.docs
        .map((d) => ({ ref: d.ref, data: d.data() }))
        .filter((d) => d.data.deleted !== true);
    const tasksOf = (p) => (Array.isArray(p.tasks) ? p.tasks : []);
    const actionsOf = (t) => (Array.isArray(t.actions) ? t.actions : []);
    const ownOf = (a) => (Array.isArray(a.ownActions) ? a.ownActions : []);
    const plural = (n, s) => `${n} ${s}${n > 1 ? "s" : ""}`;
    if (args.action === "list") {
        const usage = new Map();
        for (const p of projectDocs) {
            if (p.data.status === "archived" || p.data.status === "deleted")
                continue;
            for (const t of tasksOf(p.data))
                (0, contexts_1.countContextUsage)(actionsOf(t), usage);
        }
        for (const a of activityDocs)
            (0, contexts_1.countContextUsage)(ownOf(a.data), usage);
        const line = (c) => {
            var _a;
            const u = (_a = usage.get(c)) !== null && _a !== void 0 ? _a : { open: 0, done: 0 };
            return `- ${c} — ${plural(u.open, "ouverte")}, ${plural(u.done, "faite")}`;
        };
        const orphans = [...usage.keys()].filter((c) => !known.includes(c)).sort();
        return [
            `🏷️ CONTEXTES GTD (${known.length})`,
            ``,
            `Par défaut (fixes) :`,
            ...contexts_1.DEFAULT_GTD_CONTEXTS.map(line),
            ``,
            `Personnalisés (${customs.length}) :`,
            ...(customs.length ? customs.map(line) : ["- (aucun)"]),
            ...(orphans.length
                ? [``, `Orphelins (portés par des actions mais absents de la liste — add pour les réintégrer, rename pour les fusionner) :`, ...orphans.map(line)]
                : []),
        ].join("\n");
    }
    const ctx = (0, contexts_1.normalizeContext)(args.context);
    if (!ctx)
        return "Contexte requis (ex. @atelier).";
    if (args.action === "add") {
        if (known.includes(ctx))
            return `Le contexte ${ctx} existe déjà.`;
        await metaRef.set({ customContexts: db_1.FieldValue.arrayUnion(ctx) }, { merge: true });
        return `✅ Contexte ${ctx} créé. Il apparaît dans « Je suis… » et sur les actions dès la prochaine synchro.`;
    }
    if (contexts_1.DEFAULT_GTD_CONTEXTS.includes(ctx)) {
        return `${ctx} est un contexte par défaut : il ne se renomme ni ne se supprime.`;
    }
    // Propagation sur toutes les actions (projets + activités), un write par doc touché.
    const propagate = async (fn) => {
        let changedActions = 0;
        let changedDocs = 0;
        const batch = db_1.db.batch();
        for (const p of projectDocs) {
            let touched = 0;
            const tasks = tasksOf(p.data).map((t) => {
                const r = fn(actionsOf(t));
                if (r.changed === 0)
                    return t;
                touched += r.changed;
                return Object.assign(Object.assign({}, t), { actions: r.actions });
            });
            if (touched > 0) {
                batch.update(p.ref, { tasks, updatedAt: db_1.FieldValue.serverTimestamp() });
                changedActions += touched;
                changedDocs++;
            }
        }
        for (const a of activityDocs) {
            const r = fn(ownOf(a.data));
            if (r.changed === 0)
                continue;
            batch.update(a.ref, { ownActions: r.actions });
            changedActions += r.changed;
            changedDocs++;
        }
        if (changedDocs > 0)
            await batch.commit();
        return { changedActions, changedDocs };
    };
    if (args.action === "rename") {
        const to = (0, contexts_1.normalizeContext)(args.newContext);
        if (!to)
            return "Nouveau nom requis (newContext).";
        if (to === ctx)
            return "Même nom : rien à faire.";
        const isCustom = customs.includes(ctx);
        const nextCustoms = [...new Set(customs.map((c) => (c === ctx ? to : c)))]
            .filter((c) => !contexts_1.DEFAULT_GTD_CONTEXTS.includes(c));
        if (!isCustom && !known.includes(to) && !nextCustoms.includes(to))
            nextCustoms.push(to); // orphelin réintégré
        await metaRef.set({ customContexts: nextCustoms }, { merge: true });
        const r = await propagate((actions) => (0, contexts_1.renameContextInActions)(actions, ctx, to));
        const merged = known.includes(to) ? " (fusionné avec le contexte existant)" : "";
        return `✏️ ${ctx} → ${to}${merged} · ${plural(r.changedActions, "action")} mise(s) à jour dans ${r.changedDocs} projet(s)/activité(s).`;
    }
    if (args.action === "delete") {
        if (!customs.includes(ctx))
            return `Contexte personnalisé introuvable : ${ctx} (action list pour voir la liste).`;
        await metaRef.set({ customContexts: db_1.FieldValue.arrayRemove(ctx) }, { merge: true });
        if (args.detach === true) {
            const r = await propagate((actions) => (0, contexts_1.removeContextFromActions)(actions, ctx));
            return `🗑️ ${ctx} supprimé et retiré de ${plural(r.changedActions, "action")}.`;
        }
        const usage = new Map();
        for (const p of projectDocs)
            for (const t of tasksOf(p.data))
                (0, contexts_1.countContextUsage)(actionsOf(t), usage);
        for (const a of activityDocs)
            (0, contexts_1.countContextUsage)(ownOf(a.data), usage);
        const u = usage.get(ctx);
        const left = u ? u.open + u.done : 0;
        return `🗑️ ${ctx} retiré de la liste.${left > 0 ? ` ${plural(left, "action")} le garde(nt) comme simple tag (delete avec detach=true pour l'enlever aussi).` : ""}`;
    }
    return `Action inconnue : ${args.action} (list | add | rename | delete).`;
}
// Crée une action PROPRE sur une activité (Activity.ownActions) : une TaskAction
// qui appartient directement à l'activité, sans tâche/projet. Réutilisable ensuite
// dans schedule_day (activityId + actionId) pour la programmer.
async function executeAddActivityAction(uid, activityId, title, context, contexts, estimatedMin) {
    var _a;
    if (!(title === null || title === void 0 ? void 0 : title.trim()))
        return "Titre de l'action requis.";
    const ref = db_1.db.collection(`users/${uid}/activities`).doc(activityId);
    const snap = await ref.get();
    if (!snap.exists)
        return `Activité introuvable : ${activityId}`;
    const data = snap.data();
    if (data.deleted === true)
        return `Activité supprimée : ${activityId}`;
    const own = Array.isArray(data.ownActions)
        ? data.ownActions.slice()
        : [];
    const action = withBothContexts(Object.assign({ id: (0, uuid_1.v4)(), title: title.trim(), done: false, doneAt: null, createdAt: new Date().toISOString(), linkedActivityId: activityId, context: (context === null || context === void 0 ? void 0 : context.trim()) || null, contexts: Array.isArray(contexts) ? contexts : [] }, (() => {
        var _a;
        const est = (_a = estimatedMinOrUndefined(estimatedMin)) !== null && _a !== void 0 ? _a : (0, default_estimates_1.defaultEstimateFor)(title, [...(Array.isArray(contexts) ? contexts : []), context !== null && context !== void 0 ? context : ""]);
        return est !== undefined && est !== null ? { estimatedMin: est } : {};
    })()));
    own.push(action);
    await ref.update({ ownActions: own });
    const estNote = estimatedMinOrUndefined(estimatedMin) === undefined && typeof action.estimatedMin === "number"
        ? ` Estimation par défaut : ${action.estimatedMin} min (${(0, default_estimates_1.defaultEstimateLabel)(title, Array.isArray(contexts) ? contexts : [])}).`
        : "";
    return `✅ Action propre "${action.title}" créée sur "${(_a = data.name) !== null && _a !== void 0 ? _a : activityId}" (id: ${action.id}).${estNote} Tu peux la programmer via schedule_day (activityId: ${activityId}, actionId: ${action.id}).`;
}
async function executeLogRoutineHit(uid, activityId, delta = 1) {
    var _a;
    if (!activityId)
        return "activityId requis.";
    const dec = delta < 0;
    const ymd = todayInParis().replace(/-/g, "");
    const hpCol = db_1.db.collection(`users/${uid}/habitProgress`);
    // Compteur du jour (clé logique activityId + yyyymmdd, doc id = uuid).
    const existing = await hpCol
        .where("activityId", "==", activityId)
        .where("yyyymmdd", "==", ymd)
        .limit(1)
        .get();
    if (!existing.empty) {
        const doc = existing.docs[0];
        const cur = (_a = doc.data().value) !== null && _a !== void 0 ? _a : 0;
        await doc.ref.update({ value: Math.max(0, cur + (dec ? -1 : 1)) });
    }
    else if (!dec) {
        const id = (0, uuid_1.v4)();
        await hpCol.doc(id).set({ id, activityId, yyyymmdd: ymd, value: 1 });
    }
    const hitsCol = db_1.db.collection(`users/${uid}/habitHits`);
    if (dec) {
        // Retire le hit le plus récent du jour pour cette routine.
        // Requête à égalité seule (pas d'index composite) + tri en mémoire.
        const dayPrefix = todayInParis();
        const todayHits = (await hitsCol.where("habitId", "==", activityId).get()).docs
            .filter((doc) => { var _a; return String((_a = doc.data().ts) !== null && _a !== void 0 ? _a : "").startsWith(dayPrefix); })
            .sort((a, b) => String(b.data().ts).localeCompare(String(a.data().ts)));
        if (todayHits.length)
            await todayHits[0].ref.delete();
        return "↩️ Routine décrémentée pour aujourd'hui.";
    }
    // Trace du hit (historique des incréments).
    const hitId = (0, uuid_1.v4)();
    await hitsCol.doc(hitId).set({
        id: hitId,
        habitId: activityId,
        ts: new Date().toISOString(),
        contextActivityId: null,
    });
    return "✅ Routine incrémentée pour aujourd'hui.";
}
async function executeMarkBlockDone(uid, date, blockId, done) {
    var _a;
    if (!/^\d{4}-\d{2}-\d{2}$/.test(date))
        return `Date invalide : ${date}. Format attendu : YYYY-MM-DD`;
    const ref = db_1.db.doc(`users/${uid}/daily_schedules/${date}`);
    const snap = await ref.get();
    if (!snap.exists)
        return `Aucun programme pour le ${date}.`;
    const data = snap.data();
    const blocks = (data.blocks || []).slice();
    const idx = blocks.findIndex((b) => b.id === blockId);
    if (idx === -1)
        return `Bloc introuvable : ${blockId}`;
    const title = (_a = blocks[idx].title) !== null && _a !== void 0 ? _a : blockId;
    blocks[idx] = Object.assign(Object.assign({}, blocks[idx]), { status: done ? "done" : "pending", doneAt: done ? new Date().toISOString() : null });
    await ref.update({ blocks });
    return `✅ Bloc "${title}" ${done ? "marqué fait" : "remis à faire"}.`;
}
/** Sessions de chrono du jour (heure murale de l'app), pour reconnaître un
 *  bloc sur lequel un chrono réel a tourné (`blockHasSession`). */
async function readDaySessions(uid, date) {
    const snap = await db_1.db.collection(`users/${uid}/sessions`)
        .where("startAt", ">=", `${date}T00:00:00`)
        .where("startAt", "<=", `${date}T23:59:59.999`)
        .get();
    const out = [];
    for (const doc of (0, sessions_audit_1.liveSessionDocs)(snap)) {
        const v = doc.data();
        if (typeof v.startAt !== "string")
            continue;
        const sMs = (0, sessions_audit_1.wallMs)(v.startAt);
        const eMs = typeof v.endAt === "string" ? (0, sessions_audit_1.wallMs)(v.endAt) : (0, sessions_audit_1.wallMs)((0, sessions_audit_1.toWallIso)(Date.now()));
        const d0 = (0, sessions_audit_1.wallMs)(`${date}T00:00:00`);
        const startMin = Math.max(0, Math.floor((sMs - d0) / 60000));
        const endMin = Math.min(24 * 60, Math.ceil((eMs - d0) / 60000));
        if (endMin <= startMin)
            continue;
        out.push({
            startMin, endMin,
            taskId: typeof v.taskId === "string" ? v.taskId : null,
            activityId: typeof v.activityId === "string" ? v.activityId : null,
        });
    }
    return out;
}
const BLOCK_CATEGORIES = new Set(["project", "routine", "personal", "break"]);
const BLOCK_STATUSES = new Set(["pending", "done", "skipped", "deleted"]);
/** Retouche unitaire d'un bloc du programme : seuls les champs fournis
 *  changent ("" sur un lien = le retirer). Le reste du doc est intact. */
async function executeUpdateBlock(uid, date, blockId, updates) {
    var _a, _b, _c, _d, _e;
    if (!/^\d{4}-\d{2}-\d{2}$/.test(date))
        return `Date invalide : ${date}. Format attendu : YYYY-MM-DD`;
    if (updates.delete === true)
        updates = Object.assign(Object.assign({}, updates), { status: "deleted" });
    const ref = db_1.db.doc(`users/${uid}/daily_schedules/${date}`);
    const snap = await ref.get();
    if (!snap.exists)
        return `Aucun programme pour le ${date}.`;
    const data = snap.data();
    const blocks = (data.blocks || []).slice();
    const idx = blocks.findIndex((b) => b.id === blockId);
    if (idx === -1)
        return `Bloc introuvable : ${blockId}`;
    // Un miroir Google Agenda ne se saute ni ne se déplace ici : l'agenda est sa
    // source de vérité, il se déplace DANS l'agenda (la resync suit).
    const isMirror = blocks[idx].gcalEventId != null;
    if (isMirror && (updates.moveTo || updates.status === "skipped" || updates.status === "deleted")) {
        return `📅 « ${blocks[idx].title} » est un rendez-vous Google Agenda : il ne se saute pas et ne se déplace pas ` +
            `depuis Productivitwo. Déplace-le ou supprime-le dans l'agenda, le programme suivra à la prochaine synchronisation.`;
    }
    // B12 — déplacement ATOMIQUE : copie à destination (statut pending, lien
    // vers l'origine) + origine marquée « déplacée » (skipped/reporte + movedTo).
    // Un seul appel au lieu de skip ici + fill là-bas.
    if (updates.moveTo) {
        const mv = updates.moveTo;
        if (!/^\d{4}-\d{2}-\d{2}$/.test(String(mv.date)))
            return `moveTo.date : format YYYY-MM-DD attendu, reçu "${mv.date}"`;
        if (!/^([01]\d|2[0-3]):[0-5]\d$/.test(String(mv.startTime)))
            return `moveTo.startTime : format HH:mm attendu, reçu "${mv.startTime}"`;
        const origin = blocks[idx];
        if (origin.status === "done")
            return `« ${origin.title} » est déjà fait : rien à déplacer.`;
        const destRef = db_1.db.doc(`users/${uid}/daily_schedules/${mv.date}`);
        const destSnap = mv.date === date ? null : await destRef.get();
        const destBlocks = mv.date === date
            ? blocks.filter((b) => b.id !== blockId)
            : (((_b = (_a = destSnap === null || destSnap === void 0 ? void 0 : destSnap.data()) === null || _a === void 0 ? void 0 : _a.blocks) !== null && _b !== void 0 ? _b : []).slice());
        const copy = Object.assign(Object.assign({}, origin), { id: (0, uuid_1.v4)(), startTime: mv.startTime, status: "pending", doneAt: null, skipReason: null, reportReason: null, movedTo: null, carriedFromDate: `${date}:${blockId}`, movedFrom: { date, blockId, startTime: origin.startTime } });
        const { conflicts } = (0, schedule_dedupe_1.fillAgainstExisting)([copy], destBlocks);
        if (conflicts.length) {
            const by = conflicts[0].by;
            const found = (0, schedule_dedupe_1.nextFreeSlot)(copy, destBlocks, (0, schedule_dedupe_2.toMin)(mv.startTime));
            const hint = found.slot
                ? `prochain créneau libre : ${found.slot}`
                : `aucun créneau de ${copy.durationMin} min libre avant ${found.until ? `« ${found.until.title} » ${found.until.startTime}` : "minuit"}`;
            return `⛔ ${mv.date} ${mv.startTime} est occupé par « ${by.title} » (${by.startTime}, ${by.durationMin} min, ${by.status}, id:${by.id}) — ${hint}.`;
        }
        const movedOrigin = Object.assign(Object.assign({}, origin), { status: "skipped", skipReason: "reporte", movedTo: { date: mv.date, startTime: mv.startTime, blockId: copy.id } });
        if (mv.date === date) {
            blocks[idx] = movedOrigin;
            blocks.push(copy);
            await ref.update({ blocks });
        }
        else {
            blocks[idx] = movedOrigin;
            const destData = (destSnap === null || destSnap === void 0 ? void 0 : destSnap.exists) ? destSnap.data() : {};
            await Promise.all([
                ref.update({ blocks }),
                destRef.set({
                    date: mv.date,
                    generatedBy: (_c = destData.generatedBy) !== null && _c !== void 0 ? _c : "claude",
                    generatedAt: (_d = destData.generatedAt) !== null && _d !== void 0 ? _d : db_1.FieldValue.serverTimestamp(),
                    blocks: [...destBlocks, copy],
                }, { merge: true }),
            ]);
        }
        return `↪ « ${origin.title} » déplacé : ${date} ${origin.startTime} → ${mv.date} ${mv.startTime} (nouvel id ${copy.id}). ` +
            `L'origine reste tracée (déplacée), hors de la vue du programme.`;
    }
    const patch = {};
    if (updates.title !== undefined) {
        const t = clampStr(updates.title, 300, "title").trim();
        if (!t)
            return "title vide.";
        patch.title = t;
    }
    if (updates.startTime !== undefined) {
        if (!/^([01]\d|2[0-3]):[0-5]\d$/.test(updates.startTime))
            return `startTime : format HH:mm attendu, reçu "${updates.startTime}"`;
        patch.startTime = updates.startTime;
    }
    if (updates.durationMin !== undefined) {
        if (!Number.isFinite(updates.durationMin) || updates.durationMin < 5 || updates.durationMin > 24 * 60) {
            return "durationMin : entre 5 et 1440.";
        }
        patch.durationMin = Math.round(updates.durationMin);
    }
    if (updates.category !== undefined) {
        if (!BLOCK_CATEGORIES.has(updates.category))
            return `category invalide : "${updates.category}"`;
        patch.category = updates.category;
    }
    if (updates.status !== undefined) {
        if (!BLOCK_STATUSES.has(updates.status))
            return `status invalide : "${updates.status}"`;
        patch.status = updates.status;
        if (updates.status === "done")
            patch.doneAt = new Date().toISOString();
        else if (updates.status === "pending")
            patch.doneAt = null;
    }
    if (updates.skipReason !== undefined) {
        patch.skipReason = updates.skipReason.trim() ? clampStr(updates.skipReason, 300, "skipReason") : null;
    }
    if (updates.status === "skipped" && updates.skipReason === undefined && !blocks[idx].skipReason) {
        patch.skipReason = "saute";
    }
    for (const k of ["projectId", "taskId", "activityId", "actionId"]) {
        if (updates[k] !== undefined)
            patch[k] = updates[k] ? updates[k] : null;
    }
    if (!Object.keys(patch).length)
        return "Rien à modifier.";
    const before = String((_e = blocks[idx].title) !== null && _e !== void 0 ? _e : blockId);
    blocks[idx] = Object.assign(Object.assign({}, blocks[idx]), patch);
    await ref.update({ blocks });
    const after = String(blocks[idx].title);
    const what = Object.keys(patch).filter((k) => k !== "doneAt").join(", ");
    return before !== after
        ? `✅ Bloc « ${before} » → « ${after} » (${what}).`
        : `✅ Bloc « ${before} » mis à jour (${what}).`;
}
async function executeGetAssistantMessages(uid) {
    const [pendingSnap, shownSnap] = await Promise.all([
        db_1.db.collection(`users/${uid}/assistant_messages`)
            .where("status", "==", "pending")
            .get(),
        db_1.db.collection(`users/${uid}/assistant_messages`)
            .where("status", "==", "shown")
            .limit(10)
            .get(),
    ]);
    const pending = pendingSnap.docs
        .map((d) => {
        var _a, _b, _c, _d, _e, _f, _g, _h;
        const v = d.data();
        return {
            id: v.id,
            targetDate: v.targetDate,
            condition: v.condition,
            text: v.text,
            characterName: (_a = v.characterName) !== null && _a !== void 0 ? _a : "ORION",
            action: (_b = v.action) !== null && _b !== void 0 ? _b : null,
            expiresAfterDays: (_c = v.expiresAfterDays) !== null && _c !== void 0 ? _c : 2,
            createdAt: (_h = (_g = (_f = (_e = (_d = v.createdAt) === null || _d === void 0 ? void 0 : _d.toDate) === null || _e === void 0 ? void 0 : _e.call(_d)) === null || _f === void 0 ? void 0 : _f.toISOString) === null || _g === void 0 ? void 0 : _g.call(_f)) !== null && _h !== void 0 ? _h : null,
        };
    })
        .sort((a, b) => a.targetDate.localeCompare(b.targetDate));
    const recentShown = shownSnap.docs
        .map((d) => {
        var _a, _b, _c, _d, _e;
        const v = d.data();
        return {
            id: v.id,
            targetDate: v.targetDate,
            text: v.text,
            shownAt: (_e = (_d = (_c = (_b = (_a = v.shownAt) === null || _a === void 0 ? void 0 : _a.toDate) === null || _b === void 0 ? void 0 : _b.call(_a)) === null || _c === void 0 ? void 0 : _c.toISOString) === null || _d === void 0 ? void 0 : _d.call(_c)) !== null && _e !== void 0 ? _e : null,
        };
    })
        .sort((a, b) => { var _a, _b; return ((_a = b.shownAt) !== null && _a !== void 0 ? _a : "").localeCompare((_b = a.shownAt) !== null && _b !== void 0 ? _b : ""); })
        .slice(0, 10);
    if (!pending.length && !recentShown.length) {
        return "Aucun message ORION programmé ou récent.";
    }
    return JSON.stringify({ pending, recentShown }, null, 2);
}
async function executeDeleteAssistantMessage(uid, messageId) {
    var _a, _b;
    const ref = db_1.db.collection(`users/${uid}/assistant_messages`).doc(messageId);
    const snap = await ref.get();
    if (!snap.exists)
        return `Message introuvable : ${messageId}`;
    const text = ((_b = (_a = snap.data()) === null || _a === void 0 ? void 0 : _a.text) !== null && _b !== void 0 ? _b : "").slice(0, 50);
    await ref.update({ status: "expired" });
    return `✅ Message ORION supprimé : "${text}${text.length >= 50 ? "…" : ""}".`;
}
// ── Contexte allégé pour ORION (sans coachingRules, sans détails sessions) ────
async function executeGetOrionContext(uid) {
    const now = new Date();
    const today = todayInParis(now);
    const sevenDaysAgo = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000);
    const [domainsSnap, activitiesSnap, habitHitsSnap, sessionsSnap, projectsSnap, objectivesSnap] = await Promise.all([
        db_1.db.collection(`users/${uid}/domains`).get(),
        db_1.db.collection(`users/${uid}/activities`).get(),
        // ts = chaîne ISO (voir get_user_context) — jamais un Timestamp.
        db_1.db.collection(`users/${uid}/habitHits`).where("ts", ">=", sevenDaysAgo.toISOString()).get(),
        db_1.db.collection(`users/${uid}/sessions`).where("startAt", ">=", sevenDaysAgo.toISOString()).get(),
        db_1.db.collection(`users/${uid}/projects`).where("status", "==", "active").get(),
        db_1.db.collection(`users/${uid}/strategic_objectives`).get(),
    ]);
    const domains = domainsSnap.docs
        .map((d) => d.data()).filter((v) => !v.deleted)
        .map((v) => ({ id: v.id, name: v.name }));
    const activityMap = new Map();
    activitiesSnap.docs.forEach((d) => { const v = d.data(); activityMap.set(v.id, v.name); });
    const activities = activitiesSnap.docs.map((d) => d.data()).filter((v) => !v.deleted)
        .map((v) => { var _a, _b; return ({ id: v.id, name: v.name, type: v.type, domainId: v.domainId, goalMin: (_a = v.goalMin) !== null && _a !== void 0 ? _a : null, targetSource: (_b = v.targetSource) !== null && _b !== void 0 ? _b : "default" }); });
    // Habitudes : hits 7j par activité
    const hitsByHabit = new Map();
    habitHitsSnap.docs.forEach((d) => { const v = d.data(); hitsByHabit.set(v.habitId, (hitsByHabit.get(v.habitId) || 0) + 1); });
    const habitStats = Array.from(hitsByHabit.entries())
        .map(([id, count]) => { var _a; return ({ name: (_a = activityMap.get(id)) !== null && _a !== void 0 ? _a : id, hits7d: count }); });
    // Sessions : temps 7j par activité
    const minByActivity = new Map();
    (0, sessions_audit_1.liveSessionDocs)(sessionsSnap).forEach((d) => {
        const v = d.data();
        if (!v.endAt)
            return;
        const mins = Math.round((new Date(v.endAt).getTime() - new Date(v.startAt).getTime()) / 60000);
        if (mins > 0)
            minByActivity.set(v.activityId, (minByActivity.get(v.activityId) || 0) + mins);
    });
    const timeStats = Array.from(minByActivity.entries())
        .map(([id, mins]) => { var _a; return ({ name: (_a = activityMap.get(id)) !== null && _a !== void 0 ? _a : id, hours7d: Math.round(mins / 6) / 10 }); });
    // Projets actifs — résumé + tâches urgentes seulement
    const in30days = todayInParis(new Date(now.getTime() + 30 * 24 * 60 * 60 * 1000));
    const projects = projectsSnap.docs
        .filter((d) => d.data().paused !== true) // en pause = hors radar ORION
        .map((d) => {
        var _a, _b;
        const p = d.data();
        const tasks = (p.tasks || []);
        const activeTasks = tasks.filter((t) => t.status !== "done" && t.status !== "skipped");
        const urgentTasks = activeTasks.filter((t) => t.endDate && t.endDate <= in30days)
            .map((t) => ({ id: t.id, title: t.title, endDate: t.endDate, overdue: t.endDate < today }));
        return {
            id: p.id, title: p.title, domainId: (_a = p.domainId) !== null && _a !== void 0 ? _a : null,
            endDate: (_b = p.endDate) !== null && _b !== void 0 ? _b : null,
            activeTasks: activeTasks.length,
            urgentTasks,
        };
    });
    // Objectifs stratégiques actifs + progression hebdo (résumé compact)
    const objectivesRaw = objectivesSnap.docs
        .map((d) => { var _a; return (Object.assign(Object.assign({}, d.data()), { id: (_a = d.data().id) !== null && _a !== void 0 ? _a : d.id })); })
        .filter((v) => { var _a; return String((_a = v.status) !== null && _a !== void 0 ? _a : "active") === "active"; })
        .slice(0, 10);
    const objectives = objectivesRaw.length > 0
        ? (0, objectives_1.summarizeObjectives)(objectivesRaw, activitiesSnap.docs.map((d) => d.data()), (0, sessions_audit_1.liveSessionDocs)(sessionsSnap).map((d) => d.data()), habitHitsSnap.docs.map((d) => d.data()), today)
        : null;
    return JSON.stringify({ today, domains, activities, objectives, habitStats, timeStats, projects }, null, 2);
}
async function executeGetOrionQueue(uid) {
    const snap = await db_1.db.collection(`users/${uid}/orion_queue`)
        .orderBy("createdAt", "asc")
        .limit(10)
        .get();
    if (snap.empty)
        return "Aucune instruction en file.";
    const items = snap.docs.map((d) => {
        var _a, _b, _c, _d, _e, _f, _g;
        const v = d.data();
        return {
            id: (_a = v.id) !== null && _a !== void 0 ? _a : d.id,
            instruction: v.instruction,
            context: (_b = v.context) !== null && _b !== void 0 ? _b : null,
            createdAt: (_g = (_f = (_e = (_d = (_c = v.createdAt) === null || _c === void 0 ? void 0 : _c.toDate) === null || _d === void 0 ? void 0 : _d.call(_c)) === null || _e === void 0 ? void 0 : _e.toISOString) === null || _f === void 0 ? void 0 : _f.call(_e)) !== null && _g !== void 0 ? _g : null,
        };
    });
    return JSON.stringify(items, null, 2);
}
async function executeDeleteOrionQueueItem(uid, itemId) {
    await db_1.db.collection(`users/${uid}/orion_queue`).doc(itemId).delete();
    return `✅ Instruction traitée et retirée de la file.`;
}
async function executeGetInbox(uid) {
    // Sans orderBy (évite l'index composite status+createdAt) → tri en mémoire.
    const snap = await db_1.db.collection(`users/${uid}/captures`)
        .where("status", "==", "pending")
        .get();
    if (snap.empty)
        return "Aucune idée en attente dans l'inbox.";
    const sorted = snap.docs.slice().sort((a, b) => {
        var _a, _b, _c, _d, _e, _f;
        return ((_c = (_b = (_a = a.data().createdAt) === null || _a === void 0 ? void 0 : _a.toMillis) === null || _b === void 0 ? void 0 : _b.call(_a)) !== null && _c !== void 0 ? _c : 0) -
            ((_f = (_e = (_d = b.data().createdAt) === null || _d === void 0 ? void 0 : _d.toMillis) === null || _e === void 0 ? void 0 : _e.call(_d)) !== null && _f !== void 0 ? _f : 0);
    });
    const items = sorted.map((d) => {
        var _a, _b, _c, _d, _e;
        const v = d.data();
        return { id: v.id, text: v.text, createdAt: (_e = (_d = (_c = (_b = (_a = v.createdAt) === null || _a === void 0 ? void 0 : _a.toDate) === null || _b === void 0 ? void 0 : _b.call(_a)) === null || _c === void 0 ? void 0 : _c.toISOString) === null || _d === void 0 ? void 0 : _d.call(_c)) !== null && _e !== void 0 ? _e : null };
    });
    return JSON.stringify(items, null, 2);
}
async function executeProcessInboxItem(uid, itemId, note) {
    var _a, _b;
    const ref = db_1.db.collection(`users/${uid}/captures`).doc(itemId);
    const snap = await ref.get();
    if (!snap.exists)
        return `Item inbox introuvable : ${itemId}`;
    const text = (_b = (_a = snap.data()) === null || _a === void 0 ? void 0 : _a.text) !== null && _b !== void 0 ? _b : "";
    await ref.delete();
    return `✅ Idée traitée et retirée de l'inbox : "${text}" → ${note}`;
}
// ── Propositions ORION (« À valider ») ───────────────────────────────────────
// ORION autonome ne modifie plus les projets directement : il enregistre une
// PROPOSITION que l'utilisateur accepte/refuse/redirige côté app. L'acceptation
// applique la mutation côté client (déterministe, sans LLM). Si la proposition
// vient d'une idée inbox, la capture passe en "proposed" → disparaît de l'inbox
// (executeGetInbox ne lit que status=="pending") et n'est pas re-proposée.
async function executeProposeChange(uid, args) {
    var _a, _b, _c;
    const valid = ["new_project", "attach_idea_as_task", "create_subproject", "archive_project", "add_phase", "attach_action_to_task", "add_own_action", "restructure_project"];
    if (!valid.includes(args.kind)) {
        return `❌ kind invalide : ${args.kind} (attendu : ${valid.join(", ")})`;
    }
    const id = db_1.db.collection(`users/${uid}/orion_proposals`).doc().id;
    await db_1.db.collection(`users/${uid}/orion_proposals`).doc(id).set({
        id,
        kind: args.kind,
        title: args.title,
        rationale: (_a = args.rationale) !== null && _a !== void 0 ? _a : "",
        sourceCaptureId: (_b = args.sourceCaptureId) !== null && _b !== void 0 ? _b : null,
        payload: (_c = args.payload) !== null && _c !== void 0 ? _c : {},
        status: "pending",
        createdBy: "orion",
        createdAt: db_1.FieldValue.serverTimestamp(),
    });
    if (args.sourceCaptureId) {
        await db_1.db.collection(`users/${uid}/captures`).doc(args.sourceCaptureId)
            .set({ status: "proposed" }, { merge: true });
    }
    return `✅ Proposition enregistrée (« ${args.title} ») — en attente de validation par l'utilisateur.`;
}
// ── Programme horaire journalier ─────────────────────────────────────────────
async function executePlanDay(uid, args) {
    var _a, _b, _c, _d, _e;
    const today = todayInParis();
    const date = (_a = args.date) !== null && _a !== void 0 ? _a : today;
    if (!/^\d{4}-\d{2}-\d{2}$/.test(date))
        return `Date invalide : ${date}`;
    // Défauts = journée active réglée dans l'app (Cette semaine → Capacité),
    // sinon 7 h – 20 h ; un lève-tôt qui a mis 4 h → 20 h est planifié dès 4 h.
    const dayWindow = await readDayWindowHours(uid);
    const startHour = (_c = (_b = args.startHour) !== null && _b !== void 0 ? _b : dayWindow === null || dayWindow === void 0 ? void 0 : dayWindow.startHour) !== null && _c !== void 0 ? _c : 7;
    const endHour = (_e = (_d = args.endHour) !== null && _d !== void 0 ? _d : dayWindow === null || dayWindow === void 0 ? void 0 : dayWindow.endHour) !== null && _e !== void 0 ? _e : 20;
    // Défaut SANS écriture dans Google Calendar : l'app synchronise déjà le
    // programme (sync native) et les rendez-vous arrivent en miroirs ; une
    // 2ᵉ écriture par le connecteur Claude créait des doublons des deux côtés.
    const syncToCalendar = args.syncToCalendar === true && !(await nativeGcalSync(uid));
    // Planifier AUJOURD'HUI ne doit jamais créer de blocs déjà passés : le
    // départ effectif est calé sur le prochain quart d'heure (s'il est 15h12 et
    // que startHour=7, on planifie à partir de 15h15 — les blocs passés du
    // programme existant restent intacts).
    const isToday = date === today;
    const floorHm = isToday ? nextQuarterHour() : null;
    const startLabel = floorHm && floorHm > `${String(startHour).padStart(2, "0")}:00`
        ? floorHm
        : `${String(startHour).padStart(2, "0")}h`;
    const [userContext, existingSchedule, autoPlanEnabled, timeBlock] = await Promise.all([
        executeGetUserContext(uid),
        executeGetDaySchedule(uid, date),
        readAutoPlan(uid),
        planDayTimeBlock(uid),
    ]);
    const projectsSnap = await db_1.db.collection(`users/${uid}/projects`)
        .where("status", "==", "active").get();
    const projectDetails = [];
    for (const doc of projectsSnap.docs) {
        if (doc.data().paused === true)
            continue; // en pause = pas planifié
        projectDetails.push(await executeGetProject(uid, doc.id));
    }
    // Activités-temps programmables : un bloc peut porter UNIQUEMENT activityId
    // (sans projet/tâche) → le ▶ de l'app lance un chrono ciblé sur l'activité.
    const actsSnap = await db_1.db.collection(`users/${uid}/activities`).get();
    const timeActivities = actsSnap.docs
        .map((d) => d.data())
        .filter((a) => a.deleted !== true && a.type !== "habit")
        .map((a) => `  · "${a.name}" (activityId: ${a.id}${a.goalMin ? ` — objectif ${a.goalMin} min/j` : ""})`);
    const calendarSync = syncToCalendar
        ? [
            ``,
            `📅 SYNC GOOGLE CALENDAR (après schedule_day) :`,
            `1. list_calendars() → trouver le calendrier "Productivitwo"`,
            `2. list_events(calendarId, "${date}T00:00:00Z", "${date}T23:59:59Z") → events existants`,
            `3. Supprimer les events dont description contient "source: productivitwo"`,
            `4. create_event() pour chaque bloc SAUF les miroirs 📅 (déjà dans l'agenda)`,
            `   description format : "source: productivitwo | category: [project|routine|break|personal]"`,
            `   colorId : routine=2, project=7, break=5, personal=4`,
        ]
        : [];
    return [
        `══════════════════════════════════════════`,
        `📋 CONTEXTE PLANIFICATION — ${date} (${startLabel}-${endHour}h)`,
        `══════════════════════════════════════════`,
        ...autoPlanBanner(autoPlanEnabled, date),
        ...(isToday
            ? [
                ``,
                `⏰ Il est ${nowInParis().hm} — ne planifie AUCUN bloc avant ${floorHm}.`,
                `   Les blocs déjà passés du programme existant restent tels quels`,
                `   (ne pas les recréer, ne pas les décaler).`,
            ]
            : []),
        ``,
        `── CONTEXTE UTILISATEUR ──`,
        userContext,
        ``,
        `── PROGRAMME EXISTANT ──`,
        existingSchedule,
        ``,
        `── PROJETS ACTIFS (${projectDetails.length}) ──`,
        projectDetails.length > 0 ? projectDetails.join("\n\n---\n\n") : "Aucun projet actif.",
        ``,
        `── ACTIVITÉS-TEMPS PROGRAMMABLES (${timeActivities.length}) ──`,
        `Un bloc peut porter UNIQUEMENT activityId (sans projet/tâche) → ▶ lance un`,
        `chrono ciblé sur l'activité. Utilise-les pour bloquer du temps dessus :`,
        timeActivities.length > 0 ? timeActivities.join("\n") : "  Aucune.",
        ...timeBlock,
        ``,
        `══════════════════════════════════════════`,
        `WORKFLOW :`,
        `1. Les rendez-vous Google Agenda sont DÉJÀ dans le programme existant (blocs 📅) :`,
        `   planifie AUTOUR, ne les recrée jamais dans schedule_day (ils seraient écartés).`,
        `   list_events() ne sert qu'à voir des rendez-vous pas encore importés.`,
        `2. Générer les blocs (${startLabel}-${endHour}h) : tâches Gantt + routines + activités-temps + pauses`,
        `   → Tâche la plus proche de la deadline en premier`,
        `   → Arbitre selon objectives[] du contexte : les engagements en retard (onTrack:false) passent en premier`,
        `   → BATCHING GTD : les actions portent un champ "context" (@maison, @bureau, @courses…) —`,
        `     regroupe en séquences ADJACENTES les blocs dont les actions partagent le même contexte`,
        `     (toutes les courses ensemble, tout l'@ordinateur d'affilée…) pour éviter les allers-retours`,
        `   → Ne pas recréer les blocs marqués [supprimé par l'utilisateur]`,
        `   → DURÉES : chaque action/tâche programmée SANS estimatedMin → estime-la en appliquant le`,
        `     facteur « estimé vs réel » ci-dessus, et POSE-LA (update_action pour une action,`,
        `     update_task pour une tâche) ; la durée du bloc = cette estimation. Une action déjà`,
        `     au-delà de son estimation : prévois le reste, pas l'estimation entière.`,
        `3. schedule_day("${date}", blocks[])`,
        `4. PRÉPARATION LA VEILLE : pour tout bloc matinal (avant 9h30) qui exige du`,
        `   matériel ou de la logistique (sport, déplacement, cuisine), ajoute via`,
        `   add_prep_block un bloc de préparation de 5 min la veille au soir (défaut`,
        `   21:45), lié via prepForDate + prepForBlockId au bloc matinal. Le user`,
        `   coche la prep en un tap → le lendemain « les affaires sont prêtes depuis hier ».`,
        ...calendarSync,
        `══════════════════════════════════════════`,
    ].join("\n");
}
async function executePlanWeek(uid, args) {
    const today = todayInParis();
    let startDate = args.startDate;
    if (!startDate) {
        const d = new Date(today);
        const day = d.getDay();
        const daysToMonday = day === 1 ? 0 : day === 0 ? 1 : 8 - day;
        d.setDate(d.getDate() + daysToMonday);
        startDate = todayInParis(d);
    }
    if (!/^\d{4}-\d{2}-\d{2}$/.test(startDate))
        return `Date invalide : ${startDate}`;
    const weekDates = [];
    const start = new Date(startDate);
    for (let i = 0; weekDates.length < 5; i++) {
        const d = new Date(start);
        d.setDate(start.getDate() + i);
        const day = d.getDay();
        if (day !== 0 && day !== 6)
            weekDates.push(todayInParis(d));
    }
    const [userContext] = await Promise.all([executeGetUserContext(uid)]);
    const projectsSnap = await db_1.db.collection(`users/${uid}/projects`)
        .where("status", "==", "active").get();
    const projectDetails = [];
    for (const doc of projectsSnap.docs) {
        if (doc.data().paused === true)
            continue; // en pause = pas planifié
        projectDetails.push(await executeGetProject(uid, doc.id));
    }
    const schedules = [];
    for (const d of weekDates) {
        const s = await executeGetDaySchedule(uid, d);
        schedules.push(`${d} : ${s}`);
    }
    const syncNote = args.syncToCalendar === true && !(await nativeGcalSync(uid))
        ? `\n📅 SYNC GOOGLE CALENDAR : après chaque schedule_day(), créer les events dans le calendrier "Productivitwo" (colorId: routine=2, project=7, break=5, personal=4) — jamais les miroirs 📅.`
        : `\n📅 Les rendez-vous Google Agenda (blocs 📅) sont déjà dans les programmes : planifie autour, ne les recrée pas.`;
    return [
        `══════════════════════════════════════════`,
        `📋 CONTEXTE PLANIFICATION SEMAINE`,
        `${weekDates[0]} → ${weekDates[4]}`,
        `══════════════════════════════════════════`,
        ...(weekDates.includes(today)
            ? [
                ``,
                `⏰ Il est ${nowInParis().hm} — pour AUJOURD'HUI (${today}), ne planifie`,
                `   aucun bloc avant ${nextQuarterHour()} (jamais d'heures déjà passées).`,
            ]
            : []),
        ``,
        `── CONTEXTE UTILISATEUR ──`,
        userContext,
        ``,
        `── PROGRAMMES EXISTANTS ──`,
        schedules.join("\n"),
        ``,
        `── PROJETS ACTIFS (${projectDetails.length}) ──`,
        projectDetails.length > 0 ? projectDetails.join("\n\n---\n\n") : "Aucun projet actif.",
        ``,
        `══════════════════════════════════════════`,
        `WORKFLOW :`,
        `0. Revue des orphelins : appelle weekly_review() et soumets ses points à l'utilisateur AVANT de planifier`,
        `   (jalons passés non cochés, clôtures en retard, projets à mettre en veille, doublons) — rien n'est modifié sans son accord.`,
        `1. Répartir les tâches Gantt sur les 5 jours (deadline proche = premier)`,
        `2. Max ~6h de travail projet par jour · inclure routines matin/soir`,
        `   → BATCHING GTD : regroupe en séquences adjacentes les blocs dont les actions partagent le même "context" (@maison, @courses…)`,
        `3. Pour chaque jour, schedule_day("YYYY-MM-DD", blocks[])`,
        syncNote,
        `4. Afficher un résumé semaine`,
        `══════════════════════════════════════════`,
    ].join("\n");
}
async function executeSyncCalendar(uid, date) {
    var _a;
    const today = todayInParis();
    const targetDate = date !== null && date !== void 0 ? date : today;
    if (!/^\d{4}-\d{2}-\d{2}$/.test(targetDate))
        return `Date invalide : ${targetDate}`;
    if (await nativeGcalSync(uid)) {
        return `🗓️ Google Agenda est connecté dans l'app : le programme du ${targetDate} y est synchronisé automatiquement. ` +
            `N'appelle PAS create_event / delete_event — rien d'autre à faire.`;
    }
    const snap = await db_1.db.doc(`users/${uid}/daily_schedules/${targetDate}`).get();
    if (!snap.exists) {
        return `Aucun programme Productivitwo pour le ${targetDate}. Appelle plan_day("${targetDate}") pour en créer un.`;
    }
    const data = snap.data();
    const blocks = (_a = data.blocks) !== null && _a !== void 0 ? _a : [];
    // Les miroirs (gcalEventId) sont des rendez-vous qui existent déjà dans
    // l'agenda : les renvoyer les dupliquerait.
    const activeBlocks = blocks.filter((b) => b.status !== "deleted" && b.gcalEventId == null);
    const colorMap = { routine: 2, project: 7, break: 5, personal: 4 };
    const eventLines = activeBlocks.map((b) => {
        var _a;
        const [sh, sm] = b.startTime.split(":").map(Number);
        const endMin = sh * 60 + sm + b.durationMin;
        const eh = Math.floor(endMin / 60);
        const em = endMin % 60;
        const pad = (n) => String(n).padStart(2, "0");
        const start = `${targetDate}T${pad(sh)}:${pad(sm)}:00`;
        const end = `${targetDate}T${pad(eh)}:${pad(em)}:00`;
        const colorId = (_a = colorMap[b.category]) !== null && _a !== void 0 ? _a : 7;
        const desc = `source: productivitwo | category: ${b.category}${b.projectId ? ` | projectId: ${b.projectId}` : ""}`;
        return `  • "${b.title}" ${pad(sh)}:${pad(sm)}-${pad(eh)}:${pad(em)} colorId=${colorId}\n    description="${desc}"\n    startTime="${start}" endTime="${end}"`;
    });
    return [
        `📅 SYNC GOOGLE CALENDAR — ${targetDate}`,
        `Programme Productivitwo : ${activeBlocks.length} bloc(s) à synchroniser`,
        ``,
        `ÉTAPES :`,
        `1. list_calendars() → trouver le calendarId du calendrier "Productivitwo"`,
        `2. list_events(calendarId, "${targetDate}T00:00:00Z", "${targetDate}T23:59:59Z")`,
        `3. Supprimer les events dont description contient "source: productivitwo"`,
        `4. Créer les events suivants :`,
        ...eventLines,
        ``,
        `Note : ne pas dupliquer les events déjà présents dans le calendrier principal.`,
        `Les rendez-vous importés de l'agenda (blocs 📅) ne sont volontairement pas listés.`,
    ].join("\n");
}
async function executeGetDaySchedule(uid, date) {
    var _a;
    if (!/^\d{4}-\d{2}-\d{2}$/.test(date))
        return `Date invalide : ${date}. Format attendu : YYYY-MM-DD`;
    const snap = await db_1.db.doc(`users/${uid}/daily_schedules/${date}`).get();
    if (!snap.exists)
        return `Aucun programme pour le ${date}.`;
    const data = snap.data();
    // Ordre chronologique garanti — le tableau Firestore est en ordre
    // d'insertion (même correctif que todaySchedule dans get_user_context).
    const blocks = ((_a = data.blocks) !== null && _a !== void 0 ? _a : [])
        .slice()
        .sort((a, b) => String(a.startTime).localeCompare(String(b.startTime)));
    const statusIcon = (s) => s === "done" ? "✅" : s === "skipped" ? "⏭" : s === "deleted" ? "❌" : "⬜";
    const lines = blocks.map((b) => {
        const icon = statusIcon(b.status);
        const mt = b.movedTo;
        const deletedNote = b.status === "deleted"
            ? " [supprimé par l'utilisateur — ne pas recréer]"
            : b.status === "skipped"
                ? (mt ? ` [déplacé → ${mt.date} ${mt.startTime} — hors de la vue, ne pas recréer]`
                    : ` [sauté${b.skipReason ? ` — ${b.skipReason}` : ""} — hors de la vue]`)
                : "";
        // Miroir d'un rendez-vous Google Agenda : il est DÉJÀ dans le programme et
        // dans l'agenda — Claude ne doit ni le recréer dans schedule_day ni le
        // renvoyer vers Google Calendar.
        const mirrorNote = b.gcalEventId != null && b.status !== "deleted"
            ? " 📅 [rendez-vous Google Agenda — déjà dans le programme : ne pas recréer, ne pas synchroniser]"
            : "";
        // id indispensable (mark_block_done le demande) + rattachements pour
        // savoir quel projet/tâche/activité le bloc sert (constaté au test du
        // connecteur : impossible de valider un bloc sans son id).
        const links = [
            `id:${b.id}`,
            ...(b.projectId ? [`projet:${b.projectId}`] : []),
            ...(b.taskId ? [`tâche:${b.taskId}`] : []),
            ...(b.activityId ? [`activité:${b.activityId}`] : []),
            ...(b.actionId ? [`action:${b.actionId}`] : []),
        ].join(" · ");
        return `${icon} ${b.startTime} (${b.durationMin}min) — ${b.title} [${b.category}] (${links})${mirrorNote}${deletedNote}`;
    });
    // L'intention du jour (onglet Objectifs) fait partie du contexte : le
    // programme généré/ajusté doit la servir.
    const intention = typeof data.intention === "string" && data.intention.trim() !== ""
        ? `🎯 Intention du jour : « ${data.intention} »\n`
        : "";
    return `${intention}Programme du ${date} (généré par ${data.generatedBy}) :\n${lines.join("\n")}`;
}
async function normalizeSessionSteps(uid, steps) {
    var _a, _b, _c;
    const actsSnap = await db_1.db.collection(`users/${uid}/activities`).get();
    const routines = new Map(actsSnap.docs
        .map((d) => d.data())
        .filter((a) => a.type === "habit" && a.deleted !== true)
        .map((a) => [a.id, a.name]));
    const out = [];
    for (const s of steps) {
        const title = ((_a = s.title) !== null && _a !== void 0 ? _a : "").trim();
        if (!title)
            continue;
        if (s.routineId != null && !routines.has(s.routineId)) {
            return { steps: [], error: `Routine introuvable : ${s.routineId} (étape « ${title} »). Vérifie les ids via get_user_context.` };
        }
        out.push({
            id: (0, uuid_1.v4)(),
            title,
            kind: s.routineId != null ? "routine" : "check",
            routineId: (_b = s.routineId) !== null && _b !== void 0 ? _b : null,
            checklist: ((_c = s.checklist) !== null && _c !== void 0 ? _c : []).map((c) => String(c).trim()).filter((c) => c !== ""),
        });
    }
    if (!out.length)
        return { steps: [], error: "Aucune étape valide fournie." };
    return { steps: out };
}
async function executeListSessionTemplates(uid) {
    const snap = await db_1.db.collection(`users/${uid}/session_templates`).get();
    const tpls = snap.docs
        .map((d) => d.data())
        .filter((t) => t.archived !== true);
    if (!tpls.length) {
        return "Aucun déroulé — crée une séance avec create_session_template.";
    }
    const actsSnap = await db_1.db.collection(`users/${uid}/activities`).get();
    const names = new Map(actsSnap.docs.map((d) => [d.data().id, d.data().name]));
    return tpls
        .map((t) => {
        var _a, _b;
        const steps = ((_a = t.steps) !== null && _a !== void 0 ? _a : [])
            .map((s, i) => {
            var _a;
            return `  ${i + 1}. ${s.title}${s.kind === "routine" ? " · routine" : ""}` +
                `${((_a = s.checklist) !== null && _a !== void 0 ? _a : []).length > 0 ? ` · checklist ×${s.checklist.length}` : ""}`;
        })
            .join("\n");
        return `• « ${t.title} » (id: ${t.id}) — activité : ${(_b = names.get(t.activityId)) !== null && _b !== void 0 ? _b : t.activityId}\n${steps}`;
    })
        .join("\n");
}
async function executeCreateSessionTemplate(uid, args) {
    var _a, _b, _c;
    const actSnap = await db_1.db.collection(`users/${uid}/activities`).doc(args.activityId).get();
    const act = actSnap.data();
    if (!actSnap.exists || (act === null || act === void 0 ? void 0 : act.deleted) === true) {
        return `Activité introuvable : ${args.activityId}`;
    }
    if ((act === null || act === void 0 ? void 0 : act.type) !== "time") {
        return `« ${(_a = act === null || act === void 0 ? void 0 : act.name) !== null && _a !== void 0 ? _a : args.activityId} » n'est pas une activité-temps — un déroulé trace son temps sur une activité-temps (la routine est une ÉTAPE, pas le contenant).`;
    }
    const title = ((_b = args.title) !== null && _b !== void 0 ? _b : "").trim();
    if (!title)
        return "Titre requis.";
    const norm = await normalizeSessionSteps(uid, (_c = args.steps) !== null && _c !== void 0 ? _c : []);
    if (norm.error)
        return `❌ ${norm.error}`;
    const id = (0, uuid_1.v4)();
    await db_1.db.collection(`users/${uid}/session_templates`).doc(id).set({
        id,
        title,
        activityId: args.activityId,
        steps: norm.steps,
        archived: false,
        createdAt: new Date().toISOString(),
    });
    return `✅ Déroulé « ${title} » créé (id: ${id}) sur « ${act === null || act === void 0 ? void 0 : act.name} » — ${norm.steps.length} étape(s). Il apparaît dans la fiche de l'activité ; programmable via schedule_day (sessionTemplateId + activityId).`;
}
async function executeUpdateSessionTemplate(uid, args) {
    var _a;
    const ref = db_1.db.collection(`users/${uid}/session_templates`).doc(args.templateId);
    const snap = await ref.get();
    if (!snap.exists)
        return `Déroulé introuvable : ${args.templateId}`;
    const patch = {};
    if (typeof args.title === "string" && args.title.trim() !== "") {
        patch.title = args.title.trim();
    }
    if (args.steps != null) {
        const norm = await normalizeSessionSteps(uid, args.steps);
        if (norm.error)
            return `❌ ${norm.error}`;
        patch.steps = norm.steps;
    }
    if (typeof args.archived === "boolean")
        patch.archived = args.archived;
    if (!Object.keys(patch).length)
        return "Rien à modifier (title, steps ou archived).";
    await ref.set(patch, { merge: true });
    const t = snap.data().title;
    return args.archived === true
        ? `✅ Déroulé « ${t} » archivé.`
        : `✅ Déroulé « ${(_a = patch.title) !== null && _a !== void 0 ? _a : t} » mis à jour${patch.steps ? ` — ${patch.steps.length} étape(s)` : ""}.`;
}
async function executeScheduleDay(uid, date, blocks, opts = {}) {
    var _a, _b, _c, _d, _e, _f, _g, _h, _j, _l, _m, _o;
    if (!/^\d{4}-\d{2}-\d{2}$/.test(date))
        return `Date invalide : ${date}. Format attendu : YYYY-MM-DD`;
    if (!(blocks === null || blocks === void 0 ? void 0 : blocks.length))
        return `Aucun bloc fourni — le programme n'a pas été enregistré.`;
    // mode "fill" (programmation automatique) : le programme existant est gardé
    // tel quel, les entrants ne remplissent que les trous. Défaut "replace".
    const fill = opts.mode === "fill";
    const generatedBy = opts.generatedBy === "auto" ? "auto" : "claude";
    const normalizedBlocks = blocks.map((b) => {
        var _a, _b, _c, _d, _e, _f, _g, _h, _j, _l, _m;
        return ({
            id: (0, uuid_1.v4)(),
            startTime: b.startTime,
            durationMin: b.durationMin,
            title: b.title,
            category: b.category,
            projectId: (_a = b.projectId) !== null && _a !== void 0 ? _a : null,
            taskId: (_b = b.taskId) !== null && _b !== void 0 ? _b : null,
            activityId: (_c = b.activityId) !== null && _c !== void 0 ? _c : null,
            actionId: (_d = b.actionId) !== null && _d !== void 0 ? _d : null, // action ciblée (propre à une activité OU action de projet)
            status: "pending",
            doneAt: null,
            kind: (_e = b.kind) !== null && _e !== void 0 ? _e : "normal", // "normal" | "prep" | "bilan" | "session"
            prepForDate: (_f = b.prepForDate) !== null && _f !== void 0 ? _f : null,
            prepForBlockId: (_g = b.prepForBlockId) !== null && _g !== void 0 ? _g : null,
            domainId: (_h = b.domainId) !== null && _h !== void 0 ? _h : null, // domaine ciblé (kind:"session")
            skipReason: (_j = b.skipReason) !== null && _j !== void 0 ? _j : null, // pourquoi l'engagement a sauté (check-in)
            reportReason: (_l = b.reportReason) !== null && _l !== void 0 ? _l : null, // raison donnée au moment du report
            sessionTemplateId: (_m = b.sessionTemplateId) !== null && _m !== void 0 ? _m : null, // séance (déroulé) → ▶ = player
        });
    });
    // Remplacer les blocs ne doit pas effacer les faits trackés au niveau du
    // doc (dayReason du check-in, plannedAt/plannedSameDay du rattrapage).
    const ref = db_1.db.doc(`users/${uid}/daily_schedules/${date}`);
    const prev = await ref.get();
    const prevData = prev.exists ? prev.data() : {};
    // Les blocs posés par d'autres flux survivent au remplacement : preps du
    // soir (add_prep_block), bilans d'essai (renégociation 12c, posés à J+14),
    // sessions de définition de domaine (onboarding 18b) — et les MIROIRS
    // d'événements Google Agenda (tous statuts : un remplacement de programme
    // ne peut pas effacer un rendez-vous, ni ressusciter un miroir swipé).
    const prevBlocks = (_a = prevData.blocks) !== null && _a !== void 0 ? _a : [];
    // Le vécu est immuable (B10) : un remplacement ne touche jamais un bloc
    // FAIT ni un bloc sur lequel un chrono réel a tourné ; un bloc passé non
    // fait a sauté, il se remplace comme un bloc futur (non relisté = retiré).
    // Un entrant qui chevauche un bloc vécu est écarté comme en mode compléter.
    const daySessions = fill ? [] : await readDaySessions(uid, date);
    const settledCtx = { sessions: daySessions };
    const settled = fill ? [] : prevBlocks.filter((b) => (0, schedule_dedupe_1.isSettledBlock)(b, settledCtx));
    const preserved = fill ? prevBlocks : prevBlocks
        .filter((b) => (0, schedule_dedupe_1.isSettledBlock)(b, settledCtx) ||
        b.gcalEventId != null ||
        // Défi programmé 🔥 = engagement pris (alarme locale armée côté app) —
        // un remplacement de programme ne l'efface jamais en silence.
        (b.challenge === true && b.status !== "deleted") ||
        ((b.kind === "prep" || b.kind === "bilan" || b.kind === "session") &&
            b.status !== "deleted"));
    // Un bloc entrant qui doublonne un miroir agenda (même début + même titre
    // ou durée) n'est PAS recréé : le rendez-vous est déjà là (doublons
    // constatés dans Aujourd'hui, 2026-10-02).
    const { kept: afterMirrors, dropped } = (0, schedule_dedupe_1.splitAgainstMirrors)(normalizedBlocks, preserved);
    // En mode compléter, un entrant qui chevauche un bloc existant (fait, manuel,
    // reporté…) est écarté : on ne touche pas à ce qui est déjà posé.
    const { kept: newBlocks, conflicts } = fill
        ? (0, schedule_dedupe_1.fillAgainstExisting)(afterMirrors, preserved)
        : (0, schedule_dedupe_1.fillAgainstExisting)(afterMirrors, settled);
    // B12 — un bloc passé non fait et NON relisté a sauté : il sort de la vue
    // mais reste tracé (status skipped, cause « replanifie ») pour le check-in
    // du soir et estimate_accuracy. Relisté (même titre) = simplement re-posé,
    // pas de trace.
    const traces = fill ? [] : (0, schedule_dedupe_1.traceUnlisted)(prevBlocks, preserved, newBlocks);
    await ref.set({
        date,
        generatedBy,
        generatedAt: db_1.FieldValue.serverTimestamp(),
        blocks: [...preserved, ...traces, ...newBlocks],
        dayReason: (_b = prevData.dayReason) !== null && _b !== void 0 ? _b : null,
        plannedAt: (_c = prevData.plannedAt) !== null && _c !== void 0 ? _c : null,
        plannedSameDay: (_d = prevData.plannedSameDay) !== null && _d !== void 0 ? _d : false,
        dayMode: (_e = prevData.dayMode) !== null && _e !== void 0 ? _e : "normal", // mode soirée réversible (23c)
        dayModeActivatedAt: (_f = prevData.dayModeActivatedAt) !== null && _f !== void 0 ? _f : null,
        unavailableUntil: (_g = prevData.unavailableUntil) !== null && _g !== void 0 ? _g : null, // « je suis le flow »
        unavailableReason: (_h = prevData.unavailableReason) !== null && _h !== void 0 ? _h : null,
        reviewedAt: (_j = prevData.reviewedAt) !== null && _j !== void 0 ? _j : null, // « point fait » — jamais effacé
        energyState: (_l = prevData.energyState) !== null && _l !== void 0 ? _l : null, // état déclaré (24a) — un fait
        recoverySequence: (_m = prevData.recoverySequence) !== null && _m !== void 0 ? _m : null, // remontée (25) — idem
        intention: (_o = prevData.intention) !== null && _o !== void 0 ? _o : null, // intention du jour (onglet Objectifs)
    });
    const lines = newBlocks.map((b) => `• ${b.startTime} (${b.durationMin}min) — ${b.title}`);
    const skipped = dropped.length
        ? `\n📅 ${dropped.length} bloc(s) non recréé(s) — déjà présents comme rendez-vous Google Agenda : ${dropped.map((b) => `${b.startTime} ${b.title}`).join(", ")}`
        : "";
    // B9 : un bloc écarté n'est pas perdu en silence — on indique le créneau
    // libre le plus proche (dans la journée active) pour le reposer.
    let clashed = "";
    if (conflicts.length) {
        // B11 : suggestion vers l'avant seulement — à partir de maintenant (heure
        // vécue, si c'est aujourd'hui) ou de l'heure demandée, jamais depuis 00:00.
        const metaSnap = await db_1.db.doc(`users/${uid}/data/meta`).get();
        const tzOffset = metaSnap.exists ? metaSnap.data().tzOffsetMin : null;
        const lived = userDayParts(typeof tzOffset === "number" ? tzOffset : null);
        const nowMin = lived.ymd === date ? (0, schedule_dedupe_2.toMin)(lived.hm) : 0;
        const busy = [...preserved, ...newBlocks];
        const hints = conflicts.map(({ block: b, by }) => {
            const found = (0, schedule_dedupe_1.nextFreeSlot)(b, busy, Math.max(nowMin, (0, schedule_dedupe_2.toMin)(b.startTime)));
            const byLabel = `occupé par « ${by.title} » (${by.startTime}, ${by.durationMin} min, ${by.status}, id:${by.id})`;
            const slot = found.slot
                ? ` → prochain créneau libre : ${found.slot}`
                : ` → aucun créneau de ${b.durationMin} min libre avant ${found.until ? `« ${found.until.title} » ${found.until.startTime}` : "minuit"}`;
            return `${b.startTime} ${b.title} — ${byLabel}${slot}`;
        });
        clashed = `\n⛔ ${conflicts.length} bloc(s) écarté(s) : ${hints.join(" · ")}` +
            `\n   Repose-les avec schedule_day(mode:"fill") à l'heure indiquée, ou libère le créneau avec ` +
            `update_block(status:"skipped" | delete:true) si le bloc occupant a sauté.`;
    }
    const livedNote = (settled.length
        ? ` · ${settled.length} bloc(s) vécu(s) conservé(s) (faits, chrono rattaché, sautés / retirés)`
        : "") + (traces.length
        ? ` · ${traces.length} bloc(s) non relisté(s) tracé(s) comme sautés (hors de la vue)`
        : "");
    const head = fill
        ? `✅ Programme du ${date} complété — ${newBlocks.length} bloc(s) ajouté(s), ${prevBlocks.length} existant(s) conservé(s)`
        : `✅ Programme du ${date} enregistré — ${newBlocks.length} bloc(s)${livedNote}`;
    return `${head}\n${lines.join("\n")}${skipped}${clashed}`;
}
const sanitizeTasks = (raw) => {
    var _a;
    return ((_a = raw) !== null && _a !== void 0 ? _a : []).map((t) => JSON.parse(JSON.stringify(t, (_k, v) => v && typeof v === "object" && typeof v.toDate === "function" ? v.toDate().toISOString() : v)));
};
function pickTemplateAction(raw) {
    if (typeof raw === "string")
        return { title: clampStr(raw, 200, "action") };
    const o = (raw !== null && raw !== void 0 ? raw : {});
    return Object.assign(Object.assign({ title: clampStr(o.title, 200, "action.title") }, (Array.isArray(o.contexts) ? { contexts: o.contexts.filter((c) => typeof c === "string") }
        : typeof o.context === "string" ? { contexts: [o.context] } : {})), (typeof o.estimatedMin === "number" ? { estimatedMin: o.estimatedMin } : {}));
}
/** Normalise un modèle (stocké ou reçu) ; les parties absentes prennent le défaut. */
function pickTemplate(raw, fallbackId) {
    var _a, _b, _c;
    const prep = ((_a = raw.prep) !== null && _a !== void 0 ? _a : {});
    const closure = ((_b = raw.closure) !== null && _b !== void 0 ? _b : {});
    const num = (v, d) => (typeof v === "number" && v >= 0 ? Math.round(v) : d);
    return Object.assign(Object.assign(Object.assign(Object.assign(Object.assign({ id: typeof raw.id === "string" && raw.id ? raw.id : fallbackId !== null && fallbackId !== void 0 ? fallbackId : (0, uuid_1.v4)(), name: clampStr((_c = raw.name) !== null && _c !== void 0 ? _c : "Modèle", 100, "template.name") }, (typeof raw.startTime === "string" ? { startTime: raw.startTime } : {})), (typeof raw.endTime === "string" ? { endTime: raw.endTime } : {})), (typeof raw.place === "string" ? { place: raw.place } : {})), (typeof raw.sessionContext === "string" ? { sessionContext: raw.sessionContext } : {})), { prep: {
            daysBefore: num(prep.daysBefore, interventions_1.DEFAULT_TEMPLATE.prep.daysBefore),
            endDaysBefore: num(prep.endDaysBefore, interventions_1.DEFAULT_TEMPLATE.prep.endDaysBefore),
            actions: Array.isArray(prep.actions) ? prep.actions.map(pickTemplateAction) : interventions_1.DEFAULT_TEMPLATE.prep.actions,
        }, closure: {
            daysAfter: num(closure.daysAfter, interventions_1.DEFAULT_TEMPLATE.closure.daysAfter),
            actions: Array.isArray(closure.actions) ? closure.actions.map(pickTemplateAction) : interventions_1.DEFAULT_TEMPLATE.closure.actions,
        } });
}
async function loadTemplates(uid) {
    const snap = await db_1.db.doc(`users/${uid}/data/meta`).get();
    const raw = snap.exists ? snap.data().interventionTemplates : null;
    return Array.isArray(raw) ? raw.map((r) => pickTemplate(r)) : [];
}
function fmtTemplate(t) {
    const acts = (as) => as.map((a) => `${a.title}${a.estimatedMin ? ` (${a.estimatedMin} min)` : ""}`).join(" · ");
    return `• [${t.id}] ${t.name}` +
        (t.startTime && t.endTime ? ` · ${(0, interventions_1.hmFr)(t.startTime)}–${(0, interventions_1.hmFr)(t.endTime)}` : "") +
        (t.place ? ` · ${t.place}` : "") + (t.sessionContext ? ` · ${t.sessionContext}` : "") +
        `\n    prépa J-${t.prep.daysBefore} → J-${t.prep.endDaysBefore} : ${acts(t.prep.actions)}` +
        `\n    clôture J → J+${t.closure.daysAfter} : ${acts(t.closure.actions)}`;
}
async function executeManageInterventionTemplates(uid, args) {
    var _a;
    const metaRef = db_1.db.doc(`users/${uid}/data/meta`);
    const templates = await loadTemplates(uid);
    const list = () => [
        `Modèles d'intervention (${templates.length}) — « default » = modèle intégré, toujours disponible :`,
        fmtTemplate(interventions_1.DEFAULT_TEMPLATE),
        ...templates.map(fmtTemplate),
    ].join("\n");
    switch (args.action) {
        case "list":
            return list();
        case "add": {
            if (!args.template)
                return "❌ template requis.";
            let t;
            try {
                t = pickTemplate(args.template);
            }
            catch (e) {
                return `❌ ${e instanceof Error ? e.message : e}`;
            }
            if (templates.some((x) => x.id === t.id))
                return `❌ Un modèle porte déjà l'id ${t.id}.`;
            await metaRef.set({ interventionTemplates: [...templates, t] }, { merge: true });
            return `✅ Modèle créé.\n${fmtTemplate(t)}\n→ add_intervention(projectId, title, date, templateId: "${t.id}")`;
        }
        case "update": {
            const idx = templates.findIndex((x) => x.id === args.templateId);
            if (idx < 0)
                return `❌ Modèle introuvable : ${args.templateId}`;
            let t;
            try {
                t = pickTemplate(Object.assign(Object.assign(Object.assign({}, templates[idx]), ((_a = args.template) !== null && _a !== void 0 ? _a : {})), { id: templates[idx].id }));
            }
            catch (e) {
                return `❌ ${e instanceof Error ? e.message : e}`;
            }
            const next = templates.slice();
            next[idx] = t;
            await metaRef.set({ interventionTemplates: next }, { merge: true });
            return `✅ Modèle mis à jour.\n${fmtTemplate(t)}`;
        }
        case "delete": {
            if (!templates.some((x) => x.id === args.templateId))
                return `❌ Modèle introuvable : ${args.templateId}`;
            await metaRef.set({ interventionTemplates: templates.filter((x) => x.id !== args.templateId) }, { merge: true });
            return `✅ Modèle ${args.templateId} supprimé (les interventions créées avec restent intactes).`;
        }
        default:
            return `❌ action inconnue : ${args.action} (list | add | update | delete)`;
    }
}
async function executeAddIntervention(uid, args) {
    var _a, _b, _c, _d, _e, _f;
    const ref = db_1.db.collection(`users/${uid}/projects`).doc(args.projectId);
    const snap = await ref.get();
    if (!snap.exists)
        return `Projet introuvable : ${args.projectId}`;
    const data = snap.data();
    const templates = await loadTemplates(uid);
    const tpl = args.templateId && args.templateId !== "default"
        ? templates.find((t) => t.id === args.templateId) : interventions_1.DEFAULT_TEMPLATE;
    if (!tpl)
        return `❌ Modèle introuvable : ${args.templateId} (manage_intervention_templates list)`;
    const input = {
        title: args.title, date: args.date,
        startTime: (_b = (_a = args.startTime) !== null && _a !== void 0 ? _a : tpl.startTime) !== null && _b !== void 0 ? _b : "", endTime: (_d = (_c = args.endTime) !== null && _c !== void 0 ? _c : tpl.endTime) !== null && _d !== void 0 ? _d : "",
        place: (_e = args.place) !== null && _e !== void 0 ? _e : tpl.place, templateId: tpl.id === "default" ? undefined : tpl.id, docUrl: args.docUrl,
    };
    const err = (0, interventions_1.validateInput)(input);
    if (err)
        return `❌ ${err}${!input.startTime ? " — passe startTime/endTime ou un modèle qui les fixe" : ""}.`;
    let prepActions, closureActions;
    try {
        prepActions = Array.isArray(args.prepActions) ? args.prepActions.map(pickTemplateAction) : undefined;
        closureActions = Array.isArray(args.closureActions) ? args.closureActions.map(pickTemplateAction) : undefined;
    }
    catch (e) {
        return `❌ ${e instanceof Error ? e.message : e}`;
    }
    const intervention = (0, interventions_1.buildIntervention)(input);
    const { prep, session, closure } = (0, interventions_1.buildInterventionTasks)(intervention, tpl, {
        phases: (_f = data.phases) !== null && _f !== void 0 ? _f : [],
        steps: Array.isArray(args.steps) ? args.steps.map(String) : [],
        prepActions, closureActions,
    });
    await ref.update({
        interventions: db_1.FieldValue.arrayUnion(intervention),
        tasks: db_1.FieldValue.arrayUnion(prep, session, closure),
        updatedAt: db_1.FieldValue.serverTimestamp(),
    });
    return [
        `✅ Intervention « ${intervention.title} » créée — ${(0, interventions_1.dayLabelFr)(args.date)} ${(0, interventions_1.hmFr)(input.startTime)}–${(0, interventions_1.hmFr)(input.endTime)}` +
            (input.place ? ` · ${input.place}` : "") + ` (modèle : ${tpl.name})`,
        `• interventionId : ${intervention.id}`,
        `• 📝 Préparer (${prep.startDate} → ${prep.endDate}, ${prep.actions.length} actions) : ${prep.id}`,
        `• 🎯 Séance (jalon, ${session.actions[0] && session.actions[0].checklist.length} étapes) : ${session.id}`,
        `• ✅ Clôturer (${closure.startDate} → ${closure.endDate}, ${closure.actions.length} actions) : ${closure.id}`,
        prep.phaseId ? `• phase : ${prep.phaseId}` : `⚠️ aucune phase ne couvre le ${args.date} — tâches sans phase (update_task {phaseId} si besoin)`,
    ].join("\n");
}
async function executeUpdateIntervention(uid, args) {
    const ref = db_1.db.collection(`users/${uid}/projects`).doc(args.projectId);
    const snap = await ref.get();
    if (!snap.exists)
        return `Projet introuvable : ${args.projectId}`;
    const data = snap.data();
    let interventions = sanitizeTasks(data.interventions);
    let tasks = sanitizeTasks(data.tasks);
    const notes = [];
    if (args.mergeFrom) {
        try {
            const r = (0, interventions_1.mergeInterventions)(tasks, interventions, args.interventionId, args.mergeFrom);
            tasks = r.tasks;
            interventions = r.interventions;
            for (const m of r.moved) {
                notes.push(`fusion : « ${m.task.title} » → ${m.role}${m.demoted ? " (rôle principal déjà tenu → extra)" : ""}`);
            }
            notes.push(`intervention ${args.mergeFrom} retirée`);
        }
        catch (e) {
            return `❌ ${e instanceof Error ? e.message : e}`;
        }
    }
    const idx = interventions.findIndex((i) => i.id === args.interventionId);
    if (idx < 0)
        return `Intervention introuvable : ${args.interventionId} (voir get_project → interventions)`;
    const before = interventions[idx];
    const after = Object.assign({}, before);
    if (args.title !== undefined)
        after.title = clampStr(args.title, 200, "title");
    if (args.date !== undefined) {
        assertDate(args.date, "date");
        after.date = args.date;
    }
    if (args.startTime !== undefined)
        after.startTime = args.startTime;
    if (args.endTime !== undefined)
        after.endTime = args.endTime;
    if (args.place !== undefined)
        after.place = args.place;
    if (args.docUrl !== undefined)
        after.docUrl = args.docUrl;
    const err = (0, interventions_1.validateInput)(after);
    if (err)
        return `❌ ${err}`;
    if (after.date !== before.date) {
        tasks = (0, interventions_1.shiftTasks)(tasks, String(after.id), String(before.date), String(after.date));
        notes.push(`tâches décalées du ${before.date} au ${after.date}`);
    }
    if (after.title !== before.title || after.date !== before.date)
        tasks = (0, interventions_1.retitleTasks)(tasks, after);
    if (after.startTime !== before.startTime || after.endTime !== before.endTime) {
        tasks = tasks.map((t) => {
            var _a;
            if (t.interventionId !== after.id || t.interventionRole !== "session")
                return t;
            const acts = ((_a = t.actions) !== null && _a !== void 0 ? _a : []).map((a, i) => {
                var _a;
                return i === 0
                    ? Object.assign(Object.assign({}, a), { title: `Dérouler la séance (${(0, interventions_1.hmFr)(String(after.startTime))}–${(0, interventions_1.hmFr)(String(after.endTime))})`, estimatedMin: (0, interventions_1.netSlotMin)({ startTime: String(after.startTime), endTime: String(after.endTime), breaks: (_a = after.breaks) !== null && _a !== void 0 ? _a : [] }) }) : a;
            });
            return Object.assign(Object.assign({}, t), { actions: acts });
        });
        notes.push("créneau mis à jour");
    }
    if (args.status !== undefined) {
        if (!["planned", "done", "cancelled"].includes(args.status))
            return `❌ status invalide : ${args.status}`;
        after.status = args.status;
        if (args.status === "cancelled") {
            tasks = tasks.map((t) => t.interventionId === after.id && t.status !== "done" ? Object.assign(Object.assign({}, t), { status: "skipped" }) : t);
            notes.push("séance annulée : tâches restantes passées en skipped");
        }
        if (args.status === "done") {
            tasks = tasks.map((t) => t.interventionId === after.id && t.interventionRole === "session" ? Object.assign(Object.assign({}, t), { status: "done" }) : t);
        }
    }
    if (args.debriefText !== undefined)
        after.debriefText = clampStr(args.debriefText, 5000, "debriefText");
    if (args.carryOver !== undefined) {
        const items = args.carryOver.map((s) => String(s).trim()).filter(Boolean);
        after.carryOver = items.map((title) => ({ id: (0, uuid_1.v4)(), title, done: false, doneAt: null }));
        const r = (0, interventions_1.applyCarryOver)(tasks, interventions.map((i, k) => (k === idx ? after : i)), String(after.id), items);
        tasks = r.tasks;
        notes.push(r.nextId
            ? `${items.length} point(s) à reprendre poussés dans la prépa de la séance suivante`
            : `${items.length} point(s) à reprendre notés (pas de séance suivante planifiée : ils seront repris à la création de la prochaine)`);
    }
    if (args.debriefText !== undefined || args.carryOver !== undefined)
        after.debriefAt = new Date().toISOString();
    const next = interventions.slice();
    next[idx] = after;
    await ref.update({ interventions: next, tasks, updatedAt: db_1.FieldValue.serverTimestamp() });
    return `✅ Intervention « ${after.title} » mise à jour — ${(0, interventions_1.dayLabelFr)(String(after.date))} ${(0, interventions_1.hmFr)(String(after.startTime))}–${(0, interventions_1.hmFr)(String(after.endTime))}` +
        (notes.length ? `\n• ${notes.join("\n• ")}` : "");
}
async function executeDeleteIntervention(uid, args) {
    var _a;
    const ref = db_1.db.collection(`users/${uid}/projects`).doc(args.projectId);
    const snap = await ref.get();
    if (!snap.exists)
        return `Projet introuvable : ${args.projectId}`;
    const data = snap.data();
    const interventions = sanitizeTasks(data.interventions);
    const target = interventions.find((i) => i.id === args.interventionId);
    if (!target)
        return `Intervention introuvable : ${args.interventionId}`;
    const mode = (_a = args.tasks) !== null && _a !== void 0 ? _a : "detach";
    if (!["detach", "cancel", "delete"].includes(mode))
        return `❌ tasks invalide : ${mode} (detach | cancel | delete)`;
    let tasks = sanitizeTasks(data.tasks);
    const lines = [];
    if (mode === "detach") {
        const r = (0, interventions_1.detachAll)(tasks, String(target.id));
        tasks = r.tasks;
        for (const t of r.touched)
            lines.push(`• « ${t.title} » (${t.id}) : détachée, inchangée${t.isMilestone ? " (redevient un jalon simple)" : ""}`);
    }
    else if (mode === "cancel") {
        for (const t of tasks)
            if (t.interventionId === target.id)
                lines.push(`• « ${t.title} » (${t.id}) : ${t.status === "done" ? "déjà faite, conservée" : "passée en skipped"}`);
        tasks = tasks.map((t) => t.interventionId === target.id && t.status !== "done" ? Object.assign(Object.assign({}, t), { status: "skipped" }) : t);
    }
    else {
        for (const t of tasks)
            if (t.interventionId === target.id)
                lines.push(`• « ${t.title} » (${t.id}) : supprimée`);
        tasks = tasks.filter((t) => t.interventionId !== target.id);
    }
    await ref.update({
        interventions: interventions.filter((i) => i.id !== target.id),
        tasks,
        updatedAt: db_1.FieldValue.serverTimestamp(),
    });
    return `✅ Intervention « ${target.title} » (${(0, interventions_1.dayLabelFr)(String(target.date))}) supprimée — tâches : ${mode}\n` +
        (lines.length ? lines.join("\n") : "• aucune tâche liée");
}
// « Planifier la prépa » (§ 2.3) : les actions ouvertes de la 📝 d'une
// intervention → trous du programme (veille au soir d'abord, impression sur
// place collée au début de la séance). apply:false (défaut) = proposition ;
// apply:true = écriture via schedule_day(mode:"fill"), jour par jour.
async function executePlanPrep(uid, args) {
    var _a, _b, _c, _d, _e;
    const ref = db_1.db.collection(`users/${uid}/projects`).doc(args.projectId);
    const snap = await ref.get();
    if (!snap.exists)
        return `Projet introuvable : ${args.projectId}`;
    const data = snap.data();
    const interventions = sanitizeTasks(data.interventions);
    const i = interventions.find((x) => x.id === args.interventionId);
    if (!i)
        return `Intervention introuvable : ${args.interventionId} (get_project → interventions[])`;
    const tasks = sanitizeTasks(data.tasks);
    const prep = tasks.find((t) => t.interventionId === i.id && t.interventionRole === "prep");
    if (!prep)
        return `❌ « ${i.title} » n'a pas de tâche 📝 Préparer rattachée (update_task {interventionId, interventionRole:"prep"}).`;
    const open = ((_a = prep.actions) !== null && _a !== void 0 ? _a : []).filter((a) => a.done !== true).map((a) => {
        var _a, _b;
        return ({
            id: String(a.id), title: String((_a = a.title) !== null && _a !== void 0 ? _a : ""),
            estimatedMin: (_b = estimatedMinOrUndefined(a.estimatedMin)) !== null && _b !== void 0 ? _b : null,
            contexts: (0, contexts_1.contextsOf)(a),
        });
    });
    if (!open.length)
        return `✅ Rien à planifier : toutes les actions de « ${prep.title} » sont faites.`;
    // Journée active + heure locale de l'utilisateur.
    const metaSnap = await db_1.db.doc(`users/${uid}/data/meta`).get();
    const meta = metaSnap.exists ? metaSnap.data() : {};
    const dw = ((_b = meta.dayWindow) !== null && _b !== void 0 ? _b : {});
    const window = {
        startMin: typeof dw.startMin === "number" ? dw.startMin : 8 * 60,
        endMin: typeof dw.endMin === "number" ? dw.endMin : 22 * 60,
    };
    const tz = typeof meta.tzOffsetMin === "number" ? meta.tzOffsetMin : 120;
    const local = new Date(Date.now() + tz * 60000);
    const today = local.toISOString().slice(0, 10);
    const nowMin = local.getUTCHours() * 60 + local.getUTCMinutes();
    const D = String(i.date);
    if (D < today)
        return `❌ La séance « ${i.title} » est passée (${D}).`;
    const earliest = String((_c = prep.startDate) !== null && _c !== void 0 ? _c : "").slice(0, 10) || undefined;
    const firstDay = [(0, prep_planner_1.addDays)(D, -7), earliest !== null && earliest !== void 0 ? earliest : today, today].sort().pop();
    const existing = {};
    for (let d = firstDay; d <= D; d = (0, prep_planner_1.addDays)(d, 1)) {
        const s = await db_1.db.doc(`users/${uid}/daily_schedules/${d}`).get();
        existing[d] = s.exists ? ((_d = s.data().blocks) !== null && _d !== void 0 ? _d : []) : [];
    }
    const eveningFromMin = args.eveningFrom ? (0, schedule_dedupe_2.toMin)(args.eveningFrom) : undefined;
    const plan = (0, prep_planner_1.planPrep)(Object.assign({ intervention: { date: D, startTime: String(i.startTime), title: String(i.title) }, actions: open, existing, window, today, nowMin, earliest }, (eveningFromMin ? { eveningFromMin } : {})));
    const lines = plan.placements.map((p) => `• ${p.date} ${(0, interventions_1.hmFr)(p.startTime)} (${p.durationMin} min) — ${p.title} · ${p.why}`);
    const missing = plan.unplaced.map((u) => `⚠️ « ${u.title} » (${u.durationMin} min) : aucun trou` +
        (u.alternatives.length
            ? ` — repli possible : ${u.alternatives.map((a) => `${a.date} ${(0, interventions_1.hmFr)(a.startTime)}`).join(" ou ")}`
            : " — libère un créneau ou réduis l'estimation"));
    const head = `📝 Prépa de « ${i.title} » (${(0, interventions_1.dayLabelFr)(D)} ${(0, interventions_1.hmFr)(String(i.startTime))}) — ${open.length} action(s) ouverte(s), journée active ${(0, interventions_1.hmFr)(fromMinHm(window.startMin))}–${(0, interventions_1.hmFr)(fromMinHm(window.endMin))}`;
    if (args.apply !== true) {
        return [
            head,
            ...(lines.length ? ["Proposition (rien n'est écrit) :", ...lines] : ["Aucun créneau trouvé."]),
            ...missing,
            lines.length ? `→ Pour poser ces blocs : plan_prep(projectId, interventionId, apply:true). Pour un autre soir de début : eveningFrom:"19:00".` : "",
        ].filter(Boolean).join("\n");
    }
    const byDate = new Map();
    for (const p of plan.placements)
        byDate.set(p.date, [...((_e = byDate.get(p.date)) !== null && _e !== void 0 ? _e : []), p]);
    const out = [head, `✅ ${plan.placements.length} bloc(s) posé(s) :`];
    for (const [date, ps] of byDate) {
        const res = await executeScheduleDay(uid, date, ps.map((p) => ({
            startTime: p.startTime, durationMin: p.durationMin, title: p.title, category: "project",
            projectId: args.projectId, taskId: String(prep.id), actionId: p.actionId,
        })), { mode: "fill", generatedBy: "claude" });
        out.push(res);
    }
    out.push(...missing);
    return out.join("\n");
}
const fromMinHm = (m) => `${String(Math.floor(m / 60)).padStart(2, "0")}:${String(m % 60).padStart(2, "0")}`;
// ── Revue hebdo des orphelins (§ 2.5 + B5 + B7) ──────────────────────────────
function toAuditProject(id, d) {
    var _a, _b;
    return {
        id,
        title: String((_a = d.title) !== null && _a !== void 0 ? _a : id),
        status: String((_b = d.status) !== null && _b !== void 0 ? _b : "active"),
        paused: d.paused === true,
        startDate: typeof d.startDate === "string" ? d.startDate : undefined,
        endDate: typeof d.endDate === "string" ? d.endDate : undefined,
        parentProjectId: typeof d.parentProjectId === "string" ? d.parentProjectId : null,
        phases: sanitizeTasks(d.phases),
        tasks: sanitizeTasks(d.tasks),
        interventions: sanitizeTasks(d.interventions),
    };
}
async function loadAuditProjects(uid) {
    const snap = await db_1.db.collection(`users/${uid}/projects`).get();
    return snap.docs.map((doc) => toAuditProject(doc.id, doc.data()));
}
/** Revue à valider : tâches sans phase / hors phase, jalons passés, clôtures
 *  non faites, projets inactifs avec séances à venir, projets sans séance à
 *  14 jours, doublons, triplets non migrés. Ne modifie rien. */
async function executeWeeklyReview(uid, args = {}) {
    const projects = await loadAuditProjects(uid);
    const today = todayInParis();
    const findings = (0, project_audit_1.auditProjects)(projects, today, { horizonDays: args.horizonDays });
    return (0, project_audit_1.formatFindings)(findings, today);
}
/** B5 : séances à venir d'un projet qu'on archive — à signaler, pas à taire. */
async function upcomingWarning(uid, projectId, data) {
    const up = (0, project_audit_1.upcomingSessions)(toAuditProject(projectId, data), todayInParis());
    if (!up.length)
        return "";
    return `\n⚠️ ${up.length} séance(s) à venir dans ce projet : ${up.slice(0, 4).map((u) => `${u.date} « ${u.title} »`).join(" · ")}${up.length > 4 ? "…" : ""}. ` +
        `Annule-les (update_intervention status:"cancelled" / update_task_status skipped) ou réactive le projet si elles ont lieu — la revue hebdo (weekly_review) le rappellera.`;
}
async function executeMigrateInterventions(uid, args) {
    const dryRun = args.dryRun !== false;
    const col = db_1.db.collection(`users/${uid}/projects`);
    const docs = args.projectId
        ? [await col.doc(args.projectId).get()].filter((d) => d.exists)
        : (await col.where("status", "==", "active").get()).docs;
    if (!docs.length)
        return args.projectId ? `Projet introuvable : ${args.projectId}` : "Aucun projet actif.";
    const out = [dryRun
            ? "🔎 Simulation (dryRun) — rien n'est écrit. Relance avec dryRun:false pour appliquer."
            : "✅ Migration appliquée."];
    let total = 0;
    for (const d of docs) {
        const data = d.data();
        let tasks = sanitizeTasks(data.tasks);
        const { triplets: found, warnings } = (0, interventions_1.detectTriplets)(tasks, {
            description: typeof data.description === "string" ? data.description : "",
            defaultStart: args.defaultStart, defaultEnd: args.defaultEnd, includeOrphans: args.includeOrphans === true,
        });
        if (!found.length && !warnings.length)
            continue;
        total += found.length;
        out.push(`\n${data.title} (${d.id}) — ${found.length} intervention(s) :`);
        const created = [];
        for (const t of found) {
            const flag = t.timeSource === "default" ? " ⚠️ créneau par défaut (passe defaultStart/defaultEnd ou corrige après avec update_intervention)" : "";
            const pauses = t.breaks.length ? ` (pause ${t.breaks.map((b) => `${(0, interventions_1.hmFr)(b.start)}–${(0, interventions_1.hmFr)(b.end)}`).join(", ")})` : "";
            const extras = t.extras.length ? ` · +${t.extras.length} 🏁 le même jour (extra)` : "";
            const orphan = t.orphan ? " · orphelin (ni 📝 ni ✅)" : "";
            out.push(`• ${t.date} ${(0, interventions_1.hmFr)(t.startTime)}–${(0, interventions_1.hmFr)(t.endTime)}${pauses} « ${t.groupLabel} » — 📝 ${t.prep ? "oui" : "—"} · ✅ ${t.closure ? "oui" : "—"}${extras}${orphan}${flag}`);
            if (!dryRun) {
                const r = (0, interventions_1.applyTriplet)(tasks, t);
                tasks = r.tasks;
                created.push(r.intervention);
            }
        }
        for (const w of warnings)
            out.push(`⚠️ ${w.text}`);
        if (!dryRun && created.length) {
            await col.doc(d.id).update({
                interventions: db_1.FieldValue.arrayUnion(...created),
                tasks,
                updatedAt: db_1.FieldValue.serverTimestamp(),
            });
        }
    }
    if (!total)
        out.push("Aucun triplet 📝 / 🎯 / ✅ non migré trouvé (jalons seuls ignorés : includeOrphans:true pour les migrer).");
    return out.join("\n");
}
// Ajoute un bloc de préparation la veille (kind:"prep") au programme existant
// SANS le remplacer. Idempotent sur (prepForDate, prepForBlockId).
async function executeAddPrepBlock(uid, args) {
    var _a, _b;
    const { date, startTime, title, prepForDate, prepForBlockId } = args;
    if (!/^\d{4}-\d{2}-\d{2}$/.test(date))
        return `Date invalide : ${date}. Format attendu : YYYY-MM-DD`;
    if (!/^\d{4}-\d{2}-\d{2}$/.test(prepForDate))
        return `prepForDate invalide : ${prepForDate}. Format attendu : YYYY-MM-DD`;
    if (!startTime || !title || !prepForBlockId)
        return `startTime, title et prepForBlockId sont requis.`;
    const ref = db_1.db.doc(`users/${uid}/daily_schedules/${date}`);
    const snap = await ref.get();
    const prepBlock = {
        id: (0, uuid_1.v4)(),
        startTime,
        durationMin: (_a = args.durationMin) !== null && _a !== void 0 ? _a : 5,
        title,
        category: "personal",
        projectId: null,
        taskId: null,
        activityId: null,
        actionId: null,
        status: "pending",
        doneAt: null,
        kind: "prep",
        prepForDate,
        prepForBlockId,
    };
    if (!snap.exists) {
        await ref.set({
            date,
            generatedBy: "claude",
            generatedAt: db_1.FieldValue.serverTimestamp(),
            blocks: [prepBlock],
        });
        return `✅ Bloc de préparation ajouté le ${date} à ${startTime} — « ${title} » (pour le bloc du ${prepForDate}).`;
    }
    const data = snap.data();
    const blocks = (_b = data.blocks) !== null && _b !== void 0 ? _b : [];
    // Idempotence : une prep non supprimée pointant déjà vers ce (prepForDate, prepForBlockId) suffit.
    const exists = blocks.some((b) => b.kind === "prep" &&
        b.status !== "deleted" &&
        b.prepForDate === prepForDate &&
        b.prepForBlockId === prepForBlockId);
    if (exists) {
        return `ℹ️ Un bloc de préparation pour ce créneau existe déjà le ${date} — rien ajouté (idempotent).`;
    }
    blocks.push(prepBlock);
    await ref.update({ blocks });
    return `✅ Bloc de préparation ajouté le ${date} à ${startTime} — « ${title} » (pour le bloc du ${prepForDate}).`;
}
// ── Événement daté : « J'accompagne maman le 12 à son RDV à 14h » — un bloc
// posé DIRECTEMENT dans le programme du jour concerné. La durée est un fait
// utilisateur : sans durationMin, l'outil REFUSE et demande de la demander
// (jamais de durée inventée). Retourne aussi les instructions Google Calendar
// (connecteur GCal côté conversation, en attendant l'API native).
async function executeAddEvent(uid, args) {
    var _a;
    const { date, startTime, title } = args;
    if (!/^\d{4}-\d{2}-\d{2}$/.test(date !== null && date !== void 0 ? date : "")) {
        return `Date invalide : ${date}. Format attendu : YYYY-MM-DD`;
    }
    if (!/^\d{2}:\d{2}$/.test(startTime !== null && startTime !== void 0 ? startTime : "")) {
        return `Heure invalide : ${startTime}. Format attendu : HH:mm`;
    }
    if (!(title === null || title === void 0 ? void 0 : title.trim()))
        return "title est requis.";
    if (!args.durationMin || args.durationMin <= 0) {
        return ("⛔ Durée manquante — ne l'invente pas. Demande à l'utilisateur : " +
            `« Combien de temps estimes-tu pour “${title}” ? » puis rappelle ` +
            "add_event avec durationMin.");
    }
    const durationMin = Math.min(720, Math.round(args.durationMin));
    const ref = db_1.db.doc(`users/${uid}/daily_schedules/${date}`);
    const snap = await ref.get();
    const block = {
        id: (0, uuid_1.v4)(),
        startTime,
        durationMin,
        title: title.trim(),
        category: "personal",
        projectId: null,
        taskId: null,
        activityId: null,
        actionId: null,
        status: "pending",
        doneAt: null,
        subtitle: "événement",
    };
    if (!snap.exists) {
        await ref.set({
            date,
            generatedBy: "claude",
            generatedAt: db_1.FieldValue.serverTimestamp(),
            blocks: [block],
        });
    }
    else {
        const data = snap.data();
        const blocks = (_a = data.blocks) !== null && _a !== void 0 ? _a : [];
        // Idempotence : même titre non supprimé à la même heure le même jour.
        const exists = blocks.some((b) => {
            var _a;
            return b.status !== "deleted" &&
                b.startTime === startTime &&
                String((_a = b.title) !== null && _a !== void 0 ? _a : "").trim().toLowerCase() === title.trim().toLowerCase();
        });
        if (exists) {
            return `ℹ️ « ${title} » existe déjà le ${date} à ${startTime} — rien ajouté (idempotent).`;
        }
        blocks.push(block);
        await ref.update({ blocks });
    }
    const endMin = parseInt(startTime.slice(0, 2), 10) * 60 +
        parseInt(startTime.slice(3, 5), 10) +
        durationMin;
    const endTime = `${String(Math.floor((endMin % 1440) / 60)).padStart(2, "0")}:${String(endMin % 60).padStart(2, "0")}`;
    let out = `✅ « ${title} » posé le ${date} à ${startTime} (${durationMin} min) dans le programme.`;
    if (args.syncToCalendar !== false) {
        // Agenda natif connecté : le trigger Firestore synchronise ce bloc tout
        // seul — aucune instruction connecteur à donner.
        if (await nativeGcalSync(uid)) {
            out += `\n\n🗓️ Google Agenda : synchronisé automatiquement (agenda connecté dans l'app) — rien d'autre à faire.`;
        }
        else {
            out +=
                `\n\n📅 Google Calendar (si le connecteur est disponible) : ` +
                    `create_event { summary: "${title.trim()}", start: "${date}T${startTime}:00", ` +
                    `end: "${date}T${endTime}:00", description: "source: productivitwo" }. ` +
                    `Sans connecteur : dis-le simplement, le bloc programme suffit. ` +
                    `(L'utilisateur peut aussi connecter Google Agenda dans Paramètres → l'app synchronisera toute seule.)`;
        }
    }
    return out;
}
// ── Session de définition : écrit la fiche domaine (intention/vital/modalités)
// sur la collection domains EXISTANTE. Appelé à chaque élément validé.
async function executeSaveDomainDefinition(uid, args) {
    var _a, _b, _c, _d, _e, _f, _g, _h;
    if (!((_a = args.name) === null || _a === void 0 ? void 0 : _a.trim()))
        return "name requis.";
    const col = db_1.db.collection(`users/${uid}/domains`);
    // Upsert : id connu → doc ; sinon match par nom (insensible à la casse,
    // domaines non supprimés) ; sinon création en draft.
    let docId = args.domainId;
    let existing = null;
    if (docId) {
        const snap = await col.doc(docId).get();
        if (snap.exists)
            existing = snap.data();
        else
            docId = undefined;
    }
    if (!docId) {
        const all = await col.get();
        const match = all.docs.find((d) => {
            var _a;
            const v = d.data();
            return v.deleted !== true &&
                String((_a = v.name) !== null && _a !== void 0 ? _a : "").trim().toLowerCase() === args.name.trim().toLowerCase();
        });
        if (match) {
            docId = match.id;
            existing = match.data();
        }
    }
    if (!docId)
        docId = (0, uuid_1.v4)();
    const update = {
        id: docId,
        name: (_b = existing === null || existing === void 0 ? void 0 : existing.name) !== null && _b !== void 0 ? _b : args.name.trim(),
        deleted: (_c = existing === null || existing === void 0 ? void 0 : existing.deleted) !== null && _c !== void 0 ? _c : false,
    };
    if (args.intention !== undefined)
        update.intention = args.intention;
    if (args.vitalMinimum !== undefined) {
        update.vitalMinimum = args.vitalMinimum.map((v) => {
            var _a, _b, _c;
            return ({
                label: v.label,
                metric: (_a = v.metric) !== null && _a !== void 0 ? _a : "",
                target: (_b = v.target) !== null && _b !== void 0 ? _b : 0,
                period: (_c = v.period) !== null && _c !== void 0 ? _c : "week",
            });
        });
    }
    if (args.modalities !== undefined) {
        update.modalities = args.modalities.map((m) => ({ label: m }));
    }
    if (args.wantedArtifacts !== undefined)
        update.wantedArtifacts = args.wantedArtifacts;
    // Suivi déclaré + territoire défendu (session « sans données », tour 20).
    if (args.tracking === "timed" || args.tracking === "declared") {
        update.tracking = args.tracking;
    }
    if (args.protectedSlots !== undefined) {
        update.protectedSlots = args.protectedSlots.filter((s) => /^(mon|tue|wed|thu|fri|sat|sun)_(morning|afternoon|evening|day)$/.test(s));
    }
    const currentStatus = String((_d = existing === null || existing === void 0 ? void 0 : existing.definitionStatus) !== null && _d !== void 0 ? _d : "none");
    if (args.finalize === true) {
        update.definitionStatus = "active";
        if (!(existing === null || existing === void 0 ? void 0 : existing.definedAt))
            update.definedAt = new Date().toISOString();
    }
    else if (currentStatus === "none") {
        update.definitionStatus = "draft"; // session en cours — reprise gratuite
    }
    await col.doc(docId).set(update, { merge: true });
    const parts = [`✅ Domaine « ${update.name} » (id: ${docId})`];
    if (args.intention)
        parts.push(`intention posée`);
    if ((_e = args.vitalMinimum) === null || _e === void 0 ? void 0 : _e.length)
        parts.push(`${args.vitalMinimum.length} vital(aux)`);
    if ((_f = args.modalities) === null || _f === void 0 ? void 0 : _f.length)
        parts.push(`${args.modalities.length} modalité(s)`);
    if ((_g = args.wantedArtifacts) === null || _g === void 0 ? void 0 : _g.length)
        parts.push(`${args.wantedArtifacts.length} artefact(s) voulu(s)`);
    if (args.tracking === "declared")
        parts.push(`suivi déclaré (pas de chrono, pas de blocs, pas de score)`);
    if ((_h = args.protectedSlots) === null || _h === void 0 ? void 0 : _h.length)
        parts.push(`territoire défendu : ${args.protectedSlots.join(", ")}`);
    if (args.finalize)
        parts.push(`FINALISÉ — je m'en servirai chaque jour`);
    return parts.join(" · ");
}
async function executeListObjectives(uid) {
    const now = new Date();
    const todayStr = todayInParis(now);
    const sevenDaysAgo = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000);
    const [objectivesSnap, activitiesSnap, sessionsSnap, habitHitsSnap] = await Promise.all([
        db_1.db.collection(`users/${uid}/strategic_objectives`).get(),
        db_1.db.collection(`users/${uid}/activities`).get(),
        db_1.db.collection(`users/${uid}/sessions`)
            .where("startAt", ">=", sevenDaysAgo.toISOString()).get(),
        // ts = chaîne ISO (voir get_user_context) — jamais un Timestamp.
        db_1.db.collection(`users/${uid}/habitHits`)
            .where("ts", ">=", sevenDaysAgo.toISOString()).get(),
    ]);
    const active = objectivesSnap.docs
        .map((d) => { var _a; return (Object.assign(Object.assign({}, d.data()), { id: (_a = d.data().id) !== null && _a !== void 0 ? _a : d.id })); })
        .filter((v) => { var _a; return String((_a = v.status) !== null && _a !== void 0 ? _a : "active") === "active"; });
    if (active.length === 0) {
        return "Aucun objectif stratégique actif. Propose une session de définition (prompt definir-objectif) ou save_objective directement.";
    }
    const summaries = (0, objectives_1.summarizeObjectives)(active, activitiesSnap.docs.map((d) => d.data()), (0, sessions_audit_1.liveSessionDocs)(sessionsSnap).map((d) => d.data()), habitHitsSnap.docs.map((d) => d.data()), todayStr);
    // Détail complet (description, dates, projets) + progression compacte
    const byId = new Map(active.map((o) => [String(o.id), o]));
    const result = summaries.map((s) => {
        var _a, _b, _c;
        const raw = byId.get(s.id);
        return Object.assign(Object.assign({}, s), { description: (_a = raw === null || raw === void 0 ? void 0 : raw.description) !== null && _a !== void 0 ? _a : null, domainId: (_b = raw === null || raw === void 0 ? void 0 : raw.domainId) !== null && _b !== void 0 ? _b : null, startDate: (_c = raw === null || raw === void 0 ? void 0 : raw.startDate) !== null && _c !== void 0 ? _c : null, projectIds: Array.isArray(raw === null || raw === void 0 ? void 0 : raw.projectIds) ? raw === null || raw === void 0 ? void 0 : raw.projectIds : [] });
    });
    return JSON.stringify({ today: todayStr, objectives: result }, null, 2);
}
async function executeSaveObjective(uid, args) {
    var _a, _b, _c, _d, _e, _f, _g, _h, _j, _l, _m;
    if (!((_a = args.title) === null || _a === void 0 ? void 0 : _a.trim()))
        return "title requis.";
    const col = db_1.db.collection(`users/${uid}/strategic_objectives`);
    let picked;
    try {
        picked = pickStrategicObjective(args);
    }
    catch (e) {
        return `❌ ${e.message}`;
    }
    // Les engagements doivent référencer des activités existantes du bon type.
    const hasCommitments = ((_c = (_b = args.timeCommitments) === null || _b === void 0 ? void 0 : _b.length) !== null && _c !== void 0 ? _c : 0) > 0 || ((_e = (_d = args.routineCommitments) === null || _d === void 0 ? void 0 : _d.length) !== null && _e !== void 0 ? _e : 0) > 0;
    if (hasCommitments) {
        const actsSnap = await db_1.db.collection(`users/${uid}/activities`).get();
        const actById = new Map();
        actsSnap.docs.forEach((d) => {
            var _a;
            const v = d.data();
            if (!v.deleted)
                actById.set(String((_a = v.id) !== null && _a !== void 0 ? _a : d.id), v);
        });
        const problems = [];
        for (const c of (_f = args.timeCommitments) !== null && _f !== void 0 ? _f : []) {
            const a = actById.get(c.activityId);
            if (!a)
                problems.push(`timeCommitment : activité introuvable ${c.activityId}`);
            else if (a.type !== "time")
                problems.push(`timeCommitment : "${a.name}" n'est pas une activité-temps (type=${a.type})`);
        }
        for (const c of (_g = args.routineCommitments) !== null && _g !== void 0 ? _g : []) {
            const a = actById.get(c.activityId);
            if (!a)
                problems.push(`routineCommitment : activité introuvable ${c.activityId}`);
            else if (a.type !== "habit" && a.type !== "action")
                problems.push(`routineCommitment : "${a.name}" n'est pas une routine (type=${a.type})`);
        }
        if (problems.length > 0) {
            return `❌ Engagements invalides :\n- ${problems.join("\n- ")}\nRécupère les ids via get_user_context et réessaie.`;
        }
    }
    // Upsert : id connu → doc ; sinon match par titre (insensible à la casse,
    // objectifs non archivés) ; sinon création.
    let docId = args.objectiveId;
    let exists = false;
    if (docId) {
        const snap = await col.doc(docId).get();
        if (snap.exists)
            exists = true;
        else
            docId = undefined;
    }
    if (!docId) {
        const all = await col.get();
        const match = all.docs.find((d) => {
            var _a, _b;
            const v = d.data();
            return String((_a = v.status) !== null && _a !== void 0 ? _a : "active") !== "archived" &&
                String((_b = v.title) !== null && _b !== void 0 ? _b : "").trim().toLowerCase() === args.title.trim().toLowerCase();
        });
        if (match) {
            docId = match.id;
            exists = true;
        }
    }
    if (!docId)
        docId = (0, uuid_1.v4)();
    const update = Object.assign(Object.assign({}, picked), { id: docId, updatedAt: db_1.FieldValue.serverTimestamp() });
    if (!exists) {
        update.createdAt = db_1.FieldValue.serverTimestamp();
        if (update.status === undefined)
            update.status = "active";
    }
    if (args.projectIds !== undefined && args.projectIds.length > 0) {
        update.projectIds = db_1.FieldValue.arrayUnion(...args.projectIds.map(String));
    }
    await col.doc(docId).set(update, { merge: true });
    const parts = [
        `✅ Objectif « ${args.title.trim()} » ${exists ? "mis à jour" : "créé"} (id: ${docId})`,
    ];
    if (args.kpiTarget)
        parts.push(`KPI : ${args.kpiTarget}`);
    if (args.endDate || args.horizonLabel)
        parts.push(`échéance : ${(_h = args.endDate) !== null && _h !== void 0 ? _h : args.horizonLabel}`);
    if ((_j = args.timeCommitments) === null || _j === void 0 ? void 0 : _j.length)
        parts.push(`${args.timeCommitments.length} engagement(s) temps`);
    if ((_l = args.routineCommitments) === null || _l === void 0 ? void 0 : _l.length)
        parts.push(`${args.routineCommitments.length} routine(s) suivie(s)`);
    if ((_m = args.projectIds) === null || _m === void 0 ? void 0 : _m.length)
        parts.push(`${args.projectIds.length} projet(s) lié(s)`);
    if (args.status === "archived")
        parts.push(`ARCHIVÉ`);
    if (args.status === "done")
        parts.push(`🎉 ATTEINT`);
    return parts.join(" · ");
}
async function executeComputeTimeBudget(uid) {
    const now = new Date();
    const today = todayInParis(now);
    const twelveWeeksAgo = new Date(now.getTime() - 84 * 24 * 60 * 60 * 1000);
    const [sessionsSnap, activitiesSnap] = await Promise.all([
        db_1.db.collection(`users/${uid}/sessions`)
            .where("startAt", ">=", twelveWeeksAgo.toISOString())
            .get(),
        db_1.db.collection(`users/${uid}/activities`).get(),
    ]);
    const activities = activitiesSnap.docs
        .map((d) => d.data())
        .filter((v) => !v.deleted && v.type === "time");
    // Indexer les sessions par activité ET par jour (jours actifs = jours où l'activité a été loggée).
    // La cible = p90 des minutes des JOURS ACTIFS — pas une moyenne diluée sur 84 jours (qui écrase
    // les activités faites par à-coups à ~1 min). Cohérent avec la réf p90 du score de productivité.
    const dailyMinByActivity = new Map();
    for (const doc of (0, sessions_audit_1.liveSessionDocs)(sessionsSnap)) {
        const v = doc.data();
        if (!v.endAt)
            continue;
        const mins = Math.round((new Date(v.endAt).getTime() - new Date(v.startAt).getTime()) / 60000);
        if (mins <= 0)
            continue;
        const dayKey = todayInParis(new Date(v.startAt));
        if (!dailyMinByActivity.has(v.activityId))
            dailyMinByActivity.set(v.activityId, new Map());
        const days = dailyMinByActivity.get(v.activityId);
        days.set(dayKey, (days.get(dayKey) || 0) + mins);
    }
    const MIN_ACTIVE_DAYS = 3; // minimum pour calculer une cible
    const P90_MIN_DAYS = 30; // sous ce seuil, p90 ≈ max → on prend la médiane
    const FLOOR_MIN = 5; // une cible de jauge sous 5 min n'a pas de sens
    const SLEEP_FLOOR_MIN = 360; // plancher sommeil 6h : minimum santé quasi-universel
    // (objectif à atteindre si on dort moins), pas une norme imposée
    const percentile = (vals, p) => {
        if (vals.length === 0)
            return 0;
        const sorted = [...vals].sort((a, b) => a - b);
        const idx = Math.min(sorted.length - 1, Math.floor(p * sorted.length));
        return sorted[idx];
    };
    const budgets = activities.map((a) => {
        var _a, _b, _c, _d;
        const dailyTotals = Array.from((_b = (_a = dailyMinByActivity.get(a.id)) === null || _a === void 0 ? void 0 : _a.values()) !== null && _b !== void 0 ? _b : []);
        const activeDays = dailyTotals.length;
        const isSleep = /sommeil|sleep/i.test(a.name);
        const hasEnoughData = activeDays >= MIN_ACTIVE_DAYS;
        // Cible adaptative : sous 30 jours loggués, le p90 colle au MAX (échantillon
        // trop petit, floor(0.9·n) = dernier point) → on prend la MÉDIANE (jour typique,
        // robuste). À ≥30 jours, le p90 devient un vrai « top 10% » aspirationnel.
        const usesP90 = activeDays >= P90_MIN_DAYS;
        const stat = hasEnoughData
            ? Math.round(percentile(dailyTotals, usesP90 ? 0.90 : 0.50))
            : 0;
        let recommendedGoalMin;
        if (isSleep) {
            // Plancher 6h pour le sommeil : minimum santé quasi-universel. Si tu dors
            // plus, c'est ta médiane/p90 qui est prise ; le plancher ne mord que si tu
            // logges réellement moins de 6h (et devient alors un objectif à atteindre).
            recommendedGoalMin = Math.max(SLEEP_FLOOR_MIN, stat);
        }
        else {
            recommendedGoalMin = hasEnoughData ? Math.max(FLOOR_MIN, stat) : null;
        }
        return {
            id: a.id,
            name: a.name,
            currentGoalMin: (_c = a.goalMin) !== null && _c !== void 0 ? _c : null,
            targetSource: (_d = a.targetSource) !== null && _d !== void 0 ? _d : "default",
            activeDays,
            statMinActiveDay: stat,
            statBasis: hasEnoughData ? (usesP90 ? "p90" : "median") : "none",
            hasEnoughData,
            isSleep,
            recommendedGoalMin,
        };
    });
    const calibrated = budgets.filter((b) => b.recommendedGoalMin !== null);
    const uncalibrated = budgets.filter((b) => b.recommendedGoalMin === null);
    const hasSleep = budgets.some((b) => b.isSleep);
    return JSON.stringify({
        analysedPeriod: `${todayInParis(twelveWeeksAgo)} → ${today}`,
        method: "p90 des minutes sur les jours actifs (jours où l'activité a été loggée). Sommeil découplé (8h par défaut), plus de budget résiduel 24h.",
        calibratedActivities: calibrated.length,
        uncalibratedActivities: uncalibrated.length,
        activities: budgets,
        workflow: [
            hasSleep
                ? ""
                : "0. Optionnel : si tu veux suivre le sommeil → create_activity(name='Sommeil', type='time', domainId=<domaine Santé>) puis cible 480 min (8h) par défaut.",
            "1. set_activity_targets(targets:[{activityId, goalMin=recommendedGoalMin}, …]) pour toutes les activités avec recommendedGoalMin non-null, EN UN SEUL appel (les cibles targetSource='user' sont préservées automatiquement).",
            uncalibrated.length > 0
                ? `2. Pour les ${uncalibrated.length} activité(s) sans assez de sessions (recommendedGoalMin=null) ET targetSource='default' : pose une intention de DÉPART réaliste et conservatrice depuis le nom/domaine (ex: Méditation 10-15, Lecture 20-30, Deep Work 60-90, Sport 30-45) via le MÊME appel set_activity_targets — ne les laisse PAS à 30 min arbitraire.`
                : "",
            "3. push_assistant_message : 1 résumé concis des cibles posées (ex: 'Sport 30→42 · Vaisselle 5→15 · Sommeil 8h'). Mentionne brièvement que ce sont des intentions ajustables à la main.",
        ].filter(Boolean),
    }, null, 2);
}
async function executeUpdateScheduleBlock(uid, date, blockTitle, status) {
    var _a;
    if (!/^\d{4}-\d{2}-\d{2}$/.test(date))
        return `Date invalide : ${date}`;
    const ref = db_1.db.doc(`users/${uid}/daily_schedules/${date}`);
    const snap = await ref.get();
    if (!snap.exists)
        return `Aucun programme pour le ${date}.`;
    const data = snap.data();
    const blocks = (_a = data.blocks) !== null && _a !== void 0 ? _a : [];
    const idx = blocks.findIndex((b) => b.title.toLowerCase().includes(blockTitle.toLowerCase()));
    if (idx === -1)
        return `Bloc "${blockTitle}" introuvable dans le programme du ${date}.`;
    blocks[idx] = Object.assign(Object.assign(Object.assign({}, blocks[idx]), { status }), (status === "done" ? { doneAt: new Date().toISOString() } : {}));
    await ref.update({ blocks });
    return `✅ Bloc "${blocks[idx].title}" → ${status}`;
}
// ── generate_weekly_report ────────────────────────────────────────────────────
/** (Ré)génère le rapport hebdo d'une semaine — même garde de coût que
 * l'endpoint weeklyReportNow (3 générations/jour, le doc existant se relit). */
async function executeGenerateWeeklyReport(uid, apiKey, weekStart) {
    var _a;
    if (weekStart !== undefined && !/^\d{4}-\d{2}-\d{2}$/.test(weekStart)) {
        return "❌ weekStart invalide — format attendu YYYY-MM-DD.";
    }
    if (!apiKey)
        return "❌ ANTHROPIC_API_KEY manquante côté serveur.";
    const start = (0, weekly_report_1.mondayOf)(weekStart !== null && weekStart !== void 0 ? weekStart : todayInParis());
    const today = todayInParis();
    const limitRef = db_1.db.doc(`users/${uid}/rate_limits/weekly_report`);
    const limitSnap = await limitRef.get();
    const limitData = limitSnap.data();
    const count = (limitData === null || limitData === void 0 ? void 0 : limitData.ymd) === today ? ((_a = limitData.count) !== null && _a !== void 0 ? _a : 0) : 0;
    if (count >= 3)
        return "❌ Limite atteinte : 3 rapports générés aujourd'hui — réessaie demain.";
    await limitRef.set({ ymd: today, count: count + 1 }, { merge: true });
    const id = await (0, weekly_report_1.generateWeeklyReport)(uid, apiKey, start);
    return `✅ Rapport hebdo régénéré pour la semaine du ${id} (lundi → dimanche). ` +
        "Il remplace le doc existant et est visible immédiatement dans l'app (écran Rapport / carte du dimanche).";
}
// ── Sessions de temps : audit et correction (list_sessions / delete_sessions / update_session) ──
// Suppression DOUCE (deleted:true + deletedAt) : l'app retire la session de son état local au
// prochain pull puis hard-delete le doc (réconciliation de FirestoreSync). Une correction
// d'heures = tombstone de l'ancienne + nouvelle session (nouvel id), pour que la copie locale
// de l'app ne réécrive pas l'ancienne version (merge « local gagne » sur les sessions).
async function userNowWallMs(uid) {
    var _a;
    const snap = await db_1.db.doc(`users/${uid}/data/meta`).get();
    const v = (_a = snap.data()) === null || _a === void 0 ? void 0 : _a.tzOffsetMin;
    const off = typeof v === "number" && isFinite(v) ? v : 0;
    return Date.now() + off * 60000;
}
async function executeListSessions(uid, args) {
    var _a, _b;
    const ymd = /^\d{4}-\d{2}-\d{2}$/;
    if (!args.from || !ymd.test(args.from))
        return "❌ from requis au format YYYY-MM-DD.";
    const to = (_a = args.to) !== null && _a !== void 0 ? _a : args.from;
    if (!ymd.test(to) || to < args.from)
        return "❌ to invalide (YYYY-MM-DD, ≥ from).";
    const spanDays = ((0, sessions_audit_1.wallMs)(`${to}T00:00:00`) - (0, sessions_audit_1.wallMs)(`${args.from}T00:00:00`)) / 86400000 + 1;
    if (spanDays > 62)
        return "❌ Période limitée à 62 jours.";
    // Les sessions démarrées jusqu'à 3 j avant la période peuvent encore la toucher.
    const since = (0, sessions_audit_1.toWallIso)((0, sessions_audit_1.wallMs)(`${args.from}T00:00:00`) - 3 * 86400000).slice(0, 10);
    const [sessionsSnap, activitiesSnap, nowMs] = await Promise.all([
        db_1.db.collection(`users/${uid}/sessions`).where("startAt", ">=", since).get(),
        db_1.db.collection(`users/${uid}/activities`).get(),
        userNowWallMs(uid),
    ]);
    const names = {};
    activitiesSnap.docs.forEach((d) => { var _a; names[d.id] = (_a = d.data().name) !== null && _a !== void 0 ? _a : d.id; });
    let sessions = (0, sessions_audit_1.liveSessionDocs)(sessionsSnap).map((d) => (Object.assign(Object.assign({}, d.data()), { id: d.id })));
    if (args.activityId)
        sessions = sessions.filter((s) => s.activityId === args.activityId);
    const res = (0, sessions_audit_1.auditSessions)(sessions, names, args.from, to, nowMs);
    return (0, sessions_audit_1.formatAudit)(res, args.from, to, (_b = args.anomaliesOnly) !== null && _b !== void 0 ? _b : false);
}
async function executeDeleteSessions(uid, args) {
    var _a;
    const ids = Array.from(new Set(((_a = args.sessionIds) !== null && _a !== void 0 ? _a : []).filter((x) => typeof x === "string" && x)));
    if (ids.length === 0)
        return "❌ sessionIds requis (liste non vide).";
    if (ids.length > 200)
        return "❌ 200 sessions maximum par appel.";
    const col = db_1.db.collection(`users/${uid}/sessions`);
    const snaps = await Promise.all(ids.map((id) => col.doc(id).get()));
    const missing = [];
    const batch = db_1.db.batch();
    const deletedAt = new Date().toISOString();
    let n = 0;
    snaps.forEach((snap, i) => {
        var _a;
        if (!snap.exists || ((_a = snap.data()) === null || _a === void 0 ? void 0 : _a.deleted) === true) {
            missing.push(ids[i]);
            return;
        }
        batch.set(snap.ref, { deleted: true, deletedAt }, { merge: true });
        n++;
    });
    if (n > 0)
        await batch.commit();
    const lines = [`✅ ${n} session(s) supprimée(s) (suppression douce, retirées des stats).`];
    if (missing.length)
        lines.push(`Introuvables ou déjà supprimées : ${missing.join(", ")}`);
    lines.push("L'app les retire de son état local à sa prochaine synchro.");
    return lines.join("\n");
}
async function executeUpdateSession(uid, args) {
    var _a, _b, _c, _d;
    if (!args.sessionId)
        return "❌ sessionId requis.";
    if (!args.startAt && !args.endAt && !args.activityId && args.taskId === undefined && args.actionId === undefined) {
        return "❌ Rien à modifier (startAt, endAt, activityId, taskId ou actionId).";
    }
    const col = db_1.db.collection(`users/${uid}/sessions`);
    const snap = await col.doc(args.sessionId).get();
    if (!snap.exists || ((_a = snap.data()) === null || _a === void 0 ? void 0 : _a.deleted) === true)
        return `❌ Session ${args.sessionId} introuvable.`;
    const old = snap.data();
    const norm = (v, fallback) => {
        if (v === undefined)
            return fallback !== null && fallback !== void 0 ? fallback : null;
        const ms = (0, sessions_audit_1.wallMs)(v.length === 16 ? `${v}:00` : v);
        if (Number.isNaN(ms))
            throw new Error(`Date invalide : ${v}`);
        return (0, sessions_audit_1.toWallIso)(ms);
    };
    let startAt;
    let endAt;
    try {
        startAt = norm(args.startAt, old.startAt);
        endAt = norm(args.endAt, old.endAt);
    }
    catch (e) {
        return `❌ ${e.message} (format attendu YYYY-MM-DDTHH:mm, heure locale de l'utilisateur).`;
    }
    if (!startAt)
        return "❌ startAt manquant.";
    if (endAt && (0, sessions_audit_1.wallMs)(endAt) <= (0, sessions_audit_1.wallMs)(startAt))
        return "❌ La fin doit être après le début.";
    let activityId = old.activityId;
    if (args.activityId) {
        const act = await db_1.db.doc(`users/${uid}/activities/${args.activityId}`).get();
        if (!act.exists || ((_b = act.data()) === null || _b === void 0 ? void 0 : _b.deleted))
            return `❌ Activité ${args.activityId} introuvable.`;
        activityId = args.activityId;
    }
    // Rattachement après coup à une tâche / action ("" = détacher) : le temps
    // de la session compte alors pour le bloc qui vise cette tâche.
    const taskId = args.taskId === undefined ? (_c = old.taskId) !== null && _c !== void 0 ? _c : null : (args.taskId || null);
    const actionId = args.actionId === undefined
        ? (args.taskId !== undefined && !args.taskId ? null : (_d = old.actionId) !== null && _d !== void 0 ? _d : null)
        : (args.actionId || null);
    const newId = (0, uuid_1.v4)();
    const batch = db_1.db.batch();
    batch.set(col.doc(newId), {
        id: newId, activityId, startAt, endAt,
        taskId, actionId,
    });
    batch.set(snap.ref, { deleted: true, deletedAt: new Date().toISOString(), replacedBy: newId }, { merge: true });
    await batch.commit();
    const dur = endAt ? Math.round(((0, sessions_audit_1.wallMs)(endAt) - (0, sessions_audit_1.wallMs)(startAt)) / 60000) : null;
    return `✅ Session corrigée : ${startAt.slice(0, 16)} → ${endAt ? endAt.slice(0, 16) : "en cours"}` +
        (dur !== null ? ` (${dur} min)` : "") + `. Nouvel id ${newId} (l'ancienne ${args.sessionId} est supprimée).`;
}
//# sourceMappingURL=execute.js.map