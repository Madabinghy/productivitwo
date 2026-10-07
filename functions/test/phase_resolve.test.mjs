import test from "node:test";
import assert from "node:assert/strict";
import { resolvePhaseIds } from "../lib/phase_resolve.js";

const phases = [
  { id: "p1", label: "Préparation" },
  { id: "p2", label: "Séances — période 1" },
];

test("phaseId valide inchangé ; groupLabel = libellé → phaseId", () => {
  const r = resolvePhaseIds(phases, [
    { title: "a", phaseId: "p2" },
    { title: "b", groupLabel: "preparation" },
    { title: "c", groupLabel: "Séances – période 1" },
  ]);
  assert.equal(r.tasks[0].phaseId, "p2");
  assert.equal(r.tasks[1].phaseId, "p1");
  assert.equal(r.tasks[1].groupLabel, "preparation");
  assert.equal(r.tasks[2].phaseId, "p2");
  assert.equal(r.resolved, 2);
  assert.deepEqual(r.unknown, []);
});

test("phaseId portant un libellé → résolu ; inconnu → signalé, laissé tel quel", () => {
  const r = resolvePhaseIds(phases, [
    { title: "a", phaseId: "Préparation" },
    { title: "b", phaseId: "zzz" },
  ]);
  assert.equal(r.tasks[0].phaseId, "p1");
  assert.equal(r.tasks[1].phaseId, "zzz");
  assert.deepEqual(r.unknown, ["zzz"]);
});

test("projet mono-phase : tâche sans indication → la phase unique ; multi-phase → rien", () => {
  const one = resolvePhaseIds([phases[0]], [{ title: "a" }, { title: "b", groupLabel: "autre" }]);
  assert.equal(one.tasks[0].phaseId, "p1");
  assert.equal(one.tasks[1].phaseId, undefined);
  const multi = resolvePhaseIds(phases, [{ title: "a" }]);
  assert.equal(multi.tasks[0].phaseId, undefined);
  assert.equal(multi.resolved, 0);
});

test("sans phase : rien ne change", () => {
  const r = resolvePhaseIds([], [{ title: "a", groupLabel: "x" }]);
  assert.equal(r.tasks[0].phaseId, undefined);
  assert.equal(r.resolved, 0);
});
