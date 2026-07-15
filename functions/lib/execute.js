"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.sendFcmPush = sendFcmPush;
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
exports.executeRestoreItem = executeRestoreItem;
exports.executeCreateDomain = executeCreateDomain;
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
exports.executeLinkActionToActivity = executeLinkActionToActivity;
exports.executeAddActivityAction = executeAddActivityAction;
exports.executeLogRoutineHit = executeLogRoutineHit;
exports.executeMarkBlockDone = executeMarkBlockDone;
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
const db_1 = require("./db");
const uuid_1 = require("uuid");
const admin = require("firebase-admin");
const crypto_1 = require("crypto");
const weekly_report_1 = require("./weekly_report");
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
    const actions = rawActions.map((a) => typeof a === "string"
        ? { id: (0, uuid_1.v4)(), title: a, done: false, doneAt: null, createdAt: new Date().toISOString() }
        : a);
    return Object.assign(Object.assign(Object.assign(Object.assign(Object.assign(Object.assign({ id: typeof t.id === "string" ? t.id : (0, uuid_1.v4)(), title, startDate: t.startDate }, (typeof t.endDate === "string" ? { endDate: t.endDate } : {})), (typeof t.phaseId === "string" ? { phaseId: t.phaseId } : {})), (typeof t.groupLabel === "string" ? { groupLabel: t.groupLabel } : {})), (typeof t.color === "string" ? { color: t.color } : {})), (typeof t.barLabel === "string" ? { barLabel: t.barLabel } : {})), { isMilestone: t.isMilestone === true, status: rawStatus, actions });
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
    return Object.assign(Object.assign(Object.assign(Object.assign({ title, startDate: p.startDate }, (description !== undefined ? { description } : {})), (p.endDate !== undefined ? { endDate: p.endDate } : {})), (p.domainId !== undefined ? { domainId: p.domainId } : {})), { phases: phases.map((ph) => pickPhase(ph)), tasks: tasks.map((t) => pickTask(t)) });
}
function pickStrategicObjective(so) {
    const title = clampStr(so.title, 200, "strategicObjective.title");
    const description = so.description !== undefined
        ? clampStr(so.description, 5000, "strategicObjective.description") : undefined;
    if (so.startDate !== undefined)
        assertDate(so.startDate, "strategicObjective.startDate");
    if (so.endDate !== undefined)
        assertDate(so.endDate, "strategicObjective.endDate");
    return Object.assign(Object.assign(Object.assign(Object.assign(Object.assign(Object.assign({ title }, (description !== undefined ? { description } : {})), (so.domainId !== undefined ? { domainId: so.domainId } : {})), (so.kpiTarget !== undefined ? { kpiTarget: so.kpiTarget } : {})), (so.horizonLabel !== undefined ? { horizonLabel: so.horizonLabel } : {})), (so.startDate !== undefined ? { startDate: so.startDate } : {})), (so.endDate !== undefined ? { endDate: so.endDate } : {}));
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
async function executeGetUserContext(uid) {
    var _a, _b;
    // Fenêtre glissante : 7 derniers jours
    const now = new Date();
    const sevenDaysAgo = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000);
    const todayStr = todayInParis(now);
    const [domainsSnap, activitiesSnap, habitHitsSnap, sessionsSnap, projectsSnap, scheduleSnap, inboxSnap] = await Promise.all([
        db_1.db.collection(`users/${uid}/domains`).get(),
        db_1.db.collection(`users/${uid}/activities`).get(),
        // Incréments de routines/habitudes sur 7 jours
        db_1.db.collection(`users/${uid}/habitHits`)
            .where("ts", ">=", sevenDaysAgo)
            .get(),
        // Sessions de temps loggué sur 7 jours
        db_1.db.collection(`users/${uid}/sessions`)
            .where("startAt", ">=", sevenDaysAgo.toISOString())
            .get(),
        // Projets actifs
        db_1.db.collection(`users/${uid}/projects`).where("status", "==", "active").get(),
        // Programme du jour
        db_1.db.doc(`users/${uid}/daily_schedules/${todayStr}`).get(),
        // Inbox (idées en attente)
        db_1.db.collection(`users/${uid}/captures`).where("status", "==", "pending").get(),
    ]);
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
        // Actions PROPRES de l'activité (TaskAction sans tâche/projet) — non faites.
        const ownActions = Array.isArray(v.ownActions)
            ? v.ownActions
                .filter((a) => !(a === null || a === void 0 ? void 0 : a.done))
                .map((a) => ({ id: a.id, title: a.title }))
            : [];
        return Object.assign({ id: v.id, name: v.name, type: v.type, domainId: v.domainId, goalMin: v.goalMin, habitFreq: v.habitFreq, habitTarget: v.habitTarget }, (ownActions.length > 0 ? { ownActions } : {}));
    });
    // ── Réalisé des 7 derniers jours ──────────────────────────────────────────
    // Taux de complétion des habitudes/routines (habitHits groupés par habitId)
    const hitsByHabit = new Map();
    for (const doc of habitHitsSnap.docs) {
        const v = doc.data();
        hitsByHabit.set(v.habitId, (hitsByHabit.get(v.habitId) || 0) + 1);
    }
    const habitCompletion = Array.from(hitsByHabit.entries()).map(([id, count]) => ({
        activityId: id,
        name: activityMap.get(id) || id,
        hitsLast7Days: count,
    }));
    // Temps loggué par activité (sessions)
    const minByActivity = new Map();
    for (const doc of sessionsSnap.docs) {
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
        name: activityMap.get(id) || id,
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
    const activeProjects = projectsSnap.docs.map((d) => {
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
            })),
        }
        : null;
    // ── Inbox (idées en attente) ───────────────────────────────────────────────
    const inboxItems = inboxSnap.docs.map((d) => {
        var _a, _b, _c;
        const v = d.data();
        return { id: (_a = v.id) !== null && _a !== void 0 ? _a : d.id, text: (_c = (_b = v.text) !== null && _b !== void 0 ? _b : v.content) !== null && _c !== void 0 ? _c : "" };
    }).filter((v) => v.text);
    const coachingRules = {
        _instructions: [
            "AVANT de commencer tout travail long (programme, bilan, alignement Gantt) : annonce à l'utilisateur que ça prend ~1-2 min et que tu envoies une notification quand c'est prêt.",
            "QUAND l'utilisateur demande un programme (musculation, nutrition, formation, journée…) : demande-lui d'abord s'il veut que tu vérifies son agenda pour intégrer des créneaux concrets. Si oui : list_events → propose des créneaux → create_event après accord.",
            "APRÈS chaque save_document : envoie une push_notification pour informer l'utilisateur.",
            "QUAND tu modifies un projet Gantt (push_gantt, update_project, update_task_status) : appelle get_documents(projectId) et mets à jour le programme HTML associé via save_document en passant le documentId existant (évite les doublons).",
            "POUR créer un programme : appelle toujours get_document_template d'abord, génère le HTML, montre-le à l'utilisateur et attends sa validation avant de créer quoi que ce soit dans Productivitwo.",
            "CONVENTION CALENDRIER : quand tu crées un événement Google Calendar dans le cadre d'une session Productivitwo, ajoute ' - Productivitwo' à la fin du titre (ex: 'Séance musculation - Productivitwo'). Cela te permet d'identifier les events que tu peux modifier librement lors d'une réorganisation. Les events sans ' - Productivitwo' ont été créés par l'utilisateur ou hors contexte Productivitwo : ne les modifie pas sans demander confirmation explicite.",
            "FICHIERS DE TÂCHE : quand tu crées ou sauvegardes un document avec save_document, associe-le toujours à la tâche Gantt concernée via taskId (obtenu depuis get_project → tasks[].id). Choisis la category appropriée : 'programme' pour un plan structuré, 'brief' pour un cahier des charges, 'recherche' pour une analyse/veille, 'livrable' pour un output final, 'notes' pour des notes de travail. Avant de créer un nouveau document, vérifie via get_documents(taskId) si un document de même category existe déjà pour éviter les doublons — si oui, mets-le à jour via documentId.",
            "PRIORITÉ ABSOLUE : réponds d'abord à la demande de l'utilisateur. Ne fais jamais d'actions non demandées (schedule_day, push_assistant_message, modification Gantt…) avant d'avoir répondu. Les actions proactives viennent APRÈS la réponse, jamais à la place.",
            "ACTIONS D'ACTIVITÉ : une activité-temps peut avoir ses propres actions (champ ownActions de chaque activité dans ce contexte) — des sous-actions sans tâche/projet. Tu peux en créer via add_activity_action(activityId, title) puis les PROGRAMMER dans schedule_day en passant activityId + actionId (le chrono du bloc sera ciblé sur l'action). Quand tu programmes une action concrète qui correspond à une activité-temps existante, préfère la rattacher (action propre) plutôt qu'un bloc vague.",
            "LIER UNE ACTION À UNE ACTIVITÉ : quand tu vois une sous-action de tâche Gantt qui n'est PAS déjà liée à une activité (pas de linkedActivityId) et qu'une activité-temps du même domaine existe, PROPOSE à l'utilisateur de l'y associer via link_action_to_activity(projectId, taskId, actionId, activityId) — ainsi le temps passé dessus sera chronométré sur la bonne activité. Propose, n'impose pas ; ne touche pas à une action déjà liée.",
            "PROPOSITIONS DE FIN DE SESSION : après avoir terminé une action significative (programme créé, Gantt mis à jour, bilan fait, messages ORION programmés…), propose toujours 2 à 3 suites logiques sous forme de liste numérotée courte. " +
                "Adapte les options à ce qui vient d'être fait. Exemples pertinents selon le contexte : " +
                "• 'Programme ton plan du jour' (si pas encore fait aujourd'hui) " +
                "• 'Mettre à jour tes priorités Gantt' (si des tâches sont en retard) " +
                "• 'Faire le bilan de la semaine' (si c'est vendredi ou fin de sprint) " +
                "• 'Programmer des messages ORION pour la semaine' (si pas encore fait) " +
                "• 'Créer les routines liées à ce programme' (si un programme vient d'être créé) " +
                "• 'Aligner ton agenda Google Calendar' (si des créneaux sont à bloquer) " +
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
    return JSON.stringify(Object.assign(Object.assign({}, coachingRules), { today: todayStr, domains,
        activities,
        activeProjects,
        todaySchedule, inboxItems: inboxItems.length > 0 ? inboxItems : null, recentActivity }), null, 2);
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
    var _a, _b, _c;
    const ref = db_1.db.collection(`users/${uid}/projects`).doc(projectId);
    const snap = await ref.get();
    if (!snap.exists)
        return `Projet introuvable : ${projectId}`;
    const title = (_a = updates.title) !== null && _a !== void 0 ? _a : ((_c = (_b = snap.data()) === null || _b === void 0 ? void 0 : _b.title) !== null && _c !== void 0 ? _c : projectId);
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
    await ref.update(patch);
    return `✅ Projet "${title}" mis à jour.`;
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
    return restore
        ? `✅ Projet "${title}" réactivé — il apparaît à nouveau dans le focus.`
        : `✅ Projet "${title}" mis en veille — visible dans la section Archives du web app.`;
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
        await db_1.db.collection(`users/${uid}/strategic_objectives`).doc(objId).delete();
        return `✅ Projet "${title}" et son objectif stratégique supprimés.`;
    }
    return `✅ Projet "${title}" supprimé.`;
}
async function executeListProjects(uid) {
    const snap = await db_1.db.collection(`users/${uid}/projects`).get();
    if (snap.empty)
        return "Aucun projet trouvé dans Productivitwo.";
    const lines = snap.docs.map((doc) => {
        const d = doc.data();
        const taskCount = (d.tasks || []).length;
        const start = d.startDate || "?";
        const end = d.endDate || "?";
        const domain = d.domainId ? ` · domaine:${d.domainId}` : '';
        return `• [${d.id}] ${d.title} (${start} → ${end}, ${taskCount} tâche(s)${domain})`;
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
async function executePushGantt(uid, input, opts) {
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
        : {})), (project.id ? {} : { status: "draft" })), (strategicObjectiveId ? { strategicObjectiveId } : {})), { updatedAt: db_1.FieldValue.serverTimestamp(), createdAt: db_1.FieldValue.serverTimestamp() }), { merge: true });
    if (strategicObjectiveId) {
        await db_1.db.collection(`users/${uid}/strategic_objectives`).doc(strategicObjectiveId)
            .update({ projectIds: db_1.FieldValue.arrayUnion(projectId) });
    }
    const isUpdate = !!project.id;
    return (`✅ Projet "${project.title}" ${isUpdate ? "mis à jour" : "créé"} dans Productivitwo !\n` +
        `• ${(project.tasks || []).length} tâche(s) · ${(project.phases || []).length} phase(s)\n` +
        `• Voir sur : https://app.productivitwo.com\n` +
        `• projectId : ${projectId}`);
}
async function executeAddTask(uid, projectId, task) {
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
    // arrayUnion est atomique et ne nécessite pas de lire/réécrire le tableau entier
    await ref.update({
        tasks: db_1.FieldValue.arrayUnion(newTask),
        updatedAt: db_1.FieldValue.serverTimestamp(),
    });
    return `✅ Tâche "${newTask.title}" ajoutée au projet (id: ${newTask.id}).`;
}
async function executeUpdateTask(uid, projectId, taskId, updates) {
    var _a, _b, _c, _d;
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
    const idx = tasks.findIndex((t) => t.id === taskId);
    if (idx === -1)
        return `Tâche introuvable : ${taskId}`;
    try {
        const patch = {};
        if (updates.title !== undefined)
            patch.title = clampStr(updates.title, 200, "title");
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
        if (updates.phaseId !== undefined)
            patch.phaseId = updates.phaseId;
        if (updates.groupLabel !== undefined)
            patch.groupLabel = updates.groupLabel;
        if (updates.isMilestone !== undefined)
            patch.isMilestone = updates.isMilestone;
        if (updates.color !== undefined)
            patch.color = updates.color;
        if (updates.barLabel !== undefined)
            patch.barLabel = updates.barLabel;
        if (updates.actions !== undefined) {
            // Remplace les sous-actions, mais préserve l'état done par match de titre
            // pour ne pas perdre la progression de l'utilisateur en cas de simple
            // renommage ou réordonnancement.
            const rawActions = Array.isArray(updates.actions) ? updates.actions : [];
            const oldActions = (_a = tasks[idx].actions) !== null && _a !== void 0 ? _a : [];
            const oldByTitle = {};
            for (const a of oldActions) {
                const t = (_b = a.title) !== null && _b !== void 0 ? _b : "";
                if (t) {
                    oldByTitle[t] = {
                        done: (_c = a.done) !== null && _c !== void 0 ? _c : false,
                        doneAt: (_d = a.doneAt) !== null && _d !== void 0 ? _d : null,
                        id: a.id,
                    };
                }
            }
            patch.actions = rawActions.map((a) => {
                var _a, _b, _c;
                const title = typeof a === "string"
                    ? a
                    : (typeof a === "object" && a !== null && "title" in a ? String(a.title) : "");
                const previous = oldByTitle[title];
                return {
                    id: (_a = previous === null || previous === void 0 ? void 0 : previous.id) !== null && _a !== void 0 ? _a : (0, uuid_1.v4)(),
                    title,
                    done: (_b = previous === null || previous === void 0 ? void 0 : previous.done) !== null && _b !== void 0 ? _b : false,
                    doneAt: (_c = previous === null || previous === void 0 ? void 0 : previous.doneAt) !== null && _c !== void 0 ? _c : null,
                    createdAt: new Date().toISOString(),
                };
            });
        }
        tasks[idx] = Object.assign(Object.assign({}, tasks[idx]), patch);
    }
    catch (e) {
        return `❌ Mise à jour invalide : ${e instanceof Error ? e.message : String(e)}`;
    }
    await ref.update({ tasks, updatedAt: db_1.FieldValue.serverTimestamp() });
    return `✅ Tâche "${tasks[idx].title}" mise à jour.`;
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
    actions[actionIdx] = Object.assign(Object.assign({}, actions[actionIdx]), { done, doneAt: done ? new Date().toISOString() : null });
    tasks[taskIdx] = Object.assign(Object.assign({}, tasks[taskIdx]), { actions });
    await ref.update({ tasks, updatedAt: db_1.FieldValue.serverTimestamp() });
    return `✅ Sous-action "${actionTitle}" ${done ? "marquée faite" : "démarquée"}.`;
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
// Crée une action PROPRE sur une activité (Activity.ownActions) : une TaskAction
// qui appartient directement à l'activité, sans tâche/projet. Réutilisable ensuite
// dans schedule_day (activityId + actionId) pour la programmer.
async function executeAddActivityAction(uid, activityId, title) {
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
    const action = {
        id: (0, uuid_1.v4)(),
        title: title.trim(),
        done: false,
        doneAt: null,
        createdAt: new Date().toISOString(),
        linkedActivityId: activityId,
    };
    own.push(action);
    await ref.update({ ownActions: own });
    return `✅ Action propre "${action.title}" créée sur "${(_a = data.name) !== null && _a !== void 0 ? _a : activityId}" (id: ${action.id}). Tu peux la programmer via schedule_day (activityId: ${activityId}, actionId: ${action.id}).`;
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
    const [domainsSnap, activitiesSnap, habitHitsSnap, sessionsSnap, projectsSnap] = await Promise.all([
        db_1.db.collection(`users/${uid}/domains`).get(),
        db_1.db.collection(`users/${uid}/activities`).get(),
        db_1.db.collection(`users/${uid}/habitHits`).where("ts", ">=", sevenDaysAgo).get(),
        db_1.db.collection(`users/${uid}/sessions`).where("startAt", ">=", sevenDaysAgo.toISOString()).get(),
        db_1.db.collection(`users/${uid}/projects`).where("status", "==", "active").get(),
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
    sessionsSnap.docs.forEach((d) => {
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
    const projects = projectsSnap.docs.map((d) => {
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
    return JSON.stringify({ today, domains, activities, habitStats, timeStats, projects }, null, 2);
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
    const valid = ["new_project", "attach_idea_as_task", "create_subproject", "archive_project", "add_phase", "attach_action_to_task", "restructure_project"];
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
    var _a, _b, _c;
    const today = todayInParis();
    const date = (_a = args.date) !== null && _a !== void 0 ? _a : today;
    if (!/^\d{4}-\d{2}-\d{2}$/.test(date))
        return `Date invalide : ${date}`;
    const startHour = (_b = args.startHour) !== null && _b !== void 0 ? _b : 7;
    const endHour = (_c = args.endHour) !== null && _c !== void 0 ? _c : 20;
    const syncToCalendar = args.syncToCalendar !== false;
    // Planifier AUJOURD'HUI ne doit jamais créer de blocs déjà passés : le
    // départ effectif est calé sur le prochain quart d'heure (s'il est 15h12 et
    // que startHour=7, on planifie à partir de 15h15 — les blocs passés du
    // programme existant restent intacts).
    const isToday = date === today;
    const floorHm = isToday ? nextQuarterHour() : null;
    const startLabel = floorHm && floorHm > `${String(startHour).padStart(2, "0")}:00`
        ? floorHm
        : `${String(startHour).padStart(2, "0")}h`;
    const [userContext, existingSchedule] = await Promise.all([
        executeGetUserContext(uid),
        executeGetDaySchedule(uid, date),
    ]);
    const projectsSnap = await db_1.db.collection(`users/${uid}/projects`)
        .where("status", "==", "active").get();
    const projectDetails = [];
    for (const doc of projectsSnap.docs) {
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
            `4. create_event() pour chaque bloc (sauf conflits avec calendrier principal)`,
            `   description format : "source: productivitwo | category: [project|routine|break|personal]"`,
            `   colorId : routine=2, project=7, break=5, personal=4`,
        ]
        : [];
    return [
        `══════════════════════════════════════════`,
        `📋 CONTEXTE PLANIFICATION — ${date} (${startLabel}-${endHour}h)`,
        `══════════════════════════════════════════`,
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
        ``,
        `══════════════════════════════════════════`,
        `WORKFLOW :`,
        `1. list_events() Google Calendar principal → identifier les créneaux occupés`,
        `2. Générer les blocs (${startLabel}-${endHour}h) : tâches Gantt + routines + activités-temps + pauses`,
        `   → Tâche la plus proche de la deadline en premier`,
        `   → Ne pas recréer les blocs marqués [supprimé par l'utilisateur]`,
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
        projectDetails.push(await executeGetProject(uid, doc.id));
    }
    const schedules = [];
    for (const d of weekDates) {
        const s = await executeGetDaySchedule(uid, d);
        schedules.push(`${d} : ${s}`);
    }
    const syncNote = args.syncToCalendar !== false
        ? `\n📅 SYNC GOOGLE CALENDAR : après chaque schedule_day(), créer les events dans le calendrier "Productivitwo" (colorId: routine=2, project=7, break=5, personal=4).`
        : "";
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
        `1. Répartir les tâches Gantt sur les 5 jours (deadline proche = premier)`,
        `2. Max ~6h de travail projet par jour · inclure routines matin/soir`,
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
    const snap = await db_1.db.doc(`users/${uid}/daily_schedules/${targetDate}`).get();
    if (!snap.exists) {
        return `Aucun programme Productivitwo pour le ${targetDate}. Appelle plan_day("${targetDate}") pour en créer un.`;
    }
    const data = snap.data();
    const blocks = (_a = data.blocks) !== null && _a !== void 0 ? _a : [];
    const activeBlocks = blocks.filter((b) => b.status !== "deleted");
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
    const blocks = (_a = data.blocks) !== null && _a !== void 0 ? _a : [];
    const statusIcon = (s) => s === "done" ? "✅" : s === "skipped" ? "⏭" : s === "deleted" ? "❌" : "⬜";
    const lines = blocks.map((b) => {
        const icon = statusIcon(b.status);
        const deletedNote = b.status === "deleted" ? " [supprimé par l'utilisateur — ne pas recréer]" : "";
        return `${icon} ${b.startTime} (${b.durationMin}min) — ${b.title} [${b.category}]${deletedNote}`;
    });
    return `Programme du ${date} (généré par ${data.generatedBy}) :\n${lines.join("\n")}`;
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
async function executeScheduleDay(uid, date, blocks) {
    var _a, _b, _c, _d, _e, _f, _g, _h, _j;
    if (!/^\d{4}-\d{2}-\d{2}$/.test(date))
        return `Date invalide : ${date}. Format attendu : YYYY-MM-DD`;
    if (!(blocks === null || blocks === void 0 ? void 0 : blocks.length))
        return `Aucun bloc fourni — le programme n'a pas été enregistré.`;
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
    const preserved = ((_a = prevData.blocks) !== null && _a !== void 0 ? _a : [])
        .filter((b) => b.gcalEventId != null ||
        // Défi programmé 🔥 = engagement pris (alarme locale armée côté app) —
        // un remplacement de programme ne l'efface jamais en silence.
        (b.challenge === true && b.status !== "deleted") ||
        ((b.kind === "prep" || b.kind === "bilan" || b.kind === "session") &&
            b.status !== "deleted"));
    await ref.set({
        date,
        generatedBy: "claude",
        generatedAt: db_1.FieldValue.serverTimestamp(),
        blocks: [...preserved, ...normalizedBlocks],
        dayReason: (_b = prevData.dayReason) !== null && _b !== void 0 ? _b : null,
        plannedAt: (_c = prevData.plannedAt) !== null && _c !== void 0 ? _c : null,
        plannedSameDay: (_d = prevData.plannedSameDay) !== null && _d !== void 0 ? _d : false,
        dayMode: (_e = prevData.dayMode) !== null && _e !== void 0 ? _e : "normal", // mode soirée réversible (23c)
        dayModeActivatedAt: (_f = prevData.dayModeActivatedAt) !== null && _f !== void 0 ? _f : null,
        unavailableUntil: (_g = prevData.unavailableUntil) !== null && _g !== void 0 ? _g : null, // « je suis le flow »
        unavailableReason: (_h = prevData.unavailableReason) !== null && _h !== void 0 ? _h : null,
        reviewedAt: (_j = prevData.reviewedAt) !== null && _j !== void 0 ? _j : null, // « point fait » — jamais effacé
    });
    const lines = normalizedBlocks.map((b) => `• ${b.startTime} (${b.durationMin}min) — ${b.title}`);
    return `✅ Programme du ${date} enregistré — ${normalizedBlocks.length} bloc(s)\n${lines.join("\n")}`;
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
    var _a, _b;
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
        const gcalSnap = await db_1.db.doc(`gcal_tokens/${uid}`).get();
        if (gcalSnap.exists && ((_b = gcalSnap.data()) === null || _b === void 0 ? void 0 : _b.refreshToken)) {
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
    for (const doc of sessionsSnap.docs) {
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
//# sourceMappingURL=execute.js.map