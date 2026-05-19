"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.mcpHandler = exports.getCustomToken = exports.pushGantt = void 0;
const https_1 = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const firestore_1 = require("firebase-admin/firestore");
const uuid_1 = require("uuid");
admin.initializeApp();
const db = admin.firestore();
// ── Helpers ───────────────────────────────────────────────────────────────────
function normalizePhases(phases) {
    if (!phases)
        return [];
    return phases.map((p) => (Object.assign(Object.assign({}, p), { id: p.id || (0, uuid_1.v4)() })));
}
function normalizeTasks(tasks) {
    if (!tasks)
        return [];
    return tasks.map((t) => {
        var _a, _b;
        return (Object.assign(Object.assign({}, t), { id: t.id || (0, uuid_1.v4)(), isMilestone: (_a = t.isMilestone) !== null && _a !== void 0 ? _a : false, status: (_b = t.status) !== null && _b !== void 0 ? _b : "pending" }));
    });
}
// ── pushGantt ─────────────────────────────────────────────────────────────────
//
// POST https://us-central1-productivitwo-app.cloudfunctions.net/pushGantt
// Headers: Authorization: Bearer <token>
// Body: { uid, project, strategicObjective? }
exports.pushGantt = (0, https_1.onRequest)({ cors: true, invoker: "public" }, async (req, res) => {
    var _a, _b, _c;
    if (req.method === "OPTIONS") {
        res.status(204).send("");
        return;
    }
    if (req.method !== "POST") {
        res.status(405).json({ error: "Method Not Allowed" });
        return;
    }
    // 1. Bearer token
    const authHeader = (_a = req.headers.authorization) !== null && _a !== void 0 ? _a : "";
    if (!authHeader.startsWith("Bearer ")) {
        res.status(401).json({ error: "Missing Authorization header" });
        return;
    }
    const rawToken = authHeader.slice(7).trim();
    // 2. Validation du corps
    const body = req.body;
    if (!body.uid || !((_b = body.project) === null || _b === void 0 ? void 0 : _b.title) || !((_c = body.project) === null || _c === void 0 ? void 0 : _c.startDate)) {
        res.status(400).json({ error: "Missing required fields: uid, project.title, project.startDate" });
        return;
    }
    const { uid, project, strategicObjective } = body;
    // 3. Vérification du token
    const tokenQuery = await db
        .collection(`users/${uid}/api_tokens`)
        .where("token", "==", rawToken)
        .where("active", "==", true)
        .limit(1)
        .get();
    if (tokenQuery.empty) {
        res.status(401).json({ error: "Invalid or revoked token" });
        return;
    }
    // 4. Mise à jour lastUsedAt
    tokenQuery.docs[0].ref.update({ lastUsedAt: firestore_1.FieldValue.serverTimestamp() });
    // 5. Objectif stratégique
    let strategicObjectiveId;
    if (strategicObjective) {
        const objId = strategicObjective.id || (0, uuid_1.v4)();
        strategicObjectiveId = objId;
        await db.collection(`users/${uid}/strategic_objectives`).doc(objId).set(Object.assign(Object.assign({}, strategicObjective), { id: objId, status: "active", updatedAt: firestore_1.FieldValue.serverTimestamp(), createdAt: firestore_1.FieldValue.serverTimestamp() }), { merge: true });
    }
    // 6. Projet
    const projectId = project.id || (0, uuid_1.v4)();
    const projectDoc = Object.assign(Object.assign(Object.assign(Object.assign({}, project), { id: projectId, phases: normalizePhases(project.phases), tasks: normalizeTasks(project.tasks), createdBy: uid, sourceType: "claude_api", status: "active" }), (strategicObjectiveId ? { strategicObjectiveId } : {})), { updatedAt: firestore_1.FieldValue.serverTimestamp(), createdAt: firestore_1.FieldValue.serverTimestamp() });
    await db.collection(`users/${uid}/projects`).doc(projectId).set(projectDoc, { merge: true });
    // 7. Lier projet → objectif
    if (strategicObjectiveId) {
        await db
            .collection(`users/${uid}/strategic_objectives`)
            .doc(strategicObjectiveId)
            .update({ projectIds: firestore_1.FieldValue.arrayUnion(projectId) });
    }
    res.status(200).json({ success: true, projectId, strategicObjectiveId: strategicObjectiveId !== null && strategicObjectiveId !== void 0 ? strategicObjectiveId : null });
});
// ── Remote MCP Handler ────────────────────────────────────────────────────────
//
// URL : /mcp/{uid}/{token}
// Implémente le protocole MCP JSON-RPC 2.0 (Streamable HTTP, stateless).
// Compatible Claude Desktop et Claude.ai web (Integrations).
// ── Outils contexte utilisateur + écriture agenda ────────────────────────────
const GET_USER_CONTEXT_TOOL = {
    name: "get_user_context",
    description: "Retourne le contexte complet de l'utilisateur : domaines de vie, activités " +
        "(avec leurs objectifs quotidiens), routines actives et objectifs GTD en cours. " +
        "Appelle cet outil en premier pour personnaliser tes suggestions.",
    inputSchema: { type: "object", properties: {} },
};
const UPDATE_ACTIVITY_GOAL_TOOL = {
    name: "update_activity_goal",
    description: "Modifie l'objectif quotidien d'une activité (temps ou fréquence). " +
        "Utilise cet outil pour ajuster la charge de travail en fonction du Gantt ou de la réalité de l'utilisateur.",
    inputSchema: {
        type: "object",
        required: ["activityId"],
        properties: {
            activityId: { type: "string", description: "id de l'activité (obtenu via get_user_context)" },
            goalMin: { type: "number", description: "Nouvel objectif en minutes/jour (activités 'time')" },
            habitTarget: { type: "number", description: "Nouvelle cible de fréquence (activités 'habit')" },
            habitFreq: { type: "number", description: "0=daily, 1=weekly, 2=monthly" },
        },
    },
};
const CREATE_ROUTINE_TOOL = {
    name: "create_routine",
    description: "Crée une action récurrente dans Productivitwo. " +
        "Peut être liée à une période (startDate/endDate) et à une tâche Gantt (projectTaskId). " +
        "La routine apparaît automatiquement dans le plan quotidien de l'utilisateur.",
    inputSchema: {
        type: "object",
        required: ["title"],
        properties: {
            title: { type: "string", description: "Intitulé de l'action récurrente" },
            domainId: { type: "string", description: "id du domaine associé (optionnel)" },
            activityId: { type: "string", description: "id de l'activité associée (optionnel)" },
            recurrenceType: {
                type: "string",
                enum: ["daily", "specificDays"],
                description: "'daily' = tous les jours, 'specificDays' = jours choisis",
            },
            weekdays: {
                type: "array",
                items: { type: "number" },
                description: "Jours actifs si specificDays : 1=Lun, 2=Mar … 7=Dim",
            },
            startDate: { type: "string", description: "Date d'activation ISO YYYY-MM-DD (optionnel)" },
            endDate: { type: "string", description: "Date d'expiration ISO YYYY-MM-DD (optionnel)" },
            projectTaskId: { type: "string", description: "id de la tâche Gantt liée (optionnel)" },
        },
    },
};
const ADD_TO_DAY_PLAN_TOOL = {
    name: "add_to_day_plan",
    description: "Ajoute une action au plan quotidien de l'utilisateur pour une date donnée. " +
        "Utilise cet outil pour planifier des actions spécifiques dans l'agenda.",
    inputSchema: {
        type: "object",
        required: ["title", "date"],
        properties: {
            title: { type: "string", description: "Titre de l'action" },
            date: { type: "string", description: "Date ISO YYYY-MM-DD" },
            domainId: { type: "string" },
            activityId: { type: "string" },
            projectId: { type: "string" },
            projectTaskId: { type: "string" },
        },
    },
};
const GET_DAY_BLOCKS_TOOL = {
    name: "get_day_blocks",
    description: "Retourne les blocs de journée de l'utilisateur (Miracle Morning, Matinée, Midi…) " +
        "avec leurs activités et horaires. Utilise cet outil avant de créer un programme du jour " +
        "pour savoir dans quels blocs positionner les actions.",
    inputSchema: { type: "object", properties: {} },
};
const GET_DAY_PLAN_TOOL = {
    name: "get_day_plan",
    description: "Retourne le plan du jour pour une date donnée — ce qui est déjà planifié, " +
        "fait ou reporté. Utilise cet outil pour voir les créneaux libres avant de planifier.",
    inputSchema: {
        type: "object",
        required: ["date"],
        properties: {
            date: { type: "string", description: "Date ISO YYYY-MM-DD" },
        },
    },
};
const PLAN_DAY_TOOL = {
    name: "plan_day",
    description: "Crée le programme personnalisé d'une journée en ajoutant plusieurs actions dans " +
        "les bons blocs. C'est l'outil principal pour être l'assistant de planning de l'utilisateur. " +
        "Positionne les actions selon les blocs disponibles, les rendez-vous du calendrier, " +
        "et les objectifs de l'utilisateur. Peut aussi générer des titres de type 'Rendez-vous avec [objectif]'.",
    inputSchema: {
        type: "object",
        required: ["date", "items"],
        properties: {
            date: { type: "string", description: "Date ISO YYYY-MM-DD" },
            clearExisting: {
                type: "boolean",
                description: "Si true, efface le plan existant avant d'ajouter (défaut: false)",
            },
            items: {
                type: "array",
                description: "Liste des actions à planifier",
                items: {
                    type: "object",
                    required: ["title"],
                    properties: {
                        title: { type: "string", description: "Titre de l'action ou du créneau" },
                        blockId: { type: "string", description: "id du bloc (obtenu via get_day_blocks)" },
                        domainId: { type: "string" },
                        activityId: { type: "string" },
                        projectId: { type: "string" },
                        projectTaskId: { type: "string" },
                        durationNote: { type: "string", description: "Note de durée visible (ex: '45 min')" },
                    },
                },
            },
        },
    },
};
const DELETE_PROJECT_TOOL = {
    name: "delete_project",
    description: "Supprime définitivement un projet Gantt et son objectif stratégique associé. " +
        "Utilise list_projects pour trouver l'id avant de supprimer. " +
        "Demande toujours confirmation à l'utilisateur avant d'appeler cet outil.",
    inputSchema: {
        type: "object",
        required: ["projectId"],
        properties: {
            projectId: { type: "string", description: "id du projet à supprimer" },
            deleteObjective: {
                type: "boolean",
                description: "Si true, supprime aussi l'objectif stratégique lié (défaut: false)",
            },
        },
    },
};
const LIST_PROJECTS_TOOL = {
    name: "list_projects",
    description: "Liste les projets Gantt existants dans Productivitwo. " +
        "Appelle cet outil avant de modifier un projet afin de récupérer son id.",
    inputSchema: { type: "object", properties: {} },
};
const GET_PROJECT_TOOL = {
    name: "get_project",
    description: "Retourne le détail complet d'un projet Gantt (phases, tâches, jalons). " +
        "Utilise cet outil pour lire un projet avant de le modifier.",
    inputSchema: {
        type: "object",
        required: ["projectId"],
        properties: {
            projectId: { type: "string", description: "L'id du projet (obtenu via list_projects)" },
        },
    },
};
const PUSH_GANTT_MCP_TOOL = {
    name: "push_gantt",
    description: "Crée ou met à jour un projet Gantt dans Productivitwo. " +
        "Pour modifier un projet existant, fournis son id (obtenu via list_projects + get_project) " +
        "avec le contenu complet mis à jour. Pour créer un nouveau projet, omets l'id.",
    inputSchema: {
        type: "object",
        required: ["project"],
        properties: {
            project: {
                type: "object",
                required: ["title", "startDate"],
                properties: {
                    title: { type: "string" },
                    description: { type: "string" },
                    startDate: { type: "string", description: "YYYY-MM-DD" },
                    endDate: { type: "string", description: "YYYY-MM-DD" },
                    phases: {
                        type: "array",
                        items: {
                            type: "object",
                            required: ["label", "startDate", "endDate"],
                            properties: {
                                label: { type: "string" },
                                color: { type: "string" },
                                startDate: { type: "string" },
                                endDate: { type: "string" },
                            },
                        },
                    },
                    tasks: {
                        type: "array",
                        items: {
                            type: "object",
                            required: ["title", "startDate"],
                            properties: {
                                title: { type: "string" },
                                groupLabel: { type: "string" },
                                startDate: { type: "string" },
                                endDate: { type: "string" },
                                isMilestone: { type: "boolean" },
                                color: { type: "string" },
                                barLabel: { type: "string" },
                                status: { type: "string", enum: ["pending", "done", "skipped"] },
                            },
                        },
                    },
                },
            },
            strategicObjective: {
                type: "object",
                properties: {
                    title: { type: "string" },
                    kpiTarget: { type: "string" },
                    horizonLabel: { type: "string" },
                },
            },
        },
    },
};
async function validateToken(uid, rawToken) {
    const q = await db
        .collection(`users/${uid}/api_tokens`)
        .where("token", "==", rawToken)
        .where("active", "==", true)
        .limit(1)
        .get();
    if (!q.empty) {
        q.docs[0].ref.update({ lastUsedAt: firestore_1.FieldValue.serverTimestamp() });
        return true;
    }
    return false;
}
async function executeGetUserContext(uid) {
    // Fenêtre glissante : 7 derniers jours
    const now = new Date();
    const sevenDaysAgo = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000);
    const ymdFrom = sevenDaysAgo.toISOString().slice(0, 10).replace(/-/g, "");
    const [domainsSnap, activitiesSnap, routinesSnap, goalsSnap, dayPlanSnap, habitHitsSnap, sessionsSnap] = await Promise.all([
        db.collection(`users/${uid}/domains`).get(),
        db.collection(`users/${uid}/activities`).get(),
        db.collection(`users/${uid}/recurringActions`).get(),
        db.collection(`users/${uid}/goals`).where("status", "==", "active").get(),
        // Actions planifiées et réalisées sur 7 jours
        db.collection(`users/${uid}/dayPlan`)
            .where("yyyymmdd", ">=", ymdFrom)
            .get(),
        // Incréments de routines/habitudes sur 7 jours
        db.collection(`users/${uid}/habitHits`)
            .where("ts", ">=", sevenDaysAgo)
            .get(),
        // Sessions de temps loggué sur 7 jours
        db.collection(`users/${uid}/sessions`)
            .where("startAt", ">=", sevenDaysAgo.toISOString())
            .get(),
    ]);
    const domains = domainsSnap.docs.map((d) => {
        const v = d.data();
        return { id: v.id, name: v.name };
    });
    const activityMap = new Map();
    const activities = activitiesSnap.docs.map((d) => {
        const v = d.data();
        activityMap.set(v.id, v.name);
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
    const activeRoutines = routinesSnap.docs
        .map((d) => d.data())
        .filter((r) => r.active)
        .map((r) => ({
        id: r.id,
        title: r.title,
        type: r.type,
        weekdays: r.weekdays || [],
        startDate: r.startDate || null,
        endDate: r.endDate || null,
        domainId: r.domainId || null,
        activityId: r.activityId || null,
    }));
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
    // Actions complétées (dayPlan done)
    const completedActions = dayPlanSnap.docs
        .map((d) => d.data())
        .filter((it) => it.done)
        .map((it) => ({
        title: it.title,
        date: it.yyyymmdd,
        domainId: it.domainId || null,
    }));
    // Actions planifiées non faites (pour identifier les écarts)
    const pendingActions = dayPlanSnap.docs
        .map((d) => d.data())
        .filter((it) => !it.done && !it.archived && it.status !== "archived")
        .map((it) => ({ title: it.title, date: it.yyyymmdd }));
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
        completedActions,
        pendingActions,
        habitCompletion,
        timeLogged,
    };
    return JSON.stringify({ domains, activities, activeRoutines, activeGoals, recentActivity }, null, 2);
}
async function executeUpdateActivityGoal(uid, activityId, updates) {
    var _a, _b;
    const ref = db.collection(`users/${uid}/activities`).doc(activityId);
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
    const id = (0, uuid_1.v4)();
    await db.collection(`users/${uid}/recurringActions`).doc(id).set({
        id,
        title: args.title,
        domainId: args.domainId || null,
        activityId: args.activityId || null,
        blockId: null,
        type: args.recurrenceType === "specificDays" ? "specificDays" : "daily",
        weekdays: args.weekdays || [],
        active: true,
        createdAt: firestore_1.FieldValue.serverTimestamp(),
        startDate: args.startDate || null,
        endDate: args.endDate || null,
        projectTaskId: args.projectTaskId || null,
    });
    const period = args.startDate && args.endDate
        ? ` du ${args.startDate} au ${args.endDate}`
        : args.startDate ? ` à partir du ${args.startDate}`
            : args.endDate ? ` jusqu'au ${args.endDate}`
                : "";
    return `✅ Routine "${args.title}" créée${period}. Elle apparaîtra dans le plan quotidien dès la prochaine ouverture de l'app.`;
}
async function executeAddToDayPlan(uid, args) {
    // Valider le format de date
    if (!/^\d{4}-\d{2}-\d{2}$/.test(args.date)) {
        return `Date invalide : ${args.date}. Format attendu : YYYY-MM-DD`;
    }
    const yyyymmdd = args.date.replace(/-/g, "");
    const id = (0, uuid_1.v4)();
    await db.collection(`users/${uid}/dayPlan`).doc(id).set({
        id,
        kind: "action",
        title: args.title,
        yyyymmdd,
        done: false,
        doneCount: 0,
        allDay: false,
        isNowFocus: false,
        order: 9999,
        toPlan: false,
        archived: false,
        status: "active",
        createdAt: firestore_1.FieldValue.serverTimestamp(),
        domainId: args.domainId || null,
        activityId: args.activityId || null,
        projectId: args.projectId || null,
        projectTaskId: args.projectTaskId || null,
    });
    return `✅ "${args.title}" ajouté au plan du ${args.date}.`;
}
async function executeGetDayBlocks(uid) {
    const snap = await db.collection(`users/${uid}/blocks`).orderBy("order").get();
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
async function executeGetDayPlan(uid, date) {
    const yyyymmdd = date.replace(/-/g, "");
    const snap = await db.collection(`users/${uid}/dayPlan`)
        .where("yyyymmdd", "==", yyyymmdd)
        .get();
    if (snap.empty)
        return `Aucune action planifiée le ${date}.`;
    const items = snap.docs.map((d) => {
        const v = d.data();
        return {
            id: v.id,
            title: v.title,
            done: v.done,
            blockId: v.blockId || null,
            domainId: v.domainId || null,
            activityId: v.activityId || null,
            status: v.status || "active",
            order: v.order || 0,
        };
    }).sort((a, b) => a.order - b.order);
    const done = items.filter((it) => it.done).length;
    return JSON.stringify({
        date,
        summary: `${done}/${items.length} actions faites`,
        items,
    }, null, 2);
}
async function executePlanDay(uid, date, items, clearExisting) {
    const yyyymmdd = date.replace(/-/g, "");
    if (clearExisting) {
        // Supprimer les items non-faits du jour
        const existing = await db.collection(`users/${uid}/dayPlan`)
            .where("yyyymmdd", "==", yyyymmdd)
            .where("done", "==", false)
            .get();
        const batch = db.batch();
        for (const doc of existing.docs)
            batch.delete(doc.ref);
        if (!existing.empty)
            await batch.commit();
    }
    const addBatch = db.batch();
    items.forEach((item, i) => {
        const id = (0, uuid_1.v4)();
        const title = item.durationNote
            ? `${item.title} (${item.durationNote})`
            : item.title;
        addBatch.set(db.collection(`users/${uid}/dayPlan`).doc(id), {
            id,
            kind: "action",
            title,
            yyyymmdd,
            done: false,
            doneCount: 0,
            allDay: false,
            isNowFocus: false,
            order: 9000 + i,
            toPlan: false,
            archived: false,
            status: "active",
            createdAt: firestore_1.FieldValue.serverTimestamp(),
            blockId: item.blockId || null,
            domainId: item.domainId || null,
            activityId: item.activityId || null,
            projectId: item.projectId || null,
            projectTaskId: item.projectTaskId || null,
        });
    });
    await addBatch.commit();
    return (`✅ Programme du ${date} créé — ${items.length} action(s) planifiée(s).\n` +
        items.map((it, i) => `  ${i + 1}. ${it.title}${it.blockId ? ` → bloc ${it.blockId}` : ""}`).join("\n"));
}
async function executeDeleteProject(uid, projectId, deleteObjective) {
    var _a;
    const projectRef = db.collection(`users/${uid}/projects`).doc(projectId);
    const projectSnap = await projectRef.get();
    if (!projectSnap.exists) {
        return `Projet introuvable : ${projectId}`;
    }
    const projectData = projectSnap.data();
    const title = (_a = projectData.title) !== null && _a !== void 0 ? _a : projectId;
    const objId = projectData.strategicObjectiveId;
    await projectRef.delete();
    if (deleteObjective && objId) {
        await db.collection(`users/${uid}/strategic_objectives`).doc(objId).delete();
        return `✅ Projet "${title}" et son objectif stratégique supprimés.`;
    }
    return `✅ Projet "${title}" supprimé.`;
}
async function executeListProjects(uid) {
    const snap = await db.collection(`users/${uid}/projects`).get();
    if (snap.empty)
        return "Aucun projet trouvé dans Productivitwo.";
    const lines = snap.docs.map((doc) => {
        const d = doc.data();
        const taskCount = (d.tasks || []).length;
        const start = d.startDate || "?";
        const end = d.endDate || "?";
        return `• [${d.id}] ${d.title} (${start} → ${end}, ${taskCount} tâche(s))`;
    });
    return `Projets Productivitwo (${snap.size}) :\n${lines.join("\n")}`;
}
async function executeGetProject(uid, projectId) {
    const doc = await db.collection(`users/${uid}/projects`).doc(projectId).get();
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
        await db.collection(`users/${uid}/strategic_objectives`).doc(objId).set(Object.assign(Object.assign({}, strategicObjective), { id: objId, status: "active", updatedAt: firestore_1.FieldValue.serverTimestamp(), createdAt: firestore_1.FieldValue.serverTimestamp() }), { merge: true });
    }
    const projectId = project.id || (0, uuid_1.v4)();
    await db.collection(`users/${uid}/projects`).doc(projectId).set(Object.assign(Object.assign(Object.assign(Object.assign({}, project), { id: projectId, phases: (project.phases || []).map((p) => (Object.assign(Object.assign({}, p), { id: p.id || (0, uuid_1.v4)() }))), tasks: (project.tasks || []).map((t) => { var _a, _b; return (Object.assign(Object.assign({}, t), { id: t.id || (0, uuid_1.v4)(), isMilestone: (_a = t.isMilestone) !== null && _a !== void 0 ? _a : false, status: (_b = t.status) !== null && _b !== void 0 ? _b : "pending" })); }), createdBy: uid, sourceType: "claude_mcp", status: "active" }), (strategicObjectiveId ? { strategicObjectiveId } : {})), { updatedAt: firestore_1.FieldValue.serverTimestamp(), createdAt: firestore_1.FieldValue.serverTimestamp() }), { merge: true });
    if (strategicObjectiveId) {
        await db.collection(`users/${uid}/strategic_objectives`).doc(strategicObjectiveId)
            .update({ projectIds: firestore_1.FieldValue.arrayUnion(projectId) });
    }
    const isUpdate = !!project.id;
    return (`✅ Projet "${project.title}" ${isUpdate ? "mis à jour" : "créé"} dans Productivitwo !\n` +
        `• ${(project.tasks || []).length} tâche(s) · ${(project.phases || []).length} phase(s)\n` +
        `• Voir sur : https://productivitwo-app.web.app\n` +
        `• projectId : ${projectId}`);
}
// ── getCustomToken ────────────────────────────────────────────────────────────
//
// POST { uid, token }
// Valide le token API, retourne un Firebase custom token pour cet UID.
// Permet au web app de se connecter avec le même UID que l'app iOS.
exports.getCustomToken = (0, https_1.onRequest)({ cors: true, invoker: "public" }, async (req, res) => {
    if (req.method === "OPTIONS") {
        res.status(204).send("");
        return;
    }
    if (req.method !== "POST") {
        res.status(405).json({ error: "Method Not Allowed" });
        return;
    }
    const { uid, token } = req.body;
    if (!uid || !token) {
        res.status(400).json({ error: "uid et token requis" });
        return;
    }
    const valid = await validateToken(uid, token);
    if (!valid) {
        res.status(401).json({ error: "Token invalide ou révoqué" });
        return;
    }
    const customToken = await admin.auth().createCustomToken(uid);
    res.status(200).json({ customToken });
});
exports.mcpHandler = (0, https_1.onRequest)({ cors: true, invoker: "public" }, async (req, res) => {
    var _a, _b, _c, _d, _e, _f, _g, _h;
    // CORS preflight
    if (req.method === "OPTIONS") {
        res.status(204).send("");
        return;
    }
    // Extraire uid + token du path : /mcp/{uid}/{token}
    // Firebase Hosting conserve le préfixe /mcp/ dans req.path
    const parts = (req.path || "").replace(/^\/+mcp\/*/, "").split("/");
    const uid = parts[0] || "";
    const token = parts[1] || "";
    if (!uid || !token) {
        res.status(401).json({ error: "URL invalide — format attendu : /mcp/{uid}/{token}" });
        return;
    }
    // Valider le token
    const valid = await validateToken(uid, token);
    if (!valid) {
        res.status(401).json({ error: "Token invalide ou révoqué" });
        return;
    }
    // Lire le body JSON-RPC
    const body = req.body;
    const requests = Array.isArray(body) ? body : [body];
    const responses = [];
    for (const rpc of requests) {
        const id = (_a = rpc.id) !== null && _a !== void 0 ? _a : null;
        const method = (_b = rpc.method) !== null && _b !== void 0 ? _b : "";
        // Notifications (pas de réponse attendue)
        if (id === null && method.startsWith("notifications/"))
            continue;
        if (method === "initialize") {
            responses.push({
                jsonrpc: "2.0", id,
                result: {
                    protocolVersion: "2024-11-05",
                    capabilities: { tools: {} },
                    serverInfo: { name: "productivitwo", version: "1.0.0" },
                },
            });
        }
        else if (method === "ping") {
            responses.push({ jsonrpc: "2.0", id, result: {} });
        }
        else if (method === "tools/list") {
            responses.push({
                jsonrpc: "2.0", id,
                result: {
                    tools: [
                        GET_USER_CONTEXT_TOOL,
                        GET_DAY_BLOCKS_TOOL,
                        GET_DAY_PLAN_TOOL,
                        PLAN_DAY_TOOL,
                        LIST_PROJECTS_TOOL,
                        GET_PROJECT_TOOL,
                        PUSH_GANTT_MCP_TOOL,
                        DELETE_PROJECT_TOOL,
                        UPDATE_ACTIVITY_GOAL_TOOL,
                        CREATE_ROUTINE_TOOL,
                        ADD_TO_DAY_PLAN_TOOL,
                    ],
                },
            });
        }
        else if (method === "tools/call") {
            const toolName = (_d = (_c = rpc.params) === null || _c === void 0 ? void 0 : _c.name) !== null && _d !== void 0 ? _d : "";
            const args = (_f = (_e = rpc.params) === null || _e === void 0 ? void 0 : _e.arguments) !== null && _f !== void 0 ? _f : {};
            try {
                let text = "";
                if (toolName === "get_day_blocks") {
                    text = await executeGetDayBlocks(uid);
                }
                else if (toolName === "get_day_plan") {
                    text = await executeGetDayPlan(uid, args.date);
                }
                else if (toolName === "plan_day") {
                    text = await executePlanDay(uid, args.date, args.items, (_g = args.clearExisting) !== null && _g !== void 0 ? _g : false);
                }
                else if (toolName === "delete_project") {
                    text = await executeDeleteProject(uid, args.projectId, (_h = args.deleteObjective) !== null && _h !== void 0 ? _h : false);
                }
                else if (toolName === "get_user_context") {
                    text = await executeGetUserContext(uid);
                }
                else if (toolName === "list_projects") {
                    text = await executeListProjects(uid);
                }
                else if (toolName === "get_project") {
                    text = await executeGetProject(uid, args.projectId);
                }
                else if (toolName === "push_gantt") {
                    text = await executePushGantt(uid, Object.assign({ uid }, args));
                }
                else if (toolName === "update_activity_goal") {
                    text = await executeUpdateActivityGoal(uid, args.activityId, args);
                }
                else if (toolName === "create_routine") {
                    text = await executeCreateRoutine(uid, args);
                }
                else if (toolName === "add_to_day_plan") {
                    text = await executeAddToDayPlan(uid, args);
                }
                else {
                    responses.push({ jsonrpc: "2.0", id, error: { code: -32601, message: `Outil inconnu : ${toolName}` } });
                    continue;
                }
                responses.push({ jsonrpc: "2.0", id, result: { content: [{ type: "text", text }] } });
            }
            catch (e) {
                const msg = e instanceof Error ? e.message : String(e);
                responses.push({ jsonrpc: "2.0", id, result: { content: [{ type: "text", text: `Erreur : ${msg}` }], isError: true } });
            }
        }
        else {
            responses.push({ jsonrpc: "2.0", id, error: { code: -32601, message: `Méthode inconnue : ${method}` } });
        }
    }
    res.setHeader("Content-Type", "application/json");
    res.status(200).json(responses.length === 1 ? responses[0] : responses);
});
//# sourceMappingURL=index.js.map