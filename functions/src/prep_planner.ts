// « Planifier la prépa » (brief 2026-10, § 2.3) : pousser les actions de
// préparation d'une intervention dans les trous du programme. Règles
// utilisateur : prépa LA VEILLE AU SOIR de préférence (puis les soirs
// précédents, puis le reste des journées), IMPRESSION SUR PLACE collée au
// début du créneau (pas le matin à la maison), respect des blocs existants
// (rendez-vous Google Agenda compris) et de la journée active. Logique pure ;
// l'écriture passe par schedule_day(mode:"fill") dans execute.ts.

import { isOccupying, toMin } from "./schedule_dedupe";

type AnyRec = Record<string, unknown>;

export interface PrepAction {
  id: string;
  title: string;
  estimatedMin?: number | null;
  contexts?: string[];
}

export interface Placement {
  date: string;
  startTime: string;
  durationMin: number;
  actionId: string;
  title: string;
  /** « veille au soir » · « soir J-n » · « journée J-n » · « impression sur place » */
  why: string;
}

export interface Unplaced {
  actionId: string;
  title: string;
  durationMin: number;
  /** Les deux meilleurs créneaux de repli (hors préférence du soir). */
  alternatives: Array<{ date: string; startTime: string }>;
}

export interface PlanPrepInput {
  intervention: { date: string; startTime: string; title: string };
  actions: PrepAction[];
  /** Blocs existants par jour (YYYY-MM-DD → blocs, tous statuts). */
  existing: Record<string, AnyRec[]>;
  window: { startMin: number; endMin: number };
  today: string; // YYYY-MM-DD
  nowMin: number; // minutes depuis minuit, pour ne rien poser dans le passé
  /** Premier jour où l'on peut préparer (début de la tâche 📝), défaut J-7. */
  earliest?: string;
  eveningFromMin?: number; // défaut 18 h
  printLeadMin?: number; // marge avant la séance pour imprimer, défaut 15
  defaultActionMin?: number; // défaut 30
}

export const isPrintAction = (a: PrepAction) =>
  (a.contexts ?? []).some((c) => c.toLowerCase() === "@impression") ||
  a.title.trim().toLowerCase().startsWith("imprimer");

const fromMin = (m: number) => `${String(Math.floor(m / 60)).padStart(2, "0")}:${String(m % 60).padStart(2, "0")}`;

