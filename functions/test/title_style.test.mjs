import test from "node:test";
import assert from "node:assert/strict";
import { checkTitle, titleAdvice, WRITING_RULES } from "../lib/title_style.js";

test("titre court verbe + objet : rien à dire", () => {
  assert.deepEqual(checkTitle("Imprimer les supports", { kind: "action" }).warnings, []);
  assert.deepEqual(checkTitle("Corriger les contrôles", { kind: "action" }).warnings, []);
});

test("titre cahier des charges : long, parenthèses, codes", () => {
  const c = checkTitle(
    "CM1.2 : fiche 1.B.1 « Additionner et soustraire des nombres entiers » recto verso (2 pages max, sans cubes), niveau adapté CM1 / CM2",
    { kind: "action" });
  assert.ok(c.warnings.some((w) => w.startsWith("titre long")));
  assert.ok(c.warnings.some((w) => w.includes("parenthèses")));
  assert.ok(c.warnings.some((w) => w.includes("codes")));
  const d = checkTitle("Corriger le contrôle additions (coef. 2, sans ligue) et le DM", { kind: "action" });
  assert.ok(d.warnings.some((w) => w.includes("codes")));
});

test("emoji de rôle en double sur une tâche de séance → suggestion sans emoji", () => {
  const c = checkTitle("📝 Préparer — Séance du 12 oct : contrôle additions", { kind: "task", interventionRole: "prep" });
  assert.ok(c.warnings.some((w) => w.includes("emoji de rôle")));
  assert.equal(c.suggested, "Préparer — Séance du 12 oct : contrôle additions");
  assert.equal(checkTitle("📝 Préparer la séance", { kind: "task" }).suggested, undefined);
});

test("titleAdvice : vide quand tout est propre, 4 lignes max sinon", () => {
  assert.equal(titleAdvice([{ title: "Imprimer", kind: "action" }]), "");
  const bad = Array.from({ length: 6 }, (_, i) => ({ title: `Faire la chose numéro ${i} (coef. 2, recto verso ×19, voir p. 87 et ex. 3)`, kind: "action" }));
  const txt = titleAdvice(bad);
  assert.ok(txt.includes("Titres à alléger"));
  assert.equal(txt.split("\n").filter((l) => l.startsWith("•")).length, 4);
  assert.ok(WRITING_RULES.includes("verbe + objet"));
});
