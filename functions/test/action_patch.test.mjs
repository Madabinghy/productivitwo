import test from "node:test";
import assert from "node:assert/strict";
import { applyActionPatch } from "../lib/action_patch.js";

const base = { id: "a", title: "Appeler le plombier", contexts: ["@téléphone"], context: "@téléphone", done: false, doneAt: null };
const NOW = "2026-10-04T10:00:00.000Z";

test("titre : trim, espaces, inchangé ignoré", () => {
  const r = applyActionPatch(base, { title: "  Appeler   le plombier " }, NOW);
  assert.deepEqual(r.changes, []);
  const r2 = applyActionPatch(base, { title: "Rappeler le plombier" }, NOW);
  assert.equal(r2.action.title, "Rappeler le plombier");
  assert.equal(r2.changes.length, 1);
});

test("contextes : remplacer, ajouter, retirer, @ normalisé, context = contexts[0]", () => {
  const r = applyActionPatch(base, { contexts: ["maison", "@bureau"] }, NOW);
  assert.deepEqual(r.action.contexts, ["@maison", "@bureau"]);
  assert.equal(r.action.context, "@maison");
  const r2 = applyActionPatch(base, { addContexts: ["@maison"], removeContexts: ["téléphone"] }, NOW);
  assert.deepEqual(r2.action.contexts, ["@maison"]);
  assert.equal(r2.action.context, "@maison");
  const r3 = applyActionPatch(base, { contexts: [] }, NOW);
  assert.deepEqual(r3.action.contexts, []);
  assert.equal(r3.action.context, null);
  const r4 = applyActionPatch(base, { addContexts: ["@téléphone"] }, NOW); // déjà là
  assert.deepEqual(r4.changes, []);
});

test("estimation : pose, efface, rejette le négatif", () => {
  assert.equal(applyActionPatch(base, { estimatedMin: 20.4 }, NOW).action.estimatedMin, 20);
  assert.equal(applyActionPatch({ ...base, estimatedMin: 30 }, { estimatedMin: null }, NOW).action.estimatedMin, null);
  const r = applyActionPatch(base, { estimatedMin: -5 }, NOW);
  assert.equal(r.action.estimatedMin, undefined);
  assert.match(r.changes[0], /ignorée/);
});

test("activité liée : lier, délier", () => {
  assert.equal(applyActionPatch(base, { linkedActivityId: "act1" }, NOW).action.linkedActivityId, "act1");
  assert.equal(applyActionPatch({ ...base, linkedActivityId: "act1" }, { linkedActivityId: "" }, NOW).action.linkedActivityId, null);
  assert.deepEqual(applyActionPatch(base, { linkedActivityId: null }, NOW).changes, []);
});

test("fait : doneAt posé, checklist cochée ; rouvrir garde les étapes", () => {
  const withSteps = { ...base, checklist: [{ id: "s1", title: "x", done: false, doneAt: null }, { id: "s2", title: "y", done: true, doneAt: "2026-10-01T00:00:00.000Z" }] };
  const r = applyActionPatch(withSteps, { done: true }, NOW);
  assert.equal(r.action.done, true);
  assert.equal(r.action.doneAt, NOW);
  assert.deepEqual(r.action.checklist.map((c) => c.done), [true, true]);
  assert.equal(r.action.checklist[1].doneAt, "2026-10-01T00:00:00.000Z");
  const r2 = applyActionPatch(r.action, { done: false }, NOW);
  assert.equal(r2.action.done, false);
  assert.equal(r2.action.doneAt, null);
  assert.deepEqual(r2.action.checklist.map((c) => c.done), [true, true]);
  assert.deepEqual(applyActionPatch(base, { done: false }, NOW).changes, []);
});
