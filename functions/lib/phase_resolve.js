"use strict";
// B1 (brief 2026-10) : push_gantt créait les tâches « Sans phase » même quand
// groupLabel reprenait le libellé d'une phase — l'IA ne connaît pas les ids
// des phases qu'elle vient d'écrire. Résolution par libellé, insensible à la
// casse et aux accents ; un phaseId qui porte un libellé est aussi résolu.
Object.defineProperty(exports, "__esModule", { value: true });
exports.resolvePhaseIds = resolvePhaseIds;
const norm = (s) => String(s !== null && s !== void 0 ? s : "")
    .toLowerCase()
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .replace(/[^\p{L}\p{N}]+/gu, " ")
    .trim();
/**
 * Pose `phaseId` sur chaque tâche : id déjà valide → inchangé ; sinon
 * phaseId ou groupLabel égal au libellé d'une phase → id de cette phase ;
 * sinon, projet mono-phase sans indication → cette phase unique.
 */
function resolvePhaseIds(phases, tasks) {
    const ids = new Set(phases.map((p) => String(p.id)));
    const byLabel = new Map();
    for (const p of phases) {
        const k = norm(p.label);
        if (k && !byLabel.has(k))
            byLabel.set(k, String(p.id));
    }
    const only = phases.length === 1 ? String(phases[0].id) : null;
    let resolved = 0;
    const unknown = [];
    const out = tasks.map((t) => {
        const pid = typeof t.phaseId === "string" && t.phaseId.trim() ? t.phaseId : null;
        if (pid && ids.has(pid))
            return t;
        const target = (pid && byLabel.get(norm(pid))) ||
            (typeof t.groupLabel === "string" && byLabel.get(norm(t.groupLabel))) ||
            (!pid && !t.groupLabel ? only : null);
        if (target) {
            resolved++;
            return Object.assign(Object.assign({}, t), { phaseId: target });
        }
        if (pid)
            unknown.push(pid);
        return t;
    });
    return { tasks: out, resolved, unknown };
}
//# sourceMappingURL=phase_resolve.js.map