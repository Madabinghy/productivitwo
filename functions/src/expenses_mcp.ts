// Dépenses côté MCP (2026-11-03) — logique pure : lister les dépenses d'une
// période (avec leur id, pour pouvoir en retirer une) et préparer un retrait.
// Stockage `users/{uid}/data/meta.finances.expenses {<id>: {ymd, amount
// (centimes), envelopeId, note?, domainId?, items?, receiptId?, at?}}` et
// `finances.receipts {<id>: {...}}` (tickets conservés).

export type ExpenseDoc = {
  ymd: string;
  amount: number;
  envelopeId?: string;
  note?: string;
  domainId?: string;
  projectId?: string;
  items?: string[];
  receiptId?: string;
  at?: number;
};

const eur = (c: number) => `${(c / 100).toFixed(2).replace(".", ",")} €`;

/** Les dépenses d'une période, les plus récentes d'abord. */
export function expensesIn(expenses: Record<string, ExpenseDoc>, from: string, to: string): [string, ExpenseDoc][] {
  return Object.entries(expenses)
    .filter(([, x]) => x && typeof x.ymd === "string" && x.ymd >= from && x.ymd <= to)
    .sort((a, b) => b[1].ymd.localeCompare(a[1].ymd) || (b[1].at ?? 0) - (a[1].at ?? 0));
}

/** Une ligne lisible d'une dépense, avec son id. */
export function expenseLine(
  id: string,
  x: ExpenseDoc,
  names: { domain: (id: string) => string | undefined; envelope: (id: string) => string | undefined },
): string {
  const tags = [
    x.envelopeId ? names.envelope(x.envelopeId) ?? x.envelopeId : undefined,
    x.domainId ? names.domain(x.domainId) ?? "domaine retiré" : "sans domaine",
    x.receiptId ? `ticket ${x.receiptId}` : undefined,
  ].filter(Boolean);
  const items = x.items?.length ? ` — ${x.items.slice(0, 6).join(", ")}${x.items.length > 6 ? "…" : ""}` : "";
  return `• [${id}] ${x.ymd} · ${eur(x.amount)} · ${x.note || "sans note"} (${tags.join(" · ")})${items}`;
}

export type DeletePlan = {
  /** Ids des dépenses à retirer. */
  expenseIds: string[];
  /** Ids des tickets à retirer (toutes leurs dépenses partent avec eux). */
  receiptIds: string[];
  missing: string[];
  total: number;
};

/**
 * Ce qu'un retrait enlève : les dépenses nommées ; un ticket nommé emporte
 * toutes ses dépenses ; une dépense d'un ticket emporte le ticket entier si
 * [wholeReceipt] (sinon le ticket reste, sans cette part).
 */
export function planDelete(
  expenses: Record<string, ExpenseDoc>,
  receipts: Record<string, unknown>,
  ids: string[],
  receiptIdsIn: string[],
  wholeReceipt = false,
): DeletePlan {
  const exp = new Set<string>();
  const rec = new Set<string>();
  const missing: string[] = [];
  for (const id of ids) {
    const x = expenses[id];
    if (!x) {
      missing.push(id);
      continue;
    }
    exp.add(id);
    if (wholeReceipt && x.receiptId) rec.add(x.receiptId);
  }
  for (const r of receiptIdsIn) {
    if (receipts[r] || Object.values(expenses).some((x) => x?.receiptId === r)) rec.add(r);
    else missing.push(r);
  }
  for (const [id, x] of Object.entries(expenses)) {
    if (x?.receiptId && rec.has(x.receiptId)) exp.add(id);
  }
  const total = [...exp].reduce((s, id) => s + (expenses[id]?.amount ?? 0), 0);
  return { expenseIds: [...exp], receiptIds: [...rec].filter((r) => receipts[r] !== undefined), missing, total };
}

// ── Corriger un ticket ou une dépense (2026-11-03) ─────────────────────────

export type ReceiptPatch = { store?: string; place?: string; time?: string; ref?: string; date?: string };
export type ReceiptUpdatePlan = {
  /** Champs du ticket : valeur à poser, ou null = retirer. */
  receipt: Record<string, string | null>;
  /** Par dépense du ticket : champs à poser. */
  expenses: Record<string, { note?: string; ymd?: string }>;
  changes: string[];
  errors: string[];
};

