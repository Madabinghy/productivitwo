import test from "node:test";
import assert from "node:assert/strict";
import { removeTask, freeTaskBlocks } from "../lib/task_delete.js";

test("removeTask : retire la tâche, signale une tâche principale de séance", () => {
  const tasks = [
    { id: "a", title: "A" },
    { id: "s", title: "🎯 Séance", interventionId: "i1", interventionRole: "session" },
    { id: "x", title: "Extra", interventionId: "i1", interventionRole: "extra" },
  ];
  const r = removeTask(tasks, "a");
  assert.deepEqual(r.remaining.map((t) => t.id), ["s", "x"]);
  assert.equal(r.removed.id, "a");
  assert.equal(r.interventionRole, null);
  assert.equal(removeTask(tasks, "s").interventionRole, "session");
  assert.equal(removeTask(tasks, "x").interventionRole, null);
  assert.equal(removeTask(tasks, "inconnue").removed, null);
});

test("freeTaskBlocks : libère les blocs à venir de la tâche, jamais le vécu", () => {
  const blocks = [
    { id: "passe", projectId: "p", taskId: "t", startTime: "08:00", status: "pending" },
    { id: "fait", projectId: "p", taskId: "t", startTime: "09:00", status: "done" },
    { id: "avenir", projectId: "p", taskId: "t", startTime: "15:00", status: "pending" },
    { id: "autre", projectId: "p", taskId: "u", startTime: "16:00", status: "pending" },
  ];
  const today = freeTaskBlocks(blocks, "p", "t", { isToday: true, nowMin: 12 * 60 });
  assert.deepEqual(today.freed.map((b) => b.id), ["avenir"]);
  assert.equal(today.blocks.find((b) => b.id === "avenir").status, "deleted");
  assert.equal(today.blocks.find((b) => b.id === "passe").status, "pending");
  const tomorrow = freeTaskBlocks(blocks, "p", "t", { isToday: false, nowMin: 12 * 60 });
  assert.deepEqual(tomorrow.freed.map((b) => b.id), ["passe", "avenir"]);
});
