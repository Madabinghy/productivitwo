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

// ── Outils contexte utilisateur + écriture agenda ────────────────────────────

const GET_USER_CONTEXT_TOOL = {
  name: "get_user_context",
  description:
    "Retourne le contexte complet de l'utilisateur : domaines de vie, activités " +
    "(avec leurs objectifs quotidiens), routines actives et objectifs GTD en cours. " +
    "Appelle cet outil en premier pour personnaliser tes suggestions.",
  inputSchema: { type: "object", properties: {} },
};

const UPDATE_ACTIVITY_GOAL_TOOL = {
  name: "update_activity_goal",
  description:
    "Modifie l'objectif quotidien d'une activité (temps ou fréquence). " +
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
  description:
    "Crée une action récurrente dans Productivitwo. " +
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
  description:
    "Ajoute une action au plan quotidien de l'utilisateur pour une date donnée. " +
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

const DELETE_PROJECT_TOOL = {
  name: "delete_project",
  description:
    "Supprime définitivement un projet Gantt et son objectif stratégique associé. " +
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
  description:
    "Liste les projets Gantt existants dans Productivitwo. " +
    "Appelle cet outil avant de modifier un projet afin de récupérer son id.",
  inputSchema: { type: "object", properties: {} },
};

const GET_PROJECT_TOOL = {
  name: "get_project",
  description:
    "Retourne le détail complet d'un projet Gantt (phases, tâches, jalons). " +
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
  description:
    "Crée ou met à jour un projet Gantt dans Productivitwo. " +
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

async function executeGetUserContext(uid: string): Promise<string> {
  const [domainsSnap, activitiesSnap, routinesSnap, goalsSnap] = await Promise.all([
    db.collection(`users/${uid}/domains`).get(),
    db.collection(`users/${uid}/activities`).get(),
    db.collection(`users/${uid}/recurringActions`).get(),
    db.collection(`users/${uid}/goals`).where("status", "==", "active").get(),
  ]);

  const domains = domainsSnap.docs.map((d) => {
    const v = d.data();
    return { id: v.id, name: v.name };
  });

  const activities = activitiesSnap.docs.map((d) => {
    const v = d.data();
    return {
      id: v.id,
      name: v.name,
      type: v.type,           // 'time' | 'habit'
      domainId: v.domainId,
      goalMin: v.goalMin,     // objectif minutes/jour
      habitFreq: v.habitFreq, // 0=daily 1=weekly 2=monthly
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
    const actions = (v.actions || []) as Array<{ done: boolean }>;
    return {
      id: v.id,
      title: v.title,
      domainId: v.domainId,
      dueDate: v.dueDate || null,
      progress: `${actions.filter((a) => a.done).length}/${actions.length}`,
    };
  });

  return JSON.stringify({ domains, activities, activeRoutines, activeGoals }, null, 2);
}

async function executeUpdateActivityGoal(
  uid: string,
  activityId: string,
  updates: { goalMin?: number; habitTarget?: number; habitFreq?: number }
): Promise<string> {
  const ref = db.collection(`users/${uid}/activities`).doc(activityId);
  const snap = await ref.get();
  if (!snap.exists) return `Activité introuvable : ${activityId}`;

  const patch: Record<string, unknown> = {};
  if (updates.goalMin !== undefined) patch.goalMin = updates.goalMin;
  if (updates.habitTarget !== undefined) patch.habitTarget = updates.habitTarget;
  if (updates.habitFreq !== undefined) patch.habitFreq = updates.habitFreq;

  await ref.update(patch);
  const name = snap.data()?.name ?? activityId;
  return `✅ Objectif de "${name}" mis à jour. Visible dans Productivitwo à la prochaine synchronisation.`;
}

async function executeCreateRoutine(
  uid: string,
  args: {
    title: string;
    domainId?: string;
    activityId?: string;
    recurrenceType?: string;
    weekdays?: number[];
    startDate?: string;
    endDate?: string;
    projectTaskId?: string;
  }
): Promise<string> {
  const id = uuidv4();
  await db.collection(`users/${uid}/recurringActions`).doc(id).set({
    id,
    title: args.title,
    domainId: args.domainId || null,
    activityId: args.activityId || null,
    blockId: null,
    type: args.recurrenceType === "specificDays" ? "specificDays" : "daily",
    weekdays: args.weekdays || [],
    active: true,
    createdAt: FieldValue.serverTimestamp(),
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

async function executeAddToDayPlan(
  uid: string,
  args: {
    title: string;
    date: string;
    domainId?: string;
    activityId?: string;
    projectId?: string;
    projectTaskId?: string;
  }
): Promise<string> {
  // Valider le format de date
  if (!/^\d{4}-\d{2}-\d{2}$/.test(args.date)) {
    return `Date invalide : ${args.date}. Format attendu : YYYY-MM-DD`;
  }
  const yyyymmdd = args.date.replace(/-/g, "");

  const id = uuidv4();
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
    createdAt: FieldValue.serverTimestamp(),
    domainId: args.domainId || null,
    activityId: args.activityId || null,
    projectId: args.projectId || null,
    projectTaskId: args.projectTaskId || null,
  });

  return `✅ "${args.title}" ajouté au plan du ${args.date}.`;
}

async function executeDeleteProject(
  uid: string,
  projectId: string,
  deleteObjective: boolean
): Promise<string> {
  const projectRef = db.collection(`users/${uid}/projects`).doc(projectId);
  const projectSnap = await projectRef.get();

  if (!projectSnap.exists) {
    return `Projet introuvable : ${projectId}`;
  }

  const projectData = projectSnap.data() as Record<string, unknown>;
  const title = projectData.title ?? projectId;
  const objId = projectData.strategicObjectiveId as string | undefined;

  await projectRef.delete();

  if (deleteObjective && objId) {
    await db.collection(`users/${uid}/strategic_objectives`).doc(objId).delete();
    return `✅ Projet "${title}" et son objectif stratégique supprimés.`;
  }

  return `✅ Projet "${title}" supprimé.`;
}

async function executeListProjects(uid: string): Promise<string> {
  const snap = await db.collection(`users/${uid}/projects`).get();
  if (snap.empty) return "Aucun projet trouvé dans Productivitwo.";

  const lines = snap.docs.map((doc) => {
    const d = doc.data();
    const taskCount = (d.tasks || []).length;
    const start = d.startDate || "?";
    const end   = d.endDate   || "?";
    return `• [${d.id}] ${d.title} (${start} → ${end}, ${taskCount} tâche(s))`;
  });

  return `Projets Productivitwo (${snap.size}) :\n${lines.join("\n")}`;
}

async function executeGetProject(uid: string, projectId: string): Promise<string> {
  const doc = await db.collection(`users/${uid}/projects`).doc(projectId).get();
  if (!doc.exists) return `Projet introuvable : ${projectId}`;

  const d = doc.data() as Record<string, unknown>;
  // Retourner le JSON complet pour que Claude puisse le modifier
  return JSON.stringify(d, null, 2);
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

  const isUpdate = !!project.id;
  return (
    `✅ Projet "${project.title}" ${isUpdate ? "mis à jour" : "créé"} dans Productivitwo !\n` +
    `• ${(project.tasks || []).length} tâche(s) · ${(project.phases || []).length} phase(s)\n` +
    `• Voir sur : https://productivitwo-app.web.app\n` +
    `• projectId : ${projectId}`
  );
}

// ── getCustomToken ────────────────────────────────────────────────────────────
//
// POST { uid, token }
// Valide le token API, retourne un Firebase custom token pour cet UID.
// Permet au web app de se connecter avec le même UID que l'app iOS.

export const getCustomToken = onRequest({ cors: true, invoker: "public" }, async (req, res) => {
  if (req.method === "OPTIONS") { res.status(204).send(""); return; }
  if (req.method !== "POST") { res.status(405).json({ error: "Method Not Allowed" }); return; }

  const { uid, token } = req.body as { uid?: string; token?: string };
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
      responses.push({
        jsonrpc: "2.0", id,
        result: {
          tools: [
            GET_USER_CONTEXT_TOOL,
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
    } else if (method === "tools/call") {
      const toolName: string = rpc.params?.name ?? "";
      const args = rpc.params?.arguments ?? {};
      try {
        let text = "";
        if (toolName === "delete_project") {
          text = await executeDeleteProject(
            uid,
            args.projectId as string,
            (args.deleteObjective as boolean) ?? false
          );
        } else if (toolName === "get_user_context") {
          text = await executeGetUserContext(uid);
        } else if (toolName === "list_projects") {
          text = await executeListProjects(uid);
        } else if (toolName === "get_project") {
          text = await executeGetProject(uid, args.projectId as string);
        } else if (toolName === "push_gantt") {
          text = await executePushGantt(uid, { uid, ...args });
        } else if (toolName === "update_activity_goal") {
          text = await executeUpdateActivityGoal(uid, args.activityId as string, args);
        } else if (toolName === "create_routine") {
          text = await executeCreateRoutine(uid, args as Parameters<typeof executeCreateRoutine>[1]);
        } else if (toolName === "add_to_day_plan") {
          text = await executeAddToDayPlan(uid, args as Parameters<typeof executeAddToDayPlan>[1]);
        } else {
          responses.push({ jsonrpc: "2.0", id, error: { code: -32601, message: `Outil inconnu : ${toolName}` } });
          continue;
        }
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
