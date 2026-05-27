import Anthropic from "@anthropic-ai/sdk";
import { MODELS, logTokenUsage } from "./models";
import type { PromptCachingBetaMessageParam, PromptCachingBetaTool } from "@anthropic-ai/sdk/resources/beta/prompt-caching/messages";
import { db, FieldValue } from "./db";
import {
  executeGetOrionContext, executeGetAssistantMessages, executePushAssistantMessage,
  executeDeleteAssistantMessage, executeUpdateActivityGoal, executeCreateRoutine,
  executeGetDayBlocks, executeCreateActivity,
  executeUpdateActivity, executeDeleteActivity,
  executeCreateDomain, executeDeleteDomain,
  executeListProjects, executeGetProject, executePushGantt, executeUpdateProject,
  executeUpdateTaskStatus, executeArchiveProject, executeDeleteProject,
  executeLinkGoalToTask, executeDeleteGoal, executeDeleteRoutine,
  executeGetDocuments, executeSaveDocument, executeGetDocumentTemplate,
  executeGetArchives, executeRestoreItem,
  executeGetInbox, executeProcessInboxItem,
  executeGetDaySchedule, executeScheduleDay, executeUpdateScheduleBlock,
  executeComputeTimeBudget,
  executeGetOrionQueue, executeDeleteOrionQueueItem,
} from "./execute";
// Descriptions compactes pour ORION — ~10x moins de tokens que les tools MCP complets
const ORION_TOOLS: PromptCachingBetaTool[] = [
  { name: "get_orion_context",        description: "Contexte utilisateur : domaines, activités, routines, objectifs, projets actifs (tâches urgentes), plan du jour résumé, stats 7j.",   input_schema: { type: "object", properties: {}, required: [] } },
  { name: "get_assistant_messages",   description: "Messages ORION en attente et récents. Appeler en premier pour éviter les doublons.",                                                   input_schema: { type: "object", properties: {}, required: [] } },
  { name: "get_day_blocks",           description: "Blocs de journée configurés.",                                                                                                         input_schema: { type: "object", properties: {}, required: [] } },
  { name: "get_documents",            description: "Documents de l'utilisateur, filtrables par projectId/taskId.",                                                                         input_schema: { type: "object", properties: { projectId: { type: "string" }, taskId: { type: "string" } }, required: [] } },
  { name: "get_archives",             description: "Éléments archivés/supprimés.",                                                                                                        input_schema: { type: "object", properties: {}, required: [] } },
  { name: "list_projects",            description: "Liste résumée des projets Gantt.",                                                                                                     input_schema: { type: "object", properties: {}, required: [] } },
  { name: "get_project",              description: "Détail complet d'un projet Gantt (phases, tâches, IDs).",                                                                             input_schema: { type: "object", properties: { projectId: { type: "string" } }, required: ["projectId"] } },
  { name: "create_activity",          description: "Crée une activité (temps ou habitude).",                                                                                              input_schema: { type: "object", properties: { name: { type: "string" }, type: { type: "string" }, domainId: { type: "string" } }, required: ["name", "type", "domainId"] } },
  { name: "update_activity",          description: "Met à jour une activité.",                                                                                                            input_schema: { type: "object", properties: { activityId: { type: "string" } }, required: ["activityId"] } },
  { name: "update_activity_goal",     description: "Met à jour l'objectif quotidien d'une activité.",                                                                                    input_schema: { type: "object", properties: { activityId: { type: "string" }, goalMin: { type: "number" } }, required: ["activityId"] } },
  { name: "delete_activity",          description: "Supprime (soft-delete) une activité.",                                                                                               input_schema: { type: "object", properties: { activityId: { type: "string" } }, required: ["activityId"] } },
  { name: "create_routine",           description: "Crée une routine récurrente.",                                                                                                        input_schema: { type: "object", properties: { title: { type: "string" }, activityId: { type: "string" } }, required: ["title", "activityId"] } },
  { name: "delete_routine",           description: "Supprime une routine.",                                                                                                               input_schema: { type: "object", properties: { routineId: { type: "string" } }, required: ["routineId"] } },

  { name: "create_domain",            description: "Crée un domaine de vie.",                                                                                                             input_schema: { type: "object", properties: { name: { type: "string" } }, required: ["name"] } },
  { name: "delete_domain",            description: "Supprime un domaine.",                                                                                                                input_schema: { type: "object", properties: { domainId: { type: "string" } }, required: ["domainId"] } },
  { name: "update_project",           description: "Met à jour les champs d'un projet Gantt.",                                                                                           input_schema: { type: "object", properties: { projectId: { type: "string" } }, required: ["projectId"] } },
  { name: "update_task_status",       description: "Change le statut d'une tâche (pending/done/skipped).",                                                                               input_schema: { type: "object", properties: { projectId: { type: "string" }, taskId: { type: "string" }, status: { type: "string" } }, required: ["projectId", "taskId", "status"] } },
  { name: "archive_project",          description: "Archive ou restaure un projet.",                                                                                                      input_schema: { type: "object", properties: { projectId: { type: "string" }, restore: { type: "boolean" } }, required: ["projectId"] } },
  { name: "delete_project",           description: "Supprime définitivement un projet.",                                                                                                  input_schema: { type: "object", properties: { projectId: { type: "string" }, deleteObjective: { type: "boolean" } }, required: ["projectId"] } },
  { name: "push_gantt", description: "Crée ou met à jour un projet Gantt. TOUJOURS inclure phases[] ET tasks[] — sans tasks le projet sera vide.", input_schema: { type: "object", required: ["project"], properties: { project: { type: "object", required: ["title", "startDate", "tasks"], properties: { title: { type: "string" }, description: { type: "string" }, domainId: { type: "string" }, startDate: { type: "string", description: "YYYY-MM-DD" }, endDate: { type: "string", description: "YYYY-MM-DD" }, phases: { type: "array", items: { type: "object", required: ["id", "label", "startDate", "endDate"], properties: { id: { type: "string", description: "ex: phase-1" }, label: { type: "string" }, startDate: { type: "string" }, endDate: { type: "string" }, color: { type: "string" } } } }, tasks: { type: "array", description: "OBLIGATOIRE : au moins 2 tâches par phase", items: { type: "object", required: ["id", "title", "startDate"], properties: { id: { type: "string", description: "ex: task-1" }, title: { type: "string" }, phaseId: { type: "string" }, startDate: { type: "string", description: "YYYY-MM-DD" }, endDate: { type: "string", description: "YYYY-MM-DD" }, isMilestone: { type: "boolean" }, status: { type: "string", enum: ["pending", "done", "skipped"] } } } } } } } } },
  { name: "link_goal_to_task",        description: "Lie un objectif GTD à une tâche Gantt.",                                                                                              input_schema: { type: "object", properties: { goalId: { type: "string" }, projectId: { type: "string" }, projectTaskId: { type: "string" } }, required: ["goalId"] } },
  { name: "delete_goal",              description: "Archive ou supprime un objectif GTD.",                                                                                                input_schema: { type: "object", properties: { goalId: { type: "string" }, action: { type: "string" } }, required: ["goalId"] } },
  { name: "save_document",            description: "Sauvegarde un document HTML.",                                                                                                        input_schema: { type: "object", properties: { title: { type: "string" }, content: { type: "string" } }, required: ["title", "content"] } },
  { name: "delete_document",          description: "Supprime un document.",                                                                                                               input_schema: { type: "object", properties: { documentId: { type: "string" } }, required: ["documentId"] } },
  { name: "restore_item",             description: "Restaure un élément archivé.",                                                                                                        input_schema: { type: "object", properties: { collection: { type: "string" }, itemId: { type: "string" } }, required: ["collection", "itemId"] } },
  { name: "push_assistant_message",   description: "Planifie un message ORION contextuel. Utilise requiresReply:true pour les messages de clarification (l'utilisateur doit répondre) — ils s'affichent sans limite et disparaissent dès que l'utilisateur répond.",                input_schema: { type: "object", properties: { targetDate: { type: "string" }, text: { type: "string" }, condition: { type: "object" }, expiresAfterDays: { type: "number" }, priority: { type: "number" }, requiresReply: { type: "boolean" } }, required: ["targetDate", "text", "condition"] } },
  { name: "delete_assistant_message", description: "Supprime un message ORION.",                                                                                                          input_schema: { type: "object", properties: { messageId: { type: "string" } }, required: ["messageId"] } },
  { name: "get_orion_queue",         description: "File de travail : instructions spécifiques que l'utilisateur a envoyées en réponse à un message ORION. À lire EN PREMIER, avant l'inbox. Chaque item est une action concrète à exécuter immédiatement.",                                     input_schema: { type: "object", properties: {}, required: [] } },
  { name: "delete_orion_queue_item", description: "Supprime un item de la file après traitement.",                                                                                                                                                                                                         input_schema: { type: "object", properties: { itemId: { type: "string" } }, required: ["itemId"] } },
  { name: "get_inbox",               description: "Idées et notes capturées par l'utilisateur en attente de traitement.",                                                                  input_schema: { type: "object", properties: {}, required: [] } },
  { name: "process_inbox_item",      description: "Marque une idée inbox comme traitée avec une note expliquant l'action prise.",                                                          input_schema: { type: "object", properties: { itemId: { type: "string" }, note: { type: "string", description: "Ce qu'ORION a fait : ex: 'ajouté comme tâche dans Projet X' ou 'message reminder planifié'" } }, required: ["itemId", "note"] } },
  { name: "get_day_schedule",        description: "Lit le programme horaire d'une journée.",                                                                                               input_schema: { type: "object", properties: { date: { type: "string", description: "YYYY-MM-DD" } }, required: ["date"] } },
  { name: "update_schedule_block",   description: "Met à jour le statut d'un bloc du programme du jour (done/skipped/deleted/pending) sans écraser tout le programme.",                   input_schema: { type: "object", properties: { date: { type: "string", description: "YYYY-MM-DD" }, blockTitle: { type: "string", description: "Titre (partiel) du bloc à modifier" }, status: { type: "string", enum: ["done", "skipped", "deleted", "pending"] } }, required: ["date", "blockTitle", "status"] } },
  { name: "compute_time_budget",     description: "Calcule le budget temps 24h basé sur 12 semaines de sessions réelles. Retourne le goalMin recommandé par activité (stretch avg×1.10) et le sommeil résiduel pour sommer à 1440 min/j. À appeler le lundi avant update_activity_goal.",                input_schema: { type: "object", properties: {}, required: [] } },
  { name: "schedule_day",            description: "Crée ou remplace le programme horaire complet d'une journée.",                                                                          input_schema: { type: "object", properties: { date: { type: "string" }, blocks: { type: "array", items: { type: "object", required: ["startTime", "durationMin", "title", "category"], properties: { startTime: { type: "string" }, durationMin: { type: "number" }, title: { type: "string" }, category: { type: "string", enum: ["project", "routine", "personal", "break"] }, projectId: { type: "string" }, taskId: { type: "string" }, activityId: { type: "string" } } } } }, required: ["date", "blocks"], }, cache_control: { type: "ephemeral" } },
];
import type { PushGanttBody } from "./types";

