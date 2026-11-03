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
exports.planReceipt = planReceipt;
exports.mondayOfYmd = mondayOfYmd;
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
    var _a, _b, _c, _d, _e;
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
    const aisle = (_e = input.aisle) !== null && _e !== void 0 ? _e : m.aisle;
    if (aisle)
        out.aisle = aisle;
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
            x.aisle,
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
function apportionInt(total, weights) {
    const sum = weights.reduce((a, b) => a + b, 0);
    if (!weights.length)
        return [];
    if (sum <= 0)
        return apportionInt(total, weights.map(() => 1));
    const raw = weights.map((w) => (total * w) / sum);
    const out = raw.map((r) => Math.floor(r));
    let left = total - out.reduce((a, b) => a + b, 0);
    const order = raw.map((r, i) => [r - out[i], i]).sort((a, b) => b[0] - a[0]).map(([, i]) => i);
    for (let k = 0; left > 0; k = (k + 1) % order.length, left--)
        out[order[k]]++;
    return out;
}
/**
 * Le ticket réparti par (domaine, projet) : chaque ligne garde son prix ; si
 * le total du ticket diffère de la somme des lignes (remise, arrondi), l'écart
 * est réparti au prorata. Domaine d'une ligne : celui donné, sinon celui
 * retenu pour l'article de la liste ou pour le mot, sinon aucun.
 */
function planReceipt(lines, totalEuros, ctx) {
    const warnings = [];
    const cents = lines.map((l) => Math.max(0, Math.round((Number(l.price) || 0) * 100)));
    const sumLines = cents.reduce((a, b) => a + b, 0);
    const total = totalEuros != null && totalEuros > 0 ? Math.round(totalEuros * 100) : sumLines;
    if (total !== sumLines) {
        warnings.push(`Total du ticket ${(total / 100).toFixed(2)} € ≠ somme des lignes ${(sumLines / 100).toFixed(2)} € : l'écart est réparti au prorata.`);
    }
    const paid = total === sumLines ? cents : apportionInt(total, cents);
    const removeItemIds = [];
    const menuKeys = [];
    const groups = new Map();
    const prices = {};
    const bought = {};
    const kept = [];
    lines.forEach((l, i) => {
        var _a, _b, _c, _d, _e, _f, _g, _h, _j, _k;
        const listMatch = l.listLabel ? findItems(ctx.items, l.listLabel).find(([, x]) => fold(x.label) === fold(l.listLabel)) : undefined;
        const memKey = groceryKey(l.listLabel || l.label);
        const mem = (_c = (_b = (_a = ctx.memory[memKey]) !== null && _a !== void 0 ? _a : (l.name ? ctx.memory[groceryKey(l.name)] : undefined)) !== null && _b !== void 0 ? _b : ctx.memory[groceryKey(l.label)]) !== null && _c !== void 0 ? _c : {};
        let domainId = l.domain ? resolveDomain(l.domain, ctx.domains) : null;
        if (l.domain && !domainId)
            warnings.push(`Domaine introuvable pour « ${l.label} » : « ${l.domain} ».`);
        domainId = (_e = (_d = domainId !== null && domainId !== void 0 ? domainId : listMatch === null || listMatch === void 0 ? void 0 : listMatch[1].domainId) !== null && _d !== void 0 ? _d : mem.domainId) !== null && _e !== void 0 ? _e : null;
        const projectId = (_h = (_g = (_f = l.projectId) !== null && _f !== void 0 ? _f : listMatch === null || listMatch === void 0 ? void 0 : listMatch[1].projectId) !== null && _g !== void 0 ? _g : mem.projectId) !== null && _h !== void 0 ? _h : null;
        if (listMatch)
            removeItemIds.push(listMatch[0]);
        else if (l.listLabel)
            menuKeys.push(l.listLabel.trim().toLowerCase());
        const k = `${domainId !== null && domainId !== void 0 ? domainId : ""}|${projectId !== null && projectId !== void 0 ? projectId : ""}`;
        const g = (_j = groups.get(k)) !== null && _j !== void 0 ? _j : { domainId, projectId, amount: 0, labels: [], byAisle: {} };
        g.amount += paid[i];
        const product = (l.listLabel || l.name || l.label).trim();
        g.labels.push(product);
        const aisle = ctx.aisleOf ? ctx.aisleOf(product, l.aisle) : undefined;
        if (aisle) {
            g.byAisle[aisle] = ((_k = g.byAisle[aisle]) !== null && _k !== void 0 ? _k : 0) + paid[i];
            bought[groceryKey(product)] = { label: product, aisle };
        }
        groups.set(k, g);
        kept.push(Object.assign(Object.assign(Object.assign(Object.assign(Object.assign({ label: l.label.trim() }, (product !== l.label.trim() ? { name: product } : {})), { price: paid[i] }), (domainId ? { domainId } : {})), (projectId ? { projectId } : {})), (aisle ? { aisle } : {})));
        prices[groceryKey(product)] = Object.assign(Object.assign(Object.assign({ price: paid[i] }, (domainId ? { domainId } : {})), (projectId ? { projectId } : {})), (aisle ? { aisle } : {}));
    });
    const shares = [...groups.values()].sort((a, b) => b.amount - a.amount);
    if (shares.some((s) => s.domainId == null))
        warnings.push("Des lignes n'ont pas de domaine de vie : elles iront dans « Sans domaine ».");
    return { total, shares, prices, bought, lines: kept, removeItemIds: [...new Set(removeItemIds)], menuKeys: [...new Set(menuKeys)], warnings };
}
/** Le lundi (YYYY-MM-DD) de la semaine d'un jour. */
function mondayOfYmd(ymd) {
    const d = new Date(`${ymd}T12:00:00Z`);
    const wd = (d.getUTCDay() + 6) % 7;
    d.setUTCDate(d.getUTCDate() - wd);
    return d.toISOString().slice(0, 10);
}
//# sourceMappingURL=groceries.js.map