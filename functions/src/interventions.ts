// Intervention = objet natif (brief « Projets opérationnel » 2026-10, § 2.2) :
// une séance datée (cours, journée client) + créneau + lieu + déroulé + bilan,
// portée par le projet (`project.interventions[]`). Ses trois tâches
// (📝 Préparer · 🎯 Séance · ✅ Clôturer) restent des ProjectTask ordinaires,
// taguées `interventionId` + `interventionRole` — Gantt, Actions, programme,
// mobile et outils MCP continuent de les voir sans rien changer.
// Logique pure (testée) ; l'accès Firestore vit dans execute.ts.

import { v4 as uuidv4 } from "uuid";

type AnyRec = Record<string, unknown>;

export type Role = "prep" | "session" | "closure" | "extra";
/** Rôles PRINCIPAUX (un seul par intervention) ; `extra` = tâche secondaire
 *  rattachée (évaluation 🏁 le jour de la séance, tâche fusionnée en conflit…). */
export const PRIMARY_ROLES: Role[] = ["prep", "session", "closure"];
export const ROLES: Role[] = [...PRIMARY_ROLES, "extra"];

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

const padHm = (h: string, mm: string) => `${h.padStart(2, "0")}:${(mm || "00").padStart(2, "0")}`;

/** Toutes les plages « 8h30–12h30 + 13h30–16h30 » d'un texte, dans l'ordre. */
export function parseTimeRanges(text: string): Array<{ startTime: string; endTime: string }> {
  const out: Array<{ startTime: string; endTime: string }> = [];
  const re = new RegExp(TIME_RE.source, "g");
  let m: RegExpExecArray | null;
  while ((m = re.exec(text)) !== null) {
    out.push({ startTime: padHm(m[1], m[2]), endTime: padHm(m[3], m[4]) });
  }
  return out;
}

export interface Slot { startTime: string; endTime: string; breaks: Array<{ start: string; end: string }> }

/** Créneau global d'une liste de plages : début de la première, fin de la
 *  dernière, pauses entre deux plages (ex. midi). Null sans plage. */
export function slotFromRanges(ranges: Array<{ startTime: string; endTime: string }>): Slot | null {
  if (!ranges.length) return null;
  const sorted = [...ranges].sort((a, b) => toMin(a.startTime) - toMin(b.startTime));
  const breaks: Array<{ start: string; end: string }> = [];
  for (let i = 1; i < sorted.length; i++) {
    if (toMin(sorted[i].startTime) > toMin(sorted[i - 1].endTime)) {
      breaks.push({ start: sorted[i - 1].endTime, end: sorted[i].startTime });
    }
  }
  return { startTime: sorted[0].startTime, endTime: sorted[sorted.length - 1].endTime, breaks };
}

/** « 13h15–15h00 » → { "13:15", "15:00" } (première plage) depuis un texte libre. */
export function parseTimeRange(text: string): { startTime: string; endTime: string } | null {
  return parseTimeRanges(text)[0] ?? null;
}

/** Durée nette (minutes) hors pauses. */
export function netSlotMin(slot: { startTime: string; endTime: string; breaks?: Array<{ start: string; end: string }> }): number {
  const total = slotMin(slot.startTime, slot.endTime);
  const pauses = (slot.breaks ?? []).reduce((n, b) => n + Math.max(0, toMin(b.end) - toMin(b.start)), 0);
  return Math.max(0, total - pauses);
}

export interface DetectedTriplet {
  groupLabel: string;
  session: AnyRec;
  prep?: AnyRec;
  closure?: AnyRec;
  /** Tâches secondaires rattachées (🏁 du même jour). */
  extras: AnyRec[];
  date: string;
  startTime: string;
  endTime: string;
  breaks: Array<{ start: string; end: string }>;
  timeSource: "task" | "description" | "default";
  /** Jalon sans 📝 ni ✅ (migré seulement avec includeOrphans). */
  orphan: boolean;
}

export interface DetectionWarning { kind: "unpaired_prep" | "unpaired_closure" | "same_day"; text: string }

const MONTHS_FR: Record<string, number> = {
  janv: 1, jan: 1, janvier: 1, fev: 2, fevr: 2, fevrier: 2, mars: 3, mar: 3, avr: 4, avril: 4, mai: 5, juin: 6,
  juil: 7, juillet: 7, aout: 8, sept: 9, sep: 9, septembre: 9, oct: 10, octobre: 10, nov: 11, novembre: 11,
  dec: 12, decembre: 12,
};

