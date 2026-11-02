import { test } from "node:test";
import assert from "node:assert/strict";
import { planReceipt, mondayOfYmd } from "../lib/groceries.js";

const ctx = {
  domains: [{ id: "s", name: "Santé" }, { id: "i", name: "Intendance" }],
  memory: { lessive: { domainId: "i" } },
  items: { x1: { label: "Lessive", domainId: "i" }, x2: { label: "Ampoules", domainId: "i", projectId: "dressing" } },
};

test("un ticket réparti par domaine avec les vrais prix", () => {
  const p = planReceipt(
    [
      { label: "PATES BARILLA 500G", price: 1.49, domain: "Santé", listLabel: "Pâtes" },
      { label: "BOEUF HACHE", price: 5.2, domain: "sante" },
      { label: "LESSIVE X 30", price: 8.9, listLabel: "Lessive" },
      { label: "AMPOULE E27", price: 4.5, listLabel: "Ampoules" },
    ],
    20.09,
    ctx,
  );
  assert.equal(p.total, 2009);
  assert.deepEqual(p.shares.map((s) => [s.domainId, s.projectId, s.amount]), [["i", null, 890], ["s", null, 669], ["i", "dressing", 450]]);
  assert.deepEqual(p.removeItemIds.sort(), ["x1", "x2"]);
  assert.deepEqual(p.menuKeys, ["pâtes"]);
  assert.equal(p.prices["pâtes"].price, 149);
  assert.equal(p.warnings.length, 0);
});

test("remise : l'écart est réparti, la somme tombe juste", () => {
  const p = planReceipt([{ label: "a", price: 10, domain: "s" }, { label: "b", price: 10, domain: "i" }], 18, ctx);
  assert.equal(p.shares.reduce((a, s) => a + s.amount, 0), 1800);
  assert.match(p.warnings[0], /écart est réparti/);
});

test("lignes sans domaine, lundi de la semaine", () => {
  const p = planReceipt([{ label: "truc", price: 2 }], undefined, ctx);
  assert.equal(p.shares[0].domainId, null);
  assert.match(p.warnings.join(" "), /Sans domaine/);
  assert.equal(mondayOfYmd("2026-11-02"), "2026-11-02");
  assert.equal(mondayOfYmd("2026-11-08"), "2026-11-02");
});
