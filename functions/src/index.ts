import { onRequest } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import { v4 as uuidv4 } from "uuid";
import { db, FieldValue } from "./db";
import { MCP_PROMPTS, getPromptMessages, executeGetDocumentTemplate } from "./prompts";
import {
  GET_USER_CONTEXT_TOOL, GET_DAY_BLOCKS_TOOL, GET_DAY_PLAN_TOOL, PLAN_DAY_TOOL,
  CLEAR_DAY_PLAN_TOOL, LIST_PROJECTS_TOOL, GET_PROJECT_TOOL, PUSH_GANTT_MCP_TOOL,
  ARCHIVE_PROJECT_TOOL, DELETE_PROJECT_TOOL, UPDATE_ACTIVITY_GOAL_TOOL,
  CREATE_ROUTINE_TOOL, CREATE_RECURRING_ACTION_TOOL, DELETE_ROUTINE_TOOL,
  ADD_TO_DAY_PLAN_TOOL, DELETE_GOAL_TOOL, LINK_GOAL_TO_TASK_TOOL,
  CREATE_ACTIVITY_TOOL, UPDATE_ACTIVITY_TOOL, UPDATE_TASK_STATUS_TOOL,
  UPDATE_PROJECT_TOOL, DELETE_ACTIVITY_TOOL, DELETE_ACTION_TOOL,
  GET_DOCUMENT_TEMPLATE_TOOL, SAVE_DOCUMENT_TOOL, GET_DOCUMENTS_TOOL,
  DELETE_DOCUMENT_TOOL, GET_ARCHIVES_TOOL, RESTORE_ITEM_TOOL,
  CREATE_DOMAIN_TOOL, DELETE_DOMAIN_TOOL, PUSH_ASSISTANT_MESSAGE_TOOL,
} from "./tools";
import {
  validateToken, normalizePhases, normalizeTasks,
  executePushAssistantMessage, executeGetUserContext, executeUpdateActivityGoal,
  executeCreateRoutine, executeCreateRecurringAction, executeAddToDayPlan,
  executeGetDayBlocks, executeGetDayPlan, executePlanDay, executeCreateActivity,
  executeDeleteAction, executeSaveDocument, executeGetDocuments, executeGetArchives,
  executeRestoreItem, executeCreateDomain, executeDeleteDomain, executeDeleteActivity,
  executeUpdateProject, executeUpdateTaskStatus, executeUpdateActivity,
  executeLinkGoalToTask, executeDeleteRoutine, executeDeleteGoal, executeClearDayPlan,
  executeArchiveProject, executeDeleteProject, executeListProjects, executeGetProject,
  executePushGantt,
} from "./execute";
import type { PushGanttBody } from "./types";

// ── pushGantt ─────────────────────────────────────────────────────────────────
//
// POST https://us-central1-productivitwo-app.cloudfunctions.net/pushGantt
// Headers: Authorization: Bearer <token>
// Body: { uid, project, strategicObjective? }

export const pushGantt = onRequest({ cors: true, invoker: "public" }, async (req, res) => {
  if (req.method === "OPTIONS") { res.status(204).send(""); return; }
  if (req.method !== "POST") { res.status(405).json({ error: "Method Not Allowed" }); return; }

  const authHeader = req.headers.authorization ?? "";
  if (!authHeader.startsWith("Bearer ")) {
    res.status(401).json({ error: "Missing Authorization header" });
    return;
  }
  const rawToken = authHeader.slice(7).trim();

  const body = req.body as PushGanttBody;
  if (!body.uid || !body.project?.title || !body.project?.startDate) {
    res.status(400).json({ error: "Missing required fields: uid, project.title, project.startDate" });
    return;
  }
  const { uid, project, strategicObjective } = body;

  const tokenQuery = await db
    .collection(`users/${uid}/api_tokens`)
    .where("token", "==", rawToken)
    .where("active", "==", true)
    .limit(1)
    .get();
  if (tokenQuery.empty) { res.status(401).json({ error: "Invalid or revoked token" }); return; }
  tokenQuery.docs[0].ref.update({ lastUsedAt: FieldValue.serverTimestamp() });

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
      phases: normalizePhases(project.phases),
      tasks: normalizeTasks(project.tasks),
      createdBy: uid,
      sourceType: "claude_api",
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

  res.status(200).json({ success: true, projectId, strategicObjectiveId: strategicObjectiveId ?? null });
});

// ── pushAssistantMessage ──────────────────────────────────────────────────────
//
// POST https://us-central1-productivitwo-app.cloudfunctions.net/pushAssistantMessage

