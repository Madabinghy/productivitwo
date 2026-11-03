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
