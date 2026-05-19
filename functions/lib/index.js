"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.mcpHandler = exports.pushGantt = void 0;
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
const PUSH_GANTT_MCP_TOOL = {
    name: "push_gantt",
    description: "Crée un projet Gantt dans Productivitwo. Utilise cet outil quand " +
        "l'utilisateur veut planifier une roadmap, une campagne ou tout projet " +
        "avec des étapes dans le temps.",
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
    return (`✅ Projet "${project.title}" créé dans Productivitwo !\n` +
        `• ${(project.tasks || []).length} tâche(s) · ${(project.phases || []).length} phase(s)\n` +
        `• Voir sur : https://productivitwo-app.web.app\n` +
        `• projectId : ${projectId}`);
}
exports.mcpHandler = (0, https_1.onRequest)({ cors: true, invoker: "public" }, async (req, res) => {
    var _a, _b, _c;
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
            responses.push({ jsonrpc: "2.0", id, result: { tools: [PUSH_GANTT_MCP_TOOL] } });
        }
        else if (method === "tools/call") {
            const toolName = (_c = rpc.params) === null || _c === void 0 ? void 0 : _c.name;
            if (toolName !== "push_gantt") {
                responses.push({ jsonrpc: "2.0", id, error: { code: -32601, message: `Outil inconnu : ${toolName}` } });
                continue;
            }
            try {
                const text = await executePushGantt(uid, Object.assign({ uid }, rpc.params.arguments));
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