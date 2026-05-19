import { onRequest } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import { FieldValue } from "firebase-admin/firestore";
import { v4 as uuidv4 } from "uuid";

admin.initializeApp();
const db = admin.firestore();

// ── Types ─────────────────────────────────────────────────────────────────────

interface ProjectPhase {
  id?: string;
  label: string;
  color?: string;
  startDate: string;
  endDate: string;
}

interface ProjectTask {
  id?: string;
  title: string;
  phaseId?: string;
  groupLabel?: string;
  startDate: string;
  endDate?: string;
  isMilestone?: boolean;
  color?: string;
  barLabel?: string;
  status?: "pending" | "done" | "skipped";
}

interface ProjectPayload {
  id?: string;
  title: string;
  description?: string;
  domainId?: string;
  startDate: string;
  endDate?: string;
  phases?: ProjectPhase[];
  tasks?: ProjectTask[];
}

interface StrategicObjectivePayload {
  id?: string;
  title: string;
  description?: string;
  domainId?: string;
  kpiTarget?: string;
  horizonLabel?: string;
  startDate?: string;
  endDate?: string;
}

interface PushGanttBody {
  uid: string;
  project: ProjectPayload;
  strategicObjective?: StrategicObjectivePayload;
}

// ── Helpers ───────────────────────────────────────────────────────────────────

function normalizePhases(phases?: ProjectPhase[]): ProjectPhase[] {
  if (!phases) return [];
  return phases.map((p) => ({ ...p, id: p.id || uuidv4() }));
}

function normalizeTasks(tasks?: ProjectTask[]): ProjectTask[] {
  if (!tasks) return [];
  return tasks.map((t) => ({
    ...t,
    id: t.id || uuidv4(),
    isMilestone: t.isMilestone ?? false,
    status: t.status ?? "pending",
  }));
}

// ── pushGantt ─────────────────────────────────────────────────────────────────
//
// POST https://us-central1-productivitwo-app.cloudfunctions.net/pushGantt
// Headers: Authorization: Bearer <token>
// Body: { uid, project, strategicObjective? }

export const pushGantt = onRequest({ cors: true, invoker: "public" }, async (req, res) => {
  if (req.method === "OPTIONS") {
    res.status(204).send("");
    return;
  }

  if (req.method !== "POST") {
    res.status(405).json({ error: "Method Not Allowed" });
    return;
  }

  // 1. Bearer token
  const authHeader = req.headers.authorization ?? "";
  if (!authHeader.startsWith("Bearer ")) {
    res.status(401).json({ error: "Missing Authorization header" });
    return;
  }
  const rawToken = authHeader.slice(7).trim();

  // 2. Validation du corps
  const body = req.body as PushGanttBody;
  if (!body.uid || !body.project?.title || !body.project?.startDate) {
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
  tokenQuery.docs[0].ref.update({ lastUsedAt: FieldValue.serverTimestamp() });

  // 5. Objectif stratégique
  let strategicObjectiveId: string | undefined;
  if (strategicObjective) {
    const objId = strategicObjective.id || uuidv4();
    strategicObjectiveId = objId;
    await db.collection(`users/${uid}/strategic_objectives`).doc(objId).set(
      {
        ...strategicObjective,
        id: objId,
        status: "active",
        updatedAt: FieldValue.serverTimestamp(),
        createdAt: FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
  }

  // 6. Projet
  const projectId = project.id || uuidv4();
  const projectDoc = {
    ...project,
    id: projectId,
    phases: normalizePhases(project.phases),
    tasks: normalizeTasks(project.tasks),
    createdBy: uid,
    sourceType: "claude_api",
    status: "active",
    ...(strategicObjectiveId ? { strategicObjectiveId } : {}),
    updatedAt: FieldValue.serverTimestamp(),
    createdAt: FieldValue.serverTimestamp(),
  };

  await db.collection(`users/${uid}/projects`).doc(projectId).set(projectDoc, { merge: true });

  // 7. Lier projet → objectif
  if (strategicObjectiveId) {
    await db
      .collection(`users/${uid}/strategic_objectives`)
      .doc(strategicObjectiveId)
      .update({ projectIds: FieldValue.arrayUnion(projectId) });
  }

  res.status(200).json({ success: true, projectId, strategicObjectiveId: strategicObjectiveId ?? null });
});

// ── Remote MCP Handler ────────────────────────────────────────────────────────
//
// URL : /mcp/{uid}/{token}
// Implémente le protocole MCP JSON-RPC 2.0 (Streamable HTTP, stateless).
// Compatible Claude Desktop et Claude.ai web (Integrations).

const PUSH_GANTT_MCP_TOOL = {
  name: "push_gantt",
  description:
    "Crée un projet Gantt dans Productivitwo. Utilise cet outil quand " +
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
          title:       { type: "string" },
          description: { type: "string" },
          startDate:   { type: "string", description: "YYYY-MM-DD" },
          endDate:     { type: "string", description: "YYYY-MM-DD" },
          phases: {
            type: "array",
            items: {
              type: "object",
              required: ["label", "startDate", "endDate"],
              properties: {
                label:     { type: "string" },
                color:     { type: "string" },
                startDate: { type: "string" },
                endDate:   { type: "string" },
              },
            },
          },
          tasks: {
            type: "array",
            items: {
              type: "object",
              required: ["title", "startDate"],
              properties: {
                title:       { type: "string" },
                groupLabel:  { type: "string" },
                startDate:   { type: "string" },
                endDate:     { type: "string" },
                isMilestone: { type: "boolean" },
                color:       { type: "string" },
                barLabel:    { type: "string" },
                status:      { type: "string", enum: ["pending", "done", "skipped"] },
              },
            },
          },
        },
      },
      strategicObjective: {
        type: "object",
        properties: {
          title:        { type: "string" },
          kpiTarget:    { type: "string" },
          horizonLabel: { type: "string" },
        },
      },
    },
  },
};

