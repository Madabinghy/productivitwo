import { test } from "node:test";
import assert from "node:assert/strict";
import { coachModuleView, planCoachProposal } from "../lib/modules_coach.js";

test("absent = tout allumé, Liberté jamais montrée", () => {
  const v = coachModuleView(undefined);
  assert.ok(v.on.includes("sleep"));
  assert.ok(!v.on.includes("freedom"));
  assert.deepEqual(v.offered, []);
});

test("liste explicite", () => {
  const v = coachModuleView({ on: ["sleep", "freedom"], pending: "freedom" });
  assert.deepEqual(v.on, ["sleep"]);
  assert.ok(v.offered.includes("planning"));
  assert.equal(v.pending, null);
});

test("proposer : refus du privé, du déjà allumé, de l'inconnu", () => {
  assert.ok("error" in planCoachProposal({ on: [] }, "freedom", "Marie", "2026-11-16"));
  assert.ok("error" in planCoachProposal({ on: ["sleep"] }, "sleep", "Marie", "2026-11-16"));
  assert.ok("error" in planCoachProposal({ on: [] }, "xyz", "Marie", "2026-11-16"));
  const ok = planCoachProposal({ on: [] }, "sleep", "Marie", "2026-11-16");
  assert.deepEqual(ok, { patch: { pending: "sleep", pendingBy: "coach", pendingCoach: "Marie", lastProposed: "2026-11-16" } });
});
