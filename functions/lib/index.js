"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.structureProject = exports.orionCron = exports.orionRunCount = exports.orionSaveConfig = exports.orionWebhook = exports.mcpHandler = exports.getCustomToken = exports.pushAssistantMessage = exports.markPlanItemDone = exports.pushGantt = void 0;
const https_1 = require("firebase-functions/v2/https");
const scheduler_1 = require("firebase-functions/v2/scheduler");
const admin = require("firebase-admin");
const orion_1 = require("./orion");
const models_1 = require("./models");
const sdk_1 = require("@anthropic-ai/sdk");
const orion_tasks_1 = require("./orion_tasks");
const uuid_1 = require("uuid");
const db_1 = require("./db");
const prompts_1 = require("./prompts");
const tools_1 = require("./tools");
const execute_1 = require("./execute");
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
    const authHeader = (_a = req.headers.authorization) !== null && _a !== void 0 ? _a : "";
    if (!authHeader.startsWith("Bearer ")) {
        res.status(401).json({ error: "Missing Authorization header" });
        return;
    }
    const rawToken = authHeader.slice(7).trim();
    const body = req.body;
    if (!body.uid || !((_b = body.project) === null || _b === void 0 ? void 0 : _b.title) || !((_c = body.project) === null || _c === void 0 ? void 0 : _c.startDate)) {
        res.status(400).json({ error: "Missing required fields: uid, project.title, project.startDate" });
        return;
    }
    const { uid, project, strategicObjective } = body;
    const tokenQuery = await db_1.db
        .collection(`users/${uid}/api_tokens`)
        .where("token", "==", rawToken)
        .where("active", "==", true)
        .limit(1)
        .get();
    if (tokenQuery.empty) {
        res.status(401).json({ error: "Invalid or revoked token" });
        return;
    }
    tokenQuery.docs[0].ref.update({ lastUsedAt: db_1.FieldValue.serverTimestamp() });
    let strategicObjectiveId;
    if (strategicObjective) {
        const objId = strategicObjective.id || (0, uuid_1.v4)();
        strategicObjectiveId = objId;
        await db_1.db.collection(`users/${uid}/strategic_objectives`).doc(objId).set(Object.assign(Object.assign({}, strategicObjective), { id: objId, status: "active", updatedAt: db_1.FieldValue.serverTimestamp(), createdAt: db_1.FieldValue.serverTimestamp() }), { merge: true });
    }
    const projectId = project.id || (0, uuid_1.v4)();
    await db_1.db.collection(`users/${uid}/projects`).doc(projectId).set(Object.assign(Object.assign(Object.assign(Object.assign({}, project), { id: projectId, phases: (0, execute_1.normalizePhases)(project.phases), tasks: (0, execute_1.normalizeTasks)(project.tasks), createdBy: uid, sourceType: "claude_api", status: "active" }), (strategicObjectiveId ? { strategicObjectiveId } : {})), { updatedAt: db_1.FieldValue.serverTimestamp(), createdAt: db_1.FieldValue.serverTimestamp() }), { merge: true });
    if (strategicObjectiveId) {
        await db_1.db.collection(`users/${uid}/strategic_objectives`).doc(strategicObjectiveId)
            .update({ projectIds: db_1.FieldValue.arrayUnion(projectId) });
    }
    res.status(200).json({ success: true, projectId, strategicObjectiveId: strategicObjectiveId !== null && strategicObjectiveId !== void 0 ? strategicObjectiveId : null });
});
// ── markPlanItemDone ─────────────────────────────────────────────────────────
//
// POST https://markplanitemdone-dzos75b65q-uc.a.run.app
// Headers: Authorization: Bearer <widget_token>
// Body: { uid, planItemId, done }
// Utilisé par le widget iOS interactif pour cocher/décocher une action sans ouvrir l'app.
exports.markPlanItemDone = (0, https_1.onRequest)({ cors: true, invoker: "public" }, async (req, res) => {
    var _a;
    if (req.method === "OPTIONS") {
        res.status(204).send("");
        return;
    }
    if (req.method !== "POST") {
        res.status(405).json({ error: "Method Not Allowed" });
        return;
    }
    const authHeader = (_a = req.headers.authorization) !== null && _a !== void 0 ? _a : "";
    if (!authHeader.startsWith("Bearer ")) {
        res.status(401).json({ error: "Missing Authorization header" });
        return;
    }
    const rawToken = authHeader.slice(7).trim();
    const { uid, planItemId, done } = req.body;
    if (!uid || !planItemId || typeof done !== "boolean") {
        res.status(400).json({ error: "Missing required fields: uid, planItemId, done" });
        return;
    }
    const tokenQuery = await db_1.db
        .collection(`users/${uid}/api_tokens`)
        .where("token", "==", rawToken)
        .where("active", "==", true)
        .limit(1)
        .get();
    if (tokenQuery.empty) {
        res.status(401).json({ error: "Invalid or revoked token" });
        return;
    }
    tokenQuery.docs[0].ref.update({ lastUsedAt: db_1.FieldValue.serverTimestamp() });
    const ref = db_1.db.collection(`users/${uid}/dayPlan`).doc(planItemId);
    const snap = await ref.get();
    if (!snap.exists) {
        res.status(404).json({ error: "Plan item not found" });
        return;
    }
    await ref.update({ done, updatedAt: db_1.FieldValue.serverTimestamp() });
    res.status(200).json({ ok: true });
});
// ── pushAssistantMessage ──────────────────────────────────────────────────────
//
// POST https://us-central1-productivitwo-app.cloudfunctions.net/pushAssistantMessage
exports.pushAssistantMessage = (0, https_1.onRequest)({ cors: true, invoker: "public" }, async (req, res) => {
    var _a, _b;
    if (req.method === "OPTIONS") {
        res.status(204).send("");
        return;
    }
    if (req.method !== "POST") {
        res.status(405).json({ error: "Method Not Allowed" });
        return;
    }
    const authHeader = (_a = req.headers.authorization) !== null && _a !== void 0 ? _a : "";
    if (!authHeader.startsWith("Bearer ")) {
        res.status(401).json({ error: "Missing Authorization header" });
        return;
    }
    const rawToken = authHeader.slice(7).trim();
    const body = req.body;
    if (!body.uid || !body.targetDate || !body.text || !body.condition) {
        res.status(400).json({ error: "Missing required fields: uid, targetDate, text, condition" });
        return;
    }
    const valid = await (0, execute_1.validateToken)(body.uid, rawToken);
    if (!valid) {
        res.status(401).json({ error: "Invalid or revoked token" });
        return;
    }
    const result = await (0, execute_1.executePushAssistantMessage)(body.uid, body);
    const messageId = (_b = result.match(/messageId : (.+)$/m)) === null || _b === void 0 ? void 0 : _b[1];
    res.status(200).json({ success: true, messageId });
});
// ── getCustomToken ────────────────────────────────────────────────────────────
//
// POST { uid, token } — retourne un Firebase custom token pour cet UID.
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
    const valid = await (0, execute_1.validateToken)(uid, token);
    if (!valid) {
        res.status(401).json({ error: "Token invalide ou révoqué" });
        return;
    }
    const customToken = await admin.auth().createCustomToken(uid);
    res.status(200).json({ customToken });
});
// ── mcpHandler ────────────────────────────────────────────────────────────────
//
// URL : /mcp/{uid}/{token} — protocole MCP JSON-RPC 2.0 (Streamable HTTP, stateless)
exports.mcpHandler = (0, https_1.onRequest)({ cors: true, invoker: "public" }, async (req, res) => {
    var _a, _b, _c, _d, _e, _f, _g, _h, _j, _k, _l, _m, _o, _p, _q, _r, _s;
    if (req.method === "OPTIONS") {
        res.status(204).send("");
        return;
    }
    const parts = (req.path || "").replace(/^\/+mcp\/*/, "").split("/");
    const uid = parts[0] || "";
    const token = parts[1] || "";
    if (!uid || !token) {
        res.status(401).json({ error: "URL invalide — format attendu : /mcp/{uid}/{token}" });
        return;
    }
    const valid = await (0, execute_1.validateToken)(uid, token);
    if (!valid) {
        res.status(401).json({ error: "Token invalide ou révoqué" });
        return;
    }
    const body = req.body;
    const requests = Array.isArray(body) ? body : [body];
    const responses = [];
    for (const rpc of requests) {
        const id = (_a = rpc.id) !== null && _a !== void 0 ? _a : null;
        const method = (_b = rpc.method) !== null && _b !== void 0 ? _b : "";
        if (id === null && method.startsWith("notifications/"))
            continue;
        if (method === "initialize") {
            responses.push({
                jsonrpc: "2.0", id,
                result: {
                    protocolVersion: "2024-11-05",
                    capabilities: { tools: {}, prompts: {} },
                    serverInfo: { name: "productivitwo", version: "1.0.0" },
                },
            });
        }
        else if (method === "ping") {
            responses.push({ jsonrpc: "2.0", id, result: {} });
        }
        else if (method === "prompts/list") {
            responses.push({ jsonrpc: "2.0", id, result: { prompts: prompts_1.MCP_PROMPTS } });
        }
        else if (method === "prompts/get") {
            const promptName = (_d = (_c = rpc.params) === null || _c === void 0 ? void 0 : _c.name) !== null && _d !== void 0 ? _d : "";
            const promptArgs = (_f = (_e = rpc.params) === null || _e === void 0 ? void 0 : _e.arguments) !== null && _f !== void 0 ? _f : {};
            const prompt = prompts_1.MCP_PROMPTS.find((p) => p.name === promptName);
            if (!prompt) {
                responses.push({ jsonrpc: "2.0", id, error: { code: -32601, message: `Prompt inconnu : ${promptName}` } });
            }
            else {
                responses.push({
                    jsonrpc: "2.0", id,
                    result: { description: prompt.description, messages: (0, prompts_1.getPromptMessages)(promptName, promptArgs) },
                });
            }
        }
        else if (method === "tools/list") {
            responses.push({
                jsonrpc: "2.0", id,
                result: {
                    tools: [
                        tools_1.GET_USER_CONTEXT_TOOL, tools_1.GET_DAY_BLOCKS_TOOL,
                        tools_1.LIST_PROJECTS_TOOL, tools_1.GET_PROJECT_TOOL, tools_1.PUSH_GANTT_MCP_TOOL,
                        tools_1.ARCHIVE_PROJECT_TOOL, tools_1.DELETE_PROJECT_TOOL, tools_1.UPDATE_ACTIVITY_GOAL_TOOL,
                        tools_1.CREATE_ROUTINE_TOOL, tools_1.DELETE_ROUTINE_TOOL,
                        tools_1.DELETE_GOAL_TOOL, tools_1.LINK_GOAL_TO_TASK_TOOL,
                        tools_1.CREATE_ACTIVITY_TOOL, tools_1.UPDATE_ACTIVITY_TOOL, tools_1.UPDATE_TASK_STATUS_TOOL,
                        tools_1.UPDATE_PROJECT_TOOL, tools_1.DELETE_ACTIVITY_TOOL,
                        tools_1.GET_DOCUMENT_TEMPLATE_TOOL, tools_1.SAVE_DOCUMENT_TOOL, tools_1.GET_DOCUMENTS_TOOL,
                        tools_1.DELETE_DOCUMENT_TOOL, tools_1.GET_ARCHIVES_TOOL, tools_1.RESTORE_ITEM_TOOL,
                        tools_1.CREATE_DOMAIN_TOOL, tools_1.DELETE_DOMAIN_TOOL, tools_1.PUSH_ASSISTANT_MESSAGE_TOOL,
                        tools_1.GET_ASSISTANT_MESSAGES_TOOL, tools_1.DELETE_ASSISTANT_MESSAGE_TOOL,
                        tools_1.GET_DAY_SCHEDULE_TOOL, tools_1.SCHEDULE_DAY_TOOL,
                        tools_1.PLAN_DAY_TOOL, tools_1.PLAN_WEEK_TOOL, tools_1.SYNC_CALENDAR_TOOL,
                        tools_1.ADD_TASK_TOOL, tools_1.UPDATE_TASK_TOOL,
                    ],
                },
            });
        }
        else if (method === "tools/call") {
            const toolName = (_h = (_g = rpc.params) === null || _g === void 0 ? void 0 : _g.name) !== null && _h !== void 0 ? _h : "";
            const args = (_k = (_j = rpc.params) === null || _j === void 0 ? void 0 : _j.arguments) !== null && _k !== void 0 ? _k : {};
            try {
                let text = "";
                if (toolName === "get_user_context") {
                    text = await (0, execute_1.executeGetUserContext)(uid);
                }
                else if (toolName === "get_day_blocks") {
                    text = await (0, execute_1.executeGetDayBlocks)(uid);
                }
                else if (toolName === "list_projects") {
                    text = await (0, execute_1.executeListProjects)(uid);
                }
                else if (toolName === "get_project") {
                    text = await (0, execute_1.executeGetProject)(uid, args.projectId);
                }
                else if (toolName === "push_gantt") {
                    text = await (0, execute_1.executePushGantt)(uid, Object.assign({ uid }, args));
                }
                else if (toolName === "update_project") {
                    text = await (0, execute_1.executeUpdateProject)(uid, args.projectId, args);
                }
                else if (toolName === "update_task_status") {
                    text = await (0, execute_1.executeUpdateTaskStatus)(uid, args.projectId, args.taskId, args.status);
                }
                else if (toolName === "archive_project") {
                    text = await (0, execute_1.executeArchiveProject)(uid, args.projectId, (_l = args.restore) !== null && _l !== void 0 ? _l : false);
                }
                else if (toolName === "delete_project") {
                    text = await (0, execute_1.executeDeleteProject)(uid, args.projectId, (_m = args.deleteObjective) !== null && _m !== void 0 ? _m : false);
                }
                else if (toolName === "create_activity") {
                    text = await (0, execute_1.executeCreateActivity)(uid, args);
                }
                else if (toolName === "update_activity") {
                    text = await (0, execute_1.executeUpdateActivity)(uid, args.activityId, args);
                }
                else if (toolName === "update_activity_goal") {
                    text = await (0, execute_1.executeUpdateActivityGoal)(uid, args.activityId, args);
                }
                else if (toolName === "delete_activity") {
                    text = await (0, execute_1.executeDeleteActivity)(uid, args.activityId);
                }
                else if (toolName === "create_routine") {
                    text = await (0, execute_1.executeCreateRoutine)(uid, args);
                }
                else if (toolName === "delete_routine") {
                    text = await (0, execute_1.executeDeleteRoutine)(uid, args.routineId);
                }
                else if (toolName === "create_domain") {
                    text = await (0, execute_1.executeCreateDomain)(uid, args);
                }
                else if (toolName === "delete_domain") {
                    text = await (0, execute_1.executeDeleteDomain)(uid, args.domainId);
                }
                else if (toolName === "link_goal_to_task") {
                    text = await (0, execute_1.executeLinkGoalToTask)(uid, args.goalId, (_o = args.projectId) !== null && _o !== void 0 ? _o : null, (_p = args.projectTaskId) !== null && _p !== void 0 ? _p : null);
                }
                else if (toolName === "delete_goal") {
                    text = await (0, execute_1.executeDeleteGoal)(uid, args.goalId, (_q = args.action) !== null && _q !== void 0 ? _q : "archive");
                }
                else if (toolName === "get_document_template") {
                    text = (0, prompts_1.executeGetDocumentTemplate)();
                }
                else if (toolName === "save_document") {
                    text = await (0, execute_1.executeSaveDocument)(uid, args);
                }
                else if (toolName === "get_documents") {
                    text = await (0, execute_1.executeGetDocuments)(uid, args.projectId, args.taskId);
                }
                else if (toolName === "delete_document") {
                    const ref = db_1.db.collection(`users/${uid}/documents`).doc(args.documentId);
                    const snap = await ref.get();
                    if (!snap.exists) {
                        text = `Document introuvable : ${args.documentId}`;
                    }
                    else {
                        const title = (_s = (_r = snap.data()) === null || _r === void 0 ? void 0 : _r.title) !== null && _s !== void 0 ? _s : args.documentId;
                        await ref.delete();
                        text = `✅ Document "${title}" supprimé.`;
                    }
                }
                else if (toolName === "get_archives") {
                    text = await (0, execute_1.executeGetArchives)(uid);
                }
                else if (toolName === "restore_item") {
                    text = await (0, execute_1.executeRestoreItem)(uid, args.collection, args.itemId);
                }
                else if (toolName === "push_assistant_message") {
                    text = await (0, execute_1.executePushAssistantMessage)(uid, args);
                }
                else if (toolName === "get_assistant_messages") {
                    text = await (0, execute_1.executeGetAssistantMessages)(uid);
                }
                else if (toolName === "delete_assistant_message") {
                    text = await (0, execute_1.executeDeleteAssistantMessage)(uid, args.messageId);
                }
                else if (toolName === "get_day_schedule") {
                    text = await (0, execute_1.executeGetDaySchedule)(uid, args.date);
                }
                else if (toolName === "schedule_day") {
                    text = await (0, execute_1.executeScheduleDay)(uid, args.date, args.blocks);
                }
                else if (toolName === "plan_day") {
                    text = await (0, execute_1.executePlanDay)(uid, args);
                }
                else if (toolName === "plan_week") {
                    text = await (0, execute_1.executePlanWeek)(uid, args);
                }
                else if (toolName === "sync_calendar") {
                    text = await (0, execute_1.executeSyncCalendar)(uid, args.date);
                }
                else if (toolName === "add_task") {
                    text = await (0, execute_1.executeAddTask)(uid, args.projectId, args);
                }
                else if (toolName === "update_task") {
                    text = await (0, execute_1.executeUpdateTask)(uid, args.projectId, args.taskId, args);
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
// ── orionWebhook ──────────────────────────────────────────────────────────────
//
// POST https://orionwebhook-dzos75b65q-uc.a.run.app
// Body: { uid, token }
// Déclenché par l'app sur actions clés (save config, tâche validée, réponse user)
exports.orionWebhook = (0, https_1.onRequest)({ cors: true, invoker: "public", secrets: ["ANTHROPIC_API_KEY"] }, async (req, res) => {
    if (req.method === "OPTIONS") {
        res.status(204).send("");
        return;
    }
    if (req.method !== "POST") {
        res.status(405).json({ error: "Method Not Allowed" });
        return;
    }
    const { uid, token, taskId } = req.body;
    if (!uid || !token) {
        res.status(400).json({ error: "uid et token requis" });
        return;
    }
    const valid = await (0, execute_1.validateToken)(uid, token);
    if (!valid) {
        res.status(401).json({ error: "Token invalide ou révoqué" });
        return;
    }
    try {
        if (taskId) {
            // Tâche déterministe — pas d'appel LLM, coût $0
            const result = await (0, orion_tasks_1.runDeterministicTask)(uid, taskId);
            await (0, orion_1.writeCycleLog)(uid, Object.assign(Object.assign({ userNeeds: `[déterministe] ${taskId}`, userReply: "" }, result), { skipped: result.skipped }));
            res.status(200).json(Object.assign({ success: true }, result));
        }
        else {
            const result = await (0, orion_1.runOrionCycle)(uid);
            res.status(200).json(Object.assign({ success: true }, result));
        }
    }
    catch (e) {
        const msg = e instanceof Error ? e.message : String(e);
        console.error(`ORION webhook erreur uid=${uid}:`, msg);
        res.status(500).json({ error: msg });
    }
});
// ── orionSaveConfig ───────────────────────────────────────────────────────────
//
// POST { uid, token, userNeeds?, userReply? }
// Sauvegarde la config ORION puis déclenche un cycle.
exports.orionSaveConfig = (0, https_1.onRequest)({ cors: true, invoker: "public", secrets: ["ANTHROPIC_API_KEY"] }, async (req, res) => {
    if (req.method === "OPTIONS") {
        res.status(204).send("");
        return;
    }
    if (req.method !== "POST") {
        res.status(405).json({ error: "Method Not Allowed" });
        return;
    }
    const { uid, token, userNeeds, userReply, isOnboarding } = req.body;
    if (!uid || !token) {
        res.status(400).json({ error: "uid et token requis" });
        return;
    }
    const valid = await (0, execute_1.validateToken)(uid, token);
    if (!valid) {
        res.status(401).json({ error: "Token invalide ou révoqué" });
        return;
    }
    await (0, orion_1.saveOrionConfig)(uid, { userNeeds, userReply });
    try {
        const result = await (0, orion_1.runOrionCycle)(uid, { skipCount: isOnboarding === true });
        res.status(200).json(Object.assign({ success: true, configSaved: true }, result));
    }
    catch (e) {
        const msg = e instanceof Error ? e.message : String(e);
        console.error(`ORION saveConfig erreur uid=${uid}:`, msg);
        res.status(500).json({ error: msg });
    }
});
// ── orionRunCount ─────────────────────────────────────────────────────────────
//
// GET ?uid=&token= — retourne le nombre de cycles ORION du jour
exports.orionRunCount = (0, https_1.onRequest)({ cors: true, invoker: "public" }, async (req, res) => {
    var _a, _b;
    if (req.method === "OPTIONS") {
        res.status(204).send("");
        return;
    }
    const uid = (_a = req.query.uid) !== null && _a !== void 0 ? _a : "";
    const token = (_b = req.query.token) !== null && _b !== void 0 ? _b : "";
    if (!uid || !token) {
        res.status(400).json({ error: "uid et token requis" });
        return;
    }
    const valid = await (0, execute_1.validateToken)(uid, token);
    if (!valid) {
        res.status(401).json({ error: "Token invalide ou révoqué" });
        return;
    }
    const today = new Date().toISOString().slice(0, 10);
    const count = await (0, orion_1.getOrionRunCount)(uid, today);
    res.status(200).json({ count, max: 5, date: today });
});
// ── orionCron — toutes les 1h (test) / 6h (prod) ─────────────────────────────
exports.orionCron = (0, scheduler_1.onSchedule)({ schedule: "every 1 hours", timeZone: "Europe/Paris", secrets: ["ANTHROPIC_API_KEY"] }, async () => {
    const uids = await (0, orion_1.getAllActiveUserIds)();
    console.log(`ORION cron : ${uids.length} users actifs`);
    const results = await Promise.allSettled(uids.map((uid) => (0, orion_1.runOrionCycle)(uid)));
    const executed = results.filter((r) => r.status === "fulfilled" && !r.value.skipped).length;
    const skipped = results.length - executed;
    console.log(`ORION cron terminé : ${executed} cycles exécutés, ${skipped} skippés`);
});
// ── structureProject ──────────────────────────────────────────────────────────
//
// POST https://structureproject-dzos75b65q-uc.a.run.app
// Headers: Authorization: Bearer <firebase-id-token>
// Body: { title, domainName?, domainId?, endDate (YYYY-MM-DD), ideas }
//
// Consomme 1 action stratégique ORION. Crée le projet structuré dans Firestore.
const STRUCTURE_MAX_RUNS = 5; // quota journalier dédié création de projets (partagé avec ORION)
exports.structureProject = (0, https_1.onRequest)({ cors: true, invoker: "public", secrets: ["ANTHROPIC_API_KEY"] }, async (req, res) => {
    var _a;
    if (req.method === "OPTIONS") {
        res.status(204).send("");
        return;
    }
    if (req.method !== "POST") {
        res.status(405).json({ error: "Method Not Allowed" });
        return;
    }
    // Auth via Firebase ID token
    const authHeader = (_a = req.headers.authorization) !== null && _a !== void 0 ? _a : "";
    if (!authHeader.startsWith("Bearer ")) {
        res.status(401).json({ error: "Missing Authorization header" });
        return;
    }
    const idToken = authHeader.slice(7).trim();
    let uid;
    try {
        const decoded = await admin.auth().verifyIdToken(idToken);
        uid = decoded.uid;
    }
    catch (_b) {
        res.status(401).json({ error: "Token invalide ou expiré" });
        return;
    }
    const { title, domainName, domainId, endDate, ideas } = req.body;
    if (!title || !endDate || !ideas) {
        res.status(400).json({ error: "Champs requis : title, endDate, ideas" });
        return;
    }
    // Quota journalier
    const today = new Date().toISOString().slice(0, 10);
    const count = await (0, orion_1.getOrionRunCount)(uid, today);
    if (count >= STRUCTURE_MAX_RUNS) {
        res.status(429).json({ error: `Limite journalière atteinte (${count}/${STRUCTURE_MAX_RUNS} actions stratégiques)` });
        return;
    }
    const apiKey = process.env.ANTHROPIC_API_KEY;
    if (!apiKey) {
        res.status(500).json({ error: "ANTHROPIC_API_KEY non configurée" });
        return;
    }
    // Appel Claude
    const client = new sdk_1.default({ apiKey });
    const prompt = `Tu es ORION, l'assistant stratégique de Productivitwo.
L'utilisateur crée un nouveau projet. Transforme ses idées brutes en plan structuré.

Titre : ${title}
${domainName ? `Domaine : ${domainName}` : ""}
Date cible : ${endDate}
Aujourd'hui : ${today}

Idées de l'utilisateur :
${ideas}

Génère un plan réaliste en JSON. Règles :
- 2 à 4 phases couvrant la période ${today} → ${endDate}
- 3 à 6 tâches par phase, formulées en verbe + objet
- 2 à 4 sous-actions par tâche (étapes concrètes et séquentielles, formulées comme des instructions courtes)
- isMilestone: true uniquement pour les livrables ou validations clés
- Toutes les dates entre ${today} et ${endDate}

Retourne UNIQUEMENT ce JSON valide, sans aucun texte autour :
{
  "phases": [
    { "label": "Nom de la phase", "startDate": "YYYY-MM-DD", "endDate": "YYYY-MM-DD" }
  ],
  "tasks": [
    { "title": "Verbe + action concrète", "phaseIndex": 0, "startDate": "YYYY-MM-DD", "endDate": "YYYY-MM-DD", "isMilestone": false, "actions": ["Étape 1", "Étape 2", "Étape 3"] }
  ]
}`;
    const message = await client.messages.create({
        model: models_1.MODELS.HAIKU,
        max_tokens: 2048,
        messages: [{ role: "user", content: prompt }],
    });
    (0, models_1.logTokenUsage)("structure_project", models_1.MODELS.HAIKU, message.usage);
    const raw = message.content[0].text.trim();
    const jsonMatch = raw.match(/\{[\s\S]*\}/);
    if (!jsonMatch) {
        res.status(500).json({ error: "ORION n'a pas retourné de JSON valide" });
        return;
    }
    const structured = JSON.parse(jsonMatch[0]);
    // Construire le projet avec IDs
    const projectId = (0, uuid_1.v4)();
    const phases = structured.phases.map((p) => ({
        id: (0, uuid_1.v4)(),
        label: p.label,
        color: null,
        startDate: p.startDate,
        endDate: p.endDate,
    }));
    const tasks = structured.tasks.map((t) => {
        var _a, _b, _c, _d;
        return ({
            id: (0, uuid_1.v4)(),
            title: t.title,
            description: null,
            phaseId: (_b = (_a = phases[t.phaseIndex]) === null || _a === void 0 ? void 0 : _a.id) !== null && _b !== void 0 ? _b : null,
            groupLabel: null,
            startDate: t.startDate,
            endDate: t.endDate,
            isMilestone: (_c = t.isMilestone) !== null && _c !== void 0 ? _c : false,
            color: null,
            barLabel: null,
            status: "pending",
            recurringActionId: null,
            actions: ((_d = t.actions) !== null && _d !== void 0 ? _d : []).map((a) => ({
                id: (0, uuid_1.v4)(),
                title: a,
                done: false,
                doneAt: null,
                createdAt: new Date().toISOString(),
            })),
        });
    });
    await db_1.db.collection(`users/${uid}/projects`).doc(projectId).set({
        id: projectId,
        title,
        description: null,
        strategicObjectiveId: null,
        domainId: domainId !== null && domainId !== void 0 ? domainId : null,
        startDate: today,
        endDate,
        status: "active",
        phases,
        tasks,
        createdBy: uid,
        sourceType: "orion_mobile",
        createdAt: db_1.FieldValue.serverTimestamp(),
        updatedAt: db_1.FieldValue.serverTimestamp(),
    });
    // Consommer 1 action stratégique
    await (0, orion_1.incrementOrionRunCount)(uid, today);
    res.status(200).json({
        success: true,
        projectId,
        phasesCount: phases.length,
        tasksCount: tasks.length,
    });
});
//# sourceMappingURL=index.js.map