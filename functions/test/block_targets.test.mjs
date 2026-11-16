import test from "node:test";
import assert from "node:assert/strict";
import { normalizeExtraTargets, extraTargetLinks, MAX_BLOCK_TARGETS } from "../lib/block_targets.js";

test("sans projet principal, pas de cible suivante", () => {
  assert.deepEqual(normalizeExtraTargets([{ projectId: "p2" }], {}), []);
  assert.deepEqual(normalizeExtraTargets(undefined, { projectId: "p1" }), []);
});

test("cibles nettoyées, sans doublon de la principale ni entre elles", () => {
  const out = normalizeExtraTargets(
    [
      { projectId: "p1", taskId: "t1" },
      { projectId: "p1", taskId: "t2", actionId: "a2" },
      { projectId: "p1", taskId: "t2" },
      { projectId: "p2", actionId: "sans-tâche" },
      { taskId: "orphelin" },
      "n'importe quoi",
    ],
    { projectId: "p1", taskId: "t1" }
  );
  assert.deepEqual(out, [{ projectId: "p1", taskId: "t2", actionId: "a2" }, { projectId: "p2" }]);
});

test("jamais plus de MAX_BLOCK_TARGETS avec la principale", () => {
  const many = Array.from({ length: 12 }, (_, i) => ({ projectId: "p", taskId: `t${i}` }));
  assert.equal(normalizeExtraTargets(many, { projectId: "p", taskId: "principale" }).length, MAX_BLOCK_TARGETS - 1);
});

test("liens lisibles pour get_day_schedule", () => {
  assert.deepEqual(extraTargetLinks([{ projectId: "p2", taskId: "t9", actionId: "a1" }, { projectId: "p3" }]), [
    "aussi projet:p2 tâche:t9 action:a1",
    "aussi projet:p3",
  ]);
  assert.deepEqual(extraTargetLinks(undefined), []);
});
