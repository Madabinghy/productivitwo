"use strict";
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
exports.applyFormationProfile = exports.getVisionAccess = exports.generateFormationAccess = exports.adminProductivitwo = exports.onboardingChat = exports.structureProject = exports.orionCron = exports.orionBrief = exports.orionRunCount = exports.orionSaveConfig = exports.githubWebhook = exports.orionWebhook = exports.mcpHandler = exports.getCustomToken = exports.pushAssistantMessage = exports.markPlanItemDone = exports.pushGantt = void 0;
const https_1 = require("firebase-functions/v2/https");
const scheduler_1 = require("firebase-functions/v2/scheduler");
const admin = require("firebase-admin");
const crypto_1 = require("crypto");
const orion_1 = require("./orion");
const orion_brief_1 = require("./orion_brief");
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
    const valid = await (0, execute_1.validateToken)(uid, rawToken);
    if (!valid) {
        res.status(401).json({ error: "Invalid or revoked token" });
        return;
    }
    const rl = await (0, execute_1.checkRateLimit)(uid, "pushGantt", 30);
    if (rl.limited) {
        res.status(429).json({ error: `Rate limit dépassé — réessaie dans ${rl.retryAfterSecs}s` });
        return;
    }
    let pickedProject;
    let pickedSO;
    try {
        pickedProject = (0, execute_1.pickProject)(project);
        if (strategicObjective)
            pickedSO = (0, execute_1.pickStrategicObjective)(strategicObjective);
    }
    catch (e) {
        res.status(400).json({ error: e instanceof Error ? e.message : String(e) });
        return;
    }
    let strategicObjectiveId;
    if (strategicObjective && pickedSO) {
        const objId = strategicObjective.id || (0, uuid_1.v4)();
        strategicObjectiveId = objId;
        await db_1.db.collection(`users/${uid}/strategic_objectives`).doc(objId).set(Object.assign(Object.assign({}, pickedSO), { id: objId, status: "active", updatedAt: db_1.FieldValue.serverTimestamp(), createdAt: db_1.FieldValue.serverTimestamp() }), { merge: true });
    }
    const projectId = project.id || (0, uuid_1.v4)();
    await db_1.db.collection(`users/${uid}/projects`).doc(projectId).set(Object.assign(Object.assign(Object.assign(Object.assign({}, pickedProject), { id: projectId, createdBy: uid, sourceType: "claude_api", status: "active" }), (strategicObjectiveId ? { strategicObjectiveId } : {})), { updatedAt: db_1.FieldValue.serverTimestamp(), createdAt: db_1.FieldValue.serverTimestamp() }), { merge: true });
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
    const valid = await (0, execute_1.validateToken)(uid, rawToken);
    if (!valid) {
        res.status(401).json({ error: "Invalid or revoked token" });
        return;
    }
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
    var _a, _b, _c, _d, _e, _f, _g, _h, _j, _l, _m, _o, _p, _q;
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
                        tools_1.CREATE_ACTIVITY_TOOL, tools_1.UPDATE_ACTIVITY_TOOL, tools_1.UPDATE_TASK_STATUS_TOOL,
                        tools_1.UPDATE_PROJECT_TOOL, tools_1.DELETE_ACTIVITY_TOOL,
                        tools_1.GET_DOCUMENT_TEMPLATE_TOOL, tools_1.SAVE_DOCUMENT_TOOL, tools_1.GET_DOCUMENTS_TOOL,
                        tools_1.DELETE_DOCUMENT_TOOL, tools_1.GET_ARCHIVES_TOOL, tools_1.RESTORE_ITEM_TOOL,
                        tools_1.CREATE_DOMAIN_TOOL, tools_1.DELETE_DOMAIN_TOOL, tools_1.PUSH_ASSISTANT_MESSAGE_TOOL,
                        tools_1.GET_ASSISTANT_MESSAGES_TOOL, tools_1.DELETE_ASSISTANT_MESSAGE_TOOL,
                        tools_1.GET_DAY_SCHEDULE_TOOL, tools_1.SCHEDULE_DAY_TOOL,
                        tools_1.PLAN_DAY_TOOL, tools_1.PLAN_WEEK_TOOL, tools_1.SYNC_CALENDAR_TOOL,
                        tools_1.ADD_TASK_TOOL, tools_1.UPDATE_TASK_TOOL, tools_1.MARK_ACTION_DONE_TOOL,
                    ],
                },
            });
        }
        else if (method === "tools/call") {
            const rl = await (0, execute_1.checkRateLimit)(uid, "mcpToolCall", 100);
            if (rl.limited) {
                responses.push({ jsonrpc: "2.0", id, error: { code: -32000, message: `Rate limit dépassé — réessaie dans ${rl.retryAfterSecs}s` } });
                continue;
            }
            const toolName = (_h = (_g = rpc.params) === null || _g === void 0 ? void 0 : _g.name) !== null && _h !== void 0 ? _h : "";
            const args = (_l = (_j = rpc.params) === null || _j === void 0 ? void 0 : _j.arguments) !== null && _l !== void 0 ? _l : {};
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
                    text = await (0, execute_1.executeArchiveProject)(uid, args.projectId, (_m = args.restore) !== null && _m !== void 0 ? _m : false);
                }
                else if (toolName === "delete_project") {
                    text = await (0, execute_1.executeDeleteProject)(uid, args.projectId, (_o = args.deleteObjective) !== null && _o !== void 0 ? _o : false);
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
                        const title = (_q = (_p = snap.data()) === null || _p === void 0 ? void 0 : _p.title) !== null && _q !== void 0 ? _q : args.documentId;
                        await ref.update({ deleted: true });
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
                else if (toolName === "mark_action_done") {
                    text = await (0, execute_1.executeMarkActionDone)(uid, args.projectId, args.taskId, args.actionId, args.done);
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
// ── githubWebhook — notif push quand une PR est ouverte ─────────────────────
//
// Configuré dans GitHub (repo Settings → Webhooks), content-type application/json,
// event "Pull requests". Vérifie X-Hub-Signature-256 (HMAC du rawBody avec
// GITHUB_WEBHOOK_SECRET), puis pousse une notif FCM au dev (uid = GITHUB_NOTIFY_UID).
function verifyGithubSignature(raw, header, secret) {
    if (!secret || !header.startsWith("sha256="))
        return false;
    const expected = "sha256=" + (0, crypto_1.createHmac)("sha256", secret).update(raw).digest("hex");
    const a = Buffer.from(header);
    const b = Buffer.from(expected);
    return a.length === b.length && (0, crypto_1.timingSafeEqual)(a, b);
}
exports.githubWebhook = (0, https_1.onRequest)({ invoker: "public", secrets: ["GITHUB_WEBHOOK_SECRET"] }, async (req, res) => {
    var _a, _b, _c, _d, _e, _f, _g;
    if (req.method !== "POST") {
        res.status(405).send("Method Not Allowed");
        return;
    }
    const secret = (_a = process.env.GITHUB_WEBHOOK_SECRET) !== null && _a !== void 0 ? _a : "";
    const sig = (_b = req.get("x-hub-signature-256")) !== null && _b !== void 0 ? _b : "";
    const raw = req.rawBody;
    if (!raw || !verifyGithubSignature(raw, sig, secret)) {
        res.status(401).send("Invalid signature");
        return;
    }
    if (req.get("x-github-event") !== "pull_request") {
        res.status(200).send("ignored");
        return;
    }
    const body = req.body;
    if (body.action !== "opened" && body.action !== "ready_for_review") {
        res.status(200).send("ignored");
        return;
    }
    const uid = process.env.GITHUB_NOTIFY_UID;
    if (uid) {
        const num = (_c = body.number) !== null && _c !== void 0 ? _c : 0;
        const title = (_e = (_d = body.pull_request) === null || _d === void 0 ? void 0 : _d.title) !== null && _e !== void 0 ? _e : "";
        const url = (_g = (_f = body.pull_request) === null || _f === void 0 ? void 0 : _f.html_url) !== null && _g !== void 0 ? _g : "";
        await (0, execute_1.sendFcmPush)(uid, `📥 PR #${num} à valider`, title, { type: "github_pr", url });
    }
    res.status(200).send("ok");
});
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
    const today = (0, execute_1.todayInParis)();
    const count = await (0, orion_1.getOrionRunCount)(uid, today);
    res.status(200).json({ count, max: 5, date: today });
});
// ── ORION Brief (v2) ──────────────────────────────────────────────────────────
// Auth via Firebase ID token. Une seule fonction, méthode dans le body :
//   { action: "getBrief" | "setFocus" | "setFeedback", ... }
exports.orionBrief = (0, https_1.onRequest)({ cors: true, invoker: "public", secrets: ["ANTHROPIC_API_KEY"] }, async (req, res) => {
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
    const idToken = authHeader.slice(7).trim();
    let uid;
    try {
        uid = (await admin.auth().verifyIdToken(idToken)).uid;
    }
    catch (_b) {
        res.status(401).json({ error: "Token invalide ou expiré" });
        return;
    }
    const { action, focus, feedback, date, limit } = req.body;
    try {
        if (action === "getFocus") {
            const f = await (0, orion_brief_1.getFocus)(uid);
            res.status(200).json({ focus: f });
            return;
        }
        if (action === "setFocus") {
            const newFocus = (focus !== null && focus !== void 0 ? focus : "").trim();
            if (!newFocus) {
                res.status(400).json({ error: "focus requis" });
                return;
            }
            if (newFocus.length > 280) {
                res.status(400).json({ error: "focus trop long (max 280)" });
                return;
            }
            await (0, orion_brief_1.setFocus)(uid, newFocus);
            res.status(200).json({ success: true, focus: newFocus });
            return;
        }
        if (action === "history") {
            const briefs = await (0, orion_brief_1.listBriefs)(uid, Math.min(limit !== null && limit !== void 0 ? limit : 30, 90));
            res.status(200).json({ briefs });
            return;
        }
        if (action === "setFeedback") {
            if (!date || !feedback) {
                res.status(400).json({ error: "date et feedback requis" });
                return;
            }
            if (feedback !== "useful" && feedback !== "skip") {
                res.status(400).json({ error: "feedback doit être 'useful' ou 'skip'" });
                return;
            }
            await (0, orion_brief_1.setBriefFeedback)(uid, date, feedback);
            res.status(200).json({ success: true });
            return;
        }
        // Default : getBrief
        const brief = await (0, orion_brief_1.getOrCreateBrief)(uid);
        res.status(200).json(brief);
    }
    catch (e) {
        const msg = e instanceof Error ? e.message : String(e);
        if (msg === "FOCUS_NOT_SET") {
            res.status(412).json({ code: "FOCUS_NOT_SET", error: "Définis ton focus du moment d'abord." });
            return;
        }
        console.error("orionBrief error:", msg);
        res.status(500).json({ error: msg });
    }
});
// ── orionCron — DÉSACTIVÉ (remplacé par orionBrief lazy-generation) ──────────
//
// L'ancien cycle ORION (avec les 20 conditions, messages dispersés) est mis en
// sommeil. La nouvelle expérience passe par `orionBrief` qui génère un brief
// quotidien à la demande quand l'utilisateur ouvre l'app.
//
// Le schedule est conservé mais le body retourne early — économise les tokens
// tout en gardant la structure pour rollback éventuel.
exports.orionCron = (0, scheduler_1.onSchedule)({ schedule: "every 24 hours", timeZone: "Europe/Paris", secrets: ["ANTHROPIC_API_KEY"] }, async () => {
    console.log("ORION cron (legacy) : désactivé — remplacé par orionBrief");
    return;
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
    const today = (0, execute_1.todayInParis)();
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
// ── onboardingChat ────────────────────────────────────────────────────────────
//
// POST { token, message, history }
// Conversation multi-tours guidée par Claude pour co-construire la vision de
// vie de l'utilisateur et configurer Productivitwo en temps réel.
const REVISION_SYSTEM_PROMPT = `Tu es Productivitwo Guide en mode révision.

Aujourd'hui : {{TODAY}}

L'utilisateur a déjà fait son onboarding Productivitwo. Voici sa configuration actuelle :

{{CURRENT_CONFIG}}

━━━ TON RÔLE ━━━

Session courte (~20 min, 6-8 échanges). Aider l'utilisateur à faire évoluer sa vision et sa configuration — pas la refaire de zéro.

DÉROULÉ :
1. Ouvre avec UNE seule question : "Depuis ton dernier bilan, qu'est-ce qui a changé dans ta vie ou ta façon de voir les choses ?" — puis écoute vraiment.
2. Reformule les changements clés que tu entends (2-3 phrases max).
3. Propose des ajustements précis et limités : renommer un domaine, ajouter une activité, archiver ce qui n'est plus d'actualité, ajuster un projet Gantt.
4. Valide avec l'utilisateur avant chaque modification.
5. Maximum 3-4 changements par session — ne pas tout refaire, juste ce qui a vraiment bougé.

━━━ POUSSER LA RÉFLEXION (CRITIQUE) ━━━

Si l'utilisateur donne une réponse brève ou vague, NE WRAP PAS — creuse :
- "OK mais concrètement, qu'est-ce qui a bougé dans tes priorités du moment ?"
- "Ton focus principal a-t-il changé depuis le dernier bilan ?"
- "Y a-t-il un domaine que tu négliges et qui mérite plus d'attention ?"
- "Un projet qui a glissé ou pris une autre direction ?"
- "Une activité qui n'est plus pertinente et qu'il faudrait archiver ?"

Tu DOIS pousser au moins 2-3 questions avant d'envisager de clôturer. La valeur de la révision = forcer un vrai recul, pas valider que "tout va bien".

━━━ RÈGLES ABSOLUES ━━━

- NE RECRÉE JAMAIS ce qui existe déjà (vérifie la config ci-dessus)
- NE SUPPRIME / N'ARCHIVE rien sans que l'utilisateur l'ait dit explicitement
- Si un domaine doit être renommé : utilise update_domain
- Si un domaine n'est plus pertinent : utilise archive_domain (après validation)
- Si une nouvelle activité émerge : utilise create_activity liée au bon domaine existant
- Pour un projet existant : utilise update_project ou archive_project (PAS push_gantt qui crée un nouveau)

━━━ CLÔTURE (IMPORTANT) ━━━

Quand l'utilisateur indique qu'il a fait le tour ("c'est bon", "rien d'autre", "ça suffit"), termine par UN message de clôture spécifique à la révision — JAMAIS "ta configuration est prête" (ça c'était l'onboarding).

Modèles selon le cas :
- Si modifications effectuées : "Voilà tes ajustements appliqués : [récap court]. On se revoit pour la prochaine vision dans 30 jours pour faire un nouveau point."
- Si AUCUNE modification : "Pas de changement majeur depuis le dernier bilan — c'est aussi une info précieuse. Ton focus reste solide. On se revoit dans 30 jours."

━━━ STYLE ━━━

- Tutoiement naturel
- Bref — l'utilisateur connaît déjà l'outil
- Focalise sur les changements, pas sur la re-découverte
- NE DEMANDE PAS le prénom ni les informations de base — tu as déjà la config complète ci-dessus
- Commence directement avec ta question d'ouverture, sans introduction ni reformulation de la config`;
const REVISION_TOOLS = [
    {
        name: "update_domain",
        description: "Renomme ou recolore un domaine existant. Utilise le nom actuel du domaine.",
        input_schema: {
            type: "object",
            properties: {
                currentName: { type: "string", description: "Nom actuel exact du domaine" },
                newName: { type: "string", description: "Nouveau nom (si renommage)" },
                color: { type: "string", description: "Nouvelle couleur hex (si changement de couleur)" },
            },
            required: ["currentName"],
        },
    },
    {
        name: "archive_domain",
        description: "Archive (soft-delete) un domaine qui n'est plus pertinent. Uniquement sur demande explicite de l'utilisateur.",
        input_schema: {
            type: "object",
            properties: {
                name: { type: "string", description: "Nom exact du domaine à archiver" },
            },
            required: ["name"],
        },
    },
    {
        name: "create_domain",
        description: "Crée un nouveau domaine de vie (uniquement si vraiment nouveau).",
        input_schema: {
            type: "object",
            properties: {
                name: { type: "string" },
                color: { type: "string", description: "Couleur hex" },
            },
            required: ["name", "color"],
        },
    },
    {
        name: "create_activity",
        description: "Crée une nouvelle activité dans un domaine existant. type 'time' = suivi de durée (goalMin). type 'habit' = suivi de fréquence (habitFreq + habitTarget).",
        input_schema: {
            type: "object",
            properties: {
                name: { type: "string" },
                domainName: { type: "string", description: "Nom exact du domaine existant" },
                type: { type: "string", enum: ["time", "habit"] },
                goalMin: { type: "number", description: "Objectif quotidien en minutes (type time)" },
                habitFreq: { type: "string", enum: ["daily", "weekly", "monthly"], description: "Période de la fréquence (type habit)" },
                habitTarget: { type: "number", description: "Cible par période (type habit) — ex: 3 = 3×/semaine, 8 = 8×/jour, 1 = mensuel" },
                unit: { type: "string", description: "Unité optionnelle (ex: verres, pages, km)" },
            },
            required: ["name", "domainName", "type"],
        },
    },
    {
        name: "update_project",
        description: "Renomme, change le statut ou met à jour les dates d'un projet existant. Utilise l'id retourné dans la config.",
        input_schema: {
            type: "object",
            properties: {
                projectId: { type: "string", description: "id du projet (fourni dans la config injectée)" },
                title: { type: "string", description: "Nouveau titre (optionnel)" },
                description: { type: "string", description: "Nouvelle description (optionnel)" },
                startDate: { type: "string", description: "YYYY-MM-DD (optionnel)" },
                endDate: { type: "string", description: "YYYY-MM-DD (optionnel)" },
                status: { type: "string", enum: ["active", "archived", "completed"], description: "Nouveau statut (optionnel)" },
            },
            required: ["projectId"],
        },
    },
    {
        name: "archive_project",
        description: "Archive un projet (terminé ou abandonné). Soft-delete — récupérable.",
        input_schema: {
            type: "object",
            properties: {
                projectId: { type: "string", description: "id du projet (fourni dans la config injectée)" },
            },
            required: ["projectId"],
        },
    },
    {
        name: "add_task",
        description: "Ajoute une tâche à un projet existant (sans remplacer le projet entier).",
        input_schema: {
            type: "object",
            properties: {
                projectId: { type: "string" },
                title: { type: "string" },
                startDate: { type: "string", description: "YYYY-MM-DD" },
                endDate: { type: "string", description: "YYYY-MM-DD" },
                isMilestone: { type: "boolean" },
                actions: { type: "array", items: { type: "string" } },
            },
            required: ["projectId", "title", "startDate"],
        },
    },
    {
        name: "push_gantt",
        description: "Crée un NOUVEAU projet Gantt (uniquement si un objectif vraiment nouveau a émergé). Pour modifier un projet existant, utilise plutôt update_project.",
        input_schema: {
            type: "object",
            properties: {
                title: { type: "string" },
                startDate: { type: "string" },
                endDate: { type: "string" },
                phases: { type: "array", items: { type: "object", properties: { label: { type: "string" }, startDate: { type: "string" }, endDate: { type: "string" } } } },
                tasks: { type: "array", items: { type: "object", properties: { title: { type: "string" }, phaseIndex: { type: "number" }, startDate: { type: "string" }, endDate: { type: "string" }, isMilestone: { type: "boolean" }, actions: { type: "array", items: { type: "string" } } } } },
            },
            required: ["title", "startDate", "endDate", "phases", "tasks"],
        },
    },
];
const ONBOARDING_SYSTEM_PROMPT = `Tu es Productivitwo Guide — l'assistant d'onboarding personnel de Productivitwo.

Aujourd'hui : {{TODAY}}

{{USER_CONTEXT}}

Ta mission : conduire une conversation chaleureuse mais EFFICACE qui aboutit à un système Productivitwo réellement prêt à l'emploi — l'utilisateur doit pouvoir, dès l'ouverture de l'app, tracker concrètement ce qu'il fait.

Deux livrables comptent autant : (1) qu'il se sente vraiment compris, (2) qu'il reparte avec un VRAI système trackable (domaines + activités calibrées + 1er projet Gantt), pas un échantillon creux. Ces deux objectifs ne s'opposent PAS : garde une vraie conversation exploratoire et chaleureuse — c'est elle qui crée le sentiment d'écoute. Le "trop de blabla pour trop peu" se corrige en Phase 3, où cette écoute se convertit en un système réellement rempli (balayage des activités), PAS en raccourcissant l'exploration.

⚖️ DENSITÉ ADAPTATIVE — calibre-toi sur la personne, jamais sur un quota :
- Jauge son appétit en formulant le choix par la COUVERTURE, jamais par l'effort : "Tu veux qu'on capture TOUT ce que tu fais au quotidien (système complet), ou plutôt l'essentiel — quelques indicateurs clés pour démarrer ?" ⚠️ Ne dis JAMAIS "beaucoup d'activités" / "suivre en détail" : ça suggère à tort qu'il faudra cliquer davantage. Un système complet = il reflète ta vie, pas un surcroît de saisie (on logue seulement ce qu'on fait).
- Capture ce qu'elle fait VRAIMENT — n'invente pas pour remplir, ne plafonne pas un power-user non plus.
- Plafond souple : ~5 activités/domaine pendant l'onboarding (le reste s'ajoute dans l'app). Profil "essentiel" : 1-3 suffisent.
- Rappelle qu'on peut tout enrichir plus tard, à tout moment.

━━━ PHASES ━━━

PHASE 1 — ÉTAT PRÉSENT (4-5 échanges)
Explore la vie actuelle avec curiosité — c'est ce temps d'écoute qui fait que l'utilisateur se sent compris. Tu veux comprendre :
- Ses activités pro et perso au quotidien
- Ce qui lui prend du temps (subi vs choisi)
- Comment il structure (ou ne structure pas) sa semaine
- Ses frustrations d'organisation actuelles
Jauge aussi, au fil de l'échange, son appétit : système complet (capturer tout ce qu'il fait) vs essentiel (quelques indicateurs clés). Formule toujours par la couverture, pas par l'effort.
Pose 1-2 questions ouvertes par message. Écoute vraiment, reformule ce que tu comprends.
Ne passe pas à la Phase 2 tant que tu n'as pas une image claire et nuancée.

PHASE 2 — VISION FUTURE (3-4 échanges)
Explore ce qu'il veut construire dans les 6-12 prochains mois :
- Objectifs concrets (business, vie perso, santé, famille...)
- À quoi ressemblerait sa semaine idéale
- Ce qu'il veut arrêter / commencer / amplifier
Le delta entre Phase 1 et Phase 2 deviendra son premier projet Gantt.

PHASE 3 — STRUCTURATION PAR CATALOGUE DE DOMAINES (1 domaine à la fois)

ANNONCE D'OUVERTURE OBLIGATOIRE — commence la Phase 3 par ce message (adapte le ton, garde le fond) :
"Passons maintenant à la structure. On va explorer tes domaines de vie ensemble — jusqu'à 10 catégories, une par une. Pour chaque espace, je te propose quelques noms, tu choisis celui qui te parle ou tu donnes le tien.

Voici les catégories qu'on va parcourir :
Vie pro · Santé · Sport · Maison · Famille · Relations · Finances · Développement perso · Loisirs · Intériorité

Prends le temps qu'il te faut. Si tu dois t'arrêter, ta session est sauvegardée — tu peux revenir exactement là où on en est. Pour finir quand tu es prêt, dis-moi juste 'stop' ou 'c'est bon'.

On commence ?"

DÉROULÉ pour chaque domaine :
  1. Annonce le domaine, propose 4-5 noms + "Autre" → l'utilisateur choisit/valide.
  2. BALAYAGE DES ACTIVITÉS — c'est ICI qu'on construit le vrai système trackable.
     Demande concrètement ce qu'il fait (ou veut suivre) dans ce domaine, avec les DEUX lentilles :
       • DURÉE (type "time") : ce qu'on mesure en temps — ex: Sport, Stratégie, Cuisiner, Sommeil → goalMin réaliste (souvent 15-30 min).
       • FRÉQUENCE (type "habit") : ce qu'on coche — ex: Boire de l'eau (daily ×8), Footing (weekly ×3), Ménage (weekly), Laver la voiture (monthly) → habitFreq + habitTarget.
     Pour chaque activité, déduis la bonne lentille ; si habit, déduis fréquence + cible. Si une cible est importante et incertaine, demande — ne devine pas.
  3. Vise jusqu'à ~5 activités/domaine selon son appétit — sans remplir artificiellement, sans plafonner un power-user (il complétera dans l'app).
  4. Reformule la courte liste ("Dans X, tu suivras : … — ça te va ?"), puis passe au domaine suivant.

L'utilisateur peut dire "passe" pour sauter un domaine, "stop"/"c'est bon" pour valider et aller en Phase 4.
Maximum 6-7 domaines — propose de fusionner s'il en veut trop.

━━━ RÈGLE CRITIQUE — BESOIN ÉMOTIONNEL vs ACTIVITÉ TRACKABLE ━━━

Quand l'utilisateur exprime un ressenti (solitude, anxiété, manque, désir...) :
→ NE crée PAS automatiquement un domaine ou une activité pour "résoudre" ce ressenti.

Procédure en 3 temps :
  1. Accueille le ressenti simplement ("c'est important ce que tu partages...")
  2. DEMANDE si c'est quelque chose qu'il veut structurer : "Est-ce que tu veux en faire un espace de vie à suivre dans Productivitwo, ou c'est plutôt un désir de fond ?"
  3. Si OUI → creuse : "Qu'est-ce qui te viendrait comme indicateur concret ? Une sortie par semaine ? Du temps pour toi ? Des moments de plaisir ?" L'utilisateur choisit lui-même ce qu'il veut mesurer.
     Si NON → passe à la suite sans créer de domaine pour ce ressenti.

Exemple : "Je me sens seul" → NE PAS créer "Joie & Connexion" avec "Activité : Rencontres".
         → DEMANDER : "Tu as dit que tu veux plus de connexion. Tu veux qu'on en fasse un domaine à suivre, ou c'est un objectif de fond ?"

Un domaine doit répondre à la question : "est-ce que cette personne a des comportements concrets à tracker ici ?" Si la réponse est floue, demande.

━━━ CATALOGUE DES 10 DOMAINES DE VIE ━━━

1. VIE PROFESSIONNELLE
   Question : "Ton activité principale — comment tu gagnes ta vie ?"
   Noms : "Business" | "Travail" | "Vie pro" | "Mission" | Autre

2. SANTÉ & CORPS
   Question : "Ton énergie physique, ta santé — c'est quoi la réalité là ?"
   Noms : "Santé" | "Corps" | "Vitalité" | "Bien-être" | Autre
   (Si peu sportif : propose de fusionner Sport ici)

3. SPORT & MOUVEMENT
   Question : "Tu bouges comment ? Régulier, irrégulier, absent ?"
   Noms : "Sport" | "Mouvement" | "Fitness" | "Énergie physique" | Autre
   (Passe si déjà fusionné avec Santé)

4. MAISON & ENVIRONNEMENT
   Question : "Ton espace de vie — il te ressource ou il te pèse ?"
   Noms : "Maison" | "Foyer" | "Espace de vie" | "Environnement" | Autre

5. FAMILLE & PROCHES
   Question : "Ta famille, tes proches — c'est quoi la dynamique en ce moment ?"
   Noms : "Famille" | "Proches" | "Cercle proche" | "Liens familiaux" | Autre

6. VIE SOCIALE & RELATIONS
   Question : "Tes amis, ton réseau — nourris ou délaissés ?"
   Noms : "Social" | "Relations" | "Vie sociale" | "Amis & Réseau" | Autre

7. FINANCES
   Question : "Ta situation financière — sécurité, tension, ou flou ?"
   Noms : "Finances" | "Argent" | "Gestion financière" | "Patrimoine" | Autre

8. DÉVELOPPEMENT PERSONNEL
   Question : "Tu te formes, tu évolues — ou tu stagnes sur ce plan ?"
   Noms : "Développement" | "Croissance" | "Apprentissage" | "Évolution" | Autre

9. LOISIRS & RESSOURCEMENT
   Question : "Ce qui te fait du bien, te ressource — t'y accèdes comment ?"
   Noms : "Loisirs" | "Plaisirs" | "Ressourcement" | "Fun & Aventures" | Autre

10. INTÉRIORITÉ & MENTAL
    Question : "Ton mental, ta paix intérieure — c'est quoi le bruit de fond ?"
    Noms : "Mental" | "Intériorité" | "Spiritualité" | "Équilibre" | Autre

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

⚠️ NE CRÉE RIEN DANS PRODUCTIVITWO AVANT QUE L'UTILISATEUR DISE "stop", "c'est bon", "go", "parfait" ou équivalent.

PHASE 4 — CRÉATION (automatique après validation)
Une fois la structure validée, crée TOUT dans cet ordre :
1. create_domain pour chaque domaine (couleur cohérente).
2. create_activity pour CHAQUE activité du balayage, liée au bon domaine par nom :
   - type "time" → goalMin réaliste (souvent 15-30 min).
   - type "habit" → TOUJOURS préciser habitFreq (daily/weekly/monthly) ET habitTarget (ex: 3 = 3×/sem, 8 = 8×/jour). Ne mets jamais "daily ×1" par défaut sans raison — reflète ce que la personne a dit.
   (Routines et gestes récurrents = create_activity type "habit". Il n'existe PAS d'outil routine séparé.)
3. push_gantt pour le premier projet :
   - Titre qui reflète le voyage présent→futur de CET utilisateur
   - Phases = étapes de progression vers la vision ; 3-5 tâches/phase (actions concrètes) ; durée 6-9 mois.
4. Message final enthousiaste : annonce que le système est prêt, invite à ouvrir l'app, et précise qu'il pourra ajouter/affiner ses activités à tout moment (lui-même ou via l'assistant).

━━━ STYLE ━━━
- Tutoiement naturel et chaleureux
- Phrases courtes, questions ouvertes
- Reformule avant de proposer (montre que tu as écouté)
- En Phase 3 : utilise une mise en forme claire pour les domaines proposés
- En Phase 4 : sois enthousiaste, c'est le moment fort de l'expérience`;
const ONBOARDING_TOOLS = [
    {
        name: "create_domain",
        description: "Crée un domaine de vie dans Productivitwo. À appeler seulement après validation explicite de la structure par l'utilisateur.",
        input_schema: {
            type: "object",
            properties: {
                name: { type: "string", description: "Nom du domaine (reflète l'identité de l'utilisateur, pas générique)" },
                color: { type: "string", description: "Couleur hex cohérente avec le thème du domaine (ex: #4A90E2)" },
            },
            required: ["name", "color"],
        },
    },
    {
        name: "create_activity",
        description: "Crée une activité de tracking dans un domaine. Utilise le nom du domaine (pas son ID). 'time' = suivi de durée ; 'habit' = suivi de fréquence (routines, gestes quotidiens/hebdo/mensuels).",
        input_schema: {
            type: "object",
            properties: {
                name: { type: "string", description: "Nom de l'activité" },
                domainName: { type: "string", description: "Nom exact du domaine dans lequel créer l'activité" },
                type: { type: "string", enum: ["time", "habit"], description: "time = tracking durée, habit = tracking fréquence" },
                goalMin: { type: "number", description: "Objectif quotidien en minutes (type time)" },
                habitFreq: { type: "string", enum: ["daily", "weekly", "monthly"], description: "Période de la fréquence (type habit) — quotidien / hebdo / mensuel" },
                habitTarget: { type: "number", description: "Cible par période (type habit) — ex: 3 = 3×/semaine, 8 = 8×/jour, 1 = 1×/mois" },
                unit: { type: "string", description: "Unité optionnelle (ex: verres, pages, km)" },
            },
            required: ["name", "domainName", "type"],
        },
    },
    {
        name: "push_gantt",
        description: "Crée le premier projet Gantt représentant la progression état présent → vision future.",
        input_schema: {
            type: "object",
            properties: {
                title: { type: "string", description: "Titre du projet (personnalisé, pas générique)" },
                startDate: { type: "string", description: "YYYY-MM-DD (aujourd'hui)" },
                endDate: { type: "string", description: "YYYY-MM-DD (6-9 mois)" },
                phases: {
                    type: "array",
                    items: {
                        type: "object",
                        properties: {
                            label: { type: "string" },
                            startDate: { type: "string" },
                            endDate: { type: "string" },
                        },
                    },
                },
                tasks: {
                    type: "array",
                    items: {
                        type: "object",
                        properties: {
                            title: { type: "string" },
                            phaseIndex: { type: "number" },
                            startDate: { type: "string" },
                            endDate: { type: "string" },
                            isMilestone: { type: "boolean" },
                            actions: { type: "array", items: { type: "string" } },
                        },
                    },
                },
            },
            required: ["title", "startDate", "endDate", "phases", "tasks"],
        },
    },
];
async function executeOnboardingTool(uid, toolName, input, domainMap) {
    var _a, _b, _c, _d, _e, _f, _g, _h, _j, _l, _m, _o, _p, _q, _r, _s, _t;
    if (toolName === "create_domain") {
        const id = (0, uuid_1.v4)();
        const name = input.name;
        const colorVal = input.color ? hexToColorValue(input.color) : null;
        await db_1.db.collection(`users/${uid}/domains`).doc(id).set({
            id, name,
            goalMinDay: null, autoGoal: true,
            colorValue: colorVal,
            createdAt: db_1.FieldValue.serverTimestamp(),
        });
        domainMap[name] = id;
        return { notification: `✓ Domaine "${name}" créé`, output: `Domaine créé — id: ${id}` };
    }
    if (toolName === "create_activity") {
        const id = (0, uuid_1.v4)();
        const name = input.name;
        const domainName = input.domainName;
        const domainId = (_a = domainMap[domainName]) !== null && _a !== void 0 ? _a : null;
        const isHabit = input.type === "habit";
        const freqMap = { daily: 0, weekly: 1, monthly: 2 };
        const freqKey = (_b = input.habitFreq) !== null && _b !== void 0 ? _b : "daily";
        const habitFreq = isHabit ? ((_c = freqMap[freqKey]) !== null && _c !== void 0 ? _c : 0) : null;
        const habitTarget = isHabit ? ((_d = input.habitTarget) !== null && _d !== void 0 ? _d : 1) : null;
        // Si le guide a précisé fréquence/cible, on fige la cible (pas d'auto-tune qui l'écrase).
        const manualHabit = isHabit && (input.habitFreq !== undefined || input.habitTarget !== undefined);
        await db_1.db.collection(`users/${uid}/activities`).doc(id).set({
            id, name, domainId,
            type: isHabit ? "habit" : "time",
            role: "generic",
            goalMin: (_e = input.goalMin) !== null && _e !== void 0 ? _e : 1,
            unit: (_f = input.unit) !== null && _f !== void 0 ? _f : null,
            habitFreq,
            habitTarget,
            manualTarget: manualHabit,
            autoTune: !manualHabit,
            createdAt: db_1.FieldValue.serverTimestamp(),
            lastTuneAt: null, order: 0, iconCode: null, deleted: false,
        });
        const detail = isHabit ? ` (${freqKey} ×${habitTarget})` : (input.goalMin ? ` (${input.goalMin}min/j)` : "");
        return { notification: `✓ Activité "${name}"${detail} créée`, output: `Activité créée — id: ${id}` };
    }
    if (toolName === "create_routine") {
        const id = (0, uuid_1.v4)();
        const name = input.name;
        const domainName = input.domainName;
        const domainId = (_g = domainMap[domainName]) !== null && _g !== void 0 ? _g : ((_h = Object.values(domainMap)[0]) !== null && _h !== void 0 ? _h : null);
        await db_1.db.collection(`users/${uid}/activities`).doc(id).set({
            id, name, domainId,
            type: "habit", role: "generic",
            goalMin: (_j = input.dureeMin) !== null && _j !== void 0 ? _j : 15,
            unit: null, habitFreq: 0, habitTarget: 1,
            manualTarget: false, autoTune: false,
            createdAt: db_1.FieldValue.serverTimestamp(),
            lastTuneAt: null, order: 0, iconCode: null, deleted: false,
        });
        return { notification: `✓ Routine "${name}" créée`, output: `Routine créée — id: ${id}` };
    }
    if (toolName === "push_gantt") {
        const projectId = (0, uuid_1.v4)();
        const ganttInput = input;
        const phases = ganttInput.phases.map((p) => ({ id: (0, uuid_1.v4)(), label: p.label, color: null, startDate: p.startDate, endDate: p.endDate }));
        const tasks = ganttInput.tasks.map((t) => {
            var _a, _b, _c, _d;
            return ({
                id: (0, uuid_1.v4)(), title: t.title,
                phaseId: (_b = (_a = phases[t.phaseIndex]) === null || _a === void 0 ? void 0 : _a.id) !== null && _b !== void 0 ? _b : null,
                groupLabel: null, description: null,
                startDate: t.startDate, endDate: t.endDate,
                isMilestone: (_c = t.isMilestone) !== null && _c !== void 0 ? _c : false,
                color: null, barLabel: null, status: "pending",
                recurringActionId: null,
                actions: ((_d = t.actions) !== null && _d !== void 0 ? _d : []).map((a) => ({ id: (0, uuid_1.v4)(), title: a, done: false, doneAt: null, createdAt: new Date().toISOString() })),
            });
        });
        await db_1.db.collection(`users/${uid}/projects`).doc(projectId).set({
            id: projectId, title: ganttInput.title,
            description: null, strategicObjectiveId: null, domainId: null,
            startDate: ganttInput.startDate, endDate: ganttInput.endDate,
            status: "active", phases, tasks,
            createdBy: uid, sourceType: "formation_onboarding",
            createdAt: db_1.FieldValue.serverTimestamp(), updatedAt: db_1.FieldValue.serverTimestamp(),
        });
        return { notification: `✓ Projet Gantt "${ganttInput.title}" créé`, output: `Projet créé — id: ${projectId}` };
    }
    if (toolName === "update_domain") {
        const currentName = input.currentName;
        const newName = input.newName;
        const newColor = input.color;
        const domainId = domainMap[currentName];
        if (!domainId)
            return { notification: `Domaine "${currentName}" introuvable`, output: `Erreur: "${currentName}" pas dans le domainMap` };
        const updates = {};
        if (newName)
            updates.name = newName;
        if (newColor)
            updates.colorValue = hexToColorValue(newColor);
        if (Object.keys(updates).length > 0) {
            await db_1.db.collection(`users/${uid}/domains`).doc(domainId).update(updates);
        }
        if (newName) {
            domainMap[newName] = domainId;
            delete domainMap[currentName];
        }
        const label = newName ? `"${currentName}" → "${newName}"` : `"${currentName}"`;
        return { notification: `✓ Domaine ${label} mis à jour`, output: `Domaine mis à jour — id: ${domainId}` };
    }
    if (toolName === "archive_domain") {
        const name = input.name;
        const domainId = domainMap[name];
        if (!domainId)
            return { notification: `Domaine "${name}" introuvable`, output: "Erreur" };
        await db_1.db.collection(`users/${uid}/domains`).doc(domainId).update({ deleted: true });
        delete domainMap[name];
        return { notification: `✓ Domaine "${name}" archivé`, output: `Archivé — id: ${domainId}` };
    }
    if (toolName === "update_project") {
        const projectId = input.projectId;
        const ref = db_1.db.collection(`users/${uid}/projects`).doc(projectId);
        const snap = await ref.get();
        if (!snap.exists)
            return { notification: `Projet introuvable`, output: `Erreur: projet ${projectId} non trouvé` };
        const updates = { updatedAt: db_1.FieldValue.serverTimestamp() };
        if (input.title)
            updates.title = input.title;
        if (input.description)
            updates.description = input.description;
        if (input.startDate)
            updates.startDate = input.startDate;
        if (input.endDate)
            updates.endDate = input.endDate;
        if (input.status)
            updates.status = input.status;
        await ref.update(updates);
        const newTitle = (_o = (_l = input.title) !== null && _l !== void 0 ? _l : (_m = snap.data()) === null || _m === void 0 ? void 0 : _m.title) !== null && _o !== void 0 ? _o : projectId;
        return { notification: `✓ Projet "${newTitle}" mis à jour`, output: `Projet mis à jour` };
    }
    if (toolName === "archive_project") {
        const projectId = input.projectId;
        const ref = db_1.db.collection(`users/${uid}/projects`).doc(projectId);
        const snap = await ref.get();
        if (!snap.exists)
            return { notification: `Projet introuvable`, output: `Erreur` };
        const title = (_q = (_p = snap.data()) === null || _p === void 0 ? void 0 : _p.title) !== null && _q !== void 0 ? _q : projectId;
        await ref.update({ status: "archived", updatedAt: db_1.FieldValue.serverTimestamp() });
        return { notification: `✓ Projet "${title}" archivé`, output: `Archivé` };
    }
    if (toolName === "add_task") {
        const projectId = input.projectId;
        const ref = db_1.db.collection(`users/${uid}/projects`).doc(projectId);
        const snap = await ref.get();
        if (!snap.exists)
            return { notification: `Projet introuvable`, output: `Erreur` };
        const newTask = {
            id: (0, uuid_1.v4)(),
            title: input.title,
            description: null,
            phaseId: null,
            groupLabel: null,
            startDate: input.startDate,
            endDate: (_r = input.endDate) !== null && _r !== void 0 ? _r : null,
            isMilestone: (_s = input.isMilestone) !== null && _s !== void 0 ? _s : false,
            color: null,
            barLabel: null,
            status: "pending",
            recurringActionId: null,
            actions: ((_t = input.actions) !== null && _t !== void 0 ? _t : []).map((a) => ({
                id: (0, uuid_1.v4)(), title: a, done: false, doneAt: null, createdAt: new Date().toISOString(),
            })),
        };
        await ref.update({
            tasks: db_1.FieldValue.arrayUnion(newTask),
            updatedAt: db_1.FieldValue.serverTimestamp(),
        });
        return { notification: `✓ Tâche "${newTask.title}" ajoutée`, output: `Tâche créée — id: ${newTask.id}` };
    }
    return { notification: "", output: `Outil inconnu : ${toolName}` };
}
exports.onboardingChat = (0, https_1.onRequest)({ cors: true, invoker: "public", secrets: ["FORMATION_JWT_SECRET", "ANTHROPIC_API_KEY"] }, async (req, res) => {
    var _a, _b, _c, _d, _e, _f;
    if (req.method === "OPTIONS") {
        res.status(204).send("");
        return;
    }
    if (req.method !== "POST") {
        res.status(405).json({ error: "Method Not Allowed" });
        return;
    }
    const { token, message, history, userContext, action } = req.body;
    if (!token) {
        res.status(400).json({ error: "token requis" });
        return;
    }
    const decoded = verifyFormationToken(token, process.env.FORMATION_JWT_SECRET);
    if (!decoded) {
        res.status(401).json({ error: "Token invalide ou expiré" });
        return;
    }
    const { uid } = decoded;
    // ── Vérification statut onboarding ────────────────────────────────────────
    // Toujours chargé — sert pour checkSession, chat ET révision
    const accessDoc = await db_1.db.collection("formation_access").doc(uid).get();
    const accessData = (_a = accessDoc.data()) !== null && _a !== void 0 ? _a : {};
    const onboardingDone = accessData.onboardingDone === true;
    const isPro = accessData.isPro === true; // positionné via RevenueCat webhook (TODO)
    // ── Actions hors-chat ─────────────────────────────────────────────────────
    if (action === "checkSession") {
        const snap = await db_1.db.collection("formation_sessions").doc(uid).get();
        const base = { onboardingDone, isPro };
        if (!snap.exists) {
            res.status(200).json(Object.assign(Object.assign({}, base), { hasSession: false }));
            return;
        }
        const data = snap.data();
        const savedAt = (_b = data.savedAt) === null || _b === void 0 ? void 0 : _b.toDate();
        const ageMs = savedAt ? Date.now() - savedAt.getTime() : Infinity;
        if (ageMs > 7 * 24 * 60 * 60 * 1000) {
            res.status(200).json(Object.assign(Object.assign({}, base), { hasSession: false }));
            return;
        }
        res.status(200).json(Object.assign(Object.assign({}, base), { hasSession: true, mode: (_c = data.mode) !== null && _c !== void 0 ? _c : "onboarding", history: (_d = data.history) !== null && _d !== void 0 ? _d : [], userContext: (_e = data.userContext) !== null && _e !== void 0 ? _e : null, turnCount: (_f = data.turnCount) !== null && _f !== void 0 ? _f : 0, savedAt: savedAt === null || savedAt === void 0 ? void 0 : savedAt.toISOString() }));
        return;
    }
    if (action === "clearSession") {
        await db_1.db.collection("formation_sessions").doc(uid).delete();
        res.status(200).json({ cleared: true });
        return;
    }
    // ── Révision ──────────────────────────────────────────────────────────────
    if (action === "startRevision" || action === "revision_chat") {
        if (!isPro) {
            res.status(403).json({ code: "REVISION_PRO_REQUIRED" });
            return;
        }
        // Marque le début d'une nouvelle vision — déclenche le countdown 30j
        if (action === "startRevision") {
            await db_1.db.collection("formation_access").doc(uid).set({ lastVisionAt: db_1.FieldValue.serverTimestamp() }, { merge: true });
        }
        const apiKey2 = process.env.ANTHROPIC_API_KEY;
        if (!apiKey2) {
            res.status(500).json({ error: "ANTHROPIC_API_KEY manquante" });
            return;
        }
        const client2 = new sdk_1.default({ apiKey: apiKey2 });
        const today2 = (0, execute_1.todayInParis)();
        // Lecture config existante (pour startRevision ou premier tour)
        const [domainsSnap, activitiesSnap, projectsSnap] = await Promise.all([
            db_1.db.collection(`users/${uid}/domains`).get(),
            db_1.db.collection(`users/${uid}/activities`).get(),
            db_1.db.collection(`users/${uid}/projects`).where("status", "==", "active").get(),
        ]);
        // Construction par domaine pour que Claude voie bien les liens
        const liveDomains = domainsSnap.docs.filter(d => !d.data().deleted);
        const liveActivities = activitiesSnap.docs.filter(d => !d.data().deleted);
        const domainSections = [];
        for (const dom of liveDomains) {
            const dData = dom.data();
            const acts = liveActivities
                .filter(a => a.data().domainId === dom.id)
                .map(a => {
                const aData = a.data();
                const isHabit = aData.type === "habit";
                return `    · ${aData.name} (${isHabit ? "routine/habit" : "tracking temps"})`;
            });
            domainSections.push(`  · ${dData.name}\n${acts.length ? acts.join("\n") : "    (aucune activité)"}`);
        }
        // Activités orphelines (sans domaine ou domaine supprimé)
        const orphanActs = liveActivities
            .filter(a => !liveDomains.some(d => d.id === a.data().domainId))
            .map(a => `    · ${a.data().name} (${a.data().type === "habit" ? "routine/habit" : "tracking temps"})`);
        if (orphanActs.length) {
            domainSections.push(`  · (Activités sans domaine)\n${orphanActs.join("\n")}`);
        }
        const projectsList = projectsSnap.docs.map(d => {
            var _a, _b;
            const data = d.data();
            const tasks = (_a = data.tasks) !== null && _a !== void 0 ? _a : [];
            const done = tasks.filter(t => t.status === "done").length;
            const total = tasks.length;
            return `  · "${data.title}" (id: ${d.id}) — ${done}/${total} tâches, fin ${(_b = data.endDate) !== null && _b !== void 0 ? _b : "non définie"}`;
        }).join("\n");
        const currentConfig = `Domaines & activités :\n${domainSections.length ? domainSections.join("\n") : "  Aucun"}\n\nProjets actifs (utilise les id pour update_project/archive_project/add_task) :\n${projectsList || "  Aucun"}`;
        const revSystemPrompt = REVISION_SYSTEM_PROMPT
            .replace("{{TODAY}}", today2)
            .replace("{{CURRENT_CONFIG}}", currentConfig);
        // Pré-populer la domainMap avec les domaines existants
        const revDomainMap = {};
        for (const doc of domainsSnap.docs) {
            const d = doc.data();
            if (!d.deleted)
                revDomainMap[d.name] = doc.id;
        }
        const revMessages = [
            ...(history !== null && history !== void 0 ? history : []).map((m) => ({ role: m.role, content: m.content })),
            { role: "user", content: action === "startRevision" ? "Je suis prêt pour ma session de révision." : (message !== null && message !== void 0 ? message : "") },
        ];
        const revNotifications = [];
        let revComplete = false;
        while (true) {
            const response = await client2.messages.create({
                model: (0, models_1.getModel)("onboarding"),
                max_tokens: 1536,
                system: revSystemPrompt,
                tools: REVISION_TOOLS,
                messages: revMessages,
            });
            if (response.stop_reason === "end_turn") {
                const text2 = response.content.filter((b) => b.type === "text").map((b) => b.text).join("");
                // Sauvegarde session révision
                const newHistory = [
                    ...(history !== null && history !== void 0 ? history : []),
                    { role: "user", content: action === "startRevision" ? "Je suis prêt pour ma session de révision." : (message !== null && message !== void 0 ? message : "") },
                    { role: "assistant", content: text2 },
                ];
                db_1.db.collection("formation_sessions").doc(uid).set({ uid, history: newHistory, mode: "revision", turnCount: newHistory.length / 2, savedAt: db_1.FieldValue.serverTimestamp() }).catch(() => { });
                res.status(200).json({ message: text2, notifications: revNotifications, revisionComplete: revComplete, mode: "revision" });
                return;
            }
            if (response.stop_reason === "tool_use") {
                revMessages.push({ role: "assistant", content: response.content });
                const toolResults = [];
                for (const block of response.content) {
                    if (block.type === "tool_use") {
                        const result = await executeOnboardingTool(uid, block.name, block.input, revDomainMap);
                        if (result.notification)
                            revNotifications.push(result.notification);
                        toolResults.push({ type: "tool_result", tool_use_id: block.id, content: result.output });
                    }
                }
                revMessages.push({ role: "user", content: toolResults });
                continue;
            }
            break;
        }
        res.status(500).json({ error: "Erreur boucle révision" });
        return;
    }
    // ── Guard — onboarding déjà complété ──────────────────────────────────────
    // Bloque toute nouvelle session de chat si l'onboarding est terminé.
    if (onboardingDone) {
        res.status(403).json({ code: "ONBOARDING_DONE", isPro });
        return;
    }
    if (!message) {
        res.status(400).json({ error: "message requis" });
        return;
    }
    const apiKey = process.env.ANTHROPIC_API_KEY;
    if (!apiKey) {
        res.status(500).json({ error: "ANTHROPIC_API_KEY manquante" });
        return;
    }
    const client = new sdk_1.default({ apiKey });
    const today = (0, execute_1.todayInParis)();
    // Bloc de contexte pré-rempli injecté dans le prompt si formulaire rempli
    const uc = userContext;
    const contextBlock = (uc && Object.values(uc).some(v => typeof v === "string" && v.trim())) ? `
━━━ CONTEXTE PRÉ-REMPLI (formulaire avant session) ━━━
L'utilisateur a déjà rempli un formulaire. Tu CONNAIS ces informations — NE LES REDEMANDE JAMAIS. Pars de là pour aller immédiatement en profondeur.

Prénom : ${uc.prenom || "—"}
Activité principale : ${uc.activite || "—"}
Situation : ${uc.situation || "—"}
Ce qui lui prend le plus d'énergie en ce moment : ${uc.energie || "—"}
Ce qu'il veut pouvoir faire dans 3 mois : ${uc.objectif || "—"}
Son plus grand frein à l'organisation : ${uc.frein || "—"}

Commence ta première réponse en reformulant en 2-3 phrases ce que tu comprends de sa situation (montre que tu as vraiment lu), puis pose UNE seule question pour aller plus loin sur le point le plus révélateur.
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━` : "";
    const systemPrompt = ONBOARDING_SYSTEM_PROMPT
        .replace("{{TODAY}}", today)
        .replace("{{USER_CONTEXT}}", contextBlock);
    const firstUserMsg = (history !== null && history !== void 0 ? history : []).length === 0 && contextBlock
        ? `${message}\n\n[Contexte formulaire déjà dans le system prompt — je suis prêt à démarrer.]`
        : message;
    const messages = [
        ...(history !== null && history !== void 0 ? history : []).map((m) => ({ role: m.role, content: m.content })),
        { role: "user", content: firstUserMsg },
    ];
    const notifications = [];
    const domainMap = {};
    let onboardingComplete = false;
    // Boucle agentique : continue jusqu'à end_turn (réponse texte finale)
    while (true) {
        const response = await client.messages.create({
            model: (0, models_1.getModel)("onboarding"),
            max_tokens: 2048,
            system: systemPrompt,
            tools: ONBOARDING_TOOLS,
            messages: messages,
        });
        if (response.stop_reason === "end_turn") {
            const text = response.content
                .filter((b) => b.type === "text")
                .map((b) => b.text)
                .join("");
            if (onboardingComplete) {
                await db_1.db.collection("formation_access").doc(uid).update({
                    onboardingDone: true,
                    onboardingDoneAt: db_1.FieldValue.serverTimestamp(),
                    lastVisionAt: db_1.FieldValue.serverTimestamp(),
                }).catch(() => { });
                // Nettoie la session après completion
                db_1.db.collection("formation_sessions").doc(uid).delete().catch(() => { });
            }
            else {
                // Sauvegarde la session après chaque échange (fire & forget)
                const historyToSave = [
                    ...(history !== null && history !== void 0 ? history : []),
                    { role: "user", content: message },
                    { role: "assistant", content: text },
                ];
                db_1.db.collection("formation_sessions").doc(uid).set({
                    uid, history: historyToSave,
                    userContext: userContext !== null && userContext !== void 0 ? userContext : null,
                    turnCount: (history !== null && history !== void 0 ? history : []).length / 2 + 1,
                    savedAt: db_1.FieldValue.serverTimestamp(),
                }).catch(() => { });
            }
            res.status(200).json({ message: text, notifications, onboardingComplete });
            return;
        }
        if (response.stop_reason === "tool_use") {
            messages.push({ role: "assistant", content: response.content });
            const toolResults = [];
            for (const block of response.content) {
                if (block.type === "tool_use") {
                    const result = await executeOnboardingTool(uid, block.name, block.input, domainMap);
                    if (result.notification)
                        notifications.push(result.notification);
                    if (block.name === "push_gantt")
                        onboardingComplete = true;
                    toolResults.push({ type: "tool_result", tool_use_id: block.id, content: result.output });
                }
            }
            messages.push({ role: "user", content: toolResults });
            continue;
        }
        // stop_reason inattendu
        break;
    }
    res.status(500).json({ error: "Erreur inattendue dans la boucle agentique" });
});
// ── adminProductivitwo (sessions de co-dev avec Claude Code) ──────────────────
//
// Endpoint protégé par secret pour permettre à Claude Code d'inspecter et
// pousser dans Productivitwo pendant les sessions de travail (sans passe-plat
// avec le MCP de Claude.ai). Secret stocké en Firebase Secret Manager.
exports.adminProductivitwo = (0, https_1.onRequest)({ cors: true, invoker: "public", secrets: ["ADMIN_PUSH_SECRET"] }, async (req, res) => {
    var _a, _b, _c, _d, _e, _f, _g, _h, _j;
    if (req.method === "OPTIONS") {
        res.status(204).send("");
        return;
    }
    if (req.method !== "POST") {
        res.status(405).json({ error: "Method Not Allowed" });
        return;
    }
    const { adminSecret, uid, action, payload } = req.body;
    if (!adminSecret || adminSecret.trim() !== ((_a = process.env.ADMIN_PUSH_SECRET) !== null && _a !== void 0 ? _a : "").trim()) {
        res.status(401).json({ error: "Secret invalide" });
        return;
    }
    if (!uid) {
        res.status(400).json({ error: "uid requis" });
        return;
    }
    try {
        if (action === "inspect") {
            const [domainsSnap, activitiesSnap, projectsSnap] = await Promise.all([
                db_1.db.collection(`users/${uid}/domains`).get(),
                db_1.db.collection(`users/${uid}/activities`).get(),
                db_1.db.collection(`users/${uid}/projects`).get(),
            ]);
            const domains = domainsSnap.docs
                .filter(d => !d.data().deleted)
                .map(d => (Object.assign({ id: d.id }, d.data())));
            const activities = activitiesSnap.docs
                .filter(d => !d.data().deleted)
                .map(d => (Object.assign({ id: d.id }, d.data())));
            const projects = projectsSnap.docs.map(d => {
                var _a;
                const data = d.data();
                const tasks = (_a = data.tasks) !== null && _a !== void 0 ? _a : [];
                return {
                    id: d.id,
                    title: data.title,
                    description: data.description,
                    status: data.status,
                    startDate: data.startDate,
                    endDate: data.endDate,
                    domainId: data.domainId,
                    tasks: tasks.map(t => ({
                        id: t.id, title: t.title, status: t.status,
                        startDate: t.startDate, endDate: t.endDate,
                        isMilestone: t.isMilestone,
                        actionsCount: Array.isArray(t.actions) ? t.actions.length : 0,
                        actionsDone: Array.isArray(t.actions) ? t.actions.filter(a => a.done).length : 0,
                        actions: Array.isArray(t.actions) ? t.actions.map(a => { var _a; return ({ id: a.id, title: a.title, done: (_a = a.done) !== null && _a !== void 0 ? _a : false }); }) : [],
                    })),
                };
            });
            res.status(200).json({ domains, activities, projects });
            return;
        }
        if (action === "updateTask") {
            const { projectId, taskId, startDate, endDate, title, status } = payload;
            const ref = db_1.db.collection(`users/${uid}/projects`).doc(projectId);
            const snap = await ref.get();
            if (!snap.exists) {
                res.status(404).json({ error: "Projet introuvable" });
                return;
            }
            const rawTasks = (_c = (_b = snap.data()) === null || _b === void 0 ? void 0 : _b.tasks) !== null && _c !== void 0 ? _c : [];
            const tasks = rawTasks.map(t => JSON.parse(JSON.stringify(t, (_k, v) => v && typeof v === "object" && typeof v.toDate === "function" ? v.toDate().toISOString() : v)));
            const idx = tasks.findIndex(t => t.id === taskId);
            if (idx === -1) {
                res.status(404).json({ error: "Tâche introuvable" });
                return;
            }
            const patch = {};
            if (startDate)
                patch.startDate = startDate;
            if (endDate)
                patch.endDate = endDate;
            if (title)
                patch.title = title;
            if (status)
                patch.status = status;
            tasks[idx] = Object.assign(Object.assign({}, tasks[idx]), patch);
            await ref.update({ tasks, updatedAt: db_1.FieldValue.serverTimestamp() });
            res.status(200).json({ success: true });
            return;
        }
        if (action === "addTask") {
            const { projectId, title, startDate, endDate, isMilestone, actions, phaseId, status, actionsAllDone } = payload;
            const newTask = {
                id: (0, uuid_1.v4)(), title, description: null,
                phaseId: phaseId !== null && phaseId !== void 0 ? phaseId : null, groupLabel: null,
                startDate, endDate: endDate !== null && endDate !== void 0 ? endDate : null,
                isMilestone: isMilestone !== null && isMilestone !== void 0 ? isMilestone : false,
                color: null, barLabel: null, status: status !== null && status !== void 0 ? status : "pending",
                recurringActionId: null,
                actions: (actions !== null && actions !== void 0 ? actions : []).map(a => ({
                    id: (0, uuid_1.v4)(), title: a,
                    done: actionsAllDone === true, doneAt: actionsAllDone === true ? new Date().toISOString() : null,
                    createdAt: new Date().toISOString(),
                })),
            };
            await db_1.db.collection(`users/${uid}/projects`).doc(projectId).update({
                tasks: db_1.FieldValue.arrayUnion(newTask),
                updatedAt: db_1.FieldValue.serverTimestamp(),
            });
            res.status(200).json({ success: true, taskId: newTask.id });
            return;
        }
        if (action === "addActionToTask") {
            const { projectId, taskId, title } = payload;
            const ref = db_1.db.collection(`users/${uid}/projects`).doc(projectId);
            const snap = await ref.get();
            if (!snap.exists) {
                res.status(404).json({ error: "Projet introuvable" });
                return;
            }
            const tasks = ((_e = (_d = snap.data()) === null || _d === void 0 ? void 0 : _d.tasks) !== null && _e !== void 0 ? _e : []).map(t => JSON.parse(JSON.stringify(t, (_k, v) => v && typeof v === "object" && typeof v.toDate === "function" ? v.toDate().toISOString() : v)));
            const idx = tasks.findIndex(t => t.id === taskId);
            if (idx === -1) {
                res.status(404).json({ error: "Tâche introuvable" });
                return;
            }
            const actions = ((_f = tasks[idx].actions) !== null && _f !== void 0 ? _f : []).slice();
            const newAction = { id: (0, uuid_1.v4)(), title, done: false, doneAt: null, createdAt: new Date().toISOString() };
            actions.push(newAction);
            tasks[idx] = Object.assign(Object.assign({}, tasks[idx]), { actions });
            await ref.update({ tasks, updatedAt: db_1.FieldValue.serverTimestamp() });
            res.status(200).json({ success: true, actionId: newAction.id });
            return;
        }
        if (action === "markActionDone") {
            const { projectId, taskId, actionId, done } = payload;
            const ref = db_1.db.collection(`users/${uid}/projects`).doc(projectId);
            const snap = await ref.get();
            if (!snap.exists) {
                res.status(404).json({ error: "Projet introuvable" });
                return;
            }
            const tasks = ((_h = (_g = snap.data()) === null || _g === void 0 ? void 0 : _g.tasks) !== null && _h !== void 0 ? _h : []).map(t => JSON.parse(JSON.stringify(t, (_k, v) => v && typeof v === "object" && typeof v.toDate === "function" ? v.toDate().toISOString() : v)));
            const tIdx = tasks.findIndex(t => t.id === taskId);
            if (tIdx === -1) {
                res.status(404).json({ error: "Tâche introuvable" });
                return;
            }
            const actions = ((_j = tasks[tIdx].actions) !== null && _j !== void 0 ? _j : []).slice();
            const aIdx = actions.findIndex(a => a.id === actionId);
            if (aIdx === -1) {
                res.status(404).json({ error: "Action introuvable" });
                return;
            }
            actions[aIdx] = Object.assign(Object.assign({}, actions[aIdx]), { done, doneAt: done ? new Date().toISOString() : null });
            tasks[tIdx] = Object.assign(Object.assign({}, tasks[tIdx]), { actions });
            await ref.update({ tasks, updatedAt: db_1.FieldValue.serverTimestamp() });
            res.status(200).json({ success: true });
            return;
        }
        if (action === "addProject") {
            const { title, description, startDate, endDate, domainId, phases, tasks } = payload;
            const projectId = (0, uuid_1.v4)();
            const phasesData = (phases !== null && phases !== void 0 ? phases : []).map(p => ({ id: (0, uuid_1.v4)(), label: p.label, color: null, startDate: p.startDate, endDate: p.endDate }));
            const tasksData = (tasks !== null && tasks !== void 0 ? tasks : []).map(t => {
                var _a, _b, _c, _d;
                return ({
                    id: (0, uuid_1.v4)(), title: t.title, description: null,
                    phaseId: t.phaseIndex !== undefined ? (_b = (_a = phasesData[t.phaseIndex]) === null || _a === void 0 ? void 0 : _a.id) !== null && _b !== void 0 ? _b : null : null,
                    groupLabel: null,
                    startDate: t.startDate, endDate: (_c = t.endDate) !== null && _c !== void 0 ? _c : null,
                    isMilestone: false, color: null, barLabel: null, status: "pending",
                    recurringActionId: null,
                    actions: ((_d = t.actions) !== null && _d !== void 0 ? _d : []).map(a => ({
                        id: (0, uuid_1.v4)(), title: a, done: false, doneAt: null, createdAt: new Date().toISOString(),
                    })),
                });
            });
            await db_1.db.collection(`users/${uid}/projects`).doc(projectId).set({
                id: projectId, title,
                description: description !== null && description !== void 0 ? description : null, strategicObjectiveId: null,
                domainId: domainId !== null && domainId !== void 0 ? domainId : null,
                startDate, endDate: endDate !== null && endDate !== void 0 ? endDate : null,
                status: "active", phases: phasesData, tasks: tasksData,
                createdBy: uid, sourceType: "claude_code_session",
                createdAt: db_1.FieldValue.serverTimestamp(), updatedAt: db_1.FieldValue.serverTimestamp(),
            });
            res.status(200).json({ success: true, projectId });
            return;
        }
        if (action === "setSchedule") {
            const { date, blocks } = payload;
            const normalizedBlocks = blocks.map(b => {
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
            await db_1.db.collection(`users/${uid}/daily_schedules`).doc(date).set({
                date,
                generatedBy: "claude_code_session",
                generatedAt: db_1.FieldValue.serverTimestamp(),
                blocks: normalizedBlocks,
            });
            res.status(200).json({ success: true, blocksCount: normalizedBlocks.length });
            return;
        }
        if (action === "updateProject") {
            const _l = payload, { projectId } = _l, updates = __rest(_l, ["projectId"]);
            await db_1.db.collection(`users/${uid}/projects`).doc(projectId).update(Object.assign(Object.assign({}, updates), { updatedAt: db_1.FieldValue.serverTimestamp() }));
            res.status(200).json({ success: true });
            return;
        }
        res.status(400).json({ error: `Action inconnue : ${action}` });
    }
    catch (e) {
        const msg = e instanceof Error ? e.message : String(e);
        res.status(500).json({ error: msg });
    }
});
// ── Formation helpers ─────────────────────────────────────────────────────────
const FORMATION_URL = "https://productivitwo-app.web.app/formation";
function createFormationToken(uid, email, secret) {
    const cleanSecret = secret.trim();
    const payload = Buffer.from(JSON.stringify({
        uid,
        email,
        exp: Date.now() + 30 * 24 * 60 * 60 * 1000,
    })).toString("base64url");
    const sig = (0, crypto_1.createHmac)("sha256", cleanSecret).update(payload).digest("base64url");
    return `${payload}.${sig}`;
}
function verifyFormationToken(token, secret) {
    const cleanSecret = secret.trim();
    const dot = token.lastIndexOf(".");
    if (dot < 0)
        return null;
    const payload = token.slice(0, dot);
    const sig = token.slice(dot + 1);
    const expected = (0, crypto_1.createHmac)("sha256", cleanSecret).update(payload).digest("base64url");
    // Accepte aussi l'ancienne signature (avec \n) pour ne pas invalider les tokens en circulation
    const legacy = (0, crypto_1.createHmac)("sha256", secret).update(payload).digest("base64url");
    if (sig !== expected && sig !== legacy)
        return null;
    try {
        const data = JSON.parse(Buffer.from(payload, "base64url").toString());
        if (!data.exp || data.exp < Date.now())
            return null;
        return { uid: data.uid, email: data.email };
    }
    catch (_a) {
        return null;
    }
}
function hexToColorValue(hex) {
    const clean = hex.replace("#", "");
    if (clean.length !== 6)
        return null;
    return parseInt("FF" + clean.toUpperCase(), 16);
}
// ── generateFormationAccess ───────────────────────────────────────────────────
//
// POST — appelé par systeme.io après un achat.
// Secret accepté : header x-webhook-secret OU query param ?secret=xxx OU body.webhookSecret
// Email accepté : body.email OU body.contact_email OU body.contact.email
// Retourne { accessUrl } à inclure dans l'email de confirmation systeme.io.
exports.generateFormationAccess = (0, https_1.onRequest)({ cors: true, invoker: "public", secrets: ["FORMATION_JWT_SECRET", "SYSTEME_IO_WEBHOOK_SECRET"] }, async (req, res) => {
    var _a, _b, _c, _d, _e, _f, _g;
    if (req.method === "OPTIONS") {
        res.status(204).send("");
        return;
    }
    if (req.method !== "POST") {
        res.status(405).json({ error: "Method Not Allowed" });
        return;
    }
    // Secret : header, query param ou body (compatible systeme.io qui ne supporte pas les headers custom)
    const body = req.body;
    const providedSecret = (_c = (_a = req.headers["x-webhook-secret"]) !== null && _a !== void 0 ? _a : (_b = req.query) === null || _b === void 0 ? void 0 : _b.secret) !== null && _c !== void 0 ? _c : body === null || body === void 0 ? void 0 : body.webhookSecret;
    if (!providedSecret || providedSecret.trim() !== ((_d = process.env.SYSTEME_IO_WEBHOOK_SECRET) !== null && _d !== void 0 ? _d : "").trim()) {
        res.status(401).json({ error: "Secret invalide" });
        return;
    }
    // Email : essaie les différents formats que systeme.io peut envoyer
    const contact = body === null || body === void 0 ? void 0 : body.contact;
    const rawEmail = (_g = (_f = (_e = body === null || body === void 0 ? void 0 : body.email) !== null && _e !== void 0 ? _e : body === null || body === void 0 ? void 0 : body.contact_email) !== null && _f !== void 0 ? _f : contact === null || contact === void 0 ? void 0 : contact.email) !== null && _g !== void 0 ? _g : "";
    const email = rawEmail.trim().toLowerCase();
    if (!email || !email.includes("@")) {
        res.status(400).json({ error: "email requis", received: body });
        return;
    }
    let uid;
    try {
        const existing = await admin.auth().getUserByEmail(email);
        uid = existing.uid;
    }
    catch (_h) {
        const created = await admin.auth().createUser({ email });
        uid = created.uid;
    }
    const token = createFormationToken(uid, email, process.env.FORMATION_JWT_SECRET);
    await db_1.db.collection("formation_access").doc(uid).set({ uid, email, purchasedAt: db_1.FieldValue.serverTimestamp(), onboardingDone: false }, { merge: true });
    const accessUrl = `${FORMATION_URL}?token=${encodeURIComponent(token)}`;
    res.status(200).json({ success: true, accessUrl, uid });
});
// ── getVisionAccess ───────────────────────────────────────────────────────────
//
// POST — Header: Authorization: Bearer <Firebase ID token>
// Retourne le statut Vision pour l'utilisateur authentifié + URL d'accès si dispo.
// Utilisé par le bouton Vision dans l'app web.
const VISION_INTERVAL_DAYS = 30;
exports.getVisionAccess = (0, https_1.onRequest)({ cors: true, invoker: "public", secrets: ["FORMATION_JWT_SECRET"] }, async (req, res) => {
    var _a, _b, _c, _d, _e, _f;
    if (req.method === "OPTIONS") {
        res.status(204).send("");
        return;
    }
    if (req.method !== "POST" && req.method !== "GET") {
        res.status(405).json({ error: "Method Not Allowed" });
        return;
    }
    const authHeader = (_a = req.headers.authorization) !== null && _a !== void 0 ? _a : "";
    if (!authHeader.startsWith("Bearer ")) {
        res.status(401).json({ error: "Missing Authorization header" });
        return;
    }
    const idToken = authHeader.slice(7).trim();
    let uid;
    let email;
    try {
        const decoded = await admin.auth().verifyIdToken(idToken);
        uid = decoded.uid;
        email = (_b = decoded.email) !== null && _b !== void 0 ? _b : "";
    }
    catch (_g) {
        res.status(401).json({ error: "Token invalide ou expiré" });
        return;
    }
    const accessDoc = await db_1.db.collection("formation_access").doc(uid).get();
    const accessData = (_c = accessDoc.data()) !== null && _c !== void 0 ? _c : {};
    const isPro = accessData.isPro === true;
    const onboardingDone = accessData.onboardingDone === true;
    const lastVisionAt = (_d = accessData.lastVisionAt) === null || _d === void 0 ? void 0 : _d.toDate();
    const now = Date.now();
    const intervalMs = VISION_INTERVAL_DAYS * 24 * 60 * 60 * 1000;
    const nextAvailableAt = lastVisionAt ? new Date(lastVisionAt.getTime() + intervalMs) : null;
    const available = !lastVisionAt || (nextAvailableAt && now >= nextAvailableAt.getTime());
    const result = {
        isPro,
        onboardingDone,
        lastVisionAt: (_e = lastVisionAt === null || lastVisionAt === void 0 ? void 0 : lastVisionAt.toISOString()) !== null && _e !== void 0 ? _e : null,
        nextAvailableAt: (_f = nextAvailableAt === null || nextAvailableAt === void 0 ? void 0 : nextAvailableAt.toISOString()) !== null && _f !== void 0 ? _f : null,
        available: available === true,
        intervalDays: VISION_INTERVAL_DAYS,
    };
    // Génère un access URL frais vers la formation :
    // - première session d'onboarding : toujours accessible (gratuite)
    // - révisions mensuelles suivantes : réservées aux Pro quand disponible
    if (!onboardingDone || (isPro && available)) {
        const token = createFormationToken(uid, email, process.env.FORMATION_JWT_SECRET);
        result.accessUrl = `https://productivitwo-app.web.app/vision?token=${encodeURIComponent(token)}`;
    }
    res.status(200).json(result);
});
exports.applyFormationProfile = (0, https_1.onRequest)({ cors: true, invoker: "public", secrets: ["FORMATION_JWT_SECRET"] }, async (req, res) => {
    var _a, _b, _c, _d, _e, _f, _g, _h, _j;
    if (req.method === "OPTIONS") {
        res.status(204).send("");
        return;
    }
    if (req.method !== "POST") {
        res.status(405).json({ error: "Method Not Allowed" });
        return;
    }
    const { token, profile } = req.body;
    if (!token || !profile) {
        res.status(400).json({ error: "token et profile requis" });
        return;
    }
    const decoded = verifyFormationToken(token, process.env.FORMATION_JWT_SECRET);
    if (!decoded) {
        res.status(401).json({ error: "Token invalide ou expiré" });
        return;
    }
    const { uid } = decoded;
    // Idempotence : ne pas recréer si l'onboarding est déjà fait
    const accessDoc = await db_1.db.collection("formation_access").doc(uid).get();
    if (accessDoc.exists && ((_a = accessDoc.data()) === null || _a === void 0 ? void 0 : _a.onboardingDone)) {
        res.status(200).json({ success: true, uid, alreadyApplied: true });
        return;
    }
    // Domaines
    const domainIds = [];
    for (const d of ((_b = profile.domaines) !== null && _b !== void 0 ? _b : [])) {
        const id = (0, uuid_1.v4)();
        domainIds.push(id);
        await db_1.db.collection(`users/${uid}/domains`).doc(id).set({
            id,
            name: d.name,
            goalMinDay: null,
            autoGoal: true,
            colorValue: d.color ? hexToColorValue(d.color) : null,
            createdAt: db_1.FieldValue.serverTimestamp(),
        });
    }
    // Activités de tracking (type time)
    for (const a of ((_c = profile.activites) !== null && _c !== void 0 ? _c : [])) {
        const id = (0, uuid_1.v4)();
        const domainId = (_e = domainIds[(_d = a.domaine_index) !== null && _d !== void 0 ? _d : 0]) !== null && _e !== void 0 ? _e : null;
        const isHabit = a.type === "habit";
        await db_1.db.collection(`users/${uid}/activities`).doc(id).set({
            id,
            name: a.name,
            domainId,
            type: isHabit ? "habit" : "time",
            role: "generic",
            goalMin: (_f = a.goalMin) !== null && _f !== void 0 ? _f : 1,
            unit: null,
            habitFreq: isHabit ? 0 : null,
            habitTarget: isHabit ? 1 : null,
            manualTarget: false,
            autoTune: true,
            createdAt: db_1.FieldValue.serverTimestamp(),
            lastTuneAt: null,
            order: 0,
            iconCode: null,
            deleted: false,
        });
    }
    // Routines (habit activities dans le 1er domaine)
    for (const r of ((_g = profile.routines) !== null && _g !== void 0 ? _g : [])) {
        const id = (0, uuid_1.v4)();
        await db_1.db.collection(`users/${uid}/activities`).doc(id).set({
            id,
            name: r.name,
            domainId: (_h = domainIds[0]) !== null && _h !== void 0 ? _h : null,
            type: "habit",
            role: "generic",
            goalMin: (_j = r.dureeMin) !== null && _j !== void 0 ? _j : 15,
            unit: null,
            habitFreq: 0,
            habitTarget: 1,
            manualTarget: false,
            autoTune: false,
            createdAt: db_1.FieldValue.serverTimestamp(),
            lastTuneAt: null,
            order: 0,
            iconCode: null,
            deleted: false,
        });
    }
    await db_1.db.collection("formation_access").doc(uid).update({
        onboardingDone: true,
        onboardingDoneAt: db_1.FieldValue.serverTimestamp(),
    });
    res.status(200).json({ success: true, uid });
});
//# sourceMappingURL=index.js.map