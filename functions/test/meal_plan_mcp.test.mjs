import { test } from "node:test";
import assert from "node:assert/strict";
import { parseMoment, covered, composedTitle, toComponent, planMeals, mealOptionsText, toFinish } from "../lib/meal_plan_mcp.js";

const f = {
  families: { "galettes": "feculents" },
  memory: {},
  pantry: {
    lardons: { label: "Lardons", aisle: "Frais", state: "have", boughtAt: "2026-10-30" },
    riz: { label: "Riz", aisle: "Épicerie", state: "have" },
    champignons: { label: "Champignons", aisle: "Épicerie", state: "low" },
    ail: { label: "Ail", aisle: "Épicerie", state: "have" },
    "pâtes": { label: "Pâtes", aisle: "Épicerie", state: "out" },
  },
};

test("parseMoment : alias", () => {
  assert.equal(parseMoment("Petit-déj"), "petit-dej");
  assert.equal(parseMoment("matin"), "petit-dej");
  assert.equal(parseMoment("déjeuner"), "midi");
  assert.equal(parseMoment("Dîner"), "soir");
  assert.equal(parseMoment("goûter"), null);
});

test("toComponent / covered / composedTitle", () => {
  const cs = ["Haricots verts", { label: "Côte de porc" }, "Ail", { label: "Galettes" }].map((c) => toComponent(c, f));
  assert.deepEqual(cs[0], { label: "Haricots verts", families: ["fibres"] });
  assert.deepEqual(cs[3], { label: "Galettes", families: ["feculents"] });
  assert.deepEqual(covered(cs), ["proteines", "feculents", "fibres"]);
  assert.equal(composedTitle(cs), "Côte de porc · Galettes · Haricots verts");
  assert.deepEqual(toComponent({ label: "Tofu", family: "protéines" }, f), { label: "Tofu", families: ["proteines"] });
});

test("planMeals : valide dès 2 familles, refuse en dessous, garde ce qui a été mangé, vide", () => {
  const meals = { plans: { "2026-11-02": { "2026-11-04|soir": { title: "Chili", portions: 1, ate: "ok" } } } };
  const { writes, errors } = planMeals(
    [
      { date: "2026-11-04", moment: "soir", components: ["Lardons", "Riz", "Ail"] },
      { date: "2026-11-05", moment: "midi", components: ["Lardons", "Ail"] },
      { date: "2026-11-05", moment: "goûter", components: ["Pomme"] },
      { date: "2026-11-06", moment: "matin", clear: true },
    ],
    meals, f, "2026-11-04",
  );
  assert.equal(writes.length, 2);
  assert.equal(writes[0].monday, "2026-11-02");
  assert.equal(writes[0].key, "2026-11-04|soir");
  assert.equal(writes[0].value.title, "Lardons · Riz");
  assert.equal(writes[0].value.ate, "ok");
  assert.equal(writes[0].value.components.length, 3);
  assert.match(writes[0].text, /remplace « Chili »/);
  assert.equal(writes[1].key, "2026-11-06|petit-dej");
  assert.equal(writes[1].value, null);
  assert.equal(errors.length, 2);
  assert.match(errors[0], /il en faut 2 sur 3/);
});

test("mealOptionsText / toFinish : placard par famille, à finir, derniers repas", () => {
  assert.deepEqual(toFinish(f.pantry, "2026-11-04"), ["Champignons", "Lardons"]);
  const meals = { plans: { "2026-11-02": { "2026-11-04|midi": { title: "Lardons · Riz", components: [{ label: "Lardons", families: ["proteines"] }, { label: "Riz", families: ["feculents"] }] } } } };
  const t = mealOptionsText({ ymd: "2026-11-04", moment: "soir", meals, f });
  assert.match(t, /soir : rien de prévu/);
  assert.match(t, /Protéines : Lardons/);
  assert.match(t, /Féculents : Riz/);
  assert.match(t, /À FINIR : Champignons, Lardons/);
  assert.match(t, /pas la même protéine qu'au repas d'avant \(Lardons\)/);
});
