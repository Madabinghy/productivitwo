import Anthropic from "@anthropic-ai/sdk";
import { db, FieldValue } from "./db";
import { getModel, logTokenUsage } from "./models";
import { executeProposeChange } from "./execute";

// ─── DIRECTION C.3 : LE GANTT SUIT LA DIRECTION (réévaluation en coulisse) ────
//
// Quand un projet DÉVIE (tâches sautées en boucle, stagnation), ORION propose
// une restructuration — jamais appliquée d'office : une proposition « À
// valider » (kind restructure_project) avec le diff lisible. Refus = silence
// 30 jours sur ce projet. AUCUNE version obsolète visible : le Gantt ne bouge
// pas tant que l'utilisateur n'a pas validé.
//
// Déclencheurs DÉTERMINISTES (0 LLM pour décider) :
//   1. Dérive : ≥ 3 blocs du projet sautés/reportés sur 14 jours ;
//   3. Stagnation : projet actif > 21 j, 0 action cochée en 21 j, ≥ 1 tâche
//      pending en retard.
// (Le déclencheur « direction changée » attend un fait directionChangedAt
//  fiable — updatedAt bouge à chaque coche de tâche, trop de faux positifs.)
//
// Garde-fous : projet touché < 48 h → skip (l'utilisateur est dessus) ;
// 1 proposition pending max par projet ; refus < 30 j → silence ;
// max 2 propositions par passage ; gate 1×/jour (data/restructure_sweep).

type Json = Record<string, any>;

const if_ = (cond: boolean, s: string): string | null => (cond ? s : null);

type RestructureDecision = {
  archiveTaskIds?: string[];
  reword?: { taskId: string; title: string }[];
  addTasks?: { title: string; actions?: string[]; durationDays?: number }[];
  rationale?: string;
};

const RESTRUCTURE_PROMPT = `Tu es ORION, l'assistant de Productivitwo. Un projet Gantt a dévié : propose une RESTRUCTURATION minimale pour que le plan colle à la réalité.

## Règles
1. N'archive une tâche QUE si elle est devenue hors-sujet ou irréaliste au vu des faits — jamais une tâche presque finie.
2. Reformule quand l'intention reste bonne mais le libellé est périmé.
3. Ajoute AU PLUS 3 tâches, uniquement si un chaînon manque vraiment (verbe d'action + 2-4 sous-actions concrètes + durationDays 1-15).
4. Les tâches "done" sont INTOUCHABLES — ne les mentionne pas.
5. Si le projet est simplement en retard mais toujours pertinent tel quel, réponds avec tous les tableaux vides et un rationale court — on ne dérange pas l'utilisateur pour rien.
6. rationale : 1-2 phrases FACTUELLES (cite les faits fournis, jamais de chiffres inventés).

## Projet
{{PROJECT}}

## Faits mesurés
{{FACTS}}

Réponds UNIQUEMENT avec ce JSON (rien d'autre) :
{
  "archiveTaskIds": ["..."],
  "reword": [ { "taskId": "...", "title": "..." } ],
  "addTasks": [ { "title": "...", "actions": ["...", "..."], "durationDays": 3 } ],
  "rationale": "..."
}`;

function todayYmdFor(tzOffsetMin: number | undefined, d: Date = new Date()): string {
  if (typeof tzOffsetMin === "number" && isFinite(tzOffsetMin)) {
    return new Date(d.getTime() + tzOffsetMin * 60_000).toISOString().slice(0, 10);
  }
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: "Europe/Paris", year: "numeric", month: "2-digit", day: "2-digit",
  }).format(d);
}

