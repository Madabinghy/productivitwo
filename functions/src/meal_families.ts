// Repas en 3 familles (2026-11-04) — logique pure côté serveur, alignée sur
// `lib/utils/meal_families.dart` (**garder alignés** : mêmes mots-clés, même
// ordre, même règle — le mot-clé le plus long gagne, à égalité la première
// famille de la liste). Stockage `users/{uid}/data/meta.groceries.families`
// `{<mot>: "proteines" | "feculents,proteines" | …}`.

import { groceryKey } from "./groceries";
import { foldWords, aisleFor, type PantryDoc } from "./pantry";
import type { GroceryMemoryDoc } from "./groceries";

export const PRO = "proteines";
export const FEC = "feculents";
export const FIB = "fibres";
export const ACC = "accompagnement";
export const MEAL_FAMILIES = [PRO, FEC, FIB];
export const FAMILY_LABEL: Record<string, string> = { [PRO]: "Protéines", [FEC]: "Féculents", [FIB]: "Fibres", [ACC]: "Accompagnements" };
export const NON_FOOD_AISLES = new Set(["Ménager", "Hygiène", "Boissons"]);

export const FAMILY_KEYWORDS: [string[], string[]][] = [
  [[ACC], [
    "sauce", "concentre de tomate", "coulis", "moutarde", "ketchup", "mayonnaise", "vinaigrette", "pesto", "epice", "curry",
    "colombo", "paprika", "sel", "poivre", "huile", "vinaigre", "bouillon", "ail", "oignon", "echalote", "cive", "persil",
    "basilic", "coriandre", "menthe", "thym", "laurier", "gingembre", "piment", "herbe", "beurre", "creme", "creme fraiche",
    "lait de coco", "sucre", "farine", "levure", "confiture", "miel", "pate a tartiner", "cornichon", "olive", "capre", "chocolat",
    "cacao", "cafe", "the", "gateau", "tartelette", "biscuit", "madeleine", "bonbon", "chips", "glace", "dessert",
  ]],
  [[FEC, PRO], [
    "lentille", "pois chiche", "haricot rouge", "haricot blanc", "pois rouge", "pois d angole", "feve", "flageolet",
  ]],
  [[FEC], [
    "pomme de terre", "patate", "patate douce", "igname", "dachine", "madere", "manioc", "banane plantain", "plantain",
    "fruit a pain", "riz", "pate", "pates", "spaghetti", "tagliatelle", "farfalle", "penne", "coquillette",
    "fusilli", "macaroni", "lasagne", "nouille", "vermicelle", "gnocchi", "semoule", "couscous", "quinoa", "boulgour", "ble",
    "polenta", "pain", "baguette", "biscotte", "brioche", "tortilla", "wrap", "galette", "cracker", "cereale", "flocon",
    "avoine", "muesli", "frites", "puree", "farine de manioc", "cassave", "dombre",
  ]],
  [[PRO], [
    "oeuf", "jambon", "lardon", "bacon", "poulet", "blanc de poulet", "dinde", "canard", "boeuf", "veau", "agneau", "gigot",
    "porc", "cote", "cote de porc", "ribs", "travers", "roti", "filet", "cuisse", "aiguillette", "escalope", "steak", "viande",
    "hache", "saucisse", "merguez", "chorizo", "boudin", "nugget", "cordon bleu", "poisson", "saumon", "thon", "sardine",
    "maquereau", "cabillaud", "morue", "colin", "merlu", "crevette", "calamar", "escargot", "lambi", "chatrou", "ouassou",
    "tofu", "tempeh", "seitan", "fromage", "emmental", "mozzarella", "feta", "chevre", "comte", "gruyere", "parmesan", "ricotta",
    "yaourt", "yogourt", "skyr", "fromage blanc", "lait",
  ]],
  [[FIB], [
    "legume", "haricot vert", "petit pois", "salade", "mache", "roquette", "carotte", "tomate", "courgette", "poivron",
    "champignon", "brocoli", "chou", "chou fleur", "epinard", "concombre", "aubergine", "poireau", "radis", "navet",
    "betterave", "christophine", "giraumon", "potiron", "citrouille", "gombo", "avocat", "crudite", "ratatouille", "soupe",
    "fruit", "banane", "pomme", "poire", "orange", "citron", "clementine", "mandarine", "kiwi", "fraise", "framboise",
    "myrtille", "cerise", "raisin", "melon", "pasteque", "ananas", "mangue", "papaye", "goyave", "peche", "abricot", "prune",
    "compote",
  ]],
];

