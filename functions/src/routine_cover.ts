/**
 * Routines « sur 7 jours » et « le chrono coche » (2026-11-19) — miroir serveur
 * de `lib/utils/routine_cover.dart` (**garder alignés**).
 *
 * Une routine QUOTIDIENNE réglée `rolling` se compte sur les 7 derniers jours :
 * ce qui est fait en plus couvre les jours suivants ; le retard ne s'accumule
 * pas (un jour sans avance demande la cible normale, jamais plus).
 * `minPerHit` = minutes de chrono sur l'activité liée (`linkedActivityId`) qui
 * valent une coche ; c'est l'APP qui pose ces coches.
 */

export const ROUTINE_WINDOW_DAYS = 7;

/** Ce qu'un jour demande d'après les 6 jours d'avant. */
export function rollingDayTarget(target: number, pastSum: number): number {
  const need = ROUTINE_WINDOW_DAYS * target - pastSum;
  if (need <= 0) return 0;
  return need > target ? target : need;
}

/** `YYYY-MM-DD` décalé de `days` jours. */
export function shiftYmd(ymd: string, days: number): string {
  const [y, m, d] = ymd.split("-").map((x) => parseInt(x, 10));
  const t = new Date(Date.UTC(y, (m || 1) - 1, (d || 1) + days));
  return t.toISOString().slice(0, 10);
}

/**
 * Jour VÉCU d'une coche d'après son horodatage ISO lu tel quel (heure locale de
 * l'app) : avant la bascule (5 h par défaut), elle appartient à la veille.
 * Chaîne illisible = "".
 */
export function livedYmdOfTs(ts: string, dayStartMin = 300): string {
  if (typeof ts !== "string" || ts.length < 16) return "";
  const ymd = ts.slice(0, 10);
  const min = parseInt(ts.slice(11, 13), 10) * 60 + parseInt(ts.slice(14, 16), 10);
  if (!/^\d{4}-\d{2}-\d{2}$/.test(ymd) || isNaN(min)) return "";
  return min < dayStartMin ? shiftYmd(ymd, -1) : ymd;
}

export interface RoutineCover {
  /** Cible par jour. */
  target: number;
  todayDone: number;
  /** Coches des 6 jours passés de la fenêtre. */
  pastDone: number;
  /** Ce que le jour demande (0 = l'avance le couvre). */
  dayTarget: number;
  /** Jours à venir déjà couverts si rien d'autre n'est fait. */
  aheadDays: number;
  /** Ce que le lendemain demandera si rien d'autre n'est fait ce jour-là. */
  tomorrowTarget: number;
  /** La part du jour est faite, ou l'avance la couvre. */
  held: boolean;
}

/** Où en est une routine « sur 7 jours » le jour `ymd` (coches par jour vécu). */
export function routineCover(target: number, counts: Record<string, number>, ymd: string): RoutineCover {
  const t = target > 0 ? Math.round(target) : 1;
  const on = (back: number) => counts[shiftYmd(ymd, -back)] ?? 0;
  const window: number[] = [];
  for (let i = ROUTINE_WINDOW_DAYS - 1; i >= 1; i--) window.push(on(i));
  const pastDone = window.reduce((s, v) => s + v, 0);
  const todayDone = on(0);
  const dayTarget = rollingDayTarget(t, pastDone);
  const future = [...window, todayDone];
  const next = () => rollingDayTarget(t, future.slice(-(ROUTINE_WINDOW_DAYS - 1)).reduce((s, v) => s + v, 0));
  const tomorrowTarget = next();
  const held = todayDone >= dayTarget;
  let aheadDays = 0;
  if (held) {
    while (aheadDays < ROUTINE_WINDOW_DAYS - 1 && next() === 0) {
      aheadDays++;
      future.push(0);
    }
  }
  return { target: t, todayDone, pastDone, dayTarget, aheadDays, tomorrowTarget, held };
}

/** Routine quotidienne réglée « sur 7 jours ». */
export function isRollingRoutine(a: Record<string, unknown>): boolean {
  return a.type === "habit" && (a.habitFreq === 0 || a.habitFreq === "daily") && a.rolling === true;
}

/** Ce que Claude lit d'une routine « sur 7 jours » pour le jour visé. */
export function coverNote(c: RoutineCover): string {
  const window = `${c.pastDone + c.todayDone} / ${ROUTINE_WINDOW_DAYS * c.target} sur 7 j`;
  if (c.dayTarget === 0) {
    const ahead = c.aheadDays > 0 ? `, encore ${c.aheadDays} j d'avance ensuite` : "";
    return `sur 7 jours · COUVERTE ce jour-là par son avance (${window}${ahead}) — ne pas la programmer`;
  }
  if (c.held) return `sur 7 jours · part du jour faite (${window})`;
  if (c.dayTarget < c.target) {
    return `sur 7 jours · l'avance réduit la part du jour à ${c.dayTarget} au lieu de ${c.target} (${window})`;
  }
  return `sur 7 jours · part du jour ${c.dayTarget} (${window}) · en faire plus couvre les jours suivants`;
}

const truthy = (v: unknown) => v === true || v === 1 || v === "true" || v === "1";

/** Minutes par coche : entier de 1 à 240 ; 0, vide ou illisible = pas de chrono qui coche. */
export function normalizeMinPerHit(v: unknown): number | null {
  if (v === null || v === undefined || v === "") return null;
  const n = Math.round(Number(v));
  if (!isFinite(n) || n <= 0) return null;
  return Math.min(240, n);
}

/**
 * Champs à écrire pour `rolling` / `minPerHit`, et ce qu'on en dit. `current` =
 * la routine telle qu'elle sera après les autres modifications de l'appel.
 */
export function rhythmPatch(
  updates: { rolling?: unknown; minPerHit?: unknown },
  current: { type?: unknown; habitFreq?: unknown; linkedActivityId?: unknown },
): { patch: Record<string, unknown>; notes: string[] } {
  const patch: Record<string, unknown> = {};
  const notes: string[] = [];
  const isHabit = current.type === "habit";
  const daily = current.habitFreq === 0 || current.habitFreq === "daily";
  if (updates.rolling !== undefined) {
    const on = truthy(updates.rolling);
    if (on && !(isHabit && daily)) {
      notes.push("⚠️ « Sur 7 jours » ne s'applique qu'aux routines quotidiennes : rien n'a été changé (une hebdomadaire compte déjà sur 7 jours glissants).");
    } else if (isHabit) {
      patch.rolling = on;
      notes.push(on
        ? "Rythme : sur 7 jours — ce qui est fait en plus couvre les jours suivants, un jour raté ne s'ajoute pas."
        : "Rythme : chaque jour.");
    } else {
      notes.push("⚠️ « Sur 7 jours » concerne les routines, pas les activités de temps.");
    }
  }
  if (updates.minPerHit !== undefined) {
    const n = normalizeMinPerHit(updates.minPerHit);
    if (!isHabit) {
      notes.push("⚠️ « Le chrono coche » concerne les routines, pas les activités de temps.");
    } else {
      patch.minPerHit = n;
      if (n === null) {
        notes.push("Le chrono ne coche plus cette routine.");
      } else {
        const linked = typeof current.linkedActivityId === "string" && current.linkedActivityId.trim() !== "";
        notes.push(`Le chrono coche : 1 coche = ${n} min sur l'activité liée (les coches sont posées par l'app, chrono en cours ou à l'arrêt).`);
        if (!linked) notes.push("⚠️ Aucune activité liée : rien ne sera coché tant que linkedActivityId n'est pas posé.");
      }
    }
  }
  return { patch, notes };
}
