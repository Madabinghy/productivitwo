// Courses générales (2026-11-02) — logique pure côté serveur, alignée sur
// `lib/utils/groceries.dart` : la liste vit dans `users/{uid}/data/meta`
// `groceries {items: {<id>: {label, qty?, domainId?, projectId?, store,
// source?, inBasket?}}, memory: {<mot>: {domainId?, projectId?, store?, price?}}}`.

export type GroceryItemDoc = {
  label: string;
  qty?: string;
  domainId?: string;
  projectId?: string;
  store?: string;
  source?: string;
  inBasket?: boolean;
};

export type GroceryMemoryDoc = { domainId?: string; projectId?: string; store?: string; price?: number };

export const MENU_STORE = "Supermarché";

/** Même clé que l'app (`normLabel`) : minuscules, espaces resserrés. */
export function groceryKey(s: string): string {
  return s.trim().toLowerCase().replace(/\s+/g, " ");
}

/** Pour chercher : sans accents. */
export function fold(s: string): string {
  return s.toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "").trim();
}

/** Un domaine par id ou par nom (sans accents) ; null si introuvable. */
export function resolveDomain(input: string | undefined, domains: { id: string; name: string }[]): string | null {
  if (!input) return null;
  const byId = domains.find((d) => d.id === input);
  if (byId) return byId.id;
  const f = fold(input);
  return domains.find((d) => fold(d.name) === f)?.id ?? domains.find((d) => fold(d.name).includes(f))?.id ?? null;
}

/** Le mot déjà sur la liste (hors panier), sinon null. */
export function existingItem(items: Record<string, GroceryItemDoc>, label: string): [string, GroceryItemDoc] | null {
  const k = groceryKey(label);
  for (const [id, x] of Object.entries(items)) {
    if (groceryKey(x.label) === k && x.inBasket !== true) return [id, x];
  }
  return null;
}

/** La ligne à écrire : domaine / projet / endroit donnés, sinon retenus pour ce mot. */
export function newGroceryItem(
  input: { label: string; qty?: string; domainId?: string | null; projectId?: string | null; store?: string | null },
  memory: Record<string, GroceryMemoryDoc>,
): GroceryItemDoc {
  const m = memory[groceryKey(input.label)] ?? {};
  const out: GroceryItemDoc = {
    label: input.label.trim(),
    store: input.store || m.store || MENU_STORE,
    source: "claude",
  };
  const qty = (input.qty ?? "").trim();
  if (qty) out.qty = qty;
  const domainId = input.domainId ?? m.domainId;
  if (domainId) out.domainId = domainId;
  const projectId = input.projectId ?? m.projectId;
  if (projectId) out.projectId = projectId;
  return out;
}

/** Candidats pour un libellé (exact, sinon fragment ; sans accents). */
export function findItems(items: Record<string, GroceryItemDoc>, needle: string): [string, GroceryItemDoc][] {
  const n = fold(needle);
  if (!n) return [];
  const all = Object.entries(items);
  const exact = all.filter(([, x]) => fold(x.label) === n);
  return exact.length ? exact : all.filter(([, x]) => fold(x.label).includes(n));
}

/** La liste en texte, par endroit, avec le domaine et le projet. */
export function groceriesText(
  items: Record<string, GroceryItemDoc>,
  domainName: (id: string) => string | undefined,
  projectTitle: (id: string) => string | undefined,
): string {
  const all = Object.values(items);
  if (!all.length) return "Liste de courses vide (les ingrédients du menu de la semaine s'y ajoutent dans l'app).";
  const toBuy = all.filter((x) => x.inBasket !== true);
  const basket = all.filter((x) => x.inBasket === true);
  const byStore = new Map<string, GroceryItemDoc[]>();
  for (const x of toBuy) {
    const s = x.store || MENU_STORE;
    if (!byStore.has(s)) byStore.set(s, []);
    byStore.get(s)!.push(x);
  }
  const line = (x: GroceryItemDoc, mark: string) => {
    const tags = [
      x.domainId ? domainName(x.domainId) : undefined,
      x.projectId ? projectTitle(x.projectId) : undefined,
    ].filter(Boolean);
    return `${mark} ${x.label}${x.qty ? ` ${x.qty}` : ""}${tags.length ? ` (${tags.join(" · ")})` : ""}`;
  };
  const parts = [`Liste de courses : ${toBuy.length} à prendre${basket.length ? `, ${basket.length} dans le panier` : ""}.`];
  for (const [store, list] of byStore) {
    parts.push(`\n${store.toUpperCase()}`);
    for (const x of list.sort((a, b) => a.label.localeCompare(b.label, "fr"))) parts.push(line(x, "☐"));
  }
  if (basket.length) {
    parts.push("\nDANS LE PANIER");
    for (const x of basket) parts.push(line(x, "☑"));
  }
  parts.push("\n(Les ingrédients du menu de la semaine s'ajoutent tout seuls dans l'app ; ils ne sont pas listés ici.)");
  return parts.join("\n");
}

// ── Ticket de caisse lu par Claude (record_receipt, 2026-11-02) ─────────────

