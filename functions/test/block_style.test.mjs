import test from "node:test";
import assert from "node:assert/strict";
import { analyzeBlocks, blockAdvice } from "../lib/block_style.js";

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
