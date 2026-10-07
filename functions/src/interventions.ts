// Intervention = objet natif (brief « Projets opérationnel » 2026-10, § 2.2) :
// une séance datée (cours, journée client) + créneau + lieu + déroulé + bilan,
// portée par le projet (`project.interventions[]`). Ses trois tâches
// (📝 Préparer · 🎯 Séance · ✅ Clôturer) restent des ProjectTask ordinaires,
// taguées `interventionId` + `interventionRole` — Gantt, Actions, programme,
// mobile et outils MCP continuent de les voir sans rien changer.
// Logique pure (testée) ; l'accès Firestore vit dans execute.ts.

import { v4 as uuidv4 } from "uuid";

type AnyRec = Record<string, unknown>;

export type Role = "prep" | "session" | "closure";

export interface TemplateAction {
  title: string;
  contexts?: string[];
  estimatedMin?: number | null;
}

export interface InterventionTemplate {
  id: string;
  name: string;
  startTime?: string;
  endTime?: string;
  place?: string;
  /** Contexte de l'action « Dérouler la séance » (ex. @Chérubins). */
  sessionContext?: string;
  prep: { daysBefore: number; endDaysBefore: number; actions: TemplateAction[] };
  closure: { daysAfter: number; actions: TemplateAction[] };
}

export interface InterventionInput {
  id?: string;
  title: string;
  date: string; // YYYY-MM-DD
  startTime: string; // HH:mm
  endTime: string; // HH:mm
  place?: string;
  templateId?: string;
  docUrl?: string;
  /** Déroulé : étapes de l'action « Dérouler la séance ». */
  steps?: string[];
  prepActions?: TemplateAction[];
  closureActions?: TemplateAction[];
}

export const DEFAULT_TEMPLATE: InterventionTemplate = {
  id: "default",
  name: "Séance (défaut)",
  prep: {
    daysBefore: 7,
    endDaysBefore: 1,
    actions: [
      { title: "Adapter au bilan précédent", contexts: ["@ordinateur"], estimatedMin: 15 },
      { title: "Produire les supports", contexts: ["@ordinateur"], estimatedMin: 45 },
      { title: "Fiche de séquence", contexts: ["@ordinateur"], estimatedMin: 15 },
      { title: "Imprimer", contexts: ["@impression"], estimatedMin: 10 },
    ],
  },
  closure: {
    daysAfter: 2,
    actions: [
      { title: "Remplir la fiche de séquence (réalisé + bilan)", contexts: ["@ordinateur"], estimatedMin: 15 },
      { title: "Noter le report (ce qui n'a pas été fait)", contexts: ["@ordinateur"], estimatedMin: 5 },
      { title: "Déposer les documents", contexts: ["@ordinateur"], estimatedMin: 10 },
    ],
  },
};

export const CARRY_OVER_ACTION = /adapter au bilan/i;

const DAYS = ["Dim", "Lun", "Mar", "Mer", "Jeu", "Ven", "Sam"];
const MONTHS = ["janv.", "févr.", "mars", "avr.", "mai", "juin", "juil.", "août", "sept.", "oct.", "nov.", "déc."];

export const toMin = (hm: string): number => {
  const m = /^(\d{1,2}):(\d{2})$/.exec(hm);
  return m ? Number(m[1]) * 60 + Number(m[2]) : NaN;
};
export const hmFr = (hm: string): string => {
  const m = /^(\d{1,2}):(\d{2})$/.exec(hm);
  return m ? `${Number(m[1])}h${m[2]}` : hm;
};

