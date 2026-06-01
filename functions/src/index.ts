import { onRequest } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";
import * as admin from "firebase-admin";
import { createHmac, timingSafeEqual } from "crypto";
import { runOrionCycle, getOrionRunCount, incrementOrionRunCount, saveOrionConfig, writeCycleLog } from "./orion";
import { getOrCreateBrief, setFocus, getFocus, setBriefFeedback, listBriefs } from "./orion_brief";
import { MODELS, getModel, logTokenUsage } from "./models";
import Anthropic from "@anthropic-ai/sdk";
import sgMail = require("@sendgrid/mail");
import { runDeterministicTask } from "./orion_tasks";
import { v4 as uuidv4 } from "uuid";
import { db, FieldValue } from "./db";
import { MCP_PROMPTS, getPromptMessages, executeGetDocumentTemplate } from "./prompts";
import {
  GET_USER_CONTEXT_TOOL, GET_DAY_BLOCKS_TOOL,
  LIST_PROJECTS_TOOL, GET_PROJECT_TOOL, PUSH_GANTT_MCP_TOOL,
  ARCHIVE_PROJECT_TOOL, DELETE_PROJECT_TOOL, UPDATE_ACTIVITY_GOAL_TOOL,
  CREATE_ROUTINE_TOOL, DELETE_ROUTINE_TOOL,
  CREATE_ACTIVITY_TOOL, UPDATE_ACTIVITY_TOOL, UPDATE_TASK_STATUS_TOOL,
  UPDATE_PROJECT_TOOL, DELETE_ACTIVITY_TOOL,
  GET_DOCUMENT_TEMPLATE_TOOL, SAVE_DOCUMENT_TOOL, GET_DOCUMENTS_TOOL,
  DELETE_DOCUMENT_TOOL, GET_ARCHIVES_TOOL, RESTORE_ITEM_TOOL,
  CREATE_DOMAIN_TOOL, DELETE_DOMAIN_TOOL, PUSH_ASSISTANT_MESSAGE_TOOL,
  GET_ASSISTANT_MESSAGES_TOOL, DELETE_ASSISTANT_MESSAGE_TOOL,
  GET_DAY_SCHEDULE_TOOL, SCHEDULE_DAY_TOOL,
  PLAN_DAY_TOOL, PLAN_WEEK_TOOL, SYNC_CALENDAR_TOOL,
  ADD_TASK_TOOL, UPDATE_TASK_TOOL, MARK_ACTION_DONE_TOOL,
} from "./tools";
import {
  validateToken, sendFcmPush, pickProject, pickStrategicObjective, checkRateLimit, todayInParis,
  executePushAssistantMessage, executeGetAssistantMessages, executeDeleteAssistantMessage,
  executeGetUserContext, executeUpdateActivityGoal,
  executeCreateRoutine,
  executeGetDayBlocks, executeCreateActivity,
  executeSaveDocument, executeGetDocuments, executeGetArchives,
  executeRestoreItem, executeCreateDomain, executeDeleteDomain, executeDeleteActivity,
  executeUpdateProject, executeUpdateTaskStatus, executeUpdateActivity,
  executeDeleteRoutine,
  executeArchiveProject, executeDeleteProject, executeListProjects, executeGetProject,
  executePushGantt, executeAddTask, executeUpdateTask, executeMarkActionDone,
  executeGetDaySchedule, executeScheduleDay,
  executePlanDay, executePlanWeek, executeSyncCalendar,
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

  const valid = await validateToken(uid, rawToken);
  if (!valid) { res.status(401).json({ error: "Invalid or revoked token" }); return; }

  const rl = await checkRateLimit(uid, "pushGantt", 30);
  if (rl.limited) { res.status(429).json({ error: `Rate limit dépassé — réessaie dans ${rl.retryAfterSecs}s` }); return; }

  let pickedProject: Record<string, unknown>;
  let pickedSO: Record<string, unknown> | undefined;
  try {
    pickedProject = pickProject(project);
    if (strategicObjective) pickedSO = pickStrategicObjective(strategicObjective);
  } catch (e) {
    res.status(400).json({ error: e instanceof Error ? e.message : String(e) });
    return;
  }

  let strategicObjectiveId: string | undefined;
  if (strategicObjective && pickedSO) {
    const objId = strategicObjective.id || uuidv4();
    strategicObjectiveId = objId;
    await db.collection(`users/${uid}/strategic_objectives`).doc(objId).set(
      { ...pickedSO, id: objId, status: "active", updatedAt: FieldValue.serverTimestamp(), createdAt: FieldValue.serverTimestamp() },
      { merge: true }
    );
  }

  const projectId = project.id || uuidv4();
  await db.collection(`users/${uid}/projects`).doc(projectId).set(
    {
      ...pickedProject,
      id: projectId,
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

// ── markPlanItemDone ─────────────────────────────────────────────────────────
//
// POST https://markplanitemdone-dzos75b65q-uc.a.run.app
// Headers: Authorization: Bearer <widget_token>
// Body: { uid, planItemId, done }
// Utilisé par le widget iOS interactif pour cocher/décocher une action sans ouvrir l'app.

export const markPlanItemDone = onRequest({ cors: true, invoker: "public" }, async (req, res) => {
  if (req.method === "OPTIONS") { res.status(204).send(""); return; }
  if (req.method !== "POST") { res.status(405).json({ error: "Method Not Allowed" }); return; }

  const authHeader = req.headers.authorization ?? "";
  if (!authHeader.startsWith("Bearer ")) {
    res.status(401).json({ error: "Missing Authorization header" }); return;
  }
  const rawToken = authHeader.slice(7).trim();

  const { uid, planItemId, done } = req.body as { uid: string; planItemId: string; done: boolean };
  if (!uid || !planItemId || typeof done !== "boolean") {
    res.status(400).json({ error: "Missing required fields: uid, planItemId, done" }); return;
  }

  const valid = await validateToken(uid, rawToken);
  if (!valid) { res.status(401).json({ error: "Invalid or revoked token" }); return; }

  const ref = db.collection(`users/${uid}/dayPlan`).doc(planItemId);
  const snap = await ref.get();
  if (!snap.exists) { res.status(404).json({ error: "Plan item not found" }); return; }

  await ref.update({ done, updatedAt: FieldValue.serverTimestamp() });
  res.status(200).json({ ok: true });
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

// ── sendMagicLink ───────────────────────────────────────────────────────────
//
// POST https://sendmagiclink-dzos75b65q-uc.a.run.app
// Body: { email, continueUrl? }
//
// Génère un lien de connexion passwordless (Admin SDK) et l'envoie via SendGrid
// avec un mail HTML brandé Productivitwo — remplace le mail générique Firebase.
// La complétion côté client reste signInWithEmailLink (inchangée).

// ⚠️ MAGIC_FROM_EMAIL doit être un expéditeur VÉRIFIÉ dans SendGrid
// (Single Sender ou domaine authentifié). Sinon SendGrid rejette l'envoi.
const MAGIC_FROM_EMAIL = "noreply@productivitwo.com";
const MAGIC_FROM_NAME = "Productivitwo";
const MAGIC_DEFAULT_CONTINUE_URL = "https://app.productivitwo.com/";

function magicLinkEmailHtml(link: string): string {
  return `<!DOCTYPE html>
<html lang="fr">
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"></head>
<body style="margin:0;padding:0;background:#0D2A1E;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#0D2A1E;padding:40px 16px;">
    <tr><td align="center">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:440px;background:#0F1F19;border:1px solid rgba(255,255,255,0.08);border-radius:20px;overflow:hidden;">
        <tr><td style="padding:36px 32px 8px;text-align:center;">
          <div style="font-size:26px;font-weight:800;color:#E6F7F2;letter-spacing:-0.5px;">Productivitwo</div>
          <div style="font-size:13px;color:#9FE1CB;margin-top:6px;">Gérez vos projets, pilotés par l'IA</div>
        </td></tr>
        <tr><td style="padding:24px 32px 8px;text-align:center;">
          <div style="font-size:15px;color:#D6EFE6;line-height:1.5;">Voici ton lien de connexion.<br>Pas de mot de passe à retenir.</div>
        </td></tr>
        <tr><td style="padding:24px 32px;text-align:center;">
          <a href="${link}" style="display:inline-block;background:#10B981;color:#06231A;text-decoration:none;font-weight:700;font-size:15px;padding:14px 28px;border-radius:999px;">Me connecter</a>
        </td></tr>
        <tr><td style="padding:0 32px 28px;text-align:center;">
          <div style="font-size:11px;color:#6E8C82;line-height:1.5;">Si le bouton ne fonctionne pas, copie ce lien dans ton navigateur :<br>
          <a href="${link}" style="color:#6BBFA3;word-break:break-all;">${link}</a></div>
          <div style="font-size:11px;color:#52685F;margin-top:20px;">Tu n'as pas demandé cette connexion ? Ignore cet email.</div>
        </td></tr>
      </table>
      <div style="font-size:11px;color:#3F5249;margin-top:20px;">© ${new Date().getFullYear()} Productivitwo</div>
    </td></tr>
  </table>
</body>
</html>`;
}

// Throttle anti-abus : max 5 envois / heure / adresse email (endpoint public).
async function checkMagicLinkThrottle(email: string): Promise<boolean> {
  const id = createHmac("sha256", "magic-link-throttle").update(email).digest("hex").slice(0, 40);
  const ref = db.doc(`magic_link_throttle/${id}`);
  const now = Date.now();
  const HOUR_MS = 60 * 60 * 1000;
  const snap = await ref.get();
  const data = (snap.data() ?? {}) as { count?: number; windowStart?: number };
  const expired = now - (data.windowStart ?? now) >= HOUR_MS;
  const count = expired ? 0 : (data.count ?? 0);
  if (count >= 5) return true;
  await ref.set(
    { count: count + 1, windowStart: expired ? now : (data.windowStart ?? now) },
    { merge: true },
  );
  return false;
}

export const sendMagicLink = onRequest(
  { cors: true, invoker: "public", secrets: ["SENDGRID_API_KEY"] },
  async (req, res) => {
    if (req.method === "OPTIONS") { res.status(204).send(""); return; }
    if (req.method !== "POST") { res.status(405).json({ error: "Method Not Allowed" }); return; }

    const { email, continueUrl } = req.body as { email?: string; continueUrl?: string };
    const cleanEmail = (email ?? "").trim().toLowerCase();
    if (!cleanEmail || !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(cleanEmail)) {
      res.status(400).json({ error: "Adresse email invalide" });
      return;
    }

    const apiKey = process.env.SENDGRID_API_KEY;
    if (!apiKey) { res.status(500).json({ error: "SENDGRID_API_KEY non configurée" }); return; }

    if (await checkMagicLinkThrottle(cleanEmail)) {
      res.status(429).json({ error: "Trop de demandes. Réessaie dans une heure." });
      return;
    }

    try {
      const url = continueUrl && continueUrl.startsWith("https://")
        ? continueUrl
        : MAGIC_DEFAULT_CONTINUE_URL;
      const link = await admin.auth().generateSignInWithEmailLink(cleanEmail, {
        url,
        handleCodeInApp: true,
      });

      sgMail.setApiKey(apiKey);
      await sgMail.send({
        to: cleanEmail,
        from: { email: MAGIC_FROM_EMAIL, name: MAGIC_FROM_NAME },
        subject: "Ton lien de connexion Productivitwo",
        text:
          `Connecte-toi à Productivitwo en ouvrant ce lien :\n\n${link}\n\n` +
          `Tu n'as pas demandé cette connexion ? Ignore cet email.`,
        html: magicLinkEmailHtml(link),
      });

      res.status(200).json({ ok: true });
    } catch (e: any) {
      console.error("sendMagicLink error:", e?.response?.body ?? e?.message ?? e);
      res.status(500).json({ error: "Envoi impossible" });
    }
  },
);

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
            GET_USER_CONTEXT_TOOL, GET_DAY_BLOCKS_TOOL,
            LIST_PROJECTS_TOOL, GET_PROJECT_TOOL, PUSH_GANTT_MCP_TOOL,
            ARCHIVE_PROJECT_TOOL, DELETE_PROJECT_TOOL, UPDATE_ACTIVITY_GOAL_TOOL,
            CREATE_ROUTINE_TOOL, DELETE_ROUTINE_TOOL,
            CREATE_ACTIVITY_TOOL, UPDATE_ACTIVITY_TOOL, UPDATE_TASK_STATUS_TOOL,
            UPDATE_PROJECT_TOOL, DELETE_ACTIVITY_TOOL,
            GET_DOCUMENT_TEMPLATE_TOOL, SAVE_DOCUMENT_TOOL, GET_DOCUMENTS_TOOL,
            DELETE_DOCUMENT_TOOL, GET_ARCHIVES_TOOL, RESTORE_ITEM_TOOL,
            CREATE_DOMAIN_TOOL, DELETE_DOMAIN_TOOL, PUSH_ASSISTANT_MESSAGE_TOOL,
            GET_ASSISTANT_MESSAGES_TOOL, DELETE_ASSISTANT_MESSAGE_TOOL,
            GET_DAY_SCHEDULE_TOOL, SCHEDULE_DAY_TOOL,
            PLAN_DAY_TOOL, PLAN_WEEK_TOOL, SYNC_CALENDAR_TOOL,
            ADD_TASK_TOOL, UPDATE_TASK_TOOL, MARK_ACTION_DONE_TOOL,
          ],
        },
      });

    } else if (method === "tools/call") {
      const rl = await checkRateLimit(uid, "mcpToolCall", 100);
      if (rl.limited) {
        responses.push({ jsonrpc: "2.0", id, error: { code: -32000, message: `Rate limit dépassé — réessaie dans ${rl.retryAfterSecs}s` } });
        continue;
      }
      const toolName: string = rpc.params?.name ?? "";
      const args = rpc.params?.arguments ?? {};
      try {
        let text = "";
        if (toolName === "get_user_context") {
          text = await executeGetUserContext(uid);
        } else if (toolName === "get_day_blocks") {
          text = await executeGetDayBlocks(uid);
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
        } else if (toolName === "delete_routine") {
          text = await executeDeleteRoutine(uid, args.routineId as string);
        } else if (toolName === "create_domain") {
          text = await executeCreateDomain(uid, args as Parameters<typeof executeCreateDomain>[1]);
        } else if (toolName === "delete_domain") {
          text = await executeDeleteDomain(uid, args.domainId as string);
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
            await ref.update({ deleted: true });
            text = `✅ Document "${title}" supprimé.`;
          }
        } else if (toolName === "get_archives") {
          text = await executeGetArchives(uid);
        } else if (toolName === "restore_item") {
          text = await executeRestoreItem(uid, args.collection as string, args.itemId as string);
        } else if (toolName === "push_assistant_message") {
          text = await executePushAssistantMessage(uid, args as Parameters<typeof executePushAssistantMessage>[1]);
        } else if (toolName === "get_assistant_messages") {
          text = await executeGetAssistantMessages(uid);
        } else if (toolName === "delete_assistant_message") {
          text = await executeDeleteAssistantMessage(uid, args.messageId as string);
        } else if (toolName === "get_day_schedule") {
          text = await executeGetDaySchedule(uid, args.date as string);
        } else if (toolName === "schedule_day") {
          text = await executeScheduleDay(uid, args.date as string, args.blocks as Parameters<typeof executeScheduleDay>[2]);
        } else if (toolName === "plan_day") {
          text = await executePlanDay(uid, args as Parameters<typeof executePlanDay>[1]);
        } else if (toolName === "plan_week") {
          text = await executePlanWeek(uid, args as Parameters<typeof executePlanWeek>[1]);
        } else if (toolName === "sync_calendar") {
          text = await executeSyncCalendar(uid, args.date as string | undefined);
        } else if (toolName === "add_task") {
          text = await executeAddTask(uid, args.projectId as string, args as Parameters<typeof executeAddTask>[2]);
        } else if (toolName === "update_task") {
          text = await executeUpdateTask(uid, args.projectId as string, args.taskId as string, args);
        } else if (toolName === "mark_action_done") {
          text = await executeMarkActionDone(
            uid,
            args.projectId as string,
            args.taskId as string,
            args.actionId as string,
            args.done as boolean,
          );
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

// ── orionWebhook ──────────────────────────────────────────────────────────────
//
// POST https://orionwebhook-dzos75b65q-uc.a.run.app
// Body: { uid, token }
// Déclenché par l'app sur actions clés (save config, tâche validée, réponse user)

export const orionWebhook = onRequest(
  { cors: true, invoker: "public", secrets: ["ANTHROPIC_API_KEY"] },
  async (req, res) => {
    if (req.method === "OPTIONS") { res.status(204).send(""); return; }
    if (req.method !== "POST") { res.status(405).json({ error: "Method Not Allowed" }); return; }

    const { uid, token, taskId } = req.body as { uid?: string; token?: string; taskId?: string };
    if (!uid || !token) { res.status(400).json({ error: "uid et token requis" }); return; }

    const valid = await validateToken(uid, token);
    if (!valid) { res.status(401).json({ error: "Token invalide ou révoqué" }); return; }

    try {
      if (taskId) {
        // Tâche déterministe — pas d'appel LLM, coût $0
        const result = await runDeterministicTask(uid, taskId);
        await writeCycleLog(uid, { userNeeds: `[déterministe] ${taskId}`, userReply: "", ...result, skipped: result.skipped });
        res.status(200).json({ success: true, ...result });
      } else {
        const result = await runOrionCycle(uid);
        res.status(200).json({ success: true, ...result });
      }
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      console.error(`ORION webhook erreur uid=${uid}:`, msg);
      res.status(500).json({ error: msg });
    }
  }
);

// ── orionSaveConfig ───────────────────────────────────────────────────────────
//
// POST { uid, token, userNeeds?, userReply? }
// Sauvegarde la config ORION puis déclenche un cycle.

// ── githubWebhook — notif push quand une PR est ouverte ─────────────────────
//
// Configuré dans GitHub (repo Settings → Webhooks), content-type application/json,
// event "Pull requests". Vérifie X-Hub-Signature-256 (HMAC du rawBody avec
// GITHUB_WEBHOOK_SECRET), puis pousse une notif FCM au dev (uid = GITHUB_NOTIFY_UID).

function verifyGithubSignature(raw: Buffer, header: string, secret: string): boolean {
  if (!secret || !header.startsWith("sha256=")) return false;
  const expected = "sha256=" + createHmac("sha256", secret).update(raw).digest("hex");
  const a = Buffer.from(header);
  const b = Buffer.from(expected);
  return a.length === b.length && timingSafeEqual(a, b);
}

export const githubWebhook = onRequest(
  { invoker: "public", secrets: ["GITHUB_WEBHOOK_SECRET"] },
  async (req, res) => {
    if (req.method !== "POST") { res.status(405).send("Method Not Allowed"); return; }

    const secret = process.env.GITHUB_WEBHOOK_SECRET ?? "";
    const sig = req.get("x-hub-signature-256") ?? "";
    const raw = (req as unknown as { rawBody?: Buffer }).rawBody;
    if (!raw || !verifyGithubSignature(raw, sig, secret)) {
      res.status(401).send("Invalid signature");
      return;
    }

    if (req.get("x-github-event") !== "pull_request") { res.status(200).send("ignored"); return; }

    const body = req.body as {
      action?: string;
      number?: number;
      pull_request?: { title?: string; html_url?: string };
      repository?: { full_name?: string };
    };
    if (body.action !== "opened" && body.action !== "ready_for_review") {
      res.status(200).send("ignored");
      return;
    }

    const uid = process.env.GITHUB_NOTIFY_UID;
    if (uid) {
      const num = body.number ?? 0;
      const title = body.pull_request?.title ?? "";
      const url = body.pull_request?.html_url ?? "";
      await sendFcmPush(uid, `📥 PR #${num} à valider`, title, { type: "github_pr", url });
    }

    res.status(200).send("ok");
  }
);

export const orionSaveConfig = onRequest(
  { cors: true, invoker: "public", secrets: ["ANTHROPIC_API_KEY"] },
  async (req, res) => {
    if (req.method === "OPTIONS") { res.status(204).send(""); return; }
    if (req.method !== "POST") { res.status(405).json({ error: "Method Not Allowed" }); return; }

    const { uid, token, userNeeds, userReply, isOnboarding } = req.body as {
      uid?: string; token?: string;
      userNeeds?: string; userReply?: string;
      isOnboarding?: boolean;
    };
    if (!uid || !token) { res.status(400).json({ error: "uid et token requis" }); return; }

    const valid = await validateToken(uid, token);
    if (!valid) { res.status(401).json({ error: "Token invalide ou révoqué" }); return; }

    await saveOrionConfig(uid, { userNeeds, userReply });

    try {
      const result = await runOrionCycle(uid, { skipCount: isOnboarding === true });
      res.status(200).json({ success: true, configSaved: true, ...result });
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      console.error(`ORION saveConfig erreur uid=${uid}:`, msg);
      res.status(500).json({ error: msg });
    }
  }
);

// ── orionRunCount ─────────────────────────────────────────────────────────────
//
// GET ?uid=&token= — retourne le nombre de cycles ORION du jour

export const orionRunCount = onRequest({ cors: true, invoker: "public" }, async (req, res) => {
  if (req.method === "OPTIONS") { res.status(204).send(""); return; }

  const uid = (req.query.uid as string) ?? "";
  const token = (req.query.token as string) ?? "";
  if (!uid || !token) { res.status(400).json({ error: "uid et token requis" }); return; }

  const valid = await validateToken(uid, token);
  if (!valid) { res.status(401).json({ error: "Token invalide ou révoqué" }); return; }

  const today = todayInParis();
  const count = await getOrionRunCount(uid, today);
  res.status(200).json({ count, max: 5, date: today });
});

// ── ORION Brief (v2) ──────────────────────────────────────────────────────────
// Auth via Firebase ID token. Une seule fonction, méthode dans le body :
//   { action: "getBrief" | "setFocus" | "setFeedback", ... }

export const orionBrief = onRequest(
  { cors: true, invoker: "public", secrets: ["ANTHROPIC_API_KEY"] },
  async (req, res) => {
    if (req.method === "OPTIONS") { res.status(204).send(""); return; }
    if (req.method !== "POST") { res.status(405).json({ error: "Method Not Allowed" }); return; }

    const authHeader = req.headers.authorization ?? "";
    if (!authHeader.startsWith("Bearer ")) {
      res.status(401).json({ error: "Missing Authorization header" }); return;
    }
    const idToken = authHeader.slice(7).trim();

    let uid: string;
    try {
      uid = (await admin.auth().verifyIdToken(idToken)).uid;
    } catch {
      res.status(401).json({ error: "Token invalide ou expiré" }); return;
    }

    const { action, focus, feedback, date, limit } = req.body as {
      action?: "getBrief" | "setFocus" | "setFeedback" | "getFocus" | "history";
      focus?: string;
      feedback?: "useful" | "skip";
      date?: string;
      limit?: number;
    };

    try {
      if (action === "getFocus") {
        const f = await getFocus(uid);
        res.status(200).json({ focus: f });
        return;
      }
      if (action === "setFocus") {
        const newFocus = (focus ?? "").trim();
        if (!newFocus) { res.status(400).json({ error: "focus requis" }); return; }
        if (newFocus.length > 280) { res.status(400).json({ error: "focus trop long (max 280)" }); return; }
        await setFocus(uid, newFocus);
        res.status(200).json({ success: true, focus: newFocus });
        return;
      }
      if (action === "history") {
        const briefs = await listBriefs(uid, Math.min(limit ?? 30, 90));
        res.status(200).json({ briefs });
        return;
      }
      if (action === "setFeedback") {
        if (!date || !feedback) { res.status(400).json({ error: "date et feedback requis" }); return; }
        if (feedback !== "useful" && feedback !== "skip") {
          res.status(400).json({ error: "feedback doit être 'useful' ou 'skip'" }); return;
        }
        await setBriefFeedback(uid, date, feedback);
        res.status(200).json({ success: true });
        return;
      }
      // Default : getBrief
      const brief = await getOrCreateBrief(uid);
      res.status(200).json(brief);
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      if (msg === "FOCUS_NOT_SET") {
        res.status(412).json({ code: "FOCUS_NOT_SET", error: "Définis ton focus du moment d'abord." });
        return;
      }
      console.error("orionBrief error:", msg);
      res.status(500).json({ error: msg });
    }
  }
);

// ── orionCron — DÉSACTIVÉ (remplacé par orionBrief lazy-generation) ──────────
//
// L'ancien cycle ORION (avec les 20 conditions, messages dispersés) est mis en
// sommeil. La nouvelle expérience passe par `orionBrief` qui génère un brief
// quotidien à la demande quand l'utilisateur ouvre l'app.
//
// Le schedule est conservé mais le body retourne early — économise les tokens
// tout en gardant la structure pour rollback éventuel.

export const orionCron = onSchedule(
  { schedule: "every 24 hours", timeZone: "Europe/Paris", secrets: ["ANTHROPIC_API_KEY"] },
  async () => {
    console.log("ORION cron (legacy) : désactivé — remplacé par orionBrief");
    return;
  }
);

// ── structureProject ──────────────────────────────────────────────────────────
//
// POST https://structureproject-dzos75b65q-uc.a.run.app
// Headers: Authorization: Bearer <firebase-id-token>
// Body: { title, domainName?, domainId?, endDate (YYYY-MM-DD), ideas }
//
// Consomme 1 action stratégique ORION. Crée le projet structuré dans Firestore.

const STRUCTURE_MAX_RUNS = 5; // quota journalier dédié création de projets (partagé avec ORION)

export const structureProject = onRequest(
  { cors: true, invoker: "public", secrets: ["ANTHROPIC_API_KEY"] },
  async (req, res) => {
    if (req.method === "OPTIONS") { res.status(204).send(""); return; }
    if (req.method !== "POST") { res.status(405).json({ error: "Method Not Allowed" }); return; }

    // Auth via Firebase ID token
    const authHeader = req.headers.authorization ?? "";
    if (!authHeader.startsWith("Bearer ")) {
      res.status(401).json({ error: "Missing Authorization header" }); return;
    }
    const idToken = authHeader.slice(7).trim();

    let uid: string;
    try {
      const decoded = await admin.auth().verifyIdToken(idToken);
      uid = decoded.uid;
    } catch {
      res.status(401).json({ error: "Token invalide ou expiré" }); return;
    }

    const { title, domainName, domainId, endDate, ideas } = req.body as {
      title?: string;
      domainName?: string;
      domainId?: string;
      endDate?: string;
      ideas?: string;
    };

    if (!title || !endDate || !ideas) {
      res.status(400).json({ error: "Champs requis : title, endDate, ideas" }); return;
    }

    // Quota journalier
    const today = todayInParis();
    const count = await getOrionRunCount(uid, today);
    if (count >= STRUCTURE_MAX_RUNS) {
      res.status(429).json({ error: `Limite journalière atteinte (${count}/${STRUCTURE_MAX_RUNS} actions stratégiques)` }); return;
    }

    const apiKey = process.env.ANTHROPIC_API_KEY;
    if (!apiKey) { res.status(500).json({ error: "ANTHROPIC_API_KEY non configurée" }); return; }

    // Appel Claude
    const client = new Anthropic({ apiKey });
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
      model: MODELS.HAIKU,
      max_tokens: 2048,
      messages: [{ role: "user", content: prompt }],
    });
    logTokenUsage("structure_project", MODELS.HAIKU, message.usage);

    const raw = (message.content[0] as { type: string; text: string }).text.trim();
    const jsonMatch = raw.match(/\{[\s\S]*\}/);
    if (!jsonMatch) {
      res.status(500).json({ error: "ORION n'a pas retourné de JSON valide" }); return;
    }

    const structured: {
      phases: Array<{ label: string; startDate: string; endDate: string }>;
      tasks: Array<{ title: string; phaseIndex: number; startDate: string; endDate: string; isMilestone: boolean; actions?: string[] }>;
    } = JSON.parse(jsonMatch[0]);

    // Construire le projet avec IDs
    const projectId = uuidv4();
    const phases = structured.phases.map((p) => ({
      id: uuidv4(),
      label: p.label,
      color: null,
      startDate: p.startDate,
      endDate: p.endDate,
    }));
    const tasks = structured.tasks.map((t) => ({
      id: uuidv4(),
      title: t.title,
      description: null,
      phaseId: phases[t.phaseIndex]?.id ?? null,
      groupLabel: null,
      startDate: t.startDate,
      endDate: t.endDate,
      isMilestone: t.isMilestone ?? false,
      color: null,
      barLabel: null,
      status: "pending",
      actions: (t.actions ?? []).map((a: string) => ({
        id: uuidv4(),
        title: a,
        done: false,
        doneAt: null,
        createdAt: new Date().toISOString(),
      })),
    }));

    await db.collection(`users/${uid}/projects`).doc(projectId).set({
      id: projectId,
      title,
      description: null,
      strategicObjectiveId: null,
      domainId: domainId ?? null,
      startDate: today,
      endDate,
      status: "active",
      phases,
      tasks,
      createdBy: uid,
      sourceType: "orion_mobile",
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });

    // Consommer 1 action stratégique
    await incrementOrionRunCount(uid, today);

    res.status(200).json({
      success: true,
      projectId,
      phasesCount: phases.length,
      tasksCount: tasks.length,
    });
  }
);

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
      type: "object" as const,
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
      type: "object" as const,
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
      type: "object" as const,
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
      type: "object" as const,
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
      type: "object" as const,
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
      type: "object" as const,
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
      type: "object" as const,
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
      type: "object" as const,
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
  1. Annonce le domaine, propose 4-5 noms + "Autre" → l'utilisateur choisit/valide. DÈS qu'il valide le nom → appelle set_structure_preview (le domaine apparaît dans la mindmap).
  2. BALAYAGE DES ACTIVITÉS — c'est ICI qu'on construit le vrai système trackable.
     Demande concrètement ce qu'il fait (ou veut suivre) dans ce domaine, avec les DEUX lentilles :
       • DURÉE (type "time") : ce qu'on mesure en temps — ex: Sport, Stratégie, Cuisiner → propose TOUJOURS un goalMin réaliste (infère une valeur sensée selon l'activité et ANNONCE-la, ex: "Cuisiner ~30 min/j", "Sieste ~20 min" ; l'utilisateur ajuste s'il veut). Ne laisse JAMAIS une activité temps sans durée.
       • FRÉQUENCE (type "habit") : ce qu'on coche — ex: Boire de l'eau (daily ×8), Footing (weekly ×3), Ménage (weekly), Laver la voiture (monthly) → habitFreq + habitTarget.
     Pour chaque activité, déduis la bonne lentille ; si habit, déduis fréquence + cible. Si une cible est importante et incertaine, demande — ne devine pas.
  3. Vise jusqu'à ~5 activités/domaine selon son appétit — sans remplir artificiellement, sans plafonner un power-user (il complétera dans l'app).
  4. Reformule la courte liste ("Dans X, tu suivras : … — ça te va ?"), puis passe au domaine suivant.

