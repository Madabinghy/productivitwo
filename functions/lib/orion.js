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
const tools_1 = require("./tools");
const ORION_MAX_RUNS = 50;
const ORION_MODEL = "claude-haiku-4-5-20251001";
// ── Convertit un tool MCP (inputSchema) en tool Anthropic (input_schema) ──────
function toAT(t) {
    return {
        name: t.name,
        description: t.description,
        input_schema: t.inputSchema,
    };
}
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
// ── Cycle ORION — accès complet à tous les tools ──────────────────────────────
async function runOrionCycle(uid) {
    var _a, _b, _c, _d, _e, _f, _g;
    const today = new Date().toISOString().slice(0, 10);
    const count = await getOrionRunCount(uid, today);
    if (count >= ORION_MAX_RUNS) {
        return { skipped: true, reason: `Limite journalière atteinte (${count}/${ORION_MAX_RUNS})` };
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
2. Appelle get_user_context pour analyser l'état complet de l'utilisateur.
3. Si l'utilisateur a donné des instructions ou répondu à un message, exécute ce qu'il a demandé en utilisant les outils appropriés.
4. Génère 1 ou 2 messages ORION contextuels via push_assistant_message pour informer l'utilisateur de ce que tu as fait ou de ce qu'il devrait faire.

Règles :
- Lis TOUJOURS get_user_context avant d'agir pour avoir le contexte complet.
- Si l'instruction est ambiguë ou destructive (delete), envoie d'abord un message ORION pour confirmation plutôt que d'agir directement.
- Pour les actions réversibles (archive, update, plan), agis directement si l'intention est claire.
- Messages ORION courts (< 180 chars), bienveillants, actionnables.
- Pas de doublons avec les messages pending existants.
- characterName toujours "ORION".`;
    // Tous les tools disponibles — cache sur le dernier
    const allMcpTools = [
        tools_1.GET_USER_CONTEXT_TOOL, tools_1.GET_ASSISTANT_MESSAGES_TOOL, tools_1.GET_DAY_BLOCKS_TOOL,
        tools_1.GET_DAY_PLAN_TOOL, tools_1.GET_DOCUMENTS_TOOL, tools_1.GET_DOCUMENT_TEMPLATE_TOOL,
        tools_1.GET_ARCHIVES_TOOL, tools_1.LIST_PROJECTS_TOOL, tools_1.GET_PROJECT_TOOL,
        tools_1.PLAN_DAY_TOOL, tools_1.CLEAR_DAY_PLAN_TOOL, tools_1.ADD_TO_DAY_PLAN_TOOL,
        tools_1.CREATE_ACTIVITY_TOOL, tools_1.UPDATE_ACTIVITY_TOOL, tools_1.UPDATE_ACTIVITY_GOAL_TOOL, tools_1.DELETE_ACTIVITY_TOOL,
        tools_1.CREATE_ROUTINE_TOOL, tools_1.DELETE_ROUTINE_TOOL, tools_1.CREATE_RECURRING_ACTION_TOOL, tools_1.DELETE_ACTION_TOOL,
        tools_1.CREATE_DOMAIN_TOOL, tools_1.DELETE_DOMAIN_TOOL,
        tools_1.UPDATE_PROJECT_TOOL, tools_1.UPDATE_TASK_STATUS_TOOL, tools_1.ARCHIVE_PROJECT_TOOL,
        tools_1.DELETE_PROJECT_TOOL, tools_1.PUSH_GANTT_MCP_TOOL,
        tools_1.LINK_GOAL_TO_TASK_TOOL, tools_1.DELETE_GOAL_TOOL,
        tools_1.SAVE_DOCUMENT_TOOL, tools_1.DELETE_DOCUMENT_TOOL, tools_1.RESTORE_ITEM_TOOL,
        tools_1.PUSH_ASSISTANT_MESSAGE_TOOL, tools_1.DELETE_ASSISTANT_MESSAGE_TOOL,
    ];
    const tools = allMcpTools.map((t, i) => (Object.assign(Object.assign({}, toAT(t)), (i === allMcpTools.length - 1 ? { cache_control: { type: "ephemeral" } } : {}))));
    const messages = [
        { role: "user", content: "Effectue ton analyse et agis selon mes instructions." },
    ];
    let pushedCount = 0;
    let continueLoop = true;
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
                        case "get_user_context":
                            result = await (0, execute_1.executeGetUserContext)(uid);
                            break;
                        case "get_assistant_messages":
                            result = await (0, execute_1.executeGetAssistantMessages)(uid);
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
                            break;
                        case "clear_day_plan":
                            result = await (0, execute_1.executeClearDayPlan)(uid, args.date);
                            break;
                        case "add_to_day_plan":
                            result = await (0, execute_1.executeAddToDayPlan)(uid, args);
                            break;
                        // ── Activités ────────────────────────────────────────────────
                        case "create_activity":
                            result = await (0, execute_1.executeCreateActivity)(uid, args);
                            break;
                        case "update_activity":
                            result = await (0, execute_1.executeUpdateActivity)(uid, args.activityId, args);
                            break;
                        case "update_activity_goal":
                            result = await (0, execute_1.executeUpdateActivityGoal)(uid, args.activityId, args);
                            break;
                        case "delete_activity":
                            result = await (0, execute_1.executeDeleteActivity)(uid, args.activityId);
                            break;
                        // ── Routines / Actions ───────────────────────────────────────
                        case "create_routine":
                            result = await (0, execute_1.executeCreateRoutine)(uid, args);
                            break;
                        case "delete_routine":
                            result = await (0, execute_1.executeDeleteRoutine)(uid, args.routineId);
                            break;
                        case "create_recurring_action":
                            result = await (0, execute_1.executeCreateRecurringAction)(uid, args);
                            break;
                        case "delete_action":
                            result = await (0, execute_1.executeDeleteAction)(uid, args.actionId);
                            break;
                        // ── Domaines ─────────────────────────────────────────────────
                        case "create_domain":
                            result = await (0, execute_1.executeCreateDomain)(uid, args);
                            break;
                        case "delete_domain":
                            result = await (0, execute_1.executeDeleteDomain)(uid, args.domainId);
                            break;
                        // ── Projets ──────────────────────────────────────────────────
                        case "update_project":
                            result = await (0, execute_1.executeUpdateProject)(uid, args.projectId, args);
                            break;
                        case "update_task_status":
                            result = await (0, execute_1.executeUpdateTaskStatus)(uid, args.projectId, args.taskId, args.status);
                            break;
                        case "archive_project":
                            result = await (0, execute_1.executeArchiveProject)(uid, args.projectId, (_c = args.restore) !== null && _c !== void 0 ? _c : false);
                            break;
                        case "delete_project":
                            result = await (0, execute_1.executeDeleteProject)(uid, args.projectId, (_d = args.deleteObjective) !== null && _d !== void 0 ? _d : false);
                            break;
                        case "push_gantt":
                            result = await (0, execute_1.executePushGantt)(uid, Object.assign({ uid }, args));
                            break;
                        // ── Objectifs ────────────────────────────────────────────────
                        case "link_goal_to_task":
                            result = await (0, execute_1.executeLinkGoalToTask)(uid, args.goalId, (_e = args.projectId) !== null && _e !== void 0 ? _e : null, (_f = args.projectTaskId) !== null && _f !== void 0 ? _f : null);
                            break;
                        case "delete_goal":
                            result = await (0, execute_1.executeDeleteGoal)(uid, args.goalId, (_g = args.action) !== null && _g !== void 0 ? _g : "archive");
                            break;
                        // ── Documents ────────────────────────────────────────────────
                        case "save_document":
                            result = await (0, execute_1.executeSaveDocument)(uid, args);
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
                        case "push_assistant_message":
                            result = await (0, execute_1.executePushAssistantMessage)(uid, args);
                            pushedCount++;
                            break;
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