"use strict";
// Dépenses côté MCP (2026-11-03) — logique pure : lister les dépenses d'une
// période (avec leur id, pour pouvoir en retirer une) et préparer un retrait.
// Stockage `users/{uid}/data/meta.finances.expenses {<id>: {ymd, amount
// (centimes), envelopeId, note?, domainId?, items?, receiptId?, at?}}` et
// `finances.receipts {<id>: {...}}` (tickets conservés).
Object.defineProperty(exports, "__esModule", { value: true });
exports.expensesIn = expensesIn;
exports.expenseLine = expenseLine;
exports.planDelete = planDelete;
const eur = (c) => `${(c / 100).toFixed(2).replace(".", ",")} €`;
/** Les dépenses d'une période, les plus récentes d'abord. */
function expensesIn(expenses, from, to) {
    return Object.entries(expenses)
        .filter(([, x]) => x && typeof x.ymd === "string" && x.ymd >= from && x.ymd <= to)
        .sort((a, b) => { var _a, _b; return b[1].ymd.localeCompare(a[1].ymd) || ((_a = b[1].at) !== null && _a !== void 0 ? _a : 0) - ((_b = a[1].at) !== null && _b !== void 0 ? _b : 0); });
}
/** Une ligne lisible d'une dépense, avec son id. */
function expenseLine(id, x, names) {
    var _a, _b, _c;
    const tags = [
        x.envelopeId ? (_a = names.envelope(x.envelopeId)) !== null && _a !== void 0 ? _a : x.envelopeId : undefined,
        x.domainId ? (_b = names.domain(x.domainId)) !== null && _b !== void 0 ? _b : "domaine retiré" : "sans domaine",
        x.receiptId ? `ticket ${x.receiptId}` : undefined,
    ].filter(Boolean);
    const items = ((_c = x.items) === null || _c === void 0 ? void 0 : _c.length) ? ` — ${x.items.slice(0, 6).join(", ")}${x.items.length > 6 ? "…" : ""}` : "";
    return `• [${id}] ${x.ymd} · ${eur(x.amount)} · ${x.note || "sans note"} (${tags.join(" · ")})${items}`;
}
/**
 * Ce qu'un retrait enlève : les dépenses nommées ; un ticket nommé emporte
 * toutes ses dépenses ; une dépense d'un ticket emporte le ticket entier si
 * [wholeReceipt] (sinon le ticket reste, sans cette part).
 */
function planDelete(expenses, receipts, ids, receiptIdsIn, wholeReceipt = false) {
    const exp = new Set();
    const rec = new Set();
    const missing = [];
    for (const id of ids) {
        const x = expenses[id];
        if (!x) {
            missing.push(id);
            continue;
        }
        exp.add(id);
        if (wholeReceipt && x.receiptId)
            rec.add(x.receiptId);
    }
    for (const r of receiptIdsIn) {
        if (receipts[r] || Object.values(expenses).some((x) => (x === null || x === void 0 ? void 0 : x.receiptId) === r))
            rec.add(r);
        else
            missing.push(r);
    }
    for (const [id, x] of Object.entries(expenses)) {
        if ((x === null || x === void 0 ? void 0 : x.receiptId) && rec.has(x.receiptId))
            exp.add(id);
    }
    const total = [...exp].reduce((s, id) => { var _a, _b; return s + ((_b = (_a = expenses[id]) === null || _a === void 0 ? void 0 : _a.amount) !== null && _b !== void 0 ? _b : 0); }, 0);
    return { expenseIds: [...exp], receiptIds: [...rec].filter((r) => receipts[r] !== undefined), missing, total };
}
//# sourceMappingURL=expenses_mcp.js.map