export function addDays(ymd: string, n: number): string {
  const d = new Date(`${ymd}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + n);
  return d.toISOString().slice(0, 10);
}

export function dayLabelFr(ymd: string): string {
  const d = new Date(`${ymd}T00:00:00Z`);
  return `${DAYS[d.getUTCDay()]} ${d.getUTCDate()} ${MONTHS[d.getUTCMonth()]}`;
}

export function slotMin(startTime: string, endTime: string): number {
  const a = toMin(startTime), b = toMin(endTime);
  return Number.isFinite(a) && Number.isFinite(b) && b > a ? b - a : 0;
}

export function validateInput(i: InterventionInput): string | null {
  if (!i.title?.trim()) return "title requis";
  if (!/^\d{4}-\d{2}-\d{2}$/.test(i.date)) return `date invalide : ${i.date} (YYYY-MM-DD)`;
  if (!Number.isFinite(toMin(i.startTime))) return `startTime invalide : ${i.startTime} (HH:mm)`;
  if (!Number.isFinite(toMin(i.endTime))) return `endTime invalide : ${i.endTime} (HH:mm)`;
  if (slotMin(i.startTime, i.endTime) <= 0) return "endTime doit être après startTime";
  return null;
}

/** Phase dont la plage contient la date ; la plus courte si plusieurs. */
export function phaseForDate(phases: AnyRec[], ymd: string): string | undefined {
  const hits = phases
    .filter((p) => String(p.startDate ?? "").slice(0, 10) <= ymd && ymd <= String(p.endDate ?? "").slice(0, 10))
    .sort((a, b) =>
      (String(a.endDate).localeCompare(String(a.startDate))) - (String(b.endDate).localeCompare(String(b.startDate))));
  return hits[0] ? String(hits[0].id) : undefined;
}

const nowIso = () => new Date().toISOString();

function action(a: TemplateAction): AnyRec {
  const ctx = (a.contexts ?? []).filter((c) => typeof c === "string" && c.trim());
  return {
    id: uuidv4(),
    title: a.title,
    done: false,
    doneAt: null,
    createdAt: nowIso(),
    ...(ctx.length ? { contexts: ctx, context: ctx[0] } : {}),
    ...(typeof a.estimatedMin === "number" ? { estimatedMin: a.estimatedMin } : {}),
    checklist: [],
  };
}

const sumMin = (as: TemplateAction[]) => as.reduce((n, a) => n + (typeof a.estimatedMin === "number" ? a.estimatedMin : 0), 0);

/** Le document `interventions[]` stocké dans le projet. */
export function buildIntervention(i: InterventionInput): AnyRec {
  return {
    id: i.id ?? uuidv4(),
    title: i.title.trim(),
    date: i.date,
    startTime: i.startTime,
    endTime: i.endTime,
    place: i.place ?? null,
    templateId: i.templateId ?? null,
    docUrl: i.docUrl ?? null,
    status: "planned",
    debriefText: null,
    carryOver: [],
    debriefAt: null,
    createdAt: nowIso(),
  };
}

/** Les trois tâches d'une intervention, prêtes à être ajoutées au projet. */
export function buildInterventionTasks(
  intervention: AnyRec,
  tpl: InterventionTemplate,
  opts: { phases?: AnyRec[]; steps?: string[]; prepActions?: TemplateAction[]; closureActions?: TemplateAction[] } = {}
): { prep: AnyRec; session: AnyRec; closure: AnyRec } {
  const id = String(intervention.id);
  const title = String(intervention.title);
  const date = String(intervention.date);
  const start = String(intervention.startTime), end = String(intervention.endTime);
  const phaseId = phaseForDate(opts.phases ?? [], date);
  const base = {
    groupLabel: title,
    ...(phaseId ? { phaseId } : {}),
    interventionId: id,
    color: null,
    barLabel: null,
    todayFlag: false,
  };
  const prepActions = opts.prepActions ?? tpl.prep.actions;
  const closureActions = opts.closureActions ?? tpl.closure.actions;
  const steps = (opts.steps ?? []).filter((s) => s.trim());
  const sessionCtx = tpl.sessionContext ? [tpl.sessionContext] : [];
  return {
    prep: {
      ...base,
      id: uuidv4(),
      title: `📝 Préparer — ${title}`,
      startDate: addDays(date, -Math.max(1, tpl.prep.daysBefore)),
      endDate: addDays(date, -Math.max(0, tpl.prep.endDaysBefore)),
      isMilestone: false,
      status: "pending",
      interventionRole: "prep",
      actions: prepActions.map(action),
      estimatedMin: sumMin(prepActions) || null,
    },
    session: {
      ...base,
      id: uuidv4(),
      title: `🎯 ${dayLabelFr(date)} — ${title}`,
      startDate: date,
      endDate: date,
      isMilestone: true,
      barLabel: "SÉANCE",
      status: "pending",
      interventionRole: "session",
      actions: [{
        ...action({ title: `Dérouler la séance (${hmFr(start)}–${hmFr(end)})`, contexts: sessionCtx, estimatedMin: slotMin(start, end) }),
        checklist: steps.map((s) => ({ id: uuidv4(), title: s, done: false, doneAt: null })),
      }],
      estimatedMin: null,
    },
    closure: {
      ...base,
      id: uuidv4(),
      title: `✅ Clôturer — ${title}`,
      startDate: date,
      endDate: addDays(date, Math.max(0, tpl.closure.daysAfter)),
      isMilestone: false,
      status: "pending",
      interventionRole: "closure",
      actions: closureActions.map(action),
      estimatedMin: sumMin(closureActions) || null,
    },
  };
}

/** Déplace les tâches d'une intervention quand sa date change (même écart). */
export function shiftTasks(tasks: AnyRec[], interventionId: string, fromDate: string, toDate: string): AnyRec[] {
  const delta = Math.round((Date.parse(`${toDate}T00:00:00Z`) - Date.parse(`${fromDate}T00:00:00Z`)) / 86400000);
  if (!delta) return tasks;
  const shift = (v: unknown) => (typeof v === "string" && v ? addDays(v.slice(0, 10), delta) : v);
  return tasks.map((t) => t.interventionId === interventionId
    ? { ...t, startDate: shift(t.startDate), endDate: shift(t.endDate) }
    : t);
}

/** Retitre le jalon quand la date ou le titre change. */
export function retitleTasks(tasks: AnyRec[], intervention: AnyRec): AnyRec[] {
  const id = String(intervention.id), title = String(intervention.title), date = String(intervention.date);
  return tasks.map((t) => {
    if (t.interventionId !== id) return t;
    const out: AnyRec = { ...t, groupLabel: title };
    if (t.interventionRole === "prep") out.title = `📝 Préparer — ${title}`;
    if (t.interventionRole === "session") out.title = `🎯 ${dayLabelFr(date)} — ${title}`;
    if (t.interventionRole === "closure") out.title = `✅ Clôturer — ${title}`;
    return out;
  });
}

/**
 * Bilan N → prépa N+1 : les points « à reprendre » deviennent la checklist de
 * l'action « Adapter au bilan précédent » de la prochaine intervention (créée
 * si absente). Les items déjà présents (même titre) sont conservés.
 * Retourne les tâches mises à jour et l'id de l'intervention alimentée.
 */
export function applyCarryOver(
  tasks: AnyRec[],
  interventions: AnyRec[],
  fromId: string,
  carryOver: string[]
): { tasks: AnyRec[]; nextId: string | null } {
  const from = interventions.find((i) => i.id === fromId);
  const items = carryOver.map((s) => s.trim()).filter(Boolean);
  if (!from || !items.length) return { tasks, nextId: null };
  const next = interventions
    .filter((i) => i.id !== fromId && i.status !== "cancelled" && String(i.date) > String(from.date))
    .sort((a, b) => String(a.date).localeCompare(String(b.date)))[0];
  if (!next) return { tasks, nextId: null };
  const idx = tasks.findIndex((t) => t.interventionId === next.id && t.interventionRole === "prep");
  if (idx < 0) return { tasks, nextId: null };
  const prep = { ...tasks[idx] };
  const actions = ((prep.actions as AnyRec[]) ?? []).slice();
  let ai = actions.findIndex((a) => CARRY_OVER_ACTION.test(String(a.title)));
  if (ai < 0) {
    actions.unshift(action({ title: "Adapter au bilan précédent", contexts: ["@ordinateur"], estimatedMin: 15 }));
    ai = 0;
  }
  const a = { ...actions[ai] };
  const list = (Array.isArray(a.checklist) ? (a.checklist as AnyRec[]) : []).slice();
  const have = new Set(list.map((c) => String(c.title).trim().toLowerCase()));
  for (const s of items) {
    if (!have.has(s.toLowerCase())) list.push({ id: uuidv4(), title: s, done: false, doneAt: null });
  }
  a.checklist = list;
  if (a.done === true && list.some((c) => c.done !== true)) { a.done = false; a.doneAt = null; }
  actions[ai] = a;
  prep.actions = actions;
  const out = tasks.slice();
  out[idx] = prep;
  return { tasks: out, nextId: String(next.id) };
}

// ── Migration des triplets existants (convention émojis + groupLabel) ────────

const lead = (t: AnyRec, re: RegExp) => re.test(String(t.title ?? "").trimStart());
export const isSessionTask = (t: AnyRec) => t.isMilestone === true || lead(t, /^(🎯|🏁)/);
export const isPrepTask = (t: AnyRec) => lead(t, /^📝/);
export const isClosureTask = (t: AnyRec) => lead(t, /^✅/);

const TIME_RE = /(\d{1,2})\s?h\s?(\d{0,2})\s*(?:–|-|—|à)\s*(\d{1,2})\s?h\s?(\d{0,2})/;

/** « 13h15–15h00 » → { "13:15", "15:00" } depuis un texte libre. */
export function parseTimeRange(text: string): { startTime: string; endTime: string } | null {
  const m = TIME_RE.exec(text);
  if (!m) return null;
  const pad = (h: string, mm: string) => `${h.padStart(2, "0")}:${(mm || "00").padStart(2, "0")}`;
  return { startTime: pad(m[1], m[2]), endTime: pad(m[3], m[4]) };
}

export interface DetectedTriplet {
  groupLabel: string;
  session: AnyRec;
  prep?: AnyRec;
  closure?: AnyRec;
  date: string;
  startTime: string;
  endTime: string;
  timeSource: "task" | "description" | "default";
}

/** Repère les interventions implicites : un jalon (non annulé, non déjà tagué)
 *  + sa 📝 et sa ✅ de même groupLabel. Le créneau vient de l'action du jalon,
 *  sinon de la description du projet, sinon du défaut donné. */
export function detectTriplets(
  tasks: AnyRec[],
  opts: { description?: string; defaultStart?: string; defaultEnd?: string } = {}
): DetectedTriplet[] {
  const out: DetectedTriplet[] = [];
  for (const m of tasks) {
    if (m.status === "skipped" || m.interventionId || !isSessionTask(m)) continue;
    const g = String(m.groupLabel ?? "").trim();
    const siblings = g ? tasks.filter((t) => t !== m && !t.interventionId && String(t.groupLabel ?? "").trim() === g) : [];
    const fromTask = parseTimeRange([...((m.actions as AnyRec[]) ?? []).map((a) => String(a.title ?? "")), String(m.title ?? "")].join(" "));
    const fromDesc = fromTask ? null : parseTimeRange(opts.description ?? "");
    const slot = fromTask ?? fromDesc ?? { startTime: opts.defaultStart ?? "09:00", endTime: opts.defaultEnd ?? "12:00" };
    out.push({
      groupLabel: g || String(m.title).replace(/^(🎯|🏁)\s*/, ""),
      session: m,
      prep: siblings.find((t) => t.status !== "skipped" && isPrepTask(t)),
      closure: siblings.find((t) => t.status !== "skipped" && isClosureTask(t)),
      date: String(m.endDate ?? m.startDate).slice(0, 10),
      startTime: slot.startTime,
      endTime: slot.endTime,
      timeSource: fromTask ? "task" : fromDesc ? "description" : "default",
    });
  }
  return out.sort((a, b) => a.date.localeCompare(b.date));
}

/** Applique une détection : crée l'intervention et tague les trois tâches. */
export function applyTriplet(tasks: AnyRec[], t: DetectedTriplet): { tasks: AnyRec[]; intervention: AnyRec } {
  const intervention = buildIntervention({
    title: t.groupLabel, date: t.date, startTime: t.startTime, endTime: t.endTime,
  });
  const tag = (task: AnyRec | undefined, role: Role) =>
    task ? { ...task, interventionId: intervention.id, interventionRole: role } : undefined;
  const map = new Map<unknown, AnyRec>();
  for (const [task, role] of [[t.session, "session"], [t.prep, "prep"], [t.closure, "closure"]] as const) {
    const tagged = tag(task, role);
    if (task && tagged) map.set(task.id, tagged);
  }
  const done = t.session.status === "done" ||
    (((t.session.actions as AnyRec[]) ?? []).length > 0 && ((t.session.actions as AnyRec[]) ?? []).every((a) => a.done === true));
  if (done) intervention.status = "done";
  return { tasks: tasks.map((x) => map.get(x.id) ?? x), intervention };
}