export const pushAssistantMessage = onRequest({ cors: true, invoker: "public" }, async (req, res) => {
  if (req.method === "OPTIONS") { res.status(204).send(""); return; }
  if (req.method !== "POST") { res.status(405).json({ error: "Method Not Allowed" }); return; }

  const authHeader = req.headers.authorization ?? "";
  if (!authHeader.startsWith("Bearer ")) { res.status(401).json({ error: "Missing Authorization header" }); return; }
  const rawToken = authHeader.slice(7).trim();

  const body = req.body as { uid?: string } & Parameters<typeof executePushAssistantMessage>[1];
  if (!body.uid || !body.targetDate || !body.text || !body.condition) {
    res.status(400).json({ error: "Missing required fields: uid, targetDate, text, condition" });
    return;
  }

  const valid = await validateToken(body.uid, rawToken);
  if (!valid) { res.status(401).json({ error: "Invalid or revoked token" }); return; }

  const result = await executePushAssistantMessage(body.uid, body);
  const messageId = result.match(/messageId : (.+)$/m)?.[1];
  res.status(200).json({ success: true, messageId });
});

// ── getCustomToken ────────────────────────────────────────────────────────────
//
// POST { uid, token } — retourne un Firebase custom token pour cet UID.

export const getCustomToken = onRequest({ cors: true, invoker: "public" }, async (req, res) => {
  if (req.method === "OPTIONS") { res.status(204).send(""); return; }
  if (req.method !== "POST") { res.status(405).json({ error: "Method Not Allowed" }); return; }

  const { uid, token } = req.body as { uid?: string; token?: string };
  if (!uid || !token) { res.status(400).json({ error: "uid et token requis" }); return; }

  const valid = await validateToken(uid, token);
  if (!valid) { res.status(401).json({ error: "Token invalide ou révoqué" }); return; }

  const customToken = await admin.auth().createCustomToken(uid);
  res.status(200).json({ customToken });
});

// ── mcpHandler ────────────────────────────────────────────────────────────────
//
// URL : /mcp/{uid}/{token} — protocole MCP JSON-RPC 2.0 (Streamable HTTP, stateless)

