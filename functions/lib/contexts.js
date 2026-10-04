"use strict";
/** Contextes GTD (@maison, @bureau…) — logique pure, testée.
 *  Les défauts sont ceux de l'app (`kDefaultGtdContexts`) ; les personnalisés
 *  vivent dans `users/{uid}/data/meta.customContexts`. Une action porte
 *  `contexts` (multi, référence) et `context` (mono legacy = contexts[0]). */
Object.defineProperty(exports, "__esModule", { value: true });
exports.DEFAULT_GTD_CONTEXTS = void 0;
exports.normalizeContext = normalizeContext;
exports.contextsOf = contextsOf;
exports.renameContextInActions = renameContextInActions;
exports.removeContextFromActions = removeContextFromActions;
exports.countContextUsage = countContextUsage;
exports.DEFAULT_GTD_CONTEXTS = [
    "@maison", "@bureau", "@ordinateur", "@courses", "@extérieur", "@téléphone",
];
/** « atelier » → « @atelier » ; vide ou « @ » seul → null. */
function normalizeContext(raw) {
    if (typeof raw !== "string")
        return null;
    const t = raw.trim().replace(/\s+/g, " ");
    if (!t)
        return null;
    const c = t.startsWith("@") ? t : `@${t}`;
    return c.length > 1 ? c : null;
}
/** Contextes portés par une action : `contexts` ∪ `context` (legacy), ordre conservé. */
function contextsOf(a) {
    const out = [];
    const multi = Array.isArray(a.contexts) ? a.contexts : [];
    for (const c of multi)
        if (typeof c === "string" && c && !out.includes(c))
            out.push(c);
    const legacy = typeof a.context === "string" ? a.context : "";
    if (legacy && !out.includes(legacy))
        out.push(legacy);
    return out;
}
function withContexts(a, contexts) {
    return Object.assign(Object.assign({}, a), { contexts, context: contexts.length > 0 ? contexts[0] : null });
}
/** Remplace [from] par [to] sur chaque action qui le porte. `changed` = nb d'actions touchées. */
function renameContextInActions(actions, from, to) {
    let changed = 0;
    const out = actions.map((a) => {
        const cur = contextsOf(a);
        if (!cur.includes(from))
            return a;
        changed++;
        const next = [];
        for (const c of cur) {
            const v = c === from ? to : c;
            if (!next.includes(v))
                next.push(v);
        }
        return withContexts(a, next);
    });
    return { actions: out, changed };
}
/** Retire [ctx] de chaque action qui le porte. */
function removeContextFromActions(actions, ctx) {
    let changed = 0;
    const out = actions.map((a) => {
        const cur = contextsOf(a);
        if (!cur.includes(ctx))
            return a;
        changed++;
        return withContexts(a, cur.filter((c) => c !== ctx));
    });
    return { actions: out, changed };
}
/** Usage de chaque contexte sur un lot d'actions (ouvertes / faites). */
function countContextUsage(actions, into = new Map()) {
    var _a;
    for (const a of actions) {
        const done = a.done === true;
        for (const c of contextsOf(a)) {
            const u = (_a = into.get(c)) !== null && _a !== void 0 ? _a : { open: 0, done: 0 };
            if (done)
                u.done++;
            else
                u.open++;
            into.set(c, u);
        }
    }
    return into;
}
//# sourceMappingURL=contexts.js.map