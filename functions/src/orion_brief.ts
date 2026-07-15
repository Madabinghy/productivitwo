import Anthropic from "@anthropic-ai/sdk";
import { db, FieldValue } from "./db";
import { MODELS, logTokenUsage } from "./models";
import { processInboxToProjects } from "./orion_inbox";
import { evaluateProjectRestructures } from "./orion_restructure";

// ── Types ────────────────────────────────────────────────────────────────────

export type Brief = {
  date: string;
  focus: string | null;
  priorityAction: string;
  risk: string | null;
  question: string | null;
  productivityLever: string | null;
  feedback: "useful" | "skip" | null;
  feedbackAt: string | null;
  createdAt: string;
};

function todayInParis(d: Date = new Date()): string {
  return d.toLocaleDateString("sv-SE", { timeZone: "Europe/Paris" });
}

// ── Focus ────────────────────────────────────────────────────────────────────

export async function getFocus(uid: string): Promise<string> {
  const snap = await db.collection(`users/${uid}/orion_config`).doc("main").get();
  return (snap.data()?.focus as string) ?? "";
}

export async function setFocus(uid: string, focus: string): Promise<void> {
  await db.collection(`users/${uid}/orion_config`).doc("main").set(
    {
      focus: focus.trim(),
      focusUpdatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true }
  );
}

// ── Brief ────────────────────────────────────────────────────────────────────

const BRIEF_PROMPT = `Tu es ORION, le stratège quotidien de l'utilisateur de Productivitwo.

Le FOCUS ACTUEL de l'utilisateur :
{{FOCUS}}

État de ses projets et activités (concis) :
{{CONTEXT}}

Aujourd'hui : {{TODAY}}

Productivité du jour (équilibre routines / temps / projets) :
{{LEVER}}

Tu produis un brief structuré pour aujourd'hui. Réponds UNIQUEMENT en JSON valide, sans markdown ni texte autour :
{
  "priorityAction": "1 phrase concrète et SPÉCIFIQUE à son contexte — l'action la plus stratégique aujourd'hui pour avancer son focus",
  "risk": "1 phrase ou null — UNIQUEMENT s'il existe un élément à traiter AUJOURD'HUI sous peine de le rater (deadline du jour, échéance imminente, créneau qui se ferme). Sinon null. Pas de risque général ni de vigilance vague",
  "question": "1 phrase ou null — une question stratégique qui pousse à la réflexion. null si pas nécessaire aujourd'hui",
  "productivityLever": "1 phrase ou null — UNIQUEMENT si un levier (dimension en retard) est fourni ci-dessus. Coaching concret pour rattraper cette dimension aujourd'hui, relié à son focus si possible. Sinon null"
}

RÈGLES STRICTES :
- Tout doit converger vers son FOCUS
- Concret et spécifique — JAMAIS de motivation creuse ou de conseil générique (genre "fais du sport")
- Si rien de pertinent pour risk ou question, mets null. Ne remplis pas pour remplir
- productivityLever : ne le remplis QUE si une dimension en retard est explicitement fournie dans « Productivité du jour ». Sinon null. N'invente JAMAIS de levier
- Ton ferme et direct — tu es un stratège, pas un coach mou
- Maximum 25 mots par champ`;

async function buildBriefContext(
  uid: string
): Promise<{ text: string; leverBlock: string; hasLever: boolean }> {
  // Projets actifs avec leur progression
  const projectsSnap = await db.collection(`users/${uid}/projects`)
    .where("status", "==", "active")
    .get();

  const projects = projectsSnap.docs.slice(0, 8).map((d) => {
    const data = d.data();
    const tasks = (data.tasks as Array<{ status?: string }>) ?? [];
    const done = tasks.filter((t) => t.status === "done").length;
    const total = tasks.length;
    const overdue = tasks.filter((t) => {
      const td = d.data();
      const taskEnd = (td.tasks as Array<{ endDate?: string; status?: string }>)?.find((x) => x === t)?.endDate;
      return taskEnd && taskEnd < todayInParis() && t.status !== "done" && t.status !== "skipped";
    }).length;
    return `• ${data.title} : ${done}/${total} tâches, ${overdue} en retard, fin ${data.endDate ?? "non définie"}`;
  });

  // Domaines actifs (juste pour le contexte de QUI il est)
  const domainsSnap = await db.collection(`users/${uid}/domains`).get();
  const domains = domainsSnap.docs
    .filter((d) => !d.data().deleted)
    .map((d) => d.data().name as string)
    .join(", ");

  // Sessions des 3 derniers jours (où a-t-il mis son temps)
  const threeDaysAgo = new Date(Date.now() - 3 * 24 * 60 * 60 * 1000).toISOString().slice(0, 10);
  const sessionsSnap = await db.collection(`users/${uid}/sessions`)
    .where("date", ">=", threeDaysAgo)
    .get();

  const minByActivity: Record<string, number> = {};
  for (const doc of sessionsSnap.docs) {
    const v = doc.data();
    const name = (v.activityName as string) ?? "?";
    minByActivity[name] = (minByActivity[name] ?? 0) + ((v.durationMin as number) ?? 0);
  }
  const topActivities = Object.entries(minByActivity)
    .sort((a, b) => b[1] - a[1])
    .slice(0, 5)
    .map(([name, min]) => `${name}: ${min}min`)
    .join(", ");

  // Snapshot productivité du jour (écrit par l'app) → levier du jour.
  // hasLever uniquement si le snapshot est d'aujourd'hui ET qu'une dimension décroche.
  let leverBlock = "Aucun levier (journée équilibrée ou données indisponibles).";
  let hasLever = false;
  try {
    const snap = await db.doc(`users/${uid}/data/productivity_today`).get();
    const sd = snap.data();
    if (sd && sd.date === todayInParis() && sd.lever) {
      const lv = sd.lever as { label?: string; detail?: string };
      const dims =
        (sd.dimensions as Array<{ label?: string; detail?: string; score?: number }>) ?? [];
      const dimStr = dims
        .map((d) => `${d.label} ${Math.round((d.score ?? 0) * 100)}% (${d.detail})`)
        .join(" · ");
      leverBlock = `${dimStr}. Dimension en retard aujourd'hui : ${lv.label} (${lv.detail}).`;
      hasLever = true;
    }
  } catch (_) {
    /* pas de snapshot lisible → pas de levier */
  }

  const text = [
    `Domaines : ${domains || "aucun"}`,
    `Projets actifs (max 8) :`,
    projects.length ? projects.join("\n") : "  (aucun projet actif)",
    `Temps loggué 3 derniers jours : ${topActivities || "rien"}`,
  ].join("\n");

  return { text, leverBlock, hasLever };
}

