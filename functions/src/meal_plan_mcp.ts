// Repas en 3 familles — lot 3 (2026-11-04) : composer des repas avec Claude.
// Logique pure côté serveur ; même stockage que l'app (`lib/utils/meal_plan.dart`) :
// `users/{uid}/data/meta.meals.plans.<lundi>.<ymd|moment>` =
// `{title, portions, components: [{label, families}], ate?, ateWhat?, noted?, recipeId?, out?}`.
// Créneaux : petit-dej · midi · soir. Un repas composé est valide dès 2 familles sur 3.

import { groceryKey, mondayOfYmd, type GroceryMemoryDoc } from "./groceries";
import { type PantryDoc } from "./pantry";
import { ACC, FAMILY_LABEL, MEAL_FAMILIES, PRO, familiesFor, parseFamilies } from "./meal_families";

export const MEAL_MOMENTS = ["petit-dej", "midi", "soir"];
export const MOMENT_LABEL: Record<string, string> = { "petit-dej": "petit-déj", midi: "midi", soir: "soir" };

export type MealComponentDoc = { label: string; families: string[] };
export type PlannedMealDoc = {
  title?: string;
  portions?: number;
  components?: MealComponentDoc[];
  recipeId?: string;
  out?: boolean;
  ate?: string;
  ateWhat?: string;
  noted?: boolean;
};
export type MealsDoc = { plans?: Record<string, Record<string, PlannedMealDoc>> };

/** « matin », « petit déj », « déjeuner »… → créneau ; null si inconnu. */
export function parseMoment(s: unknown): string | null {
  const f = String(s ?? "").toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "").replace(/[^a-z]/g, "");
  if (["petitdej", "petitdejeuner", "matin", "breakfast"].includes(f)) return "petit-dej";
  if (["midi", "dejeuner", "lunch"].includes(f)) return "midi";
  if (["soir", "diner", "dinner", "souper"].includes(f)) return "soir";
  return null;
}

/** Les familles couvertes (accompagnements exclus). */
export function covered(cs: MealComponentDoc[]): string[] {
  const s = new Set<string>();
  for (const c of cs) for (const f of c.families) if (MEAL_FAMILIES.includes(f)) s.add(f);
  return MEAL_FAMILIES.filter((f) => s.has(f));
}

/** Titre : protéines · féculents · fibres, comme l'app (`composedTitle`). */
export function composedTitle(cs: MealComponentDoc[]): string {
  const rank = (c: MealComponentDoc) => {
    const i = MEAL_FAMILIES.findIndex((f) => c.families.includes(f));
    return i < 0 ? 9 : i;
  };
  return cs.filter((c) => rank(c) < 9).sort((a, b) => rank(a) - rank(b)).map((c) => c.label).join(" · ");
}

export type Families = {
  families: Record<string, string>;
  memory: Record<string, GroceryMemoryDoc>;
  pantry: Record<string, PantryDoc>;
};

/** Une brique donnée par Claude : `"Riz"` ou `{label, family?}` → libellé + familles (données, sinon celles du mot). */
export function toComponent(raw: unknown, f: Families): MealComponentDoc | null {
  const label = (typeof raw === "string" ? raw : String((raw as { label?: unknown })?.label ?? "")).trim();
  if (!label) return null;
  const given = typeof raw === "object" && raw ? parseFamilies((raw as { family?: unknown }).family) : [];
  const fams = given.length ? given : familiesFor(label, f.families, f.memory, f.pantry);
  return { label, families: fams.length ? fams : [ACC] };
}

/** Les repas composés connus, du plus récent au plus ancien. */
export function composedHistory(meals: MealsDoc): { ymd: string; moment: string; title: string; components: MealComponentDoc[] }[] {
  const out: { ymd: string; moment: string; title: string; components: MealComponentDoc[] }[] = [];
  for (const week of Object.values(meals.plans ?? {})) {
    for (const [k, v] of Object.entries(week ?? {})) {
      if (!v?.components?.length) continue;
      const [ymd, moment] = k.split("|");
      if (ymd && moment) out.push({ ymd, moment, title: v.title ?? composedTitle(v.components), components: v.components });
    }
  }
  return out.sort((a, b) => b.ymd.localeCompare(a.ymd) || MEAL_MOMENTS.indexOf(b.moment) - MEAL_MOMENTS.indexOf(a.moment));
}

const daysBetween = (a: string, b: string) => Math.round((Date.parse(`${b}T12:00:00Z`) - Date.parse(`${a}T12:00:00Z`)) / 86400000);

/** Ce qui est « à finir » : bientôt fini, ou Frais / Fruits et légumes acheté il y a plus de 3 jours. */
export function toFinish(pantry: Record<string, PantryDoc>, ymd: string): string[] {
  return Object.values(pantry)
    .filter((p) => p.state !== "out")
    .filter((p) => p.state === "low" || ((p.aisle === "Frais" || p.aisle === "Fruits et légumes") && p.boughtAt && daysBetween(p.boughtAt, ymd) > 3))
    .map((p) => p.label)
    .sort((a, b) => a.localeCompare(b, "fr"));
}

