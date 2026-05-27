"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.executePushAssistantMessage = executePushAssistantMessage;
exports.validateToken = validateToken;
exports.executeGetUserContext = executeGetUserContext;
exports.executeGetOrionContext = executeGetOrionContext;
exports.executeUpdateActivityGoal = executeUpdateActivityGoal;
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
exports.executeLinkGoalToTask = executeLinkGoalToTask;
exports.executeDeleteRoutine = executeDeleteRoutine;
exports.executeDeleteGoal = executeDeleteGoal;
exports.executeArchiveProject = executeArchiveProject;
exports.executeDeleteProject = executeDeleteProject;
exports.executeListProjects = executeListProjects;
exports.executeGetProject = executeGetProject;
exports.executePushGantt = executePushGantt;
exports.executeGetAssistantMessages = executeGetAssistantMessages;
exports.executeDeleteAssistantMessage = executeDeleteAssistantMessage;
exports.executeGetOrionQueue = executeGetOrionQueue;
exports.executeDeleteOrionQueueItem = executeDeleteOrionQueueItem;
exports.executeGetInbox = executeGetInbox;
exports.executeProcessInboxItem = executeProcessInboxItem;
exports.executeGetDaySchedule = executeGetDaySchedule;
exports.executeScheduleDay = executeScheduleDay;
exports.executeUpdateScheduleBlock = executeUpdateScheduleBlock;
exports.executeComputeTimeBudget = executeComputeTimeBudget;
exports.executePlanDay = executePlanDay;
exports.executePlanWeek = executePlanWeek;
exports.executeSyncCalendar = executeSyncCalendar;
exports.normalizePhases = normalizePhases;
exports.normalizeTasks = normalizeTasks;
const db_1 = require("./db");
const uuid_1 = require("uuid");
const admin = require("firebase-admin");
function normalizePhases(phases) {
    if (!phases)
        return [];
    return phases.map((p) => (Object.assign(Object.assign({}, p), { id: p.id || (0, uuid_1.v4)() })));
}
function normalizeTasks(tasks) {
    if (!tasks)
        return [];
    return tasks.map((t) => {
        var _a, _b, _c;
        return (Object.assign(Object.assign({}, t), { id: t.id || (0, uuid_1.v4)(), isMilestone: (_a = t.isMilestone) !== null && _a !== void 0 ? _a : false, status: (_b = t.status) !== null && _b !== void 0 ? _b : "pending", actions: ((_c = t.actions) !== null && _c !== void 0 ? _c : []).map((a) => ({
                id: (0, uuid_1.v4)(),
                title: a,
                done: false,
                doneAt: null,
                createdAt: new Date().toISOString(),
            })) }));
    });
}
async function executePushAssistantMessage(uid, args) {
    var _a, _b, _c, _d, _e;
    if (!/^\d{4}-\d{2}-\d{2}$/.test(args.targetDate)) {
        return `Date invalide : ${args.targetDate}. Format attendu : YYYY-MM-DD`;
    }
    const validTypes = [
        "always", "overdue_count", "day_plan_empty", "project_inactive_days",
        "activity_behind_target", "goal_undone_actions", "habit_streak_broken",
        "inbox_overflow", "project_deadline_near", "no_now_focus",
        "routine_completion_low", "day_plan_overloaded", "no_activity_logged_today",
        "project_milestone_today", "week_start", "week_end",
        "activity_streak", "goal_near_deadline", "first_open_of_day", "custom_date",
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
    const q = await db_1.db
        .collection(`users/${uid}/api_tokens`)
        .where("token", "==", rawToken)
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
    const todayStr = now.toISOString().slice(0, 10);
    const [domainsSnap, activitiesSnap, goalsSnap, habitHitsSnap, sessionsSnap, projectsSnap, scheduleSnap, inboxSnap] = await Promise.all([
        db_1.db.collection(`users/${uid}/domains`).get(),
        db_1.db.collection(`users/${uid}/activities`).get(),
        db_1.db.collection(`users/${uid}/goals`).where("status", "==", "active").get(),
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
        return {
            id: v.id,
            name: v.name,
            type: v.type,
            domainId: v.domainId,
            goalMin: v.goalMin,
            habitFreq: v.habitFreq,
            habitTarget: v.habitTarget,
        };
    });
    const activeGoals = goalsSnap.docs.map((d) => {
        const v = d.data();
        const actions = (v.actions || []);
        return {
            id: v.id,
            title: v.title,
            domainId: v.domainId,
            dueDate: v.dueDate || null,
            progress: `${actions.filter((a) => a.done).length}/${actions.length}`,
        };
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
                "• open_schedule pour le programme du jour ; " +
                "• open_goals pour les objectifs GTD. " +
                "Ne programme jamais deux messages avec la même condition pour la même période.",
        ],
    };
    return JSON.stringify(Object.assign(Object.assign({}, coachingRules), { today: todayStr, domains,
        activities,
        activeGoals,
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
async function executeCreateRoutine(uid, args) {
    var _a, _b, _c;
    const id = (0, uuid_1.v4)();
    await db_1.db.collection(`users/${uid}/activities`).doc(id).set({
        id,
        name: args.name,
        domainId: args.domainId,
        type: "habit",
        role: "generic",
        goalMin: 1,
        unit: (_a = args.unit) !== null && _a !== void 0 ? _a : null,
        habitFreq: (_b = args.habitFreq) !== null && _b !== void 0 ? _b : 0,
        habitTarget: (_c = args.habitTarget) !== null && _c !== void 0 ? _c : 1,
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
    const patch = { updatedAt: db_1.FieldValue.serverTimestamp() };
    if (updates.domainId !== undefined)
        patch.domainId = updates.domainId;
    if (updates.title !== undefined)
        patch.title = updates.title;
    if (updates.description !== undefined)
        patch.description = updates.description;
    if (updates.status !== undefined)
        patch.status = updates.status;
    await ref.update(patch);
    return `✅ Projet "${title}" mis à jour.`;
}
async function executeUpdateTaskStatus(uid, projectId, taskId, status) {
    var _a;
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
    var _a, _b;
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
    await ref.update(patch);
    return `✅ Activité "${currentName}" mise à jour.`;
}
async function executeLinkGoalToTask(uid, goalId, projectId, projectTaskId) {
    var _a, _b;
    const ref = db_1.db.collection(`users/${uid}/goals`).doc(goalId);
    const snap = await ref.get();
    if (!snap.exists)
        return `Objectif introuvable : ${goalId}`;
    const title = (_b = (_a = snap.data()) === null || _a === void 0 ? void 0 : _a.title) !== null && _b !== void 0 ? _b : goalId;
    await ref.update({ projectId: projectId !== null && projectId !== void 0 ? projectId : null, projectTaskId: projectTaskId !== null && projectTaskId !== void 0 ? projectTaskId : null });
    if (!projectTaskId)
        return `✅ Objectif "${title}" délié de tout projet Gantt.`;
    return `✅ Objectif "${title}" lié à la tâche Gantt ${projectTaskId}.`;
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
async function executeDeleteGoal(uid, goalId, action) {
    var _a, _b;
    const ref = db_1.db.collection(`users/${uid}/goals`).doc(goalId);
    const snap = await ref.get();
    if (!snap.exists)
        return `Objectif introuvable : ${goalId}`;
    const title = (_b = (_a = snap.data()) === null || _a === void 0 ? void 0 : _a.title) !== null && _b !== void 0 ? _b : goalId;
    if (action === "delete") {
        await ref.delete();
        return `✅ Objectif "${title}" supprimé définitivement.`;
    }
    // Archive par défaut
    await ref.update({ status: "archived" });
    return `✅ Objectif "${title}" archivé.`;
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
async function executePushGantt(uid, input) {
    const { project, strategicObjective } = input;
    let strategicObjectiveId;
    if (strategicObjective) {
        const objId = strategicObjective.id || (0, uuid_1.v4)();
        strategicObjectiveId = objId;
        await db_1.db.collection(`users/${uid}/strategic_objectives`).doc(objId).set(Object.assign(Object.assign({}, strategicObjective), { id: objId, status: "active", updatedAt: db_1.FieldValue.serverTimestamp(), createdAt: db_1.FieldValue.serverTimestamp() }), { merge: true });
    }
    const projectId = project.id || (0, uuid_1.v4)();
    await db_1.db.collection(`users/${uid}/projects`).doc(projectId).set(Object.assign(Object.assign(Object.assign(Object.assign({}, project), { id: projectId, phases: (project.phases || []).map((p) => (Object.assign(Object.assign({}, p), { id: p.id || (0, uuid_1.v4)() }))), tasks: normalizeTasks(project.tasks), createdBy: uid, sourceType: "claude_mcp", status: "active" }), (strategicObjectiveId ? { strategicObjectiveId } : {})), { updatedAt: db_1.FieldValue.serverTimestamp(), createdAt: db_1.FieldValue.serverTimestamp() }), { merge: true });
    if (strategicObjectiveId) {
        await db_1.db.collection(`users/${uid}/strategic_objectives`).doc(strategicObjectiveId)
            .update({ projectIds: db_1.FieldValue.arrayUnion(projectId) });
    }
    const isUpdate = !!project.id;
    return (`✅ Projet "${project.title}" ${isUpdate ? "mis à jour" : "créé"} dans Productivitwo !\n` +
        `• ${(project.tasks || []).length} tâche(s) · ${(project.phases || []).length} phase(s)\n` +
        `• Voir sur : https://productivitwo-app.web.app\n` +
        `• projectId : ${projectId}`);
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
    const today = now.toISOString().slice(0, 10);
    const sevenDaysAgo = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000);
    const [domainsSnap, activitiesSnap, goalsSnap, habitHitsSnap, sessionsSnap, projectsSnap] = await Promise.all([
        db_1.db.collection(`users/${uid}/domains`).get(),
        db_1.db.collection(`users/${uid}/activities`).get(),
        db_1.db.collection(`users/${uid}/goals`).where("status", "==", "active").get(),
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
        .map((v) => { var _a; return ({ id: v.id, name: v.name, type: v.type, domainId: v.domainId, goalMin: (_a = v.goalMin) !== null && _a !== void 0 ? _a : null }); });
    const goals = goalsSnap.docs.map((d) => {
        var _a;
        const v = d.data();
        const actions = (v.actions || []);
        return { id: v.id, title: v.title, domainId: v.domainId, dueDate: (_a = v.dueDate) !== null && _a !== void 0 ? _a : null,
            progress: `${actions.filter((a) => a.done).length}/${actions.length}` };
    });
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
    const in30days = new Date(now.getTime() + 30 * 24 * 60 * 60 * 1000).toISOString().slice(0, 10);
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
    return JSON.stringify({ today, domains, activities, goals, habitStats, timeStats, projects }, null, 2);
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
    const snap = await db_1.db.collection(`users/${uid}/captures`)
        .where("status", "==", "pending")
        .orderBy("createdAt", "asc")
        .get();
    if (snap.empty)
        return "Aucune idée en attente dans l'inbox.";
    const items = snap.docs.map((d) => {
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
// ── Programme horaire journalier ─────────────────────────────────────────────
async function executePlanDay(uid, args) {
    var _a, _b, _c;
    const today = new Date().toISOString().slice(0, 10);
    const date = (_a = args.date) !== null && _a !== void 0 ? _a : today;
    if (!/^\d{4}-\d{2}-\d{2}$/.test(date))
        return `Date invalide : ${date}`;
    const startHour = (_b = args.startHour) !== null && _b !== void 0 ? _b : 7;
    const endHour = (_c = args.endHour) !== null && _c !== void 0 ? _c : 20;
    const syncToCalendar = args.syncToCalendar !== false;
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
        `📋 CONTEXTE PLANIFICATION — ${date} (${startHour}h-${endHour}h)`,
        `══════════════════════════════════════════`,
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
        `══════════════════════════════════════════`,
        `WORKFLOW :`,
        `1. list_events() Google Calendar principal → identifier les créneaux occupés`,
        `2. Générer les blocs (${startHour}h-${endHour}h) : tâches Gantt + routines + pauses`,
        `   → Tâche la plus proche de la deadline en premier`,
        `   → Ne pas recréer les blocs marqués [supprimé par l'utilisateur]`,
        `3. schedule_day("${date}", blocks[])`,
        ...calendarSync,
        `══════════════════════════════════════════`,
    ].join("\n");
}
async function executePlanWeek(uid, args) {
    const today = new Date().toISOString().slice(0, 10);
    let startDate = args.startDate;
    if (!startDate) {
        const d = new Date(today);
        const day = d.getDay();
        const daysToMonday = day === 1 ? 0 : day === 0 ? 1 : 8 - day;
        d.setDate(d.getDate() + daysToMonday);
        startDate = d.toISOString().slice(0, 10);
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
            weekDates.push(d.toISOString().slice(0, 10));
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
    const today = new Date().toISOString().slice(0, 10);
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
async function executeScheduleDay(uid, date, blocks) {
    if (!/^\d{4}-\d{2}-\d{2}$/.test(date))
        return `Date invalide : ${date}. Format attendu : YYYY-MM-DD`;
    if (!(blocks === null || blocks === void 0 ? void 0 : blocks.length))
        return `Aucun bloc fourni — le programme n'a pas été enregistré.`;
    const normalizedBlocks = blocks.map((b) => {
        var _a, _b, _c;
        return ({
            id: (0, uuid_1.v4)(),
            startTime: b.startTime,
            durationMin: b.durationMin,
            title: b.title,
            category: b.category,
            projectId: (_a = b.projectId) !== null && _a !== void 0 ? _a : null,
            taskId: (_b = b.taskId) !== null && _b !== void 0 ? _b : null,
            activityId: (_c = b.activityId) !== null && _c !== void 0 ? _c : null,
            status: "pending",
            doneAt: null,
        });
    });
    await db_1.db.doc(`users/${uid}/daily_schedules/${date}`).set({
        date,
        generatedBy: "claude",
        generatedAt: db_1.FieldValue.serverTimestamp(),
        blocks: normalizedBlocks,
    });
    const lines = normalizedBlocks.map((b) => `• ${b.startTime} (${b.durationMin}min) — ${b.title}`);
    return `✅ Programme du ${date} enregistré — ${normalizedBlocks.length} bloc(s)\n${lines.join("\n")}`;
}
async function executeComputeTimeBudget(uid) {
    const now = new Date();
    const today = now.toISOString().slice(0, 10);
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
    // Indexer les sessions par activité : totalMin + semaines distinctes
    const minByActivity = new Map();
    const weeksByActivity = new Map();
    for (const doc of sessionsSnap.docs) {
        const v = doc.data();
        if (!v.endAt)
            continue;
        const mins = Math.round((new Date(v.endAt).getTime() - new Date(v.startAt).getTime()) / 60000);
        if (mins <= 0)
            continue;
        minByActivity.set(v.activityId, (minByActivity.get(v.activityId) || 0) + mins);
        // Numéro de semaine ISO pour détecter la richesse des données
        const sessionDate = new Date(v.startAt);
        const weekKey = `${sessionDate.getFullYear()}-W${String(Math.ceil(sessionDate.getDate() / 7)).padStart(2, "0")}`;
        if (!weeksByActivity.has(v.activityId))
            weeksByActivity.set(v.activityId, new Set());
        weeksByActivity.get(v.activityId).add(weekKey);
    }
    const MIN_WEEKS_TO_CALIBRATE = 2;
    const PERIOD_DAYS = 84;
    const TOTAL_DAY_MIN = 1440;
    const STRETCH = 1.10;
    const MIN_SLEEP_MIN = 420; // 7h plancher
    const budgets = activities.map((a) => {
        var _a, _b, _c, _d;
        const total = (_a = minByActivity.get(a.id)) !== null && _a !== void 0 ? _a : 0;
        const weeksOfData = (_c = (_b = weeksByActivity.get(a.id)) === null || _b === void 0 ? void 0 : _b.size) !== null && _c !== void 0 ? _c : 0;
        const isSleep = /sommeil|sleep/i.test(a.name);
        const hasEnoughData = weeksOfData >= MIN_WEEKS_TO_CALIBRATE;
        const avgPerDay = hasEnoughData ? total / PERIOD_DAYS : 0;
        return {
            id: a.id,
            name: a.name,
            currentGoalMin: (_d = a.goalMin) !== null && _d !== void 0 ? _d : null,
            avgMinPerDay: Math.round(avgPerDay),
            weeksOfData,
            hasEnoughData,
            isSleep,
        };
    });
    const nonSleep = budgets.filter((b) => !b.isSleep);
    const sleepActivity = budgets.find((b) => b.isSleep);
    // Seules les activités avec assez de données reçoivent un stretch target
    const withStretch = nonSleep.map((b) => (Object.assign(Object.assign({}, b), { recommendedGoalMin: b.hasEnoughData
            ? Math.max(1, Math.round(b.avgMinPerDay * STRETCH))
            : null })));
    const calibrated = withStretch.filter((b) => b.recommendedGoalMin !== null);
    const uncalibrated = withStretch.filter((b) => b.recommendedGoalMin === null);
    const nonSleepTotal = calibrated.reduce((s, b) => { var _a; return s + ((_a = b.recommendedGoalMin) !== null && _a !== void 0 ? _a : 0); }, 0);
    const sleepGoal = Math.max(MIN_SLEEP_MIN, TOTAL_DAY_MIN - nonSleepTotal);
    const result = [
        ...withStretch,
        sleepActivity
            ? Object.assign(Object.assign({}, sleepActivity), { recommendedGoalMin: calibrated.length > 0 ? sleepGoal : null }) : {
            id: null,
            name: "Sommeil (manquant)",
            currentGoalMin: null,
            avgMinPerDay: null,
            weeksOfData: 0,
            hasEnoughData: false,
            isSleep: true,
            recommendedGoalMin: calibrated.length > 0 ? sleepGoal : null,
            missingNote: "Créer une activité 'Sommeil' (type: time) pour activer le suivi budget 24h.",
        },
    ];
    const totalCheck = (calibrated.reduce((s, b) => { var _a; return s + ((_a = b.recommendedGoalMin) !== null && _a !== void 0 ? _a : 0); }, 0)) +
        (calibrated.length > 0 ? sleepGoal : 0);
    return JSON.stringify({
        analysedPeriod: `${twelveWeeksAgo.toISOString().slice(0, 10)} → ${today}`,
        totalDayMin: TOTAL_DAY_MIN,
        calibratedActivities: calibrated.length,
        uncalibratedActivities: uncalibrated.length,
        budgetCheck: calibrated.length > 0 ? `${totalCheck} / ${TOTAL_DAY_MIN} min` : "Données insuffisantes — budget non calculable",
        activities: result,
        workflow: calibrated.length > 0
            ? [
                "1. Si 'Sommeil' est absent (id: null) → create_activity(name='Sommeil', type='time', domainId=<domaine Santé>)",
                "2. Pour chaque activité avec hasEnoughData=true et id non-null → update_activity_goal(activityId, goalMin=recommendedGoalMin)",
                "3. push_assistant_message : liste les objectifs rééquilibrés (±X min/j) + temps sommeil",
                uncalibrated.length > 0
                    ? `4. push_assistant_message pour les ${uncalibrated.length} activité(s) non calibrée(s) : demander à l'utilisateur de logger ses premières sessions pour activer le budget 24h`
                    : "",
            ].filter(Boolean)
            : [
                "Aucune activité n'a assez de données (min 2 semaines de sessions).",
                "push_assistant_message : encourager l'utilisateur à logger ses activités pour activer le budget 24h automatique.",
                "Ne pas appeler update_activity_goal — les goalMin à 1min par défaut ne seraient pas améliorés.",
            ],
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
//# sourceMappingURL=execute.js.map