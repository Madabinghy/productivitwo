"use strict";
// Modules (lot 5, 2026-11-16) : le coach voit les modules allumés de son coaché (jamais Liberté) et peut en
// proposer un. Aligné sur lib/utils/modules.dart (clés) et lib/utils/module_journey.dart (pending).
Object.defineProperty(exports, "__esModule", { value: true });
exports.PRIVATE_MODULES = exports.MODULE_NAMES = void 0;
exports.coachModuleView = coachModuleView;
exports.planCoachProposal = planCoachProposal;
exports.MODULE_NAMES = {
    modes: "Modes d'action",
    planning: "Planification",
    game: "Jeu et badges",
    seasons: "Saisons",
    sleep: "Sommeil",
    sport: "Sport",
    kitchen: "Cuisine",
    finances: "Finances",
    freedom: "Liberté",
    analysis: "Analyse",
    trainer: "Formateur",
    assistant: "Assistant",
};
/** Privé : le coach ne le voit jamais et ne peut pas le proposer. */
exports.PRIVATE_MODULES = new Set(["freedom"]);
/** Les modules allumés, vus par le coach. Absent = compte d'avant les modules, tout allumé. */
function coachModuleView(raw) {
    const keys = Object.keys(exports.MODULE_NAMES).filter((k) => !exports.PRIVATE_MODULES.has(k));
    const m = (raw && typeof raw === "object" ? raw : {});
    const list = Array.isArray(m.on) ? m.on.map(String) : null;
    const on = list === null ? keys : keys.filter((k) => list.includes(k));
    const pending = typeof m.pending === "string" && !exports.PRIVATE_MODULES.has(m.pending) ? m.pending : null;
    return { on, offered: keys.filter((k) => !on.includes(k)), pending };
}
/** Le correctif à écrire dans `data/meta.modules` pour une proposition du coach, ou une erreur. */
function planCoachProposal(raw, key, coachName, today) {
    if (!(key in exports.MODULE_NAMES))
        return { error: `module inconnu : ${key}` };
    if (exports.PRIVATE_MODULES.has(key))
        return { error: "ce module est privé" };
    const view = coachModuleView(raw);
    if (view.on.includes(key))
        return { error: "déjà allumé" };
    return { patch: { pending: key, pendingBy: "coach", pendingCoach: coachName, lastProposed: today } };
}
//# sourceMappingURL=modules_coach.js.map