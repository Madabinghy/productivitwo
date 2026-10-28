/**
 * Élan (lot 2 badges, 2026-10) — logique pure, miroir de `lib/utils/elan_logic.dart`
 * (garder alignés). Pointages d'état `users/{uid}/mood_marks` : élan avant
 * (1 Flemme … 5 Lancé, un par créneau matin / après-midi / soir du jour vécu),
 * effort après un bloc (0 Facile · 1 Juste · 2 Dur), humeur du soir (0 Bas · 1
 * Neutre · 2 Bon). Une FENÊTRE va d'un pointage d'élan au suivant ou à la
 * bascule du jour vécu ; « victoire sur la flemme » = bloc terminé ou routine
 * quotidienne atteinte dans une fenêtre à élan ≤ 2. Rien n'est stocké : le lien
 * pointage ↔ fait est recalculé.
 */

export const MOOD_KINDS = ["elan", "effort", "mood"] as const;
export type MoodKind = (typeof MOOD_KINDS)[number];
export const ELAN_LABELS = ["", "Flemme", "Mou", "Moyen", "En forme", "Lancé"];
export const EFFORT_LABELS = ["Facile", "Juste", "Dur"];
export const MOOD_LABELS = ["Bas", "Neutre", "Bon"];
export const ELAN_BUCKETS = ["matin", "aprem", "soir"] as const;
export type ElanBucket = (typeof ELAN_BUCKETS)[number];
export const DEFAULT_DAY_START_MIN = 5 * 60;

export interface MoodMarkDoc {
  id: string;
  at: string; // ISO
  ymd: string; // jour vécu YYYY-MM-DD
  kind: MoodKind;
  value: number;
  moment?: string;
  activityId?: string;
  projectId?: string;
  taskId?: string;
  actionId?: string;
  blockId?: string;
}

/** Valeur admise pour un pointage : 1–5 pour l'élan, 0–2 pour l'effort et l'humeur. */
export function validMoodValue(kind: MoodKind, value: number): boolean {
  if (!Number.isInteger(value)) return false;
  return kind === "elan" ? value >= 1 && value <= 5 : value >= 0 && value <= 2;
}

/** Créneau d'élan d'une minute du jour vécu (0 → 24 h 30). */
export function elanBucket(livedMin: number): ElanBucket {
  return livedMin < 12 * 60 ? "matin" : livedMin < 18 * 60 ? "aprem" : "soir";
}

/** Décalage (minutes à ajouter à l'UTC) du fuseau Europe/Paris à un instant. */
export function parisOffsetMin(d: Date): number {
  const parts = new Intl.DateTimeFormat("sv-SE", {
    timeZone: "Europe/Paris", year: "numeric", month: "2-digit", day: "2-digit",
    hour: "2-digit", minute: "2-digit", hour12: false,
  }).format(d); // « 2026-10-26 14:05 »
  const local = Date.UTC(+parts.slice(0, 4), +parts.slice(5, 7) - 1, +parts.slice(8, 10), +parts.slice(11, 13), +parts.slice(14, 16));
  return Math.round((local - d.getTime()) / 60_000);
}

function offsetFor(d: Date, offsetMin: number | null | undefined): number {
  return typeof offsetMin === "number" && isFinite(offsetMin) ? offsetMin : parisOffsetMin(d);
}

/** Jour vécu et minute vécue (00:30 → 24 h 30 avant la bascule) d'un instant. */
export function livedParts(
  iso: string | Date,
  offsetMin: number | null | undefined,
  dayStartMin = DEFAULT_DAY_START_MIN
): { ymd: string; min: number } {
  const d = iso instanceof Date ? iso : new Date(iso);
  const local = new Date(d.getTime() + offsetFor(d, offsetMin) * 60_000);
  let min = local.getUTCHours() * 60 + local.getUTCMinutes();
  let day = Date.UTC(local.getUTCFullYear(), local.getUTCMonth(), local.getUTCDate());
  if (min < dayStartMin) {
    day -= 86_400_000;
    min += 24 * 60;
  }
  return { ymd: new Date(day).toISOString().slice(0, 10), min };
}

/** Fin (epoch ms) de la journée vécue `ymd` : le lendemain à l'heure de bascule. */
export function livedDayEndMs(ymd: string, offsetMin: number | null | undefined, dayStartMin = DEFAULT_DAY_START_MIN): number {
  const [y, m, d] = ymd.split("-").map(Number);
  const nextLocal = Date.UTC(y, m - 1, d + 1) + dayStartMin * 60_000;
  const approx = new Date(nextLocal);
  return nextLocal - offsetFor(approx, offsetMin) * 60_000;
}

