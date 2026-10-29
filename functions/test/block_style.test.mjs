import test from "node:test";
import assert from "node:assert/strict";
import { analyzeBlocks, blockAdvice, activityLoad, activityLoadLabel } from "../lib/block_style.js";

const wb = (startTime, durationMin, taskId, title = "x") => ({ startTime, durationMin, title, category: "project", projectId: "p", taskId });

test("blocs courts : seulement les blocs de travail", () => {
  const a = analyzeBlocks([
    wb("09:00", 15, "t1"),
    { startTime: "09:30", durationMin: 10, title: "Pompes", category: "routine", activityId: "r" },
    { startTime: "10:00", durationMin: 5, title: "Prep", category: "project", projectId: "p", kind: "prep" },
    { startTime: "12:00", durationMin: 20, title: "RDV", category: "personal", gcalEventId: "g" },
    wb("14:00", 45, "t2"),
  ]);
  assert.equal(a.short.length, 1);
  assert.equal(a.short[0].startTime, "09:00");
});

test("blocs consécutifs d'une même tâche → fusionnables (écart ≤ 15 min)", () => {
  const a = analyzeBlocks([wb("09:00", 30, "t1"), wb("09:30", 30, "t1"), wb("10:10", 30, "t1"), wb("11:00", 30, "t2"), wb("13:00", 30, "t1")]);
  assert.equal(a.mergeable.length, 1);
  assert.equal(a.mergeable[0].blocks.length, 3);
  assert.equal(analyzeBlocks([wb("09:00", 30, "t1"), wb("11:00", 30, "t1")]).mergeable.length, 0);
});

test("blockAdvice : vide quand c'est propre, sinon lignes utiles", () => {
  assert.equal(blockAdvice([wb("09:00", 45, "t1"), wb("10:00", 60, "t2")]), "");
  const txt = blockAdvice([wb("09:00", 15, "t1", "Imprimer"), wb("09:15", 15, "t1", "Relire")]);
  assert.ok(txt.includes("Programme haché"));
  assert.ok(txt.includes("2 bloc(s) de travail < 30 min"));
  assert.ok(txt.includes("2 blocs consécutifs"));
});

test("activityLoad : projets liés (projet ou action), retards par échéance effective, en pause exclus", () => {
  const projects = [
    { status: "active", linkedActivityId: "ens", tasks: [
      { status: "pending", endDate: "2026-10-27", actions: [{ title: "a", done: false }, { title: "b", done: true }] },
      { status: "done", endDate: "2026-10-01", actions: [{ title: "c" }] },
    ] },
    { status: "active", tasks: [{ status: "pending", endDate: "2026-11-20", actions: [{ title: "d", linkedActivityId: "ens", dueDate: "2026-10-20" }, { title: "e", linkedActivityId: "sport" }] }] },
    { status: "active", linkedActivityId: "ens", paused: true, tasks: [{ status: "pending", actions: [{ title: "f" }] }] },
    { status: "active", linkedActivityId: "sport", tasks: [] },
  ];
  assert.deepEqual(activityLoad("ens", projects, "2026-10-29"), { projects: 2, overdue: 2 });
  assert.equal(activityLoadLabel({ projects: 2, overdue: 2 }), "2 projets liés · 2 actions en retard");
  assert.equal(activityLoadLabel({ projects: 1, overdue: 0 }), "1 projet lié");
  assert.equal(activityLoadLabel(activityLoad("rien", projects, "2026-10-29")), "");
});