L'utilisateur peut dire "passe" pour sauter un domaine, "stop"/"c'est bon" pour valider et aller en Phase 4.
Maximum 6-7 domaines — propose de fusionner s'il en veut trop.

━━━ PAIRE FRÉQUENCE + TEMPS (PAR DÉFAUT) ━━━
Pour que l'utilisateur puisse tout tracer sans frustration ("je l'ai fait, mais où je note le temps ?"), dès qu'une habitude correspond à une action qui prend un temps mesurable, crée DEUX activités appairées :
  • FRÉQUENCE (type "habit") — forme VERBALE (l'action) : "Faire la vaisselle", "Boire de l'eau", "Lire", "Aller à la mer" → l'utilisateur coche.
  • TEMPS (type "time") — le NOM sans verbe (la chose) : "Vaisselle", "Hydratation", "Lecture", "Bain de mer" → l'utilisateur chronomètre.
C'est le comportement PAR DÉFAUT (ne demande pas à chaque fois ; mentionne-le brièvement une fois en début de balayage). N'appaire pas ce qui n'a aucune durée sensée (ex: peser son poids). Pour un appétit "essentiel", reste plus léger sur le doublement.

━━━ CAS SOMMEIL (et activités à très longue durée) ━━━
Si l'utilisateur veut suivre son SOMMEIL, crée un DOMAINE dédié "Sommeil" (et non une activité dans Santé). Raison : ~7-8h/nuit écraseraient le temps de toutes les autres activités du domaine et fausseraient sa vision du temps réellement réparti. Même logique pour toute activité au temps disproportionné.

━━━ MINDMAP LIVE (set_structure_preview) — APPEL FRÉQUENT, DÈS LE DÉBUT ━━━
L'utilisateur voit une mindmap se dessiner EN DIRECT à côté du chat. C'est OBLIGATOIRE et FRÉQUENT.
⚠️ IMPORTANT : set_structure_preview ne crée RIEN en base — c'est juste l'APERÇU VISUEL. La règle "ne rien créer avant validation" NE s'applique PAS à cet outil. Appelle-le LIBREMENT et SOUVENT, pendant toute la conversation, BIEN AVANT la Phase 4.
Quand l'appeler (envoie TOUJOURS la structure complète à jour) :
  - DÈS qu'un domaine est nommé/validé (même sans activités encore) → le domaine apparaît dans la mindmap.
  - Après le balayage des activités de chaque domaine (avec les paires fréquence/temps).
  - Après tout ajout/ajustement.
Mets center = le prénom de l'utilisateur si tu le connais, sinon "Ma vie". C'est le moment fort : voir sa vie s'organiser au fil de l'échange.

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

⚠️ NE CRÉE RIEN DANS PRODUCTIVITWO (create_domain, create_activity, push_gantt) AVANT QUE L'UTILISATEUR DISE "stop", "c'est bon", "go", "parfait" ou équivalent. (EXCEPTION : set_structure_preview — l'aperçu visuel — s'appelle librement et souvent AVANT validation ; il ne crée rien en base.)

PHASE 4 — CRÉATION (UN SEUL appel create_workspace, après validation)
La structure a été co-construite (domaines + activités + routines via le balayage ; projet présenté/validé si applicable). Pour tout créer, appelle **create_workspace UNE SEULE FOIS** avec l'ensemble :
- domains[] : chaque domaine avec SES activités.
- Pour chaque activité : type "time" (goalMin réaliste 15-30) OU type "habit" (TOUJOURS habitFreq daily/weekly/monthly + habitTarget ; jamais "daily ×1" par défaut sans raison).
- ⚠️ ROUTINES / PAIRES — ESSENTIEL, ne livre JAMAIS un système sans ses routines : pour chaque activité ayant une durée sensée, inclus la PAIRE — l'activité "time" (nom, ex "Vaisselle") ET la routine "habit" (verbe, ex "Faire la vaisselle") avec linkedActivityName = le nom de l'activité temps. ("Boire de l'eau" → linkedActivityName "Hydratation".) Pas de paire pour ce qui n'a pas de durée (ex: peser son poids).
- project (optionnel) : UNIQUEMENT si un objectif ~3 mois a été validé (cf. ci-dessous) — strategicObjective {title, kpiTarget}, phases, tasks (dates YYYY-MM-DD), durée ~3 mois.

⚠️ N'utilise PAS create_domain / create_activity / push_gantt séparément : create_workspace fait tout d'un coup (rapide, fiable).

DÉCISION PROJET (pendant la conversation, AVANT create_workspace) :
- Demande : "Y a-t-il un objectif concret que tu aimerais atteindre d'ici ~3 mois ?"
- Si OUI → présente le plan (phases = étapes + 3-5 tâches/phase) dans ta réponse texte ; le Gantt se dessine en direct sous le chat → laisse-le ajuster (1-2 échanges) → une fois validé, inclus ce projet dans l'appel create_workspace.
- Si NON/flou → pas de project ; dis-lui qu'il pourra en lancer un plus tard avec l'assistant.

Message final enthousiaste (juste après create_workspace) : annonce que le système est prêt, et explique la suite en 3 points :
   • Ouvre l'app et commence à tracker ce que tu fais.
   • Pour créer autant de projets Gantt que tu veux et aller plus loin au quotidien : connecte Claude depuis l'app web et travaille directement avec lui (il peut créer/ajuster tes projets, programmes, etc.).
   • Reviens ici dans "Vision" une fois par mois pour faire évoluer ta stratégie, tes domaines et tes activités.

━━━ STYLE ━━━
- Tutoiement naturel et chaleureux
- Phrases courtes, questions ouvertes
- Reformule avant de proposer (montre que tu as écouté)
- En Phase 3 : utilise une mise en forme claire pour les domaines proposés
- En Phase 4 : sois enthousiaste, c'est le moment fort de l'expérience
- TOUJOURS terminer ton tour par un message à l'utilisateur (au moins une phrase qui confirme/enchaîne, ex: "Noté ✓ — on continue ?"). Ne réponds JAMAIS uniquement par un appel d'outil silencieux : même quand tu mets à jour la mindmap, accompagne-le d'un mot.`;

const ONBOARDING_TOOLS = [
  {
    name: "create_domain",
    description: "Crée un domaine de vie dans Productivitwo. À appeler seulement après validation explicite de la structure par l'utilisateur.",
    input_schema: {
      type: "object" as const,
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
      type: "object" as const,
      properties: {
        name: { type: "string", description: "Nom de l'activité" },
        domainName: { type: "string", description: "Nom exact du domaine dans lequel créer l'activité" },
        type: { type: "string", enum: ["time", "habit"], description: "time = tracking durée, habit = tracking fréquence" },
        goalMin: { type: "number", description: "Objectif quotidien en minutes (type time)" },
        habitFreq: { type: "string", enum: ["daily", "weekly", "monthly"], description: "Période de la fréquence (type habit) — quotidien / hebdo / mensuel" },
        habitTarget: { type: "number", description: "Cible par période (type habit) — ex: 3 = 3×/semaine, 8 = 8×/jour, 1 = 1×/mois" },
        unit: { type: "string", description: "Unité optionnelle (ex: verres, pages, km)" },
        linkedActivityName: { type: "string", description: "Pour une ROUTINE appairée : le nom EXACT de l'activité TEMPS parente (déjà créée juste avant). Ex: routine 'Faire la vaisselle' → linkedActivityName 'Vaisselle'. Permet de retrouver la routine en lançant l'activité." },
      },
      required: ["name", "domainName", "type"],
    },
  },
  {
    name: "push_gantt",
    description: "Crée le premier projet Gantt représentant la progression état présent → vision future.",
    input_schema: {
      type: "object" as const,
      properties: {
        title: { type: "string", description: "Titre du projet (personnalisé, pas générique)" },
        startDate: { type: "string", description: "YYYY-MM-DD (aujourd'hui)" },
        endDate: { type: "string", description: "YYYY-MM-DD (6-9 mois)" },
        strategicObjective: {
          type: "object",
          description: "Objectif stratégique = le RÉSULTAT visé du projet (le 'pourquoi', au-dessus des étapes/tâches). À fournir systématiquement.",
          properties: {
            title: { type: "string", description: "Le résultat visé formulé comme un cap (ex: 'Lancer mon activité de coaching')" },
            kpiTarget: { type: "string", description: "Indicateur de succès mesurable (ex: '5 clients réguliers', '10k€/mois')" },
          },
          required: ["title"],
        },
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
  {
    name: "set_structure_preview",
    description: "Met à jour la MINDMAP visuelle affichée à l'utilisateur EN LIVE pendant la conversation. Appelle-le dès que la structure proposée évolue (un domaine nommé, les activités d'un domaine balayées, un ajustement). Envoie TOUJOURS la structure COMPLÈTE et à jour (tous les domaines + activités connus jusque-là), jamais un delta.",
    input_schema: {
      type: "object" as const,
      properties: {
        center: { type: "string", description: "Libellé du nœud central (prénom de l'utilisateur, ou 'Ma vie')" },
        domains: {
          type: "array",
          items: {
            type: "object" as const,
            properties: {
              name: { type: "string" },
              activities: {
                type: "array",
                items: {
                  type: "object" as const,
                  properties: {
                    name: { type: "string" },
                    type: { type: "string", enum: ["time", "habit"] },
                    goalMin: { type: "number", description: "Minutes/jour visées (activités type 'time' uniquement, si une durée a été évoquée)" },
                    parent: { type: "string", description: "Pour une routine appairée : nom de l'activité TEMPS parente (nichage visuel). Ex: 'Faire la vaisselle' → parent 'Vaisselle'." },
                  },
                },
              },
            },
          },
        },
      },
      required: ["domains"],
    },
  },
  {
    name: "create_workspace",
    description: "Crée TOUTE la structure validée d'un seul coup (domaines + activités + routines + projet Gantt optionnel). À utiliser POUR L'ONBOARDING à la place de create_domain/create_activity/push_gantt : appelle-le UNE seule fois, après validation de l'utilisateur. Rapide et atomique. Déclenche la fin de l'onboarding.",
    input_schema: {
      type: "object" as const,
      properties: {
        domains: {
          type: "array",
          items: {
            type: "object" as const,
            properties: {
              name: { type: "string" },
              color: { type: "string", description: "Couleur hex optionnelle (ex: #4A90E2)" },
              activities: {
                type: "array",
                items: {
                  type: "object" as const,
                  properties: {
                    name: { type: "string" },
                    type: { type: "string", enum: ["time", "habit"] },
                    goalMin: { type: "number", description: "Minutes/jour (type time)" },
                    habitFreq: { type: "string", enum: ["daily", "weekly", "monthly"], description: "Période (type habit)" },
                    habitTarget: { type: "number", description: "Cible par période (type habit) — ex: 3 = 3×/sem" },
                    unit: { type: "string" },
                    linkedActivityName: { type: "string", description: "Pour une ROUTINE : nom de l'activité temps parente (présente dans ce même appel)" },
                  },
                  required: ["name", "type"],
                },
              },
            },
            required: ["name"],
          },
        },
        project: {
          type: "object",
          description: "Projet Gantt — seulement si un objectif ~3 mois a été validé.",
          properties: {
            title: { type: "string" },
            startDate: { type: "string", description: "YYYY-MM-DD" },
            endDate: { type: "string", description: "YYYY-MM-DD" },
            strategicObjective: { type: "object", properties: { title: { type: "string" }, kpiTarget: { type: "string" } } },
            phases: { type: "array", items: { type: "object", properties: { name: { type: "string" }, startDate: { type: "string" }, endDate: { type: "string" } } } },
            tasks: { type: "array", items: { type: "object", properties: { name: { type: "string" }, phase: { type: "string" }, startDate: { type: "string" }, endDate: { type: "string" }, milestone: { type: "boolean" }, actions: { type: "array", items: { type: "string" } } } } },
          },
        },
      },
      required: ["domains"],
    },
  },
  {
    name: "complete_onboarding",
    description: "Clôture l'onboarding une fois la structure créée (domaines + activités, et projet SI pertinent). À appeler en DERNIER, juste avant le message final. Marque la config comme terminée — indépendant de la création d'un projet.",
    input_schema: {
      type: "object" as const,
      properties: {
        summary: { type: "string", description: "Récap en 1 phrase de ce qui a été mis en place (optionnel)" },
      },
    },
  },
];

type OnboardingTool = {
  notification: string;
  output: string;
};

async function executeOnboardingTool(
  uid: string,
  toolName: string,
  input: Record<string, unknown>,
  domainMap: Record<string, string>,
  activityMap: Record<string, string> = {},
): Promise<OnboardingTool> {
  if (toolName === "create_workspace") {
    type WsAct = { name: string; type?: string; goalMin?: number; habitFreq?: string; habitTarget?: number; unit?: string; linkedActivityName?: string };
    type WsDom = { name: string; color?: string; activities?: WsAct[] };
    const ws = input as {
      domains?: WsDom[];
      project?: {
        title?: string; startDate?: string; endDate?: string;
        strategicObjective?: { title?: string; kpiTarget?: string };
        phases?: Array<{ name: string; startDate?: string; endDate?: string }>;
        tasks?: Array<{ name: string; phase?: string; startDate?: string; endDate?: string; milestone?: boolean; actions?: string[] }>;
      };
    };
    // Robustesse : le modèle envoie parfois `domains`/`project`/`activities` en string JSON
    // au lieu de tableaux/objets. Sans coercition, `for...of` sur une string itère caractère
    // par caractère → des milliers de docs sans nom (incident 2026-05-31 : 9987 domaines vides).
    // On coerce, on valide la forme, et on n'écrit JAMAIS un doc sans nom non vide.
    const coerce = <T>(v: unknown): T | undefined => {
      if (typeof v === "string") { try { return JSON.parse(v) as T; } catch { return undefined; } }
      return v as T | undefined;
    };
    const asNamedArray = <T extends { name?: unknown }>(v: unknown): T[] => {
      const arr = coerce<T[]>(v);
      if (!Array.isArray(arr)) return [];
      return arr.filter((x): x is T => !!x && typeof x === "object" && typeof x.name === "string" && (x.name as string).trim().length > 0);
    };
    const domains = asNamedArray<WsDom>(ws.domains);
    // Garde-fou anti-emballement : un onboarding normal produit ~5-15 domaines.
    if (domains.length > 100) {
      return {
        notification: `⚠️ create_workspace ignoré (${domains.length} domaines — anormal)`,
        output: `Erreur : ${domains.length} domaines reçus, payload probablement malformé. Rien n'a été créé. Renvoie une structure normale (≤ ~15 domaines, en tableau JSON et non en chaîne).`,
      };
    }
    const project = coerce<typeof ws.project>(ws.project);
    const batch = db.batch();
    const freqMap: Record<string, number> = { daily: 0, weekly: 1, monthly: 2 };
    const dMap: Record<string, string> = {};
    const aMap: Record<string, string> = {};
    let nDom = 0, nAct = 0;
    for (const d of domains) {
      const id = uuidv4(); dMap[d.name] = id; nDom++;
      batch.set(db.collection(`users/${uid}/domains`).doc(id), {
        id, name: d.name, goalMinDay: null, autoGoal: true,
        colorValue: d.color ? hexToColorValue(d.color) : null,
        createdAt: FieldValue.serverTimestamp(),
      });
    }
    const allActs: Array<{ a: WsAct; domainId: string | null }> = [];
    for (const d of domains) for (const a of asNamedArray<WsAct>(d.activities)) allActs.push({ a, domainId: dMap[d.name] ?? null });
    // 2 passes : activités temps d'abord (pour résoudre linkedActivityName), puis habitudes.
    for (const pass of ["time", "habit"] as const) {
      for (const { a, domainId } of allActs) {
        const isHabit = a.type === "habit";
        if ((pass === "time") === isHabit) continue;
        const id = uuidv4(); aMap[a.name] = id; nAct++;
        batch.set(db.collection(`users/${uid}/activities`).doc(id), {
          id, name: a.name, domainId,
          type: isHabit ? "habit" : "time", role: "generic",
          goalMin: a.goalMin ?? 1, unit: a.unit ?? null,
          habitFreq: isHabit ? (freqMap[a.habitFreq ?? "daily"] ?? 0) : null,
          habitTarget: isHabit ? (a.habitTarget ?? 1) : null,
          manualTarget: isHabit, autoTune: !isHabit,
          linkedActivityId: a.linkedActivityName ? (aMap[a.linkedActivityName] ?? null) : null,
          createdAt: FieldValue.serverTimestamp(), lastTuneAt: null, order: 0, iconCode: null, deleted: false,
        });
      }
    }
    let projectMsg = "";
    if (project && project.title) {
      const arr = <T>(v: unknown): T[] => { const c = coerce<T[]>(v); return Array.isArray(c) ? c : []; };
      const p = { ...project, phases: arr<NonNullable<typeof project.phases>[number]>(project.phases), tasks: arr<NonNullable<typeof project.tasks>[number]>(project.tasks) };
      const today = todayInParis();
      const projectId = uuidv4();
      let strategicObjectiveId: string | null = null;
      if (p.strategicObjective && p.strategicObjective.title) {
        strategicObjectiveId = uuidv4();
        batch.set(db.collection(`users/${uid}/strategic_objectives`).doc(strategicObjectiveId), {
          id: strategicObjectiveId, title: p.strategicObjective.title, kpiTarget: p.strategicObjective.kpiTarget ?? null,
          description: null, domainId: null, horizonLabel: null,
          startDate: p.startDate ?? null, endDate: p.endDate ?? null,
          status: "active", projectIds: [projectId], createdAt: FieldValue.serverTimestamp(),
        });
      }
      const phases = (p.phases ?? []).map((ph) => ({ id: uuidv4(), label: ph.name, color: null, startDate: ph.startDate ?? p.startDate ?? today, endDate: ph.endDate ?? p.endDate ?? today }));
      const phaseIdByName: Record<string, string> = {};
      (p.phases ?? []).forEach((ph, i) => { phaseIdByName[ph.name] = phases[i].id; });
      const tasks = (p.tasks ?? []).map((t) => ({
        id: uuidv4(), title: t.name,
        phaseId: t.phase ? (phaseIdByName[t.phase] ?? null) : null,
        groupLabel: null, description: null,
        startDate: t.startDate ?? p.startDate ?? today, endDate: t.endDate ?? null,
        isMilestone: t.milestone ?? false, color: null, barLabel: null, status: "pending",
        actions: (t.actions ?? []).map((x) => ({ id: uuidv4(), title: x, done: false, doneAt: null, createdAt: new Date().toISOString() })),
      }));
      batch.set(db.collection(`users/${uid}/projects`).doc(projectId), {
        id: projectId, title: p.title, description: null,
        strategicObjectiveId, domainId: null,
        startDate: p.startDate ?? today, endDate: p.endDate ?? null,
        status: "active", phases, tasks,
        createdBy: uid, sourceType: "formation_onboarding",
        createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp(),
      });
      projectMsg = " + 1 projet Gantt";
    }
    await batch.commit();
    return { notification: `✓ ${nDom} domaines, ${nAct} activités créés${projectMsg}`, output: `Workspace créé : ${nDom} domaines, ${nAct} activités${projectMsg}.` };
  }

  if (toolName === "create_domain") {
    const id = uuidv4();
    const name = input.name as string;
    const colorVal = input.color ? hexToColorValue(input.color as string) : null;
    await db.collection(`users/${uid}/domains`).doc(id).set({
      id, name,
      goalMinDay: null, autoGoal: true,
      colorValue: colorVal,
      createdAt: FieldValue.serverTimestamp(),
    });
    domainMap[name] = id;
    return { notification: `✓ Domaine "${name}" créé`, output: `Domaine créé — id: ${id}` };
  }

  if (toolName === "create_activity") {
    const id = uuidv4();
    const name = input.name as string;
    const domainName = input.domainName as string;
    const domainId = domainMap[domainName] ?? null;
    const isHabit = input.type === "habit";
    const freqMap: Record<string, number> = { daily: 0, weekly: 1, monthly: 2 };
    const freqKey = (input.habitFreq as string) ?? "daily";
    const habitFreq = isHabit ? (freqMap[freqKey] ?? 0) : null;
    const habitTarget = isHabit ? ((input.habitTarget as number) ?? 1) : null;
    // Si le guide a précisé fréquence/cible, on fige la cible (pas d'auto-tune qui l'écrase).
    const manualHabit = isHabit && (input.habitFreq !== undefined || input.habitTarget !== undefined);
    // Lien routine → activité temps parente (cf. linkedActivityId : "lancer l'activité → ses routines").
    const linkedName = input.linkedActivityName as string | undefined;
    const linkedActivityId = linkedName ? (activityMap[linkedName] ?? null) : null;
    await db.collection(`users/${uid}/activities`).doc(id).set({
      id, name, domainId,
      type: isHabit ? "habit" : "time",
      role: "generic",
      goalMin: (input.goalMin as number) ?? 1,
      unit: (input.unit as string) ?? null,
      habitFreq,
      habitTarget,
      manualTarget: manualHabit,
      autoTune: !manualHabit,
      linkedActivityId,
      createdAt: FieldValue.serverTimestamp(),
      lastTuneAt: null, order: 0, iconCode: null, deleted: false,
    });
    activityMap[name] = id; // pour résoudre les liens des routines créées ensuite
    const detail = isHabit ? ` (${freqKey} ×${habitTarget})` : (input.goalMin ? ` (${input.goalMin}min/j)` : "");
    return { notification: `✓ Activité "${name}"${detail} créée`, output: `Activité créée — id: ${id}` };
  }

  if (toolName === "create_routine") {
    const id = uuidv4();
    const name = input.name as string;
    const domainName = input.domainName as string;
    const domainId = domainMap[domainName] ?? (Object.values(domainMap)[0] ?? null);
    await db.collection(`users/${uid}/activities`).doc(id).set({
      id, name, domainId,
      type: "habit", role: "generic",
      goalMin: (input.dureeMin as number) ?? 15,
      unit: null, habitFreq: 0, habitTarget: 1,
      manualTarget: false, autoTune: false,
      createdAt: FieldValue.serverTimestamp(),
      lastTuneAt: null, order: 0, iconCode: null, deleted: false,
    });
    return { notification: `✓ Routine "${name}" créée`, output: `Routine créée — id: ${id}` };
  }

  if (toolName === "push_gantt") {
    const projectId = uuidv4();
    const ganttInput = input as {
      title: string; startDate: string; endDate: string;
      strategicObjective?: { title: string; kpiTarget?: string };
      phases: Array<{ label: string; startDate: string; endDate: string }>;
      tasks: Array<{ title: string; phaseIndex: number; startDate: string; endDate: string; isMilestone?: boolean; actions?: string[] }>;
    };
    const phases = ganttInput.phases.map((p) => ({ id: uuidv4(), label: p.label, color: null, startDate: p.startDate, endDate: p.endDate }));
    const tasks = ganttInput.tasks.map((t) => ({
      id: uuidv4(), title: t.title,
      phaseId: phases[t.phaseIndex]?.id ?? null,
      groupLabel: null, description: null,
      startDate: t.startDate, endDate: t.endDate,
      isMilestone: t.isMilestone ?? false,
      color: null, barLabel: null, status: "pending",
      actions: (t.actions ?? []).map((a) => ({ id: uuidv4(), title: a, done: false, doneAt: null, createdAt: new Date().toISOString() })),
    }));
    // Objectif stratégique (le résultat visé) — affiché en tête du Gantt
    let strategicObjectiveId: string | null = null;
    if (ganttInput.strategicObjective?.title) {
      strategicObjectiveId = uuidv4();
      await db.collection(`users/${uid}/strategic_objectives`).doc(strategicObjectiveId).set({
        id: strategicObjectiveId,
        title: ganttInput.strategicObjective.title,
        kpiTarget: ganttInput.strategicObjective.kpiTarget ?? null,
        description: null, domainId: null, horizonLabel: null,
        startDate: ganttInput.startDate, endDate: ganttInput.endDate,
        status: "active", projectIds: [projectId],
        createdAt: FieldValue.serverTimestamp(),
      });
    }
    await db.collection(`users/${uid}/projects`).doc(projectId).set({
      id: projectId, title: ganttInput.title,
      description: null, strategicObjectiveId, domainId: null,
      startDate: ganttInput.startDate, endDate: ganttInput.endDate,
      status: "active", phases, tasks,
      createdBy: uid, sourceType: "formation_onboarding",
      createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp(),
    });
    return { notification: `✓ Projet Gantt "${ganttInput.title}" créé`, output: `Projet créé — id: ${projectId}` };
  }

  if (toolName === "set_structure_preview") {
    return { notification: "", output: "Aperçu de la structure mis à jour." };
  }

  if (toolName === "complete_onboarding") {
    return { notification: "✓ Configuration terminée", output: "Onboarding marqué comme terminé." };
  }

  if (toolName === "update_domain") {
    const currentName = input.currentName as string;
    const newName = input.newName as string | undefined;
    const newColor = input.color as string | undefined;
    const domainId = domainMap[currentName];
    if (!domainId) return { notification: `Domaine "${currentName}" introuvable`, output: `Erreur: "${currentName}" pas dans le domainMap` };
    const updates: Record<string, unknown> = {};
    if (newName) updates.name = newName;
    if (newColor) updates.colorValue = hexToColorValue(newColor);
    if (Object.keys(updates).length > 0) {
      await db.collection(`users/${uid}/domains`).doc(domainId).update(updates);
    }
    if (newName) { domainMap[newName] = domainId; delete domainMap[currentName]; }
    const label = newName ? `"${currentName}" → "${newName}"` : `"${currentName}"`;
    return { notification: `✓ Domaine ${label} mis à jour`, output: `Domaine mis à jour — id: ${domainId}` };
  }

  if (toolName === "archive_domain") {
    const name = input.name as string;
    const domainId = domainMap[name];
    if (!domainId) return { notification: `Domaine "${name}" introuvable`, output: "Erreur" };
    await db.collection(`users/${uid}/domains`).doc(domainId).update({ deleted: true });
    delete domainMap[name];
    return { notification: `✓ Domaine "${name}" archivé`, output: `Archivé — id: ${domainId}` };
  }

  if (toolName === "update_project") {
    const projectId = input.projectId as string;
    const ref = db.collection(`users/${uid}/projects`).doc(projectId);
    const snap = await ref.get();
    if (!snap.exists) return { notification: `Projet introuvable`, output: `Erreur: projet ${projectId} non trouvé` };
    const updates: Record<string, unknown> = { updatedAt: FieldValue.serverTimestamp() };
    if (input.title) updates.title = input.title;
    if (input.description) updates.description = input.description;
    if (input.startDate) updates.startDate = input.startDate;
    if (input.endDate) updates.endDate = input.endDate;
    if (input.status) updates.status = input.status;
    await ref.update(updates);
    const newTitle = (input.title as string) ?? (snap.data()?.title as string) ?? projectId;
    return { notification: `✓ Projet "${newTitle}" mis à jour`, output: `Projet mis à jour` };
  }

  if (toolName === "archive_project") {
    const projectId = input.projectId as string;
    const ref = db.collection(`users/${uid}/projects`).doc(projectId);
    const snap = await ref.get();
    if (!snap.exists) return { notification: `Projet introuvable`, output: `Erreur` };
    const title = (snap.data()?.title as string) ?? projectId;
    await ref.update({ status: "archived", updatedAt: FieldValue.serverTimestamp() });
    return { notification: `✓ Projet "${title}" archivé`, output: `Archivé` };
  }

  if (toolName === "add_task") {
    const projectId = input.projectId as string;
    const ref = db.collection(`users/${uid}/projects`).doc(projectId);
    const snap = await ref.get();
    if (!snap.exists) return { notification: `Projet introuvable`, output: `Erreur` };
    const newTask = {
      id: uuidv4(),
      title: input.title as string,
      description: null,
      phaseId: null,
      groupLabel: null,
      startDate: input.startDate as string,
      endDate: (input.endDate as string) ?? null,
      isMilestone: (input.isMilestone as boolean) ?? false,
      color: null,
      barLabel: null,
      status: "pending",
      actions: ((input.actions as string[]) ?? []).map((a) => ({
        id: uuidv4(), title: a, done: false, doneAt: null, createdAt: new Date().toISOString(),
      })),
    };
    await ref.update({
      tasks: FieldValue.arrayUnion(newTask),
      updatedAt: FieldValue.serverTimestamp(),
    });
    return { notification: `✓ Tâche "${newTask.title}" ajoutée`, output: `Tâche créée — id: ${newTask.id}` };
  }

  return { notification: "", output: `Outil inconnu : ${toolName}` };
}

// Mindmap (filet de sécurité, INCRÉMENTAL) : part de la structure connue + le dernier
// échange, renvoie la structure mise à jour. Input petit et constant (pas tout le
// transcript) → bien moins cher, et plus fiable (on ne perd rien).
async function extractStructurePreview(
  client: Anthropic,
  prevStructure: unknown,
  userMessage: string,
  assistantText: string,
): Promise<unknown | null> {
  try {
    const prevJson = JSON.stringify(prevStructure ?? { center: "Ma vie", domains: [] });
    const r = await client.messages.create({
      model: getModel("structure_project"),
      max_tokens: 4096,
      system:
        "Tu maintiens une structure de vie pour une mindmap. On te donne la structure ACTUELLE (JSON) et le DERNIER échange. " +
        "Renvoie la structure MISE À JOUR en appliquant le dernier échange : AJOUTE les nouveaux éléments, RENOMME ou SUPPRIME ceux que l'utilisateur demande explicitement de changer/retirer, et conserve À L'IDENTIQUE tout le reste (ne perds rien par inadvertance). UNIQUEMENT du JSON, rien d'autre. " +
        "Format exact : {\"center\": string, \"domains\": [{\"name\": string, \"activities\": [{\"name\": string, \"type\": \"time\"|\"habit\", \"goalMin\": number, \"parent\": string}]}], \"gantt\": {\"title\": string, \"startDate\": \"YYYY-MM-DD\", \"endDate\": \"YYYY-MM-DD\", \"phases\": [{\"name\": string, \"startDate\": \"YYYY-MM-DD\", \"endDate\": \"YYYY-MM-DD\"}], \"tasks\": [{\"name\": string, \"phase\": string, \"startDate\": \"YYYY-MM-DD\", \"endDate\": \"YYYY-MM-DD\", \"milestone\": boolean}]}}. " +
        "type 'time' = durée (goalMin minutes/jour ; estime si non dit : cuisiner 30, sieste 20, sport 45, lecture 20) ; 'habit' = fréquence. " +
        "parent = pour une routine appairée à une activité temps, le nom de cette activité (ex: 'Faire la vaisselle' → parent 'Vaisselle'). Omets si pas de jumelle. " +
        "gantt = UNIQUEMENT si un objectif concret à ~3 mois, avec des étapes (phases) et des tâches, est en cours de construction. Sinon N'INCLUS PAS le champ gantt. 'phase' d'une tâche = le nom de sa phase parente. Dates au format YYYY-MM-DD. " +
        "center = prénom si connu, sinon \"Ma vie\". N'ajoute QUE des domaines/activités/éléments explicitement nommés/validés.",
      messages: [{ role: "user", content: `Structure actuelle:\n${prevJson}\n\nDernier échange:\nuser: ${userMessage}\nassistant: ${assistantText}\n\nRenvoie la structure mise à jour (JSON uniquement).` }],
    });
    const txt = r.content.filter((b) => b.type === "text").map((b) => (b as { type: "text"; text: string }).text).join("");
    const m = txt.match(/\{[\s\S]*\}/);
    if (!m) return null;
    const parsed = JSON.parse(m[0]);
    if (parsed && Array.isArray(parsed.domains) && parsed.domains.length > 0) return parsed;
    return null;
  } catch (_) {
    return null;
  }
}

export const onboardingChat = onRequest(
  { cors: true, invoker: "public", secrets: ["FORMATION_JWT_SECRET", "ANTHROPIC_API_KEY"], timeoutSeconds: 300, memory: "512MiB" },
  async (req, res) => {
    if (req.method === "OPTIONS") { res.status(204).send(""); return; }
    if (req.method !== "POST") { res.status(405).json({ error: "Method Not Allowed" }); return; }

    const { token, message, history, userContext, action } = req.body as {
      token?: string;
      message?: string;
      action?: "chat" | "checkSession" | "clearSession" | "startRevision" | "revision_chat";
      history?: Array<{ role: "user" | "assistant"; content: string }>;
      userContext?: {
        prenom?: string;
        activite?: string;
        situation?: string;
        energie?: string;
        objectif?: string;
        frein?: string;
      };
    };

    if (!token) { res.status(400).json({ error: "token requis" }); return; }

    const decoded = verifyFormationToken(token, process.env.FORMATION_JWT_SECRET!);
    if (!decoded) { res.status(401).json({ error: "Token invalide ou expiré" }); return; }
    const { uid } = decoded;

    // ── Vérification statut onboarding ────────────────────────────────────────
    // Toujours chargé — sert pour checkSession, chat ET révision

    const accessDoc = await db.collection("formation_access").doc(uid).get();
    const accessData = accessDoc.data() ?? {};
    const onboardingDone = accessData.onboardingDone === true;
    const isPro = accessData.isPro === true; // positionné via RevenueCat webhook (TODO)

    // ── Actions hors-chat ─────────────────────────────────────────────────────

    if (action === "checkSession") {
      const snap = await db.collection("formation_sessions").doc(uid).get();
      const base = { onboardingDone, isPro };
      if (!snap.exists) { res.status(200).json({ ...base, hasSession: false }); return; }
      const data = snap.data()!;
      const savedAt = (data.savedAt as admin.firestore.Timestamp)?.toDate();
      const ageMs = savedAt ? Date.now() - savedAt.getTime() : Infinity;
      if (ageMs > 7 * 24 * 60 * 60 * 1000) { res.status(200).json({ ...base, hasSession: false }); return; }
      res.status(200).json({
        ...base,
        hasSession: true,
        mode: data.mode ?? "onboarding",
        history: data.history ?? [],
        userContext: data.userContext ?? null,
        turnCount: data.turnCount ?? 0,
        savedAt: savedAt?.toISOString(),
        structure: data.structure ?? null,
      });
      return;
    }

    if (action === "clearSession") {
      await db.collection("formation_sessions").doc(uid).delete();
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
        await db.collection("formation_access").doc(uid).set(
          { lastVisionAt: FieldValue.serverTimestamp() },
          { merge: true }
        );
      }

      const apiKey2 = process.env.ANTHROPIC_API_KEY;
      if (!apiKey2) { res.status(500).json({ error: "ANTHROPIC_API_KEY manquante" }); return; }
      const client2 = new Anthropic({ apiKey: apiKey2 });
      const today2 = todayInParis();

      // Lecture config existante (pour startRevision ou premier tour)
      const [domainsSnap, activitiesSnap, projectsSnap] = await Promise.all([
        db.collection(`users/${uid}/domains`).get(),
        db.collection(`users/${uid}/activities`).get(),
        db.collection(`users/${uid}/projects`).where("status", "==", "active").get(),
      ]);
      // Construction par domaine pour que Claude voie bien les liens
      const liveDomains = domainsSnap.docs.filter(d => !d.data().deleted);
      const liveActivities = activitiesSnap.docs.filter(d => !d.data().deleted);

      const domainSections: string[] = [];
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
        const data = d.data();
        const tasks = (data.tasks as Array<{ status?: string }>) ?? [];
        const done = tasks.filter(t => t.status === "done").length;
        const total = tasks.length;
        return `  · "${data.title}" (id: ${d.id}) — ${done}/${total} tâches, fin ${data.endDate ?? "non définie"}`;
      }).join("\n");
      const currentConfig = `Domaines & activités :\n${domainSections.length ? domainSections.join("\n") : "  Aucun"}\n\nProjets actifs (utilise les id pour update_project/archive_project/add_task) :\n${projectsList || "  Aucun"}`;

      const revSystemPrompt = REVISION_SYSTEM_PROMPT
        .replace("{{TODAY}}", today2)
        .replace("{{CURRENT_CONFIG}}", currentConfig);

      // Pré-populer la domainMap avec les domaines existants
      const revDomainMap: Record<string, string> = {};
      for (const doc of domainsSnap.docs) {
        const d = doc.data();
        if (!d.deleted) revDomainMap[d.name as string] = doc.id;
      }

      type MsgParam = { role: "user" | "assistant"; content: string | unknown[] };
      const revMessages: MsgParam[] = [
        ...(history ?? []).map((m) => ({ role: m.role, content: m.content })),
        { role: "user" as const, content: action === "startRevision" ? "Je suis prêt pour ma session de révision." : (message ?? "") },
      ];

      const revNotifications: string[] = [];
      let revComplete = false;

      while (true) {
        const response = await client2.messages.create({
          model: getModel("onboarding"),
          max_tokens: 1536,
          system: revSystemPrompt,
          tools: REVISION_TOOLS as Parameters<typeof client2.messages.create>[0]["tools"],
          messages: revMessages as Parameters<typeof client2.messages.create>[0]["messages"],
        });

        if (response.stop_reason === "end_turn") {
          const text2 = response.content.filter((b) => b.type === "text").map((b) => (b as { type: "text"; text: string }).text).join("");
          // Sauvegarde session révision
          const newHistory = [
            ...(history ?? []),
            { role: "user", content: action === "startRevision" ? "Je suis prêt pour ma session de révision." : (message ?? "") },
            { role: "assistant", content: text2 },
          ];
          db.collection("formation_sessions").doc(uid).set({ uid, history: newHistory, mode: "revision", turnCount: newHistory.length / 2, savedAt: FieldValue.serverTimestamp() }).catch(() => {});
          res.status(200).json({ message: text2, notifications: revNotifications, revisionComplete: revComplete, mode: "revision" });
          return;
        }

        if (response.stop_reason === "tool_use") {
          revMessages.push({ role: "assistant", content: response.content });
          const toolResults: unknown[] = [];
          for (const block of response.content) {
            if (block.type === "tool_use") {
              const result = await executeOnboardingTool(uid, block.name, block.input as Record<string, unknown>, revDomainMap);
              if (result.notification) revNotifications.push(result.notification);
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

    if (!message) { res.status(400).json({ error: "message requis" }); return; }

    const apiKey = process.env.ANTHROPIC_API_KEY;
    if (!apiKey) { res.status(500).json({ error: "ANTHROPIC_API_KEY manquante" }); return; }

    const client = new Anthropic({ apiKey });
    const today = todayInParis();

    // Bloc de contexte pré-rempli injecté dans le prompt si formulaire rempli
    const uc = userContext as Record<string, string | undefined> | undefined;
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

    // Construction des messages (text-only history + nouveau message)
    // Le premier message inclut le contexte formulaire pour que Claude parte informé
    type MessageParam = { role: "user" | "assistant"; content: string | unknown[] };
    const firstUserMsg = (history ?? []).length === 0 && contextBlock
      ? `${message}\n\n[Contexte formulaire déjà dans le system prompt — je suis prêt à démarrer.]`
      : message;
    const messages: MessageParam[] = [
      ...(history ?? []).map((m) => ({ role: m.role, content: m.content })),
      { role: "user" as const, content: firstUserMsg },
    ];

    const notifications: string[] = [];
    const domainMap: Record<string, string> = {};
    const activityMap: Record<string, string> = {};
    let onboardingComplete = false;
    let structurePreview: unknown = null;
    let assistantText = ""; // accumule le texte de TOUS les tours (évite les messages vides quand le modèle répond ET appelle un outil dans le même tour)

    // Boucle agentique : continue jusqu'à end_turn (réponse texte finale)
    while (true) {
      const response = await client.messages.create({
        model: getModel("onboarding"),
        max_tokens: 8192, // create_workspace = un gros payload unique (≈40 activités + projet)
        system: systemPrompt,
        tools: ONBOARDING_TOOLS as Parameters<typeof client.messages.create>[0]["tools"],
        messages: messages as Parameters<typeof client.messages.create>[0]["messages"],
      });

      if (response.stop_reason === "end_turn") {
        assistantText += response.content
          .filter((b) => b.type === "text")
          .map((b) => (b as { type: "text"; text: string }).text)
          .join("");
        const text = assistantText.trim();
        // Lit la structure déjà connue UNE fois (sert à l'extraction incrémentale + à la fusion).
        let prevStruct: unknown = null;
        if (!onboardingComplete) {
          try {
            const prevSnap = await db.collection("formation_sessions").doc(uid).get();
            prevStruct = prevSnap.exists ? (prevSnap.data()?.structure ?? null) : null;
          } catch (_) { /* prevStruct reste null */ }
        }
        // Filet de sécurité : si le guide n'a pas mis à jour la mindmap, on l'alimente
        // par extraction incrémentale (structure connue + dernier échange).
        if (!structurePreview && !onboardingComplete) {
          structurePreview = await extractStructurePreview(client, prevStruct, message ?? "", text);
        }
        // Pas de fusion des domaines : l'extraction incrémentale fait foi (applique
        // ajouts ET renommages/suppressions). MAIS on préserve le Gantt déjà construit
        // si l'extraction l'a omis ce tour-ci (sinon il disparaît en éditant un domaine).
        if (structurePreview && prevStruct) {
          const sp = structurePreview as { gantt?: unknown };
          const pp = prevStruct as { gantt?: unknown };
          if (!sp.gantt && pp.gantt) sp.gantt = pp.gantt;
        }
        if (onboardingComplete) {
          // set(merge) et non update : pour un compte magic-link, le doc formation_access
          // n'existe pas forcément (pas créé par le webhook) → update échouerait silencieusement
          // et l'utilisateur ne serait jamais marqué "terminé".
          await db.collection("formation_access").doc(uid).set({
            uid,
            onboardingDone: true,
            onboardingDoneAt: FieldValue.serverTimestamp(),
            lastVisionAt: FieldValue.serverTimestamp(),
          }, { merge: true }).catch(() => {});
          // Nettoie la session après completion
          db.collection("formation_sessions").doc(uid).delete().catch(() => {});
        } else {
          // Sauvegarde la session après chaque échange (fire & forget)
          const historyToSave = [
            ...(history ?? []),
            { role: "user", content: message },
            { role: "assistant", content: text },
          ];
          db.collection("formation_sessions").doc(uid).set({
            uid, history: historyToSave,
            userContext: userContext ?? null,
            turnCount: (history ?? []).length / 2 + 1,
            savedAt: FieldValue.serverTimestamp(),
            ...(structurePreview ? { structure: structurePreview } : {}),
          }, { merge: true }).catch(() => {});
        }
        res.status(200).json({ message: text, notifications, onboardingComplete, structure: structurePreview });
        return;
      }

      if (response.stop_reason === "tool_use") {
        messages.push({ role: "assistant", content: response.content });

        // Récupère le texte émis DANS ce tour (le modèle répond souvent ET appelle un outil
        // dans le même tour) — sinon ce texte serait perdu → bulle vide côté chat.
        assistantText += response.content
          .filter((b) => b.type === "text")
          .map((b) => (b as { type: "text"; text: string }).text)
          .join("");

        const toolResults: unknown[] = [];
        for (const block of response.content) {
          if (block.type === "tool_use") {
            const result = await executeOnboardingTool(uid, block.name, block.input as Record<string, unknown>, domainMap, activityMap);
            if (result.notification) notifications.push(result.notification);
            if (block.name === "push_gantt" || block.name === "complete_onboarding" || block.name === "create_workspace") onboardingComplete = true;
            if (block.name === "set_structure_preview") structurePreview = block.input;
            toolResults.push({ type: "tool_result", tool_use_id: block.id, content: result.output });
          }
        }
        messages.push({ role: "user", content: toolResults });
        continue;
      }

      // stop_reason inattendu (ex: max_tokens) — on sort de la boucle
      break;
    }

    // Au lieu d'échouer : on renvoie ce qu'on a accumulé (texte + structure).
    res.status(200).json({
      message: assistantText.trim() || "Désolé, peux-tu reformuler ? (réponse interrompue)",
      notifications,
      onboardingComplete,
      structure: structurePreview,
    });
  }
);

// ── adminProductivitwo (sessions de co-dev avec Claude Code) ──────────────────
//
// Endpoint protégé par secret pour permettre à Claude Code d'inspecter et
// pousser dans Productivitwo pendant les sessions de travail (sans passe-plat
// avec le MCP de Claude.ai). Secret stocké en Firebase Secret Manager.

export const adminProductivitwo = onRequest(
  { cors: true, invoker: "public", secrets: ["ADMIN_PUSH_SECRET"] },
  async (req, res) => {
    if (req.method === "OPTIONS") { res.status(204).send(""); return; }
    if (req.method !== "POST") { res.status(405).json({ error: "Method Not Allowed" }); return; }

    const { adminSecret, uid, action, payload } = req.body as {
      adminSecret?: string;
      uid?: string;
      action?: "inspect" | "addTask" | "updateTask" | "addProject" | "updateProject" | "addActionToTask" | "markActionDone" | "setSchedule";
      payload?: Record<string, unknown>;
    };

    if (!adminSecret || adminSecret.trim() !== (process.env.ADMIN_PUSH_SECRET ?? "").trim()) {
      res.status(401).json({ error: "Secret invalide" }); return;
    }
    if (!uid) { res.status(400).json({ error: "uid requis" }); return; }

    try {
      if (action === "inspect") {
        const [domainsSnap, activitiesSnap, projectsSnap] = await Promise.all([
          db.collection(`users/${uid}/domains`).get(),
          db.collection(`users/${uid}/activities`).get(),
          db.collection(`users/${uid}/projects`).get(),
        ]);
        const domains = domainsSnap.docs
          .filter(d => !d.data().deleted)
          .map(d => ({ id: d.id, ...d.data() }));
        const activities = activitiesSnap.docs
          .filter(d => !d.data().deleted)
          .map(d => ({ id: d.id, ...d.data() }));
        const projects = projectsSnap.docs.map(d => {
          const data = d.data();
          const tasks = (data.tasks as Array<Record<string, unknown>>) ?? [];
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
              actionsDone: Array.isArray(t.actions) ? (t.actions as Array<{ done?: boolean }>).filter(a => a.done).length : 0,
              actions: Array.isArray(t.actions) ? (t.actions as Array<{ id: string; title: string; done?: boolean }>).map(a => ({ id: a.id, title: a.title, done: a.done ?? false })) : [],
            })),
          };
        });
        res.status(200).json({ domains, activities, projects });
        return;
      }

      if (action === "updateTask") {
        const { projectId, taskId, startDate, endDate, title, status } = payload as {
          projectId: string; taskId: string;
          startDate?: string; endDate?: string; title?: string; status?: string;
        };
        const ref = db.collection(`users/${uid}/projects`).doc(projectId);
        const snap = await ref.get();
        if (!snap.exists) { res.status(404).json({ error: "Projet introuvable" }); return; }
        const rawTasks = (snap.data()?.tasks as Array<Record<string, unknown>>) ?? [];
        const tasks = rawTasks.map(t => JSON.parse(JSON.stringify(t, (_k, v) =>
          v && typeof v === "object" && typeof v.toDate === "function" ? v.toDate().toISOString() : v
        )));
        const idx = tasks.findIndex(t => t.id === taskId);
        if (idx === -1) { res.status(404).json({ error: "Tâche introuvable" }); return; }
        const patch: Record<string, unknown> = {};
        if (startDate) patch.startDate = startDate;
        if (endDate) patch.endDate = endDate;
        if (title) patch.title = title;
        if (status) patch.status = status;
        tasks[idx] = { ...tasks[idx], ...patch };
        await ref.update({ tasks, updatedAt: FieldValue.serverTimestamp() });
        res.status(200).json({ success: true });
        return;
      }

      if (action === "addTask") {
        const { projectId, title, startDate, endDate, isMilestone, actions, phaseId, status, actionsAllDone } = payload as {
          projectId: string; title: string; startDate: string;
          endDate?: string; isMilestone?: boolean; actions?: string[]; phaseId?: string;
          status?: "pending" | "done" | "skipped";
          actionsAllDone?: boolean;
        };
        const newTask = {
          id: uuidv4(), title, description: null,
          phaseId: phaseId ?? null, groupLabel: null,
          startDate, endDate: endDate ?? null,
          isMilestone: isMilestone ?? false,
          color: null, barLabel: null, status: status ?? "pending",
          actions: (actions ?? []).map(a => ({
            id: uuidv4(), title: a,
            done: actionsAllDone === true, doneAt: actionsAllDone === true ? new Date().toISOString() : null,
            createdAt: new Date().toISOString(),
          })),
        };
        await db.collection(`users/${uid}/projects`).doc(projectId).update({
          tasks: FieldValue.arrayUnion(newTask),
          updatedAt: FieldValue.serverTimestamp(),
        });
        res.status(200).json({ success: true, taskId: newTask.id });
        return;
      }

      if (action === "addActionToTask") {
        const { projectId, taskId, title } = payload as { projectId: string; taskId: string; title: string };
        const ref = db.collection(`users/${uid}/projects`).doc(projectId);
        const snap = await ref.get();
        if (!snap.exists) { res.status(404).json({ error: "Projet introuvable" }); return; }
        const tasks = ((snap.data()?.tasks as Array<Record<string, unknown>>) ?? []).map(t => JSON.parse(JSON.stringify(t, (_k, v) =>
          v && typeof v === "object" && typeof v.toDate === "function" ? v.toDate().toISOString() : v
        )));
        const idx = tasks.findIndex(t => t.id === taskId);
        if (idx === -1) { res.status(404).json({ error: "Tâche introuvable" }); return; }
        const actions = ((tasks[idx].actions as Array<Record<string, unknown>>) ?? []).slice();
        const newAction = { id: uuidv4(), title, done: false, doneAt: null, createdAt: new Date().toISOString() };
        actions.push(newAction);
        tasks[idx] = { ...tasks[idx], actions };
        await ref.update({ tasks, updatedAt: FieldValue.serverTimestamp() });
        res.status(200).json({ success: true, actionId: newAction.id });
        return;
      }

      if (action === "markActionDone") {
        const { projectId, taskId, actionId, done } = payload as { projectId: string; taskId: string; actionId: string; done: boolean };
        const ref = db.collection(`users/${uid}/projects`).doc(projectId);
        const snap = await ref.get();
        if (!snap.exists) { res.status(404).json({ error: "Projet introuvable" }); return; }
        const tasks = ((snap.data()?.tasks as Array<Record<string, unknown>>) ?? []).map(t => JSON.parse(JSON.stringify(t, (_k, v) =>
          v && typeof v === "object" && typeof v.toDate === "function" ? v.toDate().toISOString() : v
        )));
        const tIdx = tasks.findIndex(t => t.id === taskId);
        if (tIdx === -1) { res.status(404).json({ error: "Tâche introuvable" }); return; }
        const actions = ((tasks[tIdx].actions as Array<Record<string, unknown>>) ?? []).slice();
        const aIdx = actions.findIndex(a => a.id === actionId);
        if (aIdx === -1) { res.status(404).json({ error: "Action introuvable" }); return; }
        actions[aIdx] = { ...actions[aIdx], done, doneAt: done ? new Date().toISOString() : null };
        tasks[tIdx] = { ...tasks[tIdx], actions };
        await ref.update({ tasks, updatedAt: FieldValue.serverTimestamp() });
        res.status(200).json({ success: true });
        return;
      }

      if (action === "addProject") {
        const { title, description, startDate, endDate, domainId, phases, tasks } = payload as {
          title: string; description?: string; startDate: string; endDate?: string;
          domainId?: string;
          phases?: Array<{ label: string; startDate: string; endDate: string }>;
          tasks?: Array<{ title: string; startDate: string; endDate?: string; phaseIndex?: number; actions?: string[] }>;
        };
        const projectId = uuidv4();
        const phasesData = (phases ?? []).map(p => ({ id: uuidv4(), label: p.label, color: null, startDate: p.startDate, endDate: p.endDate }));
        const tasksData = (tasks ?? []).map(t => ({
          id: uuidv4(), title: t.title, description: null,
          phaseId: t.phaseIndex !== undefined ? phasesData[t.phaseIndex]?.id ?? null : null,
          groupLabel: null,
          startDate: t.startDate, endDate: t.endDate ?? null,
          isMilestone: false, color: null, barLabel: null, status: "pending",
          actions: (t.actions ?? []).map(a => ({
            id: uuidv4(), title: a, done: false, doneAt: null, createdAt: new Date().toISOString(),
          })),
        }));
        await db.collection(`users/${uid}/projects`).doc(projectId).set({
          id: projectId, title,
          description: description ?? null, strategicObjectiveId: null,
          domainId: domainId ?? null,
          startDate, endDate: endDate ?? null,
          status: "active", phases: phasesData, tasks: tasksData,
          createdBy: uid, sourceType: "claude_code_session",
          createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp(),
        });
        res.status(200).json({ success: true, projectId });
        return;
      }

      if (action === "setSchedule") {
        const { date, blocks } = payload as {
          date: string;
          blocks: Array<{
            startTime: string; durationMin: number; title: string;
            category: "project" | "routine" | "personal" | "break";
            projectId?: string; taskId?: string; activityId?: string;
          }>;
        };
        const normalizedBlocks = blocks.map(b => ({
          id: uuidv4(),
          startTime: b.startTime,
          durationMin: b.durationMin,
          title: b.title,
          category: b.category,
          projectId: b.projectId ?? null,
          taskId: b.taskId ?? null,
          activityId: b.activityId ?? null,
          status: "pending",
          doneAt: null,
        }));
        await db.collection(`users/${uid}/daily_schedules`).doc(date).set({
          date,
          generatedBy: "claude_code_session",
          generatedAt: FieldValue.serverTimestamp(),
          blocks: normalizedBlocks,
        });
        res.status(200).json({ success: true, blocksCount: normalizedBlocks.length });
        return;
      }

      if (action === "updateProject") {
        const { projectId, ...updates } = payload as { projectId: string } & Record<string, unknown>;
        await db.collection(`users/${uid}/projects`).doc(projectId).update({
          ...updates,
          updatedAt: FieldValue.serverTimestamp(),
        });
        res.status(200).json({ success: true });
        return;
      }

      res.status(400).json({ error: `Action inconnue : ${action}` });
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      res.status(500).json({ error: msg });
    }
  }
);

// ── Formation helpers ─────────────────────────────────────────────────────────

const FORMATION_URL = "https://app.productivitwo.com/formation";

function createFormationToken(uid: string, email: string, secret: string): string {
  const cleanSecret = secret.trim();
  const payload = Buffer.from(JSON.stringify({
    uid,
    email,
    exp: Date.now() + 30 * 24 * 60 * 60 * 1000,
  })).toString("base64url");
  const sig = createHmac("sha256", cleanSecret).update(payload).digest("base64url");
  return `${payload}.${sig}`;
}

function verifyFormationToken(token: string, secret: string): { uid: string; email: string } | null {
  const cleanSecret = secret.trim();
  const dot = token.lastIndexOf(".");
  if (dot < 0) return null;
  const payload = token.slice(0, dot);
  const sig = token.slice(dot + 1);
  const expected = createHmac("sha256", cleanSecret).update(payload).digest("base64url");
  // Accepte aussi l'ancienne signature (avec \n) pour ne pas invalider les tokens en circulation
  const legacy = createHmac("sha256", secret).update(payload).digest("base64url");
  if (sig !== expected && sig !== legacy) return null;
  try {
    const data = JSON.parse(Buffer.from(payload, "base64url").toString());
    if (!data.exp || data.exp < Date.now()) return null;
    return { uid: data.uid, email: data.email };
  } catch {
    return null;
  }
}

function hexToColorValue(hex: string): number | null {
  const clean = hex.replace("#", "");
  if (clean.length !== 6) return null;
  return parseInt("FF" + clean.toUpperCase(), 16);
}

// ── generateFormationAccess ───────────────────────────────────────────────────
//
// POST — appelé par systeme.io après un achat.
// Secret accepté : header x-webhook-secret OU query param ?secret=xxx OU body.webhookSecret
// Email accepté : body.email OU body.contact_email OU body.contact.email
// Retourne { accessUrl } à inclure dans l'email de confirmation systeme.io.

export const generateFormationAccess = onRequest(
  { cors: true, invoker: "public", secrets: ["FORMATION_JWT_SECRET", "SYSTEME_IO_WEBHOOK_SECRET"] },
  async (req, res) => {
    if (req.method === "OPTIONS") { res.status(204).send(""); return; }
    if (req.method !== "POST") { res.status(405).json({ error: "Method Not Allowed" }); return; }

    // Secret : header, query param ou body (compatible systeme.io qui ne supporte pas les headers custom)
    const body = req.body as Record<string, unknown>;
    const providedSecret =
      (req.headers["x-webhook-secret"] as string | undefined) ??
      (req.query?.secret as string | undefined) ??
      (body?.webhookSecret as string | undefined);
    if (!providedSecret || providedSecret.trim() !== (process.env.SYSTEME_IO_WEBHOOK_SECRET ?? "").trim()) {
      res.status(401).json({ error: "Secret invalide" });
      return;
    }

    // Email : essaie les différents formats que systeme.io peut envoyer
    const contact = body?.contact as Record<string, string> | undefined;
    const rawEmail =
      (body?.email as string) ??
      (body?.contact_email as string) ??
      (contact?.email as string) ??
      "";
    const email = rawEmail.trim().toLowerCase();
    if (!email || !email.includes("@")) {
      res.status(400).json({ error: "email requis", received: body });
      return;
    }

    let uid: string;
    try {
      const existing = await admin.auth().getUserByEmail(email);
      uid = existing.uid;
    } catch {
      const created = await admin.auth().createUser({ email });
      uid = created.uid;
    }

    const token = createFormationToken(uid, email, process.env.FORMATION_JWT_SECRET!);

    await db.collection("formation_access").doc(uid).set(
      { uid, email, purchasedAt: FieldValue.serverTimestamp(), onboardingDone: false },
      { merge: true }
    );

    const accessUrl = `${FORMATION_URL}?token=${encodeURIComponent(token)}`;
    res.status(200).json({ success: true, accessUrl, uid });
  }
);

// ── applyFormationProfile ─────────────────────────────────────────────────────
//
// POST { token, profile } — Appelé depuis la Netlify function après le test de
// positionnement. Crée les domaines, activités et routines dans Productivitwo.

type FormationDomaine  = { name: string; color?: string };
type FormationActivite = { name: string; type?: string; domaine_index?: number; goalMin?: number };
type FormationRoutine  = { name: string; dureeMin?: number };

// ── getVisionAccess ───────────────────────────────────────────────────────────
//
// POST — Header: Authorization: Bearer <Firebase ID token>
// Retourne le statut Vision pour l'utilisateur authentifié + URL d'accès si dispo.
// Utilisé par le bouton Vision dans l'app web.

const VISION_INTERVAL_DAYS = 30;

export const getVisionAccess = onRequest(
  { cors: true, invoker: "public", secrets: ["FORMATION_JWT_SECRET"] },
  async (req, res) => {
    if (req.method === "OPTIONS") { res.status(204).send(""); return; }
    if (req.method !== "POST" && req.method !== "GET") { res.status(405).json({ error: "Method Not Allowed" }); return; }

    const authHeader = req.headers.authorization ?? "";
    if (!authHeader.startsWith("Bearer ")) {
      res.status(401).json({ error: "Missing Authorization header" }); return;
    }
    const idToken = authHeader.slice(7).trim();

    let uid: string;
    let email: string;
    try {
      const decoded = await admin.auth().verifyIdToken(idToken);
      uid = decoded.uid;
      email = decoded.email ?? "";
    } catch {
      res.status(401).json({ error: "Token invalide ou expiré" }); return;
    }

    const accessDoc = await db.collection("formation_access").doc(uid).get();
    const accessData = accessDoc.data() ?? {};
    const isPro = accessData.isPro === true;
    const onboardingDone = accessData.onboardingDone === true;
    const lastVisionAt = (accessData.lastVisionAt as admin.firestore.Timestamp | undefined)?.toDate();

    const now = Date.now();
    const intervalMs = VISION_INTERVAL_DAYS * 24 * 60 * 60 * 1000;
    const nextAvailableAt = lastVisionAt ? new Date(lastVisionAt.getTime() + intervalMs) : null;
    const available = !lastVisionAt || (nextAvailableAt && now >= nextAvailableAt.getTime());

    const result: Record<string, unknown> = {
      isPro,
      onboardingDone,
      lastVisionAt: lastVisionAt?.toISOString() ?? null,
      nextAvailableAt: nextAvailableAt?.toISOString() ?? null,
      available: available === true,
      intervalDays: VISION_INTERVAL_DAYS,
    };

    // Génère un access URL frais vers la formation :
    // - première session d'onboarding : toujours accessible (gratuite)
    // - révisions mensuelles suivantes : réservées aux Pro quand disponible
    if (!onboardingDone || (isPro && available)) {
      const token = createFormationToken(uid, email, process.env.FORMATION_JWT_SECRET!);
      result.accessUrl = `https://app.productivitwo.com/vision?token=${encodeURIComponent(token)}`;
    }

    res.status(200).json(result);
  }
);

export const applyFormationProfile = onRequest(
  { cors: true, invoker: "public", secrets: ["FORMATION_JWT_SECRET"] },
  async (req, res) => {
    if (req.method === "OPTIONS") { res.status(204).send(""); return; }
    if (req.method !== "POST") { res.status(405).json({ error: "Method Not Allowed" }); return; }

    const { token, profile } = req.body as {
      token?: string;
      profile?: {
        domaines?: FormationDomaine[];
        activites?: FormationActivite[];
        routines?: FormationRoutine[];
      };
    };

    if (!token || !profile) {
      res.status(400).json({ error: "token et profile requis" });
      return;
    }

    const decoded = verifyFormationToken(token, process.env.FORMATION_JWT_SECRET!);
    if (!decoded) {
      res.status(401).json({ error: "Token invalide ou expiré" });
      return;
    }
    const { uid } = decoded;

    // Idempotence : ne pas recréer si l'onboarding est déjà fait
    const accessDoc = await db.collection("formation_access").doc(uid).get();
    if (accessDoc.exists && accessDoc.data()?.onboardingDone) {
      res.status(200).json({ success: true, uid, alreadyApplied: true });
      return;
    }

    // Domaines
    const domainIds: string[] = [];
    for (const d of (profile.domaines ?? [])) {
      const id = uuidv4();
      domainIds.push(id);
      await db.collection(`users/${uid}/domains`).doc(id).set({
        id,
        name: d.name,
        goalMinDay: null,
        autoGoal: true,
        colorValue: d.color ? hexToColorValue(d.color) : null,
        createdAt: FieldValue.serverTimestamp(),
      });
    }

    // Activités de tracking (type time)
    for (const a of (profile.activites ?? [])) {
      const id = uuidv4();
      const domainId = domainIds[a.domaine_index ?? 0] ?? null;
      const isHabit = a.type === "habit";
      await db.collection(`users/${uid}/activities`).doc(id).set({
        id,
        name: a.name,
        domainId,
        type: isHabit ? "habit" : "time",
        role: "generic",
        goalMin: a.goalMin ?? 1,
        unit: null,
        habitFreq: isHabit ? 0 : null,
        habitTarget: isHabit ? 1 : null,
        manualTarget: false,
        autoTune: true,
        createdAt: FieldValue.serverTimestamp(),
        lastTuneAt: null,
        order: 0,
        iconCode: null,
        deleted: false,
      });
    }

    // Routines (habit activities dans le 1er domaine)
    for (const r of (profile.routines ?? [])) {
      const id = uuidv4();
      await db.collection(`users/${uid}/activities`).doc(id).set({
        id,
        name: r.name,
        domainId: domainIds[0] ?? null,
        type: "habit",
        role: "generic",
        goalMin: r.dureeMin ?? 15,
        unit: null,
        habitFreq: 0,
        habitTarget: 1,
        manualTarget: false,
        autoTune: false,
        createdAt: FieldValue.serverTimestamp(),
        lastTuneAt: null,
        order: 0,
        iconCode: null,
        deleted: false,
      });
    }

    await db.collection("formation_access").doc(uid).update({
      onboardingDone: true,
      onboardingDoneAt: FieldValue.serverTimestamp(),
    });

    res.status(200).json({ success: true, uid });
  }
);