export interface ElanWindow {
  mark: MoodMarkDoc;
  startMs: number;
  endMs: number;
}

/** Historique des changements d'élan (miroir de `dedupeMoodMarks`,
 *  lib/utils/elan_logic.dart) : chaque changement est un pointage, sauf un
 *  changement moins de ELAN_CORRECTION_MIN minutes après le précédent du même
 *  jour vécu, qui le remplace (correction). Effort : un par (jour, bloc) ;
 *  humeur : un par jour. */
export const ELAN_CORRECTION_MIN = 5;

export function moodMarkKey(m: MoodMarkDoc): string {
  if (m.kind === "effort") return `effort:${m.ymd}:${m.blockId ?? m.id}`;
  return `${m.kind}:${m.ymd}`;
}

export function dedupeMoodMarks(marks: MoodMarkDoc[]): MoodMarkDoc[] {
  const out: MoodMarkDoc[] = [];
  const elanByYmd = new Map<string, MoodMarkDoc[]>();
  const best = new Map<string, MoodMarkDoc>();
  for (const m of marks) {
    if (m.kind === "elan") {
      const l = elanByYmd.get(m.ymd) ?? [];
      l.push(m);
      elanByYmd.set(m.ymd, l);
      continue;
    }
    const k = moodMarkKey(m);
    const cur = best.get(k);
    if (!cur || Date.parse(m.at) > Date.parse(cur.at)) best.set(k, m);
  }
  out.push(...best.values());
  for (const l of elanByYmd.values()) {
    l.sort((a, b) => Date.parse(a.at) - Date.parse(b.at));
    for (let i = 0; i < l.length; i++) {
      const next = l[i + 1];
      if (next && (Date.parse(next.at) - Date.parse(l[i].at)) / 60_000 < ELAN_CORRECTION_MIN) continue;
      out.push(l[i]);
    }
  }
  return out.sort((a, b) => Date.parse(a.at) - Date.parse(b.at));
}

export function elanWindows(
  marks: MoodMarkDoc[],
  ymd: string,
  offsetMin: number | null | undefined,
  dayStartMin = DEFAULT_DAY_START_MIN
): ElanWindow[] {
  const ms = dedupeMoodMarks(marks.filter((m) => m.kind === "elan" && m.ymd === ymd))
    .map((m) => ({ m, t: Date.parse(m.at) }))
    .filter((x) => isFinite(x.t))
    .sort((a, b) => a.t - b.t);
  const end = livedDayEndMs(ymd, offsetMin, dayStartMin);
  return ms.map((x, i) => ({ mark: x.m, startMs: x.t, endMs: i + 1 < ms.length ? ms[i + 1].t : end }));
}

export interface ActivityLite { id: string; type?: string; habitFreq?: number | string | null; habitTarget?: number | null; deleted?: boolean }
export interface HitLite { habitId: string; ts: string }
export interface BlockLite { status?: string; doneAt?: string | null }

function isDailyRoutine(a: ActivityLite): boolean {
  if (a.deleted || (a.type !== "habit" && a.type !== "action")) return false;
  return a.habitFreq === 0 || a.habitFreq === "daily";
}

/** Faits dans une fenêtre : blocs terminés (`doneAt` dedans) et routines
 *  quotidiennes dont la cible du jour est atteinte PAR un hit de la fenêtre. */
export function winsIn(
  w: ElanWindow,
  blocks: BlockLite[],
  hits: HitLite[],
  activities: ActivityLite[],
  offsetMin: number | null | undefined,
  dayStartMin = DEFAULT_DAY_START_MIN
): number {
  let n = 0;
  for (const b of blocks) {
    if (b.status !== "done" || !b.doneAt) continue;
    const t = Date.parse(b.doneAt);
    if (t >= w.startMs && t < w.endMs) n++;
  }
  for (const a of activities) {
    if (!isDailyRoutine(a)) continue;
    const target = Math.max(1, a.habitTarget ?? 1);
    const dayHits = hits
      .filter((h) => h.habitId === a.id && livedParts(h.ts, offsetMin, dayStartMin).ymd === w.mark.ymd)
      .map((h) => Date.parse(h.ts))
      .sort((x, y) => x - y);
    if (dayHits.length < target) continue;
    const reachedAt = dayHits[target - 1];
    if (reachedAt >= w.startMs && reachedAt < w.endMs) n++;
  }
  return n;
}

