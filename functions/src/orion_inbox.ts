import Anthropic from "@anthropic-ai/sdk";
import { v4 as uuidv4 } from "uuid";
import { db, FieldValue } from "./db";
import { getModel, logTokenUsage } from "./models";
import {
  executePushGantt,
  executeAddTask,
  executeProcessInboxItem,
  executePushAssistantMessage,
} from "./execute";
import type { ProjectTask, ProjectPhase } from "./types";

function todayParis(d: Date = new Date()): string {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: "Europe/Paris",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(d);
}

/** Ajoute n jours à un YYYY-MM-DD et renvoie un YYYY-MM-DD. */
function addDays(ymd: string, n: number): string {
  const d = new Date(`${ymd}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + n);
  return d.toISOString().slice(0, 10);
}

type Idea = { id: string; text: string; date: string };

type RoutingTask = {
  title: string;
  actions?: string[];
  durationDays?: number;
};

type RoutingDecision = {
  newProjects?: {
    title: string;
    description?: string;
    domainId?: string | null;
    ideaIds: string[];
    startOffsetDays?: number; // dans combien de jours démarrer (étalement de charge)
    tasks?: RoutingTask[];
  }[];
  appendTo?: {
    projectId: string;
    ideaIds: string[];
    tasks: RoutingTask[];
  }[];
  skip?: string[];
  // Message léger optionnel sur UNE idée laissée — ne révèle jamais le traitement.
  nudge?: { text: string };
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
4. Pour un nouveau projet : titre court et clair, domainId le plus cohérent parmi les domaines (ou null), et 2-4 tâches qui forment un VRAI Gantt :
   - chaque tâche = un verbe d'action + 2-4 **sous-actions** concrètes (\`actions\`) qui détaillent comment la faire,
   - chaque tâche a une **durée réaliste** en jours (\`durationDays\`, 1 à 15) — les tâches seront ENCHAÎNÉES dans le temps (l'une après l'autre), donne donc un ordre logique d'exécution.
5. PLANIFICATION RÉALISTE (important) : l'utilisateur a DÉJÀ des projets en cours avec des tâches planifiées (voir leurs dates). Ne surcharge PAS les prochains jours. Donne à chaque nouveau projet un \`startOffsetDays\` (dans combien de jours il démarre) pour ÉTALER la charge : tiens compte des tâches existantes ET des autres nouveaux projets (ne les fais pas tous démarrer en même temps). Un projet peu urgent peut démarrer dans 1-3 semaines.

## Message léger (nudge) — optionnel
Les projets créés apparaissent EN SILENCE (effet de surprise). MAIS si une idée est laissée (skip) et mérite un petit rappel, tu peux proposer "nudge": { "text": "..." } = UN message court à la 1ère personne d'ORION qui évoque cette idée — SANS JAMAIS dire que tu as traité l'inbox ni mentionner les projets créés. Ex: "Pense à boucler ta dernière facture SOF 😉" ou "Tu avais noté l'idée X — tu veux en faire quoi ?". Un seul nudge max, et seulement si pertinent (sinon omets-le).

## Idées en attente
{{IDEAS}}

## Projets actifs (pour rattacher)
{{PROJECTS}}

## Domaines
{{DOMAINS}}

Date du jour : {{TODAY}}

Réponds UNIQUEMENT avec ce JSON (rien d'autre) :
{
  "newProjects": [ { "title": "...", "description": "...", "domainId": "<id|null>", "ideaIds": ["..."], "startOffsetDays": 0, "tasks": [ {"title":"...", "actions":["...","..."], "durationDays": 2} ] } ],
  "appendTo": [ { "projectId": "...", "ideaIds": ["..."], "tasks": [ {"title":"...", "actions":["..."]} ] } ],
  "skip": ["ideaId", ...],
  "nudge": { "text": "..." }
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
): Promise<{ found: number; created: number; appended: number; skipped: number } | null> {
  const today = todayParis();
  const gateRef = db.doc(`users/${uid}/data/inbox_sweep`);

  const gate = await gateRef.get();
  if (!opts?.force && gate.exists && (gate.data()?.lastSweepYmd as string) === today) {
    return null; // déjà passé aujourd'hui
  }

  // Pas d'orderBy ici → évite un index composite (status+createdAt). On trie en
  // mémoire (l'inbox est petite).
  const inboxSnap = await db
    .collection(`users/${uid}/captures`)
    .where("status", "==", "pending")
    .get();

  if (inboxSnap.empty) {
    await gateRef.set({ lastSweepYmd: today }, { merge: true });
    return { found: 0, created: 0, appended: 0, skipped: 0 };
  }

  const sortedDocs = inboxSnap.docs.slice().sort((a, b) => {
    const ta = (a.data().createdAt?.toMillis?.() as number) ?? 0;
    const tb = (b.data().createdAt?.toMillis?.() as number) ?? 0;
    return ta - tb;
  });

  const ideas: Idea[] = sortedDocs.map((d) => {
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
    // Tâches déjà planifiées (non terminées) avec dates → permet à Sonnet de
    // placer les nouveaux projets SANS surcharger les jours déjà occupés.
    const activeTasks = ((v.tasks as Array<Record<string, unknown>>) ?? [])
      .filter((t) => t.status !== "done" && t.status !== "skipped")
      .map((t) => ({
        title: t.title as string,
        startDate: (t.startDate as string) ?? null,
        endDate: (t.endDate as string) ?? null,
      }));
    return {
      id: v.id as string,
      title: v.title as string,
      description: (v.description as string) ?? "",
      domainId: (v.domainId as string) ?? null,
      activeTasks,
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
      max_tokens: 3000,
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

    // Tâches ENCHAÎNÉES dans le temps (staircase Gantt) + sous-actions.
    // Démarrage décalé (startOffsetDays) pour étaler la charge vs les en-cours.
    const offset = Math.min(120, Math.max(0, Math.round(np.startOffsetDays ?? 0)));
    const projectStart = addDays(today, offset);
    const rawTasks: RoutingTask[] = np.tasks?.length ? np.tasks : [{ title: np.title }];
    let cursor = projectStart;
    const tasks: ProjectTask[] = rawTasks.map((t, i) => {
      const dur = Math.min(15, Math.max(1, Math.round(t.durationDays ?? 2)));
      const startDate = cursor;
      const endDate = addDays(startDate, dur);
      cursor = addDays(endDate, 1); // la tâche suivante démarre après celle-ci
      return {
        id: `task-${i + 1}`,
        title: t.title,
        phaseId: "phase-1",
        startDate,
        endDate,
        actions: (t.actions ?? []).slice(0, 6),
      };
    });
    const lastEnd = tasks.length ? tasks[tasks.length - 1].endDate ?? projectStart : projectStart;
    const phases: ProjectPhase[] = [
      { id: "phase-1", label: "Réalisation", startDate: projectStart, endDate: lastEnd },
    ];
    await executePushGantt(
      uid,
      {
        uid,
        project: {
          title: np.title,
          description: np.description,
          domainId: np.domainId ?? undefined,
          startDate: projectStart,
          endDate: lastEnd,
          phases,
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
        actions: (t.actions ?? []).slice(0, 6),
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

  // Silence sur les projets créés (effet « wow »). Seul message éventuel : un
  // nudge léger sur une idée laissée, sans révéler le traitement de l'inbox.
  const nudgeText = decision.nudge?.text?.trim();
  if (nudgeText) {
    try {
      await executePushAssistantMessage(uid, {
        targetDate: today,
        text: nudgeText,
        condition: { type: "always" },
        characterName: "ORION",
        expiresAfterDays: 3,
      });
    } catch (e) {
      console.error("nudge push failed (non bloquant)", e);
    }
  }

  await gateRef.set(
    {
      lastSweepYmd: today,
      lastResult: { found: ideas.length, created, appended, skipped },
      at: FieldValue.serverTimestamp(),
    },
    { merge: true }
  );

  return { found: ideas.length, created, appended, skipped };
}
