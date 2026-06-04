import Anthropic from "@anthropic-ai/sdk";
import { v4 as uuidv4 } from "uuid";
import { db, FieldValue } from "./db";
import { getModel, logTokenUsage } from "./models";
import {
  executePushGantt,
  executeAddTask,
  executeProcessInboxItem,
} from "./execute";
import type { ProjectTask } from "./types";

function todayParis(d: Date = new Date()): string {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: "Europe/Paris",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(d);
}

type Idea = { id: string; text: string; date: string };

type RoutingDecision = {
  newProjects?: {
    title: string;
    description?: string;
    domainId?: string | null;
    ideaIds: string[];
    tasks?: { title: string }[];
  }[];
  appendTo?: {
    projectId: string;
    ideaIds: string[];
    tasks: { title: string }[];
  }[];
  skip?: string[];
};

const ROUTING_PROMPT = `Tu es ORION, l'assistant de Productivitwo. Tu traites la boîte à idées de l'utilisateur : transformer des idées en projets Gantt, les rattacher à des projets existants, ou les laisser.

## RÈGLE D'OR (granularité — la plus importante)
Ne crée un projet QUE pour une idée (ou un groupe d'idées) qui décrit un VRAI travail multi-étapes, stratégique, méritant un suivi sur plusieurs jours/semaines.
Une simple tâche isolée, une course, un achat, une note vague, un rappel ponctuel → NE PAS créer de projet → mets-la dans "skip".
Dans le doute : skip. Mieux vaut laisser une idée que créer un projet bidon.

## Règles
1. Préfère TOUJOURS enrichir un projet ACTIF existant (appendTo) plutôt que créer, si l'idée s'y rattache sémantiquement.
2. AGRÈGE : si plusieurs idées concernent le même sujet, regroupe-les — soit dans UN seul newProject (plusieurs ideaIds), soit en plusieurs tâches d'un même projet.
3. Chaque idée apparaît EXACTEMENT une fois (dans newProjects, appendTo, OU skip).
4. Pour un nouveau projet : titre court et clair, 2-4 tâches concrètes (verbe d'action), domainId le plus cohérent parmi les domaines (ou null).

## Idées en attente
{{IDEAS}}

## Projets actifs (pour rattacher)
{{PROJECTS}}

## Domaines
{{DOMAINS}}

Date du jour : {{TODAY}}

Réponds UNIQUEMENT avec ce JSON (rien d'autre) :
{
  "newProjects": [ { "title": "...", "description": "...", "domainId": "<id|null>", "ideaIds": ["..."], "tasks": [ {"title":"..."} ] } ],
  "appendTo": [ { "projectId": "...", "ideaIds": ["..."], "tasks": [ {"title":"..."} ] } ],
  "skip": ["ideaId", ...]
}`;

/**
 * Sweep autonome de l'inbox → projets. Gaté 1×/jour (déclenché en lazy à
 * l'ouverture de l'app via getOrCreateBrief). Routage/agrégation par un appel
 * Sonnet, application déterministe. Les projets créés portent source:"orion" +
 * la provenance des idées (originIdeas) pour le style distinct + l'effet « wow ».
 */
