import { test } from "node:test";
import assert from "node:assert/strict";
import { guessAisle, aisleFor, addAisle, renameAisle, removeAisle, resolveAisle, parseState, pantryText, DEFAULT_AISLES, OTHER_AISLE } from "../lib/pantry.js";
import { planReceipt } from "../lib/groceries.js";

test("guessAisle : mêmes réponses que l'app (pantry_test.dart)", () => {
  const cases = {
    "Pâtes farfalle 500g": "Épicerie",
    "Sauce tomate": "Épicerie",
    "Tomates cerises": "Fruits et légumes",
    "Jus d'orange": "Boissons",
    "Gâteau au chocolat": "Épicerie",
    "Œufs bio x6": "Frais",
    "Crème hydratante": "Hygiène",
    "Crème fraîche": "Frais",
    "Liquide vaisselle": "Ménager",
    "Petits pois": "Fruits et légumes",
    "Lait de coco": "Épicerie",
    "Vinaigre balsamique": "Épicerie",
  };
  for (const [label, aisle] of Object.entries(cases)) assert.equal(guessAisle(label), aisle, label);
  assert.equal(guessAisle("Truc inconnu"), null);
});

test("aisleFor : mot retenu, placard, deviné, Autre", () => {
  const memory = { "pâtes": { aisle: "Vrac" } };
  const pantry = { "tofu fumé": { label: "Tofu fumé", aisle: "Bio", state: "have" } };
  assert.equal(aisleFor("Pâtes", memory, pantry), "Vrac");
  assert.equal(aisleFor("tofu fumé", memory, pantry), "Bio");
  assert.equal(aisleFor("Riz", memory, pantry), "Épicerie");
  assert.equal(aisleFor("Truc", memory, pantry), OTHER_AISLE);
});

test("rayons : ajouter avant Autre, renommer partout, fusionner, retirer", () => {
  const added = addAisle(DEFAULT_AISLES, "Bébé");
  assert.deepEqual(added.slice(-2), ["Bébé", "Autre"]);
  assert.equal(addAisle(added, "bebe"), added);
  assert.equal(resolveAisle("epicerie", added), "Épicerie");
  const st = {
    aisles: added,
    pantry: { riz: { label: "Riz", aisle: "Épicerie", state: "have" } },
    items: { a: { label: "Pâtes", aisle: "Épicerie" } },
    memory: { "pâtes": { aisle: "Épicerie", price: 120 } },
  };
  const r = renameAisle(st, "Épicerie", "Épicerie salée");
  assert.equal(r.aisles[0], "Épicerie salée");
  assert.equal(r.pantry.riz.aisle, "Épicerie salée");
  assert.equal(r.items.a.aisle, "Épicerie salée");
  assert.equal(r.memory["pâtes"].price, 120);
  const merged = renameAisle(r, "Épicerie salée", "Frais");
  assert.ok(!merged.aisles.includes("Épicerie salée"));
  assert.equal(merged.pantry.riz.aisle, "Frais");
  const removed = removeAisle(r, "Épicerie salée");
  assert.equal(removed.pantry.riz.aisle, OTHER_AISLE);
  assert.equal(removeAisle(r, OTHER_AISLE), r);
});

test("parseState et texte du placard", () => {
  assert.equal(parseState("plus rien"), "out");
  assert.equal(parseState("Bientôt fini"), "low");
  assert.equal(parseState("have"), "have");
  assert.equal(parseState("bof"), null);
  const t = pantryText({ riz: { label: "Riz", aisle: "Épicerie", state: "low", staple: true } }, DEFAULT_AISLES);
  assert.match(t, /ÉPICERIE/);
  assert.match(t, /! Riz — bientôt fini · habituel/);
});

test("ticket : rayon par ligne, montant par rayon, produits pour les placards", () => {
  const ctx = {
    domains: [{ id: "s", name: "Santé" }, { id: "i", name: "Intendance" }],
    memory: {},
    items: {},
    aisleOf: (label, given) => given ?? guessAisle(label) ?? OTHER_AISLE,
  };
  const p = planReceipt(
    [
      { label: "PATES FARFALLE 500G", name: "Pâtes", price: 1.5, domain: "Santé" },
      { label: "LAIT DEMI ECR", name: "Lait", price: 1.0, domain: "Santé" },
      { label: "LESSIVE X30", price: 8.0, domain: "Intendance", aisle: "Ménager" },
    ],
    undefined,
    ctx,
  );
  const sante = p.shares.find((s) => s.domainId === "s");
  assert.deepEqual(sante.byAisle, { "Épicerie": 150, "Frais": 100 });
  assert.deepEqual(sante.labels, ["Pâtes", "Lait"]);
  assert.equal(p.bought["pâtes"].aisle, "Épicerie");
  assert.equal(p.bought["lessive x30"].aisle, "Ménager");
  assert.equal(p.prices["lait"].aisle, "Frais");
});

test("ticket conservé : lignes avec prix payé, nom simple, domaine, rayon", () => {
  const p = planReceipt(
    [
      { label: "PATES FARFALLE 500G", name: "Pâtes", price: 1.5, domain: "Santé" },
      { label: "LESSIVE X30", price: 8.5, domain: "Intendance", aisle: "Ménager" },
    ],
    9.0,
    { domains: [{ id: "s", name: "Santé" }, { id: "i", name: "Intendance" }], memory: {}, items: {}, aisleOf: (l, g) => g ?? guessAisle(l) ?? OTHER_AISLE },
  );
  assert.equal(p.lines.length, 2);
  assert.deepEqual(p.lines[0], { label: "PATES FARFALLE 500G", name: "Pâtes", price: 135, domainId: "s", aisle: "Épicerie" });
  assert.equal(p.lines[1].name, undefined);
  assert.equal(p.lines.reduce((a, l) => a + l.price, 0), 900);
});

test("les viandes vont en Frais (mêmes réponses que l'app)", () => {
  for (const l of ["Ribs", "Travers de porc", "Côtes d'agneau", "Bacon", "Rôti de veau", "Cuisses de poulet", "Escargots"]) {
    assert.equal(guessAisle(l), "Frais", l);
  }
});