/** Repères d'un titre : « J3 » → j3 ; « 23/11 », « 15 oct » → d-m. */
export function titleHints(title: string): Set<string> {
  const t = String(title ?? "").toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "");
  const out = new Set<string>();
  for (const m of t.matchAll(/\bj\s?(\d{1,2})\b/g)) out.add(`j${Number(m[1])}`);
  for (const m of t.matchAll(/\b(\d{1,2})\s*\/\s*(\d{1,2})\b/g)) out.add(`${Number(m[1])}-${Number(m[2])}`);
  for (const m of t.matchAll(/\b(\d{1,2})(?:er)?\s+([a-z]{3,9})\.?\b/g)) {
    const mo = MONTHS_FR[m[2]];
    if (mo) out.add(`${Number(m[1])}-${mo}`);
  }
  return out;
}

/** Repères d'un jalon : ceux de son titre + sa date. */
function sessionHints(m: AnyRec, date: string): Set<string> {
  const h = titleHints(String(m.title ?? ""));
  const [, mo, d] = date.split("-").map(Number);
  h.add(`${d}-${mo}`);
  return h;
}

const sharesHint = (a: Set<string>, b: Set<string>) => [...a].some((k) => b.has(k));
const ymd = (v: unknown) => String(v ?? "").slice(0, 10);

/**
 * Repère les interventions implicites. Par `groupLabel` : chaque jalon 🎯 est
 * apparié à la 📝 et à la ✅ qui l'encadrent dans le temps (📝 : endDate la
 * plus proche avant ; ✅ : startDate la plus proche à partir du jalon), un
 * repère de titre commun (« J3 », « 15 oct ») primant sur la proximité ;
 * chaque tâche ne sert qu'une fois. Un 🏁 le jour d'un 🎯 du même groupe
 * devient une tâche secondaire (`extra`) ; un 🏁 seul n'est pas une séance.
 * Un jalon sans 📝 ni ✅ est un orphelin (ignoré sauf includeOrphans).
 */