async function validateToken(uid: string, rawToken: string): Promise<boolean> {
  const q = await db
    .collection(`users/${uid}/api_tokens`)
    .where("token", "==", rawToken)
    .where("active", "==", true)
    .limit(1)
    .get();
  if (!q.empty) {
    q.docs[0].ref.update({ lastUsedAt: FieldValue.serverTimestamp() });
    return true;
  }
  return false;
}

async function executePushGantt(uid: string, input: PushGanttBody): Promise<string> {
  const { project, strategicObjective } = input;

  let strategicObjectiveId: string | undefined;
  if (strategicObjective) {
    const objId = strategicObjective.id || uuidv4();
    strategicObjectiveId = objId;
    await db.collection(`users/${uid}/strategic_objectives`).doc(objId).set(
      { ...strategicObjective, id: objId, status: "active", updatedAt: FieldValue.serverTimestamp(), createdAt: FieldValue.serverTimestamp() },
      { merge: true }
    );
  }

  const projectId = project.id || uuidv4();
  await db.collection(`users/${uid}/projects`).doc(projectId).set(
    {
      ...project,
      id: projectId,
      phases: (project.phases || []).map((p: ProjectPhase) => ({ ...p, id: p.id || uuidv4() })),
      tasks: (project.tasks || []).map((t: ProjectTask) => ({ ...t, id: t.id || uuidv4(), isMilestone: t.isMilestone ?? false, status: t.status ?? "pending" })),
      createdBy: uid,
      sourceType: "claude_mcp",
      status: "active",
      ...(strategicObjectiveId ? { strategicObjectiveId } : {}),
      updatedAt: FieldValue.serverTimestamp(),
      createdAt: FieldValue.serverTimestamp(),
    },
    { merge: true }
  );

  if (strategicObjectiveId) {
    await db.collection(`users/${uid}/strategic_objectives`).doc(strategicObjectiveId)
      .update({ projectIds: FieldValue.arrayUnion(projectId) });
  }

  return (
    `✅ Projet "${project.title}" créé dans Productivitwo !\n` +
    `• ${(project.tasks || []).length} tâche(s) · ${(project.phases || []).length} phase(s)\n` +
    `• Voir sur : https://productivitwo-app.web.app\n` +
    `• projectId : ${projectId}`
  );
}

export const mcpHandler = onRequest({ cors: true, invoker: "public" }, async (req, res) => {
  // CORS preflight
  if (req.method === "OPTIONS") { res.status(204).send(""); return; }

  // Extraire uid + token du path : /mcp/{uid}/{token}
  // Firebase Hosting conserve le préfixe /mcp/ dans req.path
  const parts = (req.path || "").replace(/^\/+mcp\/*/, "").split("/");
  const uid   = parts[0] || "";
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
  const responses: object[] = [];

  for (const rpc of requests) {
    const id   = rpc.id ?? null;
    const method: string = rpc.method ?? "";

    // Notifications (pas de réponse attendue)
    if (id === null && method.startsWith("notifications/")) continue;

    if (method === "initialize") {
      responses.push({
        jsonrpc: "2.0", id,
        result: {
          protocolVersion: "2024-11-05",
          capabilities: { tools: {} },
          serverInfo: { name: "productivitwo", version: "1.0.0" },
        },
      });
    } else if (method === "ping") {
      responses.push({ jsonrpc: "2.0", id, result: {} });
    } else if (method === "tools/list") {
      responses.push({ jsonrpc: "2.0", id, result: { tools: [PUSH_GANTT_MCP_TOOL] } });
    } else if (method === "tools/call") {
      const toolName = rpc.params?.name;
      if (toolName !== "push_gantt") {
        responses.push({ jsonrpc: "2.0", id, error: { code: -32601, message: `Outil inconnu : ${toolName}` } });
        continue;
      }
      try {
        const text = await executePushGantt(uid, { uid, ...rpc.params.arguments });
        responses.push({ jsonrpc: "2.0", id, result: { content: [{ type: "text", text }] } });
      } catch (e: unknown) {
        const msg = e instanceof Error ? e.message : String(e);
        responses.push({ jsonrpc: "2.0", id, result: { content: [{ type: "text", text: `Erreur : ${msg}` }], isError: true } });
      }
    } else {
      responses.push({ jsonrpc: "2.0", id, error: { code: -32601, message: `Méthode inconnue : ${method}` } });
    }
  }

  res.setHeader("Content-Type", "application/json");
  res.status(200).json(responses.length === 1 ? responses[0] : responses);
});
