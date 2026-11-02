import { test } from "node:test";
import assert from "node:assert/strict";
import { existingItem, findItems, groceriesText, groceryKey, newGroceryItem, resolveDomain } from "../lib/groceries.js";

test("domaine par nom ou id, sans accents", () => {
  const ds = [{ id: "s", name: "Santé" }, { id: "i", name: "Intendance" }];
  assert.equal(resolveDomain("sante", ds), "s");
  assert.equal(resolveDomain("i", ds), "i");
  assert.equal(resolveDomain("Inten", ds), "i");
  assert.equal(resolveDomain("Finances", ds), null);
});

test("une ligne via Claude reprend ce qui est retenu pour le mot", () => {
  const x = newGroceryItem({ label: " Lessive ", domainId: null }, { lessive: { domainId: "i", store: "Bricolage" } });
  assert.equal(x.label, "Lessive");
  assert.equal(x.domainId, "i");
  assert.equal(x.store, "Bricolage");
  assert.equal(x.source, "claude");
  assert.equal(groceryKey("  Sacs   poubelle "), "sacs poubelle");
});

test("doublon, recherche et texte par endroit", () => {
  const items = {
    a: { label: "Lessive", store: "Supermarché", domainId: "i" },
    b: { label: "Pâtes", inBasket: true },
    c: { label: "Ampoules", store: "Bricolage", projectId: "p" },
  };
  assert.equal(existingItem(items, "lessive")[0], "a");
  assert.equal(existingItem(items, "pâtes"), null);
  assert.equal(findItems(items, "pates")[0][0], "b");
  const t = groceriesText(items, (id) => (id === "i" ? "Intendance" : undefined), (id) => (id === "p" ? "Dressing" : undefined));
  assert.match(t, /2 à prendre, 1 dans le panier/);
  assert.match(t, /BRICOLAGE\n☐ Ampoules \(Dressing\)/);
  assert.match(t, /☐ Lessive \(Intendance\)/);
});