export function detectTriplets(
  tasks: AnyRec[],
  opts: { description?: string; defaultStart?: string; defaultEnd?: string; includeOrphans?: boolean } = {}
): { triplets: DetectedTriplet[]; warnings: DetectionWarning[] } {
  const live = tasks.filter((t) => t.status !== "skipped" && !t.interventionId);
  const groups = new Map<string, AnyRec[]>();
  for (const t of live) {
    const g = String(t.groupLabel ?? "").trim() || `__${t.id}`;
    groups.set(g, [...(groups.get(g) ?? []), t]);
  }
  const triplets: DetectedTriplet[] = [];
  const warnings: DetectionWarning[] = [];
  const isFlag = (t: AnyRec) => lead(t, /^🏁/);
  const isTarget = (t: AnyRec) => isSessionTask(t) && !isFlag(t);

  for (const [g, members] of groups) {
    const sessions = members.filter(isTarget).sort((a, b) => ymd(a.endDate ?? a.startDate).localeCompare(ymd(b.endDate ?? b.startDate)));
    const flags = members.filter(isFlag);
    const preps = members.filter(isPrepTask);
    const closures = members.filter(isClosureTask);
    const usedPrep = new Set<unknown>(), usedClosure = new Set<unknown>();
    const label = g.startsWith("__") ? "" : g;

    const picks = sessions.map((m) => ({ m, date: ymd(m.endDate ?? m.startDate), hints: sessionHints(m, ymd(m.endDate ?? m.startDate)), prep: undefined as AnyRec | undefined, closure: undefined as AnyRec | undefined }));
    // Passe 1 : repères de titre.
    for (const p of picks) {
      p.prep = preps.find((t) => !usedPrep.has(t.id) && sharesHint(titleHints(String(t.title)), p.hints));
      if (p.prep) usedPrep.add(p.prep.id);
      p.closure = closures.find((t) => !usedClosure.has(t.id) && sharesHint(titleHints(String(t.title)), p.hints));
      if (p.closure) usedClosure.add(p.closure.id);
    }
    // Passe 2 : proximité temporelle (📝 avant, ✅ à partir du jalon).
    for (const p of picks) {
      if (!p.prep) {
        const c = preps
          .filter((t) => !usedPrep.has(t.id) && ymd(t.endDate ?? t.startDate) <= p.date)
          .sort((a, b) => ymd(b.endDate ?? b.startDate).localeCompare(ymd(a.endDate ?? a.startDate)))[0];
        if (c) { p.prep = c; usedPrep.add(c.id); }
      }
      if (!p.closure) {
        const c = closures
          .filter((t) => !usedClosure.has(t.id) && ymd(t.startDate) >= p.date)
          .sort((a, b) => ymd(a.startDate).localeCompare(ymd(b.startDate)))[0];
        if (c) { p.closure = c; usedClosure.add(c.id); }
      }
    }
    for (const p of picks) {
      const orphan = !p.prep && !p.closure;
      if (orphan && !opts.includeOrphans) continue;
      const extras = flags.filter((f) => ymd(f.endDate ?? f.startDate) === p.date);
      const text = [...((p.m.actions as AnyRec[]) ?? []).map((a) => String(a.title ?? "")), String(p.m.title ?? "")].join(" ");
      const fromTask = slotFromRanges(parseTimeRanges(text));
      const fromDesc = fromTask ? null : slotFromRanges(parseTimeRanges(opts.description ?? ""));
      const slot = fromTask ?? fromDesc ?? { startTime: opts.defaultStart ?? "09:00", endTime: opts.defaultEnd ?? "12:00", breaks: [] };
      triplets.push({
        groupLabel: label || String(p.m.title).replace(/^(🎯|🏁)\s*/, ""),
        session: p.m, prep: p.prep, closure: p.closure, extras,
        date: p.date, startTime: slot.startTime, endTime: slot.endTime, breaks: slot.breaks,
        timeSource: fromTask ? "task" : fromDesc ? "description" : "default",
        orphan,
      });
    }
    for (const t of preps) if (!usedPrep.has(t.id)) warnings.push({ kind: "unpaired_prep", text: `📝 sans jalon apparié : « ${t.title} » (${ymd(t.startDate)} → ${ymd(t.endDate ?? t.startDate)}, groupe « ${label || "—"} »)` });
    for (const t of closures) if (!usedClosure.has(t.id)) warnings.push({ kind: "unpaired_closure", text: `✅ sans jalon apparié : « ${t.title} » (${ymd(t.startDate)}, groupe « ${label || "—"} »)` });
  }
  triplets.sort((a, b) => a.date.localeCompare(b.date));
  const byDay = new Map<string, number>();
  for (const t of triplets) byDay.set(t.date, (byDay.get(t.date) ?? 0) + 1);
  for (const [d, n] of byDay) if (n > 1) warnings.push({ kind: "same_day", text: `${n} interventions le ${d} dans ce projet — vérifie (update_intervention mergeFrom pour fusionner)` });
  return { triplets, warnings };
}

/** Applique une détection : crée l'intervention et tague ses tâches. */
export function applyTriplet(tasks: AnyRec[], t: DetectedTriplet): { tasks: AnyRec[]; intervention: AnyRec } {
  const intervention = buildIntervention({
    title: t.groupLabel, date: t.date, startTime: t.startTime, endTime: t.endTime,
  });
  if (t.breaks.length) intervention.breaks = t.breaks;
  const tag = (task: AnyRec | undefined, role: Role) =>
    task ? { ...task, interventionId: intervention.id, interventionRole: role } : undefined;
  const map = new Map<unknown, AnyRec>();
  const pairs: Array<[AnyRec | undefined, Role]> = [[t.session, "session"], [t.prep, "prep"], [t.closure, "closure"], ...t.extras.map((e): [AnyRec, Role] => [e, "extra"])];
  for (const [task, role] of pairs) {
    const tagged = tag(task, role);
    if (task && tagged) map.set(task.id, tagged);
  }
  const done = t.session.status === "done" ||
    (((t.session.actions as AnyRec[]) ?? []).length > 0 && ((t.session.actions as AnyRec[]) ?? []).every((a) => a.done === true));
  if (done) intervention.status = "done";
  return { tasks: tasks.map((x) => map.get(x.id) ?? x), intervention };
}

// ── Rattachement manuel, suppression, fusion ─────────────────────────────────

/**
 * Rattache une tâche à une intervention (ou la détache : interventionId "").
 * Un rôle principal n'est porté que par une tâche : conflit = erreur nommant
 * la tâche en place. Ne touche ni statut, ni dates, ni actions.
 */
