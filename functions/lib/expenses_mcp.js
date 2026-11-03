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
exports.noteForStore = noteForStore;
exports.planReceiptUpdate = planReceiptUpdate;
exports.planExpenseUpdate = planExpenseUpdate;
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
const YMD = /^\d{4}-\d{2}-\d{2}$/;
/** La note d'une dépense de ticket suit le magasin (« Courses · K-Market »), sauf note écrite à la main. */
function noteForStore(note, store) {
    if (note && note !== "Courses" && !note.startsWith("Courses · "))
        return undefined;
    return store ? `Courses · ${store}` : "Courses";
}
/**
 * Ce que change la correction d'un ticket conservé : magasin, lieu, heure,
 * référence, date (`""` = retirer le champ, sauf la date). Les prix, les
 * articles et les placards ne bougent pas ; les dépenses du ticket suivent
 * (note « Courses · magasin », date).
 */
function planReceiptUpdate(receiptId, receipt, expenses, patch) {
    const out = { receipt: {}, expenses: {}, changes: [], errors: [] };
    const mine = Object.entries(expenses).filter(([, x]) => (x === null || x === void 0 ? void 0 : x.receiptId) === receiptId);
    if (!receipt && !mine.length) {
        out.errors.push(`ticket ${receiptId} introuvable (list_expenses donne les ids de ticket).`);
        return out;
    }
    const set = (k, label) => {
        const v = patch[k];
        if (v === undefined)
            return;
        const t = String(v).trim();
        out.receipt[k] = t || null;
        out.changes.push(t ? `${label} : ${t}` : `${label} retiré`);
    };
    set("store", "magasin");
    set("place", "lieu");
    set("ref", "référence");
    if (patch.time !== undefined) {
        const t = patch.time.trim();
        if (!t) {
            out.receipt.time = null;
            out.changes.push("heure retirée");
        }
        else if (/^\d{1,2}:\d{2}$/.test(t)) {
            out.receipt.time = t.padStart(5, "0");
            out.changes.push(`heure : ${out.receipt.time}`);
        }
        else
            out.errors.push(`heure « ${patch.time} » : attendu HH:MM.`);
    }
    if (patch.date !== undefined) {
        if (YMD.test(patch.date)) {
            out.receipt.ymd = patch.date;
            out.changes.push(`date : ${patch.date}`);
        }
        else
            out.errors.push(`date « ${patch.date} » : attendu YYYY-MM-DD.`);
    }
    for (const [id, x] of mine) {
        const p = {};
        if ("store" in out.receipt) {
            const n = noteForStore(x.note, out.receipt.store);
            if (n !== undefined && n !== x.note)
                p.note = n;
        }
        if (out.receipt.ymd && out.receipt.ymd !== x.ymd)
            p.ymd = out.receipt.ymd;
        if (Object.keys(p).length)
            out.expenses[id] = p;
    }
    return out;
}
/**
 * Une dépense corrigée : note (`""` = retirer), montant en centimes, enveloppe,
 * domaine / projet (`""` = retirer), date. Le montant d'une part de ticket ne
 * se change pas (le ticket ne tomberait plus juste).
 */
function planExpenseUpdate(x, patch) {
    const out = { set: {}, remove: [], changes: [], errors: [] };
    if (!x) {
        out.errors.push("dépense introuvable (list_expenses donne les ids).");
        return out;
    }
    const opt = (k, label, show = (v) => v) => {
        const v = patch[k];
        if (v === undefined)
            return;
        const t = String(v).trim();
        if (t) {
            out.set[k] = t;
            out.changes.push(`${label} : ${show(t)}`);
        }
        else {
            out.remove.push(k);
            out.changes.push(`${label} retiré`);
        }
    };
    opt("note", "note");
    opt("domainId", "domaine");
    opt("projectId", "projet");
    if (patch.envelopeId !== undefined && patch.envelopeId.trim()) {
        out.set.envelopeId = patch.envelopeId.trim();
        out.changes.push(`enveloppe : ${patch.envelopeId.trim()}`);
    }
    if (patch.amount !== undefined) {
        const c = Math.round(Number(patch.amount));
        if (x.receiptId)
            out.errors.push("le montant d'une part de ticket ne se change pas : retire le ticket (delete_expenses) et réenregistre-le.");
        else if (!Number.isFinite(c) || c <= 0)
            out.errors.push("montant invalide (centimes > 0).");
        else {
            out.set.amount = c;
            out.changes.push(`montant : ${eur(c)}`);
        }
    }
    if (patch.date !== undefined) {
        if (!YMD.test(patch.date))
            out.errors.push(`date « ${patch.date} » : attendu YYYY-MM-DD.`);
        else if (x.receiptId)
            out.errors.push("la date d'une part de ticket se change sur le ticket (update_receipt).");
        else {
            out.set.ymd = patch.date;
            out.changes.push(`date : ${patch.date}`);
        }
    }
    return out;
}
//# sourceMappingURL=expenses_mcp.js.map