export const mcpHandler = onRequest({ cors: true, invoker: "public" }, async (req, res) => {
  if (req.method === "OPTIONS") { res.status(204).send(""); return; }

  const parts = (req.path || "").replace(/^\/+mcp\/*/, "").split("/");
  const uid   = parts[0] || "";
  const token = parts[1] || "";

  if (!uid || !token) {
    res.status(401).json({ error: "URL invalide — format attendu : /mcp/{uid}/{token}" });
    return;
  }

  const valid = await validateToken(uid, token);
  if (!valid) { res.status(401).json({ error: "Token invalide ou révoqué" }); return; }

  const body = req.body;
  const requests = Array.isArray(body) ? body : [body];
  const responses: object[] = [];

  for (const rpc of requests) {
    const id     = rpc.id ?? null;
    const method: string = rpc.method ?? "";

    if (id === null && method.startsWith("notifications/")) continue;

    if (method === "initialize") {
      responses.push({
        jsonrpc: "2.0", id,
        result: {
          protocolVersion: "2024-11-05",
          capabilities: { tools: {}, prompts: {} },
          serverInfo: { name: "productivitwo", version: "1.0.0" },
        },
      });
    } else if (method === "ping") {
      responses.push({ jsonrpc: "2.0", id, result: {} });

    } else if (method === "prompts/list") {
      responses.push({ jsonrpc: "2.0", id, result: { prompts: MCP_PROMPTS } });

    } else if (method === "prompts/get") {
      const promptName: string = rpc.params?.name ?? "";
      const promptArgs: Record<string, string> = rpc.params?.arguments ?? {};
      const prompt = MCP_PROMPTS.find((p) => p.name === promptName);
      if (!prompt) {
        responses.push({ jsonrpc: "2.0", id, error: { code: -32601, message: `Prompt inconnu : ${promptName}` } });
      } else {
        responses.push({
          jsonrpc: "2.0", id,
          result: { description: prompt.description, messages: getPromptMessages(promptName, promptArgs) },
        });
      }

    } else if (method === "tools/list") {
      responses.push({
        jsonrpc: "2.0", id,
        result: {
          tools: [
            GET_USER_CONTEXT_TOOL, GET_DAY_BLOCKS_TOOL, GET_DAY_PLAN_TOOL, PLAN_DAY_TOOL,
            CLEAR_DAY_PLAN_TOOL, LIST_PROJECTS_TOOL, GET_PROJECT_TOOL, PUSH_GANTT_MCP_TOOL,
            ARCHIVE_PROJECT_TOOL, DELETE_PROJECT_TOOL, UPDATE_ACTIVITY_GOAL_TOOL,
            CREATE_ROUTINE_TOOL, CREATE_RECURRING_ACTION_TOOL, DELETE_ROUTINE_TOOL,
            ADD_TO_DAY_PLAN_TOOL, DELETE_GOAL_TOOL, LINK_GOAL_TO_TASK_TOOL,
            CREATE_ACTIVITY_TOOL, UPDATE_ACTIVITY_TOOL, UPDATE_TASK_STATUS_TOOL,
            UPDATE_PROJECT_TOOL, DELETE_ACTIVITY_TOOL, DELETE_ACTION_TOOL,
            GET_DOCUMENT_TEMPLATE_TOOL, SAVE_DOCUMENT_TOOL, GET_DOCUMENTS_TOOL,
            DELETE_DOCUMENT_TOOL, GET_ARCHIVES_TOOL, RESTORE_ITEM_TOOL,
            CREATE_DOMAIN_TOOL, DELETE_DOMAIN_TOOL, PUSH_ASSISTANT_MESSAGE_TOOL,
          ],
        },
      });

    } else if (method === "tools/call") {
      const toolName: string = rpc.params?.name ?? "";
      const args = rpc.params?.arguments ?? {};
      try {
        let text = "";
        if (toolName === "get_user_context") {
          text = await executeGetUserContext(uid);
        } else if (toolName === "get_day_blocks") {
          text = await executeGetDayBlocks(uid);
        } else if (toolName === "get_day_plan") {
          text = await executeGetDayPlan(uid, args.date as string);
        } else if (toolName === "plan_day") {
          text = await executePlanDay(uid, args.date as string, args.items as Parameters<typeof executePlanDay>[2], (args.clearExisting as boolean) ?? false);
        } else if (toolName === "clear_day_plan") {
          text = await executeClearDayPlan(uid, args.date as string);
        } else if (toolName === "add_to_day_plan") {
          text = await executeAddToDayPlan(uid, args as Parameters<typeof executeAddToDayPlan>[1]);
        } else if (toolName === "delete_action") {
          text = await executeDeleteAction(uid, args.actionId as string);
        } else if (toolName === "list_projects") {
          text = await executeListProjects(uid);
        } else if (toolName === "get_project") {
          text = await executeGetProject(uid, args.projectId as string);
        } else if (toolName === "push_gantt") {
          text = await executePushGantt(uid, { uid, ...args });
        } else if (toolName === "update_project") {
          text = await executeUpdateProject(uid, args.projectId as string, args);
        } else if (toolName === "update_task_status") {
          text = await executeUpdateTaskStatus(uid, args.projectId as string, args.taskId as string, args.status as string);
        } else if (toolName === "archive_project") {
          text = await executeArchiveProject(uid, args.projectId as string, (args.restore as boolean) ?? false);
        } else if (toolName === "delete_project") {
          text = await executeDeleteProject(uid, args.projectId as string, (args.deleteObjective as boolean) ?? false);
        } else if (toolName === "create_activity") {
          text = await executeCreateActivity(uid, args as Parameters<typeof executeCreateActivity>[1]);
        } else if (toolName === "update_activity") {
          text = await executeUpdateActivity(uid, args.activityId as string, args);
        } else if (toolName === "update_activity_goal") {
          text = await executeUpdateActivityGoal(uid, args.activityId as string, args);
        } else if (toolName === "delete_activity") {
          text = await executeDeleteActivity(uid, args.activityId as string);
        } else if (toolName === "create_routine") {
          text = await executeCreateRoutine(uid, args as Parameters<typeof executeCreateRoutine>[1]);
        } else if (toolName === "create_recurring_action") {
          text = await executeCreateRecurringAction(uid, args as Parameters<typeof executeCreateRecurringAction>[1]);
        } else if (toolName === "delete_routine") {
          text = await executeDeleteRoutine(uid, args.routineId as string);
        } else if (toolName === "create_domain") {
          text = await executeCreateDomain(uid, args as Parameters<typeof executeCreateDomain>[1]);
        } else if (toolName === "delete_domain") {
          text = await executeDeleteDomain(uid, args.domainId as string);
        } else if (toolName === "link_goal_to_task") {
          text = await executeLinkGoalToTask(uid, args.goalId as string, (args.projectId as string) ?? null, (args.projectTaskId as string) ?? null);
        } else if (toolName === "delete_goal") {
          text = await executeDeleteGoal(uid, args.goalId as string, (args.action as string) ?? "archive");
        } else if (toolName === "get_document_template") {
          text = executeGetDocumentTemplate();
        } else if (toolName === "save_document") {
          text = await executeSaveDocument(uid, args as Parameters<typeof executeSaveDocument>[1]);
        } else if (toolName === "get_documents") {
          text = await executeGetDocuments(uid, args.projectId as string | undefined, args.taskId as string | undefined);
        } else if (toolName === "delete_document") {
          const ref = db.collection(`users/${uid}/documents`).doc(args.documentId as string);
          const snap = await ref.get();
          if (!snap.exists) {
            text = `Document introuvable : ${args.documentId}`;
          } else {
            const title = (snap.data() as Record<string, unknown>)?.title ?? args.documentId;
            await ref.delete();
            text = `✅ Document "${title}" supprimé.`;
          }
        } else if (toolName === "get_archives") {
          text = await executeGetArchives(uid);
        } else if (toolName === "restore_item") {
          text = await executeRestoreItem(uid, args.collection as string, args.itemId as string);
        } else if (toolName === "push_assistant_message") {
          text = await executePushAssistantMessage(uid, args as Parameters<typeof executePushAssistantMessage>[1]);
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
