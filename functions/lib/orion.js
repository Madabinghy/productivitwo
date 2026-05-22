"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.getOrionConfig = getOrionConfig;
exports.saveOrionConfig = saveOrionConfig;
exports.getOrionRunCount = getOrionRunCount;
exports.runOrionCycle = runOrionCycle;
exports.getAllActiveUserIds = getAllActiveUserIds;
const sdk_1 = require("@anthropic-ai/sdk");
const db_1 = require("./db");
const execute_1 = require("./execute");
// Descriptions compactes pour ORION — ~10x moins de tokens que les tools MCP complets
const ORION_TOOLS = [
    { name: "get_orion_context", description: "Contexte utilisateur : domaines, activités, routines, objectifs, projets actifs (tâches urgentes), plan du jour résumé, stats 7j.", input_schema: { type: "object", properties: {}, required: [] } },
    { name: "get_assistant_messages", description: "Messages ORION en attente et récents. Appeler en premier pour éviter les doublons.", input_schema: { type: "object", properties: {}, required: [] } },
    { name: "get_day_blocks", description: "Blocs de journée configurés.", input_schema: { type: "object", properties: {}, required: [] } },
    { name: "get_day_plan", description: "Plan du jour pour une date donnée.", input_schema: { type: "object", properties: { date: { type: "string", description: "YYYYMMDD" } }, required: ["date"] } },
    { name: "get_documents", description: "Documents de l'utilisateur, filtrables par projectId/taskId.", input_schema: { type: "object", properties: { projectId: { type: "string" }, taskId: { type: "string" } }, required: [] } },
    { name: "get_archives", description: "Éléments archivés/supprimés.", input_schema: { type: "object", properties: {}, required: [] } },
    { name: "list_projects", description: "Liste résumée des projets Gantt.", input_schema: { type: "object", properties: {}, required: [] } },
    { name: "get_project", description: "Détail complet d'un projet Gantt (phases, tâches, IDs).", input_schema: { type: "object", properties: { projectId: { type: "string" } }, required: ["projectId"] } },
    { name: "plan_day", description: "Planifie des actions pour une date.", input_schema: { type: "object", properties: { date: { type: "string" }, items: { type: "array" }, clearExisting: { type: "boolean" } }, required: ["date", "items"] } },
    { name: "clear_day_plan", description: "Vide le plan du jour d'une date.", input_schema: { type: "object", properties: { date: { type: "string" } }, required: ["date"] } },
    { name: "add_to_day_plan", description: "Ajoute un élément au plan du jour.", input_schema: { type: "object", properties: { title: { type: "string" }, yyyymmdd: { type: "string" } }, required: ["title", "yyyymmdd"] } },
    { name: "create_activity", description: "Crée une activité (temps ou habitude).", input_schema: { type: "object", properties: { name: { type: "string" }, type: { type: "string" }, domainId: { type: "string" } }, required: ["name", "type", "domainId"] } },
    { name: "update_activity", description: "Met à jour une activité.", input_schema: { type: "object", properties: { activityId: { type: "string" } }, required: ["activityId"] } },
    { name: "update_activity_goal", description: "Met à jour l'objectif quotidien d'une activité.", input_schema: { type: "object", properties: { activityId: { type: "string" }, goalMin: { type: "number" } }, required: ["activityId"] } },
    { name: "delete_activity", description: "Supprime (soft-delete) une activité.", input_schema: { type: "object", properties: { activityId: { type: "string" } }, required: ["activityId"] } },
    { name: "create_routine", description: "Crée une routine récurrente.", input_schema: { type: "object", properties: { title: { type: "string" }, activityId: { type: "string" } }, required: ["title", "activityId"] } },
    { name: "delete_routine", description: "Supprime une routine.", input_schema: { type: "object", properties: { routineId: { type: "string" } }, required: ["routineId"] } },
    { name: "create_recurring_action", description: "Crée une action récurrente (sans tracking).", input_schema: { type: "object", properties: { title: { type: "string" }, activityId: { type: "string" } }, required: ["title", "activityId"] } },
    { name: "delete_action", description: "Supprime une action récurrente.", input_schema: { type: "object", properties: { actionId: { type: "string" } }, required: ["actionId"] } },
    { name: "create_domain", description: "Crée un domaine de vie.", input_schema: { type: "object", properties: { name: { type: "string" } }, required: ["name"] } },
    { name: "delete_domain", description: "Supprime un domaine.", input_schema: { type: "object", properties: { domainId: { type: "string" } }, required: ["domainId"] } },
    { name: "update_project", description: "Met à jour les champs d'un projet Gantt.", input_schema: { type: "object", properties: { projectId: { type: "string" } }, required: ["projectId"] } },
    { name: "update_task_status", description: "Change le statut d'une tâche (pending/done/skipped).", input_schema: { type: "object", properties: { projectId: { type: "string" }, taskId: { type: "string" }, status: { type: "string" } }, required: ["projectId", "taskId", "status"] } },
    { name: "archive_project", description: "Archive ou restaure un projet.", input_schema: { type: "object", properties: { projectId: { type: "string" }, restore: { type: "boolean" } }, required: ["projectId"] } },
    { name: "delete_project", description: "Supprime définitivement un projet.", input_schema: { type: "object", properties: { projectId: { type: "string" }, deleteObjective: { type: "boolean" } }, required: ["projectId"] } },
    { name: "push_gantt", description: "Crée ou met à jour un projet Gantt complet (phases + tâches).", input_schema: { type: "object", properties: { project: { type: "object" } }, required: ["project"] } },
    { name: "link_goal_to_task", description: "Lie un objectif GTD à une tâche Gantt.", input_schema: { type: "object", properties: { goalId: { type: "string" }, projectId: { type: "string" }, projectTaskId: { type: "string" } }, required: ["goalId"] } },
    { name: "delete_goal", description: "Archive ou supprime un objectif GTD.", input_schema: { type: "object", properties: { goalId: { type: "string" }, action: { type: "string" } }, required: ["goalId"] } },
    { name: "save_document", description: "Sauvegarde un document HTML.", input_schema: { type: "object", properties: { title: { type: "string" }, content: { type: "string" } }, required: ["title", "content"] } },
    { name: "delete_document", description: "Supprime un document.", input_schema: { type: "object", properties: { documentId: { type: "string" } }, required: ["documentId"] } },
    { name: "restore_item", description: "Restaure un élément archivé.", input_schema: { type: "object", properties: { collection: { type: "string" }, itemId: { type: "string" } }, required: ["collection", "itemId"] } },
    { name: "push_assistant_message", description: "Planifie un message ORION contextuel.", input_schema: { type: "object", properties: { targetDate: { type: "string" }, text: { type: "string" }, condition: { type: "object" }, expiresAfterDays: { type: "number" }, priority: { type: "number" } }, required: ["targetDate", "text", "condition"] } },
    { name: "delete_assistant_message", description: "Supprime un message ORION.", input_schema: { type: "object", properties: { messageId: { type: "string" } }, required: ["messageId"] }, cache_control: { type: "ephemeral" } },
];
const ORION_MAX_RUNS = 50;
const ORION_MODEL = "claude-haiku-4-5-20251001";
// ── Config utilisateur ────────────────────────────────────────────────────────
async function getOrionConfig(uid) {
    var _a, _b, _c, _d;
    const snap = await db_1.db.collection(`users/${uid}/orion_config`).doc("main").get();
    if (!snap.exists)
        return { userNeeds: "", userReply: "", replyTimestamp: null };
    const d = (_a = snap.data()) !== null && _a !== void 0 ? _a : {};
    return {
        userNeeds: (_b = d.userNeeds) !== null && _b !== void 0 ? _b : "",
        userReply: (_c = d.userReply) !== null && _c !== void 0 ? _c : "",
        replyTimestamp: (_d = d.replyTimestamp) !== null && _d !== void 0 ? _d : null,
    };
}
async function saveOrionConfig(uid, fields) {
    const update = { updatedAt: db_1.FieldValue.serverTimestamp() };
    if (fields.userNeeds !== undefined)
        update.userNeeds = fields.userNeeds;
    if (fields.userReply !== undefined) {
        update.userReply = fields.userReply;
        update.replyTimestamp = new Date().toISOString().slice(0, 10);
    }
    await db_1.db.collection(`users/${uid}/orion_config`).doc("main").set(update, { merge: true });
}
// ── Rate limiting ─────────────────────────────────────────────────────────────
async function getOrionRunCount(uid, date) {
    var _a, _b;
    const snap = await db_1.db.collection("orion_runs").doc(`${uid}_${date}`).get();
    return snap.exists ? ((_b = (_a = snap.data()) === null || _a === void 0 ? void 0 : _a.count) !== null && _b !== void 0 ? _b : 0) : 0;
}
async function incrementOrionRunCount(uid, date) {
    await db_1.db
        .collection("orion_runs")
        .doc(`${uid}_${date}`)
        .set({ count: db_1.FieldValue.increment(1), uid, date }, { merge: true });
}
// ── Log de cycle ──────────────────────────────────────────────────────────────
async function writeCycleLog(uid, log) {
    const { v4: uuidv4 } = await Promise.resolve().then(() => require("uuid"));
    await db_1.db.collection(`users/${uid}/orion_logs`).doc(uuidv4()).set(Object.assign(Object.assign({}, log), { cycleAt: db_1.FieldValue.serverTimestamp() }));
}
// ── Cycle ORION — accès complet à tous les tools ──────────────────────────────
async function runOrionCycle(uid) {
    var _a, _b, _c, _d, _e, _f, _g, _h, _j, _k, _l, _m, _o, _p, _q;
    const today = new Date().toISOString().slice(0, 10);
    const count = await getOrionRunCount(uid, today);
    if (count >= ORION_MAX_RUNS) {
        const reason = `Limite journalière atteinte (${count}/${ORION_MAX_RUNS})`;
        await writeCycleLog(uid, { userNeeds: "", userReply: "", actions: [], pushed: 0, skipped: true, skippedReason: reason });
        return { skipped: true, reason };
    }
    await incrementOrionRunCount(uid, today);
    const apiKey = process.env.ANTHROPIC_API_KEY;
    if (!apiKey)
        throw new Error("ANTHROPIC_API_KEY non configurée dans Firebase Secret Manager");
    const config = await getOrionConfig(uid);
    const client = new sdk_1.default({ apiKey });
    const userContext = [
        config.userNeeds ? `Instructions de l'utilisateur :\n${config.userNeeds}` : "",
        config.userReply
            ? `Dernière réponse de l'utilisateur (${(_a = config.replyTimestamp) !== null && _a !== void 0 ? _a : "récent"}) :\n${config.userReply}`
            : "",
    ]
        .filter(Boolean)
        .join("\n\n");
    const systemPrompt = `Tu es ORION, l'agent IA autonome de Productivitwo. Tu as accès à tous les outils de l'app et tu peux agir directement sur les données de l'utilisateur.

Date du jour : ${today}${userContext ? `\n\n${userContext}` : ""}

Ta mission pour ce cycle :
1. Appelle get_assistant_messages pour voir les messages ORION en attente (évite les doublons).
2. Appelle get_orion_context pour analyser l'état complet de l'utilisateur.
3. Si l'utilisateur a donné des instructions ou répondu à un message, exécute ce qu'il a demandé en utilisant les outils appropriés.
4. Génère 1 ou 2 messages ORION contextuels via push_assistant_message pour informer l'utilisateur de ce que tu as fait ou de ce qu'il devrait faire.

Règles :
- Lis TOUJOURS get_orion_context avant d'agir pour avoir le contexte complet.
- Si l'instruction est ambiguë ou destructive (delete), envoie d'abord un message ORION pour confirmation plutôt que d'agir directement.
- Pour les actions réversibles (archive, update, plan), agis directement si l'intention est claire.
- Messages ORION courts (< 180 chars), bienveillants, actionnables.
- Pas de doublons avec les messages pending existants.
- characterName toujours "ORION".`;
    const tools = ORION_TOOLS;
    const messages = [
        { role: "user", content: "Effectue ton analyse et agis selon mes instructions." },
    ];
    let pushedCount = 0;
    let continueLoop = true;
    const actionLog = [];
    while (continueLoop) {
        const response = await client.beta.promptCaching.messages.create({
            model: ORION_MODEL,
            max_tokens: 2048,
            system: [{ type: "text", text: systemPrompt, cache_control: { type: "ephemeral" } }],
            tools,
            messages,
        });
        messages.push({ role: "assistant", content: response.content });
        if (response.stop_reason === "end_turn") {
            continueLoop = false;
            break;
        }
        if (response.stop_reason === "tool_use") {
            const toolResults = [];
            for (const block of response.content) {
                if (block.type !== "tool_use")
                    continue;
                const args = block.input;
                let result = "";
                try {
                    switch (block.name) {
                        // ── Lecture ──────────────────────────────────────────────────
                        case "get_orion_context":
                            result = await (0, execute_1.executeGetOrionContext)(uid);
                            actionLog.push("📖 Lecture du contexte utilisateur");
                            break;
                        case "get_assistant_messages":
                            result = await (0, execute_1.executeGetAssistantMessages)(uid);
                            actionLog.push("📩 Vérification des messages ORION existants");
                            break;
                        case "get_day_blocks":
                            result = await (0, execute_1.executeGetDayBlocks)(uid);
                            break;
                        case "get_day_plan":
                            result = await (0, execute_1.executeGetDayPlan)(uid, args.date);
                            break;
                        case "get_documents":
                            result = await (0, execute_1.executeGetDocuments)(uid, args.projectId, args.taskId);
                            break;
                        case "get_document_template":
                            result = (0, execute_1.executeGetDocumentTemplate)();
                            break;
                        case "get_archives":
                            result = await (0, execute_1.executeGetArchives)(uid);
                            break;
                        case "list_projects":
                            result = await (0, execute_1.executeListProjects)(uid);
                            break;
                        case "get_project":
                            result = await (0, execute_1.executeGetProject)(uid, args.projectId);
                            break;
                        // ── Plan du jour ─────────────────────────────────────────────
                        case "plan_day":
                            result = await (0, execute_1.executePlanDay)(uid, args.date, args.items, (_b = args.clearExisting) !== null && _b !== void 0 ? _b : false);
                            actionLog.push(`📅 Plan du jour mis à jour (${args.date})`);
                            break;
                        case "clear_day_plan":
                            result = await (0, execute_1.executeClearDayPlan)(uid, args.date);
                            actionLog.push(`🗑 Plan du jour vidé (${args.date})`);
                            break;
                        case "add_to_day_plan":
                            result = await (0, execute_1.executeAddToDayPlan)(uid, args);
                            actionLog.push(`➕ Ajout au plan du jour`);
                            break;
                        // ── Activités ────────────────────────────────────────────────
                        case "create_activity":
                            result = await (0, execute_1.executeCreateActivity)(uid, args);
                            actionLog.push(`✅ Activité créée : ${(_c = args.name) !== null && _c !== void 0 ? _c : ""}`);
                            break;
                        case "update_activity":
                            result = await (0, execute_1.executeUpdateActivity)(uid, args.activityId, args);
                            actionLog.push(`✏️ Activité mise à jour`);
                            break;
                        case "update_activity_goal":
                            result = await (0, execute_1.executeUpdateActivityGoal)(uid, args.activityId, args);
                            actionLog.push(`🎯 Objectif activité mis à jour`);
                            break;
                        case "delete_activity":
                            result = await (0, execute_1.executeDeleteActivity)(uid, args.activityId);
                            actionLog.push(`🗑 Activité supprimée`);
                            break;
                        // ── Routines / Actions ───────────────────────────────────────
                        case "create_routine":
                            result = await (0, execute_1.executeCreateRoutine)(uid, args);
                            actionLog.push(`✅ Routine créée : ${(_d = args.title) !== null && _d !== void 0 ? _d : ""}`);
                            break;
                        case "delete_routine":
                            result = await (0, execute_1.executeDeleteRoutine)(uid, args.routineId);
                            actionLog.push(`🗑 Routine supprimée`);
                            break;
                        case "create_recurring_action":
                            result = await (0, execute_1.executeCreateRecurringAction)(uid, args);
                            actionLog.push(`✅ Action récurrente créée : ${(_e = args.title) !== null && _e !== void 0 ? _e : ""}`);
                            break;
                        case "delete_action":
                            result = await (0, execute_1.executeDeleteAction)(uid, args.actionId);
                            actionLog.push(`🗑 Action supprimée`);
                            break;
                        // ── Domaines ─────────────────────────────────────────────────
                        case "create_domain":
                            result = await (0, execute_1.executeCreateDomain)(uid, args);
                            actionLog.push(`✅ Domaine créé : ${(_f = args.name) !== null && _f !== void 0 ? _f : ""}`);
                            break;
                        case "delete_domain":
                            result = await (0, execute_1.executeDeleteDomain)(uid, args.domainId);
                            actionLog.push(`🗑 Domaine supprimé`);
                            break;
                        // ── Projets ──────────────────────────────────────────────────
                        case "update_project":
                            result = await (0, execute_1.executeUpdateProject)(uid, args.projectId, args);
                            actionLog.push(`✏️ Projet mis à jour`);
                            break;
                        case "update_task_status":
                            result = await (0, execute_1.executeUpdateTaskStatus)(uid, args.projectId, args.taskId, args.status);
                            actionLog.push(`✏️ Statut tâche → ${args.status} (${args.taskId})`);
                            break;
                        case "archive_project":
                            result = await (0, execute_1.executeArchiveProject)(uid, args.projectId, (_g = args.restore) !== null && _g !== void 0 ? _g : false);
                            actionLog.push(args.restore ? `♻️ Projet restauré` : `🗄 Projet archivé`);
                            break;
                        case "delete_project":
                            result = await (0, execute_1.executeDeleteProject)(uid, args.projectId, (_h = args.deleteObjective) !== null && _h !== void 0 ? _h : false);
                            actionLog.push(`🗑 Projet supprimé`);
                            break;
                        case "push_gantt":
                            result = await (0, execute_1.executePushGantt)(uid, Object.assign({ uid }, args));
                            actionLog.push(`🗂 Projet Gantt créé : ${(_k = (_j = args.project) === null || _j === void 0 ? void 0 : _j.title) !== null && _k !== void 0 ? _k : ""}`);
                            break;
                        // ── Objectifs ────────────────────────────────────────────────
                        case "link_goal_to_task":
                            result = await (0, execute_1.executeLinkGoalToTask)(uid, args.goalId, (_l = args.projectId) !== null && _l !== void 0 ? _l : null, (_m = args.projectTaskId) !== null && _m !== void 0 ? _m : null);
                            actionLog.push(`🔗 Objectif lié à une tâche Gantt`);
                            break;
                        case "delete_goal":
                            result = await (0, execute_1.executeDeleteGoal)(uid, args.goalId, (_o = args.action) !== null && _o !== void 0 ? _o : "archive");
                            actionLog.push(`🗑 Objectif archivé/supprimé`);
                            break;
                        // ── Documents ────────────────────────────────────────────────
                        case "save_document":
                            result = await (0, execute_1.executeSaveDocument)(uid, args);
                            actionLog.push(`📄 Document sauvegardé : ${(_p = args.title) !== null && _p !== void 0 ? _p : ""}`);
                            break;
                        case "delete_document": {
                            const ref = db_1.db.collection(`users/${uid}/documents`).doc(args.documentId);
                            const snap = await ref.get();
                            if (!snap.exists) {
                                result = `Document introuvable : ${args.documentId}`;
                                break;
                            }
                            await ref.delete();
                            result = `✅ Document supprimé.`;
                            break;
                        }
                        case "restore_item":
                            result = await (0, execute_1.executeRestoreItem)(uid, args.collection, args.itemId);
                            break;
                        // ── Messages ORION ───────────────────────────────────────────
                        case "push_assistant_message": {
                            result = await (0, execute_1.executePushAssistantMessage)(uid, args);
                            const msgText = ((_q = args.text) !== null && _q !== void 0 ? _q : "").slice(0, 80);
                            actionLog.push(`💬 Message ORION planifié : "${msgText}${msgText.length >= 80 ? "…" : ""}"`);
                            pushedCount++;
                            break;
                        }
                        case "delete_assistant_message":
                            result = await (0, execute_1.executeDeleteAssistantMessage)(uid, args.messageId);
                            break;
                        default:
                            result = `Outil inconnu dans ORION : ${block.name}`;
                    }
                }
                catch (e) {
                    result = `Erreur outil ${block.name} : ${e instanceof Error ? e.message : String(e)}`;
                }
                toolResults.push({ type: "tool_result", tool_use_id: block.id, content: result });
            }
            messages.push({ role: "user", content: toolResults });
        }
        else {
            continueLoop = false;
        }
    }
    await writeCycleLog(uid, {
        userNeeds: config.userNeeds,
        userReply: config.userReply,
        actions: actionLog,
        pushed: pushedCount,
        skipped: false,
    });
    return { skipped: false, pushed: pushedCount };
}
// ── Itération sur tous les users actifs (pour le cron) ────────────────────────
async function getAllActiveUserIds() {
    const snap = await db_1.db
        .collectionGroup("api_tokens")
        .where("active", "==", true)
        .get();
    const uids = new Set();
    for (const doc of snap.docs) {
        const parts = doc.ref.path.split("/");
        if (parts.length >= 2)
            uids.add(parts[1]);
    }
    return [...uids];
}
//# sourceMappingURL=orion.js.map