export async function getOrCreateBrief(uid: string): Promise<Brief> {
  const date = todayInParis();
  const ref = db.collection(`users/${uid}/orion_briefs`).doc(date);

  // Sweep de la boîte à idées (gaté 1×/jour côté processInboxToProjects) —
  // AVANT l'early-return du brief en cache, sinon il ne tournerait jamais les
  // jours où le brief du jour existe déjà. Best-effort, ne casse jamais le brief.
  try {
    await processInboxToProjects(uid);
  } catch (e) {
    console.error("inbox sweep failed (non bloquant)", e);
  }
  // Direction C.3 : les projets qui dévient reçoivent une proposition de
  // restructuration « À valider » (gaté 1×/j côté module, best-effort).
  try {
    await evaluateProjectRestructures(uid);
  } catch (e) {
    console.error("restructure sweep failed (non bloquant)", e);
  }

  const existing = await ref.get();
  if (existing.exists) {
    const d = existing.data() as Record<string, unknown>;
    return {
      date,
      focus: (d.focus as string) ?? null,
      priorityAction: d.priorityAction as string,
      risk: (d.risk as string) ?? null,
      question: (d.question as string) ?? null,
      productivityLever: (d.productivityLever as string) ?? null,
      feedback: (d.feedback as "useful" | "skip") ?? null,
      feedbackAt: (d.feedbackAt as { toDate?: () => Date })?.toDate?.()?.toISOString() ?? null,
      createdAt: (d.createdAt as { toDate?: () => Date })?.toDate?.()?.toISOString() ?? new Date().toISOString(),
    };
  }

  // Génère le brief
  const focus = await getFocus(uid);
  if (!focus) {
    throw new Error("FOCUS_NOT_SET");
  }

  const context = await buildBriefContext(uid);
  const prompt = BRIEF_PROMPT
    .replace("{{FOCUS}}", focus)
    .replace("{{CONTEXT}}", context.text)
    .replace("{{LEVER}}", context.leverBlock)
    .replace("{{TODAY}}", date);

  const client = new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY });
  const message = await client.messages.create({
    model: MODELS.HAIKU,
    max_tokens: 512,
    messages: [{ role: "user", content: prompt }],
  });
  logTokenUsage("orion_brief", MODELS.HAIKU, message.usage);

  const rawText = (message.content[0] as { type: string; text: string }).text.trim();
  const jsonMatch = rawText.match(/\{[\s\S]*\}/);
  if (!jsonMatch) throw new Error("ORION_INVALID_RESPONSE");

  const parsed = JSON.parse(jsonMatch[0]) as {
    priorityAction: string;
    risk: string | null;
    question: string | null;
    productivityLever?: string | null;
  };

  const briefData = {
    date,
    focus,
    priorityAction: parsed.priorityAction ?? "",
    risk: parsed.risk ?? null,
    question: parsed.question ?? null,
    // Anti-hallucination : pas de levier dans le contexte → on force null.
    productivityLever: context.hasLever ? parsed.productivityLever ?? null : null,
    feedback: null,
    feedbackAt: null,
    createdAt: FieldValue.serverTimestamp(),
  };
  await ref.set(briefData);

  return {
    date,
    focus,
    priorityAction: briefData.priorityAction,
    risk: briefData.risk,
    question: briefData.question,
    productivityLever: briefData.productivityLever,
    feedback: null,
    feedbackAt: null,
    createdAt: new Date().toISOString(),
  };
}

export async function setBriefFeedback(
  uid: string,
  date: string,
  feedback: "useful" | "skip"
): Promise<void> {
  await db.collection(`users/${uid}/orion_briefs`).doc(date).update({
    feedback,
    feedbackAt: FieldValue.serverTimestamp(),
  });
}

export async function listBriefs(uid: string, limit = 30): Promise<Brief[]> {
  const snap = await db.collection(`users/${uid}/orion_briefs`)
    .orderBy("createdAt", "desc")
    .limit(limit)
    .get();
  return snap.docs.map((doc) => {
    const d = doc.data();
    return {
      date: doc.id,
      focus: (d.focus as string) ?? null,
      priorityAction: d.priorityAction as string,
      risk: (d.risk as string) ?? null,
      question: (d.question as string) ?? null,
      productivityLever: (d.productivityLever as string) ?? null,
      feedback: (d.feedback as "useful" | "skip") ?? null,
      feedbackAt: (d.feedbackAt as { toDate?: () => Date })?.toDate?.()?.toISOString() ?? null,
      createdAt: (d.createdAt as { toDate?: () => Date })?.toDate?.()?.toISOString() ?? "",
    };
  });
}