const YMD = /^\d{4}-\d{2}-\d{2}$/;

/** La note d'une dépense de ticket suit le magasin (« Courses · K-Market »), sauf note écrite à la main. */
export function noteForStore(note: string | undefined, store: string | null): string | undefined {
  if (note && note !== "Courses" && !note.startsWith("Courses · ")) return undefined;
  return store ? `Courses · ${store}` : "Courses";
}

/**
 * Ce que change la correction d'un ticket conservé : magasin, lieu, heure,
 * référence, date (`""` = retirer le champ, sauf la date). Les prix, les
 * articles et les placards ne bougent pas ; les dépenses du ticket suivent
 * (note « Courses · magasin », date).
 */
export function planReceiptUpdate(
  receiptId: string,
  receipt: Record<string, unknown> | undefined,
  expenses: Record<string, ExpenseDoc>,
  patch: ReceiptPatch,
): ReceiptUpdatePlan {
  const out: ReceiptUpdatePlan = { receipt: {}, expenses: {}, changes: [], errors: [] };
  const mine = Object.entries(expenses).filter(([, x]) => x?.receiptId === receiptId);
  if (!receipt && !mine.length) {
    out.errors.push(`ticket ${receiptId} introuvable (list_expenses donne les ids de ticket).`);
    return out;
  }
  const set = (k: "store" | "place" | "ref", label: string) => {
    const v = patch[k];
    if (v === undefined) return;
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
    } else if (/^\d{1,2}:\d{2}$/.test(t)) {
      out.receipt.time = t.padStart(5, "0");
      out.changes.push(`heure : ${out.receipt.time}`);
    } else out.errors.push(`heure « ${patch.time} » : attendu HH:MM.`);
  }
  if (patch.date !== undefined) {
    if (YMD.test(patch.date)) {
      out.receipt.ymd = patch.date;
      out.changes.push(`date : ${patch.date}`);
    } else out.errors.push(`date « ${patch.date} » : attendu YYYY-MM-DD.`);
  }
  for (const [id, x] of mine) {
    const p: { note?: string; ymd?: string } = {};
    if ("store" in out.receipt) {
      const n = noteForStore(x.note, out.receipt.store);
      if (n !== undefined && n !== x.note) p.note = n;
    }
    if (out.receipt.ymd && out.receipt.ymd !== x.ymd) p.ymd = out.receipt.ymd as string;
    if (Object.keys(p).length) out.expenses[id] = p;
  }
  return out;
}

export type ExpensePatch = { note?: string; amount?: number; envelopeId?: string; domainId?: string; projectId?: string; date?: string };

/**
 * Une dépense corrigée : note (`""` = retirer), montant en centimes, enveloppe,
 * domaine / projet (`""` = retirer), date. Le montant d'une part de ticket ne
 * se change pas (le ticket ne tomberait plus juste).
 */
export function planExpenseUpdate(
  x: ExpenseDoc | undefined,
  patch: ExpensePatch,
): { set: Record<string, unknown>; remove: string[]; changes: string[]; errors: string[] } {
  const out = { set: {} as Record<string, unknown>, remove: [] as string[], changes: [] as string[], errors: [] as string[] };
  if (!x) {
    out.errors.push("dépense introuvable (list_expenses donne les ids).");
    return out;
  }
  const opt = (k: "note" | "domainId" | "projectId", label: string, show = (v: string) => v) => {
    const v = patch[k];
    if (v === undefined) return;
    const t = String(v).trim();
    if (t) {
      out.set[k] = t;
      out.changes.push(`${label} : ${show(t)}`);
    } else {
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
    if (x.receiptId) out.errors.push("le montant d'une part de ticket ne se change pas : retire le ticket (delete_expenses) et réenregistre-le.");
    else if (!Number.isFinite(c) || c <= 0) out.errors.push("montant invalide (centimes > 0).");
    else {
      out.set.amount = c;
      out.changes.push(`montant : ${eur(c)}`);
    }
  }
  if (patch.date !== undefined) {
    if (!YMD.test(patch.date)) out.errors.push(`date « ${patch.date} » : attendu YYYY-MM-DD.`);
    else if (x.receiptId) out.errors.push("la date d'une part de ticket se change sur le ticket (update_receipt).");
    else {
      out.set.ymd = patch.date;
      out.changes.push(`date : ${patch.date}`);
    }
  }
  return out;
}
