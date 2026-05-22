import Anthropic from "@anthropic-ai/sdk";
import type { PromptCachingBetaMessageParam, PromptCachingBetaTool } from "@anthropic-ai/sdk/resources/beta/prompt-caching/messages";
import { db, FieldValue } from "./db";
import {
  executeGetOrionContext, executeGetAssistantMessages, executePushAssistantMessage,
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
// Descriptions compactes pour ORION — ~10x moins de tokens que les tools MCP complets
const ORION_TOOLS: PromptCachingBetaTool[] = [
  { name: "get_orion_context",        description: "Contexte utilisateur : domaines, activités, routines, objectifs, projets actifs (tâches urgentes), plan du jour résumé, stats 7j.",   input_schema: { type: "object", properties: {}, required: [] } },
  { name: "get_assistant_messages",   description: "Messages ORION en attente et récents. Appeler en premier pour éviter les doublons.",                                                   input_schema: { type: "object", properties: {}, required: [] } },
  { name: "get_day_blocks",           description: "Blocs de journée configurés.",                                                                                                         input_schema: { type: "object", properties: {}, required: [] } },
  { name: "get_day_plan",             description: "Plan du jour pour une date donnée.",                                                                                                   input_schema: { type: "object", properties: { date: { type: "string", description: "YYYYMMDD" } }, required: ["date"] } },
  { name: "get_documents",            description: "Documents de l'utilisateur, filtrables par projectId/taskId.",                                                                         input_schema: { type: "object", properties: { projectId: { type: "string" }, taskId: { type: "string" } }, required: [] } },
  { name: "get_archives",             description: "Éléments archivés/supprimés.",                                                                                                        input_schema: { type: "object", properties: {}, required: [] } },
  { name: "list_projects",            description: "Liste résumée des projets Gantt.",                                                                                                     input_schema: { type: "object", properties: {}, required: [] } },
  { name: "get_project",              description: "Détail complet d'un projet Gantt (phases, tâches, IDs).",                                                                             input_schema: { type: "object", properties: { projectId: { type: "string" } }, required: ["projectId"] } },
  { name: "plan_day",                 description: "Planifie des actions pour une date.",                                                                                                  input_schema: { type: "object", properties: { date: { type: "string" }, items: { type: "array" }, clearExisting: { type: "boolean" } }, required: ["date", "items"] } },
  { name: "clear_day_plan",           description: "Vide le plan du jour d'une date.",                                                                                                    input_schema: { type: "object", properties: { date: { type: "string" } }, required: ["date"] } },
  { name: "add_to_day_plan",          description: "Ajoute un élément au plan du jour.",                                                                                                  input_schema: { type: "object", properties: { title: { type: "string" }, yyyymmdd: { type: "string" } }, required: ["title", "yyyymmdd"] } },
  { name: "create_activity",          description: "Crée une activité (temps ou habitude).",                                                                                              input_schema: { type: "object", properties: { name: { type: "string" }, type: { type: "string" }, domainId: { type: "string" } }, required: ["name", "type", "domainId"] } },
  { name: "update_activity",          description: "Met à jour une activité.",                                                                                                            input_schema: { type: "object", properties: { activityId: { type: "string" } }, required: ["activityId"] } },
  { name: "update_activity_goal",     description: "Met à jour l'objectif quotidien d'une activité.",                                                                                    input_schema: { type: "object", properties: { activityId: { type: "string" }, goalMin: { type: "number" } }, required: ["activityId"] } },
  { name: "delete_activity",          description: "Supprime (soft-delete) une activité.",                                                                                               input_schema: { type: "object", properties: { activityId: { type: "string" } }, required: ["activityId"] } },
  { name: "create_routine",           description: "Crée une routine récurrente.",                                                                                                        input_schema: { type: "object", properties: { title: { type: "string" }, activityId: { type: "string" } }, required: ["title", "activityId"] } },
  { name: "delete_routine",           description: "Supprime une routine.",                                                                                                               input_schema: { type: "object", properties: { routineId: { type: "string" } }, required: ["routineId"] } },
  { name: "create_recurring_action",  description: "Crée une action récurrente (sans tracking).",                                                                                        input_schema: { type: "object", properties: { title: { type: "string" }, activityId: { type: "string" } }, required: ["title", "activityId"] } },
  { name: "delete_action",            description: "Supprime une action récurrente.",                                                                                                     input_schema: { type: "object", properties: { actionId: { type: "string" } }, required: ["actionId"] } },
  { name: "create_domain",            description: "Crée un domaine de vie.",                                                                                                             input_schema: { type: "object", properties: { name: { type: "string" } }, required: ["name"] } },
  { name: "delete_domain",            description: "Supprime un domaine.",                                                                                                                input_schema: { type: "object", properties: { domainId: { type: "string" } }, required: ["domainId"] } },
  { name: "update_project",           description: "Met à jour les champs d'un projet Gantt.",                                                                                           input_schema: { type: "object", properties: { projectId: { type: "string" } }, required: ["projectId"] } },
  { name: "update_task_status",       description: "Change le statut d'une tâche (pending/done/skipped).",                                                                               input_schema: { type: "object", properties: { projectId: { type: "string" }, taskId: { type: "string" }, status: { type: "string" } }, required: ["projectId", "taskId", "status"] } },
  { name: "archive_project",          description: "Archive ou restaure un projet.",                                                                                                      input_schema: { type: "object", properties: { projectId: { type: "string" }, restore: { type: "boolean" } }, required: ["projectId"] } },
  { name: "delete_project",           description: "Supprime définitivement un projet.",                                                                                                  input_schema: { type: "object", properties: { projectId: { type: "string" }, deleteObjective: { type: "boolean" } }, required: ["projectId"] } },
  { name: "push_gantt",               description: "Crée ou met à jour un projet Gantt complet (phases + tâches).",                                                                      input_schema: { type: "object", properties: { project: { type: "object" } }, required: ["project"] } },
  { name: "link_goal_to_task",        description: "Lie un objectif GTD à une tâche Gantt.",                                                                                              input_schema: { type: "object", properties: { goalId: { type: "string" }, projectId: { type: "string" }, projectTaskId: { type: "string" } }, required: ["goalId"] } },
  { name: "delete_goal",              description: "Archive ou supprime un objectif GTD.",                                                                                                input_schema: { type: "object", properties: { goalId: { type: "string" }, action: { type: "string" } }, required: ["goalId"] } },
  { name: "save_document",            description: "Sauvegarde un document HTML.",                                                                                                        input_schema: { type: "object", properties: { title: { type: "string" }, content: { type: "string" } }, required: ["title", "content"] } },
  { name: "delete_document",          description: "Supprime un document.",                                                                                                               input_schema: { type: "object", properties: { documentId: { type: "string" } }, required: ["documentId"] } },
  { name: "restore_item",             description: "Restaure un élément archivé.",                                                                                                        input_schema: { type: "object", properties: { collection: { type: "string" }, itemId: { type: "string" } }, required: ["collection", "itemId"] } },
  { name: "push_assistant_message",   description: "Planifie un message ORION contextuel.",                                                                                               input_schema: { type: "object", properties: { targetDate: { type: "string" }, text: { type: "string" }, condition: { type: "object" }, expiresAfterDays: { type: "number" }, priority: { type: "number" } }, required: ["targetDate", "text", "condition"] } },
  { name: "delete_assistant_message", description: "Supprime un message ORION.",                                                                                                          input_schema: { type: "object", properties: { messageId: { type: "string" } }, required: ["messageId"] }, cache_control: { type: "ephemeral" } },
];
import type { PushGanttBody } from "./types";

const ORION_MAX_RUNS = 50;
const ORION_MODEL = "claude-haiku-4-5-20251001";

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

  const systemPrompt = `Tu es ORION, l'agent IA autonome de Productivitwo. Tu as accès à tous les outils de l'app.

Date du jour : ${today}${userContext ? `\n\n${userContext}` : ""}

## Contexte déjà disponible

Le contexte utilisateur et les messages ORION existants sont fournis directement dans le message — tu n'as PAS besoin d'appeler get_orion_context ou get_assistant_messages.

## Workflow OBLIGATOIRE

1. Lis le contexte et les messages existants dans le message fourni.
2. Si l'utilisateur a donné une instruction spécifique → exécute-la avec les outils appropriés.
3. TOUJOURS terminer par push_assistant_message — MINIMUM 1 message, MAXIMUM 3.
4. Si plusieurs push, appelle-les dans la MÊME réponse (tool use parallèle) pour économiser des tokens.

## RÈGLE ABSOLUE : tu DOIS pousser au moins 1 message avant de terminer

Même si tu n'as fait aucune action, même s'il n'y a rien d'urgent — pousse toujours un message de synthèse. Le cycle n'est jamais "vide".

## Types d'instructions et réponses attendues

**"Analyse mes retards / propose un plan de rattrapage"**
→ Lis planSummary.overdue et projects[].urgentTasks dans le contexte
→ Pousse 2-3 messages ciblés : un par tâche/projet en retard, avec condition overdue_count ou project_deadline_near
→ Pour chaque message, inclus une action concrète (ex: open_gantt_task)
→ targetDate = aujourd'hui, condition: {type:"always"} pour affichage immédiat

**"Bilan de semaine / rapport de progression"**
→ Lis habitStats et timeStats dans le contexte
→ Pousse un message résumant les points clés (ce qui a bien marché, ce qui est en retard)

**"Optimiser mon plan du jour"**
→ Appelle get_day_plan(today) pour voir ce qui est planifié
→ Utilise plan_day pour ajouter les tâches urgentes manquantes
→ Pousse un message confirmant les changements

**"Archiver les projets inactifs"**
→ Liste les projets dans get_orion_context, ceux sans tâches urgentes = inactifs
→ Appelle archive_project pour chacun
→ Pousse un message listant ce qui a été archivé

**Instruction ambiguë ou destructive (delete)**
→ Ne pas agir — pousse un message demandant confirmation

## Format des messages
- Courts (< 180 chars), bienveillants, actionnables
- characterName: "ORION"
- Pas de doublons avec les messages pending existants
- targetDate = aujourd'hui (${today}) sauf si contexte spécifique justifie demain`;

  let pushedCount = 0;
  let continueLoop = true;
  const actionLog: string[] = [];

  // Pré-fetch contexte + messages existants — évite 2 turns d'API coûteux
  const [orionContext, existingMessages] = await Promise.all([
    executeGetOrionContext(uid),
    executeGetAssistantMessages(uid),
  ]);
  actionLog.push("📖 Lecture du contexte utilisateur");
  actionLog.push("📩 Vérification des messages ORION existants");

  // Tools réduits : le contexte est déjà injecté, pas besoin de le refetcher
  const tools = ORION_TOOLS.filter((t) =>
    !["get_orion_context", "get_assistant_messages"].includes(t.name)
  );
  // Cache sur le dernier tool de la liste filtrée
  if (tools.length > 0 && !tools[tools.length - 1].cache_control) {
    tools[tools.length - 1] = { ...tools[tools.length - 1], cache_control: { type: "ephemeral" } };
  }

  const firstMessage = [
    `## Contexte utilisateur\n${orionContext}`,
    `## Messages ORION déjà en attente\n${existingMessages}`,
    config.userNeeds ? `## Instruction\n${config.userNeeds}` : "## Instruction\nAnalyse autonome : génère des messages ORION pertinents.",
    config.userReply ? `## Réponse de l'utilisateur au dernier message\n${config.userReply}` : "",
  ].filter(Boolean).join("\n\n");

  const messages: PromptCachingBetaMessageParam[] = [
    { role: "user", content: firstMessage },
  ];

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
            case "get_orion_context":
              result = await executeGetOrionContext(uid);
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