export interface ElanDaySummary { ymd: string; marks: { bucket: string; value: number; won: boolean }[]; mood: number | null }
export interface ElanSummary {
  days: ElanDaySummary[];
  count: number;
  mean: number | null;
  lowCount: number;
  lowWon: number;
  slots: number; // créneaux pointés (3 par jour au plus)
  discipline: number | null; // 0..1
  effort: { facile: number; juste: number; dur: number };
}

/** Résumé des `days` derniers jours vécus (aujourd'hui compris). */
export function elanSummary(opts: {
  marks: MoodMarkDoc[];
  schedulesByYmd: Map<string, BlockLite[]>;
  hits: HitLite[];
  activities: ActivityLite[];
  todayYmd: string;
  days?: number;
  offsetMin?: number | null;
  dayStartMin?: number;
  nowMs?: number;
}): ElanSummary {
  const days = opts.days ?? 7;
  const dayStartMin = opts.dayStartMin ?? DEFAULT_DAY_START_MIN;
  const [y, m, d] = opts.todayYmd.split("-").map(Number);
  const out: ElanDaySummary[] = [];
  let count = 0, sum = 0, lowCount = 0, lowWon = 0, minutes = 0, weighted = 0, slots = 0;
  const nowMs = opts.nowMs ?? Date.now();
  const effort = { facile: 0, juste: 0, dur: 0 };
  for (let i = days - 1; i >= 0; i--) {
    const ymd = new Date(Date.UTC(y, m - 1, d - i)).toISOString().slice(0, 10);
    const seen = new Set<string>();
    const views = elanWindows(opts.marks, ymd, opts.offsetMin, dayStartMin).map((w) => {
      const won = winsIn(w, opts.schedulesByYmd.get(ymd) ?? [], opts.hits, opts.activities, opts.offsetMin, dayStartMin) > 0;
      count++;
      sum += w.mark.value;
      // Moyenne pondérée par le temps tenu (jusqu'au pointage suivant, la fin de journée ou maintenant).
      const mins = Math.max(0, (Math.min(w.endMs, nowMs) - w.startMs) / 60_000);
      minutes += mins;
      weighted += w.mark.value * mins;
      seen.add(w.mark.moment ?? elanBucket(livedParts(w.mark.at, opts.offsetMin, dayStartMin).min));
      if (w.mark.value <= 2) {
        lowCount++;
        if (won) lowWon++;
      }
      return { bucket: w.mark.moment ?? elanBucket(livedParts(w.mark.at, opts.offsetMin, dayStartMin).min), value: w.mark.value, won };
    });
    for (const mk of opts.marks) {
      if (mk.kind === "effort" && mk.ymd === ymd) {
        if (mk.value === 0) effort.facile++;
        else if (mk.value === 1) effort.juste++;
        else effort.dur++;
      }
    }
    const moods = opts.marks.filter((mk) => mk.kind === "mood" && mk.ymd === ymd).sort((a, b) => a.at.localeCompare(b.at));
    slots += seen.size;
    out.push({ ymd, marks: views, mood: moods.length ? moods[moods.length - 1].value : null });
  }
  const mean = count === 0 ? null : minutes > 0 ? weighted / minutes : sum / count;
  return {
    days: out,
    count,
    slots,
    mean: mean === null ? null : Math.round(mean * 10) / 10,
    lowCount,
    lowWon,
    discipline: lowCount ? Math.round((lowWon / lowCount) * 100) / 100 : null,
    effort,
  };
}

/** Une ligne pour les prompts : « Élan 7 j : moyen 2,8 (11 pointages) · face à la flemme 5 / 7 (71 %) · effort : 3 facile, 4 juste, 1 dur ». */
export function formatElanSummary(s: ElanSummary): string | null {
  if (s.count === 0) return null;
  const mean = s.mean === null ? "—" : String(s.mean).replace(".", ",");
  const disc = s.discipline === null ? "aucune fenêtre de flemme" : `face à la flemme ${s.lowWon} / ${s.lowCount} (${Math.round(s.discipline * 100)} %)`;
  const eff = s.effort.facile + s.effort.juste + s.effort.dur > 0
    ? ` · effort : ${s.effort.facile} facile, ${s.effort.juste} juste, ${s.effort.dur} dur`
    : "";
  const n = s.slots || s.count;
  return `Élan 7 j : moyen ${mean} sur 5 (${n} créneau${n > 1 ? "x" : ""} pointé${n > 1 ? "s" : ""}, moyenne pondérée par le temps) · ${disc}${eff}`;
}
