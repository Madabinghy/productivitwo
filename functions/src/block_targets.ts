// Plusieurs cibles dans un même bloc (2026-11-16) : `projectId` / `taskId` /
// `actionId` restent la cible principale ; les suivantes vivent dans
// `extraTargets`, dans l'ordre. Aligné sur `BlockTarget` de l'app
// (`lib/models/schedule.dart`, `lib/utils/block_stack.dart`).

export type BlockTarget = { projectId: string; taskId?: string; actionId?: string };

/** Au-delà de 6 cibles (principale comprise), l'app n'en accepte plus. */
export const MAX_BLOCK_TARGETS = 6;

const str = (v: unknown): string | undefined => (typeof v === "string" && v.trim() ? v.trim() : undefined);

/**
 * Les cibles suivantes d'un bloc, nettoyées : sans projet principal il n'y en
 * a pas ; une cible déjà portée (même projet et même tâche) n'est gardée
 * qu'une fois ; jamais plus de MAX_BLOCK_TARGETS avec la principale.
 */
export function normalizeExtraTargets(
  input: unknown,
  primary: { projectId?: string | null; taskId?: string | null }
): BlockTarget[] {
  if (!primary.projectId || !Array.isArray(input)) return [];
  const seen = new Set([`${primary.projectId}|${primary.taskId ?? ""}`]);
  const out: BlockTarget[] = [];
  for (const raw of input) {
    if (out.length >= MAX_BLOCK_TARGETS - 1) break;
    if (!raw || typeof raw !== "object") continue;
    const r = raw as Record<string, unknown>;
    const projectId = str(r.projectId);
    if (!projectId) continue;
    const taskId = str(r.taskId);
    const actionId = taskId ? str(r.actionId) : undefined;
    const key = `${projectId}|${taskId ?? ""}`;
    if (seen.has(key)) continue;
    seen.add(key);
    out.push({ projectId, ...(taskId ? { taskId } : {}), ...(actionId ? { actionId } : {}) });
  }
  return out;
}

/** « aussi projet:p2 tâche:t9 » pour la ligne d'un bloc lu par Claude. */
export function extraTargetLinks(extra: unknown): string[] {
  if (!Array.isArray(extra)) return [];
  return extra
    .filter((t): t is Record<string, unknown> => !!t && typeof t === "object" && typeof (t as Record<string, unknown>).projectId === "string")
    .map((t) => `aussi projet:${t.projectId}${t.taskId ? ` tâche:${t.taskId}` : ""}${t.actionId ? ` action:${t.actionId}` : ""}`);
}
