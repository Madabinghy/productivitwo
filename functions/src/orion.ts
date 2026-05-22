import Anthropic from "@anthropic-ai/sdk";
import type { PromptCachingBetaMessageParam, PromptCachingBetaTool } from "@anthropic-ai/sdk/resources/beta/prompt-caching/messages";
import { db, FieldValue } from "./db";
import {
  executeGetUserContext, executeGetAssistantMessages, executePushAssistantMessage,
  executeDeleteAssistantMessage, executeUpdateActivityGoal, executeCreateRoutine,
  executeCreateRecurringAction, executeAddToDayPlan, executeGetDayBlocks,
  executeGetDayPlan, executePlanDay, executeClearDayPlan, executeCreateActivity,
  executeUpdateActivity, executeUpdateActivityGoal as _uag, executeDeleteActivity,
  executeDeleteAction, executeCreateDomain, executeDeleteDomain,
  executeListProjects, executeGetProject, executePushGantt, executeUpdateProject,
  executeUpdateTaskStatus, executeArchiveProject, executeDeleteProject,
  executeLinkGoalToTask, executeDeleteGoal, executeDeleteRoutine,
  executeGetDocuments, executeSaveDocument, executeGetDocumentTemplate,
  executeGetArchives, executeRestoreItem,
} from "./execute";
import {
  GET_USER_CONTEXT_TOOL, UPDATE_ACTIVITY_GOAL_TOOL, CREATE_ROUTINE_TOOL,
  CREATE_RECURRING_ACTION_TOOL, ADD_TO_DAY_PLAN_TOOL, CREATE_ACTIVITY_TOOL,
  CREATE_DOMAIN_TOOL, PUSH_ASSISTANT_MESSAGE_TOOL, DELETE_DOMAIN_TOOL,
  GET_DOCUMENT_TEMPLATE_TOOL, SAVE_DOCUMENT_TOOL, GET_DOCUMENTS_TOOL,
  DELETE_DOCUMENT_TOOL, GET_ARCHIVES_TOOL, RESTORE_ITEM_TOOL, DELETE_ACTION_TOOL,
  DELETE_ACTIVITY_TOOL, UPDATE_PROJECT_TOOL, UPDATE_TASK_STATUS_TOOL,
  UPDATE_ACTIVITY_TOOL, LINK_GOAL_TO_TASK_TOOL, DELETE_ROUTINE_TOOL,
  DELETE_GOAL_TOOL, CLEAR_DAY_PLAN_TOOL, GET_DAY_BLOCKS_TOOL, GET_DAY_PLAN_TOOL,
  PLAN_DAY_TOOL, ARCHIVE_PROJECT_TOOL, DELETE_PROJECT_TOOL, LIST_PROJECTS_TOOL,
  GET_PROJECT_TOOL, PUSH_GANTT_MCP_TOOL,
  GET_ASSISTANT_MESSAGES_TOOL, DELETE_ASSISTANT_MESSAGE_TOOL,
} from "./tools";
import type { PushGanttBody } from "./types";

const ORION_MAX_RUNS = 50;
const ORION_MODEL = "claude-haiku-4-5-20251001";

// ── Convertit un tool MCP (inputSchema) en tool Anthropic (input_schema) ──────
function toAT(t: { name: string; description: string; inputSchema: unknown }): PromptCachingBetaTool {
  return {
    name: t.name,
    description: t.description,
    input_schema: t.inputSchema as PromptCachingBetaTool["input_schema"],
  };
}

// ── Config utilisateur ────────────────────────────────────────────────────────

export async function getOrionConfig(uid: string): Promise<{
  userNeeds: string;
  userReply: string;
  replyTimestamp: string | null;
}> {
  const snap = await db.collection(`users/${uid}/orion_config`).doc("main").get();
  if (!snap.exists) return { userNeeds: "", userReply: "", replyTimestamp: null };
  const d = snap.data() ?? {};
  return {
    userNeeds: (d.userNeeds as string) ?? "",
    userReply: (d.userReply as string) ?? "",
    replyTimestamp: (d.replyTimestamp as string) ?? null,
  };
}

export async function saveOrionConfig(
  uid: string,
  fields: { userNeeds?: string; userReply?: string }
): Promise<void> {
  const update: Record<string, unknown> = { updatedAt: FieldValue.serverTimestamp() };
  if (fields.userNeeds !== undefined) update.userNeeds = fields.userNeeds;
  if (fields.userReply !== undefined) {
    update.userReply = fields.userReply;
    update.replyTimestamp = new Date().toISOString().slice(0, 10);
  }
  await db.collection(`users/${uid}/orion_config`).doc("main").set(update, { merge: true });
}