function addDays(ymd: string, n: number): string {
  const d = new Date(`${ymd}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + n);
  return d.toISOString().slice(0, 10);
}

export async function evaluateProjectRestructures(
  uid: string,
  opts?: { force?: boolean }
): Promise<{ checked: number; proposed: number } | null> {
  const metaSnap = await db.doc(`users/${uid}/data/meta`).get();
  const today = todayYmdFor(metaSnap.data()?.tzOffsetMin as number | undefined);
  const gateRef = db.doc(`users/${uid}/data/restructure_sweep`);
  const gate = await gateRef.get();
  if (!opts?.force && gate.exists && gate.data()?.lastYmd === today) return null;

  const [projSnap, propSnap] = await Promise.all([
    db.collection(`users/${uid}/projects`).where("status", "==", "active").get(),
    db.collection(`users/${uid}/orion_proposals`)
      .where("kind", "==", "restructure_project").get(),
  ]);

  // Silences : proposition pending existante, ou refus < 30 jours.
  const pendingIds = new Set<string>();
  const refusedIds = new Set<string>();
  const cutoff30 = Date.now() - 30 * 86400000;
  for (const d of propSnap.docs) {
    const v = d.data();
    const pid = (v.payload as Json | undefined)?.projectId as string | undefined;
    if (!pid) continue;
    if (v.status === "pending") pendingIds.add(pid);
    if (v.status === "rejected") {
      const at = (v.createdAt as { toMillis?: () => number } | undefined)?.toMillis?.() ?? 0;
      if (at > cutoff30) refusedIds.add(pid);
    }
  }

  // Blocs sautés/reportés des 14 derniers jours, comptés par projet.
  const skipped14: Record<string, number> = {};
  const dayReads = await Promise.all(
    Array.from({ length: 14 }, (_, i) =>
      db.doc(`users/${uid}/daily_schedules/${addDays(today, -i)}`).get()
    )
  );
  for (const snap of dayReads) {
    for (const b of ((snap.data()?.blocks as Json[]) ?? [])) {
      if (b.projectId && b.status === "skipped") {
        skipped14[b.projectId as string] = (skipped14[b.projectId as string] ?? 0) + 1;
      }
    }
  }

  const now = Date.now();
  const cutoff48h = now - 48 * 3600000;
  const cutoff21d = now - 21 * 86400000;
  let proposed = 0;
  let checked = 0;

  for (const doc of projSnap.docs) {
    if (proposed >= 2) break; // jamais une avalanche de propositions
    const p = doc.data() as Json;
    const pid = p.id as string;
    checked++;
    if (pendingIds.has(pid) || refusedIds.has(pid)) continue;
    // Touché récemment → l'utilisateur est déjà dessus, on ne s'en mêle pas.
    const updatedAt = (p.updatedAt as { toMillis?: () => number } | undefined)?.toMillis?.();
    if (updatedAt != null && updatedAt > cutoff48h) continue;

    const tasks = ((p.tasks as Json[]) ?? []);
    const pending = tasks.filter((t) => t.status !== "done" && t.status !== "skipped");
    if (pending.length === 0) continue;

    // Déclencheur 1 — dérive : ≥ 3 blocs du projet sautés sur 14 jours.
    const drift = (skipped14[pid] ?? 0) >= 3;

    // Déclencheur 3 — stagnation : > 21 j, 0 action cochée en 21 j, retard.
    let lastDoneAt = 0;
    for (const t of tasks) {
      for (const a of ((t.actions as Json[]) ?? [])) {
        const at = Date.parse(String(a.doneAt ?? ""));
        if (isFinite(at) && at > lastDoneAt) lastDoneAt = at;
      }
    }
    const createdParsed = Date.parse(String(p.createdAt ?? ""));
    const createdAtMs =
      (p.createdAt as { toMillis?: () => number } | undefined)?.toMillis?.() ??
      (isFinite(createdParsed) ? createdParsed : now);
    const hasLate = pending.some(
      (t) => String(t.endDate ?? "") !== "" && String(t.endDate) < today
    );
    const stagnant =
      createdAtMs < cutoff21d && lastDoneAt < cutoff21d && hasLate;

    if (!drift && !stagnant) continue;

    const facts = [
      if_(drift, `${skipped14[pid]} bloc(s) de ce projet sautés/reportés sur les 14 derniers jours`),
      if_(stagnant, `aucune action cochée depuis plus de 21 jours`),
      if_(hasLate, `${pending.filter((t) => String(t.endDate ?? "") !== "" && String(t.endDate) < today).length} tâche(s) pending en retard sur leur date de fin`),
    ].filter((s): s is string => s !== null);

    const projectJson = {
      title: p.title,
      description: p.description ?? "",
      tasks: tasks.map((t) => ({
        id: t.id,
        title: t.title,
        status: t.status ?? "pending",
        startDate: t.startDate ?? null,
        endDate: t.endDate ?? null,
        actionsDone: ((t.actions as Json[]) ?? []).filter((a) => a.done === true).length,
        actionsPending: ((t.actions as Json[]) ?? []).filter((a) => a.done !== true).length,
      })),
    };

    let decision: RestructureDecision;
    try {
      const client = new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY });
      const msg = await client.messages.create({
        model: getModel("restructure_project"),
        max_tokens: 1500,
        messages: [{
          role: "user",
          content: RESTRUCTURE_PROMPT
            .replace("{{PROJECT}}", JSON.stringify(projectJson, null, 2))
            .replace("{{FACTS}}", facts.map((f) => `- ${f}`).join("\n")),
        }],
      });
      logTokenUsage("restructure_project", getModel("restructure_project"), msg.usage);
      const raw = (msg.content[0] as { type: string; text: string }).text.trim();
      const m = raw.match(/\{[\s\S]*\}/);
      if (!m) continue;
      decision = JSON.parse(m[0]) as RestructureDecision;
    } catch (e) {
      console.error("restructure LLM failed", e);
      continue;
    }

    // Validation déterministe du diff : ids réels, jamais une tâche done.
    const byId = new Map(tasks.map((t) => [t.id as string, t]));
    const archive = (decision.archiveTaskIds ?? []).filter(
      (id) => byId.has(id) && byId.get(id)!.status !== "done"
    );
    const reword = (decision.reword ?? []).filter(
      (r) => byId.has(r.taskId) && byId.get(r.taskId)!.status !== "done" &&
        (r.title ?? "").trim() !== ""
    );
    const addTasks = (decision.addTasks ?? [])
      .filter((t) => (t.title ?? "").trim() !== "")
      .slice(0, 3)
      .map((t) => ({
        title: t.title.trim(),
        actions: (t.actions ?? []).slice(0, 6),
        durationDays: Math.min(15, Math.max(1, Math.round(t.durationDays ?? 3))),
      }));
    if (archive.length + reword.length + addTasks.length === 0) continue;

    const parts = [
      archive.length > 0 ? `archiver ${archive.length} tâche(s)` : null,
      reword.length > 0 ? `reformuler ${reword.length}` : null,
      addTasks.length > 0 ? `ajouter ${addTasks.length}` : null,
    ].filter((s): s is string => s !== null);

    await executeProposeChange(uid, {
      kind: "restructure_project",
      title: `Recaler « ${p.title} » : ${parts.join(" · ")}`,
      rationale: `${facts.join(" · ")}. ${decision.rationale ?? ""}`.trim(),
      payload: {
        projectId: pid,
        archiveTaskIds: archive,
        reword,
        addTasks,
      },
    });
    proposed++;
  }

  await gateRef.set(
    { lastYmd: today, lastResult: { checked, proposed }, at: FieldValue.serverTimestamp() },
    { merge: true }
  );
  return { checked, proposed };
}