export function addDays(ymd: string, n: number): string {
  const d = new Date(`${ymd}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + n);
  return d.toISOString().slice(0, 10);
}

const daysBetween = (a: string, b: string) =>
  Math.round((Date.parse(`${b}T00:00:00Z`) - Date.parse(`${a}T00:00:00Z`)) / 86400000);

interface Busy { start: number; end: number }

function busyOf(blocks: AnyRec[]): Busy[] {
  return blocks
    .filter(isOccupying)
    .map((b) => ({ start: toMin(b.startTime), end: toMin(b.startTime) + Number(b.durationMin ?? 0) }))
    .filter((b) => b.end > b.start);
}

const fits = (busy: Busy[], start: number, dur: number) =>
  !busy.some((b) => start < b.end && b.start < start + dur);

/** Premier début libre ≥ from dans [from, to − dur], par pas de 15 min. */
function firstFree(busy: Busy[], from: number, to: number, dur: number, step = 15): number | null {
  const base = Math.ceil(from / step) * step;
  for (let s = base; s + dur <= to; s += step) {
    if (fits(busy, s, dur)) return s;
  }
  return null;
}

/** Dernier début libre ≤ (to − dur) en remontant depuis to, par pas de 15 min. */
function lastFree(busy: Busy[], from: number, to: number, dur: number, step = 15): number | null {
  const top = Math.floor((to - dur) / step) * step;
  for (let s = top; s >= from; s -= step) {
    if (fits(busy, s, dur)) return s;
  }
  return null;
}

export function planPrep(input: PlanPrepInput): { placements: Placement[]; unplaced: Unplaced[] } {
  const { intervention, window, today, nowMin } = input;
  const evening = input.eveningFromMin ?? 18 * 60;
  const lead = input.printLeadMin ?? 15;
  const defMin = input.defaultActionMin ?? 30;
  const D = intervention.date;
  const earliest = input.earliest && input.earliest > today ? input.earliest : today;
  const firstDay = addDays(D, -7) > earliest ? addDays(D, -7) : earliest;

  // Occupation mutable par jour (on y ajoute nos propres placements).
  const busy = new Map<string, Busy[]>();
  const busyFor = (date: string) => {
    if (!busy.has(date)) busy.set(date, busyOf(input.existing[date] ?? []));
    return busy.get(date)!;
  };
  const lowerBound = (date: string) => (date === today ? Math.max(window.startMin, nowMin) : window.startMin);

  const placements: Placement[] = [];
  const unplaced: Unplaced[] = [];
  const dur = (a: PrepAction) => Math.max(5, a.estimatedMin ?? defMin);

  // 1) Impression : sur place, collée au début de la séance.
  const prints = input.actions.filter(isPrintAction);
  if (prints.length) {
    const total = Math.max(lead, prints.reduce((n, a) => n + (a.estimatedMin ?? 10), 0));
    const sessionStart = toMin(intervention.startTime);
    const b = busyFor(D);
    let start: number | null = null;
    // Le plus tard possible avant la séance, en reculant si un bloc gêne.
    for (let s = sessionStart - total; s >= window.startMin; s -= 5) {
      if (fits(b, s, total) && !(D === today && s < nowMin)) { start = s; break; }
    }
    if (start !== null) {
      const first = prints[0];
      placements.push({
        date: D, startTime: fromMin(start), durationMin: total, actionId: first.id,
        title: prints.length > 1 ? `🖨 Imprimer sur place — ${intervention.title}` : `🖨 ${first.title}`,
        why: "impression sur place",
      });
      b.push({ start, end: start + total });
    } else {
      for (const a of prints) unplaced.push({ actionId: a.id, title: a.title, durationMin: dur(a), alternatives: [] });
    }
  }

  // 2) Les autres actions : veille au soir, puis soirs précédents, puis journées.
  const others = input.actions.filter((a) => !isPrintAction(a));
  const days: string[] = [];
  for (let d = addDays(D, -1); d >= firstDay; d = addDays(d, -1)) days.push(d);
  // Jour J avant la séance (matin) en dernier recours.
  const sessionStart = toMin(intervention.startTime);

  type Pass = { name: (d: string) => string; range: (d: string) => [number, number]; dates: string[]; fromEnd: boolean };
  const passes: Pass[] = [
    {
      name: (d) => (d === addDays(D, -1) ? "veille au soir" : `soir J-${daysBetween(d, D)}`),
      range: () => [Math.max(evening, window.startMin), window.endMin],
      dates: days,
      fromEnd: false,
    },
    {
      name: (d) => `journée J-${daysBetween(d, D)}`,
      range: () => [window.startMin, Math.max(evening, window.startMin)],
      dates: days,
      fromEnd: true, // le plus tard possible dans la journée
    },
    {
      name: () => "le jour même, avant la séance",
      range: () => [window.startMin, Math.min(sessionStart - lead, window.endMin)],
      dates: [D],
      fromEnd: true,
    },
  ];

  for (const a of others) {
    const need = dur(a);
    let placed = false;
    for (const pass of passes) {
      for (const date of pass.dates) {
        if (date < earliest) continue;
        const [lo0, hi] = pass.range(date);
        const lo = Math.max(lo0, lowerBound(date));
        if (hi - lo < need) continue;
        const b = busyFor(date);
        const start = pass.fromEnd ? lastFree(b, lo, hi, need) : firstFree(b, lo, hi, need);
        if (start === null) continue;
        placements.push({ date, startTime: fromMin(start), durationMin: need, actionId: a.id, title: a.title, why: pass.name(date) });
        b.push({ start, end: start + need });
        placed = true;
        break;
      }
      if (placed) break;
    }
    if (!placed) {
      // Repli : les deux premiers trous de la fenêtre, tous jours confondus.
      const alts: Array<{ date: string; startTime: string }> = [];
      for (const date of [...days].reverse().concat(D)) {
        if (alts.length >= 2 || date < earliest) continue;
        const b = busyFor(date);
        const hi = date === D ? Math.min(sessionStart - lead, window.endMin) : window.endMin;
        const s = firstFree(b, lowerBound(date), hi, need);
        if (s !== null) alts.push({ date, startTime: fromMin(s) });
      }
      unplaced.push({ actionId: a.id, title: a.title, durationMin: need, alternatives: alts });
    }
  }

  placements.sort((x, y) => (x.date + x.startTime).localeCompare(y.date + y.startTime));
  return { placements, unplaced };
}