// ── Rate limiting ─────────────────────────────────────────────────────────────

export async function getOrionRunCount(uid: string, date: string): Promise<number> {
  const snap = await db.collection("orion_runs").doc(`${uid}_${date}`).get();
  return snap.exists ? ((snap.data()?.count as number) ?? 0) : 0;
}

async function incrementOrionRunCount(uid: string, date: string): Promise<void> {
  await db
    .collection("orion_runs")
    .doc(`${uid}_${date}`)
    .set({ count: FieldValue.increment(1), uid, date }, { merge: true });
}

// ── Log de cycle ──────────────────────────────────────────────────────────────

async function writeCycleLog(uid: string, log: {
  userNeeds: string;
  userReply: string;
  actions: string[];
  pushed: number;
  skipped: boolean;
  skippedReason?: string;
}): Promise<void> {
  const { v4: uuidv4 } = await import("uuid");
  await db.collection(`users/${uid}/orion_logs`).doc(uuidv4()).set({
    ...log,
    cycleAt: FieldValue.serverTimestamp(),
  });
}

// ── Cycle ORION — accès complet à tous les tools ──────────────────────────────

export async function runOrionCycle(uid: string): Promise<{
  skipped: boolean;
  reason?: string;
  pushed?: number;
}> {
  const today = new Date().toISOString().slice(0, 10);
  const count = await getOrionRunCount(uid, today);
  if (count >= ORION_MAX_RUNS) {
    const reason = `Limite journalière atteinte (${count}/${ORION_MAX_RUNS})`;
    await writeCycleLog(uid, { userNeeds: "", userReply: "", actions: [], pushed: 0, skipped: true, skippedReason: reason });
    return { skipped: true, reason };
  }

  await incrementOrionRunCount(uid, today);

  const apiKey = process.env.ANTHROPIC_API_KEY;
  if (!apiKey) throw new Error("ANTHROPIC_API_KEY non configurée dans Firebase Secret Manager");

  const config = await getOrionConfig(uid);
  const client = new Anthropic({ apiKey });

  const userContext = [
    config.userNeeds ? `Instructions de l'utilisateur :\n${config.userNeeds}` : "",
    config.userReply
      ? `Dernière réponse de l'utilisateur (${config.replyTimestamp ?? "récent"}) :\n${config.userReply}`
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
    GET_USER_CONTEXT_TOOL, GET_ASSISTANT_MESSAGES_TOOL, GET_DAY_BLOCKS_TOOL,
    GET_DAY_PLAN_TOOL, GET_DOCUMENTS_TOOL, GET_DOCUMENT_TEMPLATE_TOOL,
    GET_ARCHIVES_TOOL, LIST_PROJECTS_TOOL, GET_PROJECT_TOOL,
    PLAN_DAY_TOOL, CLEAR_DAY_PLAN_TOOL, ADD_TO_DAY_PLAN_TOOL,
    CREATE_ACTIVITY_TOOL, UPDATE_ACTIVITY_TOOL, UPDATE_ACTIVITY_GOAL_TOOL, DELETE_ACTIVITY_TOOL,
    CREATE_ROUTINE_TOOL, DELETE_ROUTINE_TOOL, CREATE_RECURRING_ACTION_TOOL, DELETE_ACTION_TOOL,
    CREATE_DOMAIN_TOOL, DELETE_DOMAIN_TOOL,
    UPDATE_PROJECT_TOOL, UPDATE_TASK_STATUS_TOOL, ARCHIVE_PROJECT_TOOL,
    DELETE_PROJECT_TOOL, PUSH_GANTT_MCP_TOOL,
    LINK_GOAL_TO_TASK_TOOL, DELETE_GOAL_TOOL,
    SAVE_DOCUMENT_TOOL, DELETE_DOCUMENT_TOOL, RESTORE_ITEM_TOOL,
    PUSH_ASSISTANT_MESSAGE_TOOL, DELETE_ASSISTANT_MESSAGE_TOOL,
  ];

  const tools: PromptCachingBetaTool[] = allMcpTools.map((t, i) => ({
    ...toAT(t as Parameters<typeof toAT>[0]),
    ...(i === allMcpTools.length - 1 ? { cache_control: { type: "ephemeral" as const } } : {}),
  }));

  const messages: PromptCachingBetaMessageParam[] = [
    { role: "user", content: "Effectue ton analyse et agis selon mes instructions." },
  ];

  let pushedCount = 0;
  let continueLoop = true;
  const actionLog: string[] = [];

  while (continueLoop) {
    const response = await client.beta.promptCaching.messages.create({
      model: ORION_MODEL,
      max_tokens: 2048,
      system: [{ type: "text", text: systemPrompt, cache_control: { type: "ephemeral" } }],
      tools,
      messages,
    });

    messages.push({ role: "assistant", content: response.content as PromptCachingBetaMessageParam["content"] });

    if (response.stop_reason === "end_turn") {
      continueLoop = false;
      break;
    }

    if (response.stop_reason === "tool_use") {
      const toolResults: Anthropic.ToolResultBlockParam[] = [];

      for (const block of response.content) {
        if (block.type !== "tool_use") continue;
        const args = block.input as Record<string, unknown>;
        let result = "";

        try {
          switch (block.name) {
            // ── Lecture ──────────────────────────────────────────────────
            case "get_user_context":
              result = await executeGetUserContext(uid);
              actionLog.push("📖 Lecture du contexte utilisateur");
              break;
            case "get_assistant_messages":
              result = await executeGetAssistantMessages(uid);
              actionLog.push("📩 Vérification des messages ORION existants");
              break;
            case "get_day_blocks":          result = await executeGetDayBlocks(uid); break;
            case "get_day_plan":            result = await executeGetDayPlan(uid, args.date as string); break;
            case "get_documents":           result = await executeGetDocuments(uid, args.projectId as string | undefined, args.taskId as string | undefined); break;
            case "get_document_template":   result = executeGetDocumentTemplate(); break;
            case "get_archives":            result = await executeGetArchives(uid); break;
            case "list_projects":           result = await executeListProjects(uid); break;
            case "get_project":             result = await executeGetProject(uid, args.projectId as string); break;
            // ── Plan du jour ─────────────────────────────────────────────
            case "plan_day":
              result = await executePlanDay(uid, args.date as string, args.items as Parameters<typeof executePlanDay>[2], (args.clearExisting as boolean) ?? false);
              actionLog.push(`📅 Plan du jour mis à jour (${args.date})`);
              break;
            case "clear_day_plan":
              result = await executeClearDayPlan(uid, args.date as string);
              actionLog.push(`🗑 Plan du jour vidé (${args.date})`);
              break;
            case "add_to_day_plan":
              result = await executeAddToDayPlan(uid, args as Parameters<typeof executeAddToDayPlan>[1]);
              actionLog.push(`➕ Ajout au plan du jour`);
              break;
            // ── Activités ────────────────────────────────────────────────
            case "create_activity":
              result = await executeCreateActivity(uid, args as Parameters<typeof executeCreateActivity>[1]);
              actionLog.push(`✅ Activité créée : ${args.name ?? ""}`);
              break;
            case "update_activity":
              result = await executeUpdateActivity(uid, args.activityId as string, args);
              actionLog.push(`✏️ Activité mise à jour`);
              break;
            case "update_activity_goal":
              result = await executeUpdateActivityGoal(uid, args.activityId as string, args);
              actionLog.push(`🎯 Objectif activité mis à jour`);
              break;
            case "delete_activity":
              result = await executeDeleteActivity(uid, args.activityId as string);
              actionLog.push(`🗑 Activité supprimée`);
              break;
            // ── Routines / Actions ───────────────────────────────────────
            case "create_routine":
              result = await executeCreateRoutine(uid, args as Parameters<typeof executeCreateRoutine>[1]);
              actionLog.push(`✅ Routine créée : ${args.title ?? ""}`);
              break;
            case "delete_routine":
              result = await executeDeleteRoutine(uid, args.routineId as string);
              actionLog.push(`🗑 Routine supprimée`);
              break;
            case "create_recurring_action":
              result = await executeCreateRecurringAction(uid, args as Parameters<typeof executeCreateRecurringAction>[1]);
              actionLog.push(`✅ Action récurrente créée : ${args.title ?? ""}`);
              break;
            case "delete_action":
              result = await executeDeleteAction(uid, args.actionId as string);
              actionLog.push(`🗑 Action supprimée`);
              break;
            // ── Domaines ─────────────────────────────────────────────────
            case "create_domain":
              result = await executeCreateDomain(uid, args as Parameters<typeof executeCreateDomain>[1]);
              actionLog.push(`✅ Domaine créé : ${args.name ?? ""}`);
              break;
            case "delete_domain":
              result = await executeDeleteDomain(uid, args.domainId as string);
              actionLog.push(`🗑 Domaine supprimé`);
              break;
            // ── Projets ──────────────────────────────────────────────────
            case "update_project":
              result = await executeUpdateProject(uid, args.projectId as string, args);
              actionLog.push(`✏️ Projet mis à jour`);
              break;
            case "update_task_status":
              result = await executeUpdateTaskStatus(uid, args.projectId as string, args.taskId as string, args.status as string);
              actionLog.push(`✏️ Statut tâche → ${args.status} (${args.taskId})`);
              break;
            case "archive_project":
              result = await executeArchiveProject(uid, args.projectId as string, (args.restore as boolean) ?? false);
              actionLog.push((args.restore as boolean) ? `♻️ Projet restauré` : `🗄 Projet archivé`);
              break;
            case "delete_project":
              result = await executeDeleteProject(uid, args.projectId as string, (args.deleteObjective as boolean) ?? false);
              actionLog.push(`🗑 Projet supprimé`);
              break;
            case "push_gantt":
              result = await executePushGantt(uid, { uid, ...args } as PushGanttBody);
              actionLog.push(`🗂 Projet Gantt créé : ${(args as unknown as PushGanttBody).project?.title ?? ""}`);
              break;
            // ── Objectifs ────────────────────────────────────────────────
            case "link_goal_to_task":
              result = await executeLinkGoalToTask(uid, args.goalId as string, (args.projectId as string) ?? null, (args.projectTaskId as string) ?? null);
              actionLog.push(`🔗 Objectif lié à une tâche Gantt`);
              break;
            case "delete_goal":
              result = await executeDeleteGoal(uid, args.goalId as string, (args.action as string) ?? "archive");
              actionLog.push(`🗑 Objectif archivé/supprimé`);
              break;
            // ── Documents ────────────────────────────────────────────────
            case "save_document":
              result = await executeSaveDocument(uid, args as Parameters<typeof executeSaveDocument>[1]);
              actionLog.push(`📄 Document sauvegardé : ${args.title ?? ""}`);
              break;
            case "delete_document": {
              const ref = db.collection(`users/${uid}/documents`).doc(args.documentId as string);
              const snap = await ref.get();
              if (!snap.exists) { result = `Document introuvable : ${args.documentId}`; break; }
              await ref.delete();
              result = `✅ Document supprimé.`;
              break;
            }
            case "restore_item":            result = await executeRestoreItem(uid, args.collection as string, args.itemId as string); break;
            // ── Messages ORION ───────────────────────────────────────────
            case "push_assistant_message": {
              result = await executePushAssistantMessage(uid, args as Parameters<typeof executePushAssistantMessage>[1]);
              const msgText = (args.text as string ?? "").slice(0, 80);
              actionLog.push(`💬 Message ORION planifié : "${msgText}${msgText.length >= 80 ? "…" : ""}"`);
              pushedCount++;
              break;
            }
            case "delete_assistant_message": result = await executeDeleteAssistantMessage(uid, args.messageId as string); break;
            default:
              result = `Outil inconnu dans ORION : ${block.name}`;
          }
        } catch (e) {
          result = `Erreur outil ${block.name} : ${e instanceof Error ? e.message : String(e)}`;
        }

        toolResults.push({ type: "tool_result", tool_use_id: block.id, content: result });
      }

      messages.push({ role: "user", content: toolResults as PromptCachingBetaMessageParam["content"] });
    } else {
      continueLoop = false;
    }
  }

  await writeCycleLog(uid, {
    userNeeds: config.userNeeds,
    userReply: config.userReply,
    actions: actionLog,
    pushed: pushedCount,
    skipped: false,
  });

  return { skipped: false, pushed: pushedCount };
}

// ── Itération sur tous les users actifs (pour le cron) ────────────────────────

export async function getAllActiveUserIds(): Promise<string[]> {
  const snap = await db
    .collectionGroup("api_tokens")
    .where("active", "==", true)
    .get();
  const uids = new Set<string>();
  for (const doc of snap.docs) {
    const parts = doc.ref.path.split("/");
    if (parts.length >= 2) uids.add(parts[1]);
  }
  return [...uids];
}
