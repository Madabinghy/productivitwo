/** Estimé vs réel — logique pure, testée.
 *  Le temps réel d'une action = somme des sessions de chrono CIBLÉES sur elle
 *  (`Session.actionId`) ; d'une tâche = sessions portant son `taskId`. Les
 *  blocs du programme ne comptent pas (temps prévu, pas mesuré). Une session
 *  encore ouverte ou de plus de 12 h (chrono oublié) est ignorée. */
import { contextsOf } from "./contexts";

type Rec = Record<string, unknown>;

export const MAX_SESSION_MIN = 12 * 60;

function toMs(v: unknown): number | null {
  if (typeof v === "string") {
    const t = Date.parse(v);
    return Number.isNaN(t) ? null : t;
  }
  if (v && typeof v === "object" && typeof (v as { toDate?: unknown }).toDate === "function") {
    return ((v as { toDate: () => Date }).toDate()).getTime();
  }
  return null;
}

/** Minutes d'une session fermée ; 0 si ouverte, invalide ou > 12 h. */
export function sessionMinutes(s: Rec): number {
  const a = toMs(s.startAt), b = toMs(s.endAt);
  if (a === null || b === null || b <= a) return 0;
  const min = Math.round((b - a) / 60000);
  return min > MAX_SESSION_MIN ? 0 : min;
}

export function spentMaps(sessions: Rec[]): { byAction: Map<string, number>; byTask: Map<string, number> } {
  const byAction = new Map<string, number>();
  const byTask = new Map<string, number>();
  for (const s of sessions) {
    const m = sessionMinutes(s);
    if (m <= 0) continue;
    if (typeof s.actionId === "string" && s.actionId) {
      byAction.set(s.actionId, (byAction.get(s.actionId) ?? 0) + m);
    }
    if (typeof s.taskId === "string" && s.taskId) {
      byTask.set(s.taskId, (byTask.get(s.taskId) ?? 0) + m);
    }
  }
  return { byAction, byTask };
}

export type Ref =
  | { kind: "project"; projectId: string; taskId: string; actionId: string }
  | { kind: "activity"; activityId: string; actionId: string }
  | { kind: "task"; projectId: string; taskId: string };

export type TimeEntry = {
  ref: Ref;
  title: string;
  holder: string;
  contexts: string[];
  estimatedMin: number | null;
  spentMin: number;
  done: boolean;
  doneAt: string | null;
};

function estimate(v: unknown): number | null {
  return typeof v === "number" && Number.isFinite(v) && v > 0 ? Math.round(v) : null;
}

const arr = (v: unknown) => (Array.isArray(v) ? v : []) as Rec[];

/** Toutes les actions (projets + activités) et tâches, avec estimé et réel. */
export function timeEntries(projects: Rec[], activities: Rec[], sessions: Rec[]): TimeEntry[] {
  const { byAction, byTask } = spentMaps(sessions);
  const out: TimeEntry[] = [];
  for (const p of projects) {
    if (p.status === "deleted") continue;
    const pid = String(p.id ?? "");
    for (const t of arr(p.tasks)) {
      const tid = String(t.id ?? "");
      if (t.isMilestone === true) continue;
      for (const a of arr(t.actions)) {
        const aid = String(a.id ?? "");
        out.push({
          ref: { kind: "project", projectId: pid, taskId: tid, actionId: aid },
          title: String(a.title ?? ""),
          holder: `${p.title ?? pid} › ${t.title ?? tid}`,
          contexts: contextsOf(a),
          estimatedMin: estimate(a.estimatedMin),
          spentMin: byAction.get(aid) ?? 0,
          done: a.done === true,
          doneAt: typeof a.doneAt === "string" ? a.doneAt : null,
        });
      }
      out.push({
        ref: { kind: "task", projectId: pid, taskId: tid },
        title: String(t.title ?? ""),
        holder: String(p.title ?? pid),
        contexts: [],
        estimatedMin: estimate(t.estimatedMin),
        spentMin: byTask.get(tid) ?? 0,
        done: t.status === "done",
        doneAt: typeof t.doneAt === "string" ? t.doneAt : null,
      });
    }
  }
  for (const act of activities) {
    if (act.deleted === true) continue;
    const actId = String(act.id ?? "");
    for (const a of arr(act.ownActions)) {
      const aid = String(a.id ?? "");
      out.push({
        ref: { kind: "activity", activityId: actId, actionId: aid },
        title: String(a.title ?? ""),
        holder: `activité ${act.name ?? actId}`,
        contexts: contextsOf(a),
        estimatedMin: estimate(a.estimatedMin),
        spentMin: byAction.get(aid) ?? 0,
        done: a.done === true,
        doneAt: typeof a.doneAt === "string" ? a.doneAt : null,
      });
    }
  }
  return out;
}

export function median(xs: number[]): number | null {
  if (xs.length === 0) return null;
  const s = [...xs].sort((a, b) => a - b);
  const m = Math.floor(s.length / 2);
  return s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2;
}

