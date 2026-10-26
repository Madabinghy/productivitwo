// ── D : programme du jour moins haché (2026-10) ──────────────────────────────
// Diagnostic : les blocs copiaient la granularité des actions (15–25 min, une
// action = un bloc), et l'utilisateur retravaillait le programme à la main.
// Règle : un bloc de travail dure 30 min minimum ; les actions consécutives
// d'une même tâche tiennent dans UN bloc nommé par la tâche (actionId = la
// première action, les suivantes s'enchaînent dans l'écran bloc). Routines,
// pauses, préparations et rendez-vous ne sont pas concernés. Pure, pas d'I/O.

export const BLOCK_RULES =
  "BLOCS : 30 min minimum pour un bloc de travail (projet / activité) ; les actions consécutives d'une " +
  "même tâche vont dans UN SEUL bloc nommé par la tâche (actionId = la première, l'écran bloc enchaîne " +
  "les suivantes) plutôt qu'un bloc par action. Routines, pauses, prep (5 min) et rendez-vous gardent " +
  "leur durée propre.";

export const MIN_WORK_BLOCK_MIN = 30;

export interface BlockLike {
  startTime: string;
  durationMin: number;
  title: string;
  category?: string | null;
  kind?: string | null;
  projectId?: string | null;
  taskId?: string | null;
  activityId?: string | null;
  gcalEventId?: string | null;
}

function toMin(hm: string): number {
  const [h, m] = hm.split(":").map((x) => parseInt(x, 10));
  return (h || 0) * 60 + (m || 0);
}

function isWorkBlock(b: BlockLike): boolean {
  if (b.gcalEventId) return false;
  if (b.kind && b.kind !== "normal") return false;
  if (b.category === "routine" || b.category === "break") return false;
  return !!(b.projectId || b.taskId || (b.activityId && b.category !== "personal"));
}

export interface BlockAdvice {
  short: BlockLike[];
  mergeable: Array<{ taskId: string; blocks: BlockLike[] }>;
}

/** Blocs de travail trop courts, et suites de blocs consécutifs d'une même tâche. */
export function analyzeBlocks(blocks: BlockLike[]): BlockAdvice {
  const sorted = [...blocks].sort((a, b) => toMin(a.startTime) - toMin(b.startTime));
  const short = sorted.filter((b) => isWorkBlock(b) && b.durationMin < MIN_WORK_BLOCK_MIN);
  const mergeable: BlockAdvice["mergeable"] = [];
  let run: BlockLike[] = [];
  const flush = () => {
    if (run.length >= 2) mergeable.push({ taskId: String(run[0].taskId), blocks: run });
    run = [];
  };
  for (const b of sorted) {
    const prev = run[run.length - 1];
    const sameTask = prev && b.taskId && prev.taskId === b.taskId &&
      toMin(b.startTime) - (toMin(prev.startTime) + prev.durationMin) <= 15;
    if (sameTask) run.push(b);
    else { flush(); run = isWorkBlock(b) && b.taskId ? [b] : []; }
  }
  flush();
  return { short, mergeable };
}

/** Ligne d'avis pour la réponse de schedule_day, "" si rien à dire. */
export function blockAdvice(blocks: BlockLike[]): string {
  const { short, mergeable } = analyzeBlocks(blocks);
  const rows: string[] = [];
  if (short.length) {
    rows.push(`• ${short.length} bloc(s) de travail < ${MIN_WORK_BLOCK_MIN} min : ` +
      short.slice(0, 4).map((b) => `${b.startTime} « ${b.title} » (${b.durationMin} min)`).join(", ") +
      (short.length > 4 ? "…" : "") + " — regroupe-les ou allonge-les.");
  }
  for (const m of mergeable.slice(0, 3)) {
    const total = m.blocks.reduce((s, b) => s + b.durationMin, 0);
    rows.push(`• ${m.blocks.length} blocs consécutifs sur la même tâche (${m.blocks[0].startTime} → ` +
      `${m.blocks[m.blocks.length - 1].startTime}, ${total} min) : un seul bloc nommé par la tâche suffit, ` +
      `l'écran bloc enchaîne les actions.`);
  }
  if (!rows.length) return "";
  return `\n⏱ Programme haché (règle : ${MIN_WORK_BLOCK_MIN} min minimum, une tâche = un bloc) :\n${rows.join("\n")}`;
}