const sameWord = (t: string, kw: string) => t === kw || t === `${kw}s` || t === `${kw}x`;
function hasPhrase(tokens: string[], kw: string[]): boolean {
  for (let i = 0; i + kw.length <= tokens.length; i++) {
    if (kw.every((w, j) => sameWord(tokens[i + j], w))) return true;
  }
  return false;
}

/** Les familles devinées par les mots ; [] si rien ne le reconnaît. */
export function guessFamilies(label: string): string[] {
  const tokens = foldWords(label).split(" ").filter(Boolean);
  if (!tokens.length) return [];
  let best: string[] = [];
  let bestLen = 0;
  for (const [fams, words] of FAMILY_KEYWORDS) {
    for (const w of words) {
      const kw = w.split(" ");
      if (kw.length > bestLen && hasPhrase(tokens, kw)) {
        best = fams;
        bestLen = kw.length;
      }
    }
  }
  return best;
}

/** `"feculents,proteines"` / liste / noms en clair → familles propres ; accompagnement exclusif. */
export function parseFamilies(raw: unknown): string[] {
  const parts = Array.isArray(raw) ? raw.map(String) : String(raw ?? "").split(",");
  const alias: Record<string, string> = {
    proteine: PRO, proteines: PRO, feculent: FEC, feculents: FEC, fibre: FIB, fibres: FIB, legumes: FIB, legume: FIB,
    accompagnement: ACC, accompagnements: ACC, condiment: ACC, aucune: ACC,
  };
  const out: string[] = [];
  for (const p of parts) {
    const f = alias[foldWords(p).replace(/ /g, "")];
    if (f && !out.includes(f)) out.push(f);
  }
  if (out.includes(ACC) && out.length > 1) out.splice(out.indexOf(ACC), 1);
  return out;
}

/** Les familles d'un produit : retenues pour le mot, sinon devinées ; hors alimentaire = [] ; inconnu = accompagnement. */
export function familiesFor(
  label: string,
  families: Record<string, string>,
  memory: Record<string, GroceryMemoryDoc>,
  pantry: Record<string, PantryDoc>,
  aisle?: string,
): string[] {
  const k = groceryKey(label);
  const set = parseFamilies(families[k]);
  if (set.length) return set;
  const a = aisle ?? pantry[k]?.aisle ?? aisleFor(label, memory, pantry);
  if (NON_FOOD_AISLES.has(a)) return [];
  const g = guessFamilies(label);
  return g.length ? g : [ACC];
}

/** Ce qu'on a (j'en ai · bientôt fini) par famille, en texte. */
export function familiesText(
  pantry: Record<string, PantryDoc>,
  families: Record<string, string>,
  memory: Record<string, GroceryMemoryDoc>,
): string {
  const by: Record<string, string[]> = { [PRO]: [], [FEC]: [], [FIB]: [], [ACC]: [] };
  for (const p of Object.values(pantry)) {
    if (p.state === "out") continue;
    for (const f of familiesFor(p.label, families, memory, pantry, p.aisle)) by[f]?.push(p.state === "low" ? `${p.label} (bientôt fini)` : p.label);
  }
  const lines = [PRO, FEC, FIB, ACC].map((f) => `${FAMILY_LABEL[f]} : ${by[f].length ? by[f].sort((a, b) => a.localeCompare(b, "fr")).join(", ") : "—"}`);
  return ["PAR FAMILLE (repas : 2 familles sur 3 suffisent ; les accompagnements ne comptent pas)", ...lines].join("\n");
}
