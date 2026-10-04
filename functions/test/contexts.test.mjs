import test from "node:test";
import assert from "node:assert/strict";
import {
  normalizeContext, contextsOf, renameContextInActions, removeContextFromActions, countContextUsage,
  DEFAULT_GTD_CONTEXTS,
} from "../lib/contexts.js";

test("normalizeContext : préfixe @, espaces, vides", () => {
  assert.equal(normalizeContext("atelier"), "@atelier");
  assert.equal(normalizeContext("  @atelier  "), "@atelier");
  assert.equal(normalizeContext("en  déplacement"), "@en déplacement");
  assert.equal(normalizeContext("@"), null);
  assert.equal(normalizeContext("   "), null);
  assert.equal(normalizeContext(42), null);
  assert.equal(DEFAULT_GTD_CONTEXTS.length, 6);
});

test("contextsOf : union contexts + context legacy, sans doublon", () => {
  assert.deepEqual(contextsOf({ contexts: ["@maison", "@bureau"], context: "@maison" }), ["@maison", "@bureau"]);
  assert.deepEqual(contextsOf({ context: "@maison" }), ["@maison"]);
  assert.deepEqual(contextsOf({ contexts: ["@bureau"], context: "@maison" }), ["@bureau", "@maison"]);
  assert.deepEqual(contextsOf({}), []);
});

test("renameContextInActions : remplace, dédoublonne, garde context = contexts[0]", () => {
  const actions = [
    { id: "a", contexts: ["@atelier", "@maison"], context: "@atelier" },
    { id: "b", context: "@atelier" },
    { id: "c", contexts: ["@bureau"], context: "@bureau" },
    { id: "d", contexts: ["@atelier", "@garage"], context: "@atelier" },
  ];
  const r = renameContextInActions(actions, "@atelier", "@garage");
  assert.equal(r.changed, 3);
  assert.deepEqual(r.actions[0], { id: "a", contexts: ["@garage", "@maison"], context: "@garage" });
  assert.deepEqual(r.actions[1], { id: "b", contexts: ["@garage"], context: "@garage" });
  assert.equal(r.actions[2], actions[2]); // intacte (même référence)
  assert.deepEqual(r.actions[3], { id: "d", contexts: ["@garage"], context: "@garage" }); // fusion
});

test("removeContextFromActions : retire ; plus aucun contexte → context null", () => {
  const r = removeContextFromActions(
    [{ id: "a", contexts: ["@atelier"], context: "@atelier" }, { id: "b", contexts: ["@atelier", "@maison"], context: "@atelier" }],
    "@atelier",
  );
  assert.equal(r.changed, 2);
  assert.deepEqual(r.actions[0], { id: "a", contexts: [], context: null });
  assert.deepEqual(r.actions[1], { id: "b", contexts: ["@maison"], context: "@maison" });
});

test("countContextUsage : ouvertes / faites, cumul sur plusieurs lots", () => {
  const m = countContextUsage([{ contexts: ["@maison"], done: false }, { context: "@maison", done: true }]);
  countContextUsage([{ contexts: ["@maison", "@bureau"] }], m);
  assert.deepEqual(m.get("@maison"), { open: 2, done: 1 });
  assert.deepEqual(m.get("@bureau"), { open: 1, done: 0 });
});
