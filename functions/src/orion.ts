import Anthropic from "@anthropic-ai/sdk";
import type { PromptCachingBetaMessageParam, PromptCachingBetaTool } from "@anthropic-ai/sdk/resources/beta/prompt-caching/messages";
import { db, FieldValue } from "./db";
import {
  executeGetUserContext,
  executeGetAssistantMessages,
  executePushAssistantMessage,
} from "./execute";

const ORION_MAX_RUNS = 5;
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

// ── Cycle ORION ───────────────────────────────────────────────────────────────

export async function runOrionCycle(uid: string): Promise<{
  skipped: boolean;
  reason?: string;
  pushed?: number;
}> {
  const today = new Date().toISOString().slice(0, 10);
  const count = await getOrionRunCount(uid, today);
  if (count >= ORION_MAX_RUNS) {
    return { skipped: true, reason: `Limite journalière atteinte (${count}/${ORION_MAX_RUNS})` };
  }

  // Incrémenter avant l'appel Claude (évite les doublons en cas de retry)
  await incrementOrionRunCount(uid, today);

  const apiKey = process.env.ANTHROPIC_API_KEY;
  if (!apiKey) throw new Error("ANTHROPIC_API_KEY non configurée dans Firebase Secret Manager");

  const config = await getOrionConfig(uid);
  const client = new Anthropic({ apiKey });

  const userContext = [
    config.userNeeds
      ? `Instructions persistantes de l'utilisateur :\n${config.userNeeds}`
      : "",
    config.userReply
      ? `Dernière réponse de l'utilisateur à ORION (${config.replyTimestamp ?? "récent"}) :\n${config.userReply}`
      : "",
  ]
    .filter(Boolean)
    .join("\n\n");

  const systemPrompt = `Tu es ORION, l'assistant IA autonome de Productivitwo. Tu fonctionnes silencieusement en arrière-plan pour soutenir l'utilisateur dans sa productivité et ses objectifs.

Date du jour : ${today}${userContext ? `\n\n${userContext}` : ""}

Mission pour ce cycle :
1. Appelle get_assistant_messages — vérifie les messages ORION en attente pour éviter les doublons.
2. Appelle get_user_context — analyse l'état actuel (activités, objectifs, projets, plan du jour).
3. Génère 1 ou 2 messages ORION pertinents et non-redondants via push_assistant_message.

Règles impératives :
- Aucun doublon avec les messages pending existants.
- Messages courts (< 180 caractères), bienveillants, concrets, actionnables.
- Utilise des conditions contextuelles adaptées (project_deadline_near, overdue_count, week_start, etc.).
- targetDate = aujourd'hui (${today}) ou demain au maximum.
- characterName toujours "ORION".
- Si userReply est fourni, adapte le message en tenant compte de ce retour utilisateur.`;

  // Tools ORION : lecture + push uniquement
  const tools: PromptCachingBetaTool[] = [
    {
      name: "get_user_context",
      description: "Retourne le contexte complet de l'utilisateur (activités, objectifs, plan du jour, projets).",
      input_schema: { type: "object" as const, properties: {}, required: [] },
    },
    {
      name: "get_assistant_messages",
      description: "Liste les messages ORION en attente et récents. Appeler en premier pour éviter les doublons.",
      input_schema: { type: "object" as const, properties: {}, required: [] },
    },
    {
      name: "push_assistant_message",
      description: "Planifie un message ORION contextuel pour l'utilisateur.",
      input_schema: {
        type: "object" as const,
        properties: {
          targetDate: { type: "string", description: "Date YYYY-MM-DD" },
          text: { type: "string", description: "Texte du message (max 180 chars)" },
          condition: {
            type: "object",
            description: "Condition d'affichage. Ex: {type:'always'} ou {type:'overdue_count',min:2}",
          },
          expiresAfterDays: { type: "number", description: "Durée d'expiration en jours (défaut: 2)" },
          priority: { type: "number", description: "Priorité 1 (haute) à 5 (basse)" },
        },
        required: ["targetDate", "text", "condition"],
      },
      // Cache les tool schemas (statiques entre appels)
      cache_control: { type: "ephemeral" },
    },
  ];

  const messages: PromptCachingBetaMessageParam[] = [
    { role: "user", content: "Effectue ton analyse et génère les messages ORION pour aujourd'hui." },
  ];

  let pushedCount = 0;
  let continueLoop = true;

  while (continueLoop) {
    const response = await client.beta.promptCaching.messages.create({
      model: ORION_MODEL,
      max_tokens: 1024,
      system: [
        {
          type: "text",
          text: systemPrompt,
          cache_control: { type: "ephemeral" },
        },
      ],
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

        let result = "";
        try {
          if (block.name === "get_user_context") {
            result = await executeGetUserContext(uid);
          } else if (block.name === "get_assistant_messages") {
            result = await executeGetAssistantMessages(uid);
          } else if (block.name === "push_assistant_message") {
            result = await executePushAssistantMessage(
              uid,
              block.input as Parameters<typeof executePushAssistantMessage>[1]
            );
            pushedCount++;
          } else {
            result = `Outil non disponible dans ORION : ${block.name}`;
          }
        } catch (e) {
          result = `Erreur outil ${block.name} : ${e instanceof Error ? e.message : String(e)}`;
        }

        toolResults.push({
          type: "tool_result",
          tool_use_id: block.id,
          content: result,
        });
      }

      messages.push({ role: "user", content: toolResults as PromptCachingBetaMessageParam["content"] });
    } else {
      continueLoop = false;
    }
  }

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
    // path : users/{uid}/api_tokens/{id}
    const parts = doc.ref.path.split("/");
    if (parts.length >= 2) uids.add(parts[1]);
  }
  return [...uids];
}