/** Facteur réel / estimé arrondi au 0,05, borné [0,25 ; 4]. */
export function roundFactor(r: number): number {
  const c = Math.min(4, Math.max(0.25, r));
  return Math.round(c * 20) / 20;
}

export type Calibration = {
  n: number;
  factor: number | null;      // médiane réel/estimé
  accurate: number;           // |ratio − 1| ≤ 25 %
  under: number;              // réel > 1,25 × estimé (sous-estimées)
  over: number;               // réel < 0,8 × estimé (surestimées)
  byContext: Array<{ context: string; n: number; factor: number }>;
  byHolder: Array<{ holder: string; n: number; factor: number }>;
};

/** Mesurées = terminées, estimées et chronométrées (actions seulement). */
export function measured(entries: TimeEntry[], sinceMs: number | null = null): TimeEntry[] {
  return entries.filter((e) =>
    e.ref.kind !== "task" && e.done && e.estimatedMin !== null && e.spentMin > 0 &&
    (sinceMs === null || e.doneAt === null || (Date.parse(e.doneAt) || 0) >= sinceMs));
}

export function calibrate(measuredEntries: TimeEntry[], minGroup = 3): Calibration {
  const ratios = measuredEntries.map((e) => e.spentMin / (e.estimatedMin as number));
  const f = median(ratios);
  const group = (keyOf: (e: TimeEntry) => string[]) => {
    const g = new Map<string, number[]>();
    for (const e of measuredEntries) {
      for (const k of keyOf(e)) {
        const l = g.get(k) ?? [];
        l.push(e.spentMin / (e.estimatedMin as number));
        g.set(k, l);
      }
    }
    return [...g.entries()]
      .filter(([, l]) => l.length >= minGroup)
      .map(([k, l]) => ({ key: k, n: l.length, factor: roundFactor(median(l) as number) }))
      .sort((a, b) => b.n - a.n);
  };
  return {
    n: ratios.length,
    factor: f === null ? null : roundFactor(f),
    accurate: ratios.filter((r) => Math.abs(r - 1) <= 0.25).length,
    under: ratios.filter((r) => r > 1.25).length,
    over: ratios.filter((r) => r < 0.8).length,
    byContext: group((e) => e.contexts).map((x) => ({ context: x.key, n: x.n, factor: x.factor })),
    byHolder: group((e) => [e.holder]).map((x) => ({ holder: x.key, n: x.n, factor: x.factor })),
  };
}

/** Ouvertes, estimées, et déjà au-delà de l'estimation. */
export function overBudget(entries: TimeEntry[]): TimeEntry[] {
  return entries
    .filter((e) => e.ref.kind !== "task" && !e.done && e.estimatedMin !== null && e.spentMin > e.estimatedMin)
    .sort((a, b) => b.spentMin / (b.estimatedMin as number) - a.spentMin / (a.estimatedMin as number));
}

/** Ouvertes, déjà travaillées, sans estimation : à estimer en priorité. */
export function workedUnestimated(entries: TimeEntry[]): TimeEntry[] {
  return entries
    .filter((e) => e.ref.kind !== "task" && !e.done && e.estimatedMin === null && e.spentMin > 0)
    .sort((a, b) => b.spentMin - a.spentMin);
}

// ── Rendu texte ──────────────────────────────────────────────────────────────

export function fmtMin(m: number): string {
  if (m < 60) return `${m} min`;
  const h = Math.floor(m / 60), r = m % 60;
  return r === 0 ? `${h} h` : `${h} h ${String(r).padStart(2, "0")}`;
}

export function fmtFactor(f: number): string {
  return `×${f.toFixed(2).replace(/0$/, "").replace(".", ",")}`;
}

export function refLabel(r: Ref): string {
  switch (r.kind) {
    case "project": return `projectId=${r.projectId} taskId=${r.taskId} actionId=${r.actionId}`;
    case "activity": return `activityId=${r.activityId} actionId=${r.actionId}`;
    case "task": return `projectId=${r.projectId} taskId=${r.taskId}`;
  }
}

export function adviceLine(c: Calibration): string {
  if (c.factor === null) return "Pas encore de mesure : estime au jugé et lance le chrono ciblé sur l'action pour mesurer.";
  if (c.n < 3) return `Seulement ${c.n} mesure(s) : facteur ${fmtFactor(c.factor)} indicatif, pas encore fiable.`;
  if (c.factor >= 1.15) return `Tu sous-estimes : multiplie ta première intuition par ~${fmtFactor(c.factor).slice(1)}.`;
  if (c.factor <= 0.85) return `Tu surestimes : réduis ta première intuition (facteur ~${fmtFactor(c.factor).slice(1)}).`;
  return `Tes estimations sont justes (facteur ${fmtFactor(c.factor)}) : garde-les telles quelles.`;
}

export function calibrationHeadline(c: Calibration): string {
  if (c.n === 0) return "Aucune action terminée, estimée et chronométrée sur la période.";
  return `${c.n} action(s) mesurée(s) · réel/estimé médian ${fmtFactor(c.factor as number)} · ` +
    `${c.accurate} juste(s) à ±25 % · ${c.under} sous-estimée(s) · ${c.over} surestimée(s)`;
}