export async function processInboxToProjects(
  uid: string,
  opts?: { force?: boolean }
): Promise<{ created: number; appended: number; skipped: number } | null> {
  const today = todayParis();
  const gateRef = db.doc(`users/${uid}/data/inbox_sweep`);

  const gate = await gateRef.get();
  if (!opts?.force && gate.exists && (gate.data()?.lastSweepYmd as string) === today) {
    return null; // déjà passé aujourd'hui
  }

  const inboxSnap = await db
    .collection(`users/${uid}/captures`)
    .where("status", "==", "pending")
    .orderBy("createdAt", "asc")
    .get();

  if (inboxSnap.empty) {
    await gateRef.set({ lastSweepYmd: today }, { merge: true });
    return { created: 0, appended: 0, skipped: 0 };
  }

  const ideas: Idea[] = inboxSnap.docs.map((d) => {
    const v = d.data();
    return {
      id: (v.id as string) ?? d.id,
      text: (v.text as string) ?? "",
      date:
        (v.createdAt?.toDate?.() as Date | undefined)
          ?.toISOString?.()
          ?.slice(0, 10) ?? today,
    };
  });

  const [projSnap, domSnap] = await Promise.all([
    db.collection(`users/${uid}/projects`).where("status", "==", "active").get(),
    db.collection(`users/${uid}/domains`).get(),
  ]);
  const projects = projSnap.docs.map((d) => {
    const v = d.data();
    return {
      id: v.id as string,
      title: v.title as string,
      description: (v.description as string) ?? "",
      domainId: (v.domainId as string) ?? null,
    };
  });
  const domains = domSnap.docs
    .map((d) => d.data())
    .filter((v) => !v.deleted)
    .map((v) => ({ id: v.id as string, name: v.name as string }));

  const prompt = ROUTING_PROMPT.replace("{{IDEAS}}", JSON.stringify(ideas, null, 2))
    .replace("{{PROJECTS}}", JSON.stringify(projects, null, 2))
    .replace("{{DOMAINS}}", JSON.stringify(domains, null, 2))
    .replace("{{TODAY}}", today);

  let decision: RoutingDecision;
  try {
    const client = new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY });
    const msg = await client.messages.create({
      model: getModel("inbox_routing"),
      max_tokens: 1500,
      messages: [{ role: "user", content: prompt }],
    });
    logTokenUsage("inbox_routing", getModel("inbox_routing"), msg.usage);
    const raw = (msg.content[0] as { type: string; text: string }).text.trim();
    const m = raw.match(/\{[\s\S]*\}/);
    if (!m) throw new Error("no json");
    decision = JSON.parse(m[0]) as RoutingDecision;
  } catch (e) {
    console.error("inbox routing failed", e);
    await gateRef.set({ lastSweepYmd: today, error: String(e) }, { merge: true });
    return null;
  }

  const ideaById = new Map(ideas.map((i) => [i.id, i]));
  let created = 0;
  let appended = 0;

  for (const np of decision.newProjects ?? []) {
    const origin = (np.ideaIds ?? [])
      .map((id) => ideaById.get(id))
      .filter((i): i is Idea => !!i)
      .map((i) => ({ text: i.text, date: i.date }));
    if (origin.length === 0) continue;

    const tasks: ProjectTask[] = (np.tasks?.length ? np.tasks : [{ title: np.title }]).map(
      (t, i) => ({ id: `task-${i + 1}`, title: t.title, startDate: today })
    );
    await executePushGantt(
      uid,
      {
        uid,
        project: {
          title: np.title,
          description: np.description,
          domainId: np.domainId ?? undefined,
          startDate: today,
          tasks,
        },
      },
      { source: "orion", originIdeas: origin }
    );
    for (const id of np.ideaIds ?? []) {
      if (ideaById.has(id)) {
        await executeProcessInboxItem(uid, id, `→ projet ORION « ${np.title} »`);
      }
    }
    created++;
  }

  for (const ap of decision.appendTo ?? []) {
    const proj = projects.find((p) => p.id === ap.projectId);
    if (!proj) continue;
    for (const t of ap.tasks ?? []) {
      await executeAddTask(uid, ap.projectId, {
        id: uuidv4(),
        title: t.title,
        startDate: today,
      } as ProjectTask);
      appended++;
    }
    const origin = (ap.ideaIds ?? [])
      .map((id) => ideaById.get(id))
      .filter((i): i is Idea => !!i)
      .map((i) => ({ text: i.text, date: i.date }));
    if (origin.length) {
      await db
        .doc(`users/${uid}/projects/${ap.projectId}`)
        .set({ originIdeas: FieldValue.arrayUnion(...origin) }, { merge: true });
    }
    for (const id of ap.ideaIds ?? []) {
      if (ideaById.has(id)) {
        await executeProcessInboxItem(uid, id, `→ ajoutée au projet « ${proj.title} »`);
      }
    }
  }

  const skipped = (decision.skip ?? []).filter((id) => ideaById.has(id)).length;

  await gateRef.set(
    {
      lastSweepYmd: today,
      lastResult: { created, appended, skipped },
      at: FieldValue.serverTimestamp(),
    },
    { merge: true }
  );

  return { created, appended, skipped };
}
