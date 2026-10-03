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
): { kept: T[]; dropped: T[] } {
  const busy: AnyBlock[] = existing.filter(isOccupying);
  const kept: T[] = [];
  const dropped: T[] = [];
  for (const b of incoming) {
    if (busy.some((e) => overlaps(b, e))) {
      dropped.push(b);
    } else {
      kept.push(b);
      busy.push(b);
    }
  }
  return { kept, dropped };
}
