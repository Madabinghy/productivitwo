"use strict";
// Plusieurs cibles dans un même bloc (2026-11-16) : `projectId` / `taskId` /
// `actionId` restent la cible principale ; les suivantes vivent dans
// `extraTargets`, dans l'ordre. Aligné sur `BlockTarget` de l'app
// (`lib/models/schedule.dart`, `lib/utils/block_stack.dart`).
Object.defineProperty(exports, "__esModule", { value: true });
exports.MAX_BLOCK_TARGETS = void 0;
exports.normalizeExtraTargets = normalizeExtraTargets;
exports.extraTargetLinks = extraTargetLinks;
/** Au-delà de 6 cibles (principale comprise), l'app n'en accepte plus. */
exports.MAX_BLOCK_TARGETS = 6;
const str = (v) => (typeof v === "string" && v.trim() ? v.trim() : undefined);
/**
 * Les cibles suivantes d'un bloc, nettoyées : sans projet principal il n'y en
 * a pas ; une cible déjà portée (même projet et même tâche) n'est gardée
 * qu'une fois ; jamais plus de MAX_BLOCK_TARGETS avec la principale.
 */
function normalizeExtraTargets(input, primary) {
    var _a;
    if (!primary.projectId || !Array.isArray(input))
        return [];
    const seen = new Set([`${primary.projectId}|${(_a = primary.taskId) !== null && _a !== void 0 ? _a : ""}`]);
    const out = [];
    for (const raw of input) {
        if (out.length >= exports.MAX_BLOCK_TARGETS - 1)
            break;
        if (!raw || typeof raw !== "object")
            continue;
        const r = raw;
        const projectId = str(r.projectId);
        if (!projectId)
            continue;
        const taskId = str(r.taskId);
        const actionId = taskId ? str(r.actionId) : undefined;
        const key = `${projectId}|${taskId !== null && taskId !== void 0 ? taskId : ""}`;
        if (seen.has(key))
            continue;
        seen.add(key);
        out.push(Object.assign(Object.assign({ projectId }, (taskId ? { taskId } : {})), (actionId ? { actionId } : {})));
    }
    return out;
}
/** « aussi projet:p2 tâche:t9 » pour la ligne d'un bloc lu par Claude. */
function extraTargetLinks(extra) {
    if (!Array.isArray(extra))
        return [];
    return extra
        .filter((t) => !!t && typeof t === "object" && typeof t.projectId === "string")
        .map((t) => `aussi projet:${t.projectId}${t.taskId ? ` tâche:${t.taskId}` : ""}${t.actionId ? ` action:${t.actionId}` : ""}`);
}
//# sourceMappingURL=block_targets.js.map