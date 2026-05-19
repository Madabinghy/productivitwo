"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.pushGantt = void 0;
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
//# sourceMappingURL=index.js.map