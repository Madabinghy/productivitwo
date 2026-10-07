// B1 (brief 2026-10) : push_gantt créait les tâches « Sans phase » même quand
// groupLabel reprenait le libellé d'une phase — l'IA ne connaît pas les ids
// des phases qu'elle vient d'écrire. Résolution par libellé, insensible à la
// casse et aux accents ; un phaseId qui porte un libellé est aussi résolu.

type AnyRec = Record<string, unknown>;

const norm = (s: unknown) =>
  String(s ?? "")
    .toLowerCase()
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .replace(/[^\p{L}\p{N}]+/gu, " ")
    .trim();

export interface PhaseResolution<T extends AnyRec> {
  tasks: T[];
  /** Tâches dont le phaseId a été posé ou corrigé par libellé. */
  resolved: number;
  /** phaseId fournis qui ne correspondent à aucune phase (laissés tels quels). */
  unknown: string[];
}

/**
 * Pose `phaseId` sur chaque tâche : id déjà valide → inchangé ; sinon
 * phaseId ou groupLabel égal au libellé d'une phase → id de cette phase ;
 * sinon, projet mono-phase sans indication → cette phase unique.
 */
export function resolvePhaseIds<T extends AnyRec>(phases: AnyRec[], tasks: T[]): PhaseResolution<T> {
  const ids = new Set(phases.map((p) => String(p.id)));
  const byLabel = new Map<string, string>();
  for (const p of phases) {
    const k = norm(p.label);
    if (k && !byLabel.has(k)) byLabel.set(k, String(p.id));
  }
  const only = phases.length === 1 ? String(phases[0].id) : null;
  let resolved = 0;
  const unknown: string[] = [];
  const out = tasks.map((t) => {
    const pid = typeof t.phaseId === "string" && t.phaseId.trim() ? t.phaseId : null;
    if (pid && ids.has(pid)) return t;
    const target =
      (pid && byLabel.get(norm(pid))) ||
      (typeof t.groupLabel === "string" && byLabel.get(norm(t.groupLabel))) ||
      (!pid && !t.groupLabel ? only : null);
    if (target) {
      resolved++;
      return { ...t, phaseId: target };
    }
    if (pid) unknown.push(pid);
    return t;
  });
  return { tasks: out, resolved, unknown };
}
