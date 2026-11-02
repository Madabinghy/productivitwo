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