/** Le texte de get_meal_options : le créneau, ce qu'on a par famille, à finir, les derniers repas. */
export function mealOptionsText(args: {
  ymd: string;
  moment: string | null;
  meals: MealsDoc;
  f: Families;
}): string {
  const { ymd, moment, meals, f } = args;
  const week = meals.plans?.[mondayOfYmd(ymd)] ?? {};
  const moments = moment ? [moment] : MEAL_MOMENTS;
  const lines: string[] = [`Repas du ${ymd} :`];
  for (const m of moments) {
    const p = week[`${ymd}|${m}`];
    lines.push(`• ${MOMENT_LABEL[m]} : ${p ? `${p.title ?? "?"}${p.components?.length ? ` (composé : ${covered(p.components).map((x) => FAMILY_LABEL[x]).join(" + ") || "—"})` : ""}${p.ate ? ` — mangé${p.ate === "ok" ? ", équilibré" : ""}` : ""}` : "rien de prévu"}`);
  }
  const by: Record<string, string[]> = { proteines: [], feculents: [], fibres: [], [ACC]: [] };
  for (const p of Object.values(f.pantry)) {
    if (p.state === "out") continue;
    for (const fam of familiesFor(p.label, f.families, f.memory, f.pantry, p.aisle)) by[fam]?.push(p.label);
  }
  lines.push("", "AU PLACARD, PAR FAMILLE");
  for (const fam of [...MEAL_FAMILIES, ACC]) {
    lines.push(`${FAMILY_LABEL[fam]} : ${by[fam].length ? by[fam].sort((a, b) => a.localeCompare(b, "fr")).join(", ") : "—"}`);
  }
  const finish = toFinish(f.pantry, ymd);
  if (finish.length) lines.push("", `À FINIR : ${finish.join(", ")}`);
  const hist = composedHistory(meals).filter((h) => h.ymd <= ymd).slice(0, 6);
  if (hist.length) {
    lines.push("", "DERNIERS REPAS COMPOSÉS");
    for (const h of hist) lines.push(`${h.ymd} ${MOMENT_LABEL[h.moment] ?? h.moment} : ${h.title}`);
  }
  const lastMain = composedHistory(meals).find((h) => h.moment !== "petit-dej" && (h.ymd < ymd || (h.ymd === ymd && moment && MEAL_MOMENTS.indexOf(h.moment) < MEAL_MOMENTS.indexOf(moment))));
  const lastProt = lastMain?.components.filter((c) => c.families.includes(PRO)).map((c) => c.label) ?? [];
  lines.push(
    "",
    "Règles : un repas = une brique par famille (protéines · féculents · fibres), 2 familles sur 3 suffisent ; les " +
      "accompagnements (ail, oignon, sauces…) ne comptent pas. Propose d'abord ce qu'il y a au placard, ce qui est à finir, " +
      (lastProt.length ? `pas la même protéine qu'au repas d'avant (${lastProt.join(", ")}), ` : "") +
      "puis montre ta proposition et appelle plan_meals (apply:false puis apply:true après accord).",
  );
  return lines.join("\n");
}

export type PlanMealInput = { date?: string; moment?: string; components?: unknown[]; clear?: boolean };

export type PlannedWrite = { monday: string; key: string; value: PlannedMealDoc | null; text: string };

/** Valide les repas demandés ; un repas composé qui couvre moins de 2 familles est refusé. */
export function planMeals(
  inputs: PlanMealInput[],
  meals: MealsDoc,
  f: Families,
  today: string,
): { writes: PlannedWrite[]; errors: string[] } {
  const writes: PlannedWrite[] = [];
  const errors: string[] = [];
  for (const x of inputs) {
    const ymd = String(x.date ?? today);
    if (!/^\d{4}-\d{2}-\d{2}$/.test(ymd)) {
      errors.push(`date invalide « ${x.date} » (YYYY-MM-DD).`);
      continue;
    }
    const moment = parseMoment(x.moment);
    if (!moment) {
      errors.push(`${ymd} : créneau inconnu « ${x.moment ?? ""} » (petit-dej · midi · soir).`);
      continue;
    }
    const monday = mondayOfYmd(ymd);
    const key = `${ymd}|${moment}`;
    const cur = meals.plans?.[monday]?.[key];
    if (x.clear === true) {
      writes.push({ monday, key, value: null, text: `🗑 ${ymd} ${MOMENT_LABEL[moment]} vidé${cur?.title ? ` (était : ${cur.title})` : ""}` });
      continue;
    }
    const seen = new Set<string>();
    const cs = (x.components ?? [])
      .map((c) => toComponent(c, f))
      .filter((c): c is MealComponentDoc => !!c && !seen.has(groceryKey(c.label)) && !!seen.add(groceryKey(c.label)));
    const cov = covered(cs);
    if (cov.length < 2) {
      errors.push(`${ymd} ${MOMENT_LABEL[moment]} : ${cs.map((c) => c.label).join(", ") || "rien"} ne couvre que ${cov.map((c) => FAMILY_LABEL[c]).join(" + ") || "aucune famille"} — il en faut 2 sur 3 (précise family si une brique est mal classée).`);
      continue;
    }
    const value: PlannedMealDoc = {
      title: composedTitle(cs),
      portions: 1,
      components: cs,
      ...(cur?.ate ? { ate: cur.ate } : {}),
      ...(cur?.ateWhat ? { ateWhat: cur.ateWhat } : {}),
    };
    const sides = cs.filter((c) => !c.families.some((fam) => MEAL_FAMILIES.includes(fam))).map((c) => c.label);
    writes.push({
      monday,
      key,
      value,
      text: `✓ ${ymd} ${MOMENT_LABEL[moment]} : ${value.title}${sides.length ? ` · avec ${sides.join(", ").toLowerCase()}` : ""} (${cov.map((c) => FAMILY_LABEL[c]).join(" + ")})${cur?.title && cur.title !== value.title ? ` — remplace « ${cur.title} »` : ""}`,
    });
  }
  return { writes, errors };
}
