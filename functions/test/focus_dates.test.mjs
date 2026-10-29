import test from "node:test";
import assert from "node:assert/strict";
import { migrateTaskFocusDates, migrateOwnFocusDates, focusedActions, isInterventionTask } from "../lib/focus_dates.js";
import { applyActionPatch } from "../lib/action_patch.js";

test("migrateTaskFocusDates : dueDate → focusDate hors tâches de séance, faites et déjà visées intactes", () => {
  const tasks = [
    { title: "Corriger", status: "pending", actions: [
      { title: "copies", dueDate: "2026-10-27" },
      { title: "faite", dueDate: "2026-10-20", done: true },
      { title: "déjà visée", dueDate: "2026-10-28", focusDate: "2026-10-29" },
      { title: "sans date" },
    ] },
    { title: "📝 Préparer — Séance du 5 nov", status: "pending", actions: [{ title: "relire", dueDate: "2026-11-04" }] },
    { title: "Clôturer", interventionId: "i1", status: "pending", actions: [{ title: "fiche", dueDate: "2026-11-07" }] },
  ];
  const m = migrateTaskFocusDates(tasks, "5e");
  assert.equal(m.moved, 1);
  assert.equal(m.skippedIntervention, 2);
  assert.equal(m.alreadyFocused, 1);
  assert.deepEqual(m.tasks[0].actions[0], { title: "copies", focusDate: "2026-10-27", dueDate: null });
  assert.equal(m.tasks[0].actions[1].dueDate, "2026-10-20");
  assert.equal(m.tasks[1].actions[0].dueDate, "2026-11-04");
  assert.equal(m.lines.length, 1);
  assert.equal(isInterventionTask({ title: "🎯 Jeu", isMilestone: true }), true);
  assert.equal(isInterventionTask({ title: "Corriger" }), false);
});

test("migrateOwnFocusDates + focusedActions", () => {
  const m = migrateOwnFocusDates([{ title: "Ranger", dueDate: "2026-10-30" }, { title: "ok" }], "Maison");
  assert.equal(m.moved, 1);
  assert.equal(m.own[0].focusDate, "2026-10-30");
  const lines = focusedActions([
    { title: "P", status: "active", tasks: [{ title: "T", status: "pending", actions: [
      { title: "a", focusDate: "2026-10-30", estimatedMin: 20 },
      { title: "b", focusDate: "2026-10-28" },
      { title: "c", focusDate: "2026-11-02" },
      { title: "d", focusDate: "2026-10-30", done: true },
    ] }] },
    { title: "Pause", status: "active", paused: true, tasks: [{ title: "T", actions: [{ title: "e", focusDate: "2026-10-30" }] }] },
  ], "2026-10-30");
  assert.equal(lines.length, 2);
  assert.match(lines[0], /"a" — P › T \(aujourd'hui · ≈ 20 min\)/);
  assert.match(lines[1], /à re-viser/);
});

test("applyActionPatch : focusDate posé, retiré, invalide", () => {
  const base = { id: "a", title: "x", done: false };
  const r = applyActionPatch(base, { focusDate: "2026-10-30" }, new Date("2026-10-29T10:00:00Z"));
  assert.equal(r.action.focusDate, "2026-10-30");
  assert.match(r.changes.join(" "), /jour visé — → 2026-10-30/);
  const r2 = applyActionPatch(r.action, { focusDate: "" }, new Date());
  assert.equal(r2.action.focusDate, null);
  const r3 = applyActionPatch(r.action, { focusDate: "demain" }, new Date());
  assert.equal(r3.action.focusDate, "2026-10-30");
  assert.match(r3.changes.join(" "), /ignoré/);
});
