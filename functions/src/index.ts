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