const ORION_MAX_RUNS = 30;
const ORION_MODEL = MODELS.HAIKU;

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

export async function incrementOrionRunCount(uid: string, date: string): Promise<void> {
  await db
    .collection("orion_runs")
    .doc(`${uid}_${date}`)
    .set({ count: FieldValue.increment(1), uid, date }, { merge: true });
}

// ── Log de cycle ──────────────────────────────────────────────────────────────

export async function writeCycleLog(uid: string, log: {
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

export async function runOrionCycle(uid: string, opts?: { skipCount?: boolean }): Promise<{
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

  // isOnboarding → on ne décompte pas cette action stratégique
  if (!opts?.skipCount) {
    await incrementOrionRunCount(uid, today);
  }

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

  const nowParis = new Date().toLocaleString("fr-FR", { timeZone: "Europe/Paris", hour: "2-digit", minute: "2-digit" });
  const hourParis = new Date(new Date().toLocaleString("en-US", { timeZone: "Europe/Paris" })).getHours();
  const timeSlot = hourParis < 10 ? "matin" : hourParis < 13 ? "fin de matinée" : hourParis < 17 ? "après-midi" : hourParis < 21 ? "soirée" : "nuit";

  const systemPrompt = `Tu es ORION, le coach IA de Productivitwo. Tu tournes en continu et envoies des messages courts, contextuels, comme un coach qui suit l'utilisateur tout au long de sa journée.

Date et heure : ${today} ${nowParis} (${timeSlot})${userContext ? `\n\n${userContext}` : ""}

## Contexte déjà disponible

Le contexte utilisateur et les messages ORION existants sont fournis directement dans le message — tu n'as PAS besoin d'appeler get_orion_context ou get_assistant_messages.

## Workflow OBLIGATOIRE

1. Lis le contexte et les messages existants dans le message fourni.
2. **PRIORITÉ ABSOLUE** : appelle get_orion_queue — si des instructions y sont en attente, exécute-les IMMÉDIATEMENT comme actions concrètes (push_gantt, update_project, create_activity…), puis delete_orion_queue_item pour chaque item traité. Ne passe à l'étape suivante qu'après avoir vidé la file.
3. Appelle get_inbox — si des idées sont en attente, traite-les (voir règles inbox ci-dessous).
4. Si l'utilisateur a donné une instruction spécifique → exécute-la avec les outils appropriés.
4. TOUJOURS terminer par push_assistant_message — MINIMUM 1 message, MAXIMUM 3.
5. Si plusieurs push, appelle-les dans la MÊME réponse (tool use parallèle) pour économiser des tokens.

## Traitement de l'inbox

L'utilisateur peut capturer des idées rapides dans son inbox. À chaque cycle, tu lis ces idées et tu les traites selon leur nature :

- **Note ponctuelle** ("acheter du lait", "appeler X", rappel) → push_assistant_message avec condition always pour aujourd'hui ou demain + process_inbox_item(note: "message reminder planifié pour le [date]")
- **Idée liée à un projet existant** → ajoute une sous-action à la tâche pertinente ou mets à jour le projet + process_inbox_item(note: "ajouté comme sous-action dans [projet > tâche]")
- **Nouvelle initiative / projet** → push_gantt pour créer le projet + process_inbox_item(note: "projet '[titre]' créé")
- **Idée vague ou hors scope** → process_inbox_item(note: "noté — pas d'action immédiate") + optionnel: push_assistant_message pour demander de clarifier

Appelle toujours process_inbox_item après avoir traité une idée. Ne laisse jamais une idée pending non traitée.

## Ton de coach — adapté à l'heure

- **Matin (6h-10h)** : énergie, intention du jour, rappel des priorités urgentes
- **Fin de matinée (10h-13h)** : focus sur la tâche en cours, blocages à lever
- **Après-midi (13h-17h)** : avancement, recalibration si en retard
- **Soirée (17h-21h)** : bilan partiel, préparation du lendemain, récupération
- **Nuit (21h+)** : court, bienveillant, prépare la tête du lendemain — pas d'action urgente

Adapte systématiquement le contenu et le ton au créneau horaire actuel (${timeSlot}).
Ne répète jamais un message récent — vérifie recentShown pour éviter les doublons thématiques.

## RÈGLE ABSOLUE : tu DOIS pousser au moins 1 message avant de terminer

Même si tu n'as fait aucune action, même s'il n'y a rien d'urgent — pousse toujours un message de synthèse. Le cycle n'est jamais "vide".

## Types d'instructions et réponses attendues

**"Analyse mes retards / propose un plan de rattrapage"**
→ Lis projects[].urgentTasks dans le contexte
→ Pousse 2-3 messages ciblés : un par tâche/projet en retard, avec condition overdue_count ou project_deadline_near
→ Pour chaque message, inclus une action concrète (ex: open_gantt_task)
→ targetDate = aujourd'hui, condition: {type:"always"} pour affichage immédiat

**"Bilan de semaine / rapport de progression"**
→ Lis habitStats et timeStats dans le contexte
→ Pousse un message résumant les points clés (ce qui a bien marché, ce qui est en retard)

**"Archiver les projets inactifs"**
→ Liste les projets dans get_orion_context, ceux sans tâches urgentes = inactifs
→ Appelle archive_project pour chacun
→ Pousse un message listant ce qui a été archivé

**"Crée un projet [nom]" ou demande de création de projet**
→ Utilise push_gantt pour créer le projet avec une structure raisonnable déduite du contexte : 3-4 phases, 2-4 tâches chacune, dates réalistes à partir d'aujourd'hui
→ Si le domaine n'est pas précisé, choisis le plus cohérent parmi les domaines existants dans le contexte
→ Pousse ensuite un push_assistant_message confirmant ce qui a été créé (titre du projet, nb de phases/tâches)

**Lundi matin — rééquilibrage du budget temps 24h**
→ compute_time_budget → pour chaque activité avec id non-null : update_activity_goal(activityId, goalMin=recommendedGoalMin)
→ Si l'activité "Sommeil" est absente (id: null) → create_activity(name="Sommeil", domainId=<domaine Santé/Bien-être>)
→ push_assistant_message : liste concise des objectifs rééquilibrés (ex: "Sport : 45min/j → 49min/j · Sommeil : 7h30")
→ Ne pas exécuter si déjà fait cette semaine (vérifie recentShown pour un message de type "budget")

**Instruction ambiguë (sans supression/delete)**
→ Interprète au mieux, agis, puis pousse un message expliquant ce que tu as fait et demandant si c'est correct

**Instruction destructive (delete, supprimer définitivement)**
→ Ne pas agir — pousse un message demandant confirmation explicite

## RAPPEL ABSOLU : ne jamais terminer sans push_assistant_message

Tu dois TOUJOURS appeler push_assistant_message avant end_turn, quelle que soit la situation. Si tu n'as rien fait d'autre, pousse au moins un message de synthèse de ce que tu as observé.

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
    logTokenUsage("orion_cycle", ORION_MODEL, response.usage as Parameters<typeof logTokenUsage>[2]);

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
            case "get_documents":           result = await executeGetDocuments(uid, args.projectId as string | undefined, args.taskId as string | undefined); break;
            case "get_document_template":   result = executeGetDocumentTemplate(); break;
            case "get_archives":            result = await executeGetArchives(uid); break;
            case "list_projects":           result = await executeListProjects(uid); break;
            case "get_project":             result = await executeGetProject(uid, args.projectId as string); break;
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
            // ── Inbox ─────────────────────────────────────────────────────
            case "get_orion_queue":
              result = await executeGetOrionQueue(uid);
              actionLog.push("📬 Lecture de la file Orion");
              break;
            case "delete_orion_queue_item":
              result = await executeDeleteOrionQueueItem(uid, args.itemId as string);
              actionLog.push("✅ Instruction file Orion traitée");
              break;
            case "get_inbox":           result = await executeGetInbox(uid); break;
            case "process_inbox_item":  result = await executeProcessInboxItem(uid, args.itemId as string, args.note as string);
              actionLog.push(`💡 Idée traitée depuis l'inbox`);
              break;
            // ── Programme du jour ──────────────────────────────────────────
            case "compute_time_budget":
              result = await executeComputeTimeBudget(uid);
              actionLog.push("📊 Budget temps 24h calculé (12 semaines)");
              break;
            case "get_day_schedule":       result = await executeGetDaySchedule(uid, args.date as string); break;
            case "update_schedule_block":
              result = await executeUpdateScheduleBlock(uid, args.date as string, args.blockTitle as string, args.status as "done" | "skipped" | "deleted" | "pending");
              actionLog.push(`📅 Bloc programme mis à jour`);
              break;
            case "schedule_day":
              result = await executeScheduleDay(uid, args.date as string, args.blocks as []);
              actionLog.push(`📅 Programme du jour enregistré`);
              break;
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
  const uids = new Set<string>();

  // Utilisateurs MCP (avec token API actif)
  const tokenSnap = await db
    .collectionGroup("api_tokens")
    .where("active", "==", true)
    .get();
  for (const doc of tokenSnap.docs) {
    const parts = doc.ref.path.split("/");
    if (parts.length >= 2) uids.add(parts[1]);
  }

  // Utilisateurs app (iOS/Android) inscrits au cron ORION
  const subSnap = await db
    .collectionGroup("orion_subscription")
    .where("enabled", "==", true)
    .get();
  for (const doc of subSnap.docs) {
    const parts = doc.ref.path.split("/");
    if (parts.length >= 2) uids.add(parts[1]);
  }

  return [...uids];
}
