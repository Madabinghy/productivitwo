import { test } from "node:test";
import assert from "node:assert/strict";
import { guessFamilies, parseFamilies, familiesFor, familiesText, PRO, FEC, FIB, ACC } from "../lib/meal_families.js";

test("guessFamilies : mêmes réponses que l'app (meal_families_test.dart)", () => {
  const cases = {
    "Côte de porc": [PRO],
    "Lardons fumés": [PRO],
    "Œufs bio x6": [PRO],
    "Pâtes farfalle 500g": [FEC],
    "Riz basmati": [FEC],
    "Pommes de terre 1,35 kg": [FEC],
    "Banane plantain": [FEC],
    "Fruit à pain": [FEC],
    "Haricots verts": [FIB],
    "Champignons de Paris émincés": [FIB],
    "Pommes Golden": [FIB],
    "Banane": [FIB],
    "Lentilles corail": [FEC, PRO],
    "Haricots rouges": [FEC, PRO],
    "Sauce bolognaise 420G": [ACC],
    "Concentré de tomate tube": [ACC],
    "Ail violet": [ACC],
    "Oignon jaune": [ACC],
    "Moutarde bocal": [ACC],
    "Lait de coco": [ACC],
    "Tartelettes fraise": [ACC],
  };
  for (const [label, fams] of Object.entries(cases)) assert.deepEqual(guessFamilies(label), fams, label);
  assert.deepEqual(guessFamilies("Truc inconnu"), []);
});

test("parseFamilies : alias, accompagnement exclusif", () => {
  assert.deepEqual(parseFamilies("feculents,proteines"), [FEC, PRO]);
  assert.deepEqual(parseFamilies("Protéines"), [PRO]);
  assert.deepEqual(parseFamilies("légumes"), [FIB]);
  assert.deepEqual(parseFamilies("accompagnement,proteines"), [PRO]);
  assert.deepEqual(parseFamilies("bidon"), []);
  assert.deepEqual(parseFamilies(""), []);
});

test("familiesFor : retenue, devinée, hors alimentaire, accompagnement", () => {
  const families = { "tofu fumé": "proteines" };
  const pantry = { "gel wc": { label: "Gel WC", aisle: "Ménager", state: "have" } };
  assert.deepEqual(familiesFor("Tofu fumé", families, {}, pantry), [PRO]);
  assert.deepEqual(familiesFor("Gel WC", families, {}, pantry), []);
  assert.deepEqual(familiesFor("Eau de source", families, {}, pantry), []);
  assert.deepEqual(familiesFor("Truc inconnu", families, {}, pantry), [ACC]);
});

test("familiesText : ce qu'on a, par famille", () => {
  const pantry = {
    lardons: { label: "Lardons", aisle: "Frais", state: "have" },
    riz: { label: "Riz", aisle: "Épicerie", state: "low" },
    "pâtes": { label: "Pâtes", aisle: "Épicerie", state: "out" },
    ail: { label: "Ail", aisle: "Épicerie", state: "have" },
  };
  const t = familiesText(pantry, {}, {});
  assert.match(t, /Protéines : Lardons/);
  assert.match(t, /Féculents : Riz \(bientôt fini\)/);
  assert.match(t, /Fibres : —/);
  assert.match(t, /Accompagnements : Ail/);
});