export function attachTask(
  tasks: AnyRec[],
  interventions: AnyRec[],
  taskId: string,
  interventionId: string,
  role?: string
): { tasks: AnyRec[]; note: string } {
  const idx = tasks.findIndex((t) => t.id === taskId);
  if (idx < 0) throw new Error(`Tâche introuvable : ${taskId}`);
  if (!interventionId) {
    const out = tasks.slice();
    const { interventionId: _i, interventionRole: _r, ...rest } = out[idx];
    out[idx] = rest;
    return { tasks: out, note: "détachée de son intervention" };
  }
  const target = interventions.find((i) => i.id === interventionId);
  if (!target) throw new Error(`Intervention introuvable dans ce projet : ${interventionId}`);
  if (!role || !ROLES.includes(role as Role)) {
    throw new Error(`interventionRole requis : ${ROLES.join(" | ")}`);
  }
  if (PRIMARY_ROLES.includes(role as Role)) {
    const holder = tasks.find((t) => t.id !== taskId && t.interventionId === interventionId && t.interventionRole === role);
    if (holder) {
      throw new Error(`Le rôle ${role} de « ${target.title} » est déjà tenu par « ${holder.title} » (${holder.id}) — détache-la d'abord ou utilise le rôle extra.`);
    }
  }
  const out = tasks.slice();
  out[idx] = { ...out[idx], interventionId, interventionRole: role };
  return { tasks: out, note: `rattachée à « ${target.title} » (${role})` };
}

/** Détache toutes les tâches d'une intervention (statut, dates, actions intacts). */
export function detachAll(tasks: AnyRec[], interventionId: string): { tasks: AnyRec[]; touched: AnyRec[] } {
  const touched: AnyRec[] = [];
  const out = tasks.map((t) => {
    if (t.interventionId !== interventionId) return t;
    touched.push(t);
    const { interventionId: _i, interventionRole: _r, ...rest } = t;
    return rest;
  });
  return { tasks: out, touched };
}

/**
 * Fusion : les tâches de `from` passent sur `target` ; un rôle principal déjà
 * tenu → la tâche entrante devient `extra` ; bilans concaténés ; `from`
 * retirée. Retourne l'état et le détail des rôles attribués.
 */
export function mergeInterventions(
  tasks: AnyRec[],
  interventions: AnyRec[],
  targetId: string,
  fromId: string
): { tasks: AnyRec[]; interventions: AnyRec[]; moved: Array<{ task: AnyRec; role: Role; demoted: boolean }> } {
  if (targetId === fromId) throw new Error("mergeFrom doit désigner une autre intervention");
  const target = interventions.find((i) => i.id === targetId);
  const from = interventions.find((i) => i.id === fromId);
  if (!target) throw new Error(`Intervention introuvable : ${targetId}`);
  if (!from) throw new Error(`Intervention à fusionner introuvable : ${fromId}`);
  const held = new Set(tasks.filter((t) => t.interventionId === targetId).map((t) => String(t.interventionRole)));
  const moved: Array<{ task: AnyRec; role: Role; demoted: boolean }> = [];
  const out = tasks.map((t) => {
    if (t.interventionId !== fromId) return t;
    const wanted = String(t.interventionRole ?? "extra") as Role;
    const demoted = PRIMARY_ROLES.includes(wanted) && held.has(wanted);
    const role: Role = demoted ? "extra" : wanted;
    if (PRIMARY_ROLES.includes(role)) held.add(role);
    const nt = { ...t, interventionId: targetId, interventionRole: role };
    moved.push({ task: nt, role, demoted });
    return nt;
  });
  const text = [target.debriefText, from.debriefText].filter((x) => typeof x === "string" && x.trim()).join("\n\n");
  const carry = [...((target.carryOver as AnyRec[]) ?? []), ...((from.carryOver as AnyRec[]) ?? [])];
  const mergedTarget: AnyRec = {
    ...target,
    debriefText: text || null,
    carryOver: carry,
    ...(target.debriefAt || from.debriefAt ? { debriefAt: target.debriefAt ?? from.debriefAt } : {}),
  };
  const nextInterventions = interventions.filter((i) => i.id !== fromId).map((i) => (i.id === targetId ? mergedTarget : i));
  return { tasks: out, interventions: nextInterventions, moved };
}
