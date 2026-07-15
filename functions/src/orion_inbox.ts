import Anthropic from "@anthropic-ai/sdk";
import { v4 as uuidv4 } from "uuid";
import { db, FieldValue } from "./db";
import { getModel, logTokenUsage } from "./models";
import {
  executeProposeChange,
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

type Idea = { id: string; text: string; date: string; ageDays: number };

/** Nombre de jours entre deux YYYY-MM-DD (b - a). */
function daysBetween(a: string, b: string): number {
  const da = new Date(`${a}T00:00:00Z`).getTime();
  const db = new Date(`${b}T00:00:00Z`).getTime();
  return Math.max(0, Math.round((db - da) / 86400000));
}

type RoutingTask = {
  title: string;
  actions?: string[]; // legacy — plus demandé au LLM (les actions sont définies par le user)
  durationDays?: number;
};

/// Contextes GTD par défaut — miroir de kDefaultGtdContexts (lib/models/projects.dart).
const DEFAULT_GTD_CONTEXTS = [
  "@maison", "@bureau", "@ordinateur", "@courses", "@extérieur", "@téléphone",
];

type RoutingDecision = {
  newProjects?: {
    title: string;
    description?: string;
    domainId?: string | null;
    objectiveId?: string | null; // objectif stratégique existant à rattacher
    ideaIds: string[];
    startOffsetDays?: number; // dans combien de jours démarrer (étalement de charge)
    tasks?: RoutingTask[];
    // Prochaine action GTD : LA première chose concrète à faire, avec son contexte.
    firstAction?: { title: string; context?: string | null };
  }[];
  appendTo?: {
    projectId: string;
    ideaIds: string[];
    tasks: RoutingTask[];
  }[];
  // ACTION ponctuelle (corvée, course, appel…) → défi 🔥 daté, posé DIRECTEMENT
  // dans le programme (un bloc se refuse d'un swipe — pas besoin de validation).
  schedule?: {
    ideaId: string;
    title: string;
    dayOffset?: number; // 0 = aujourd'hui (si l'heure est encore devant), 1..14
    startTime?: string; // "HH:mm" plausible
    durationMin?: number;
    activityId?: string | null; // routine/activité existante du même sujet
  }[];
  // ÉVÉNEMENT (rendez-vous à date/heure FIXE mentionnée dans l'idée) → bloc
  // d'agenda ordinaire, sans préfixe défi.
  events?: {
    ideaId: string;
    title: string;
    dayOffset?: number;
    startTime?: string;
    durationMin?: number;
  }[];
  skip?: string[];
  // Message léger optionnel sur UNE idée laissée — ne révèle jamais le traitement.
  nudge?: { text: string };
};

const ROUTING_PROMPT = `Tu es ORION, l'assistant de Productivitwo. Tu traites la boîte à idées de l'utilisateur selon la méthode GTD : chaque idée est classée PROJET, ACTION ponctuelle, ÉVÉNEMENT, ou laissée.

## CLASSIFICATION GTD (la règle la plus importante)
- **PROJET** ("newProjects") : un VRAI travail multi-étapes, stratégique, méritant un suivi sur plusieurs jours/semaines. Jamais pour une simple corvée.
- **ACTION ponctuelle** ("schedule") : réalisable en un coup (corvée, course, appel, petite réparation, message) → DÉFI daté dans les 14 prochains jours — jour et heure PLAUSIBLES (jamais avant {{WAKE}} ni après 21h, corvée extérieure en journée), durée réaliste (5-60 min), charge étalée (max 2 défis/jour). Si une routine/activité existante correspond au sujet, mets son activityId (chrono ciblé).
- **ÉVÉNEMENT** ("events") : l'idée mentionne un rendez-vous à date/heure FIXE (rdv médecin mardi 15h, réunion, anniversaire) → bloc d'agenda simple à cette date/heure, SANS le traiter comme un défi.
- **Laisser** ("skip") : note vague, non actionnable, ou qui demande une décision de l'utilisateur.
Dans le doute : skip. Mieux vaut laisser une idée que créer un projet bidon ou un défi absurde.

## Règles
1. Préfère TOUJOURS enrichir un projet ACTIF existant (appendTo) plutôt que créer, si l'idée s'y rattache sémantiquement.
2. AGRÈGE : si plusieurs idées concernent le même sujet, regroupe-les — soit dans UN seul newProject (plusieurs ideaIds), soit en plusieurs tâches d'un même projet.
3. Chaque idée apparaît EXACTEMENT une fois (dans newProjects, appendTo, schedule, events, OU skip).
4. Pour un nouveau projet :
   - titre court et clair, domainId le plus cohérent parmi les domaines (ou null) ;
   - si un OBJECTIF stratégique existant (voir liste) correspond au projet, mets son id dans \`objectiveId\` (sinon null) ;
   - 2-4 tâches de niveau PHASE (un verbe d'action, \`durationDays\` 1-15, enchaînées dans le temps) — SANS sous-actions : c'est l'utilisateur qui définira ses actions, pas toi ;
   - \`firstAction\` = LA PROCHAINE ACTION GTD : la première chose physique et concrète à faire pour démarrer (ex: "Appeler la mairie pour les horaires"), avec son \`context\` choisi dans la liste des contextes ci-dessous (où/avec quoi c'est réalisable).
5. PLANIFICATION RÉALISTE (important) : l'utilisateur a DÉJÀ des projets en cours avec des tâches planifiées (voir leurs dates). Ne surcharge PAS les prochains jours. Donne à chaque nouveau projet un \`startOffsetDays\` pour ÉTALER la charge. Un projet peu urgent peut démarrer dans 1-3 semaines.

## Message léger (nudge) — optionnel
Les propositions apparaissent EN SILENCE. MAIS si une idée est laissée (skip), tu peux proposer "nudge": { "text": "..." } = UN message court à la 1ère personne d'ORION qui évoque cette idée — SANS JAMAIS dire que tu as traité l'inbox. Un seul nudge max.
PRIORISE l'idée laissée qui traîne depuis le PLUS LONGTEMPS (\`ageDays\` le plus élevé), et adapte le ton à l'âge :
- récente (≤ 3j) : pas forcément de nudge (laisse infuser), ou rappel très léger ;
- une à deux semaines : rappel amical (ex: "Pense à boucler ta facture SOF 😉") ;
- ancienne (> 2-3 semaines) : invite à trancher (ex: "Ça fait {ageDays} jours que tu as noté « X » — tu veux t'y mettre ou je la classe sans suite ?").
Omets le nudge si rien ne le mérite.

## Idées en attente
{{IDEAS}}

## Projets actifs (pour rattacher)
{{PROJECTS}}

## Objectifs stratégiques actifs (pour objectiveId)
{{OBJECTIVES}}

## Contextes GTD disponibles (pour firstAction.context)
{{CONTEXTS}}

## Domaines
{{DOMAINS}}

## Routines & activités existantes (pour l'activityId des défis)
{{ACTIVITIES}}

Date du jour : {{TODAY}} — heure de lever de l'utilisateur : {{WAKE}}

Réponds UNIQUEMENT avec ce JSON (rien d'autre) :
{
  "newProjects": [ { "title": "...", "description": "...", "domainId": "<id|null>", "objectiveId": "<id|null>", "ideaIds": ["..."], "startOffsetDays": 0, "tasks": [ {"title":"...", "durationDays": 2} ], "firstAction": { "title": "...", "context": "@maison" } } ],
  "appendTo": [ { "projectId": "...", "ideaIds": ["..."], "tasks": [ {"title":"..."} ] } ],
  "schedule": [ { "ideaId": "...", "title": "...", "dayOffset": 1, "startTime": "10:00", "durationMin": 25, "activityId": null } ],
  "events": [ { "ideaId": "...", "title": "...", "dayOffset": 3, "startTime": "15:00", "durationMin": 60 } ],
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
): Promise<{ found: number; created: number; appended: number; scheduled: number; events: number; skipped: number } | null> {
  // Jour + heure VÉCUS (fait data/meta.tzOffsetMin posé par l'app) —
  // fallback Paris tant que le fait n'existe pas.
  const tzSnap = await db.doc(`users/${uid}/data/meta`).get();
  const tzOffsetMin = tzSnap.data()?.tzOffsetMin as number | undefined;
  const userParts = (d: Date = new Date()) => {
    if (typeof tzOffsetMin === "number" && isFinite(tzOffsetMin)) {
      const iso = new Date(d.getTime() + tzOffsetMin * 60_000).toISOString();
      return { ymd: iso.slice(0, 10), hm: iso.slice(11, 16) };
    }
    return {
      ymd: todayParis(d),
      hm: new Intl.DateTimeFormat("en-GB", {
        timeZone: "Europe/Paris", hour: "2-digit", minute: "2-digit", hour12: false,
      }).format(d),
    };
  };
  const today = userParts().ymd;
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
    return { found: 0, created: 0, appended: 0, scheduled: 0, events: 0, skipped: 0 };
  }

  const sortedDocs = inboxSnap.docs.slice().sort((a, b) => {
    const ta = (a.data().createdAt?.toMillis?.() as number) ?? 0;
    const tb = (b.data().createdAt?.toMillis?.() as number) ?? 0;
    return ta - tb;
  });

  const ideas: Idea[] = sortedDocs.map((d) => {
    const v = d.data();
    const date =
      (v.createdAt?.toDate?.() as Date | undefined)
        ?.toISOString?.()
        ?.slice(0, 10) ?? today;
    return {
      id: (v.id as string) ?? d.id,
      text: (v.text as string) ?? "",
      date,
      ageDays: daysBetween(date, today),
    };
  });

  const [projSnap, domSnap, actsSnap, metaSnap, objSnap] = await Promise.all([
    db.collection(`users/${uid}/projects`).where("status", "==", "active").get(),
    db.collection(`users/${uid}/domains`).get(),
    db.collection(`users/${uid}/activities`).get(),
    db.doc(`users/${uid}/data/meta`).get(),
    db.collection(`users/${uid}/strategic_objectives`).get(),
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
  const activities = actsSnap.docs
    .map((d) => d.data())
    .filter((v) => v.deleted !== true)
    .map((v) => ({ id: v.id as string, name: v.name as string, type: (v.type as string) ?? "time" }));
  const metaWake = metaSnap.data()?.wakeTime as string | undefined;
  const wake = typeof metaWake === "string" && /^\d{2}:\d{2}$/.test(metaWake) ? metaWake : "07:00";

  // Objectifs stratégiques actifs (rattachement des nouveaux projets).
  const objectives = objSnap.docs
    .map((d) => ({ ...d.data(), id: (d.data().id as string) ?? d.id }))
    .filter((v) => String((v as Record<string, unknown>).status ?? "active") === "active")
    .map((v) => {
      const o = v as Record<string, unknown>;
      return { id: o.id as string, title: o.title as string, kpiTarget: (o.kpiTarget as string) ?? null };
    });

  // Contextes GTD = défauts + personnalisés (data/meta.customContexts).
  const customContexts = ((metaSnap.data()?.customContexts as string[] | undefined) ?? [])
    .filter((c) => typeof c === "string" && c.trim().length > 0);
  const gtdContexts = [
    ...DEFAULT_GTD_CONTEXTS,
    ...customContexts.filter((c) => !DEFAULT_GTD_CONTEXTS.includes(c)),
  ];

  const prompt = ROUTING_PROMPT.replace("{{IDEAS}}", JSON.stringify(ideas, null, 2))
    .replace("{{PROJECTS}}", JSON.stringify(projects, null, 2))
    .replace("{{OBJECTIVES}}", JSON.stringify(objectives, null, 2))
    .replace("{{CONTEXTS}}", JSON.stringify(gtdContexts))
    .replace("{{DOMAINS}}", JSON.stringify(domains, null, 2))
    .replace("{{ACTIVITIES}}", JSON.stringify(activities, null, 2))
    .replace(/\{\{WAKE\}\}/g, wake)
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
    // NE PAS avancer lastSweepYmd en cas d'échec : le sweep doit pouvoir réessayer
    // le jour même. Sinon un seul plantage (ex: secret LLM indisponible) gèle le tri
    // de l'inbox pendant 24h. On consigne juste l'erreur pour diagnostic.
    await gateRef.set(
      { lastError: String(e), lastErrorAt: FieldValue.serverTimestamp() },
      { merge: true }
    );
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
    const ids = (np.ideaIds ?? []).filter((id) => ideaById.has(id));
    // Prochaine action GTD proposée : contexte validé contre la liste connue,
    // objectif validé contre les objectifs actifs.
    const firstActionTitle = np.firstAction?.title?.trim();
    const firstActionContext =
      np.firstAction?.context && gtdContexts.includes(np.firstAction.context)
        ? np.firstAction.context
        : null;
    const objectiveId =
      np.objectiveId && objectives.some((o) => o.id === np.objectiveId)
        ? np.objectiveId
        : undefined;
    // Au lieu de créer le projet en silence → on PROPOSE (file « À valider »).
    await executeProposeChange(uid, {
      kind: "new_project",
      title: `Créer le projet « ${np.title} »`,
      rationale: np.description ?? origin.map((o) => o.text).join(" · "),
      sourceCaptureId: ids[0],
      payload: {
        projectTitle: np.title,
        domainId: np.domainId ?? undefined,
        objectiveId,
        description: np.description,
        startDate: projectStart,
        endDate: lastEnd,
        phases,
        tasks, // appliqué par acceptProposal (phases + tâches niveau Gantt)
        ...(firstActionTitle
          ? { firstAction: { title: firstActionTitle, context: firstActionContext } }
          : {}),
      },
    });
    await Promise.all(
      ids.map((id) =>
        db.doc(`users/${uid}/captures/${id}`).set({ status: "proposed" }, { merge: true })
      )
    );
    created++;
  }

  for (const ap of decision.appendTo ?? []) {
    const proj = projects.find((p) => p.id === ap.projectId);
    if (!proj) continue;
    const ids = (ap.ideaIds ?? []).filter((id) => ideaById.has(id));
    for (const t of ap.tasks ?? []) {
      await executeProposeChange(uid, {
        kind: "attach_idea_as_task",
        title: `Ajouter « ${t.title} » à « ${proj.title} »`,
        rationale: ids.map((id) => ideaById.get(id)?.text).filter(Boolean).join(" · "),
        sourceCaptureId: ids[0],
        payload: {
          projectId: ap.projectId,
          taskTitle: t.title,
          description: (t.actions ?? []).slice(0, 6).join(" · "),
        },
      });
      appended++;
    }
    await Promise.all(
      ids.map((id) =>
        db.doc(`users/${uid}/captures/${id}`).set({ status: "proposed" }, { merge: true })
      )
    );
  }

  // Défis datés : posés DIRECTEMENT (un bloc se refuse d'un swipe, sans
  // pénalité) — l'idée est marquée traitée avec sa provenance. Garde-fous
  // déterministes : jamais avant le lever, heure passée → lendemain.
  const validActivityIds = new Set(activities.map((a) => a.id));
  let scheduled = 0;
  const nowHm = userParts().hm; // heure VÉCUE — « déjà passé » se juge là
  const toMin = (hm: string) =>
    parseInt(hm.slice(0, 2), 10) * 60 + parseInt(hm.slice(3, 5), 10);
  for (const sc of decision.schedule ?? []) {
    const idea = ideaById.get(sc.ideaId);
    if (!idea || !sc.title?.trim()) continue;
    let offset = Math.min(14, Math.max(0, Math.round(sc.dayOffset ?? 1)));
    let startTime =
      typeof sc.startTime === "string" && /^\d{2}:\d{2}$/.test(sc.startTime)
        ? sc.startTime
        : "09:00";
    if (toMin(startTime) < toMin(wake)) startTime = wake;
    // Aujourd'hui mais l'heure est déjà passée → demain.
    if (offset === 0 && toMin(startTime) <= toMin(nowHm) + 15) offset = 1;
    const ymd = addDays(today, offset);
    const block = {
      id: uuidv4(),
      startTime,
      durationMin: Math.min(60, Math.max(5, Math.round(sc.durationMin ?? 25))),
      title: `🔥 Défi : ${sc.title.trim()}`,
      category: "personal",
      projectId: null,
      taskId: null,
      activityId:
        sc.activityId && validActivityIds.has(sc.activityId) ? sc.activityId : null,
      actionId: null,
      status: "pending",
      doneAt: null,
      challenge: true,
    };
    const ref = db.doc(`users/${uid}/daily_schedules/${ymd}`);
    const snap = await ref.get();
    if (!snap.exists) {
      await ref.set({
        date: ymd,
        generatedBy: "orion",
        generatedAt: FieldValue.serverTimestamp(),
        blocks: [block],
      });
    } else {
      const blocks =
        ((snap.data() as Record<string, unknown>).blocks as Array<
          Record<string, unknown>
        >) ?? [];
      blocks.push(block);
      await ref.update({ blocks });
    }
    await db.doc(`users/${uid}/captures/${sc.ideaId}`).set(
      {
        status: "processed",
        orionNote: `Défi posé le ${ymd} à ${startTime} — « ${sc.title.trim()} »`,
        processedAt: new Date().toISOString(),
      },
      { merge: true }
    );
    scheduled++;
  }

  // Événements (rendez-vous à date/heure fixe) : bloc d'agenda simple, sans 🔥
  // ni challenge — miroir d'executeAddEvent (category personal, subtitle).
  let events = 0;
  for (const ev of decision.events ?? []) {
    const idea = ideaById.get(ev.ideaId);
    if (!idea || !ev.title?.trim()) continue;
    const offset = Math.min(60, Math.max(0, Math.round(ev.dayOffset ?? 1)));
    const startTime =
      typeof ev.startTime === "string" && /^\d{2}:\d{2}$/.test(ev.startTime)
        ? ev.startTime
        : "09:00";
    const ymd = addDays(today, offset);
    const block = {
      id: uuidv4(),
      startTime,
      durationMin: Math.min(480, Math.max(15, Math.round(ev.durationMin ?? 60))),
      title: ev.title.trim(),
      subtitle: "événement",
      category: "personal",
      projectId: null,
      taskId: null,
      activityId: null,
      actionId: null,
      status: "pending",
      doneAt: null,
    };
    const ref = db.doc(`users/${uid}/daily_schedules/${ymd}`);
    const snap = await ref.get();
    if (!snap.exists) {
      await ref.set({
        date: ymd,
        generatedBy: "orion",
        generatedAt: FieldValue.serverTimestamp(),
        blocks: [block],
      });
    } else {
      const blocks =
        ((snap.data() as Record<string, unknown>).blocks as Array<
          Record<string, unknown>
        >) ?? [];
      blocks.push(block);
      await ref.update({ blocks });
    }
    await db.doc(`users/${uid}/captures/${ev.ideaId}`).set(
      {
        status: "processed",
        orionNote: `Événement posé le ${ymd} à ${startTime} — « ${ev.title.trim()} »`,
        processedAt: new Date().toISOString(),
      },
      { merge: true }
    );
    events++;
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
      lastResult: { found: ideas.length, created, appended, scheduled, events, skipped },
      at: FieldValue.serverTimestamp(),
    },
    { merge: true }
  );

  return { found: ideas.length, created, appended, scheduled, events, skipped };
}
