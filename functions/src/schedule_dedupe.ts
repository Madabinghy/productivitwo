// Doublons agenda ↔ programme (constaté 2026-10-02) : un rendez-vous Google
// arrive dans le programme comme bloc MIROIR (gcalEventId), puis Claude, qui
// le voit dans l'agenda, le recréait comme bloc ordinaire dans schedule_day
// → deux lignes identiques dans Aujourd'hui. Règle unique : même début +
// même titre (ou même durée) qu'un miroir vivant = le même rendez-vous.

type AnyBlock = Record<string, unknown>;

const norm = (s: unknown) =>
  String(s ?? "")
    .toLowerCase()
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .replace(/\s+/g, " ")
    .trim();

/** Même créneau qu'un miroir : même heure de début ET (même titre OU même durée). */
export function sameSlot(a: AnyBlock, mirror: AnyBlock): boolean {
  if (String(a.startTime) !== String(mirror.startTime)) return false;
  return norm(a.title) === norm(mirror.title) || Number(a.durationMin) === Number(mirror.durationMin);
}

export const isLiveMirror = (b: AnyBlock) => b.gcalEventId != null && b.status !== "deleted";

/** Sépare les blocs entrants : ceux à garder, ceux qui doublonnent un miroir. */
export function splitAgainstMirrors<T extends AnyBlock>(
  incoming: T[],
  existing: AnyBlock[]
): { kept: T[]; dropped: T[] } {
  const mirrors = existing.filter(isLiveMirror);
  const kept: T[] = [];
  const dropped: T[] = [];
  for (const b of incoming) {
    (mirrors.some((m) => sameSlot(b, m)) ? dropped : kept).push(b);
  }
  return { kept, dropped };
}

/**
 * Nettoyage d'un programme existant : un bloc ORDINAIRE (sans gcalEventId)
 * qui doublonne un miroir vivant est retiré. Retourne le tableau nettoyé et
 * le nombre de retraits (0 = rien à écrire).
 */
export function dropPlainDuplicates(blocks: AnyBlock[]): { blocks: AnyBlock[]; removed: number } {
  const mirrors = blocks.filter(isLiveMirror);
  if (mirrors.length === 0) return { blocks, removed: 0 };
  const out: AnyBlock[] = [];
  let removed = 0;
  for (const b of blocks) {
    const plain = b.gcalEventId == null && b.status !== "done";
    if (plain && mirrors.some((m) => sameSlot(b, m))) {
      removed++;
      continue;
    }
    out.push(b);
  }
  return { blocks: out, removed };
}

/** "HH:mm" → minutes depuis minuit (format invalide → 0). */
export const toMin = (hm: unknown): number => {
  const m = /^(\d{1,2}):(\d{2})$/.exec(String(hm ?? ""));
  return m ? Number(m[1]) * 60 + Number(m[2]) : 0;
};

/** Bloc qui OCCUPE son créneau : ni supprimé, ni sauté. */
export const isOccupying = (b: AnyBlock) => b.status !== "deleted" && b.status !== "skipped";

const overlaps = (a: AnyBlock, b: AnyBlock): boolean => {
  const aS = toMin(a.startTime), aE = aS + Number(a.durationMin ?? 0);
  const bS = toMin(b.startTime), bE = bS + Number(b.durationMin ?? 0);
  return aS < bE && bS < aE;
};

/**
 * Mode « compléter » de schedule_day (programmation automatique, 2026-10) :
 * le programme existant est conservé TEL QUEL (blocs faits, manuels, reports,
 * tombstones) et un bloc entrant n'est posé que s'il ne chevauche aucun bloc
 * existant qui occupe son créneau. Les entrants qui se chevauchent entre eux
 * sont posés dans l'ordre : le second est écarté.
 */
