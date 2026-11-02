"use strict";
// Courses générales (2026-11-02) — logique pure côté serveur, alignée sur
// `lib/utils/groceries.dart` : la liste vit dans `users/{uid}/data/meta`
// `groceries {items: {<id>: {label, qty?, domainId?, projectId?, store,
// source?, inBasket?}}, memory: {<mot>: {domainId?, projectId?, store?, price?}}}`.
Object.defineProperty(exports, "__esModule", { value: true });
exports.MENU_STORE = void 0;
exports.groceryKey = groceryKey;
exports.fold = fold;
exports.resolveDomain = resolveDomain;
exports.existingItem = existingItem;
exports.newGroceryItem = newGroceryItem;
exports.findItems = findItems;
exports.groceriesText = groceriesText;
exports.MENU_STORE = "Supermarché";
/** Même clé que l'app (`normLabel`) : minuscules, espaces resserrés. */
function groceryKey(s) {
    return s.trim().toLowerCase().replace(/\s+/g, " ");
}
/** Pour chercher : sans accents. */
function fold(s) {
    return s.toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "").trim();
}
/** Un domaine par id ou par nom (sans accents) ; null si introuvable. */
function resolveDomain(input, domains) {
    var _a, _b, _c, _d;
    if (!input)
        return null;
    const byId = domains.find((d) => d.id === input);
    if (byId)
        return byId.id;
    const f = fold(input);
    return (_d = (_b = (_a = domains.find((d) => fold(d.name) === f)) === null || _a === void 0 ? void 0 : _a.id) !== null && _b !== void 0 ? _b : (_c = domains.find((d) => fold(d.name).includes(f))) === null || _c === void 0 ? void 0 : _c.id) !== null && _d !== void 0 ? _d : null;
}
/** Le mot déjà sur la liste (hors panier), sinon null. */
function existingItem(items, label) {
    const k = groceryKey(label);
    for (const [id, x] of Object.entries(items)) {
        if (groceryKey(x.label) === k && x.inBasket !== true)
            return [id, x];
    }
    return null;
}
/** La ligne à écrire : domaine / projet / endroit donnés, sinon retenus pour ce mot. */
function newGroceryItem(input, memory) {
    var _a, _b, _c, _d;
    const m = (_a = memory[groceryKey(input.label)]) !== null && _a !== void 0 ? _a : {};
    const out = {
        label: input.label.trim(),
        store: input.store || m.store || exports.MENU_STORE,
        source: "claude",
    };
    const qty = ((_b = input.qty) !== null && _b !== void 0 ? _b : "").trim();
    if (qty)
        out.qty = qty;
    const domainId = (_c = input.domainId) !== null && _c !== void 0 ? _c : m.domainId;
    if (domainId)
        out.domainId = domainId;
    const projectId = (_d = input.projectId) !== null && _d !== void 0 ? _d : m.projectId;
    if (projectId)
        out.projectId = projectId;
    return out;
}
/** Candidats pour un libellé (exact, sinon fragment ; sans accents). */
function findItems(items, needle) {
    const n = fold(needle);
    if (!n)
        return [];
    const all = Object.entries(items);
    const exact = all.filter(([, x]) => fold(x.label) === n);
    return exact.length ? exact : all.filter(([, x]) => fold(x.label).includes(n));
}
/** La liste en texte, par endroit, avec le domaine et le projet. */
function groceriesText(items, domainName, projectTitle) {
    const all = Object.values(items);
    if (!all.length)
        return "Liste de courses vide (les ingrédients du menu de la semaine s'y ajoutent dans l'app).";
    const toBuy = all.filter((x) => x.inBasket !== true);
    const basket = all.filter((x) => x.inBasket === true);
    const byStore = new Map();
    for (const x of toBuy) {
        const s = x.store || exports.MENU_STORE;
        if (!byStore.has(s))
            byStore.set(s, []);
        byStore.get(s).push(x);
    }
    const line = (x, mark) => {
        const tags = [
            x.domainId ? domainName(x.domainId) : undefined,
            x.projectId ? projectTitle(x.projectId) : undefined,
        ].filter(Boolean);
        return `${mark} ${x.label}${x.qty ? ` ${x.qty}` : ""}${tags.length ? ` (${tags.join(" · ")})` : ""}`;
    };
    const parts = [`Liste de courses : ${toBuy.length} à prendre${basket.length ? `, ${basket.length} dans le panier` : ""}.`];
    for (const [store, list] of byStore) {
        parts.push(`\n${store.toUpperCase()}`);
        for (const x of list.sort((a, b) => a.label.localeCompare(b.label, "fr")))
            parts.push(line(x, "☐"));
    }
    if (basket.length) {
        parts.push("\nDANS LE PANIER");
        for (const x of basket)
            parts.push(line(x, "☑"));
    }
    parts.push("\n(Les ingrédients du menu de la semaine s'ajoutent tout seuls dans l'app ; ils ne sont pas listés ici.)");
    return parts.join("\n");
}
//# sourceMappingURL=groceries.js.map