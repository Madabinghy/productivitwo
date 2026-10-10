// Suppression d'une tâche de projet (outil MCP delete_task) — logique pure.
// Même effet que « Supprimer la tâche » de l'app : la tâche (et ses actions)
// quitte le tableau `tasks` du projet. Les blocs du programme encore À VENIR qui
// la visent sont libérés (status "deleted") ; le vécu (fait, passé) ne bouge pas.

type Task = Record<string, unknown>;
type Block = Record<string, unknown>;

export interface TaskRemoval {
  remaining: Task[];
  removed: Task | null;
  /** Rôle principal dans une séance (prep / session / debrief) : à confirmer. */
  interventionRole: string | null;
}

export function removeTask(tasks: Task[], taskId: string): TaskRemoval {
  const removed = tasks.find((t) => t.id === taskId) ?? null;
  const role = removed && removed.interventionId && removed.interventionRole !== "extra"
    ? String(removed.interventionRole ?? "séance")
    : null;
  return {
    remaining: tasks.filter((t) => t.id !== taskId),
    removed,
    interventionRole: role,
  };
}

function toMin(hm: unknown): number {
  const m = /^(\d{1,2}):(\d{2})$/.exec(String(hm ?? ""));
  return m ? Number(m[1]) * 60 + Number(m[2]) : 0;
}

/** Libère les blocs à venir d'une tâche dans le programme d'un jour.
 *  [nowMin] = minute vécue si [isToday], ignorée sinon (tout le jour est à venir). */
export function freeTaskBlocks(
  blocks: Block[],
  projectId: string,
  taskId: string,
  opts: { isToday: boolean; nowMin: number }
): { blocks: Block[]; freed: Block[] } {
  const freed: Block[] = [];
  const out = blocks.map((b) => {
    if (b.projectId !== projectId || b.taskId !== taskId) return b;
    if ((b.status ?? "pending") !== "pending") return b;
    if (opts.isToday && toMin(b.startTime) < opts.nowMin) return b;
    const nb = { ...b, status: "deleted" };
    freed.push(nb);
    return nb;
  });
  return { blocks: out, freed };
}