export function fillAgainstExisting<T extends AnyBlock>(
  incoming: T[],
  existing: AnyBlock[]
): { kept: T[]; dropped: T[]; conflicts: Array<{ block: T; by: AnyBlock }> } {
  const busy: AnyBlock[] = existing.filter(isOccupying);
  const kept: T[] = [];
  const dropped: T[] = [];
  const conflicts: Array<{ block: T; by: AnyBlock }> = [];
  for (const b of incoming) {
    const by = busy.find((e) => overlaps(b, e));
    if (by) {
      dropped.push(b);
      conflicts.push({ block: b, by });
    } else {
      kept.push(b);
      busy.push(b);
    }
  }
  return { kept, dropped, conflicts };
}

/** Session de chrono ramenée aux minutes murales du jour du programme. */
export interface DaySession {
  startMin: number;
  endMin: number;
  taskId?: string | null;
  activityId?: string | null;
}

/** Un chrono RÉEL a tourné pour ce bloc : même tâche (sinon même activité)
 *  et au moins une minute en commun avec son créneau. */
export function blockHasSession(b: AnyBlock, sessions: DaySession[]): boolean {
  const bS = toMin(b.startTime), bE = bS + Number(b.durationMin ?? 0);
  return sessions.some((s) => {
    const sameSource = (b.taskId != null && s.taskId === b.taskId) ||
      (b.taskId == null && b.activityId != null && s.activityId === b.activityId);
    return sameSource && s.startMin < bE && bS < s.endMin;
  });
}

/**
 * Bloc VÉCU, qu'un remplacement de programme ne doit jamais effacer (B10) :
 * **fait**, ou un chrono réel y est rattaché ([sessions]). Les tombstones
 * (`skipped`, `deleted`) sont gardés aussi : ils n'occupent pas le créneau,
 * disent « ne pas recréer » et nourrissent le check-in du soir. Un bloc
 * passé NON fait n'est pas protégé : il a sauté, il se remplace comme un bloc
 * futur (constat 2026-10-07 : un BPF de 22 h 40 resté `pending` bloquait
 * 23 h 15 et personne ne pouvait le retirer).
 * (La première version protégeait « commencé avant maintenant » : trop large.)
 */
export function isSettledBlock(
  b: AnyBlock,
  ctx: { sessions?: DaySession[] } = {}
): boolean {
  if (b.status === "done" || b.status === "skipped" || b.status === "deleted") return true;
  return blockHasSession(b, ctx.sessions ?? []);
}

const fromMin = (m: number) => `${String(Math.floor(m / 60)).padStart(2, "0")}:${String(m % 60).padStart(2, "0")}`;

/**
 * Créneau libre le plus proche de l'heure demandée (B9) : on cherche, par pas
 * de 15 min, le début le plus proche (avant ou après) dans la fenêtre
 * [startMin, endMin[ où le bloc tient sans chevaucher un bloc occupant.
 * Null si aucun. Retourne "HH:mm".
 */
export function nearestFreeSlot(
  block: AnyBlock,
  existing: AnyBlock[],
  window: { startMin: number; endMin: number },
  step = 15
): string | null {
  const dur = Number(block.durationMin ?? 0);
  if (dur <= 0) return null;
  const busy = existing.filter(isOccupying);
  const want = toMin(block.startTime);
  const fits = (start: number) =>
    start >= window.startMin &&
    start + dur <= window.endMin &&
    !busy.some((e) => overlaps({ startTime: fromMin(start), durationMin: dur }, e));
  const base = Math.round(want / step) * step;
  for (let delta = 0; delta <= 24 * 60; delta += step) {
    for (const start of delta === 0 ? [base] : [base + delta, base - delta]) {
      if (fits(start)) return fromMin(start);
    }
  }
  return null;
}

/** Créneau libre le plus proche : dans la journée active d'abord, sinon
 *  n'importe où dans les 24 h (le soir tard après le dernier bloc, par ex.). */
export function nearestFreeSlotAnywhere(
  block: AnyBlock,
  existing: AnyBlock[],
  window: { startMin: number; endMin: number },
  step = 15
): { slot: string; inWindow: boolean } | null {
  const inWin = nearestFreeSlot(block, existing, window, step);
  if (inWin) return { slot: inWin, inWindow: true };
  const any = nearestFreeSlot(block, existing, { startMin: 0, endMin: 24 * 60 }, step);
  return any ? { slot: any, inWindow: false } : null;
}