export type ReceiptLineInput = {
  label: string;
  /** Prix payé pour la ligne, en euros (ex. 3.49). */
  price: number;
  domain?: string;
  projectId?: string;
  /** Article de la liste de courses que cette ligne couvre (libellé exact de la liste). */
  listLabel?: string;
};

export type ReceiptShare = { domainId: string | null; projectId: string | null; amount: number; labels: string[] };

export type ReceiptPlan = {
  total: number;
  shares: ReceiptShare[];
  /** Mot → prix (centimes), pour la mémoire. */
  prices: Record<string, { price: number; domainId?: string; projectId?: string }>;
  /** Lignes de la liste couvertes (ids des lignes à la main à retirer). */
  removeItemIds: string[];
  /** Clés d'ingrédients du menu à marquer achetés (libellé de la liste, minuscules). */
  menuKeys: string[];
  warnings: string[];
};

function apportionInt(total: number, weights: number[]): number[] {
  const sum = weights.reduce((a, b) => a + b, 0);
  if (!weights.length) return [];
  if (sum <= 0) return apportionInt(total, weights.map(() => 1));
  const raw = weights.map((w) => (total * w) / sum);
  const out = raw.map((r) => Math.floor(r));
  let left = total - out.reduce((a, b) => a + b, 0);
  const order = raw.map((r, i) => [r - out[i], i] as const).sort((a, b) => b[0] - a[0]).map(([, i]) => i);
  for (let k = 0; left > 0; k = (k + 1) % order.length, left--) out[order[k]]++;
  return out;
}

/**
 * Le ticket réparti par (domaine, projet) : chaque ligne garde son prix ; si
 * le total du ticket diffère de la somme des lignes (remise, arrondi), l'écart
 * est réparti au prorata. Domaine d'une ligne : celui donné, sinon celui
 * retenu pour l'article de la liste ou pour le mot, sinon aucun.
 */
export function planReceipt(
  lines: ReceiptLineInput[],
  totalEuros: number | undefined,
  ctx: {
    domains: { id: string; name: string }[];
    memory: Record<string, GroceryMemoryDoc>;
    items: Record<string, GroceryItemDoc>;
  },
): ReceiptPlan {
  const warnings: string[] = [];
  const cents = lines.map((l) => Math.max(0, Math.round((Number(l.price) || 0) * 100)));
  const sumLines = cents.reduce((a, b) => a + b, 0);
  const total = totalEuros != null && totalEuros > 0 ? Math.round(totalEuros * 100) : sumLines;
  if (total !== sumLines) {
    warnings.push(`Total du ticket ${(total / 100).toFixed(2)} € ≠ somme des lignes ${(sumLines / 100).toFixed(2)} € : l'écart est réparti au prorata.`);
  }
  const paid = total === sumLines ? cents : apportionInt(total, cents);
  const removeItemIds: string[] = [];
  const menuKeys: string[] = [];
  const groups = new Map<string, ReceiptShare>();
  const prices: ReceiptPlan["prices"] = {};
  lines.forEach((l, i) => {
    const listMatch = l.listLabel ? findItems(ctx.items, l.listLabel).find(([, x]) => fold(x.label) === fold(l.listLabel!)) : undefined;
    const memKey = groceryKey(l.listLabel || l.label);
    const mem = ctx.memory[memKey] ?? ctx.memory[groceryKey(l.label)] ?? {};
    let domainId = l.domain ? resolveDomain(l.domain, ctx.domains) : null;
    if (l.domain && !domainId) warnings.push(`Domaine introuvable pour « ${l.label} » : « ${l.domain} ».`);
    domainId = domainId ?? listMatch?.[1].domainId ?? mem.domainId ?? null;
    const projectId = l.projectId ?? listMatch?.[1].projectId ?? mem.projectId ?? null;
    if (listMatch) removeItemIds.push(listMatch[0]);
    else if (l.listLabel) menuKeys.push(l.listLabel.trim().toLowerCase());
    const k = `${domainId ?? ""}|${projectId ?? ""}`;
    const g = groups.get(k) ?? { domainId, projectId, amount: 0, labels: [] };
    g.amount += paid[i];
    g.labels.push(l.listLabel || l.label);
    groups.set(k, g);
    prices[memKey] = { price: paid[i], ...(domainId ? { domainId } : {}), ...(projectId ? { projectId } : {}) };
  });
  const shares = [...groups.values()].sort((a, b) => b.amount - a.amount);
  if (shares.some((s) => s.domainId == null)) warnings.push("Des lignes n'ont pas de domaine de vie : elles iront dans « Sans domaine ».");
  return { total, shares, prices, removeItemIds: [...new Set(removeItemIds)], menuKeys: [...new Set(menuKeys)], warnings };
}

/** Le lundi (YYYY-MM-DD) de la semaine d'un jour. */
export function mondayOfYmd(ymd: string): string {
  const d = new Date(`${ymd}T12:00:00Z`);
  const wd = (d.getUTCDay() + 6) % 7;
  d.setUTCDate(d.getUTCDate() - wd);
  return d.toISOString().slice(0, 10);
}
