"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.applyActionPatch = applyActionPatch;
/** Modification d'une action existante (projet ou activité) — logique pure.
 *  Champs : titre, contextes (remplacer / ajouter / retirer), estimation,
 *  activité liée, état fait. Renvoie l'action patchée et la liste des
 *  changements en clair (pour le retour outil). */
const contexts_1 = require("./contexts");
function cleanList(raw) {
    if (!Array.isArray(raw))
        return [];
    const out = [];
    for (const r of raw) {
        const c = (0, contexts_1.normalizeContext)(r);
        if (c && !out.includes(c))
            out.push(c);
    }
    return out;
}
function applyActionPatch(action, patch, nowIso = new Date().toISOString()) {
    var _a;
    const changes = [];
    let a = Object.assign({}, action);
    if (patch.title !== undefined) {
        const t = patch.title.trim().replace(/\s+/g, " ");
        if (t && t !== a.title) {
            changes.push(`titre « ${(_a = a.title) !== null && _a !== void 0 ? _a : ""} » → « ${t} »`);
            a = Object.assign(Object.assign({}, a), { title: t });
        }
    }
    if (patch.contexts !== undefined || patch.addContexts !== undefined || patch.removeContexts !== undefined) {
        const before = (0, contexts_1.contextsOf)(a);
        let next = patch.contexts !== undefined ? cleanList(patch.contexts) : [...before];
        for (const c of cleanList(patch.addContexts))
            if (!next.includes(c))
                next.push(c);
        const rm = cleanList(patch.removeContexts);
        if (rm.length)
            next = next.filter((c) => !rm.includes(c));
        if (next.join("\u0000") !== before.join("\u0000")) {
            changes.push(`contextes ${before.length ? before.join(" ") : "(aucun)"} → ${next.length ? next.join(" ") : "(aucun)"}`);
            a = Object.assign(Object.assign({}, a), { contexts: next, context: next.length ? next[0] : null });
        }
    }
    if (patch.estimatedMin !== undefined) {
        const v = patch.estimatedMin;
        if (v !== null && (!Number.isFinite(v) || v < 0)) {
            changes.push("estimation ignorée (minutes ≥ 0 attendues)");
        }
        else {
            const n = v === null ? null : Math.round(v);
            const cur = typeof a.estimatedMin === "number" ? a.estimatedMin : null;
            if (n !== cur) {
                changes.push(`estimation ${cur === null ? "—" : `${cur} min`} → ${n === null ? "—" : `${n} min`}`);
                a = Object.assign(Object.assign({}, a), { estimatedMin: n });
            }
        }
    }
    if (patch.linkedActivityId !== undefined) {
        const v = patch.linkedActivityId && patch.linkedActivityId.trim() ? patch.linkedActivityId.trim() : null;
        const cur = typeof a.linkedActivityId === "string" && a.linkedActivityId ? a.linkedActivityId : null;
        if (v !== cur) {
            changes.push(v ? `activité liée → ${v}` : "activité déliée");
            a = Object.assign(Object.assign({}, a), { linkedActivityId: v });
        }
    }
    if (patch.done !== undefined && patch.done !== (a.done === true)) {
        changes.push(patch.done ? "marquée faite" : "rouverte");
        a = Object.assign(Object.assign({}, a), { done: patch.done, doneAt: patch.done ? nowIso : null });
        if (patch.done && Array.isArray(a.checklist)) {
            a = Object.assign(Object.assign({}, a), { checklist: a.checklist.map((c) => c.done === true ? c : Object.assign(Object.assign({}, c), { done: true, doneAt: nowIso })) });
        }
    }
    return { action: a, changes };
}
//# sourceMappingURL=action_patch.js.map