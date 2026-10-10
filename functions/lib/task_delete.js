"use strict";
// Suppression d'une tâche de projet (outil MCP delete_task) — logique pure.
// Même effet que « Supprimer la tâche » de l'app : la tâche (et ses actions)
// quitte le tableau `tasks` du projet. Les blocs du programme encore À VENIR qui
// la visent sont libérés (status "deleted") ; le vécu (fait, passé) ne bouge pas.
Object.defineProperty(exports, "__esModule", { value: true });
exports.removeTask = removeTask;
exports.freeTaskBlocks = freeTaskBlocks;
function removeTask(tasks, taskId) {
    var _a, _b;
    const removed = (_a = tasks.find((t) => t.id === taskId)) !== null && _a !== void 0 ? _a : null;
    const role = removed && removed.interventionId && removed.interventionRole !== "extra"
        ? String((_b = removed.interventionRole) !== null && _b !== void 0 ? _b : "séance")
        : null;
    return {
        remaining: tasks.filter((t) => t.id !== taskId),
        removed,
        interventionRole: role,
    };
}
function toMin(hm) {
    const m = /^(\d{1,2}):(\d{2})$/.exec(String(hm !== null && hm !== void 0 ? hm : ""));
    return m ? Number(m[1]) * 60 + Number(m[2]) : 0;
}
/** Libère les blocs à venir d'une tâche dans le programme d'un jour.
 *  [nowMin] = minute vécue si [isToday], ignorée sinon (tout le jour est à venir). */
function freeTaskBlocks(blocks, projectId, taskId, opts) {
    const freed = [];
    const out = blocks.map((b) => {
        var _a;
        if (b.projectId !== projectId || b.taskId !== taskId)
            return b;
        if (((_a = b.status) !== null && _a !== void 0 ? _a : "pending") !== "pending")
            return b;
        if (opts.isToday && toMin(b.startTime) < opts.nowMin)
            return b;
        const nb = Object.assign(Object.assign({}, b), { status: "deleted" });
        freed.push(nb);
        return nb;
    });
    return { blocks: out, freed };
}
//# sourceMappingURL=task_delete.js.map